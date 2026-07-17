import Foundation

/// 家庭 CKShare 中每台裝置最新的一筆位置快照。
/// 「即時」代表位置變動後近即時同步；畫面必須同時顯示 updatedAt，不能暗示秒級連續追蹤。
struct FamilyLiveLocation: Identifiable, Equatable {
    let id: String
    let participantID: String
    let displayName: String
    let latitude: Double
    let longitude: Double
    let radiusMeters: Int
    let district: String
    let updatedAt: Date
    let isSharing: Bool

    var isFresh: Bool {
        isSharing && updatedAt > Date.now.addingTimeInterval(-15 * 60)
    }

    var freshnessText: String {
        guard isSharing else { return "已停止分享" }
        guard isFresh else { return "位置已過期" }
        return "\(updatedAt.formatted(.relative(presentation: .named)))更新"
    }

    enum Field {
        static let recordType = "FamilyLiveLocation"
        static let participantID = "participantID"
        static let displayName = "displayName"
        static let latitude = "latitude"
        static let longitude = "longitude"
        static let radiusMeters = "radiusMeters"
        static let district = "district"
        static let updatedAt = "updatedAt"
        static let isSharing = "isSharing"
    }
}
