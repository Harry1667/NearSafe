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

    var body: some View {
        Map(initialPosition: .automatic, interactionModes: []) {
            ForEach(members.flatMap(\.lifeCircles)) { circle in
                MapCircle(
                    center: .init(latitude: circle.latitude, longitude: circle.longitude),
                    radius: CLLocationDistance(circle.radiusMeters)
                )
                .foregroundStyle(.indigo.opacity(0.08))
                .stroke(.indigo.opacity(0.4), lineWidth: 1)
            }
            ForEach(events) { event in
                Annotation(event.isDrill ? "演練" : event.eventType,
                           coordinate: .init(latitude: event.latitude, longitude: event.longitude)) {
                    Button {
                        onSelect(event)
                    } label: {
                        Image(systemName: event.isOfficiallyConfirmed ? "exclamationmark.triangle.fill" : "eye.fill")
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(event.isOfficiallyConfirmed ? .red : .orange, in: Circle())
                    }
                }
            }
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("點兩下開啟完整安全地圖")
    }
}
