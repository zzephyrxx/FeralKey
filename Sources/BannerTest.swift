// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import UserNotifications

final class BannerTest: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BannerTest()
    func send(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { allowed, error in
            guard allowed, error == nil else { DispatchQueue.main.async { completion(false) }; return }
            let content = UNMutableNotificationContent()
            content.title = "FeralKey 通知联动测试"
            content.body = "请观察通知区图案，固定的额度区应保持不变。"
            center.add(UNNotificationRequest(identifier: "feralkey-banner-" + UUID().uuidString, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))) { error in
                DispatchQueue.main.async { completion(error == nil) }
            }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
