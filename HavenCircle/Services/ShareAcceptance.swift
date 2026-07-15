import SwiftUI
import CloudKit

/// CKShare 邀請接受的處理鏈。
///
/// SwiftUI 生命週期的 App 沒有直接的分享接受修飾符，必須透過
/// UIApplicationDelegate 設定一個 scene delegate，由系統在使用者點開邀請連結時回呼。
/// 接受到的 metadata 透過 NotificationCenter 轉交給 FamilySyncService 處理。
extension Notification.Name {
    static let didAcceptFamilyShare = Notification.Name("didAcceptFamilyShare")
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = ShareSceneDelegate.self
        return config
    }
}

final class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        NotificationCenter.default.post(
            name: .didAcceptFamilyShare,
            object: cloudKitShareMetadata
        )
    }
}
