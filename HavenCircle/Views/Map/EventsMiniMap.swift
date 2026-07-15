import SwiftUI
import MapKit

/// 精簡地圖卡片：嵌在提醒中心頂部，一眼看到事件與生活圈的相對位置。
/// 完整互動（圖層、過濾、家人切換）在中間的「安全地圖」分頁。
struct EventsMiniMap: View {
    let events: [LocalSafetyEvent]
    let members: [LocalFamilyMember]
    var onSelect: (LocalSafetyEvent) -> Void

    var body: some View {
        Map(initialPosition: .automatic) {
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
    }
}
