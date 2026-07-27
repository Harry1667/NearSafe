import Foundation
import CoreLocation
import SwiftData
import WidgetKit

/// 把主 App 的安全狀態壓成 Widget 快照寫進 App Group，並請 WidgetKit 重載。
/// 呼叫時機：資料管線每次刷新結束（Widget 自己不做網路請求，離線也能呈現最後狀態）。
enum WidgetSnapshotWriter {
    static func refresh(context: ModelContext) {
        guard let url = WidgetShared.snapshotURL else {
            // App Group 未佈建（例如免費帳號簽章）時安靜跳過，不影響主功能
            return
        }
        let members = (try? context.fetch(FetchDescriptor<LocalFamilyMember>())) ?? []
        let events = (try? context.fetch(FetchDescriptor<LocalSafetyEvent>())) ?? []
        let circles = members.flatMap(\.lifeCircles)
        // Widget 只呈現使用者保存的固定地點，不放家人位置或移動軌跡。
        guard let primary = circles.first(where: { $0.kind == .fixed }) else { return }

        // 「需要留意」＝官方確認、進行中、且 AlertPolicy 判定命中任一警戒圈。
        // 必須與 App 內用同一個判定式（含災型影響半徑），否則會出現
        // 「App 紅盾、小工具卻說平安」的矛盾（實機回報過的 bug）
        let attention = events
            .filter { $0.isActiveForAwareness && !$0.isArchived && $0.isOfficiallyConfirmed }
            .filter { !AlertPolicy.evaluate(event: $0, members: members).matches.isEmpty }
            .sorted { distance(from: $0, to: primary) < distance(from: $1, to: primary) }

        let eventSummaries = attention.prefix(3).map { event in
            WidgetEventSummary(
                title: event.title,
                isOfficial: event.isOfficiallyConfirmed,
                approximateDistanceMeters: roundedDistance(from: event, to: primary),
                approximateLocation: event.approximateLocation,
                latitude: event.latitude,
                longitude: event.longitude
            )
        }
        let snapshot = WidgetSnapshot(
            generatedAt: .now,
            circleName: primary.name,
            radiusMeters: primary.radiusMeters,
            circleKind: primary.kind.rawValue,
            circleUpdatedAt: primary.locationUpdatedAt,
            circleLatitude: primary.latitude,
            circleLongitude: primary.longitude,
            attentionCount: attention.count,
            topEvent: eventSummaries.first,
            events: Array(eventSummaries)
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: url, options: .atomic)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.widgetKind)
        } catch {
            AppLog.dataError("Widget 快照寫入失敗：\(error.localizedDescription)")
        }
    }

    private static func distance(from event: LocalSafetyEvent, to circle: LocalLifeCircle) -> Double {
        CLLocation(latitude: event.latitude, longitude: event.longitude)
            .distance(from: CLLocation(latitude: circle.latitude, longitude: circle.longitude))
    }

    /// 距離只取到百公尺，避免 Widget 暴露不必要的精度。
    private static func roundedDistance(from event: LocalSafetyEvent, to circle: LocalLifeCircle) -> Int {
        max(Int(distance(from: event, to: circle) / 100) * 100, 100)
    }
}
