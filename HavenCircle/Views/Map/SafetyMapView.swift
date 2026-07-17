import SwiftUI
import SwiftData
import MapKit

/// 安全地圖：全螢幕地圖為主體，狀態橫幅、區域警報與附近更新以浮層呈現。
struct SafetyMapView: View {
    @Environment(FamilySyncService.self) private var sync
    @Environment(\.modelContext) private var modelContext
    @Query private var events: [LocalSafetyEvent]
    @Query private var members: [LocalFamilyMember]
    @Query private var regionAlerts: [RegionAlert]
    @State private var selected: LocalSafetyEvent?
    @State private var selectedAlert: RegionAlert?

    // 圖層與過濾（顯示偏好，不影響通知決策）
    @State private var showCircles = true
    @State private var showAlertAreas = true
    /// 避難所／醫院圖層：已接上消防署／衛福部開放資料（近 6,000 筆官方座標）。
    /// 預設關；開啟後只在鏡頭夠近時顯示視野內最近的一批，全國點位一次全畫會拖垮地圖。
    @State private var showShelters = false
    @State private var showHospitals = false
    /// 目前鏡頭範圍，供資源圖層做視野內過濾
    @State private var visibleRegion: MKCoordinateRegion?
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

    // 守護圈開場（簽名動效）：Onboarding 完成後首次進地圖才演一次
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 開場進行中：摘要卡先隱藏，鏡頭抵達生活圈後才進場
    @State private var isIntroRunning = false
    /// 盾牌確認脈衝：翻轉一次觸發 symbolEffect bounce 與成功觸覺
    @State private var shieldConfirmPulse = false

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
        SafetyOverview.activeEvents(events)
    }

    /// 套用圖層過濾後、顯示在地圖與卡片上的事件
    private var filteredEvents: [LocalSafetyEvent] {
        allActiveEvents.filter {
            enabledTypes.contains($0.eventType) && (showUnverified || $0.isOfficiallyConfirmed)
        }
    }

    /// 安全狀態一律以「未過濾」的事件計算——聚合邏輯與安心頁共用 SafetyStatus，
    /// 兩頁對「平安與否」的說法永遠一致
    private var status: SafetyOverview {
        SafetyOverview.compute(events: events, regionAlerts: regionAlerts, members: visibleMembers)
    }

    private var attentionCount: Int { status.attentionCount }
    private var confirmingCount: Int { status.confirmingCount }
    private var elsewhereCount: Int { status.elsewhereCount }

    private var activeRegionAlerts: [RegionAlert] {
        regionAlerts.filter { !$0.isEnded }
    }

    private var visibleCircles: [LocalLifeCircle] {
        visibleMembers.flatMap(\.lifeCircles)
    }

    /// 尚未開啟即時圈的家人，仍可顯示最近一次主動安否回報的位置。
    private var familyPingAnnotations: [SafetyPing] {
        let liveNames = Set(sync.liveLocations.filter(\.isSharing).map(\.displayName))
        var latest: [String: SafetyPing] = [:]
        for ping in sync.pings where ping.hasLocation && !liveNames.contains(ping.senderName) {
            if let kept = latest[ping.senderName], kept.createdAt >= ping.createdAt { continue }
            latest[ping.senderName] = ping
        }
        return Array(latest.values)
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
                // 功能導覽直接讀取地圖實際版面，不再用機型相關的安全區域常數猜位置。
                .tourAnchor(.mapCanvas)
                .onAppear {
                    playGuardianIntroIfNeeded()
                    // 地圖藍點需要定位權限；只在未決定時跳系統框，拒絕過就不再打擾
                    LocationService.shared.requestPermissionIfNeeded()
                }
                .task {
                    await sync.fetchPings()
                    await sync.fetchLiveLocations(context: modelContext)
                }
                .overlay(alignment: .top) {
                    if !isChromeHidden { topOverlays }
                }
                .overlay(alignment: .bottomTrailing) { chromeToggle }
                // 圖例：地圖有多層塗色，沒有圖例評審與使用者都無法自行解讀顏色
                // （含治安層免責：統計≠即時安全程度，避免標籤化社區——產品倫理要求）
                .overlay(alignment: .bottomLeading) {
                    if !isChromeHidden { legendPanel }
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
            let rank = RegionAlert.severityRank(alert.severity)
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

    // 嚴重度排序與配色已上移到 RegionAlert extension（Theme.swift）：
    // 警報卡、塗層、圖例共用同一套，避免「卡片的紅」與「地圖的紅」不一致

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
                        .foregroundStyle(HCColor.reference.opacity(Self.crimeOpacity(area.severityRank)))
                }
            }
            if showAlertAreas {
                ForEach(alertAreas) { area in
                    MapPolygon(coordinates: area.ring)
                        .foregroundStyle(RegionAlert.severityColor(rank: area.severityRank).opacity(0.18))
                        .stroke(RegionAlert.severityColor(rank: area.severityRank).opacity(0.55), lineWidth: 1)
                }
            }
            if showCircles {
                ForEach(visibleCircles) { circle in
                    let circleColor: Color = circle.kind == .live ? HCColor.safe : HCColor.brand
                    let renderedColor = circle.isActiveForAlerts ? circleColor : Color.gray
                    MapCircle(
                        center: .init(latitude: circle.latitude, longitude: circle.longitude),
                        radius: CLLocationDistance(circle.radiusMeters)
                    )
                    .foregroundStyle(renderedColor.opacity(0.08))
                    .stroke(renderedColor.opacity(0.5), lineWidth: 1.5)
                    Annotation(
                        circle.name,
                        coordinate: .init(latitude: circle.latitude, longitude: circle.longitude)
                    ) {
                        VStack(spacing: 2) {
                            Image(systemName: circle.kind.iconName)
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(renderedColor, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            Text(circle.kind.title)
                                .font(.system(size: 9, weight: .semibold))
                            if circle.kind == .live {
                                Text(circle.locationFreshnessText)
                                    .font(.system(size: 8))
                                    .foregroundStyle(circle.isActiveForAlerts ? .secondary : HCColor.attention)
                            }
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "\(circle.name)，\(circle.kind.title)，警戒半徑 \(circle.radiusMeters) 公尺，\(circle.locationFreshnessText)"
                        )
                    }
                }
            }
            // 資源點放在事件標記之前宣告，讓事件永遠蓋在資源點上層
            if showShelters, let region = resourceRegion {
                ForEach(EmergencyResourceStore.resources(kind: ResourceKind.shelter, in: region, limit: 60)) { resource in
                    resourceAnnotation(resource, icon: "tent.fill", color: HCColor.safe)
                }
            }
            if showHospitals, let region = resourceRegion {
                ForEach(EmergencyResourceStore.resources(kind: ResourceKind.hospital, in: region, limit: 30)) { resource in
                    resourceAnnotation(resource, icon: "cross.case.fill", color: HCColor.medical)
                }
            }
            ForEach(filteredEvents) { event in
                Annotation(event.isDrill ? "演練" : event.eventType,
                           coordinate: .init(latitude: event.latitude, longitude: event.longitude)) {
                    Button {
                        selected = event
                    } label: {
                        // 兩套視覺通道：圖示＝事件類型、顏色＝可信度（官方紅／確認中琥珀）；
                        // 白色外圈讓標記在任何底圖上都可辨識
                        Image(systemName: event.isDrill
                              ? "bell.and.waves.left.and.right"
                              : EventCategory.icon(for: event.eventType))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(event.isOfficiallyConfirmed ? HCColor.danger : HCColor.attention, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    }
                    .accessibilityLabel("\(event.title)，\(event.trustStatus)，\(event.approximateLocation)")
                }
            }
            // 自己的位置（藍點）：需要 when-in-use 權限，未授權時 MapKit 自動不畫
            UserAnnotation()
            // 沒有即時圈時，以最近一次自願安否回報位置作為降級資訊。
            ForEach(familyPingAnnotations, id: \.id) { ping in
                Annotation(ping.senderName,
                           coordinate: .init(latitude: ping.latitude ?? 0, longitude: ping.longitude ?? 0)) {
                    VStack(spacing: 2) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(ping.status == .safe ? HCColor.safe : HCColor.danger, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                        Text(ping.createdAt.formatted(.relative(presentation: .named)))
                            .font(.system(size: 9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.thinMaterial, in: Capsule())
                    }
                    .accessibilityLabel("\(ping.senderName) \(ping.status.rawValue)，回報於\(ping.createdAt.formatted(date: .omitted, time: .shortened))，位置\(ping.placeName ?? "未知")")
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
        // 降噪底圖：壓低底圖彩度並排除 Apple Maps 的 POI（餐廳、商店……），
        // 讓警報塗層、生活圈與事件標記成為畫面主角，而不是跟底圖搶注意力
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
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
        // 鏡頭停下才更新（.onEnd），拖曳過程不重算資源過濾
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
        }
    }

    // MARK: - 緊急資源圖層

    /// 鏡頭夠近才顯示資源點：縮到全台視角時畫幾千個點既讀不了也拖效能
    private static let resourceZoomThreshold: CLLocationDegrees = 0.35
    private var resourceRegion: MKCoordinateRegion? {
        guard let region = visibleRegion,
              region.span.latitudeDelta <= Self.resourceZoomThreshold else { return nil }
        return region
    }

    /// 點資源標記→在 Apple 地圖顯示該地點（不直接發起導航，把決定權留給使用者）
    private func resourceAnnotation(_ resource: EmergencyResource, icon: String, color: Color) -> some MapContent {
        Annotation(resource.name, coordinate: .init(latitude: resource.latitude, longitude: resource.longitude)) {
            Button {
                var components = URLComponents(string: "https://maps.apple.com/")
                components?.queryItems = [
                    URLQueryItem(name: "q", value: resource.name),
                    URLQueryItem(name: "ll", value: "\(resource.latitude),\(resource.longitude)"),
                ]
                if let url = components?.url { UIApplication.shared.open(url) }
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(color, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
            }
            .accessibilityLabel("\(resource.kind)：\(resource.name)，點擊在地圖 App 查看")
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
                Toggle("警戒圈範圍", isOn: $showCircles)
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
        .tint(isPaused ? HCColor.attention : nil)
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
        // 開場時摘要卡先退場，鏡頭抵達生活圈後縮放進場（Reduce Motion 只做淡入不縮放）
        .scaleEffect(isIntroRunning && !reduceMotion ? 0.9 : 1, anchor: .top)
        .opacity(isIntroRunning ? 0 : 1)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.45) : .spring(response: 0.5, dampingFraction: 0.75),
            value: isIntroRunning
        )
        // 進場完成的「守護開始」確認觸覺，與盾牌 bounce 同一個觸發源
        .sensoryFeedback(.success, trigger: shieldConfirmPulse)
    }

    // MARK: - 守護圈開場（簽名動效）

    /// 開場起點：全台廣域鏡頭
    private static let taiwanWideRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 23.7, longitude: 120.96),
        span: MKCoordinateSpan(latitudeDelta: 4.6, longitudeDelta: 4.6)
    )

    /// Onboarding 完成後首次進地圖：鏡頭從全台飛向生活圈，抵達後摘要卡進場、
    /// 盾牌 bounce＋成功觸覺——把「開始守護這個範圍」演成一個確認儀式。
    /// 旗標消耗制只演一次；Reduce Motion 時不飛鏡頭，改直接定位＋交叉淡入。
    private func playGuardianIntroIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKeys.guardianIntroPending) else {
            cameraPosition = circlesRegion
            return
        }
        defaults.set(false, forKey: SettingsKeys.guardianIntroPending)
        isIntroRunning = true
        if reduceMotion {
            cameraPosition = circlesRegion
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                isIntroRunning = false
                shieldConfirmPulse.toggle()
            }
            return
        }
        cameraPosition = .region(Self.taiwanWideRegion)
        Task { @MainActor in
            // 讓廣域畫面站穩一拍再起飛，觀眾才看得出「從哪裡飛到哪裡」
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeInOut(duration: 1.5)) { cameraPosition = circlesRegion }
            try? await Task.sleep(for: .milliseconds(1700))
            isIntroRunning = false
            shieldConfirmPulse.toggle()
        }
    }

    /// 圖例面板：只在對應圖層開啟且畫面上真的有塗色時出現，避免常駐佔位
    @ViewBuilder
    private var legendPanel: some View {
        let showsSeverity = showAlertAreas && !alertAreas.isEmpty
        // 資源圖層開著但鏡頭太遠時，要說明「為什麼看不到點」——不說會像壞掉
        let resourceHint = (showShelters || showHospitals) && resourceRegion == nil
        if showsSeverity || showCrimeLayer || resourceHint || showCircles {
            VStack(alignment: .leading, spacing: 5) {
                if showCircles {
                    Text("警戒圈").font(.caption2.bold())
                    legendRow(HCColor.safe.opacity(0.8), "即時圈（跟隨家人手機）")
                    legendRow(HCColor.brand.opacity(0.8), "固定圈（住家／資產）")
                    legendRow(Color.gray.opacity(0.8), "即時位置已過期")
                }
                if showsSeverity {
                    Text("警報區").font(.caption2.bold())
                    legendRow(RegionAlert.severityColor(rank: 3), "警戒／危急")
                    legendRow(RegionAlert.severityColor(rank: 1), "注意")
                    legendRow(RegionAlert.severityColor(rank: 0), "留意／提醒")
                }
                if showCrimeLayer {
                    Text("治安參考").font(.caption2.bold())
                    legendRow(HCColor.reference.opacity(0.7), "季度統計高於全國中位數（越深越多）")
                    Text("統計≠即時安全程度，僅供參考")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if resourceHint {
                    Label("放大地圖即可顯示避難所／醫院", systemImage: "plus.magnifyingglass")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.leading, 12)
            .padding(.bottom, 12)
            .accessibilityElement(children: .combine)
        }
    }

    private func legendRow(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(color.opacity(0.8), lineWidth: 1))
                .frame(width: 14, height: 10)
            Text(text).font(.caption2)
        }
    }

    /// 摘要預設收成單行膠囊（把視野還給地圖），點開才展開完整卡。
    /// 平時整個畫面只有地圖與低彩度膠囊；真危險時膠囊變紅——警示色的獨佔舞台
    @ViewBuilder
    private var safetySummary: some View {
        if isSummaryExpanded { summaryCard } else { summaryCapsule }
    }

    private var summaryCapsule: some View {
        let hasAttention = attentionCount > 0
        let statusColor = hasAttention ? HCColor.danger : HCColor.safe
        return Button {
            withAnimation { isSummaryExpanded = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: hasAttention ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(statusColor, in: Circle())
                    .symbolEffect(.bounce, value: shieldConfirmPulse)
                Text(hasAttention ? "\(attentionCount) 件需要注意" : "警戒圈平安")
                    .font(.subheadline.weight(.semibold))
                if isPaused {
                    Image(systemName: "bell.slash.fill")
                        .font(.caption)
                        .foregroundStyle(HCColor.attention)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(statusColor.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            hasAttention
                ? "警戒圈有 \(attentionCount) 件需要注意的事件，點擊展開摘要"
                : "警戒圈平安\(isPaused ? "，提醒已暫停" : "")，點擊展開摘要"
        )
    }

    /// 展開版：完整安全狀態卡（各層級數字、區域警報入口、資料新鮮度）
    private var summaryCard: some View {
        let hasAttention = attentionCount > 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                // 盾牌放進色底圓形 chip：狀態色作底、白色圖示，讓「目前安全與否」一眼可辨
                Image(systemName: hasAttention ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(hasAttention ? HCColor.danger : HCColor.safe, in: Circle())
                    // 守護圈細環：與 Onboarding hero、提醒中心平安狀態同一個圓環 motif
                    .overlay(
                        Circle()
                            .stroke((hasAttention ? HCColor.danger : HCColor.safe).opacity(0.35), lineWidth: 1.5)
                            .frame(width: 42, height: 42)
                    )
                    .symbolEffect(.bounce, value: shieldConfirmPulse)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasAttention ? "警戒圈有需要注意的事件" : "警戒圈目前沒有需要注意的事件")
                        .font(.subheadline.bold())
                    Text(hasAttention ? "已確認且位於提醒範圍內：\(attentionCount) 件" : "持續留意資料更新即可")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                summaryMetric("需要注意", count: attentionCount, emphasis: hasAttention)
                summaryMetric("未驗證線索（不限警戒圈）", count: confirmingCount, emphasis: false)
                summaryMetric("其他區域", count: elsewhereCount, emphasis: false)
            }

            if let alert = activeRegionAlerts.first {
                Button {
                    selectedAlert = alert
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: alert.iconName)
                            .foregroundStyle(HCColor.attention)
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

            Button("收合摘要") {
                withAnimation { isSummaryExpanded = false }
            }
            .font(.caption.bold())

            VStack(alignment: .leading, spacing: 2) {
                if isPaused {
                    Text("提醒已暫停——事件仍會顯示，但不會推播。")
                        .font(.caption)
                        .foregroundStyle(HCColor.attention)
                }
                DataFreshnessLabel()
            }
        }
        .padding(HCSpacing.x3)
        .background(
            (hasAttention ? HCColor.danger : HCColor.safe).opacity(0.10),
            in: RoundedRectangle(cornerRadius: HCRadius.card, style: .continuous)
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HCRadius.card, style: .continuous))
    }

    private func summaryMetric(_ title: String, count: Int, emphasis: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(count) 件")
                .font(.caption.bold())
                .foregroundStyle(emphasis ? HCColor.danger : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    /// 附近更新：地圖底部的橫向卡片（依離生活圈最近排序，且真的要「附近」——
    /// 超過 NearbyScope 上限的事件只留在地圖與提醒中心，不冒充附近）
    @ViewBuilder
    private var nearbyStrip: some View {
        let nearby = filteredEvents.filter {
            nearestCircleDistance($0, visibleMembers) <= NearbyScope.maxMeters
        }
        if !nearby.isEmpty {
            let sorted = nearby.sorted {
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
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HCRadius.card, style: .continuous))
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

#if DEBUG
#Preview {
    SafetyMapView()
        .modelContainer(PreviewSupport.container())
}
#endif
