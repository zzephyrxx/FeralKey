// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

final class NoDeviceTransport: KeyboardTransport {
    var connected = false
    var writesAuthorized = false
    func scan() -> [[String: Any]] { [] }
    func open() throws { fatalError("timer test must never open HID") }
    func close() { }
    func send(_ reports: [[UInt8]]) throws { fatalError("timer test must never write HID") }
}

@main enum AutoRefreshTimerTests {
    static func main() throws {
        let suite = "feralkey-timer-test-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(30, forKey: "quotaInterval")
        preferences.set(URL(fileURLWithPath: "tests/fake-codex.py").standardizedFileURL.path, forKey: "codexPath")
        let model = LabModel(resourceRoot: URL(fileURLWithPath: "Resources").standardizedFileURL, preferences: preferences, transport: NoDeviceTransport(), enumerateOnStart: false)
        model.activate()
        precondition(model.quotaAutoRefresh && model.quotaInterval == 30)
        let firstDeadline = Date().addingTimeInterval(5)
        while model.quota == nil && Date() < firstDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        guard let first = model.quota?.fetchedAt else { fatalError("initial automatic fixture read did not complete") }
        let deadline = Date().addingTimeInterval(33)
        while model.quota?.fetchedAt == first && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        precondition(model.quota!.fetchedAt > first, "30-second timer must read again without manual refresh")
        model.stopQuota()
        let second = model.quota!.fetchedAt
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        precondition(model.quota!.fetchedAt == second && model.nextQuotaRefresh == nil)
        model.cleanup()
        print("PASS: actual 30-second automatic timer performed two fixture reads without manual refresh, then paused; no accounts or HID accessed.")
    }
}
