import SwiftUI
import MapKit

/// 精簡地圖卡片：嵌在提醒中心頂部，一眼看到事件與生活圈的相對位置。
/// 定位是「唯讀預覽」：關閉地圖手勢，點空白處放大（跳到安全地圖分頁），
/// 標記仍可直接點開事件詳情。完整互動（圖層、過濾、家人切換）在安全地圖分頁。
struct EventsMiniMap: View {
    let events: [LocalSafetyEvent]
    let members: [LocalFamilyMember]
    var onSelect: (LocalSafetyEvent) -> Void
    /// 點地圖空白處（非標記）時呼叫——外部決定怎麼「放大」（跳分頁）
    var onExpand: () -> Void = {}

    /// 預覽應先回答「事件相對於我的警戒圈在哪裡」，不能因為全台事件而拉成太平洋視角。
    /// 若尚未設定生活圈，則穩定顯示台灣全覽，避免 MapKit 的自動預設落到任意海外地區。
    private var focusedPosition: MapCameraPosition {
        let orderedMembers = members.sorted { lhs, rhs in
            if lhs.isCurrentUser != rhs.isCurrentUser { return lhs.isCurrentUser }
            return lhs.name < rhs.name
        }
        let circles = orderedMembers.flatMap(\.lifeCircles)
        let focusCircle = circles.first(where: \.isActiveForAlerts) ?? circles.first

        guard let focusCircle else {
            return .region(Self.taiwanFallbackRegion)
        }
        let radiusDelta = max(Double(focusCircle.radiusMeters) / 111_000 * 3.2, 0.015)
        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: focusCircle.latitude, longitude: focusCircle.longitude),
            span: MKCoordinateSpan(latitudeDelta: radiusDelta, longitudeDelta: radiusDelta)
        ))
    }

    private static let taiwanFallbackRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 23.7, longitude: 120.96),
        span: MKCoordinateSpan(latitudeDelta: 4.6, longitudeDelta: 4.6)
    )

    var body: some View {
        Map(initialPosition: focusedPosition, interactionModes: []) {
            ForEach(members.flatMap(\.lifeCircles)) { circle in
                MapCircle(
                    center: .init(latitude: circle.latitude, longitude: circle.longitude),
                    radius: CLLocationDistance(circle.radiusMeters)
                )
                .foregroundStyle(HCColor.brand.opacity(0.08))
                .stroke(HCColor.brand.opacity(0.4), lineWidth: 1.5)
            }
            ForEach(events) { event in
                Annotation(event.isDrill ? "演練" : event.eventType,
                           coordinate: .init(latitude: event.latitude, longitude: event.longitude)) {
                    Button {
                        onSelect(event)
                    } label: {
                        // 與安全地圖同一套標記語言：圖示＝類型、顏色＝可信度
                        Image(systemName: event.isDrill
                              ? "bell.and.waves.left.and.right"
                              : EventCategory.icon(for: event.eventType))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(event.isOfficiallyConfirmed ? HCColor.danger : HCColor.attention, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .frame(height: 152)
        .clipShape(RoundedRectangle(cornerRadius: HCRadius.card, style: .continuous))
        // 空白處點擊＝放大；Annotation 內的 Button 優先攔截，不受影響
        .onTapGesture { onExpand() }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption.weight(.semibold))
                .padding(8)
                .background(.regularMaterial, in: Circle())
                .padding(8)
                .allowsHitTesting(false) // 純視覺提示，點擊仍由整卡的 onTapGesture 處理
        }
        .overlay(alignment: .bottomLeading) {
            Label("警戒圈相對位置", systemImage: "scope")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(8)
                .allowsHitTesting(false)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("點兩下開啟完整安全地圖")
    }
}
