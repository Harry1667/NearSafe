import SwiftUI
import SwiftData
import MapKit

struct SafetyMapView: View {
    @Query private var events: [LocalSafetyEvent]
    @Query private var members: [LocalFamilyMember]
    @Query private var regionAlerts: [RegionAlert]
    @State private var selected: LocalSafetyEvent?
    @State private var selectedAlert: RegionAlert?
    @State private var showShelters = false
    @State private var showHospitals = false
    /// nil＝全家；對應產品規格「可切換媽媽、弟弟或全家」
    @State private var selectedMemberKey: String?
    /// .automatic 讓鏡頭自動框住地圖內容（生活圈與事件），取代舊版寫死的台北市中心
    @State private var cameraPosition: MapCameraPosition = .automatic
    // 用 @AppStorage 與設定頁共用同一旗標，修正舊版兩邊狀態不同步的問題
    @AppStorage(SettingsKeys.alertsPaused) private var isPaused = false

    /// 目前顯示對象（家人切換器過濾後）
    private var visibleMembers: [LocalFamilyMember] {
        guard let key = selectedMemberKey else { return members }
        return members.filter { $0.memberKey == key }
    }

    private var activeEvents: [LocalSafetyEvent] {
        events.filter { !$0.isEnded && !$0.isArchived }
    }

    private var attentionCount: Int {
        activeEvents.filter { event in
            event.isOfficiallyConfirmed
                && !AlertPolicy.evaluate(event: event, members: visibleMembers).matches.isEmpty
        }.count
    }

    private var activeRegionAlerts: [RegionAlert] {
        regionAlerts.filter { !$0.isEnded }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                statusBanner
                regionAlertBanners
                map
                nearbyUpdates
            }
            .navigationTitle("安心圈")
            .toolbar {
                memberPicker
                layerMenu
            }
            // 對應規格「點選標記後，底部出現事件摘要；上滑看完整資訊」：
            // 半版先看摘要（狀態＋提醒判斷），上拉展開全頁；半版時地圖仍可互動
            .sheet(item: $selected) {
                EventDetailView(event: $0, members: members)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
            .sheet(item: $selectedAlert) {
                RegionAlertDetailView(alert: $0, members: members)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    /// 家人切換器：全家或個別家人（切換時鏡頭重新框選）
    private var memberPicker: some View {
        Menu {
            Picker("顯示對象", selection: $selectedMemberKey) {
                Text("全家").tag(String?.none)
                ForEach(members) { member in
                    Text(member.name).tag(String?.some(member.memberKey))
                }
            }
        } label: {
            Label(
                visibleMembers.count == members.count ? "全家" : (visibleMembers.first?.name ?? "全家"),
                systemImage: "person.2"
            )
        }
        .onChange(of: selectedMemberKey) {
            cameraPosition = .automatic
        }
    }

    /// 圖層開關：緊急資源預設關閉，維持「安靜的地圖」
    private var layerMenu: some View {
        Menu("圖層", systemImage: "square.3.layers.3d") {
            Toggle("避難收容所", isOn: $showShelters)
            Toggle("急救責任醫院", isOn: $showHospitals)
        }
    }

    @ViewBuilder
    private var regionAlertBanners: some View {
        ForEach(activeRegionAlerts) { alert in
            Button {
                selectedAlert = alert
            } label: {
                RegionAlertBanner(alert: alert, members: members)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
    }

    /// 首頁一句話回答「我家人附近有什麼事？」，並附資料時效與暫停狀態
    private var statusBanner: some View {
        let hasAttention = attentionCount > 0
        return HStack {
            Image(systemName: hasAttention ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                .foregroundStyle(hasAttention ? .red : .green)
            VStack(alignment: .leading) {
                Text(hasAttention
                     ? "家人生活圈附近有 \(attentionCount) 件需要注意的事件"
                     : "生活圈附近暫無立即危險")
                    .font(.subheadline.bold())
                if isPaused {
                    // 暫停是影響安全的狀態，必須在主橫幅明確可見，不能只靠小按鈕
                    Text("提醒已暫停——事件仍會顯示，但不會推播。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("事件以來源、時間與距離篩選；未驗證線索不會推播。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DataFreshnessLabel()
            }
            Spacer()
        }
        .padding(12)
        .background(
            (hasAttention ? Color.red : Color.green).opacity(0.1),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .padding(.horizontal)
    }

    private var map: some View {
        Map(position: $cameraPosition) {
            ForEach(visibleMembers.flatMap(\.lifeCircles)) { circle in
                MapCircle(
                    center: .init(latitude: circle.latitude, longitude: circle.longitude),
                    radius: CLLocationDistance(circle.radiusMeters)
                )
                .foregroundStyle(.indigo.opacity(0.08))
                .stroke(.indigo.opacity(0.4), lineWidth: 1)
            }
            ForEach(activeEvents) { event in
                Annotation(event.isDrill ? "演練" : event.eventType,
                           coordinate: .init(latitude: event.latitude, longitude: event.longitude)) {
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
            if showShelters {
                ForEach(EmergencyResourceStore.shelters) { resource in
                    Annotation(resource.name, coordinate: .init(latitude: resource.latitude, longitude: resource.longitude)) {
                        Image(systemName: "tent.fill")
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.green, in: Circle())
                    }
                }
            }
            if showHospitals {
                ForEach(EmergencyResourceStore.hospitals) { resource in
                    Annotation(resource.name, coordinate: .init(latitude: resource.latitude, longitude: resource.longitude)) {
                        Image(systemName: "cross.case.fill")
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.teal, in: Circle())
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
        .overlay(alignment: .bottomTrailing) {
            Button(isPaused ? "提醒已暫停" : "暫停提醒", systemImage: isPaused ? "bell.slash.fill" : "bell.slash") {
                isPaused.toggle()
            }
            .font(.caption.bold())
            .foregroundStyle(isPaused ? .orange : .primary)
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
                // 依「離生活圈最近」排序，最相關的先看到
                let sorted = activeEvents.sorted {
                    nearestCircleDistance($0, visibleMembers) < nearestCircleDistance($1, visibleMembers)
                }
                ForEach(sorted.prefix(3)) { event in
                    Button {
                        selected = event
                    } label: {
                        EventRow(event: event, members: visibleMembers)
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
