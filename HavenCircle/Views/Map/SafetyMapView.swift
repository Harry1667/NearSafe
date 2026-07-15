import SwiftUI
import SwiftData
import MapKit

/// 安全地圖：全螢幕地圖為主體，狀態橫幅、區域警報與附近更新以浮層呈現。
struct SafetyMapView: View {
    @Query private var events: [LocalSafetyEvent]
    @Query private var members: [LocalFamilyMember]
    @Query private var regionAlerts: [RegionAlert]
    @State private var selected: LocalSafetyEvent?
    @State private var selectedAlert: RegionAlert?

    // 圖層與過濾（顯示偏好，不影響通知決策）
    @State private var showCircles = true
    @State private var showShelters = false
    @State private var showHospitals = false
    @State private var enabledTypes: Set<String> = Set(EventCategory.all)
    @State private var showUnverified = true

    /// nil＝全家；對應產品規格「可切換媽媽、弟弟或全家」
    @State private var selectedMemberKey: String?
    /// .automatic 讓鏡頭自動框住地圖內容（生活圈與事件）
    @State private var cameraPosition: MapCameraPosition = .automatic
    // 用 @AppStorage 與設定頁共用同一旗標
    @AppStorage(SettingsKeys.alertsPaused) private var isPaused = false

    /// 目前顯示對象（家人切換器過濾後）
    private var visibleMembers: [LocalFamilyMember] {
        guard let key = selectedMemberKey else { return members }
        return members.filter { $0.memberKey == key }
    }

    private var allActiveEvents: [LocalSafetyEvent] {
        events.filter { !$0.isEnded && !$0.isArchived }
    }

    /// 套用圖層過濾後、顯示在地圖與卡片上的事件
    private var filteredEvents: [LocalSafetyEvent] {
        allActiveEvents.filter {
            enabledTypes.contains($0.eventType) && (showUnverified || $0.isOfficiallyConfirmed)
        }
    }

    /// 安全狀態一律以「未過濾」的事件計算——過濾是顯示偏好，不能過濾掉安全警告
    private var attentionCount: Int {
        allActiveEvents.filter { event in
            event.isOfficiallyConfirmed
                && !AlertPolicy.evaluate(event: event, members: visibleMembers).matches.isEmpty
        }.count
    }

    private var activeRegionAlerts: [RegionAlert] {
        regionAlerts.filter { !$0.isEnded }
    }

    var body: some View {
        NavigationStack {
            map
                .overlay(alignment: .top) { topOverlays }
                .safeAreaInset(edge: .bottom) { nearbyStrip }
                .navigationTitle("安心圈")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    memberPicker
                    filterMenu
                    pauseButton
                }
                // 半版先看摘要，上拉展開全頁；半版時地圖仍可互動
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

    // MARK: - 地圖本體

    private var map: some View {
        Map(position: $cameraPosition) {
            if showCircles {
                ForEach(visibleMembers.flatMap(\.lifeCircles)) { circle in
                    MapCircle(
                        center: .init(latitude: circle.latitude, longitude: circle.longitude),
                        radius: CLLocationDistance(circle.radiusMeters)
                    )
                    .foregroundStyle(.indigo.opacity(0.08))
                    .stroke(.indigo.opacity(0.4), lineWidth: 1)
                }
            }
            ForEach(filteredEvents) { event in
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
    }

    // MARK: - 工具列

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

    /// 圖層與過濾：資源圖層開關＋事件類型與可信度過濾
    private var filterMenu: some View {
        Menu {
            Section("圖層") {
                Toggle("生活圈範圍", isOn: $showCircles)
                Toggle("避難收容所", isOn: $showShelters)
                Toggle("急救責任醫院", isOn: $showHospitals)
            }
            Section("事件類型") {
                ForEach(EventCategory.all, id: \.self) { type in
                    Toggle(type, isOn: typeBinding(type))
                }
            }
            Section("可信度") {
                Toggle("顯示未驗證線索", isOn: $showUnverified)
            }
        } label: {
            Label("圖層與過濾", systemImage: "square.3.layers.3d")
        }
    }

    private func typeBinding(_ type: String) -> Binding<Bool> {
        Binding(
            get: { enabledTypes.contains(type) },
            set: { isOn in
                if isOn { enabledTypes.insert(type) } else { enabledTypes.remove(type) }
            }
        )
    }

    private var pauseButton: some View {
        Button(isPaused ? "恢復提醒" : "暫停提醒",
               systemImage: isPaused ? "bell.slash.fill" : "bell.slash") {
            isPaused.toggle()
        }
        .tint(isPaused ? .orange : nil)
    }

    // MARK: - 浮層

    private var topOverlays: some View {
        VStack(spacing: 8) {
            statusBanner
            ForEach(activeRegionAlerts.prefix(2)) { alert in
                Button {
                    selectedAlert = alert
                } label: {
                    regionAlertChip(alert)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// 一句話回答「我家人附近有什麼事？」，並附資料時效與暫停狀態
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
                    // 暫停是影響安全的狀態，必須在主橫幅明確可見
                    Text("提醒已暫停——事件仍會顯示，但不會推播。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                DataFreshnessLabel()
            }
            Spacer()
        }
        .padding(10)
        .background((hasAttention ? Color.red : Color.green).opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func regionAlertChip(_ alert: RegionAlert) -> some View {
        HStack {
            Image(systemName: "cloud.bolt.rain.fill").foregroundStyle(.orange)
            Text("\(alert.kind)警報：\(alert.title)")
                .font(.caption.bold())
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.15), in: Capsule())
        .background(.regularMaterial, in: Capsule())
    }

    /// 附近更新：地圖底部的橫向卡片（依離生活圈最近排序）
    @ViewBuilder
    private var nearbyStrip: some View {
        if !filteredEvents.isEmpty {
            let sorted = filteredEvents.sorted {
                nearestCircleDistance($0, visibleMembers) < nearestCircleDistance($1, visibleMembers)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(sorted.prefix(5)) { event in
                        Button {
                            selected = event
                        } label: {
                            EventRow(event: event, members: visibleMembers)
                                .frame(width: 320)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
        }
    }
}

#Preview {
    SafetyMapView()
        .modelContainer(PreviewSupport.container())
}
