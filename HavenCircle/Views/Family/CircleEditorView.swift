import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import os

struct CircleEditorView: View {
    let member: LocalFamilyMember
    let circle: LocalLifeCircle?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var radius = 1000
    @State private var found: MKMapItem?
    @State private var searchFailed = false
    @State private var district = Districts.unspecified
    @State private var scheduleEnabled = false
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]  // 預設週一到週五
    @State private var startHour = 8
    @State private var endHour = 19
    // 可把目前位置保存成固定圈；儲存後不會跟著手機移動
    @State private var picked: CLLocationCoordinate2D?
    @State private var pickedLabel = ""
    @State private var locating = false
    @State private var locationHint = ""
    @State private var locationNeedsConfirmation: Bool
    /// 行政區是否由地址搜尋／目前位置反查「自動判定」而來（非使用者手動在進階設定裡挑的）；
    /// 只用來決定要不要顯示「自動判定」提示行，不影響實際儲存的 district 值。
    @State private var districtAutoDetected = false
    /// 「進階設定」（手動行政區 Picker）展開狀態：新增地點情境下預設展開，
    /// 自動判定成功就收合，判定失敗（含尚未查詢）維持展開讓人手動挑。
    @State private var advancedExpanded = false

    /// 新增地點接續情境：從 PlaceSelectView 選完地點名稱、550ms 後直接接著開這裡建第一個固定圈。
    /// 此時 member 名稱就是使用者剛選的地點名稱（住家／公司／⋯），標題與欄位預填據此客製化；
    /// 編輯既有圈或替一般家人新增圈都不算，外觀維持原本樣子（見 body 內 districtSection 分支）。
    private let isNewPlaceCircle: Bool

    init(member: LocalFamilyMember, circle: LocalLifeCircle? = nil) {
        self.member = member
        self.circle = circle
        let isNewPlaceCircle = member.isPlace && circle == nil
        self.isNewPlaceCircle = isNewPlaceCircle
        _name = State(initialValue: circle?.name ?? (isNewPlaceCircle ? member.name : ""))
        _address = State(initialValue: circle?.addressText ?? "")
        _radius = State(initialValue: circle?.radiusMeters ?? 1_000)
        _district = State(initialValue: circle?.district ?? Districts.unspecified)
        _scheduleEnabled = State(initialValue: circle?.scheduleEnabled ?? false)
        _weekdays = State(initialValue: Set(circle?.scheduleWeekdays ?? [2, 3, 4, 5, 6]))
        _startHour = State(initialValue: circle?.scheduleStartHour ?? 8)
        _endHour = State(initialValue: circle?.scheduleEndHour ?? 19)
        _locationNeedsConfirmation = State(initialValue: circle == nil)
        // 尚未做過任何自動判定嘗試前，進階設定預設展開，讓使用者一開始就能手動挑
        _advancedExpanded = State(initialValue: true)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("地點名稱", text: $name)
                TextField("地址或地標", text: $address)
                    .onChange(of: address) { oldValue, newValue in
                        guard oldValue != newValue,
                              newValue != circle?.addressText,
                              newValue != pickedLabel else { return }
                        found = nil
                        picked = nil
                        pickedLabel = ""
                        searchFailed = false
                        locationNeedsConfirmation = true
                    }
                    // 停止輸入 0.7 秒就自動搜尋（每次改字 task 會重啟，形成 debounce）；
                    // 下方按鈕保留，給想立即搜尋或自動搜尋失敗後重試的人
                    .task(id: address) {
                        let query = address.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !query.isEmpty,
                              address != circle?.addressText,
                              address != pickedLabel,
                              found == nil, picked == nil else { return }
                        do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
                        await search()
                    }
                Button("使用 Apple Maps 搜尋") {
                    Task { await search() }
                }
                .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button {
                    Task { await useCurrentLocation() }
                } label: {
                    HStack {
                        Label("把目前位置設為固定地點", systemImage: "location.fill")
                        if locating { Spacer(); ProgressView() }
                    }
                }
                if !pickedLabel.isEmpty {
                    Text("已確認位置：\(pickedLabel)").foregroundStyle(HCColor.safe)
                } else if !locationHint.isEmpty {
                    Text(locationHint).font(.caption).foregroundStyle(HCColor.attention)
                }
                if let found, picked == nil {
                    Text("找到：\(found.name ?? address)").foregroundStyle(HCColor.safe)
                } else if searchFailed && picked == nil {
                    Text("找不到這個地點，請修改地址或改用目前位置；未確認前不會儲存這個地點。")
                        .font(.caption)
                        .foregroundStyle(HCColor.attention)
                }
                Stepper("通知範圍：\(radius) 公尺", value: $radius, in: 300...3000, step: 100)
                districtSection
                Text("提醒類型：\(EventCategory.defaultSelection.joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                scheduleSection
            }
            .navigationTitle(navigationTitleText)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                        .disabled(!canSave)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .analyticsScreen("circle_editor")
        }
    }

    /// 導覽標題：新增地點接續情境講人話（帶出剛選的地點名稱），其餘情境沿用「守護地點」語彙
    private var navigationTitleText: String {
        if isNewPlaceCircle { return "把「\(member.name)」放上地圖" }
        return circle == nil ? "守護這個地點" : "編輯守護地點"
    }

    /// 所在行政區欄位：新增地點接續情境下改成「自動判定＋收進進階設定」，
    /// 其餘情境（編輯既有圈、替一般家人新增圈）外觀維持原本常駐 Picker。
    @ViewBuilder
    private var districtSection: some View {
        if isNewPlaceCircle {
            if districtAutoDetected, district != Districts.unspecified {
                Text("所在行政區：\(district)（自動判定）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            DisclosureGroup("進階設定", isExpanded: $advancedExpanded) {
                Picker("所在行政區", selection: districtBinding) {
                    ForEach(Districts.all, id: \.self) { Text($0) }
                }
                Text("行政區用於颱風、豪雨等區域型警報的比對，已支援全國鄉鎮市區；沒把握就選「未指定」，仍可收到點狀事件與全國官方警報。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Picker("所在行政區", selection: districtBinding) {
                ForEach(Districts.all, id: \.self) { Text($0) }
            }
            Text("行政區用於颱風、豪雨等區域型警報的比對，已支援全國鄉鎮市區；沒把握就選「未指定」，仍可收到點狀事件與全國官方警報。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 使用者手動在 Picker 挑行政區時，視為不再是自動判定的結果，讓上面的「自動判定」提示行消失
    private var districtBinding: Binding<String> {
        Binding(
            get: { district },
            set: { newValue in
                district = newValue
                districtAutoDetected = false
            }
        )
    }

    /// 自動判定行政區的共用邏輯：只從 Districts.all 這個集合裡挑值（guessDistrict 內部已用包含比對
    /// 對到集合項），對不到就維持「未指定」並展開進階設定讓使用者手動選——絕不寫入集合外的自創字串，
    /// 否則會讓區域型警報的行政區比對失效。已有值（含使用者手動選過）時不覆蓋。
    private func applyAutoDetectedDistrict(_ matched: String) {
        guard district == Districts.unspecified else { return }
        if matched != Districts.unspecified {
            district = matched
            districtAutoDetected = true
            advancedExpanded = false
        } else {
            districtAutoDetected = false
            advancedExpanded = true
        }
    }

    /// 一鍵帶入目前位置：反查地名與行政區，取代手動輸入地址
    private func useCurrentLocation() async {
        locating = true
        defer { locating = false }
        guard LocationService.shared.isAuthorized else {
            LocationService.shared.requestPermissionIfNeeded()
            locationHint = "請先允許定位權限，再點一次"
            return
        }
        guard let location = await LocationService.shared.currentLocation() else {
            locationHint = "取不到目前位置，請稍後再試或改用地址搜尋"
            return
        }
        picked = location.coordinate
        locationNeedsConfirmation = false
        locationHint = ""
        if let place = await MapReverseGeocoder.lookup(location) {
            let matchedDistrict = OnboardingView.guessDistrict(from: place.searchableText)
            pickedLabel = place.approximateLabel(district: matchedDistrict) ?? "座標已取得"
            applyAutoDetectedDistrict(matchedDistrict)
            if address.isEmpty { address = pickedLabel }
        } else {
            pickedLabel = "座標已取得"
        }
    }

    /// 時段感知設定：公司圈只在上班時間推播、住家圈只在夜間等。
    /// 時段外的官方事件仍會顯示在 App 內，只是不推播。
    private var scheduleSection: some View {
        Section {
            Toggle("只在特定時段提醒", isOn: $scheduleEnabled)
            if scheduleEnabled {
                HStack {
                    ForEach(1...7, id: \.self) { day in
                        let names = ["日", "一", "二", "三", "四", "五", "六"]
                        Button(names[day - 1]) {
                            if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                        }
                        .buttonStyle(.bordered)
                        .tint(weekdays.contains(day) ? HCColor.brand : .gray)
                        .font(.caption)
                    }
                }
                Stepper("開始：\(startHour):00", value: $startHour, in: 0...23)
                Stepper("結束：\(endHour):00", value: $endHour, in: (startHour + 1)...24)
                Text("時段外的官方事件仍會顯示在 App 內，只是不推播。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func search() async {
        let query = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            found = nil
            searchFailed = false
            locationNeedsConfirmation = true
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        do {
            found = try await MKLocalSearch(request: request).start().mapItems.first
            searchFailed = (found == nil)
            locationNeedsConfirmation = (found == nil)
            // 搜尋成功時嘗試從地址文字自動帶入行政區（已有值時 applyAutoDetectedDistrict 內部會自動略過）
            applyAutoDetectedDistrict(OnboardingView.guessDistrict(from: "\(found?.name ?? "") \(address)"))
        } catch {
            AppLog.data.error("地點搜尋失敗：\(error.localizedDescription)")
            found = nil
            searchFailed = true
            locationNeedsConfirmation = true
        }
    }

    private var canSave: Bool {
        guard !locationNeedsConfirmation else { return false }
        return picked != nil || found != nil || circle != nil
    }

    private func save() {
        guard canSave else { return }
        let coordinate = picked
            ?? found?.location.coordinate
            ?? circle.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        guard let coordinate else { return }
        let target = circle ?? LocalLifeCircle(
            name: "守護地點",
            encryptedAddress: "",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusMeters: radius,
            alertTypes: EventCategory.defaultSelection,
            member: member
        )
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "守護地點" : name
        target.setAddress(pickedLabel.isEmpty ? (found?.name ?? address) : pickedLabel)
        target.latitude = coordinate.latitude
        target.longitude = coordinate.longitude
        target.radiusMeters = radius
        target.scheduleEnabled = scheduleEnabled
        target.scheduleWeekdays = Array(weekdays).sorted()
        target.scheduleStartHour = startHour
        target.scheduleEndHour = endHour
        target.district = district
        target.kind = .fixed
        if circle == nil { context.insert(target) }
        context.saveReporting()
        dismiss()
    }
}
