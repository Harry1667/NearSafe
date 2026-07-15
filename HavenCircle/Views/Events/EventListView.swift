import SwiftUI
import SwiftData

/// 提醒中心：按「需要注意 / 持續確認中 / 已結束」分類（對應產品規格的通知頁分類）
struct EventListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LocalSafetyEvent.occurredAt, order: .reverse) private var events: [LocalSafetyEvent]
    @Query private var members: [LocalFamilyMember]
    @Query private var regionAlerts: [RegionAlert]
    @State private var showDrill = false
    @State private var selected: LocalSafetyEvent?
    @State private var selectedAlert: RegionAlert?

    private var visibleEvents: [LocalSafetyEvent] { events.filter { !$0.isArchived } }
    /// 需要注意＝官方確認「且真的落在某個生活圈的提醒範圍」（分類標籤與邏輯必須一致）
    private var attention: [LocalSafetyEvent] {
        visibleEvents
            .filter { !$0.isEnded && $0.isOfficiallyConfirmed && isInAnyCircle($0) }
            .sorted { nearestCircleDistance($0, members) < nearestCircleDistance($1, members) }
    }
    /// 官方確認、但離所有生活圈較遠的事件另立分類，不冒充「需要注意」
    private var elsewhere: [LocalSafetyEvent] {
        visibleEvents
            .filter { !$0.isEnded && $0.isOfficiallyConfirmed && !isInAnyCircle($0) }
            .sorted { nearestCircleDistance($0, members) < nearestCircleDistance($1, members) }
    }
    private var confirming: [LocalSafetyEvent] {
        visibleEvents.filter { !$0.isEnded && !$0.isOfficiallyConfirmed }
    }
    private var ended: [LocalSafetyEvent] {
        Array(visibleEvents.filter(\.isEnded).prefix(20))
    }

    private func isInAnyCircle(_ event: LocalSafetyEvent) -> Bool {
        !AlertPolicy.evaluate(event: event, members: members).matches.isEmpty
    }

    private var activeRegionAlerts: [RegionAlert] {
        regionAlerts.filter { !$0.isEnded }
    }

    var body: some View {
        NavigationStack {
            List {
                miniMapSection
                if visibleEvents.isEmpty && activeRegionAlerts.isEmpty {
                    ContentUnavailableView("目前沒有事件", systemImage: "checkmark.shield")
                }
                regionAlertSection
                section(title: "需要注意", subtitle: "官方確認且位於生活圈提醒範圍內", items: attention)
                section(title: "持續確認中", subtitle: "資料尚未充分驗證，不會推播", items: confirming)
                section(title: "其他區域動態", subtitle: "官方事件，但離所有生活圈較遠", items: elsewhere)
                section(title: "已結束", subtitle: "已解除或已過期的事件", items: ended)
            }
            .navigationTitle("提醒中心")
            .toolbar {
                // 「回顧」已升級為獨立分頁，這裡只留演練
                Button("演練", systemImage: "bell.and.waves.left.and.right") { showDrill = true }
            }
            // 手動下拉刷新：重跑一次資料管線
            .refreshable { await EventPipeline.refresh(context: context) }
            .sheet(isPresented: $showDrill) { DrillView() }
            .sheet(item: $selected) { EventDetailView(event: $0, members: members) }
            .sheet(item: $selectedAlert) { RegionAlertDetailView(alert: $0, members: members) }
        }
    }

    /// 頂部精簡地圖：只放進行中的事件，點標記開詳情
    @ViewBuilder
    private var miniMapSection: some View {
        let active = visibleEvents.filter { !$0.isEnded }
        if !active.isEmpty {
            Section {
                EventsMiniMap(events: active, members: members) { selected = $0 }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
    }

    @ViewBuilder
    private var regionAlertSection: some View {
        if !activeRegionAlerts.isEmpty {
            Section("區域警報") {
                ForEach(activeRegionAlerts) { alert in
                    Button {
                        selectedAlert = alert
                    } label: {
                        RegionAlertBanner(alert: alert, members: members)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func section(title: String, subtitle: String, items: [LocalSafetyEvent]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { event in
                    Button {
                        selected = event
                    } label: {
                        EventRow(event: event, members: members)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { delete(at: $0, in: items) }
            } header: {
                VStack(alignment: .leading) {
                    Text("\(title)（\(items.count)）")
                    Text(subtitle).font(.caption2).textCase(nil)
                }
            }
        }
    }

    /// 刪除索引對「該分類的清單」取，不能用完整 events 陣列
    private func delete(at offsets: IndexSet, in items: [LocalSafetyEvent]) {
        for index in offsets {
            context.delete(items[index])
        }
        context.saveReporting()
    }
}

#Preview {
    EventListView()
        .modelContainer(PreviewSupport.container())
}
