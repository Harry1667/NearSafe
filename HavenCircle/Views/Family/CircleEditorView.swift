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

    init(member: LocalFamilyMember, circle: LocalLifeCircle? = nil) {
        self.member = member
        self.circle = circle
        _name = State(initialValue: circle?.name ?? "")
        _address = State(initialValue: circle?.encryptedAddress ?? "")
        _radius = State(initialValue: circle?.radiusMeters ?? 1_000)
        _district = State(initialValue: circle?.district ?? Districts.unspecified)
        _scheduleEnabled = State(initialValue: circle?.scheduleEnabled ?? false)
        _weekdays = State(initialValue: Set(circle?.scheduleWeekdays ?? [2, 3, 4, 5, 6]))
        _startHour = State(initialValue: circle?.scheduleStartHour ?? 8)
        _endHour = State(initialValue: circle?.scheduleEndHour ?? 19)
        _locationNeedsConfirmation = State(initialValue: circle == nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("地點名稱", text: $name)
                TextField("地址或地標", text: $address)
                    .onChange(of: address) { oldValue, newValue in
                        guard oldValue != newValue,
                              newValue != circle?.encryptedAddress,
                              newValue != pickedLabel else { return }
                        found = nil
                        picked = nil
                        pickedLabel = ""
                        searchFailed = false
                        locationNeedsConfirmation = true
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
                    Text("找不到這個地點，請修改地址或改用目前位置；未確認前不會儲存固定圈。")
                        .font(.caption)
                        .foregroundStyle(HCColor.attention)
                }
                Stepper("提醒半徑：\(radius) 公尺", value: $radius, in: 300...3000, step: 100)
                Picker("所在行政區", selection: $district) {
                    ForEach(Districts.all, id: \.self) { Text($0) }
                }
                Text("行政區用於颱風、豪雨等區域型警報的比對，已支援全國鄉鎮市區；沒把握就選「未指定」，仍可收到點狀事件與全國官方警報。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("提醒類型：\(EventCategory.defaultSelection.joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                scheduleSection
            }
            .navigationTitle(circle == nil ? "新增固定圈" : "編輯固定圈")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                        .disabled(!canSave)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
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
            if district == Districts.unspecified { district = matchedDistrict }
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
            // 搜尋成功且尚未手動選行政區時，從地址文字自動帶入
            if district == Districts.unspecified {
                district = OnboardingView.guessDistrict(from: "\(found?.name ?? "") \(address)")
            }
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
            name: "固定圈",
            encryptedAddress: "",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusMeters: radius,
            alertTypes: EventCategory.defaultSelection,
            member: member
        )
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "固定圈" : name
        target.encryptedAddress = pickedLabel.isEmpty ? (found?.name ?? address) : pickedLabel
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
