import SwiftUI
import CoreLocation

struct EventRow: View {
    let event: LocalSafetyEvent
    let members: [LocalFamilyMember]

    var body: some View {
        HStack {
            Image(systemName: event.eventType == EventCategory.fire ? "flame.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(event.isOfficiallyConfirmed ? .red : .orange)
                .frame(width: 25)
            VStack(alignment: .leading) {
                Text(event.title)
                    .font(.subheadline.bold())
                Text("\(event.approximateLocation) · \(relativeDistance(event, members))")
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
}

/// 事件到「最近生活圈」的概略距離文字（只顯示百公尺級精度，避免暴露精確位置）
func relativeDistance(_ event: LocalSafetyEvent, _ members: [LocalFamilyMember]) -> String {
    let point = CLLocation(latitude: event.latitude, longitude: event.longitude)
    let distances = members.flatMap(\.lifeCircles).map {
        point.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
    }
    guard let nearest = distances.min() else { return "尚未設定生活圈" }
    return "距離生活圈 \(Int(nearest / 100) * 100) 公尺"
}
