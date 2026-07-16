import SwiftUI
import SwiftData
import UserNotifications

/// 演練模式：讓使用者在平時就確認「整條通知管線真的會動」。
/// 安全類產品的信任必須在真的出事之前建立。
struct DrillView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var members: [LocalFamilyMember]
    @Query(filter: #Predicate<LocalSafetyEvent> { $0.isDrill }) private var drillEvents: [LocalSafetyEvent]
    @AppStorage(SettingsKeys.alertsEnabled) private var alertsEnabled = true
    @AppStorage(SettingsKeys.alertsPaused) private var paused = false
    @State private var permission: UNAuthorizationStatus?
    @State private var lastDecision: AlertDecision?
    @State private var showManualEditor = false

    private var activeDrill: LocalSafetyEvent? {
        drillEvents.first { !$0.isEnded }
    }

    var body: some View {
        NavigationStack {
            List {
                checklistSection
                drillSection
                advancedSection
            }
            .navigationTitle("通知演練")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .task { permission = await NotificationScheduler.authorizationStatus() }
            .sheet(isPresented: $showManualEditor) { EventEditorView() }
        }
    }

    private var checklistSection: some View {
        Section("演練前檢查") {
            ChecklistRow(
                ok: permission == .authorized,
                okText: "通知權限已允許",
                problemText: permission == nil ? "檢查通知權限中…" : "尚未允許通知——演練通知發不出去"
            )
            if permission != .authorized {
                Button("允許通知") {
                    Task {
                        _ = await NotificationScheduler.requestPermission()
                        permission = await NotificationScheduler.authorizationStatus()
                    }
                }
            }
            ChecklistRow(ok: alertsEnabled, okText: "本機提醒已啟用", problemText: "本機提醒已關閉（設定頁可開啟）")
            ChecklistRow(ok: !paused, okText: "提醒未暫停", problemText: "提醒暫停中——演練通知不會發出")
            ChecklistRow(
                ok: !members.flatMap(\.lifeCircles).isEmpty,
                okText: "已設定 \(members.flatMap(\.lifeCircles).count) 個生活圈",
                problemText: "尚未設定任何生活圈"
            )
        }
    }

    private var drillSection: some View {
        Section("演練") {
            if let drill = activeDrill {
                VStack(alignment: .leading, spacing: 4) {
                    Text("演練事件進行中：\(drill.title)").font(.subheadline.bold())
                    if let lastDecision {
                        Text(lastDecision.shouldPush
                             ? "已發送演練通知：\(lastDecision.reason)"
                             : "未發送通知：\(lastDecision.reason)")
                            .font(.caption)
                            .foregroundStyle(lastDecision.shouldPush ? HCColor.safe : HCColor.attention)
                    }
                }
                Button("結束演練（發送解除通知）") {
                    Task { await endDrill(drill) }
                }
            } else {
                Button("開始演練", systemImage: "bell.and.waves.left.and.right") {
                    Task { await startDrill() }
                }
                Text("會在你的第一個生活圈附近產生一個模擬事件，走完整的「判斷 → 推播 → 解除」流程。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lastDecision {
                    Text(lastDecision.shouldPush
                         ? "上次演練已發送通知：\(lastDecision.reason)"
                         : "上次演練未發送通知：\(lastDecision.reason)")
                        .font(.caption)
                        .foregroundStyle(lastDecision.shouldPush ? HCColor.safe : HCColor.attention)
                }
            }
            if !drillEvents.isEmpty {
                Button("清除演練資料", role: .destructive) {
                    drillEvents.forEach { context.delete($0) }
                    context.saveReporting()
                    lastDecision = nil
                }
            }
        }
    }

    private var advancedSection: some View {
        Section("進階") {
            Button("手動新增測試事件") { showManualEditor = true }
            Text("手動事件可自訂類型與可信度，用來測試提醒決策的各種情境。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func startDrill() async {
        guard let circle = members.flatMap(\.lifeCircles).first else { return }
        // 模擬事件放在生活圈中心往北約 300 公尺處，確保會命中提醒範圍
        let event = LocalSafetyEvent(
            eventKey: "drill-\(UUID().uuidString)",
            title: "模擬火警通報",
            eventType: circle.alertTypes.first ?? EventCategory.fire,
            approximateLocation: "\(circle.name)附近（演練）",
            latitude: circle.latitude + 0.003,
            longitude: circle.longitude,
            precisionMeters: 300,
            sourceName: "安心圈演練系統",
            sourceURL: "https://example.com/drill",
            trustStatus: TrustStatus.officialConfirmed,
            severity: "需要注意",
            deduplicationGroup: "drill",
            expiresAt: .now.addingTimeInterval(3_600),
            isDrill: true
        )
        context.insert(event)
        context.saveReporting()
        lastDecision = await NotificationScheduler.notifyIfNeeded(for: event, members: members)
    }

    private func endDrill(_ drill: LocalSafetyEvent) async {
        drill.resolve()
        context.saveReporting()
        await NotificationScheduler.notifyResolved(for: drill)
    }
}

private struct ChecklistRow: View {
    let ok: Bool
    let okText: String
    let problemText: String

    var body: some View {
        Label {
            Text(ok ? okText : problemText)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? HCColor.safe : HCColor.attention)
        }
    }
}

#Preview {
    DrillView()
        .modelContainer(PreviewSupport.container())
}
