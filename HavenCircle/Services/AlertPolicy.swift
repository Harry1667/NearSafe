import Foundation
import CoreLocation

struct CircleMatch {
    let memberName: String
    let circleName: String
    /// 概略距離（取整到百公尺，避免暴露精確位置）
    let distanceMeters: Int
    let withinSchedule: Bool
    /// 命中的圈屬於本人＝通知帶「回報我平安」；屬於其他家人＝帶「詢問是否平安」
    let isCurrentUser: Bool
    /// 地點類成員（倉庫等）不會回報平安，不掛互動按鈕
    let isPlace: Bool
}

/// 提醒決策結果。reason 直接顯示給使用者——「每則通知都能看見為何收到」
struct AlertDecision {
    let shouldPush: Bool
    let matches: [CircleMatch]
    let reason: String
}

/// 分級提醒的單一決策點：所有「要不要推播」的判斷都集中在這裡，
/// 才能保證產品守則（未驗證線索不推播、時段外不打擾）處處一致。
enum AlertPolicy {
    static func evaluate(
        event: LocalSafetyEvent,
        members: [LocalFamilyMember],
        at date: Date = .now
    ) -> AlertDecision {
        let point = CLLocation(latitude: event.latitude, longitude: event.longitude)
        var matches: [CircleMatch] = []

        for member in members {
            for circle in member.lifeCircles {
                guard circle.isActiveForAlerts else { continue }
                guard circle.alertTypes.contains(event.eventType) else { continue }
                let distance = point.distance(
                    from: CLLocation(latitude: circle.latitude, longitude: circle.longitude)
                )
                // 交集判定：事件影響圈（災型影響半徑＋位置精度緩衝）碰到警戒圈就算命中。
                // 車禍只掃一個路口、火災濃煙波及上千公尺——影響半徑依災型而異，可遠端調參
                let impactMeters = RemoteConfig.impactRadiusMeters(for: event.eventType)
                guard distance <= Double(circle.radiusMeters + event.precisionMeters + impactMeters) else { continue }
                matches.append(CircleMatch(
                    memberName: member.name,
                    circleName: circle.name,
                    distanceMeters: max(Int(distance / 100) * 100, 100),
                    withinSchedule: circle.isWithinSchedule(at: date),
                    isCurrentUser: member.isCurrentUser,
                    isPlace: member.isPlace
                ))
            }
        }

        guard !matches.isEmpty else {
            return AlertDecision(shouldPush: false, matches: [], reason: "事件不在任何有效警戒圈的提醒範圍內")
        }
        guard event.isOfficiallyConfirmed else {
            return AlertDecision(shouldPush: false, matches: matches, reason: "未驗證線索僅在 App 內顯示，不會推播")
        }
        let inSchedule = matches.filter(\.withinSchedule)
        guard let best = inSchedule.min(by: { $0.distanceMeters < $1.distanceMeters }) else {
            return AlertDecision(shouldPush: false, matches: matches, reason: "相關警戒圈都在提醒時段外，僅在 App 內顯示")
        }
        return AlertDecision(
            shouldPush: true,
            matches: matches,
            reason: "事件位於\(best.memberName)的「\(best.circleName)」警戒圈約 \(best.distanceMeters) 公尺內，\(event.trustStatus)"
        )
    }
}
