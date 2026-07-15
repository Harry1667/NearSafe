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
}
