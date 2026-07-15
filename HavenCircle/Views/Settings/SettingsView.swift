import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKeys.alertsEnabled) private var alertsEnabled = true
    @AppStorage(SettingsKeys.alertsPaused) private var paused = false
    @AppStorage(SettingsKeys.highConfidenceOnly) private var highConfidenceOnly = true

    var body: some View {
        NavigationStack {
            Form {
                Section("提醒偏好") {
                    Toggle("啟用本機提醒", isOn: $alertsEnabled)
                    Toggle("暴力事件僅高可信度提醒", isOn: $highConfidenceOnly)
                    Toggle("暫停提醒", isOn: $paused)
                    Button("允許通知") {
                        Task { _ = await NotificationScheduler.requestPermission() }
                    }
                }
                Section("資料與安全") {
                    Text("所有家人、生活圈與事件資料皆只保存在此裝置。刪除 App 會刪除本機資料。")
                    Text("安心圈不是 110、119 或緊急救難服務。遇立即危險請直接撥打 110 或 119。")
                }
            }
            .navigationTitle("提醒設定")
        }
    }
}

#Preview {
    SettingsView()
}
