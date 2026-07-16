import Foundation
import SwiftData
import os // Swift 6.2 MemberImportVisibility：用 os.Logger 插值的檔案必須自行 import

/// Demo 彩排配套：載入「真實保存的 NCDR 歷史示警」與一鍵重設。
///
/// 誠實原則：內容是中繼站 2026-07-15／16 實際抓到的官方示警**原文**——
/// 發布單位、地點、座標、發生時間皆為真實資料，只有兩處人為調整並明確標示：
/// 1. 標題冠【歷史示範】字樣，不冒充進行中的即時警報；
/// 2. 顯示效期改為載入後 2 小時，讓彩排時事件出現在「進行中」清單
///    （原始效期已過，照真實效期載入會直接掉進「已結束」）。
/// 所有種子事件用 `demo-history-` 鍵前綴標記，「重設 Demo 資料」可乾淨移除。
@MainActor
enum DemoSeed {
    static let keyPrefix = "demo-history-"

    /// 載入歷史官方事件（重複按不會疊加：先清掉舊種子再載入）
    static func loadHistoricalEvents(context: ModelContext) {
        removeAll(context: context)
        let iso = ISO8601DateFormatter()
        let displayExpiry = Date.now.addingTimeInterval(2 * 3_600)

        // NFA_Fire_20260715195753004：內政部消防署 2026-07-15 實際發布
        let fire = LocalSafetyEvent(
            eventKey: keyPrefix + "NFA_Fire_20260715195753004",
            title: "【歷史示範】重大火災事件通報（工廠及倉庫）",
            eventType: EventCategory.fire,
            occurredAt: iso.date(from: "2026-07-15T21:29:54+08:00") ?? .now,
            approximateLocation: "彰化縣福興鄉秀厝一街",
            latitude: 24.024781293071428,
            longitude: 120.42816408584251,
            precisionMeters: 500,
            sourceName: "內政部消防署",
            sourceURL: "https://alerts.ncdr.nat.gov.tw/",
            trustStatus: TrustStatus.officialConfirmed,
            severity: "需要注意",
            deduplicationGroup: keyPrefix + "fire",
            expiresAt: displayExpiry
        )

        // THB-Bobe_621_23552_42037_20260716152004：交通部公路局 2026-07-16 實際發布
        let roadClosure = LocalSafetyEvent(
            eventKey: keyPrefix + "THB-Bobe_621_23552_42037_20260716152004",
            title: "【歷史示範】省道台9線 227K+500~229K+0 道路封閉",
            eventType: EventCategory.traffic,
            occurredAt: iso.date(from: "2026-07-16T15:00:00+08:00") ?? .now,
            approximateLocation: "花蓮縣鳳林鎮 台9線 227K+500~229K+0",
            latitude: 23.7230998,
            longitude: 121.4309008,
            precisionMeters: 10_000,
            sourceName: "交通部公路局",
            sourceURL: "https://alerts.ncdr.nat.gov.tw/",
            trustStatus: TrustStatus.officialConfirmed,
            severity: "需要注意",
            deduplicationGroup: keyPrefix + "road",
            expiresAt: displayExpiry
        )

        context.insert(fire)
        context.insert(roadClosure)
        context.saveReporting()
        AppLog.pipeline.notice("DemoSeed：已載入 2 筆歷史官方事件示範")
    }

    /// 一鍵重設：移除所有歷史示範種子與演練事件，不動真實管線抓到的事件
    static func removeAll(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<LocalSafetyEvent>())) ?? []
        var removed = 0
        for event in all where event.eventKey.hasPrefix(keyPrefix) || event.isDrill {
            context.delete(event)
            removed += 1
        }
        guard removed > 0 else { return }
        context.saveReporting()
        AppLog.pipeline.notice("DemoSeed：已移除 \(removed) 筆 Demo 資料")
    }
}
