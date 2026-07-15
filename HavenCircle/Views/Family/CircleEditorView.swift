import SwiftUI
import SwiftData
import MapKit
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
    @State private var scheduleEnabled = false
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]  // 預設週一到週五
    @State private var startHour = 8
    @State private var endHour = 19

    var body: some View {
        NavigationStack {
            Form {
                TextField("地點名稱", text: $name)
                TextField("地址或地標", text: $address)
                Button("使用 Apple Maps 搜尋") {
                    Task { await search() }
                }
                if let found {
                    Text("找到：\(found.name ?? address)").foregroundStyle(.green)
                } else if searchFailed {
                    Text("找不到這個地點，會改用預設座標（台北市中心）")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Stepper("提醒半徑：\(radius) 公尺", value: $radius, in: 300...3000, step: 100)
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
                        .tint(weekdays.contains(day) ? .indigo : .gray)
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
        } catch {
            AppLog.data.error("地點搜尋失敗：\(error.localizedDescription)")
            found = nil
            searchFailed = true
        }
    }

    private func save() {
        let coordinate = found?.location.coordinate ?? .init(latitude: 25.035, longitude: 121.54)
        let circle = LocalLifeCircle(
            name: name.isEmpty ? "生活圈" : name,
            encryptedAddress: found?.name ?? address,
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
        context.insert(circle)
        context.saveReporting()
        dismiss()
    }
}
