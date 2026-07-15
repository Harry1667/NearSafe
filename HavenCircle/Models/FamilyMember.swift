import Foundation
import SwiftData

@Model
final class LocalFamilyMember {
    @Attribute(.unique) var memberKey: String
    var name: String
    var relationship: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \LocalLifeCircle.member)
    var lifeCircles: [LocalLifeCircle] = []

    init(memberKey: String = UUID().uuidString, name: String, relationship: String) {
        self.memberKey = memberKey
        self.name = name
        self.relationship = relationship
        self.createdAt = .now
    }
}
