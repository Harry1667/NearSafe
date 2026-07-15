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

    /// CloudKit 記錄類型與欄位名（集中定義，避免字串散落）
    enum Field {
        static let recordType = "SafetyPing"
        static let senderName = "senderName"
        static let status = "status"
        static let note = "note"
        static let createdAt = "createdAt"
        static let readBy = "readBy"
    }
}
