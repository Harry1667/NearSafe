import WidgetKit
import SwiftUI

/// 安心圈中型 Widget（Phase 1）：三個安全語意缺一不可的狀態——
/// 01 平穩（綠）、03 需要留意（琥珀）、09 資料失效（灰，「安全」與「無法判斷」必須區分）。
/// 資料來源：主 App 寫入 App Group 的快照；Widget 不做網路請求。

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let isStale: Bool
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder, isStale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // 30 分鐘後請系統再讀一次（把「新鮮」自動翻成「失效」）；即時性由主 App 寫入時 reload 負責
        completion(Timeline(entries: [loadEntry()], policy: .after(.now.addingTimeInterval(30 * 60))))
    }

    private func loadEntry() -> SnapshotEntry {
        guard let url = WidgetShared.snapshotURL,
              let data = try? Data(contentsOf: url) else {
            return SnapshotEntry(date: .now, snapshot: nil, isStale: true)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data) else {
            return SnapshotEntry(date: .now, snapshot: nil, isStale: true)
        }
        let stale = Date.now.timeIntervalSince(snapshot.generatedAt) > WidgetShared.staleInterval
        return SnapshotEntry(date: .now, snapshot: snapshot, isStale: stale)
    }
}

extension WidgetSnapshot {
    static let placeholder = WidgetSnapshot(
        generatedAt: .now, circleName: "住家", radiusMeters: 1000,
        attentionCount: 0, topEvent: nil
    )
}

// MARK: - View

struct HavenCircleWidgetView: View {
    let entry: SnapshotEntry

    private enum DisplayState {
        case normal, attention, stale
    }

    private var state: DisplayState {
        // 規格優先級：失效 > 需要留意 > 平穩（沒資料不能顯示成平穩）
        guard let snapshot = entry.snapshot, !entry.isStale else { return .stale }
        return snapshot.attentionCount > 0 ? .attention : .normal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Spacer(minLength: 0)
            statusRow
            Spacer(minLength: 0)
            footer
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .widgetURL(deepLink)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "house.fill")
                .font(.caption)
                .padding(5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            Text("安心圈").font(.subheadline.bold())
            if let snapshot = entry.snapshot {
                Text("\(snapshot.circleName) · \(formattedDistance(snapshot.radiusMeters))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private var statusIcon: some View {
        ZStack {
            Circle().fill(iconBackground).frame(width: 46, height: 46)
            Image(systemName: iconName)
                .font(.title3.bold())
                .foregroundStyle(iconForeground)
        }
        .accessibilityHidden(true) // 狀態語意由標題文字承擔，不靠顏色（規格要求）
    }

    @ViewBuilder
    private var footer: some View {
        switch state {
        case .attention:
            HStack {
                if let event = entry.snapshot?.topEvent {
                    Label(footerAttentionText(event), systemImage: "checkmark.shield.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("查看事件")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.orange.opacity(0.9), in: Capsule())
                    .foregroundStyle(.white)
            }
        case .normal, .stale:
            Label(updatedText, systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: 文案與樣式（對照設計稿 01 / 03 / 09）

    private var title: String {
        switch state {
        case .normal: "一切平穩"
        case .attention: "需要留意"
        case .stale: "狀態暫時無法更新"
        }
    }

    private var subtitle: String {
        switch state {
        case .normal: "目前沒有需留意事件"
        case .attention: "附近有 \(entry.snapshot?.attentionCount ?? 0) 件相關事件"
        case .stale: "目前狀態未知，請開啟 App 更新"
        }
    }

    private var iconName: String {
        switch state {
        case .normal: "checkmark"
        case .attention: "exclamationmark"
        case .stale: "questionmark"
        }
    }

    private var iconBackground: Color {
        switch state {
        case .normal: .green.opacity(0.18)
        case .attention: .orange.opacity(0.22)
        case .stale: .gray.opacity(0.18)
        }
    }

    private var iconForeground: Color {
        switch state {
        case .normal: .green
        case .attention: .orange
        case .stale: .gray
        }
    }

    private var updatedText: String {
        guard let generated = entry.snapshot?.generatedAt else { return "尚未取得資料" }
        let time = generated.formatted(date: .omitted, time: .shortened)
        return state == .stale ? "上次成功更新 \(time)" : "更新於 \(time)"
    }

    private func footerAttentionText(_ event: WidgetEventSummary) -> String {
        var parts: [String] = [event.isOfficial ? "官方來源" : "待確認"]
        if let meters = event.approximateDistanceMeters {
            parts.append(formattedDistance(meters))
        }
        return parts.joined(separator: " · ")
    }

    private func formattedDistance(_ meters: Int) -> String {
        meters >= 1000 ? String(format: "%.0f km", Double(meters) / 1000) : "\(meters) m"
    }

    private var deepLink: URL? {
        switch state {
        case .attention: URL(string: "havencircle://alerts")
        case .normal: URL(string: "havencircle://map")
        case .stale: URL(string: "havencircle://refresh")
        }
    }
}

// MARK: - Widget

struct HavenCircleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.widgetKind, provider: SnapshotProvider()) { entry in
            HavenCircleWidgetView(entry: entry)
        }
        .configurationDisplayName("安心圈狀態")
        .description("一眼掌握生活圈的安全狀態。")
        .supportedFamilies([.systemMedium])
    }
}

#Preview(as: .systemMedium) {
    HavenCircleWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .placeholder, isStale: false)
    SnapshotEntry(date: .now,
                  snapshot: WidgetSnapshot(generatedAt: .now, circleName: "住家", radiusMeters: 1000,
                                           attentionCount: 1,
                                           topEvent: WidgetEventSummary(title: "火警通報", isOfficial: true, approximateDistanceMeters: 800)),
                  isStale: false)
    SnapshotEntry(date: .now, snapshot: nil, isStale: true)
}
