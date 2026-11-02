// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@main enum QuotaTests {
    static func main() throws {
        var checks = 0
        func check(_ value: Bool, _ name: String) { precondition(value, name); checks += 1 }
        func rejects(_ name: String, _ action: () throws -> Void) { do { try action(); fatalError(name) } catch { checks += 1 } }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = Data("""
        {"rateLimits":{"limitId":"legacy","primary":{"usedPercent":99,"windowDurationMins":300,"resetsAt":1800000300}},
         "rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":58,"windowDurationMins":10080,"resetsAt":1800010000},"secondary":{"usedPercent":14,"windowDurationMins":300,"resetsAt":1800000300}},"other":{"primary":null,"secondary":null}}}
        """.utf8)
        let response = try JSONDecoder().decode(QuotaResponse.self, from: fixture)
        let snapshot = QuotaSnapshot(buckets: response.buckets, fetchedAt: now, isDemo: false)
        check(snapshot.buckets["legacy"] == nil, "multi-bucket takes precedence")
        check(snapshot.remaining(bucket: "codex", minutes: 300, at: now) == 86, "identify 5h by duration, not primary position")
        check(snapshot.remaining(bucket: "codex", minutes: 10080, at: now) == 42, "weekly by duration")
        check(snapshot.remaining(bucket: "other", minutes: 300, at: now) == nil, "missing is unknown")
        check(snapshot.remaining(bucket: "codex", minutes: 300, at: now, failed: true) == nil, "failure invalidates old values immediately")
        check(snapshot.remaining(bucket: "codex", minutes: 300, at: now.addingTimeInterval(180)) == nil, "3 minute stale deadline")
        check(snapshot.remaining(bucket: "codex", minutes: 300, at: now.addingTimeInterval(-10)) == nil, "clock rollback is unknown")
        for (used, expected) in [(-10.0,100.0),(120.0,0.0),(25.0,75.0)] {
            check(QuotaWindow(usedPercent: used, windowDurationMins: 300, resetsAt: 1_800_000_100).remaining(at: now) == expected, "clamp remaining")
        }
        check(QuotaWindow(usedPercent: 10, windowDurationMins: 300, resetsAt: now.timeIntervalSince1970).remaining(at: now) == nil, "never invent full quota after reset")
        check(QuotaWindow(usedPercent: nil, windowDurationMins: 300, resetsAt: 1_800_000_100).remaining(at: now) == nil, "null usage")
        check(QuotaWindow(usedPercent: 10, windowDurationMins: 300, resetsAt: nil).remaining(at: now) == nil, "missing reset")
        let legacy = try JSONDecoder().decode(QuotaResponse.self, from: Data("{\"rateLimits\":{\"primary\":null}}".utf8))
        check(legacy.buckets["codex"] != nil, "legacy single bucket")
        let layout = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: URL(fileURLWithPath: "Resources/rk98-layout.json")))
        let zones = QuotaZones.defaults(layout: layout)
        try zones.validate(layout: layout)
        check(zones.fiveHour.count == 10 && zones.weekly.count == 10, "default bars are 10 keys each")
        rejects("overlap") { try QuotaZones(fiveHour: [6], weekly: [6]).validate(layout: layout) }
        rejects("empty zone") { try QuotaZones(fiveHour: [], weekly: [6]).validate(layout: layout) }
        rejects("unknown key") { try QuotaZones(fiveHour: [9999], weekly: [6]).validate(layout: layout) }
        for remaining in [0.0, 0.1, 10, 25, 42, 86, 100] {
            let frame = QuotaRenderer.frame(zones: zones, fiveHour: remaining, weekly: remaining)
            let packets = try RKCodec.customLighting(layout: layout, colors: frame)
            try RKCodec.validateTransaction(packets)
            check(packets.count == 8 && packets.allSatisfy { $0.count == 65 }, "8 complete 65 byte reports")
            check(packets[0][5] == 14, "Rangoli RGB Custom is mode 14")
            check(Array(packets[1].prefix(6)) == [10,7,1,3,126,1], "RGB header golden vector")
            var payload: [UInt8] = []
            for (i, packet) in packets.dropFirst().enumerated() { payload += packet[(i == 0 ? 6 : 3)...] }
            check(payload.count == 431, "RGB payload with correct first packet boundary")
            for key in layout.keys {
                let color = frame[key.id] ?? QuotaRenderer.off
                check(Array(payload[key.id*3..<key.id*3+3]) == [color.r,color.g,color.b], "physical slot color round trip")
            }
            check(zones.fiveHour.filter { frame[$0] != QuotaRenderer.off }.count == Int(ceil(remaining/10)), "lit count including partial segment")
        }
        let unknown = QuotaRenderer.frame(zones: zones, fiveHour: nil, weekly: nil)
        check(unknown.values.allSatisfy { $0 == QuotaRenderer.unknown }, "unknown is distinct from zero")
        let sentinel = try RKCodec.customLighting(layout: layout, colors: [0: RGB(r: 1,g: 2,b: 3), 112: RGB(r: 4,g: 5,b: 6)])
        check(Array(sentinel[1][6...8]) == [1,2,3], "first slot golden bytes")
        rejects("incomplete custom transaction") { try RKCodec.validateTransaction(Array(sentinel.dropLast())) }
        var outOfOrder = sentinel; outOfOrder.swapAt(2, 3)
        rejects("out of order") { try RKCodec.validateTransaction(outOfOrder) }
        rejects("unknown command") { try RKCodec.validateTransaction([[UInt8](repeating: 0, count: 65)]) }
        rejects("empty reports") { try RKCodec.validateTransaction([]) }
        rejects("wrong RGB slot") { _ = try RKCodec.customLighting(layout: layout, colors: [999: .mint]) }
        try RKCodec.validateTransaction([RKCodec.lighting(LightSettings())])
        let codes = try JSONDecoder().decode([String:UInt32].self, from: Data(contentsOf: URL(fileURLWithPath: "Resources/keycodes.json")))
        rejects("unknown mapping code") { _ = try RKCodec.keymap(layout: layout, codes: codes, overrides: [0: UInt32.max]) }
        rejects("Fn overwrite") { _ = try RKCodec.keymap(layout: layout, codes: codes, overrides: [65: codes["Key_A"]!]) }
        rejects("empty layout cannot write all-zero map") { _ = try RKCodec.keymap(layout: Layout(name: "empty", keys: []), codes: codes, overrides: [:]) }
        var unsupported = LabProfile(); unsupported.overrides[0] = UInt32.max
        rejects("profile validates mapping") { try unsupported.validate(layout: layout, codes: codes) }
        let oversized = FileManager.default.temporaryDirectory.appendingPathComponent("feralkey-profile-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: oversized) }
        try Data(repeating: 32, count: LabProfile.maximumFileBytes+1).write(to: oversized)
        rejects("oversized profile") { _ = try LabProfile.read(from: oversized, layout: layout, codes: codes) }
        try RKCodec.validateTransaction(RKCodec.keymap(layout: layout, codes: codes, overrides: [:]))
        let known = DeviceDescriptor(vendorID: 0x258a, productID: 0xc1, product: "Bluetooth Keyboard", transport: "USB", usagePage: 1, usage: 128, featureBytes: 65)
        check(known.matchesRK98Control, "exact known interface")
        let other = DeviceDescriptor(vendorID: 0x258a, productID: 0xc1, product: "RK98", transport: "Bluetooth", usagePage: 1, usage: 128, featureBytes: 65)
        check(!other.matchesRK98Control, "same VID/PID over Bluetooth not writable")
        let receiver = DeviceDescriptor(vendorID:0x25a7,productID:0xfa70,product:"2.4G Wireless Receiver",transport:"USB",usagePage:1,usage:2,featureBytes:8)
        check(receiver.isCompxReceiver && !receiver.matchesRK98Control, "receiver recognition never enables wired RGB")
        let receiverFixture = try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:"tests/fixtures/compx-fa70-0391-descriptors.json"))) as! [[String:Any]]
        let hex = receiverFixture.first { ($0["MaxFeatureReportSize"] as? Int) == 8 }!["reportDescriptorHex"] as! String
        let values = stride(from:0,to:hex.count,by:2).map { offset -> UInt8 in
            let start = hex.index(hex.startIndex,offsetBy:offset)
            return UInt8(hex[start..<hex.index(start,offsetBy:2)],radix:16)!
        }
        let descriptor = Data(values)
        check(ReceiverResearch.permitsStatusRead(device:receiver,version:0x0391,descriptor:descriptor), "known receiver permits only bounded status read")
        check(!ReceiverResearch.permitsStatusRead(device:receiver,version:0x0300,descriptor:descriptor), "unknown receiver version fails closed")
        check(!ReceiverResearch.permitsStatusRead(device:receiver,version:0x0391,descriptor:descriptor+Data([0])), "modified receiver descriptor fails closed")
        check(!ReceiverResearch.permitsStatusRead(device:known,version:0x0391,descriptor:descriptor), "status read cannot target wired keyboard")
        let package = try DeviceDiscovery.researchPackage(devices: [known])
        let obj = try JSONSerialization.jsonObject(with: package) as! [String:Any]
        check(Set(obj.keys) == ["schemaVersion","appVersion","platform","contains","verification","devices"], "research export restricted fields")
        print("PASS: \(checks) quota / packet / discovery checks. No hardware I/O.")
    }
}
