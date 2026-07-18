import Foundation
import os

/// 遠端設定（熱更）：啟動時抓 config/app.json；抓不到用上次成功的快取，再不行用程式內建預設值。
/// 後臺（config/admin.php）改完存檔，App 下次啟動即生效，不必重新送審。
///
/// 紅線（Apple Guideline 2.5.2）：這裡只解析「開關與數值」，絕不下載或執行任何程式碼；
/// app.json 是公開檔，伺服器端也絕不放任何祕密。
enum RemoteConfig {
    private static let endpoint = URL(string: "https://havencircle.looptw.com/config/app.json")!
    private static let cacheKey = "remoteConfigCache"

    /// 解析後的設定值。欄位全部 Optional：缺欄位＝用內建預設值，
    /// 舊版 App 讀到新版設定檔也不會解碼失敗（向前相容的關鍵）
    private struct Payload: Decodable {
        var schemaVersion: Int?
        var minimumBuild: Int?
        var upgradeMessage: String?
        var features: [String: Bool]?
        var tuning: [String: Double]?
        /// 災型影響半徑（公尺）：鍵＝EventCategory 的類別字串。
        /// 上架後可遠端調參（300m 太吵、3km 太廣都不必送審）
        var impactRadius: [String: Double]?
    }

    /// 目前生效的設定：啟動先載快取，refresh() 成功後換新
    private static var current = loadCached()

    /// 功能開關：伺服器沒給這個鍵（或從沒抓成功過）時用呼叫端的內建預設，遠端壞掉不影響 App
    static func feature(_ name: String, default defaultValue: Bool) -> Bool {
        current.features?[name] ?? defaultValue
    }

    /// 數值參數：同上，缺鍵用內建預設
    static func tuning(_ name: String, default defaultValue: Double) -> Double {
        current.tuning?[name] ?? defaultValue
    }

    /// 災型影響半徑（公尺）：不同災害的波及範圍天差地遠——
    /// 車禍影響一個路口、槍擊影響一個街區、火災濃煙波及上千公尺。
    /// 警報判定式＝事件距離 ≤ 警戒圈半徑 ＋ 位置精度 ＋ 這個值（影響圈與警戒圈的交集）。
    static func impactRadiusMeters(for eventType: String) -> Int {
        if let remote = current.impactRadius?[eventType] { return max(0, Int(remote)) }
        return Self.defaultImpactRadius[eventType] ?? 0
    }

    /// 內建預設（遠端沒給或斷網時生效）
    private static let defaultImpactRadius: [String: Int] = [
        EventCategory.traffic: 300,        // 車禍：一個路口的範圍
        EventCategory.publicSafety: 1_500, // 槍擊／械鬥：波及整個街區，避開為上
        EventCategory.fire: 1_000,         // 火災：濃煙與延燒範圍
        EventCategory.disaster: 1_000,     // 天災（淹水感測、空品惡化等）
    ]

    /// 啟動時呼叫：抓最新設定並更新快取。逾時收短到 5 秒——
    /// 這一步在啟動流程的最前面，不能讓斷網使用者等一分鐘才看到資料。
    static func refresh() async {
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData // 伺服器端已 no-store，這裡雙保險
        request.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                AppLog.pipeline.error("遠端設定抓取失敗（HTTP \(status)），沿用快取／預設值")
                return
            }
            current = try JSONDecoder().decode(Payload.self, from: data)
            UserDefaults.standard.set(data, forKey: cacheKey)
            AppLog.pipeline.info("遠端設定已更新（schemaVersion \(current.schemaVersion ?? 0)）")
        } catch {
            // 斷網／逾時是日常，不打擾使用者；快取與內建預設保證 App 照常運作
            AppLog.pipeline.error("遠端設定抓取失敗（沿用快取／預設值）：\(error.localizedDescription)")
        }
    }

    private static func loadCached() -> Payload {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return Payload()
        }
        return payload
    }
}
