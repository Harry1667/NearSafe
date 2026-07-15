import SwiftUI
import SwiftData
import UIKit

struct EventDetailView: View {
    let event: LocalSafetyEvent
    let members: [LocalFamilyMember]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var unrelated = false

    private var decision: AlertDecision {
        AlertPolicy.evaluate(event: event, members: members)
    }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                whySection
                infoSection
                sourceSection
                actionSection
            }
            .navigationTitle(event.isDrill ? "【演練】\(event.title)" : event.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var statusSection: some View {
        Section {
            Label(
                "\(event.statusText)・\(event.trustStatus)",
                systemImage: event.isEnded
                    ? "checkmark.circle"
                    : (event.isOfficiallyConfirmed ? "checkmark.seal.fill" : "clock.badge.questionmark")
            )
            .foregroundStyle(event.isEnded ? Color.secondary : (event.isOfficiallyConfirmed ? Color.red : Color.orange))
            if event.isEnded {
                Text("此事件已結束，無需進一步行動。")
            } else {
                Text(event.isOfficiallyConfirmed
                     ? "官方來源已確認。若有立即危險，請直接撥打 110 或 119。"
                     : "資料仍在確認中，不會自動通知家人。")
            }
        }
    }

    /// 「每則通知都能看見為何收到」——直接顯示 AlertPolicy 的決策理由
    private var whySection: some View {
        Section("提醒判斷") {
            Text(decision.reason)
                .font(.subheadline)
            ForEach(decision.matches, id: \.circleName) { match in
                LabeledContent("\(match.memberName)・\(match.circleName)") {
                    Text("約 \(match.distanceMeters) 公尺\(match.withinSchedule ? "" : "（時段外）")")
                }
                .font(.caption)
            }
        }
    }

    private var infoSection: some View {
        Section("事件資訊") {
            LabeledContent("類型", value: event.eventType)
            LabeledContent("概略位置", value: event.approximateLocation)
            LabeledContent("嚴重程度", value: event.severity)
            LabeledContent("位置精準度", value: "約 \(event.precisionMeters) 公尺")
            LabeledContent("發生時間", value: event.occurredAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("最近更新", value: event.updatedAt.formatted(date: .abbreviated, time: .shortened))
        }
    }

    private var sourceSection: some View {
        Section("來源") {
            LabeledContent("資訊來源", value: event.sourceName)
            if let url = URL(string: event.sourceURL) {
                Link("查看原始來源", destination: url)
            } else {
                // 來源網址格式異常時仍以文字呈現，不讓 App 因強制解包閃退
                LabeledContent("來源網址", value: event.sourceURL)
            }
        }
    }

    private var actionSection: some View {
        Section {
            Button(unrelated ? "已隱藏相似提醒" : "此事件與我無關",
                   systemImage: unrelated ? "checkmark" : "hand.thumbsdown") {
                unrelated = true
            }
            if !event.isEnded {
                Button("標記為已結束") {
                    event.resolve()
                    context.saveReporting()
                    Task { await NotificationScheduler.notifyResolved(for: event) }
                    dismiss()
                }
            }
            Button("緊急情況請撥打 119", systemImage: "phone.fill") {
                if let tel = URL(string: "tel://119") {
                    UIApplication.shared.open(tel)
                }
            }
            .foregroundStyle(.red)
        }
    }
}
