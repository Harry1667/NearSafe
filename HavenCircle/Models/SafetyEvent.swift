import Foundation
import SwiftData

/// 可信度狀態（對外顯示一律用文字說明，不能只靠顏色）
enum TrustStatus {
    static let officialConfirmed = "官方已確認"
    static let crossVerified = "多來源交叉驗證"
    static let confirming = "持續確認中"
}

/// 事件生命週期狀態機：進行中 → 已解除（解除時發送解除通知，關閉使用者的焦慮迴圈）
enum EventStatus: String {
    case active = "進行中"
    case resolved = "已解除"
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
    /// 生命週期狀態（EventStatus 的 rawValue；新欄位給預設值以支援輕量遷移）
    var status: String = EventStatus.active.rawValue
    /// 演練模式產生的模擬事件
    var isDrill: Bool = false
    /// 已封存（過期後保留供歷史回顧，不再出現在提醒中心）
    var isArchived: Bool = false

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
        expiresAt: Date,
        status: EventStatus = .active,
        isDrill: Bool = false
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
        self.status = status.rawValue
        self.isDrill = isDrill
    }
}

extension LocalSafetyEvent {
    /// 只有官方來源或多來源交叉驗證的事件才允許推播（產品守則）
    var isOfficiallyConfirmed: Bool {
        trustStatus == TrustStatus.officialConfirmed || trustStatus == TrustStatus.crossVerified
    }

    var isExpired: Bool { expiresAt <= .now }

    var isResolved: Bool { status == EventStatus.resolved.rawValue }

    /// 提醒中心「已結束」分類：使用者標記解除、或已過期
    var isEnded: Bool { isResolved || isExpired }

    /// 對使用者顯示的狀態文字（不能只靠顏色）
    var statusText: String { isEnded ? EventStatus.resolved.rawValue : EventStatus.active.rawValue }

    /// 標記為已解除（呼叫端負責存檔與發送解除通知）
    func resolve() {
        status = EventStatus.resolved.rawValue
        updatedAt = .now
    }
}
