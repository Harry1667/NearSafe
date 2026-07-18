import Foundation
import UserNotifications
import os

/// 本機通知排程。所有通知都必須經過這裡，才能保證「暫停提醒」真的有效。
enum NotificationScheduler {
    /// 事件警報通知的互動分類：長按（或下拉）通知即可直接回報安否，不必先開 App。
    /// 這是「事件 → 你 → 家人」閉環的入口：按下後由 NotificationDelegate 寫入安否回報並同步家庭圈。
    static let safetyAlertCategory = "SAFETY_ALERT"
    static let actionReportSafe = "REPORT_SAFE"
    static let actionReportDanger = "REPORT_DANGER"

    /// App 啟動時登記通知分類（Apple 規定要在通知送出前登記好）
    static func registerCategories() {
        let safe = UNNotificationAction(
            identifier: actionReportSafe,
            title: "回報我平安",
            options: [] // 不需開 App，背景就能回報
        )
        let danger = UNNotificationAction(
            identifier: actionReportDanger,
            title: "尚未脫離危險",
            options: [] // 同上；紅色 destructive 樣式反而像「刪除」，不用
        )
        let category = UNNotificationCategory(
            identifier: safetyAlertCategory,
            actions: [safe, danger],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
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
    /// eventKey：讓通知點擊能直達該事件詳情，不帶就只開提醒中心清單（如每日摘要）。
    static func scheduleAlert(title: String, body: String, id: String, eventKey: String? = nil) async {
        let defaults = UserDefaults.standard
        // alertsEnabled 預設值為 true（鍵不存在時視為啟用），alertsPaused 預設 false
        let enabled = defaults.object(forKey: SettingsKeys.alertsEnabled) as? Bool ?? true
        let paused = defaults.bool(forKey: SettingsKeys.alertsPaused)
        guard enabled, !paused else {
            AppLog.notifications.info("提醒已停用或暫停，略過通知：\(id)")
            return
        }
        // 只檢查現有權限，不在這裡觸發系統對話框——
        // 否則資料管線會在刷新途中被權限框卡住。權限請求只發生在
        // 明確的 UX 時機（首次設定完成、演練頁、設定頁按鈕）。
        guard await authorizationStatus() == .authorized else {
            AppLog.notifications.info("尚未取得通知權限，略過通知：\(id)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let eventKey {
            content.userInfo = ["eventKey": eventKey]
            // 事件警報才掛安否回報按鈕（每日摘要、解除通知不需要）
            content.categoryIdentifier = safetyAlertCategory
        }
        do {
            try await UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        } catch {
            AppLog.notifications.error("通知排程失敗（\(id)）：\(error.localizedDescription)")
        }
    }

    /// 事件提醒的唯一入口：先過 AlertPolicy 決策，該推才推。
    /// 回傳決策讓呼叫端（例如演練模式）能顯示「為何推播／為何不推播」。
    @discardableResult
    static func notifyIfNeeded(
        for event: LocalSafetyEvent,
        members: [LocalFamilyMember]
    ) async -> AlertDecision {
        let decision = AlertPolicy.evaluate(event: event, members: members)
        guard decision.shouldPush else {
            AppLog.notifications.info("不推播（\(event.eventKey)）：\(decision.reason)")
            return decision
        }
        let prefix = event.isDrill ? "【演練】" : ""
        await scheduleAlert(
            title: "\(prefix)\(event.title)",
            body: "\(decision.reason)。長按通知可直接回報安否，家人會收到你的狀態。",
            id: event.eventKey,
            eventKey: event.eventKey
        )
        // 標記已推播：同一事件不重複打擾（通知限流的最小單位）
        event.hasNotified = true
        return decision
    }

    /// 解除通知：焦慮被打開了就要被關上
    static func notifyResolved(for event: LocalSafetyEvent) async {
        let prefix = event.isDrill ? "【演練】" : ""
        await scheduleAlert(
            title: "\(prefix)事件已解除：\(event.title)",
            body: "\(event.approximateLocation)的事件已標記為結束，無需進一步行動。",
            id: "\(event.eventKey)-resolved",
            eventKey: event.eventKey
        )
    }

    // MARK: - 每日安全摘要

    static let digestID = "daily-digest"

    /// 重排每日摘要通知。摘要內容是「排程當下」計算的快照——
    /// 原型限制：App 沒有背景更新，每次回到前景時重算一次讓內容盡量新鮮。
    static func refreshDailyDigest(summary: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [digestID])

        let defaults = UserDefaults.standard
        let digestEnabled = defaults.object(forKey: SettingsKeys.digestEnabled) as? Bool ?? true
        let alertsEnabled = defaults.object(forKey: SettingsKeys.alertsEnabled) as? Bool ?? true
        guard digestEnabled, alertsEnabled else { return }
        guard await authorizationStatus() == .authorized else { return }

        var components = DateComponents()
        components.hour = defaults.object(forKey: SettingsKeys.digestHour) as? Int ?? 20
        components.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "今日安全摘要"
        content.body = summary
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        do {
            try await center.add(UNNotificationRequest(identifier: digestID, content: content, trigger: trigger))
        } catch {
            AppLog.notifications.error("每日摘要排程失敗：\(error.localizedDescription)")
        }
    }
}
