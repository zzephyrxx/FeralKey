// SPDX-License-Identifier: GPL-3.0-or-later
// RK report encoding adapted from rnayabed/rangoli. See THIRD_PARTY.md.
import Foundation

struct RGB: Codable, Equatable {
    var r: UInt8; var g: UInt8; var b: UInt8
    static let mint = RGB(r: 75, g: 232, b: 184)
}

struct LightSettings: Codable, Equatable {
    var mode: UInt8 = 17
    var speed: UInt8 = 3
    var brightness: UInt8 = 3
    var color = RGB.mint
    var rainbow = false
    var sleep: UInt8 = 1
}

struct PhysicalKey: Codable, Identifiable {
    let bIndex: Int
    let keyCode: String
    let top: [Double]
    let bottom: [Double]
    var id: Int { bIndex }
    var label: String {
        let names = ["Escape":"esc", "Back_Quote":"`", "Backspace":"⌫", "Tab":"tab", "Caps_Lock":"caps", "Enter":"return", "Left_Shift":"shift", "Right_Shift":"shift", "Left_Control":"ctrl", "Right_Control":"ctrl", "Left_Super":"⌘", "Right_Super":"⌘", "Left_Alt":"opt", "Right_Alt":"opt", "Space":"space", "Print_Screen":"prt", "Page_Up":"pg↑", "Page_Down":"pg↓", "Delete":"del", "Left":"←", "Right":"→", "Up":"↑", "Down":"↓", "Hyphen":"-", "Equals":"=", "Left_Bracket":"[", "Right_Bracket":"]", "Back_Slash":"\\", "Semi_Colon":";", "Quote":"'", "Comma":",", "Dot":".", "Slash":"/", "Num_Lock":"num", "Num_Divide":"/", "Num_Multiply":"*", "Num_Substract":"-", "Num_Add":"+", "Num_Enter":"enter", "Num_Decimal_Point":"."]
        let name = keyCode.replacingOccurrences(of: "Key_", with: "")
        if name == "Insert" { return "ins" }
        if name == "Num_Enter" { return "↵" }
        return names[name] ?? name.replacingOccurrences(of: "Num_", with: "")
    }
}

struct Layout: Codable {
    let name: String
    let keys: [PhysicalKey]
    func validate(codes: [String: UInt32]) throws {
        guard !keys.isEmpty, keys.count <= 139, Set(keys.map(\.id)).count == keys.count,
              keys.allSatisfy({ key in
                  key.id >= 0 && key.id < 139 && codes[key.keyCode] != nil &&
                  key.top.count == 2 && key.bottom.count == 2 &&
                  (key.top + key.bottom).allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 2000 } &&
                  key.bottom[0] > key.top[0] && key.bottom[1] > key.top[1]
              }) else { throw RKError.message("键盘布局资源无效，已禁用设备写入。") }
    }
}

struct HIDWritePlanner {
    private var lightHeader: [UInt8]?
    func packets(for reports: [[UInt8]]) throws -> [[UInt8]] {
        try RKCodec.validateTransaction(reports)
        // The complete RGB payload is already validated. Keep mode 14 alive
        // instead of reselecting it on every animation frame.
        if reports.count == 8 && lightHeader == reports[0] { return Array(reports.dropFirst()) }
        return reports
    }
    mutating func didSend(_ reports: [[UInt8]]) {
        if reports.count == 8 { lightHeader = reports[0] }
        else { lightHeader = nil }
    }
    mutating func reset() { lightHeader = nil }
}

enum RKCodec {
    // Same-family SignalRGB live frames: command 0x06, one leading RGB byte,
    // 61 bytes in packet 1 and 62 in packets 2...7. Not a static-save packet.
    static func liveColors(layout:Layout,colors:[Int:RGB]) throws -> [[UInt8]] {
        guard Set(colors.keys).isSubset(of:Set(layout.keys.map(\.id))), layout.keys.allSatisfy({ (0..<139).contains($0.id) }) else { throw RKError.message("实时颜色包含无效键位") }
        var payload = [UInt8](repeating:0,count:433)
        for (id,c) in colors { let offset = 1+id*3; payload[offset] = c.r; payload[offset+1] = c.g; payload[offset+2] = c.b }
        var offset = 0
        return (0..<7).map { index in
            var packet = [UInt8](repeating:0,count:65)
            packet[0] = 10; packet[1] = 7; packet[2] = UInt8(index+1)
            let start = index == 0 ? 4 : 3
            if index == 0 { packet[3] = 6 }
            for position in start..<65 { packet[position] = payload[offset]; offset += 1 }
            return packet
        }
    }
    static func validateLiveColors(_ reports:[[UInt8]]) throws {
        guard reports.count == 7, reports.allSatisfy({ $0.count == 65 }), Array(reports[0].prefix(4)) == [10,7,1,6], reports.enumerated().allSatisfy({ $0.element[0] == 10 && $0.element[1] == 7 && $0.element[2] == UInt8($0.offset+1) }) else { throw RKError.message("拒绝无效的实时颜色事务") }
    }
    // Rangoli RGBModes::Custom == 14. First RGB report carries 59 bytes,
    // the following six carry 62 each (431 transmitted bytes, zero padded).
    static func customLighting(layout: Layout, colors: [Int: RGB], brightness: UInt8 = 3, sleep: UInt8 = 1) throws -> [[UInt8]] {
        guard Set(colors.keys).isSubset(of: Set(layout.keys.map(\.id))),
              layout.keys.allSatisfy({ $0.id >= 0 && $0.id <= 142 }) else { throw RKError.message("逐键颜色包含无效键位") }
        var settings = LightSettings(); settings.mode = 14; settings.brightness = brightness; settings.sleep = sleep
        var full = [UInt8](repeating: 0, count: 431)
        for (id, color) in colors {
            full[id*3] = color.r; full[id*3+1] = color.g; full[id*3+2] = color.b
        }
        var reports = [try lighting(settings)]
        var offset = 0
        for i in 0..<7 {
            var packet = [UInt8](repeating: 0, count: 65)
            packet[0] = 10; packet[1] = 7; packet[2] = UInt8(i+1)
            if i == 0 { packet[3] = 3; packet[4] = 0x7e; packet[5] = 1 }
            for j in (i == 0 ? 6 : 3)..<65 { packet[j] = full[offset]; offset += 1 }
            reports.append(packet)
        }
        return reports
    }

    static func validateTransaction(_ reports: [[UInt8]]) throws {
        guard !reports.isEmpty, reports.allSatisfy({ $0.count == 65 && $0[0] == 10 }) else { throw RKError.message("拒绝不完整报告") }
        func standard(_ p: [UInt8]) -> Bool {
            Array(p.prefix(5)) == [10,1,1,2,41] && (1...21).contains(p[5]) && p[6] == 0 && (1...5).contains(p[7]) && p[8] <= 5 && p[12] <= 1 && (1...5).contains(p[13]) && p[14...].allSatisfy { $0 == 0 }
        }
        if reports.count == 1, standard(reports[0]), reports[0][5] != 14 { return }
        if reports.count == 9, Array(reports[0].prefix(5)) == [10,9,1,1,248], reports.enumerated().allSatisfy({ $0.element[1] == 9 && Int($0.element[2]) == $0.offset+1 }) { return }
        if reports.count == 8, standard(reports[0]), reports[0][5] == 14,
           Array(reports[1].prefix(6)) == [10,7,1,3,126,1],
           reports.dropFirst().enumerated().allSatisfy({ $0.element[1] == 7 && Int($0.element[2]) == $0.offset+1 }) { return }
        throw RKError.message("拒绝未知命令或不完整配置；未发送任何报告。")
    }

    static func lighting(_ s: LightSettings) throws -> [UInt8] {
        guard (1...21).contains(s.mode), (1...5).contains(s.speed), s.brightness <= 5, (1...5).contains(s.sleep) else { throw RKError.message("灯光参数超出范围") }
        var p = [UInt8](repeating: 0, count: 65)
        p.replaceSubrange(0...5, with: [10, 1, 1, 2, 0x29, s.mode])
        p[7] = s.speed; p[8] = s.brightness
        if !s.rainbow { p[9] = s.color.r; p[10] = s.color.g; p[11] = s.color.b }
        p[12] = s.rainbow ? 1 : 0; p[13] = s.sleep
        return p
    }

    static func keymap(layout: Layout, codes: [String: UInt32], overrides: [Int: UInt32]) throws -> [[UInt8]] {
        try layout.validate(codes: codes)
        guard overrides.keys.allSatisfy({ idx in layout.keys.contains { $0.bIndex == idx } }) else { throw RKError.message("按键不属于 RK98 布局") }
        guard overrides.values.allSatisfy({ ShortcutCode.isSupported($0, codes: codes) }),
              overrides.keys.allSatisfy({ id in layout.keys.first { $0.id == id }?.keyCode != "Key_Fn" }) else { throw RKError.message("拒绝未知映射代码或修改 Fn 键。") }
        var full = [UInt8](repeating: 0, count: 9 * 65)
        for key in layout.keys {
            guard let code = overrides[key.bIndex] ?? codes[key.keyCode], key.bIndex >= 0, key.bIndex * 4 + 3 < 556 else { throw RKError.message("无效按键配置") }
            let offset = key.bIndex * 4
            for j in 0..<4 { full[offset + j] = UInt8(truncatingIfNeeded: code >> ((3-j)*8)) }
        }
        var offset = 0
        return (0..<9).map { i in
            var p = [UInt8](repeating: 0, count: 65)
            p[0] = 10; p[1] = 9; p[2] = UInt8(i+1)
            if i == 0 { p[3] = 1; p[4] = 0xf8 }
            let start = i == 0 ? 5 : 3
            for j in start..<65 { p[j] = full[offset]; offset += 1 }
            return p
        }
    }
}

enum ShortcutCode {
    static func isSupported(_ value: UInt32, codes: [String: UInt32]) -> Bool {
        if codes.values.contains(value) { return true }
        let modifiers = value >> 16, base = value & 0xffff
        return (1...15).contains(modifiers) && base != codes["Key_Fn"] &&
            codes.values.contains(where: { $0 > 0 && $0 <= 0xffff && $0 == base })
    }
    static func encode(key: String, modifiers: UInt8, codes: [String: UInt32]) throws -> UInt32 {
        guard modifiers <= 15, key != "Key_Fn", let base = codes[key], base > 0, base <= 0xffff else { throw RKError.message("请选择一个普通按键，最多搭配四个修饰键。") }
        return base | (UInt32(modifiers) << 16)
    }
}

enum RKError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct LabProfile: Codable {
    var version = 1
    var light = LightSettings()
    var overrides: [Int: UInt32] = [:]
    var shortcutURL = "https://www.rkgaming.com"
    var shortcutName = ""
    var workflow: String?

    static let maximumFileBytes = 256 * 1024
    func validate(layout: Layout, codes: [String: UInt32]) throws {
        guard version == 1 else { throw RKError.message("不支持的配置版本") }
        guard light.mode != 14 else { throw RKError.message("基础灯效配置不能使用需要完整颜色数据的自定义模式。") }
        _ = try RKCodec.lighting(light)
        _ = try RKCodec.keymap(layout: layout, codes: codes, overrides: overrides)
        guard shortcutURL.utf8.count <= 8192, shortcutName.utf8.count <= 1024,
              workflow == nil || ["灯光通知", "专注计时", "打开网址", "运行快捷指令"].contains(workflow!) else { throw RKError.message("工作流配置无效或内容过长。") }
    }
    static func read(from url: URL, layout: Layout, codes: [String: UInt32]) throws -> LabProfile {
        let values = try url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw RKError.message("配置必须是普通 JSON 文件。") }
        guard (values.fileSize ?? maximumFileBytes+1) <= maximumFileBytes else { throw RKError.message("配置文件超过 256 KB，已拒绝导入。") }
        // Read a bounded amount even if the file grows after its size check.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumFileBytes + 1) ?? Data()
        guard data.count <= maximumFileBytes else { throw RKError.message("配置文件超过 256 KB，已拒绝导入。") }
        let profile = try JSONDecoder().decode(LabProfile.self, from: data)
        try profile.validate(layout: layout, codes: codes)
        return profile
    }
}
