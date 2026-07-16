import Foundation

/// Widget 快照共用模型。
/// ⚠️ 這個檔案在 HavenCircle/Support/ 與 HavenCircleWidget/ 各有一份，內容必須完全一致
/// （Xcode 同步資料夾跨 target 共檔設定繁瑣，原型期以雙副本換簡單；改動時兩份一起改）。
enum WidgetShared {
    static let appGroupID = "group.com.gomiigo.CamMenuApp.HavenCircle"
    static let widgetKind = "HavenCircleWidget"
    static let snapshotFilename = "widget-snapshot.json"

    static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(snapshotFilename)
    }

    /// 快照超過這個時間視為失效（規格 09：一般資料 2 小時）
    static let staleInterval: TimeInterval = 2 * 3600
}

/// 需要留意的事件摘要（規格 03；不含精確地址）
struct WidgetEventSummary: Codable {
    let title: String
    let isOfficial: Bool
    let approximateDistanceMeters: Int?
}

struct WidgetSnapshot: Codable {
    let generatedAt: Date
    /// 主要生活圈名稱與提醒半徑（規格 01 的表頭：「住家 · 1 km」）
    let circleName: String
    let radiusMeters: Int
    /// 生活圈提醒範圍內、官方確認的進行中事件數
    let attentionCount: Int
    /// 最需要留意的一件（依距離排序取最近）
    let topEvent: WidgetEventSummary?
}
