// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum RefreshSchedule {
    static let intervals = [30, 60, 180, 300, 600, 1800]
    static func title(_ seconds: Int) -> String { seconds < 60 ? "\(seconds) 秒" : "\(seconds / 60) 分钟" }
    static func maximumAge(_ interval: Int) -> TimeInterval { Double(max(180, interval * 2 + 30)) }
}

enum NotificationPattern: String, Codable, CaseIterable, Identifiable {
    case border, cross, checkerboard, solid, marquee, codeRain
    var id: String { rawValue }
    var title: String { switch self { case .border: return "光框"; case .cross: return "十字"; case .checkerboard: return "棋盘"; case .solid: return "呼吸 / 自由绘制"; case .marquee: return "跑马灯"; case .codeRain: return "代码雨" } }
    var motion: MotionStyle? { switch self { case .marquee: return .marquee; case .codeRain: return .codeRain; default: return nil } }
}

struct NotificationSettings: Codable {
    var keys: [Int]
    var pattern: NotificationPattern = .border
    var color = RGB(r: 255, g: 145, b: 55)
    static func defaults(_ layout: Layout) -> Self {
        Self(keys: layout.keys.filter { $0.keyCode.hasPrefix("Key_Num_") || ($0.keyCode == "Key_Enter" && $0.top[0] >= 665) }.map(\.id))
    }
    func validate(_ layout: Layout) throws {
        guard !keys.isEmpty, Set(keys).count == keys.count, Set(keys).isSubset(of: Set(layout.keys.map(\.id))) else { throw RKError.message("请为通知选择至少一个有效键位。") }
    }
    func colors(layout: Layout, background: [Int: RGB], time: Double = 0, pulse: Bool = false) -> [Int: RGB] {
        if let style = pattern.motion {
            return background.merging(MotionRenderer.frame(layout: layout, keys: Set(keys), style: style, color: color, time: time)) { _, new in new }
        }
        let chosen = layout.keys.filter { keys.contains($0.id) }
        guard !chosen.isEmpty else { return background }
        let centers = chosen.map { (($0.top[0]+$0.bottom[0])/2, ($0.top[1]+$0.bottom[1])/2) }
        let minX = centers.map(\.0).min()!, maxX = centers.map(\.0).max()!
        let minY = centers.map(\.1).min()!, maxY = centers.map(\.1).max()!
        var result = background
        for (key, center) in zip(chosen, centers) {
            let x = (center.0-minX)/max(1,maxX-minX), y = (center.1-minY)/max(1,maxY-minY)
            let lit: Bool
            switch pattern {
            case .solid: lit = true
            case .border: lit = x < 0.2 || x > 0.8 || y < 0.15 || y > 0.85
            case .cross: lit = abs(x-0.5) <= 0.2 || abs(y-0.5) <= 0.15
            case .checkerboard: lit = (Int((x*3).rounded()) + Int((y*4).rounded())) % 2 == 0
            case .marquee, .codeRain: lit = false
            }
            let safeTime = time.isFinite ? time : 0
            let intensity = pulse ? 0.12 + 0.88*pow((cos(safeTime*2*Double.pi/1.6)+1)/2, 1.4) : 1
            let tint = RGB(r: UInt8(Double(color.r)*intensity), g: UInt8(Double(color.g)*intensity), b: UInt8(Double(color.b)*intensity))
            result[key.id] = lit || chosen.count <= 2 ? tint : .init(r: 0,g: 0,b: 0)
        }
        return result
    }
}

enum AudioEnvelope {
    static func level(sumSquares: Double, count: Int) -> Double {
        guard count > 0, sumSquares.isFinite, sumSquares > 0 else { return 0 }
        let db = 20 * log10(sqrt(sumSquares / Double(count)))
        return min(1, max(0, (db + 60)/60))
    }
}

struct ShortcutPreset: Identifiable {
    let id: String
    let title: String
    let key: String
    let modifiers: UInt8
    let detail: String
    static let all: [Self] = [
        .init(id: "pasteStyle", title: "粘贴并匹配格式", key: "Key_V", modifiers: 14, detail: "⌘⌥⇧V · 支持此命令的应用内去掉来源格式"),
        .init(id: "finderMove", title: "Finder 移动已复制文件", key: "Key_V", modifiers: 12, detail: "⌘⌥V · 先复制文件，再在目标文件夹使用"),
        .init(id: "clipShot", title: "区域截图到剪贴板", key: "Key_4", modifiers: 11, detail: "⌃⇧⌘4 · 选择区域后直接粘贴，不生成桌面截图文件"),
        .init(id: "shotPanel", title: "截图与录屏面板", key: "Key_5", modifiers: 10, detail: "⇧⌘5 · 打开系统截图选项"),
        .init(id: "emoji", title: "表情与符号面板", key: "Key_Space", modifiers: 9, detail: "⌃⌘空格 · 输入表情、数学符号"),
        .init(id: "restoreTab", title: "重新打开关闭的标签页", key: "Key_T", modifiers: 10, detail: "⇧⌘T · 常见浏览器，依其快捷键设置"),
        .init(id: "format", title: "VS Code 格式化文档", key: "Key_F", modifiers: 6, detail: "⇧⌥F · 需要当前语言的格式化器"),
        .init(id: "multiCursor", title: "VS Code 全部匹配多光标", key: "Key_L", modifiers: 10, detail: "⇧⌘L · 选中文字后一次修改所有匹配位置"),
        .init(id: "commandPalette", title: "VS Code 命令面板", key: "Key_P", modifiers: 10, detail: "⇧⌘P · 搜索并执行编辑器命令")
    ]
}
