import Foundation
import os

/// APNs 權杖登記：把裝置權杖上傳到中繼站，伺服器偵測到新官方警報時
/// 才能對這台裝置發「無聲喚醒」（App 沒開也能即時收到警報的關鍵一段）。
///
/// 零追蹤守則：只上傳「權杖＋環境（sandbox/production）」，不附位置、姓名、生活圈。
/// 伺服器一律廣播喚醒所有裝置，警報與這位使用者是否相關，永遠由裝置自己比對。
enum APNsRegistrar {
    private static let endpoint = URL(string: "https://havencircle.looptw.com/apns/register.php")!

    static func upload(token: String) async {
        // Xcode 直裝的 Debug build 走 Apple 的 sandbox 推播環境，TestFlight/上架走 production；
        // 環境選錯 Apple 會回 BadDeviceToken，所以要隨 build 型態自動帶對
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token, "env": environment])
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                AppLog.notifications.error("APNs 權杖登記失敗：伺服器回應異常")
                return
            }
            AppLog.notifications.info("APNs 權杖已登記到中繼站（\(environment)）")
        } catch {
            // 登記失敗不打擾使用者：下次啟動會再試（每次啟動都重新登記，冪等）
            AppLog.notifications.error("APNs 權杖登記失敗：\(error.localizedDescription)")
        }
    }
}
