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
        context.insert(LocalLifeCircle(
            name: name.isEmpty ? "生活圈" : name,
            encryptedAddress: found?.name ?? address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusMeters: radius,
            alertTypes: EventCategory.defaultSelection,
            member: member
        ))
        context.saveReporting()
        dismiss()
    }
}
