import Foundation
import SwiftData

/// 首次啟動的示範資料，讓地圖不是空的（僅在資料庫沒有任何事件時插入）
enum DemoSeed {
    static func insertIfNeeded(into context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<LocalSafetyEvent>())) ?? []
        guard existing.isEmpty else { return }
        context.insert(LocalSafetyEvent(
            eventKey: "taipei-fire-demo-1",
            title: "火警通報",
            eventType: EventCategory.fire,
            approximateLocation: "信義區松仁路附近",
            latitude: 25.0333,
            longitude: 121.5688,
            precisionMeters: 500,
            sourceName: "台北市政府消防局",
            sourceURL: "https://www.119.gov.taipei/",
            trustStatus: TrustStatus.officialConfirmed,
            severity: "需要注意",
            deduplicationGroup: "fire-xinyi-20260715",
            expiresAt: .now.addingTimeInterval(86_400)
        ))
        context.saveReporting()
    }
}
