import SwiftUI
import SwiftData
import UIKit

struct EventDetailView: View {
    let event: LocalSafetyEvent
    let members: [LocalFamilyMember]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showResolveConfirmation = false

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
                resourceSection
                actionSection
            }
            .navigationTitle(event.isDrill ? "【演練】\(event.title)" : event.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .confirmationDialog("將這則事件標記為本機已解除？", isPresented: $showResolveConfirmation) {
                Button("確認標記", role: .destructive) { resolveLocally() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("這只會更新此裝置的顯示與解除通知，不會改變官方來源。")
            }
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
            .foregroundStyle(event.isEnded ? Color.secondary : (event.isOfficiallyConfirmed ? HCColor.danger : HCColor.attention))
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
            LabeledContent("發生時間", value: localizedDate(event.occurredAt))
            LabeledContent("最近更新", value: localizedDate(event.updatedAt))
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

    /// 事件「發生後怎麼辦」：離事件最近的避難收容所與急救責任醫院＋一鍵導航。
    /// 座標全數來自政府開放資料官方欄位（消防署／衛福部＋國土測繪中心），未自行 geocode——
    /// 導航目的地的正確性是安全產品的誠信底線。
    private var resourceSection: some View {
        Section("緊急應變") {
            resourceRow(kind: ResourceKind.shelter)
            resourceRow(kind: ResourceKind.hospital)
            Text("有立即危險時請勿等待 App 指引：直接撥打 119（火災、救護）或 110（治安）。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("資料來源：內政部消防署避難收容處所、衛福部急救責任醫院名單。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func resourceRow(kind: String) -> some View {
        if let nearest = EmergencyResourceStore.nearest(
            kind: kind, latitude: event.latitude, longitude: event.longitude
        ) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(kind)：\(nearest.resource.name)").font(.subheadline)
                    Text("約 \(formattedDistance(nearest.distanceMeters)) · \(nearest.resource.district)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("導航", systemImage: "arrow.triangle.turn.up.right.circle") {
                    openInMaps(nearest.resource)
                }
                .font(.caption)
            }
        }
    }

    private func formattedDistance(_ meters: Int) -> String {
        meters >= 1000
            ? String(format: "%.1f 公里", Double(meters) / 1000)
            : "\(max(meters / 100 * 100, 100)) 公尺"
    }

    private func openInMaps(_ resource: EmergencyResource) {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "daddr", value: "\(resource.latitude),\(resource.longitude)"),
            URLQueryItem(name: "q", value: resource.name),
        ]
        if let url = components?.url {
            UIApplication.shared.open(url)
        }
    }

    private var actionSection: some View {
        Section {
            Button("隱藏此裝置的相似提醒", systemImage: "hand.thumbsdown") {
                EventVisibility.suppressSimilar(to: event)
                dismiss()
            }
            if !event.isEnded {
                Button("回報此事件在我這裡已解除") {
                    showResolveConfirmation = true
                }
            }
            Button("人身安全或犯罪請撥 110", systemImage: "phone.fill") {
                call("110")
            }
            .foregroundStyle(HCColor.danger)
            Button("火災或緊急救護請撥 119", systemImage: "cross.case.fill") {
                call("119")
            }
            .foregroundStyle(HCColor.danger)
        }
    }

    private func resolveLocally() {
        event.resolve()
        context.saveReporting()
        Task { await NotificationScheduler.notifyResolved(for: event) }
        dismiss()
    }

    private func call(_ number: String) {
        guard let tel = URL(string: "tel://\(number)") else { return }
        UIApplication.shared.open(tel)
    }

    private func localizedDate(_ date: Date) -> String {
        date.formatted(.dateTime.locale(Locale(identifier: "zh_TW")).year().month().day().hour().minute())
    }
}
