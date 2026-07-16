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
    @State private var showAlertAreas = true
    @State private var showShelters = false
    @State private var showHospitals = false
    /// 空品圖層：日常環境資訊，預設關（開啟時才抓資料）
    @State private var showAirQuality = false
    @State private var aqiStations: [AQIStation] = []
    /// 治安參考圖層：季度歷史統計，預設關；刻意用靛藍色系與紅色系的即時警報區隔
    @State private var showCrimeLayer = false
    @State private var crimeReference: CrimeReference?
    @State private var enabledTypes: Set<String> = Set(EventCategory.all)
    @State private var showUnverified = true
    @State private var isSummaryExpanded = false
    /// 乾淨地圖模式：收起頂部摘要與底部卡片列，只留地圖（顯示偏好，不影響通知）
    @State private var isChromeHidden = false

    /// nil＝全家；對應產品規格「可切換媽媽、弟弟或全家」
    @State private var selectedMemberKey: String?
    /// 鏡頭明確框住生活圈（不能用 .automatic——它會框住所有內容，
    /// 加了全台塗層後開圖會變成全台灣視角，失去「聚焦自家」的預設）
    @State private var cameraPosition: MapCameraPosition = .automatic
    // 用 @AppStorage 與設定頁共用同一旗標
    @AppStorage(SettingsKeys.alertsPaused) private var isPaused = false

    /// 目前顯示對象（家人切換器過濾後）
    private var visibleMembers: [LocalFamilyMember] {
        guard let key = selectedMemberKey else { return members }
        return members.filter { $0.memberKey == key }
    }

    private var allActiveEvents: [LocalSafetyEvent] {
        events.filter { !$0.isEnded && !$0.isArchived && !EventVisibility.isSuppressed($0) }
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

    private var confirmingCount: Int {
        allActiveEvents.filter { !$0.isOfficiallyConfirmed }.count
    }

    private var elsewhereCount: Int {
        allActiveEvents.filter { event in
            event.isOfficiallyConfirmed
                && AlertPolicy.evaluate(event: event, members: visibleMembers).matches.isEmpty
        }.count
    }

    /// 框住目前顯示對象所有生活圈的鏡頭範圍
    private var circlesRegion: MapCameraPosition {
        let circles = visibleMembers.flatMap(\.lifeCircles)
        guard !circles.isEmpty else { return .automatic }
        let lats = circles.map(\.latitude)
        let lons = circles.map(\.longitude)
        // 邊界加緩衝：至少涵蓋最大半徑的兩倍，避免圈貼著螢幕邊
        let maxRadiusDeg = Double(circles.map(\.radiusMeters).max() ?? 1000) / 111_000 * 2.5
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(lats.max()! - lats.min()! + maxRadiusDeg, 0.02),
            longitudeDelta: max(lons.max()! - lons.min()! + maxRadiusDeg, 0.02)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    var body: some View {
        NavigationStack {
            map
                .onAppear { cameraPosition = circlesRegion }
                .overlay(alignment: .top) {
                    if !isChromeHidden { topOverlays }
                }
                .overlay(alignment: .bottomTrailing) { chromeToggle }
                // 治安層免責說明：統計≠即時安全程度，避免標籤化社區（產品倫理要求）
                .overlay(alignment: .bottomLeading) {
                    if showCrimeLayer {
                        Text("治安參考為\(crimeReference?.period.prefix(5) ?? "")季度歷史統計，僅供參考，不代表實際安全程度")
                            .font(.caption2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.leading, 12)
                            .padding(.bottom, 12)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !isChromeHidden { nearbyStrip }
                }
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

    /// 區域警報塗層：受影響行政區整片著色（依嚴重度取色，同區取最嚴重）。
    /// 為什麼是塗層不是大頭針：強風/豪雨這類警報影響的是「一整個行政區」，
    /// 釘一個點會錯誤暗示事件發生在該點。
    private struct AlertArea: Identifiable {
        let id: String
        let ring: [CLLocationCoordinate2D]
        let severityRank: Int
    }

    private var alertAreas: [AlertArea] {
        // 只塗天災與公共安全：交通/民生類（捷運誤點、局部停水）把整區塗色會造成
        // 視覺洪水，反而稀釋真正的危險訊號；它們仍在提醒中心的分組清單裡
        let paintable = activeRegionAlerts.filter { ["天災", "公共安全"].contains($0.group) }
        // 同一區被多則警報涵蓋時取最嚴重的顏色
        var severityByTown: [String: (rank: Int, severity: String)] = [:]
        for alert in paintable {
            let rank = Self.severityRank(alert.severity)
            for town in alert.affectedDistricts where town != Districts.unspecified {
                if rank > (severityByTown[town]?.rank ?? -1) {
                    severityByTown[town] = (rank, alert.severity)
                }
            }
        }
        return severityByTown.flatMap { town, info in
            DistrictBoundaries.shared.districts(named: town).flatMap { district in
                district.rings.enumerated().map { index, ring in
                    AlertArea(id: "\(district.county)-\(town)-\(index)", ring: ring, severityRank: info.rank)
                }
            }
        }
    }

    private static func severityRank(_ severity: String) -> Int {
        switch severity {
        case "危急": 3
        case "警戒": 2
        case "注意": 1
        default: 0 // 留意／提醒
        }
    }

    private static func severityColor(_ rank: Int) -> Color {
        switch rank {
        case 3: .red
        case 2: .red
        case 1: .orange
        default: .yellow
        }
    }

    /// 治安參考塗層：只塗「高於全國中位數」的行政區（四分位分級），
    /// 低於中位數不塗——全塗會讓圖層變成無資訊的雜訊。
    private var crimeAreas: [AlertArea] {
        guard let reference = crimeReference, !reference.districts.isEmpty else { return [] }
        let totals = reference.districts.map(\.total).sorted()
        let p50 = totals[totals.count / 2]
        let p75 = totals[totals.count * 3 / 4]
        let p90 = totals[min(totals.count * 9 / 10, totals.count - 1)]
        func normalize(_ s: String) -> String { s.replacingOccurrences(of: "臺", with: "台") }

        return reference.districts.flatMap { district -> [AlertArea] in
            let tier: Int
            switch district.total {
            case let t where t >= p90: tier = 3
            case let t where t >= p75: tier = 2
            case let t where t >= p50: tier = 1
            default: return [] // 低於中位數不塗
            }
            return DistrictBoundaries.shared.districts(named: district.town)
                .filter { normalize($0.county) == normalize(district.county) } // 縣市也要對上，避免同名區誤塗
                .flatMap { boundary in
                    boundary.rings.enumerated().map { index, ring in
                        AlertArea(id: "crime-\(district.county)-\(district.town)-\(index)",
                                  ring: ring, severityRank: tier)
                    }
                }
        }
    }

    private static func crimeOpacity(_ tier: Int) -> Double {
        switch tier {
        case 3: 0.32
        case 2: 0.20
        default: 0.10
        }
    }

    private var map: some View {
        Map(position: $cameraPosition) {
            if showCrimeLayer {
                ForEach(crimeAreas) { area in
                    MapPolygon(coordinates: area.ring)
                        .foregroundStyle(.indigo.opacity(Self.crimeOpacity(area.severityRank)))
                }
            }
            if showAlertAreas {
                ForEach(alertAreas) { area in
                    MapPolygon(coordinates: area.ring)
                        .foregroundStyle(Self.severityColor(area.severityRank).opacity(0.18))
                        .stroke(Self.severityColor(area.severityRank).opacity(0.55), lineWidth: 1)
                }
            }
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
                    .accessibilityLabel("\(event.title)，\(event.trustStatus)，\(event.approximateLocation)")
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
            if showAirQuality {
                ForEach(aqiStations) { station in
                    Annotation(station.name ?? "測站",
                               coordinate: .init(latitude: station.latitude, longitude: station.longitude)) {
                        Text("\(station.aqi)")
                            .font(.caption2.bold())
                            .foregroundStyle(station.aqi > 100 ? .white : .black)
                            .padding(6)
                            .background(station.color, in: Circle())
                            .accessibilityLabel("\(station.name ?? "")空品測站，AQI \(station.aqi)，\(station.status ?? "")")
                    }
                }
            }
        }
        // 開啟空品圖層時才抓資料（不開不花流量）
        .onChange(of: showAirQuality) { _, isOn in
            guard isOn, aqiStations.isEmpty else { return }
            Task {
                do {
                    aqiStations = try await AirQualityService.fetchStations()
                } catch {
                    AppLog.dataError("空品資料抓取失敗：\(error.localizedDescription)")
                }
            }
        }
        .onChange(of: showCrimeLayer) { _, isOn in
            guard isOn, crimeReference == nil else { return }
            Task {
                do {
                    crimeReference = try await CrimeReferenceService.fetch()
                } catch {
                    AppLog.dataError("治安統計抓取失敗：\(error.localizedDescription)")
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
            cameraPosition = circlesRegion
        }
    }

    /// 圖層與過濾：資源圖層開關＋事件類型與可信度過濾
    private var filterMenu: some View {
        Menu {
            Section("圖層") {
                Toggle("生活圈範圍", isOn: $showCircles)
                Toggle("區域警報範圍", isOn: $showAlertAreas)
                Toggle("避難收容所", isOn: $showShelters)
                Toggle("急救責任醫院", isOn: $showHospitals)
                Toggle("空氣品質（每小時）", isOn: $showAirQuality)
                Toggle("治安參考（季更統計）", isOn: $showCrimeLayer)
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

    /// 乾淨地圖模式切換鈕：收起／恢復資訊浮層。
    /// 永遠可見（否則收起後沒有入口恢復）；有「需要注意」事件時不隱藏警示——
    /// 收起的只是摘要卡與卡片列，地圖上的事件標記仍在。
    private var chromeToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isChromeHidden.toggle() }
        } label: {
            Image(systemName: isChromeHidden
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
                .font(.body.weight(.semibold))
                .padding(12)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.bottom, 12)
        .accessibilityLabel(isChromeHidden ? "顯示資訊面板" : "收合資訊面板，只看地圖")
    }

    private var topOverlays: some View {
        safetySummary
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// 一張摘要卡先回答安全狀態，再提供各層級事件與區域警報的入口。
    private var safetySummary: some View {
        let hasAttention = attentionCount > 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: hasAttention ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                    .foregroundStyle(hasAttention ? .red : .green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasAttention ? "生活圈有需要注意的事件" : "生活圈目前沒有需要注意的事件")
                        .font(.subheadline.bold())
                    Text(hasAttention ? "已確認且位於提醒範圍內：\(attentionCount) 件" : "持續留意資料更新即可")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if isSummaryExpanded {
                HStack(spacing: 8) {
                    summaryMetric("需要注意", count: attentionCount, emphasis: hasAttention)
                    summaryMetric("確認中（不限生活圈）", count: confirmingCount, emphasis: false)
                    summaryMetric("其他區域", count: elsewhereCount, emphasis: false)
                }

                if let alert = activeRegionAlerts.first {
                    Button {
                        selectedAlert = alert
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: alert.iconName)
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            Text("區域警報：\(alert.kind)｜\(alert.title)")
                                .font(.caption.bold())
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("區域警報：\(alert.kind)，\(alert.title)")
                }
            } else {
                Button("查看確認中 \(confirmingCount) 件、其他區域 \(elsewhereCount) 件與區域警報 \(activeRegionAlerts.count) 則") {
                    withAnimation { isSummaryExpanded = true }
                }
                .font(.caption)
            }

            if isSummaryExpanded {
                Button("收合摘要") {
                    withAnimation { isSummaryExpanded = false }
                }
                .font(.caption.bold())
            }

            VStack(alignment: .leading, spacing: 2) {
                if isPaused {
                    Text("提醒已暫停——事件仍會顯示，但不會推播。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                DataFreshnessLabel()
            }
        }
        .padding(12)
        .background((hasAttention ? Color.red : Color.green).opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func summaryMetric(_ title: String, count: Int, emphasis: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(count) 件")
                .font(.caption.bold())
                .foregroundStyle(emphasis ? .red : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
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
