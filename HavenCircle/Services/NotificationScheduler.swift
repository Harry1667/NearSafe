import Foundation
import UserNotifications
import os

/// 本機通知排程。所有通知都必須經過這裡，才能保證「暫停提醒」真的有效。
enum NotificationScheduler {
    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            AppLog.notifications.error("通知權限請求失敗：\(error.localizedDescription)")
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// 發送事件提醒。修正舊版問題：這裡實際檢查「啟用本機提醒」與「暫停提醒」旗標，
    /// 任一不符就不發，並記錄原因。
    static func scheduleAlert(title: String, body: String, id: String) async {
        let defaults = UserDefaults.standard
        // alertsEnabled 預設值為 true（鍵不存在時視為啟用），alertsPaused 預設 false
        let enabled = defaults.object(forKey: SettingsKeys.alertsEnabled) as? Bool ?? true
        let paused = defaults.bool(forKey: SettingsKeys.alertsPaused)
        guard enabled, !paused else {
            AppLog.notifications.info("提醒已停用或暫停，略過通知：\(id)")
            return
        }
        guard await requestPermission() else {
            AppLog.notifications.info("未取得通知權限，略過通知：\(id)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        do {
            try await UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        } catch {
            AppLog.notifications.error("通知排程失敗（\(id)）：\(error.localizedDescription)")
        }
    }
}
