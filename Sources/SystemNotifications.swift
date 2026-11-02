// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import AppKit
import ApplicationServices

// Observes public Accessibility metadata of NotificationCenter only. It does
// not read AXTitle/AXDescription/AXValue, messages, notification databases,
// clipboard, screenshots or other applications' accessibility trees.
final class SystemBannerMonitor {
    private let queue = DispatchQueue(label: "feralkey.banner-metadata")
    private var timer: DispatchSourceTimer?
    private var previous: Set<String>?
    private var previousPID: pid_t?
    private let onBanner: () -> Void
    private let onStatus: (String) -> Void
    static var hasPermission: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    init(onBanner: @escaping () -> Void, onStatus: @escaping (String) -> Void) {
        self.onBanner = onBanner; self.onStatus = onStatus
    }
    deinit { timer?.cancel() }
    func start() -> Bool {
        guard Self.hasPermission else { return false }
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel(); self.previous = nil; self.previousPID = nil
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(750))
            timer.setEventHandler { [weak self] in self?.poll() }
            self.timer = timer; timer.resume()
        }
        return true
    }
    func stop() { queue.async { [weak self] in self?.timer?.cancel(); self?.timer = nil; self?.previous = nil } }
    private func publish(_ status: String) { DispatchQueue.main.async { [weak self] in self?.onStatus(status) } }
    private func poll() {
        guard Self.hasPermission else { previous = nil; publish("辅助功能授权已失效，请重新授权后开启监听。"); return }
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else {
            previous = nil; publish("正在等待系统通知中心启动…"); return
        }
        if previousPID != process.processIdentifier { previous = nil; previousPID = process.processIdentifier }
        let root = AXUIElementCreateApplication(process.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        var reliable = true
        func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            var output: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, key as CFString, &output)
            guard result == .success else {
                if result != .attributeUnsupported && result != .noValue { reliable = false }
                return nil
            }
            return output
        }
        guard let roots = (value(root, kAXWindowsAttribute) as? [AXUIElement]) ?? (value(root, kAXChildrenAttribute) as? [AXUIElement]), reliable else {
            publish("通知中心暂不可读取或当前系统结构不支持，正在重试。"); return
        }
        if roots.isEmpty { previous = []; publish("监听已开启 · 等待可见系统横幅"); return }
        let roles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterAlert", "AXNotificationCenterNotification", "AXNotificationCenterBannerWindow", "AXNotificationCenterAlertStack"]
        var pending = roots.prefix(24).map { ($0, 0, false) }
        var visited = Set<CFHashCode>(), current = Set<String>(), count = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 0.35
        while !pending.isEmpty {
            guard count < 120, ProcessInfo.processInfo.systemUptime < deadline else { break }
            let (node, depth, inBanner) = pending.removeLast()
            let hash = CFHash(node)
            guard visited.insert(hash).inserted else { continue }; count += 1
            if (value(node, "AXHidden") as? Bool) == true { continue }
            let subrole = value(node, kAXSubroleAttribute) as? String ?? ""
            let role = value(node, kAXRoleAttribute) as? String ?? ""
            let identifier = value(node, kAXIdentifierAttribute) as? String ?? ""
            if subrole.localizedCaseInsensitiveContains("widget") || identifier.localizedCaseInsensitiveContains("widget") { continue }
            let recognized = roles.contains(subrole)
            if recognized || (inBanner && role == kAXGroupRole && UUID(uuidString: identifier) != nil) {
                current.insert(identifier.isEmpty ? "element:\(hash)" : "id:\(identifier)")
            }
            if depth < 9, let children = value(node, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children.prefix(32).map { ($0, depth+1, inBanner || recognized) })
            }
        }
        // An incomplete accessibility census must not turn existing elements
        // into apparent new arrivals on the next scan.
        guard pending.isEmpty, reliable else { publish("横幅扫描未完成，已保留原状态并等待下一次。"); return }
        let arrivals = BannerDeduplicator.newIDs(previous: previous, current: current)
        previous = current
        if !arrivals.isEmpty && !process.isActive {
            DispatchQueue.main.async { [weak self] in self?.onBanner() }
        }
        publish("监听已开启 · 当前识别 \(current.count) 个横幅元素，不读取正文")
    }
}
