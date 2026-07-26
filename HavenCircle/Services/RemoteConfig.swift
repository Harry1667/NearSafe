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
        /// 危險級災型清單（通知漏斗）：命中者用時效性通知＋安否互動按鈕；
        /// 其餘（高溫、降雨、停水…）只發一般提醒。可遠端調整
        var dangerKinds: [String]?
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

    /// 危險級判定（通知漏斗）：火災、械鬥、地震、海嘯、颱風這類「需要家人互相確認」的災型。
    /// 點狀事件比對 eventType（火災／公共安全），區域警報比對 kind（地震／海嘯／颱風），
    /// 兩個命名空間字串不重疊，共用同一張清單
    static func isDangerKind(_ kind: String) -> Bool {
        (current.dangerKinds ?? Self.defaultDangerKinds).contains(kind)
    }

    private static let defaultDangerKinds = [
        EventCategory.fire, EventCategory.publicSafety, // 點狀：火災、械鬥/槍擊
        "地震", "海嘯", "颱風",                            // 區域：三大重災
        // 對標 Beacon 後補上的細分類——直接危及人身安全的進行式事件，維持保命推播；
        // 「地震」細分類跟區域警報用同一個字串，已經在上面涵蓋不必重複。
        // 可疑人物／性騷擾／受傷動物／交通/軌道事故／停水停電等留在留意級（不推播），
        // 避免把不確定/非立即人身危險的事件也推成保命等級造成通知疲乏。
        EventCategory.knifeAttack, EventCategory.shooting, EventCategory.disturbance,
        EventCategory.gasLeak, EventCategory.explosion, EventCategory.animalAttack,
    ]

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
