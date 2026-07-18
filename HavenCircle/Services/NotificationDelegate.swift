import Foundation
import UserNotifications

/// 讓通知在 App 於前景時也以橫幅顯示——演練模式與即時事件都需要這個行為，
/// 否則使用者開著 App 演練時會以為通知管線壞了。
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    /// 點擊通知 → 打開提醒中心；通知帶事件 key 時直達該事件詳情。
    /// 冷啟動時視圖可能尚未訂閱 NotificationCenter，
    /// 所以同時寫入 DeepLinkStore.pending（AppTabs 出現後會補路由），兩條路都通。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let eventKey = response.notification.request.content.userInfo["eventKey"] as? String
        await MainActor.run {
            // 用 URLComponents 組網址：eventKey 來自資料源（可能含空格或非 ASCII），要正確編碼
            var components = URLComponents()
            components.scheme = "havencircle"
            components.host = "alerts"
            if let eventKey {
                components.queryItems = [URLQueryItem(name: "event", value: eventKey)]
            }
            guard let url = components.url else { return }
            DeepLinkStore.pending = url
            NotificationCenter.default.post(name: .didReceiveDeepLink, object: url)
        }
    }
}
