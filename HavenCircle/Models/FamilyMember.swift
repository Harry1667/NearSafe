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
