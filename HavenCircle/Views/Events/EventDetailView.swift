import SwiftUI
import SwiftData
import UIKit

struct EventDetailView: View {
    let event: LocalSafetyEvent
    let members: [LocalFamilyMember]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(FamilySyncService.self) private var sync
    @AppStorage(SettingsKeys.profileDisplayName) private var profileName = ""
    @State private var showResolveConfirmation = false
    @State private var checkInFeedback: String?
    @State private var isReporting = false
    // AI 影響分析：只在使用者主動點按時才呼叫，結果存行程內快取避免重複計費
    @State private var aiImpact: String?
    @State private var aiImpactLoading = false
    @State private var aiImpactError: String?

    private var decision: AlertDecision {
        AlertPolicy.evaluate(event: event, members: members)
    }

    /// 這則事件最靠近的命中圈（決定安否按鈕要放哪一組）
    private var closestMatch: CircleMatch? {
        decision.matches.min(by: { $0.distanceMeters < $1.distanceMeters })
    }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                detailSection
                whySection
                aiImpactSection
                checkInSection
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
            .onAppear {
                // 重開同一事件時，若行程內已有分析結果就直接顯示，不再打 AI
                if aiImpact == nil { aiImpact = AIImpactCache.store[impactCacheKey] }
            }
        }
    }

    /// AI 個人化影響分析：結合這起事件與使用者的警戒圈命中狀況，說明「對我的影響」。
    /// 成本/延遲控制：僅在使用者主動點按時才呼叫；結果快取在行程內（同一事件重開不重複計費）；
    /// 用低運算強度（effort=low）壓延遲。刻意不寫進 SwiftData，避免為快取改 schema 觸發遷移風險。
    @ViewBuilder
    private var aiImpactSection: some View {
        Section {
            if let aiImpact {
                Text(aiImpact)
                    .font(.subheadline)
                    .textSelection(.enabled)
                Text("AI 生成，僅供參考，不取代官方指示；有立即危險請直接撥 119 或 110。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await runImpactAnalysis(force: true) }
                } label: {
                    Label("重新分析", systemImage: "arrow.clockwise")
                }
                .font(.caption)
                .disabled(aiImpactLoading)
            } else {
                Button {
                    Task { await runImpactAnalysis(force: false) }
                } label: {
                    HStack {
                        Label("AI 分析：這起事件對我的影響", systemImage: "sparkles")
                            .foregroundStyle(HCColor.brand)
                        if aiImpactLoading {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(aiImpactLoading)
            }
            if let aiImpactError {
                Text(aiImpactError)
                    .font(.caption)
                    .foregroundStyle(HCColor.danger)
            }
        } header: {
            Text("AI 影響分析")
        } footer: {
            if aiImpact == nil && !aiImpactLoading {
                Text("依你設定的警戒圈與這起事件的位置、類型，產生個人化的影響說明。")
            }
        }
    }

    /// 這起事件在行程內快取的鍵：以事件本身＋命中圈的簽章組合，
    /// 圈設定改變（距離/時段/成員）時 key 就變，會重新分析而非給舊結果。
    private var impactCacheKey: String {
        let signature = decision.matches
            .map { "\($0.memberName):\($0.circleName):\($0.distanceMeters):\($0.withinSchedule)" }
            .joined(separator: ",")
        return "\(event.eventType)|\(Int(event.occurredAt.timeIntervalSince1970))|\(event.approximateLocation)|\(signature)"
    }

    /// 組給 AI 的提示詞：只帶「概略」位置與距離（已取整到百公尺），不外洩精確座標。
    private var impactPrompt: String {
        var lines: [String] = [
            "你是台灣的防災助理。根據以下災害事件與使用者的守護設定，用繁體中文寫一段 100–150 字的「這起事件對我的影響」個人化說明。",
            "要求：具體、冷靜、不誇大；聚焦(1)是否可能影響到使用者或其家人／據點(2)建議的下一步（留意／遠離／聯繫家人）。若有立即危險請提醒直接撥 119 或 110，不要提供其他電話號碼。不要重複事件標題，直接輸出說明本文、不要開場白。",
            "",
            "【事件】",
            "類型：\(event.eventType)",
            "概略位置：\(event.approximateLocation)",
            "發生時間：\(localizedDate(event.occurredAt))",
            "嚴重程度：\(event.severity)",
            "狀態：\(event.isOfficiallyConfirmed ? "官方已確認" : "未驗證線索，仍在確認中")",
        ]
        if let detail = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
            lines.append("說明：\(detail)")
        }
        lines.append("")
        lines.append("【我的守護設定】")
        if decision.matches.isEmpty {
            lines.append("目前沒有任何警戒圈直接落在事件影響範圍內，但使用者仍在關注此類事件。")
        } else {
            for match in decision.matches {
                let who = match.isCurrentUser ? "我" : match.memberName
                let schedule = match.withinSchedule ? "提醒時段內" : "提醒時段外"
                lines.append("- \(who)的「\(match.circleName)」約 \(match.distanceMeters) 公尺（\(schedule)）")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func runImpactAnalysis(force: Bool) async {
        // 非強制且已有快取：直接用，不計費
        if !force, let cached = AIImpactCache.store[impactCacheKey] {
            aiImpact = cached
            return
        }
        aiImpactLoading = true
        aiImpactError = nil
        defer { aiImpactLoading = false }
        do {
            let result = try await AIService.complete(prompt: impactPrompt, effort: "low")
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            aiImpact = trimmed
            AIImpactCache.store[impactCacheKey] = trimmed
        } catch {
            aiImpactError = "分析失敗：\(error.localizedDescription)"
            AppLog.cloudError("AI 影響分析失敗：\(error.localizedDescription)")
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
                     : "這是未驗證線索，資料仍在確認中，不會自動通知家人。")
            }
        }
    }

    /// AI 整理的詳細描述：新聞事件是爬蟲 LLM 產的白話說明、官方事件是政府原始 description。
    /// 只在有內容時顯示；空的舊資料不佔版面（詳情頁其他區塊仍完整）。
    @ViewBuilder
    private var detailSection: some View {
        if let detail = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
            Section("事件說明") {
                Text(detail)
                    .font(.subheadline)
                    .textSelection(.enabled)
                Text(event.isOfficiallyConfirmed
                     ? "以上為官方發布內容。"
                     : "以上為新聞來源經整理後的說明，非官方確認資訊。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 「每則通知都能看見為何收到」——直接顯示 AlertPolicy 的決策理由
    private var whySection: some View {
        Section("提醒判斷") {
            Text(decision.reason)
                .font(.subheadline)
            ForEach(decision.matches, id: \.circleName) { match in
                LabeledContent("\(match.isCurrentUser ? "我" : match.memberName)・\(match.circleName)") {
                    Text("約 \(match.distanceMeters) 公尺\(match.withinSchedule ? "" : "（時段外）")")
                }
                .font(.caption)
            }
        }
    }

    /// 安否操作：與通知按鈕同一套「主角」邏輯，讓錯過通知的人也能在詳情頁快速回報。
    /// 我的圈→回報平安/尚未脫離危險；家人的圈→詢問對方是否平安；地點類（倉庫）→不顯示。
    @ViewBuilder
    private var checkInSection: some View {
        if !event.isEnded, let match = closestMatch, !match.isPlace {
            Section("安否") {
                if match.isCurrentUser {
                    Button {
                        report(.safe)
                    } label: {
                        Label("回報我平安", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(HCColor.safe)
                    }
                    Button {
                        report(.inDanger)
                    } label: {
                        Label("尚未脫離危險", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(HCColor.danger)
                    }
                } else {
                    Button {
                        report(.pleaseReport)
                    } label: {
                        Label("詢問\(match.memberName)是否平安", systemImage: "questionmark.circle.fill")
                            .foregroundStyle(HCColor.brand)
                    }
                }
                if let checkInFeedback {
                    Label(checkInFeedback, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(HCColor.safe)
                }
            }
            .disabled(isReporting)
        }
    }

    private func report(_ status: SafetyStatus) {
        isReporting = true
        let senderName = profileName.trimmingCharacters(in: .whitespaces).isEmpty ? "我" : profileName
        Task {
            await sync.postPing(
                senderName: senderName,
                status: status,
                note: status == .pleaseReport ? "從事件詳情發起平安確認" : "從事件詳情回報"
            )
            checkInFeedback = status == .pleaseReport ? "已送出確認請求" : "已送出回報"
            isReporting = false
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

/// 事件 AI 影響分析的行程內快取：同一事件重開不重複計費（重啟 App 即清空）。
/// 刻意不落地到 SwiftData——避免為快取欄位改 @Model schema 觸發遷移風險（見 LESSONS）。
@MainActor
enum AIImpactCache {
    static var store: [String: String] = [:]
}
