import Foundation
import SwiftData

/// 區域型警報（地震、颱風、豪雨特報）。
/// 台灣最重要的災害多半不是點狀事件——這類警報以行政區為單位發布，
/// 套不進「事件點＋半徑」模型，所以需要獨立的資料層。
@Model
final class RegionAlert {
    @Attribute(.unique) var alertKey: String
    var title: String
    /// 警報種類（颱風、地震、豪雨…）
    var kind: String
    var affectedDistricts: [String]
    var severity: String
    /// 應變建議（顯示在警報詳情與通知內文）
    var guidance: String
    var sourceName: String
    var sourceURL: String
    var issuedAt: Date
    var updatedAt: Date
    var expiresAt: Date
    var status: String = EventStatus.active.rawValue

    init(
        alertKey: String,
        title: String,
        kind: String,
        affectedDistricts: [String],
        severity: String,
        guidance: String,
        sourceName: String,
        sourceURL: String,
        issuedAt: Date = .now,
        expiresAt: Date
    ) {
        self.alertKey = alertKey
        self.title = title
        self.kind = kind
        self.affectedDistricts = affectedDistricts
        self.severity = severity
        self.guidance = guidance
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.issuedAt = issuedAt
        self.updatedAt = issuedAt
        self.expiresAt = expiresAt
    }
}

extension RegionAlert {
    var isEnded: Bool {
        status == EventStatus.resolved.rawValue || expiresAt <= .now
    }

    var statusText: String {
        isEnded ? EventStatus.resolved.rawValue : EventStatus.active.rawValue
    }

    /// 受影響的生活圈（以行政區比對）
    func matchedCircles(members: [LocalFamilyMember]) -> [(memberName: String, circleName: String)] {
        members.flatMap { member in
            member.lifeCircles
                .filter { affectedDistricts.contains($0.district) }
                .map { (member.name, $0.name) }
        }
    }
}
