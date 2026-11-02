// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@main
enum ProtocolTests {
    static func main() throws {
        let decoder = JSONDecoder()
        let layout = try decoder.decode(Layout.self, from: Data(contentsOf: URL(fileURLWithPath:"Resources/rk98-layout.json")))
        let codes = try decoder.decode([String: UInt32].self, from: Data(contentsOf: URL(fileURLWithPath:"Resources/keycodes.json")))
        func check(_ ok: Bool, _ text: String) {
            if !ok { fatalError(text) }
            print("PASS: \(text)")
        }
        let p = try RKCodec.lighting(LightSettings())
        check(p.count == 65 && Array(p.prefix(14)) == [10,1,1,2,41,17,0,3,3,75,232,184,0,1], "RGB report matches upstream header, mode 17 and field offsets")
        var rainbow = LightSettings(); rainbow.rainbow = true; rainbow.mode = 18; rainbow.sleep = 5
        let r = try RKCodec.lighting(rainbow)
        check(Array(r[9...12]) == [0,0,0,1] && r[5] == 18 && r[13] == 5, "breathing, rainbow flag and sleep-off encode correctly")
        for level: UInt8 in [0, 1, 5] {
            var s = LightSettings(); s.brightness = level
            check(try RKCodec.lighting(s)[8] == level, "brightness \(level) allowed")
        }
        var invalid = LightSettings(); invalid.mode = 0
        do { _ = try RKCodec.lighting(invalid); fatalError("accepted unknown mode") } catch { print("PASS: invalid mode rejected") }
        invalid = LightSettings(); invalid.sleep = 0
        do { _ = try RKCodec.lighting(invalid); fatalError("accepted sleep zero") } catch { print("PASS: sleep zero rejected") }
        check(layout.keys.count == 100 && Set(layout.keys.map(\.bIndex)).count == 100, "100 unique physical key slots")
        check(layout.keys.allSatisfy { codes[$0.keyCode] != nil }, "every default key has a known firmware code")
        let reports = try RKCodec.keymap(layout: layout, codes: codes, overrides: [0:0x080600, 112:0x0d1e00])
        check(reports.count == 9 && reports.allSatisfy { $0.count == 65 }, "complete mapping uses nine 65-byte reports")
        check(Array(reports[0].prefix(5)) == [10,9,1,1,248], "mapping first header matches upstream")
        var flat: [UInt8] = []
        for (i, report) in reports.enumerated() {
            check(report[2] == UInt8(i+1), "mapping packet \(i+1) sequence")
            flat.append(contentsOf: report[(i == 0 ? 5 : 3)..<65])
        }
        check(flat.count == 556, "mapping payload size matches upstream")
        check(Array(flat[0..<4]) == [0,8,6,0], "Mac Cmd+C modifier bytes")
        check(Array(flat[448..<452]) == [0,13,30,0], "Ctrl+Option+Cmd+1 workflow bytes at slot 112")
        for key in layout.keys where key.bIndex != 0 && key.bIndex != 112 {
            let start = key.bIndex*4
            let code = codes[key.keyCode]!
            let decoded = flat[start..<start+4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            check(decoded == code, "unchanged key \(key.keyCode)")
        }
        do { _ = try RKCodec.keymap(layout: layout, codes: codes, overrides: [999:1]); fatalError("unknown slot accepted") } catch { print("PASS: unknown slot rejected") }
        let profile = LabProfile(light: rainbow, overrides: [0:0x080600])
        let restored = try decoder.decode(LabProfile.self, from: JSONEncoder().encode(profile))
        check(restored.light == rainbow && restored.overrides == profile.overrides, "profile roundtrip preserves settings")
        print("All protocol checks passed. No hardware reports sent.")
    }
}
