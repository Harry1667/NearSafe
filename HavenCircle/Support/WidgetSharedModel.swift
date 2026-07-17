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
    let approximateLocation: String?
    let latitude: Double?
    let longitude: Double?

    init(
        title: String,
        isOfficial: Bool,
        approximateDistanceMeters: Int?,
        approximateLocation: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.title = title
        self.isOfficial = isOfficial
        self.approximateDistanceMeters = approximateDistanceMeters
        self.approximateLocation = approximateLocation
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct WidgetSnapshot: Codable {
    let generatedAt: Date
    /// 主要警戒圈名稱、類型與提醒半徑
    let circleName: String
    let radiusMeters: Int
    /// Optional 以相容尚未寫入圈類型的舊版快照；nil 視為固定地點。
    let circleKind: String?
    let circleUpdatedAt: Date?
    /// 僅供 Widget 概略地圖定位；不包含住址文字。
    let circleLatitude: Double?
    let circleLongitude: Double?
    /// 警戒圈提醒範圍內、官方確認的進行中事件數
    let attentionCount: Int
    /// 最需要留意的一件（依距離排序取最近）
    let topEvent: WidgetEventSummary?
    /// 大型 Widget 最多顯示三件。Optional 讓舊版 App Group 快照仍可解碼。
    let events: [WidgetEventSummary]?

    init(
        generatedAt: Date,
        circleName: String,
        radiusMeters: Int,
        circleKind: String?,
        circleUpdatedAt: Date?,
        circleLatitude: Double? = nil,
        circleLongitude: Double? = nil,
        attentionCount: Int,
        topEvent: WidgetEventSummary?,
        events: [WidgetEventSummary]? = nil
    ) {
        self.generatedAt = generatedAt
        self.circleName = circleName
        self.radiusMeters = radiusMeters
        self.circleKind = circleKind
        self.circleUpdatedAt = circleUpdatedAt
        self.circleLatitude = circleLatitude
        self.circleLongitude = circleLongitude
        self.attentionCount = attentionCount
        self.topEvent = topEvent
        self.events = events
    }

    var eventSummaries: [WidgetEventSummary] {
        if let events, !events.isEmpty { return events }
        return topEvent.map { [$0] } ?? []
    }
}
