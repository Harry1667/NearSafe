import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import os

struct CircleEditorView: View {
    let member: LocalFamilyMember
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
    // 目前位置與跟隨圈
    @State private var picked: CLLocationCoordinate2D?
    @State private var pickedLabel = ""
    @State private var locating = false
    @State private var locationHint = ""
    @State private var isFollowMe = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("地點名稱", text: $name)
                if !isFollowMe {
                    TextField("地址或地標", text: $address)
                    Button("使用 Apple Maps 搜尋") {
                        Task { await search() }
                    }
                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        HStack {
                            Label("使用目前位置", systemImage: "location.fill")
                            if locating { Spacer(); ProgressView() }
                        }
                    }
                    if !pickedLabel.isEmpty {
                        Text("已取得目前位置：\(pickedLabel)").foregroundStyle(HCColor.safe)
                    } else if !locationHint.isEmpty {
                        Text(locationHint).font(.caption).foregroundStyle(HCColor.attention)
                    }
                    if let found, picked == nil {
                        Text("找到：\(found.name ?? address)").foregroundStyle(HCColor.safe)
                    } else if searchFailed && picked == nil {
                        Text("找不到這個地點，會改用預設座標（台北市中心）")
                            .font(.caption)
                            .foregroundStyle(HCColor.attention)
                    }
                }
                followSection
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
            .navigationTitle("新增生活圈")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    /// 跟隨圈：圈心跟著這台手機移動。開啟後隱藏地址輸入（地址沒有意義），
    /// 需要「永遠允許」定位權限；隱私邊界寫明在 footer，位置只留本機
    private var followSection: some View {
        Section {
            Toggle("跟著我移動", isOn: $isFollowMe)
                .onChange(of: isFollowMe) { _, on in
                    if on {
                        LocationService.shared.requestAlwaysPermission()
                        // 順手抓一次目前位置當初始圈心，省得存檔後要等第一次顯著位置變更
                        Task { await useCurrentLocation() }
                    }
                }
        } footer: {
            Text("開啟後這個圈會跟著這台手機移動（約每移動 500 公尺更新一次，走到哪守到哪）。需要定位權限設為「永遠允許」。你的位置只留在這台手機，不會上傳或分享給任何人。")
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
        locationHint = ""
        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            let label = [placemark.locality, placemark.subLocality].compactMap { $0 }.joined()
            pickedLabel = label.isEmpty ? "座標已取得" : label
            if district == Districts.unspecified {
                let text = [placemark.subAdministrativeArea, placemark.locality,
                            placemark.subLocality, placemark.name].compactMap { $0 }.joined(separator: " ")
                district = OnboardingView.guessDistrict(from: text)
            }
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
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address
        do {
            found = try await MKLocalSearch(request: request).start().mapItems.first
            searchFailed = (found == nil)
            // 搜尋成功且尚未手動選行政區時，從地址文字自動帶入
            if district == Districts.unspecified {
                district = OnboardingView.guessDistrict(from: "\(found?.name ?? "") \(address)")
            }
        } catch {
            AppLog.data.error("地點搜尋失敗：\(error.localizedDescription)")
            found = nil
            searchFailed = true
        }
    }

    private func save() {
        // 座標優先序：目前位置 > 地圖搜尋結果 > 預設（台北市中心）。
        // 跟隨圈存檔後 300 公尺內的第一次顯著位置變更就會把圈心校正到實際位置
        let coordinate = picked ?? found?.location.coordinate ?? .init(latitude: 25.035, longitude: 121.54)
        let circle = LocalLifeCircle(
            name: name.isEmpty ? (isFollowMe ? "我的位置" : "生活圈") : name,
            encryptedAddress: isFollowMe ? "跟著我移動" : (pickedLabel.isEmpty ? (found?.name ?? address) : pickedLabel),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusMeters: radius,
            alertTypes: EventCategory.defaultSelection,
            member: member
        )
        circle.scheduleEnabled = scheduleEnabled
        circle.scheduleWeekdays = Array(weekdays).sorted()
        circle.scheduleStartHour = startHour
        circle.scheduleEndHour = endHour
        circle.district = district
        circle.isFollowMe = isFollowMe
        context.insert(circle)
        context.saveReporting()
        // 跟隨圈的監聽開關要跟著圈的存亡走
        LocationService.shared.syncFollowMonitoring(
            hasFollowCircle: FollowCircleService.hasFollowCircle(context: context)
        )
        dismiss()
    }
}
