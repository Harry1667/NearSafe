import SwiftUI
import SwiftData

/// 區域回顧：過去 30 天的事件統計與清單。
/// 解決冷啟動問題——新使用者當下沒有事件時，仍看得到這個區域的歷史樣貌。
struct HistoryView: View {
    @Query(sort: \LocalSafetyEvent.occurredAt, order: .reverse) private var events: [LocalSafetyEvent]
    @Query private var members: [LocalFamilyMember]

    private var recentEvents: [LocalSafetyEvent] {
        let cutoff = Date.now.addingTimeInterval(-30 * 86_400)
        return events.filter { $0.occurredAt >= cutoff && !$0.isDrill }
    }

    private var countsByType: [(type: String, count: Int)] {
        Dictionary(grouping: recentEvents, by: \.eventType)
            .map { (type: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        List {
            Section("過去 30 天統計") {
                if countsByType.isEmpty {
                    Text("這段期間沒有紀錄到事件").foregroundStyle(.secondary)
                } else {
                    ForEach(countsByType, id: \.type) { item in
                        statBar(type: item.type, count: item.count)
                    }
                }
            }
            Section("事件紀錄") {
                ForEach(recentEvents) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(event.title).font(.subheadline.bold())
                            Spacer()
                            Text(event.statusText).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("\(event.eventType) · \(event.approximateLocation)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .navigationTitle("區域回顧")
    }

    private func statBar(type: String, count: Int) -> some View {
        let maxCount = countsByType.first?.count ?? 1
        return HStack {
            Text(type).font(.subheadline).frame(width: 100, alignment: .leading)
            GeometryReader { geo in
                Capsule()
                    .fill(.indigo.opacity(0.6))
                    .frame(width: max(geo.size.width * CGFloat(count) / CGFloat(maxCount), 8))
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            Text("\(count) 件").font(.caption).foregroundStyle(.secondary)
        }
        .frame(height: 24)
    }
}

#Preview {
    NavigationStack { HistoryView() }
        .modelContainer(PreviewSupport.container())
}
