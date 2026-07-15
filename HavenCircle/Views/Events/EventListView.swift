import SwiftUI
import SwiftData

/// 提醒中心：目前有效的事件列表
struct EventListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LocalSafetyEvent.occurredAt, order: .reverse) private var events: [LocalSafetyEvent]
    @Query private var members: [LocalFamilyMember]
    @State private var adding = false

    private var activeEvents: [LocalSafetyEvent] {
        events.filter { !$0.isExpired }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(activeEvents) { EventRow(event: $0, members: members) }
                    .onDelete(perform: delete)
            }
            .navigationTitle("提醒中心")
            .toolbar {
                Button("新增事件", systemImage: "plus") { adding = true }
            }
            .sheet(isPresented: $adding) { EventEditorView() }
        }
    }

    /// 修正舊版 bug：刪除索引要對「過濾後」的清單取，不能直接用完整 events 陣列
    private func delete(at offsets: IndexSet) {
        let visible = activeEvents
        for index in offsets {
            context.delete(visible[index])
        }
        context.saveReporting()
    }
}

#Preview {
    EventListView()
        .modelContainer(PreviewSupport.container())
}
