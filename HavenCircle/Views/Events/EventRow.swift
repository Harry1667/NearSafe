import SwiftUI
import CoreLocation

struct EventRow: View {
    let event: LocalSafetyEvent
    let members: [LocalFamilyMember]

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundStyle(event.isOfficiallyConfirmed ? .red : .orange)
                .frame(width: 25)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.isDrill ? "【演練】\(event.title)" : event.title)
                    .font(.subheadline.bold())
                Text(event.approximateLocation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // 對應產品規格的事件摘要格式：「距離媽媽公司 0.8 公里，18 分鐘前」
                Text("\(relativeDistance(event, members)) · \(relativeTime(event.occurredAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(event.trustStatus)
                .font(.caption2)
                .foregroundStyle(event.isOfficiallyConfirmed ? .red : .orange)
        }
        .padding(10)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var iconName: String {
        if event.isDrill { return "bell.and.waves.left.and.right" }
        return event.eventType == EventCategory.fire ? "flame.fill" : "exclamationmark.triangle.fill"
    }
}

/// 事件到「最近生活圈」的距離，含歸屬（誰的哪個生活圈）。
/// 只顯示百公尺級精度，避免暴露精確位置。
func relativeDistance(_ event: LocalSafetyEvent, _ members: [LocalFamilyMember]) -> String {
    let point = CLLocation(latitude: event.latitude, longitude: event.longitude)
    let candidates = members.flatMap { member in
        member.lifeCircles.map { circle in
            (
                ownerName: member.name,
                circleName: circle.name,
                distance: point.distance(from: CLLocation(latitude: circle.latitude, longitude: circle.longitude))
            )
        }
    }
    guard let nearest = candidates.min(by: { $0.distance < $1.distance }) else { return "尚未設定生活圈" }
    let meters = max(Int(nearest.distance / 100) * 100, 100)
    if meters >= 1_000 {
        let km = Double(meters) / 1_000
        return "距離\(nearest.ownerName)的「\(nearest.circleName)」\(km.formatted(.number.precision(.fractionLength(0...1)))) 公里"
    }
    return "距離\(nearest.ownerName)的「\(nearest.circleName)」\(meters) 公尺"
}

/// 相對時間文字（不依賴裝置語系，全繁中）
func relativeTime(_ date: Date) -> String {
    let seconds = Date.now.timeIntervalSince(date)
    let minutes = Int(seconds / 60)
    if minutes < 1 { return "剛剛" }
    if minutes < 60 { return "\(minutes) 分鐘前" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours) 小時前" }
    return "\(hours / 24) 天前"
}

/// 事件到最近生活圈的距離（公尺），供排序使用
func nearestCircleDistance(_ event: LocalSafetyEvent, _ members: [LocalFamilyMember]) -> Double {
    let point = CLLocation(latitude: event.latitude, longitude: event.longitude)
    return members.flatMap(\.lifeCircles)
        .map { point.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) }
        .min() ?? .greatestFiniteMagnitude
}
