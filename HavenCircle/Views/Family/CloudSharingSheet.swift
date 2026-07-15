import SwiftUI
import CloudKit
import UIKit

/// 包裝 UICloudSharingController：系統原生的邀請介面，
/// 直接產生邀請連結、訊息、AirDrop 等分享管道（涵蓋「未安裝 App 的家人 fallback」）。
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func itemTitle(for csc: UICloudSharingController) -> String? { "安心圈家庭" }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            AppLog.cloudError("分享儲存失敗：\(error.localizedDescription)")
        }
    }
}
