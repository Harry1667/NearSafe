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
        [.banner, .sound]
    }

    /// 點擊通知 → 打開提醒中心。冷啟動時視圖可能尚未訂閱 NotificationCenter，
    /// 所以同時寫入 DeepLinkStore.pending（AppTabs 出現後會補路由），兩條路都通。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            guard let url = URL(string: "havencircle://alerts") else { return }
            DeepLinkStore.pending = url
            NotificationCenter.default.post(name: .didReceiveDeepLink, object: url)
        }
    }
}
