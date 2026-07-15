import SwiftUI
import SwiftData

/// 手動新增測試事件（僅供 MVP 測試；上線前應接正式資料來源）
struct EventEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var members: [LocalFamilyMember]
    @State private var title = ""
    @State private var type = EventCategory.fire
    @State private var location = "台北市"
    @State private var source = "手動測試"
    @State private var official = true

    var body: some View {
        NavigationStack {
            Form {
                TextField("事件名稱", text: $title)
                Picker("類型", selection: $type) {
                    ForEach(EventCategory.all, id: \.self) { Text($0) }
                }
                TextField("概略位置", text: $location)
                TextField("來源名稱", text: $source)
                Toggle("官方已確認", isOn: $official)
                Text("手動新增僅供 MVP 測試；上線前應接正式資料來源。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("新增測試事件")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let event = LocalSafetyEvent(
            eventKey: UUID().uuidString,
            title: title.isEmpty ? "測試事件" : title,
            eventType: type,
            approximateLocation: location,
            latitude: 25.035,
            longitude: 121.54,
            precisionMeters: 800,
            sourceName: source,
            sourceURL: "https://www.apple.com",
            trustStatus: official ? TrustStatus.officialConfirmed : TrustStatus.confirming,
            severity: official ? "需要注意" : "持續確認中",
            deduplicationGroup: UUID().uuidString,
            expiresAt: .now.addingTimeInterval(86_400)
        )
        context.insert(event)
        context.saveReporting()
        DataFreshness.markRefreshedNow()
        // 走正式的提醒決策管線：不在生活圈內或未驗證的事件不會推播（與正式資料流一致）
        Task {
            await NotificationScheduler.notifyIfNeeded(for: event, members: members)
        }
        dismiss()
    }
}
