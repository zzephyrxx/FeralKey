// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@main enum QuotaSmoke {
    static func main() throws {
        let live = CommandLine.arguments.contains("--live")
        let snapshot: QuotaSnapshot
        if live {
            guard let executable = CodexClient.locate() else { throw RKError.message("未找到 Codex") }
            snapshot = try CodexClient.fetch(executable: executable)
        } else { snapshot = .demo() }
        let bucket = live ? (snapshot.buckets["codex"] != nil ? "codex" : snapshot.buckets.keys.sorted().first ?? "") : "demo"
        let layout = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: URL(fileURLWithPath: "Resources/rk98-layout.json")))
        let five = snapshot.remaining(bucket: bucket, minutes: 300, at: Date())
        let week = snapshot.remaining(bucket: bucket, minutes: 10080, at: Date())
        guard let five, let week else { throw RKError.message("没有同时返回有效的五小时及每周额度。") }
        let zones = QuotaZones.defaults(layout: layout)
        try zones.validate(layout: layout)
        let reports = try RKCodec.customLighting(layout: layout, colors: QuotaRenderer.frame(zones: zones, fiveHour: five, weekly: week))
        try RKCodec.validateTransaction(reports)
        let summary: [String:Any] = ["source": live ? "codex-app-server" : "demo", "fiveHourRemaining": five, "weeklyRemaining": week, "reportsPrepared": reports.count, "bytesPerReport": 65, "hardwareReportsSent": 0]
        print(String(data: try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted,.sortedKeys]), encoding: .utf8)!)
    }
}
