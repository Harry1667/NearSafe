import Foundation
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
        guard let primary = circles.first else { return } // 尚未完成新手設定

        // 「需要留意」＝官方確認、進行中、落在任一生活圈提醒範圍（與提醒中心同一判準）
        let attention = events
            .filter { !$0.isEnded && !$0.isArchived && $0.isOfficiallyConfirmed }
            .filter { !AlertPolicy.evaluate(event: $0, members: members).matches.isEmpty }
            .sorted { nearestCircleDistance($0, members) < nearestCircleDistance($1, members) }

        let topEvent = attention.first.map { event in
            WidgetEventSummary(
                title: event.title,
                isOfficial: event.isOfficiallyConfirmed,
                approximateDistanceMeters: Int(nearestCircleDistance(event, members))
            )
        }
        let snapshot = WidgetSnapshot(
            generatedAt: .now,
            circleName: primary.name,
            radiusMeters: primary.radiusMeters,
            attentionCount: attention.count,
            topEvent: topEvent
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
}
