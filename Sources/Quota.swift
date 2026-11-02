// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

struct QuotaWindow: Codable, Equatable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: Double?
    func remaining(at date: Date) -> Double? {
        guard let used = usedPercent, used.isFinite,
              let reset = resetsAt, reset.isFinite, reset > date.timeIntervalSince1970 else { return nil }
        return min(100, max(0, 100 - used))
    }
}

struct QuotaBucket: Codable, Equatable {
    let limitId: String?
    let limitName: String?
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    func window(minutes: Int) -> QuotaWindow? {
        [primary, secondary].compactMap { $0 }.first { $0.windowDurationMins == minutes }
    }
}

struct QuotaResponse: Decodable {
    let rateLimits: QuotaBucket?
    let rateLimitsByLimitId: [String: QuotaBucket]?
    var buckets: [String: QuotaBucket] {
        if let many = rateLimitsByLimitId, !many.isEmpty { return many }
        if let one = rateLimits { return [one.limitId ?? "codex": one] }
        return [:]
    }
}

struct QuotaSnapshot {
    let buckets: [String: QuotaBucket]
    let fetchedAt: Date
    let isDemo: Bool
    func remaining(bucket: String, minutes: Int, at date: Date, failed: Bool = false, maximumAge: TimeInterval = 180) -> Double? {
        guard !failed, date.timeIntervalSince(fetchedAt) >= -5,
              date.timeIntervalSince(fetchedAt) < maximumAge else { return nil }
        return buckets[bucket]?.window(minutes: minutes)?.remaining(at: date)
    }
    static func demo(at date: Date = Date()) -> QuotaSnapshot {
        let bucket = QuotaBucket(limitId: "demo", limitName: "演示数据", primary: QuotaWindow(usedPercent: 24, windowDurationMins: 300, resetsAt: date.addingTimeInterval(7200).timeIntervalSince1970), secondary: QuotaWindow(usedPercent: 62, windowDurationMins: 10080, resetsAt: date.addingTimeInterval(345600).timeIntervalSince1970))
        return QuotaSnapshot(buckets: ["demo": bucket], fetchedAt: date, isDemo: true)
    }
}

struct QuotaZones: Codable, Equatable {
    var fiveHour: [Int]
    var weekly: [Int]
    static func defaults(layout: Layout) -> QuotaZones {
        func indexes(_ names: [String]) -> [Int] { names.compactMap { name in layout.keys.first { $0.keyCode == name }?.id } }
        return QuotaZones(fiveHour: indexes((1...10).map { "Key_F\($0)" }), weekly: indexes((1...9).map { "Key_\($0)" } + ["Key_0"]))
    }
    func validate(layout: Layout) throws {
        let all = fiveHour + weekly
        guard fiveHour.count == 10, weekly.count == 10,
              Set(all).count == all.count,
              Set(all).isSubset(of: Set(layout.keys.map(\.id))) else { throw RKError.message("每组额度灯需要 10 个不同按键，对应 10% 至 100%，两组不能重叠。") }
    }
    static func migrated(_ old: Self, layout:Layout) -> Self {
        let defaults = Self.defaults(layout:layout)
        func ordered(_ ids:[Int]) -> [Int] {
            layout.keys.filter { ids.contains($0.id) }.sorted {
                let rowA = Int(($0.top[1]+$0.bottom[1])/2/35), rowB = Int(($1.top[1]+$1.bottom[1])/2/35)
                return rowA == rowB ? $0.top[0] < $1.top[0] : rowA < rowB
            }.map(\.id)
        }
        var first = Array(ordered(old.fiveHour).prefix(10))
        let reservedWeekly = Set(ordered(old.weekly).prefix(10))
        for id in defaults.fiveHour + layout.keys.map(\.id) where first.count < 10 && !first.contains(id) && !reservedWeekly.contains(id) { first.append(id) }
        var second = Array(ordered(old.weekly).filter { !first.contains($0) }.prefix(10))
        for id in defaults.weekly + layout.keys.map(\.id) where second.count < 10 && !first.contains(id) && !second.contains(id) { second.append(id) }
        let result = Self(fiveHour:ordered(first),weekly:ordered(second))
        return (try? result.validate(layout:layout)) != nil ? result : defaults
    }
}

struct AgentDisplay: Codable, Equatable {
    var fiveHourEnabled = true
    var weeklyEnabled = true
    func keys(in zones:QuotaZones) -> Set<Int> {
        Set((fiveHourEnabled ? zones.fiveHour : []) + (weeklyEnabled ? zones.weekly : []))
    }
}
struct AgentConfiguration: Codable, Equatable {
    var zones: QuotaZones
    var palette = AgentPalette()
    var display = AgentDisplay()
    var keys: Set<Int> { display.keys(in:zones) }
    func colors(fiveHour:Double?,weekly:Double?) -> [Int:RGB] {
        let five = display.fiveHourEnabled ? QuotaRenderer.band(keys:zones.fiveHour,remaining:fiveHour,weekly:false,palette:palette) : [:]
        let week = display.weeklyEnabled ? QuotaRenderer.band(keys:zones.weekly,remaining:weekly,weekly:true,palette:palette) : [:]
        return five.merging(week) { first,_ in first }
    }
}

enum QuotaRenderer {
    static let off = RGB(r: 0, g: 0, b: 0)
    static let unknown = RGB(r: 55, g: 59, b: 65)
    static func color(remaining: Double, weekly: Bool, palette: AgentPalette? = nil) -> RGB {
        if palette?.warningColors != false && remaining <= 10 { return RGB(r: 245, g: 65, b: 60) }
        if palette?.warningColors != false && remaining <= 25 { return RGB(r: 245, g: 162, b: 50) }
        if let palette { return weekly ? palette.weekly : palette.fiveHour }
        return weekly ? RGB(r: 107, g: 150, b: 248) : RGB(r: 70, g: 212, b: 166)
    }
    // The final segment is proportionally dimmed; 0% means every segment is off.
    static func band(keys: [Int], remaining: Double?, weekly: Bool, palette: AgentPalette? = nil) -> [Int: RGB] {
        guard let remaining, remaining.isFinite else { return Dictionary(uniqueKeysWithValues: keys.map { ($0, unknown) }) }
        let amount = min(100, max(0, remaining)) / 100 * Double(keys.count)
        let rgb = color(remaining: remaining, weekly: weekly, palette: palette)
        return Dictionary(uniqueKeysWithValues: keys.enumerated().map { index, key in
            let level = max(0, min(1, amount - Double(index)))
            return (key, RGB(r: UInt8((Double(rgb.r)*level).rounded()), g: UInt8((Double(rgb.g)*level).rounded()), b: UInt8((Double(rgb.b)*level).rounded())))
        })
    }
    static func frame(zones: QuotaZones, fiveHour: Double?, weekly: Double?, palette: AgentPalette? = nil) -> [Int: RGB] {
        band(keys: zones.fiveHour, remaining: fiveHour, weekly: false, palette: palette).merging(band(keys: zones.weekly, remaining: weekly, weekly: true, palette: palette)) { first, _ in first }
    }
}
