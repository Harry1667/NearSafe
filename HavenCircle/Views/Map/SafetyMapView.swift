import SwiftUI
import SwiftData
import MapKit

struct SafetyMapView: View {
    @Query private var events: [LocalSafetyEvent]
    @Query private var members: [LocalFamilyMember]
    @State private var selected: LocalSafetyEvent?
    // 用 @AppStorage 與設定頁共用同一旗標，修正舊版兩邊狀態不同步的問題
    @AppStorage(SettingsKeys.alertsPaused) private var isPaused = false

    private let camera = MapCameraPosition.region(
        MKCoordinateRegion(
            center: .init(latitude: 25.035, longitude: 121.54),
            span: .init(latitudeDelta: 0.12, longitudeDelta: 0.18)
        )
    )

    private var activeEvents: [LocalSafetyEvent] {
        events.filter { !$0.isExpired }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                statusBanner
                map
                nearbyUpdates
            }
            .navigationTitle("安心圈")
            .sheet(item: $selected) { EventDetailView(event: $0, members: members) }
        }
    }

    private var statusBanner: some View {
        HStack {
            Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
            VStack(alignment: .leading) {
                Text("生活圈附近暫無立即危險")
                    .font(.subheadline.bold())
                Text("事件以來源、時間與距離篩選；未驗證線索不會推播。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    private var map: some View {
        Map(initialPosition: camera) {
            ForEach(members.flatMap(\.lifeCircles)) { circle in
                MapCircle(
                    center: .init(latitude: circle.latitude, longitude: circle.longitude),
                    radius: CLLocationDistance(circle.radiusMeters)
                )
                .foregroundStyle(.indigo.opacity(0.08))
                .stroke(.indigo.opacity(0.4), lineWidth: 1)
            }
            ForEach(activeEvents) { event in
                Annotation(event.eventType, coordinate: .init(latitude: event.latitude, longitude: event.longitude)) {
                    Button {
                        selected = event
                    } label: {
                        Image(systemName: event.isOfficiallyConfirmed ? "exclamationmark.triangle.fill" : "eye.fill")
                            .foregroundStyle(.white)
                            .padding(9)
                            .background(event.isOfficiallyConfirmed ? .red : .orange, in: Circle())
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .overlay(alignment: .bottomTrailing) {
            Button(isPaused ? "提醒已暫停" : "暫停提醒", systemImage: "bell.slash") {
                isPaused.toggle()
            }
            .font(.caption.bold())
            .padding(10)
            .background(.thinMaterial, in: Capsule())
            .padding(26)
        }
    }

    private var nearbyUpdates: some View {
        VStack(alignment: .leading) {
            Text("附近更新").font(.headline)
            if activeEvents.isEmpty {
                ContentUnavailableView("目前沒有事件", systemImage: "checkmark.shield")
            } else {
                ForEach(activeEvents.prefix(2)) { event in
                    Button {
                        selected = event
                    } label: {
                        EventRow(event: event, members: members)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
    }
}

#Preview {
    SafetyMapView()
        .modelContainer(PreviewSupport.container())
}
