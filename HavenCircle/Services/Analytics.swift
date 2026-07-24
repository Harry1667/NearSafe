import Foundation
import os
import SwiftUI
import FirebaseAnalytics

/// 匿名使用統計：只累計「事件名 × 次數」，送出時附 App 版本與 iOS 版本。
/// 不含任何識別碼、位置或個人資料；伺服器端（analytics/events.php）同樣不存 IP、
/// 只累加當日計數器——兩端合起來才撐得起隱私權政策裡「無法回溯至任何個人」的承諾。
///
/// 設定頁「匿名使用統計」開關可整個關閉：關閉時不記錄也不送出。
enum Analytics {
    private static let endpoint = URL(string: "https://havencircle.looptw.com/analytics/events.php")!
    private static let queueKey = "analyticsPendingEvents"

    private static var isEnabled: Bool {
        // 鍵不存在視為啟用（與 alertsEnabled 同一套預設值慣例）
        UserDefaults.standard.object(forKey: SettingsKeys.analyticsEnabled) as? Bool ?? true
    }

    /// 記一筆事件（先進本機佇列，flush 時才送）。事件名限小寫英數與底線，如 app_open。
    static func track(_ name: String, count: Int = 1) {
        guard isEnabled else { return }
        var queue = pendingQueue()
        queue[name, default: 0] += count
        UserDefaults.standard.set(queue, forKey: queueKey)
        // 同步送 Firebase Analytics（無廣告識別碼版，一樣受此開關控制）。
        // 用模組限定名避免與本 enum「Analytics」撞名。
        FirebaseAnalytics.Analytics.logEvent(name, parameters: count > 1 ? ["count": count] : nil)
    }

    /// 把「匿名使用統計」開關套用到 Firebase：關閉時停止收集。
    /// App 啟動（configure 後）與使用者切換開關時都要呼叫，讓 Firebase 的自動事件
    /// （app_open、session 等）也真的服從使用者的隱私選擇。
    static func applyFirebaseCollectionSetting() {
        FirebaseAnalytics.Analytics.setAnalyticsCollectionEnabled(isEnabled)
    }

    /// 把佇列一次送出；失敗整批保留，下次啟動再送（伺服器端是累加計數，重送順序無所謂）。
    static func flush() async {
        guard isEnabled else {
            UserDefaults.standard.removeObject(forKey: queueKey) // 關閉開關後不留殘料
            return
        }
        let snapshot = pendingQueue()
        guard !snapshot.isEmpty else { return }

        // 伺服器單批上限 20 個事件名；超過的留在佇列等下一輪
        let batch = Array(snapshot.prefix(20))
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let body: [String: Any] = [
            "events": batch.map { ["name": $0.key, "count": $0.value] },
            "app": [
                "ver": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                "os": "\(osVersion.majorVersion).\(osVersion.minorVersion)",
            ],
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return // 伺服器暫時異常：佇列原封不動，下次再送
            }
            // 只扣掉送出的份量：flush 期間新 track 進來的次數要保留
            var latest = pendingQueue()
            for (name, sentCount) in batch {
                let remaining = (latest[name] ?? 0) - sentCount
                if remaining > 0 { latest[name] = remaining } else { latest.removeValue(forKey: name) }
            }
            UserDefaults.standard.set(latest, forKey: queueKey)
        } catch {
            // 斷網是日常：不記 error 級（會洗版），佇列留著下次送
            AppLog.pipeline.info("匿名統計暫時送不出去，下次啟動再送")
        }
    }

    /// 使用者關閉開關時呼叫：清掉尚未送出的佇列
    static func clearQueue() {
        UserDefaults.standard.removeObject(forKey: queueKey)
    }

    /// 記一次「畫面被打開」。只走 Firebase Analytics 標準事件（screen_view），
    /// **不**進 [track] 的自家伺服器佇列——screen_view 量遠大於漏斗事件，
    /// 自家 events.php 是給關鍵漏斗事件用的輕量計數器，塞進大量畫面瀏覽只會撐爆
    /// 每批 20 筆的上限、稀釋真正重要的漏斗訊號。畫面的「次數＋停留時長」交給
    /// Firebase 用 screen_view 自動歸戶到各畫面，不必自己另外計時。
    /// 名稱請用小寫英數與底線（如 settings、alert_center），與 [track] 的慣例一致。
    static func trackScreen(_ name: String) {
        guard isEnabled else { return }
        FirebaseAnalytics.Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: name,
            AnalyticsParameterScreenClass: name,
        ])
    }

    private static func pendingQueue() -> [String: Int] {
        (UserDefaults.standard.dictionary(forKey: queueKey) ?? [:]).compactMapValues { $0 as? Int }
    }
}

extension View {
    /// 掛在畫面根容器上：畫面出現時記一筆 screen_view（見 [Analytics.trackScreen]）。
    func analyticsScreen(_ name: String) -> some View {
        onAppear { Analytics.trackScreen(name) }
    }
}
