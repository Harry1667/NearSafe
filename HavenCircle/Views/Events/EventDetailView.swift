import SwiftUI
import SwiftData
import UIKit

struct EventDetailView: View {
    let event: LocalSafetyEvent
    let members: [LocalFamilyMember]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var unrelated = false

    var body: some View {
        NavigationStack {
            List {
                statusSection
                infoSection
                sourceSection
                actionSection
            }
            .navigationTitle(event.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var statusSection: some View {
        Section {
            Label(
                event.trustStatus,
                systemImage: event.isOfficiallyConfirmed ? "checkmark.seal.fill" : "clock.badge.questionmark"
            )
            .foregroundStyle(event.isOfficiallyConfirmed ? .red : .orange)
            Text(event.isOfficiallyConfirmed
                 ? "官方來源已確認。若有立即危險，請直接撥打 110 或 119。"
                 : "資料仍在確認中，不會自動通知家人。")
        }
    }

    private var infoSection: some View {
        Section("事件資訊") {
            LabeledContent("類型", value: event.eventType)
            LabeledContent("概略位置", value: event.approximateLocation)
            LabeledContent("影響範圍", value: relativeDistance(event, members))
            LabeledContent("嚴重程度", value: event.severity)
            LabeledContent("位置精準度", value: "約 \(event.precisionMeters) 公尺")
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
            Button("標記為已結束") {
                event.expiresAt = .now
                context.saveReporting()
                dismiss()
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
