import Foundation
import SwiftData

@Model
final class LocalFamilyMember {
    @Attribute(.unique) var memberKey: String
    var name: String
    var relationship: String
    var createdAt: Date
    /// "person"＝家人；"place"＝獨立重要地點（如老家）。
    /// 地點重用 member+circle 結構：警報比對與地圖渲染都走 members.flatMap(\.lifeCircles)，
    /// 拆新 model 得改兩套邏輯，加 kind 欄位一行都不用動（有預設值，SwiftData 輕量遷移安全）
    var kind: String = "person"
    /// 本裝置的使用者；即時圈只能由本人裝置開啟，不能替別人代開定位分享。
    var isCurrentUser: Bool = false
    /// 家人裝置在 CKShare 中的匿名識別碼，用於把共享位置穩定對應到本機家人資料。
    var sharedIdentityKey: String?
    @Relationship(deleteRule: .cascade, inverse: \LocalLifeCircle.member)
    var lifeCircles: [LocalLifeCircle] = []

    init(memberKey: String = UUID().uuidString, name: String, relationship: String, kind: String = "person") {
        self.memberKey = memberKey
        self.name = name
        self.relationship = relationship
        self.createdAt = .now
        self.kind = kind
    }
}

extension LocalFamilyMember {
    var isPlace: Bool { kind == "place" }
}
