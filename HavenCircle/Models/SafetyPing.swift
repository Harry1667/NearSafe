import Foundation

/// 安否狀態（安否回報的核心）
enum SafetyStatus: String, CaseIterable {
    case safe = "我平安"
    case needHelp = "需要協助"

    var systemImage: String {
        switch self {
        case .safe: "checkmark.circle.fill"
        case .needHelp: "exclamationmark.circle.fill"
        }
    }
}

/// 一則安否回報。透過 CloudKit 共享 zone 在家人之間同步。
/// 這是「事件 → 我 → 家人 → 回報」雙向閉環的回報端。
struct SafetyPing: Identifiable {
    let id: String
    let senderName: String
    let status: SafetyStatus
    let note: String
    let createdAt: Date
    /// 已讀這則回報的家人名稱（已讀回條）
    let readBy: [String]
    /// 回報者「自願附上」的當下位置（nil＝沒附）。這不是追蹤——
    /// 位置只在按下回報的那一刻取得一次，由回報者自己決定要不要附
    let latitude: Double?
    let longitude: Double?
    /// 位置的可讀描述（回報端反向地理編碼一次，例「台北市信義區」），家人不用看座標
    let placeName: String?

    var hasLocation: Bool { latitude != nil && longitude != nil }

    /// CloudKit 記錄類型與欄位名（集中定義，避免字串散落）
    enum Field {
        static let recordType = "SafetyPing"
        static let senderName = "senderName"
        static let status = "status"
        static let note = "note"
        static let createdAt = "createdAt"
        static let readBy = "readBy"
        static let latitude = "latitude"
        static let longitude = "longitude"
        static let placeName = "placeName"
    }
}
