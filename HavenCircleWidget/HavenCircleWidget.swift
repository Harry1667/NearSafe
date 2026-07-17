import MapKit
import SwiftUI
import UIKit
import WidgetKit

/// 小型：只顯示安全語意；中型：補一筆事件敘述；大型：概略地圖與事件清單。
/// 資料由主 App 寫入 App Group，Widget 不讀取家人位置或精確地址。

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let isStale: Bool
    let mapImage: UIImage?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder, isStale: false, mapImage: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        loadEntry(for: context, completion: completion)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        loadEntry(for: context) { entry in
            // 30 分鐘後再讀一次；主 App 每次刷新完成也會要求 WidgetKit 重載。
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
        }
    }

    private func loadEntry(for context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let entry = loadSnapshot()
        guard context.family == .systemLarge,
              !entry.isStale,
              let snapshot = entry.snapshot else {
            completion(entry)
            return
        }

        WidgetMapSnapshotRenderer.render(snapshot: snapshot, width: context.displaySize.width - 32) { mapImage in
            completion(SnapshotEntry(
                date: entry.date,
                snapshot: entry.snapshot,
                isStale: entry.isStale,
                mapImage: mapImage
            ))
        }
    }

    private func loadSnapshot() -> SnapshotEntry {
        guard let url = WidgetShared.snapshotURL,
              let data = try? Data(contentsOf: url) else {
            return SnapshotEntry(date: .now, snapshot: nil, isStale: true, mapImage: nil)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data) else {
            return SnapshotEntry(date: .now, snapshot: nil, isStale: true, mapImage: nil)
        }

        // 新版 Widget 只呈現固定地點；舊的移動圈快照不繼續顯示。
        let isUnsupportedCircle = snapshot.circleKind.map { $0 != "fixed" } ?? false
        let isStale = Date.now.timeIntervalSince(snapshot.generatedAt) > WidgetShared.staleInterval
            || isUnsupportedCircle
        return SnapshotEntry(date: .now, snapshot: snapshot, isStale: isStale, mapImage: nil)
    }
}

extension WidgetSnapshot {
    static let placeholder = WidgetSnapshot(
        generatedAt: .now,
        circleName: "住家",
        radiusMeters: 1_000,
        circleKind: "fixed",
        circleUpdatedAt: nil,
        circleLatitude: 25.033,
        circleLongitude: 121.5654,
        attentionCount: 0,
        topEvent: nil,
        events: []
    )

    static let attentionPlaceholder: WidgetSnapshot = {
        let events = [
            WidgetEventSummary(
                title: "附近火災事件通報",
                isOfficial: true,
                approximateDistanceMeters: 800,
                approximateLocation: "信義區附近",
                latitude: 25.037,
                longitude: 121.568
            ),
            WidgetEventSummary(
                title: "道路封閉，請留意替代路線",
                isOfficial: true,
                approximateDistanceMeters: 1_200,
                approximateLocation: "市府路周邊",
                latitude: 25.031,
                longitude: 121.57
            )
        ]
        return WidgetSnapshot(
            generatedAt: .now,
            circleName: "住家",
            radiusMeters: 1_500,
            circleKind: "fixed",
            circleUpdatedAt: nil,
            circleLatitude: 25.033,
            circleLongitude: 121.5654,
            attentionCount: events.count,
            topEvent: events.first,
            events: events
        )
    }()
}

// MARK: - Presentation

private enum WidgetDisplayState {
    case normal
    case attention
    case stale

    var title: String {
        switch self {
        case .normal: "一切平穩"
        case .attention: "需要留意"
        case .stale: "狀態未知"
        }
    }

    var compactTitle: String {
        switch self {
        case .normal: "安全"
        case .attention: "危險"
        case .stale: "未知"
        }
    }

    var iconName: String {
        switch self {
        case .normal: "checkmark"
        case .attention: "exclamationmark"
        case .stale: "questionmark"
        }
    }

    var iconBackground: Color {
        switch self {
        case .normal: .green.opacity(0.18)
        case .attention: .orange.opacity(0.22)
        case .stale: .gray.opacity(0.18)
        }
    }

    var iconForeground: Color {
        switch self {
        case .normal: .green
        case .attention: .orange
        case .stale: .gray
        }
    }
}

struct HavenCircleWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: SnapshotEntry

    private var state: WidgetDisplayState {
        guard let snapshot = entry.snapshot, !entry.isStale else { return .stale }
        return snapshot.attentionCount > 0 ? .attention : .normal
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(entry: entry, state: state)
            case .systemLarge:
                LargeWidgetView(entry: entry, state: state)
            default:
                MediumWidgetView(entry: entry, state: state)
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .widgetURL(deepLink)
    }

    private var deepLink: URL? {
        switch state {
        case .attention: URL(string: "havencircle://alerts")
        case .normal: URL(string: "havencircle://map")
        case .stale: URL(string: "havencircle://refresh")
        }
    }
}

private struct SmallWidgetView: View {
    let entry: SnapshotEntry
    let state: WidgetDisplayState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "house.fill")
                    .font(.caption.bold())
                Text(entry.snapshot?.circleName ?? "安心圈")
                    .font(.caption.bold())
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            StatusIcon(state: state, size: 44)
            Text(state.compactTitle)
                .font(.title.bold())
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text(statusCaption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(footerText)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.snapshot?.circleName ?? "安心圈")，\(state.title)，\(statusCaption)")
    }

    private var statusCaption: String {
        switch state {
        case .normal: "目前沒有需留意事件"
        case .attention: "附近有需留意事件"
        case .stale: "請開啟 App 更新"
        }
    }

    private var footerText: String {
        state == .attention ? "非緊急服務 · 緊急請撥 110／119" : "非緊急服務"
    }
}

private struct MediumWidgetView: View {
    let entry: SnapshotEntry
    let state: WidgetDisplayState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(snapshot: entry.snapshot)

            HStack(spacing: 10) {
                StatusIcon(state: state, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.title)
                        .font(.headline.bold())
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if state == .attention, let event = entry.snapshot?.eventSummaries.first {
                EventSummaryRow(event: event, compact: true)
            } else {
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Label(updatedText, systemImage: "clock")
                Spacer(minLength: 0)
                Text("非緊急服務")
                if state == .attention {
                    Text("· 緊急請撥 110／119")
                }
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusSubtitle: String {
        switch state {
        case .normal: "目前沒有需留意事件"
        case .attention: "附近有 \(entry.snapshot?.attentionCount ?? 0) 件相關事件"
        case .stale: "目前無法判斷，請開啟 App 更新"
        }
    }

    private var updatedText: String {
        guard let generatedAt = entry.snapshot?.generatedAt else { return "尚未取得資料" }
        return "\(generatedAt.formatted(date: .omitted, time: .shortened)) 更新"
    }
}

private struct LargeWidgetView: View {
    let entry: SnapshotEntry
    let state: WidgetDisplayState

    private var events: [WidgetEventSummary] {
        guard state == .attention else { return [] }
        return Array((entry.snapshot?.eventSummaries ?? []).prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(snapshot: entry.snapshot)

            HStack(spacing: 10) {
                StatusIcon(state: state, size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.title)
                        .font(.headline.bold())
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(updatedText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            mapPreview
                .frame(height: 112)

            HStack {
                Text("事件摘要")
                    .font(.caption.bold())
                Spacer(minLength: 0)
                if let count = entry.snapshot?.attentionCount, count > 0 {
                    Text("共 \(count) 件")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if state == .attention, !events.isEmpty {
                VStack(spacing: 7) {
                    ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                        EventSummaryRow(event: event, compact: false)
                    }
                }
            } else {
                Label(emptyText, systemImage: state == .stale ? "arrow.clockwise" : "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }

            Spacer(minLength: 0)

            Text("HavenCircle 非緊急服務 · 緊急狀況請撥 110／119")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var mapPreview: some View {
        ZStack(alignment: .topLeading) {
            if let mapImage = entry.mapImage, state != .stale {
                Image(uiImage: mapImage)
                    .resizable()
                    .scaledToFill()
            } else {
                MapPlaceholder(state: state)
            }

            Label(state == .stale ? "地圖資料未更新" : "概略位置", systemImage: "map.fill")
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        }
        .accessibilityLabel(state == .stale ? "地圖資料未更新" : "固定警戒圈與事件概略位置圖")
    }

    private var statusSubtitle: String {
        switch state {
        case .normal: "固定警戒圈目前沒有需留意事件"
        case .attention: "固定警戒圈附近有 \(entry.snapshot?.attentionCount ?? 0) 件相關事件"
        case .stale: "目前無法判斷，請開啟 App 更新"
        }
    }

    private var emptyText: String {
        state == .stale ? "開啟 App 取得最新狀態" : "目前沒有需留意事件"
    }

    private var updatedText: String {
        guard let generatedAt = entry.snapshot?.generatedAt else { return "尚無資料" }
        return generatedAt.formatted(date: .omitted, time: .shortened)
    }
}

private struct WidgetHeader: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "house.fill")
                .font(.caption)
                .padding(5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            Text("安心圈")
                .font(.subheadline.bold())
            if let snapshot {
                Text("\(snapshot.circleName) · \(formattedDistance(snapshot.radiusMeters))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct StatusIcon: View {
    let state: WidgetDisplayState
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(state.iconBackground)
                .frame(width: size, height: size)
            Image(systemName: state.iconName)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(state.iconForeground)
        }
        .accessibilityHidden(true)
    }
}

private struct EventSummaryRow: View {
    let event: WidgetEventSummary
    let compact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: event.isOfficial ? "checkmark.shield.fill" : "questionmark.diamond.fill")
                .font(.caption)
                .foregroundStyle(event.isOfficial ? .blue : .secondary)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(compact ? .caption : .caption.bold())
                    .lineLimit(compact ? 1 : 2)
                Text(metadata)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 9 : 0)
        .padding(.vertical, compact ? 6 : 0)
        .background(compact ? Color.orange.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9))
    }

    private var metadata: String {
        var parts = [event.isOfficial ? "官方已確認" : "未驗證線索"]
        if let location = event.approximateLocation, !location.isEmpty {
            parts.append(location)
        }
        if let meters = event.approximateDistanceMeters {
            parts.append(formattedDistance(meters))
        }
        return parts.joined(separator: " · ")
    }
}

private struct MapPlaceholder: View {
    let state: WidgetDisplayState

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Canvas { context, size in
                var grid = Path()
                for fraction in stride(from: 0.2, through: 0.8, by: 0.2) {
                    grid.move(to: CGPoint(x: size.width * fraction, y: 0))
                    grid.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                    grid.move(to: CGPoint(x: 0, y: size.height * fraction))
                    grid.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                }
                context.stroke(grid, with: .color(.gray.opacity(0.18)), lineWidth: 1)
            }
            Image(systemName: state == .stale ? "map" : "mappin.and.ellipse")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

private enum WidgetMapSnapshotRenderer {
    static func render(snapshot: WidgetSnapshot, width: CGFloat, completion: @escaping (UIImage?) -> Void) {
        guard let latitude = snapshot.circleLatitude,
              let longitude = snapshot.circleLongitude else {
            completion(nil)
            return
        }

        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let visibleMeters = max(Double(snapshot.radiusMeters) * 3.2, 2_000)
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: visibleMeters,
            longitudinalMeters: visibleMeters
        )
        options.size = CGSize(width: max(width, 240), height: 112)
        options.scale = 2
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { mapSnapshot, _ in
            guard let mapSnapshot else {
                completion(nil)
                return
            }
            completion(drawMarkers(on: mapSnapshot, snapshot: snapshot, center: center))
        }
    }

    private static func drawMarkers(
        on mapSnapshot: MKMapSnapshotter.Snapshot,
        snapshot: WidgetSnapshot,
        center: CLLocationCoordinate2D
    ) -> UIImage {
        let image = mapSnapshot.image
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { rendererContext in
            image.draw(at: .zero)

            let centerPoint = mapSnapshot.point(for: center)
            let longitudeMeters = max(111_320 * cos(center.latitude * .pi / 180), 1)
            let edgeCoordinate = CLLocationCoordinate2D(
                latitude: center.latitude,
                longitude: center.longitude + Double(snapshot.radiusMeters) / longitudeMeters
            )
            let edgePoint = mapSnapshot.point(for: edgeCoordinate)
            let radius = max(abs(edgePoint.x - centerPoint.x), 10)

            let context = rendererContext.cgContext
            context.setFillColor(UIColor.systemBlue.withAlphaComponent(0.14).cgColor)
            context.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.75).cgColor)
            context.setLineWidth(2)
            context.addEllipse(in: CGRect(
                x: centerPoint.x - radius,
                y: centerPoint.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.drawPath(using: .fillStroke)

            for event in snapshot.eventSummaries.prefix(3) {
                guard let latitude = event.latitude, let longitude = event.longitude else { continue }
                let point = mapSnapshot.point(for: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                guard image.size.width.contains(point.x), image.size.height.contains(point.y) else { continue }
                context.setFillColor(UIColor.systemOrange.cgColor)
                context.addEllipse(in: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
                context.fillPath()
                context.setFillColor(UIColor.white.cgColor)
                context.addEllipse(in: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
                context.fillPath()
            }
        }
    }
}

private func formattedDistance(_ meters: Int) -> String {
    meters >= 1_000
        ? String(format: "%.1f km", Double(meters) / 1_000).replacingOccurrences(of: ".0", with: "")
        : "\(meters) m"
}

private extension CGFloat {
    func contains(_ value: CGFloat) -> Bool {
        value >= 0 && value <= self
    }
}

// MARK: - Widget

struct HavenCircleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.widgetKind, provider: SnapshotProvider()) { entry in
            HavenCircleWidgetView(entry: entry)
        }
        .configurationDisplayName("安心圈狀態")
        .description("以小、中、大三種尺寸查看固定警戒圈狀態、事件摘要與概略地圖。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview("小型狀態", as: .systemSmall) {
    HavenCircleWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .placeholder, isStale: false, mapImage: nil)
    SnapshotEntry(date: .now, snapshot: .attentionPlaceholder, isStale: false, mapImage: nil)
    SnapshotEntry(date: .now, snapshot: nil, isStale: true, mapImage: nil)
}

#Preview("中型事件", as: .systemMedium) {
    HavenCircleWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .attentionPlaceholder, isStale: false, mapImage: nil)
    SnapshotEntry(date: .now, snapshot: .placeholder, isStale: false, mapImage: nil)
}

#Preview("大型地圖與事件", as: .systemLarge) {
    HavenCircleWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .attentionPlaceholder, isStale: false, mapImage: nil)
    SnapshotEntry(date: .now, snapshot: .placeholder, isStale: false, mapImage: nil)
    SnapshotEntry(date: .now, snapshot: nil, isStale: true, mapImage: nil)
}
