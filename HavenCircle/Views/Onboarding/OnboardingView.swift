import SwiftUI
import SwiftData
import MapKit
import os

/// 首次設定：建立本人與第一個生活圈
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var placeName = "住家"
    @State private var address = "台北市南港區"
    @State private var radius = 1000
    @State private var found: MKMapItem?
    @State private var searchFailed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 54))
                        .foregroundStyle(.indigo)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    Text("守護家人的日常生活圈。")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                    Text("資料只儲存在這支手機；不會追蹤任何人的即時位置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                Section("先建立你的生活圈") {
                    TextField("你的名稱", text: $name)
                    TextField("地點名稱", text: $placeName)
                    TextField("城市或地址", text: $address)
                    Button("使用 Apple Maps 搜尋位置") {
                        Task { await search() }
                    }
                    if let found {
                        Text("找到：\(found.name ?? address)").foregroundStyle(.green)
                    } else if searchFailed {
                        Text("找不到這個地點，會先用台北市南港區的預設位置，之後可在「家人」頁修改。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Stepper("提醒半徑：\(radius) 公尺", value: $radius, in: 300...3000, step: 100)
                }
                Section {
                    Button("完成設定") { finishSetup() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("歡迎使用安心圈")
        }
    }

    private func search() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address
        do {
            found = try await MKLocalSearch(request: request).start().mapItems.first
            searchFailed = (found == nil)
        } catch {
            AppLog.data.error("首次設定地點搜尋失敗：\(error.localizedDescription)")
            found = nil
            searchFailed = true
        }
    }

    private func finishSetup() {
        let me = LocalFamilyMember(name: name.isEmpty ? "我" : name, relationship: "擁有者")
        context.insert(me)
        // 有搜尋結果用實際座標；沒有就退回南港區預設位置
        let coordinate = found?.location.coordinate ?? .init(latitude: 25.0525, longitude: 121.6072)
        let circle = LocalLifeCircle(
            name: placeName.isEmpty ? "住家" : placeName,
            encryptedAddress: found?.name ?? address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusMeters: radius,
            alertTypes: EventCategory.defaultSelection,
            member: me
        )
        circle.district = Self.guessDistrict(from: "\(found?.name ?? "") \(address)")
        context.insert(circle)
        context.saveReporting()
        // 首次設定完成是請求通知權限的最佳時機（使用者剛表達了「想被提醒」的意圖）
        Task { _ = await NotificationScheduler.requestPermission() }
    }

    /// 從地址文字比對雙北行政區（供區域型警報使用）；找不到就標「未指定」
    static func guessDistrict(from text: String) -> String {
        Districts.all.dropFirst().first { text.contains($0) } ?? Districts.unspecified
    }
}

#Preview {
    OnboardingView()
        .modelContainer(PreviewSupport.container())
}
