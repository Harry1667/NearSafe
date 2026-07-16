import SwiftUI
import SwiftData
import UIKit

/// 設定頁：仿 Apple 系統設定的結構——頂部大帳號卡，下方彩色圖示分組列。
struct SettingsView: View {
    @Environment(FamilySyncService.self) private var sync
    @AppStorage(SettingsKeys.profileDisplayName) private var displayName = ""

    var body: some View {
        NavigationStack {
            List {
                // 頂部帳號卡：名稱＋iCloud 狀態，點入帳號詳情
                Section {
                    NavigationLink {
                        AppleAccountView()
                    } label: {
                        HStack(spacing: 14) {
                            avatar
                            VStack(alignment: .leading, spacing: 3) {
                                Text(displayName.isEmpty ? "設定你的名稱" : displayName)
                                    .font(.title3.weight(.semibold))
                                Text(accountStatusText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section {
                    settingsRow("個人資訊", subtitle: "顯示名稱與緊急聯絡備註",
                                icon: "person.text.rectangle.fill", color: .blue) {
                        PersonalProfileView()
                    }
                    settingsRow("提醒設定", subtitle: "本機提醒、可信度與每日摘要",
                                icon: "bell.badge.fill", color: .red) {
                        AlertSettingsView()
                    }
                }

                Section {
                    Label("安心圈不是緊急服務。遇立即危險請直接撥打 110 或 119。", systemImage: "phone.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .task { await sync.refreshAccountStatus() }
        }
    }

    /// 頭像：取顯示名稱第一個字，沒設名稱用預設盾牌
    private var avatar: some View {
        ZStack {
            Circle().fill(.indigo.gradient)
            if let initial = displayName.first {
                Text(String(initial))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }

    /// 仿系統設定的列：彩色圓角方塊圖示＋標題＋副標
    private func settingsRow(
        _ title: String,
        subtitle: String,
        icon: String,
        color: Color,
        @ViewBuilder destination: () -> some View
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .frame(width: 29, height: 29)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private var accountStatusText: String {
        switch sync.state {
        case .ready, .sharing:
            "iCloud 已可用"
        case .noAccount:
            "尚未登入 iCloud"
        case .error:
            "iCloud 暫時無法使用"
        case .unknown:
            "正在檢查 iCloud 狀態"
        }
    }
}

private struct AppleAccountView: View {
    @Environment(FamilySyncService.self) private var sync

    var body: some View {
        List {
            Section("iCloud 同步狀態") {
                LabeledContent("目前狀態", value: statusTitle)
                Text(statusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("重新檢查帳號狀態", systemImage: "arrow.clockwise") {
                    Task { await sync.refreshAccountStatus() }
                }
            }

            if sync.state == .noAccount {
                Section("登入流程") {
                    Label("開啟 iPhone 的「設定」", systemImage: "1.circle.fill")
                    Label("登入 Apple 帳號並啟用 iCloud", systemImage: "2.circle.fill")
                    Label("回到安心圈後重新檢查狀態", systemImage: "3.circle.fill")
                    // 系統沒有直達 iCloud 登入頁的公開深連結，開本 App 的設定頁是最近的合法入口
                    Button("開啟系統設定", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }

            Section("資料範圍") {
                Text("Apple 帳號只用於家人安否回報的 iCloud 同步。生活圈與事件資料仍保存在此裝置。")
                    .font(.footnote)
            }
        }
        .navigationTitle("Apple 帳號")
        .navigationBarTitleDisplayMode(.inline)
        .task { await sync.refreshAccountStatus() }
    }

    private var statusTitle: String {
        switch sync.state {
        case .ready: "已登入，可建立家庭圈"
        case .sharing: "已登入，家庭圈同步中"
        case .noAccount: "尚未登入 iCloud"
        case .error: "目前無法使用"
        case .unknown: "檢查中"
        }
    }

    private var statusDescription: String {
        switch sync.state {
        case .noAccount:
            "安心圈無法代替你登入 Apple 帳號；請在系統設定完成登入後再回來。"
        case .error(let message):
            message
        case .ready, .sharing:
            "你可以在「家人 > 安否回報」邀請家人加入。"
        case .unknown:
            "正在確認這台裝置的 iCloud 狀態。"
        }
    }
}

private struct PersonalProfileView: View {
    @AppStorage(SettingsKeys.profileDisplayName) private var displayName = ""
    @AppStorage(SettingsKeys.profileContactNote) private var contactNote = ""

    var body: some View {
        Form {
            Section("顯示資訊") {
                TextField("顯示名稱", text: $displayName)
                Text("顯示名稱會用在安否回報的署名。請只填寫家人辨識所需的資訊。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("緊急聯絡備註") {
                TextField("備註（選填）", text: $contactNote, axis: .vertical)
                    .lineLimit(3...6)
                Text("請勿填入不必要的個人資料；此原型只會儲存在此裝置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("個人資訊")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AlertSettingsView: View {
    @AppStorage(SettingsKeys.alertsEnabled) private var alertsEnabled = true
    @AppStorage(SettingsKeys.alertsPaused) private var paused = false
    @AppStorage(SettingsKeys.highConfidenceOnly) private var highConfidenceOnly = true
    @AppStorage(SettingsKeys.digestEnabled) private var digestEnabled = true
    @AppStorage(SettingsKeys.digestHour) private var digestHour = 20
    @Query private var events: [LocalSafetyEvent]
    @Query private var members: [LocalFamilyMember]

    var body: some View {
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
        .navigationBarTitleDisplayMode(.inline)
        // 摘要設定變更時立即重排通知
        .onChange(of: digestEnabled) { refreshDigest() }
        .onChange(of: digestHour) { refreshDigest() }
    }

    private func refreshDigest() {
        let summary = DigestComposer.summary(events: events, members: members)
        Task { await NotificationScheduler.refreshDailyDigest(summary: summary) }
    }
}

#Preview {
    SettingsView()
        .environment(FamilySyncService())
}
