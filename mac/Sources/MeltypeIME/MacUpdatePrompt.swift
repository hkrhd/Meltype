// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 hkrhd

import Foundation
import UserNotifications

/// 準備できた更新を macOS の通知で知らせ、通知か入力メニューで選ばれたら更新して再起動する。
final class MacUpdatePrompt: NSObject, UNUserNotificationCenterDelegate {
    static let notificationIdentifier = "update-ready"
    /// 通知のクリックで起こされたときにも届くよう、起動時に通知センターの delegate にする (main.swift)。
    static let shared = MacUpdatePrompt()

    var updater: MacUpdater?

    static func readyMessage(build: Int) -> String {
        "Meltype ビルド \(build) を準備しました。ここをクリックすると更新して再起動します。入力メニューの「\(menuTitle(build: build))」からも更新できます。"
    }

    static func menuTitle(build: Int) -> String { "Meltype ビルド \(build) に更新して再起動" }

    func notifyReady(build: Int) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            guard granted else {
                NSLog("Meltype: 更新の通知を出せません (入力メニューから更新できます): %@", error?.localizedDescription ?? "通知が許可されていません")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Meltype の更新"
            content.body = Self.readyMessage(build: build)
            center.add(UNNotificationRequest(identifier: Self.notificationIdentifier, content: content, trigger: nil))
        }
    }

    func installUpdate() {
        guard let updater else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
        if case .failed(let reason) = updater.install() { NSLog("Meltype: 更新できませんでした: %@", reason) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier == Self.notificationIdentifier,
           response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            DispatchQueue.main.async { self.installUpdate() }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
