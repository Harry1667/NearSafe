import Foundation
import os

/// APNs 權杖登記：把裝置權杖上傳到中繼站，伺服器偵測到新官方警報時
/// 才能對這台裝置發「無聲喚醒」（App 沒開也能即時收到警報的關鍵一段）。
///
/// 最少資料守則：只上傳「權杖＋環境（sandbox/production）」，不附位置、姓名、警戒圈。
/// 伺服器一律廣播喚醒所有裝置，警報與這位使用者是否相關，永遠由裝置自己比對。
enum APNsRegistrar {
    private static let registerEndpoint = URL(string: "https://havencircle.looptw.com/apns/register.php")!
    private static let unregisterEndpoint = URL(string: "https://havencircle.looptw.com/apns/unregister.php")!

    static func upload(token: String) async {
        // Xcode 直裝的 Debug build 走 Apple 的 sandbox 推播環境，TestFlight/上架走 production；
        // 環境選錯 Apple 會回 BadDeviceToken，所以要隨 build 型態自動帶對
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        var request = URLRequest(url: registerEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token, "env": environment])
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                AppLog.notifications.error("APNs 權杖登記失敗：伺服器 HTTP \(status)")
                return
            }
            AppLog.notifications.info("APNs 權杖已登記到中繼站（\(environment)）")
        } catch {
            // 登記失敗不打擾使用者：下次啟動會再試（每次啟動都重新登記，冪等）
            AppLog.notifications.error("APNs 權杖登記失敗：\(error.localizedDescription)")
        }
    }

    /// 「刪除帳號與所有資料」的一部分：讓使用者能撤回中繼站的推播識別碼。
    /// 不上傳其他身分欄位；權杖本身就是刪除索引。
    static func unregister(token: String) async {
        var request = URLRequest(url: unregisterEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token])
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                AppLog.notifications.error("APNs 權杖撤銷失敗：伺服器 HTTP \(status)")
                return
            }
            AppLog.notifications.info("APNs 權杖已從中繼站撤銷")
        } catch {
            // 刪除本機資料不能被網路狀態卡住；失效權杖仍會在 APNs 回應後由伺服器淘汰。
            AppLog.notifications.error("APNs 權杖撤銷失敗：\(error.localizedDescription)")
        }
    }
}
