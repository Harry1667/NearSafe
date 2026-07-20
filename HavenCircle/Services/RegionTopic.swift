import Foundation
import CryptoKit

/// FCM 主題名的單一真實來源（App 與 Oracle 伺服器必須用「完全相同」的規則）。
///
/// 設計：
/// - 地區性事件用「縣市＋區」算出穩定、ASCII 安全的主題名（FCM 主題只允許 [a-zA-Z0-9-_.~%]，
///   中文不能直接當主題名，故取正規化字串的 SHA-1 前 16 碼）。
/// - 全台有感事件（地震／海嘯／颱風）用固定的全域主題 `hc_all`，所有裝置都訂。
/// - 正規化規則（臺→台、去空白）App 與伺服器（region_topic.php）必須完全一致，
///   否則同一個區在兩邊會算出不同主題、通知永遠對不上。已用跨語言測試驗證一致。
enum RegionTopic {
    /// 全台廣播主題（地震／海嘯／颱風等全區有感事件）。所有裝置都應訂閱。
    static let all = "hc_all"

    /// 由「縣市＋區」算出主題名，例如 forRegion(county: "台中市", town: "中區")。
    static func forRegion(county: String, town: String) -> String {
        let canonical = normalize(county) + normalize(town)
        let digest = Insecure.SHA1.hash(data: Data(canonical.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "hc_r_" + String(hex.prefix(16))
    }

    /// 正規化：政府 CAP 資料用「臺」、本地 GeoJSON 用「台」，統一成「台」；並去除前後空白。
    /// 這條規則若與伺服器端 region_topic.php 不一致，整套訂閱制就會失效。
    private static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "臺", with: "台")
            .trimmingCharacters(in: .whitespaces)
    }
}
