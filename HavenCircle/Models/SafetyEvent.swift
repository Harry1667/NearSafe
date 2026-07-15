import Foundation
import SwiftData

/// 可信度狀態（對外顯示一律用文字說明，不能只靠顏色）
enum TrustStatus {
    static let officialConfirmed = "官方已確認"
    static let crossVerified = "多來源交叉驗證"
    static let confirming = "持續確認中"
}

@Model
final class LocalSafetyEvent {
    @Attribute(.unique) var eventKey: String
    var title: String
    var eventType: String
    var occurredAt: Date
    var updatedAt: Date
    /// 概略位置描述；對外不顯示精確地址
    var approximateLocation: String
    var latitude: Double
    var longitude: Double
    /// 位置精準度（公尺）
    var precisionMeters: Int
    var sourceName: String
    var sourceURL: String
    var trustStatus: String
    var severity: String
    /// 相似事件去重群組
    var deduplicationGroup: String
    var expiresAt: Date

    init(
        eventKey: String,
        title: String,
        eventType: String,
        occurredAt: Date = .now,
        updatedAt: Date = .now,
        approximateLocation: String,
        latitude: Double,
        longitude: Double,
        precisionMeters: Int,
        sourceName: String,
        sourceURL: String,
        trustStatus: String,
        severity: String,
        deduplicationGroup: String,
        expiresAt: Date
    ) {
        self.eventKey = eventKey
        self.title = title
        self.eventType = eventType
        self.occurredAt = occurredAt
        self.updatedAt = updatedAt
        self.approximateLocation = approximateLocation
        self.latitude = latitude
        self.longitude = longitude
        self.precisionMeters = precisionMeters
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.trustStatus = trustStatus
        self.severity = severity
        self.deduplicationGroup = deduplicationGroup
        self.expiresAt = expiresAt
    }
}

extension LocalSafetyEvent {
    /// 只有官方來源或多來源交叉驗證的事件才允許推播（產品守則）
    var isOfficiallyConfirmed: Bool {
        trustStatus == TrustStatus.officialConfirmed || trustStatus == TrustStatus.crossVerified
    }

    var isExpired: Bool { expiresAt <= .now }
}
