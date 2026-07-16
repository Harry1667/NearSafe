import SwiftUI
import CloudKit

/// CKShare 邀請接受的處理鏈。
///
/// SwiftUI 生命週期的 App 沒有直接的分享接受修飾符，必須透過
/// UIApplicationDelegate 設定一個 scene delegate，由系統在使用者點開邀請連結時回呼。
/// 接受到的 metadata 透過 NotificationCenter 轉交給 FamilySyncService 處理。
extension Notification.Name {
    static let didAcceptFamilyShare = Notification.Name("didAcceptFamilyShare")
    static let didReceiveDeepLink = Notification.Name("didReceiveDeepLink")
}

/// 冷啟動時由 URL 拉起 App 的暫存（scene 連接早於 SwiftUI 視圖訂閱，直接發通知會漏接）
enum DeepLinkStore {
    @MainActor static var pending: URL?
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

    // 設了自訂 scene delegate 後，SwiftUI 的 .onOpenURL 收不到 URL（系統改送這裡），
    // Widget deep link 必須在此接手轉交。
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let url = connectionOptions.urlContexts.first?.url {
            DeepLinkStore.pending = url // 冷啟動：等視圖出現後再路由
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        NotificationCenter.default.post(name: .didReceiveDeepLink, object: url)
    }
}
