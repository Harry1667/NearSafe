import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage(SettingsKeys.alertsEnabled) private var alertsEnabled = true
    @AppStorage(SettingsKeys.alertsPaused) private var paused = false
    @AppStorage(SettingsKeys.highConfidenceOnly) private var highConfidenceOnly = true
    @AppStorage(SettingsKeys.digestEnabled) private var digestEnabled = true
    @AppStorage(SettingsKeys.digestHour) private var digestHour = 20
    @Query private var events: [LocalSafetyEvent]
    @Query private var members: [LocalFamilyMember]

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
                Section("每日安全摘要") {
                    Toggle("每天固定時間發送摘要", isOn: $digestEnabled)
                    if digestEnabled {
                        Picker("發送時間", selection: $digestHour) {
                            ForEach(0..<24, id: \.self) { Text("\($0):00") }
                        }
                    }
                    Text("沒有事件的日子也會告訴你「今天平安」，並回報過濾了多少低風險資訊。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("資料與安全") {
                    Text("所有家人、生活圈與事件資料皆只保存在此裝置。刪除 App 會刪除本機資料。")
                    Text("安心圈不是 110、119 或緊急救難服務。遇立即危險請直接撥打 110 或 119。")
                }
            }
            .navigationTitle("提醒設定")
            // 摘要設定變更時立即重排通知
            .onChange(of: digestEnabled) { refreshDigest() }
            .onChange(of: digestHour) { refreshDigest() }
        }
    }

    private func refreshDigest() {
        let summary = DigestComposer.summary(events: events, members: members)
        Task { await NotificationScheduler.refreshDailyDigest(summary: summary) }
    }
}

#Preview {
    SettingsView()
}
