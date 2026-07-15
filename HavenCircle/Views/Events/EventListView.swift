import SwiftUI
import SwiftData

/// 提醒中心：按「需要注意 / 持續確認中 / 已結束」分類（對應產品規格的通知頁分類）
struct EventListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LocalSafetyEvent.occurredAt, order: .reverse) private var events: [LocalSafetyEvent]
    @Query private var members: [LocalFamilyMember]
    @State private var showDrill = false
    @State private var selected: LocalSafetyEvent?

    private var visibleEvents: [LocalSafetyEvent] { events.filter { !$0.isArchived } }
    private var attention: [LocalSafetyEvent] {
        visibleEvents.filter { !$0.isEnded && $0.isOfficiallyConfirmed }
    }
    private var confirming: [LocalSafetyEvent] {
        visibleEvents.filter { !$0.isEnded && !$0.isOfficiallyConfirmed }
    }
    private var ended: [LocalSafetyEvent] {
        Array(visibleEvents.filter(\.isEnded).prefix(20))
    }

    var body: some View {
        NavigationStack {
            List {
                if visibleEvents.isEmpty {
                    ContentUnavailableView("目前沒有事件", systemImage: "checkmark.shield")
                }
                section(title: "需要注意", subtitle: "官方確認且位於生活圈附近", items: attention)
                section(title: "持續確認中", subtitle: "資料尚未充分驗證，不會推播", items: confirming)
                section(title: "已結束", subtitle: "已解除或已過期的事件", items: ended)
            }
            .navigationTitle("提醒中心")
            .toolbar {
                Button("演練", systemImage: "bell.and.waves.left.and.right") { showDrill = true }
            }
            .sheet(isPresented: $showDrill) { DrillView() }
            .sheet(item: $selected) { EventDetailView(event: $0, members: members) }
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
