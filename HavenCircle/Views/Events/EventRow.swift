import SwiftUI
import CoreLocation

struct EventRow: View {
    let event: LocalSafetyEvent
    let members: [LocalFamilyMember]

    /// 可信度顏色（官方確認＝危險紅、確認中＝琥珀）；事件類型交給圖示表達
    private var trustColor: Color {
        event.isOfficiallyConfirmed ? HCColor.danger : HCColor.attention
    }

    var body: some View {
        HStack(spacing: HCSpacing.x3) {
            Image(systemName: iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(trustColor)
                .frame(width: 34, height: 34)
                .background(trustColor.opacity(0.12), in: RoundedRectangle(cornerRadius: HCRadius.badge, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.isDrill ? "【演練】\(event.title)" : event.title)
                    .lineLimit(2) // 卡片定高：超長標題（媒體事件偶有）截斷，不撐爆版面
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
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(trustColor)
                .background(trustColor.opacity(0.12), in: Capsule())
        }
        .hcCard()
    }

    private var iconName: String {
        if event.isDrill { return "bell.and.waves.left.and.right" }
        return EventCategory.icon(for: event.eventType)
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

/// 「附近」的距離語意：離所有生活圈超過這個距離的事件不算「附近」。
/// 審查發現：沒有上限時，145 公里外的花蓮路況會被當「附近更新」推到台北使用者眼前，
/// 稀釋真正相關的訊號。超過上限的事件收進「全台其他」次級清單，不是消失。
enum NearbyScope {
    static let maxMeters: Double = 30_000
}

/// 事件到最近生活圈的距離（公尺），供排序使用
func nearestCircleDistance(_ event: LocalSafetyEvent, _ members: [LocalFamilyMember]) -> Double {
    let point = CLLocation(latitude: event.latitude, longitude: event.longitude)
    return members.flatMap(\.lifeCircles)
        .map { point.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) }
        .min() ?? .greatestFiniteMagnitude
}
