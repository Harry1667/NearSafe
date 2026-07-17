import SwiftUI
import SwiftData
import UIKit
import AuthenticationServices
import UserNotifications

/// 設定頁：仿 Apple 系統設定的結構——頂部大帳號卡，下方彩色圖示分組列。
struct SettingsView: View {
    @Environment(FamilySyncService.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss // 設定現在是 sheet：重看導覽等動作要先把自己收起來
    @AppStorage(SettingsKeys.profileDisplayName) private var displayName = ""
    @AppStorage(SettingsKeys.appleAccountEmail) private var appleEmail = ""
    @AppStorage(SettingsKeys.apnsDeviceToken) private var apnsToken = ""
    @AppStorage(SettingsKeys.appearanceMode) private var appearanceMode = AppearanceMode.system.rawValue
    @State private var showTutorial = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var demoNoticeScheduled = false
    @State private var tokenCopied = false
    @State private var demoSeedFeedback: String?

    var body: some View {
        NavigationStack {
            List {
                // 頂部帳號卡：名稱＋email（Sign in with Apple 授權後）＋iCloud 狀態
                Section {
                    NavigationLink {
                        AppleAccountView()
                    } label: {
                        HStack(spacing: 14) {
                            avatar
                            VStack(alignment: .leading, spacing: 3) {
                                Text(displayName.isEmpty ? "設定你的名稱" : displayName)
                                    .font(.title3.weight(.semibold))
                                if !appleEmail.isEmpty {
                                    Text(appleEmail)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Text(accountStatusText)
                                    .font(.footnote)
                                    .foregroundStyle(appleEmail.isEmpty ? .secondary : .tertiary)
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
                    Picker(selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    } label: {
                        Label {
                            Text("外觀")
                        } icon: {
                            Image(systemName: "circle.lefthalf.filled")
                                .font(.callout)
                                .foregroundStyle(.white)
                                .frame(width: 29, height: 29)
                                .background(Color.indigo.gradient, in: RoundedRectangle(cornerRadius: HCRadius.badge))
                        }
                    }
                }

                Section {
                    settingsRow("法律與隱私", subtitle: "隱私權政策、用戶協議與使用條款",
                                icon: "hand.raised.square.fill", color: .purple) {
                        LegalCenterView()
                    }
                    settingsRow("資料來源", subtitle: "政府示警來源與資料新鮮度",
                                icon: "antenna.radiowaves.left.and.right", color: .teal) {
                        DataSourceView()
                    }
                    settingsRow("關於安心圈", subtitle: "版本、官網與隱私原則",
                                icon: "info.circle.fill", color: .gray) {
                        AboutView()
                    }
                    Button {
                        showTutorial = true
                    } label: {
                        Label {
                            Text("重看新手教學")
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "book.fill")
                                .font(.callout)
                                .foregroundStyle(.white)
                                .frame(width: 29, height: 29)
                                .background(HCColor.safe.gradient, in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                    Button {
                        // 種旗標＋關掉設定 sheet，AppTabs 觀察到旗標會從安心頁開始跨分頁導覽
                        UserDefaults.standard.set(true, forKey: SettingsKeys.homeTourPending)
                        dismiss()
                    } label: {
                        Label {
                            Text("重看功能導覽")
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .font(.callout)
                                .foregroundStyle(.white)
                                .frame(width: 29, height: 29)
                                .background(HCColor.brand.gradient, in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }

                // App Store 審查指南 5.1.1(v)：提供帳號/資料刪除
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label {
                            Text("刪除帳號與所有資料")
                        } icon: {
                            Image(systemName: "trash.fill")
                                .font(.callout)
                                .foregroundStyle(.white)
                                .frame(width: 29, height: 29)
                                .background(HCColor.danger.gradient, in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                    .disabled(isDeleting)
                } footer: {
                    Text("清除這支手機上的所有家人、警戒圈與事件資料，停止即時位置分享，並退出（擁有者則刪除）iCloud 家庭圈。此動作無法復原。")
                }

                #if DEBUG
                demoSection
                #endif

                Section {
                    Label("安心圈不是緊急服務。遇立即危險請直接撥打 110 或 119。", systemImage: "phone.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .task { await sync.refreshAccountStatus() }
            .fullScreenCover(isPresented: $showTutorial) {
                OnboardingView(isReplay: true)
            }
            .confirmationDialog("確定要刪除所有資料嗎？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("刪除所有資料", role: .destructive) {
                    Task { await deleteEverything() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("本機資料與 iCloud 家庭圈都會被清除，無法復原。")
            }
        }
    }

    // MARK: - 示範與開發

    /// 模擬警報通知與 APNs 權杖。誠實原則：模擬通知標題一律帶【示範】字樣，
    /// 不冒充真實災害警報；權杖只在本機顯示，供 Apple Push Console 推播測試。
    @ViewBuilder
    private var demoSection: some View {
        Section {
            Button {
                Task { await scheduleDemoNotification() }
            } label: {
                Label {
                    Text("模擬警報通知（示範用）")
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "bell.and.waves.left.and.right.fill")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .frame(width: 29, height: 29)
                        .background(HCColor.attention.gradient, in: RoundedRectangle(cornerRadius: HCRadius.badge))
                }
            }
            if demoNoticeScheduled {
                Label("已排程，5 秒後送達——現在鎖定螢幕可看到鎖屏通知。", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(HCColor.safe)
            }
            Button {
                DemoSeed.loadHistoricalEvents(context: context)
                demoSeedFeedback = "已載入 2 筆歷史官方事件（標題含【歷史示範】）"
            } label: {
                Label {
                    Text("載入歷史官方事件示範")
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .frame(width: 29, height: 29)
                        .background(HCColor.brand.gradient, in: RoundedRectangle(cornerRadius: HCRadius.badge))
                }
            }
            Button {
                DemoSeed.removeAll(context: context)
                demoSeedFeedback = "已移除所有歷史示範與演練事件"
            } label: {
                Label {
                    Text("重設 Demo 資料")
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .frame(width: 29, height: 29)
                        .background(Color.gray.gradient, in: RoundedRectangle(cornerRadius: HCRadius.badge))
                }
            }
            if let demoSeedFeedback {
                Label(demoSeedFeedback, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(HCColor.safe)
            }
            // APNs 權杖只在 Debug build 顯示：權杖本身不足以發送推播（還需開發者私鑰），
            // 但它能識別裝置，且對一般使用者只是一串困惑的亂碼——正式版不編譯這段
            #if DEBUG
            if !apnsToken.isEmpty {
                Button {
                    UIPasteboard.general.string = apnsToken
                    tokenCopied = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tokenCopied ? "APNs 裝置權杖（已複製）" : "APNs 裝置權杖（點一下複製）")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(apnsToken)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                }
            }
            #endif
        } header: {
            Text("示範與開發")
        } footer: {
            #if DEBUG
            Text("模擬通知為本機發送的示範內容（標題含【示範】字樣），非真實災害警報。歷史事件示範重播的是 NCDR 實際發布過的官方示警原文（標題含【歷史示範】，僅顯示效期經過調整）。權杖供 APNs 推播測試，操作步驟見專案 APNS_PUSH_TEST.md。")
            #else
            Text("模擬通知為本機發送的示範內容（標題含【示範】字樣），非真實災害警報。歷史事件示範重播的是 NCDR 實際發布過的官方示警原文（標題含【歷史示範】，僅顯示效期經過調整）。")
            #endif
        }
    }

    /// 延遲 5 秒發送：留時間鎖定螢幕，展示通知在鎖屏上的真實樣貌
    private func scheduleDemoNotification() async {
        guard await NotificationScheduler.requestPermission() else { return }
        let content = UNMutableNotificationContent()
        content.title = "【示範】地震速報：臺北市南港區"
        content.body = "官方確認事件落在「住家」提醒範圍內。此為示範內容，非真實警報。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        do {
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "demo-alert", content: content, trigger: trigger)
            )
            demoNoticeScheduled = true
            try? await Task.sleep(for: .seconds(6))
            demoNoticeScheduled = false
        } catch {
            AppLog.notificationsError("示範通知排程失敗：\(error.localizedDescription)")
        }
    }

    /// 刪除帳號與資料：撤銷推播權杖 → 雲端家庭圈 → 本機資料庫 → 偏好設定 → 通知。
    /// 完成後 ContentView 會因旗標與資料清空自動回到新手設定。
    private func deleteEverything() async {
        isDeleting = true
        defer { isDeleting = false }
        UserDefaults.standard.set(false, forKey: SettingsKeys.liveLocationSharingEnabled)
        LocationService.shared.syncLiveLocationSharing(isEnabled: false)
        // 先使用仍保留的權杖要求中繼站刪除，再清掉本機副本；即使離線失敗，
        // Apple 之後也會讓失效權杖被 APNs 回收，且刪除流程不應因此卡住。
        if !apnsToken.isEmpty {
            await APNsRegistrar.unregister(token: apnsToken)
        }
        if UserDefaults.standard.string(forKey: SettingsKeys.liveLocationDeviceID) != nil {
            await sync.stopLiveLocationSharing(context: context)
        }
        await sync.leaveFamily()
        // 逐筆刪除，不用 delete(model:)：批次刪除走 CoreData batch delete，
        // 會撞上 LocalLifeCircle.member 強制反向關聯的約束（實機已踩到）；
        // 逐筆刪除才會執行 cascade 與反向關聯清理。資料量小，效能無虞。
        do {
            for member in try context.fetch(FetchDescriptor<LocalFamilyMember>()) {
                context.delete(member) // cascade 會一併刪除生活圈
            }
            for circle in try context.fetch(FetchDescriptor<LocalLifeCircle>()) {
                context.delete(circle) // 保險：清掉沒掛在成員下的孤兒生活圈
            }
            for event in try context.fetch(FetchDescriptor<LocalSafetyEvent>()) {
                context.delete(event)
            }
            for alert in try context.fetch(FetchDescriptor<RegionAlert>()) {
                context.delete(alert)
            }
        } catch {
            AppLog.dataError("刪除本機資料失敗：\(error.localizedDescription)")
        }
        context.saveReporting()
        for key in [SettingsKeys.profileDisplayName, SettingsKeys.profileContactNote,
                    SettingsKeys.appleAccountEmail, SettingsKeys.onboardingCompleted,
                    SettingsKeys.lastDataRefresh, SettingsKeys.alertsEnabled,
                    SettingsKeys.alertsPaused, SettingsKeys.highConfidenceOnly,
                    SettingsKeys.digestEnabled, SettingsKeys.digestHour,
                    SettingsKeys.liveLocationSharingEnabled, SettingsKeys.liveCircleRadiusMeters,
                    SettingsKeys.liveLocationDeviceID, SettingsKeys.apnsDeviceToken,
                    SettingsKeys.legalAcceptanceVersion] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        EventVisibility.reset()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// 頭像：取顯示名稱第一個字，沒設名稱用預設盾牌
    private var avatar: some View {
        ZStack {
            Circle().fill(HCColor.brand.gradient)
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
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKeys.profileDisplayName) private var displayName = ""
    @AppStorage(SettingsKeys.appleAccountEmail) private var appleEmail = ""
    @State private var signInError: String?
    @State private var showLogoutConfirm = false
    @State private var showSignIn = false

    var body: some View {
        List {
            Section("Apple 帳號資訊") {
                if !appleEmail.isEmpty {
                    LabeledContent("Email", value: appleEmail)
                }
                // CloudKit 依隱私政策拿不到帳號 email；用 Sign in with Apple 授權一次帶入
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleSignIn(result)
                }
                .frame(height: 44)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                if let signInError {
                    Text(signInError)
                        .font(.caption)
                        .foregroundStyle(HCColor.danger)
                }
                Text("授權一次即可把名稱與 email 帶入設定頁。Apple 只在首次授權時提供這些資料，資料只存在這支手機。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                Text("Apple 帳號用於家人安否回報與即時圈位置的 iCloud 同步。固定圈與事件資料仍保存在此裝置。")
                    .font(.footnote)
            }

            Section {
                Button("登出", role: .destructive) {
                    showLogoutConfirm = true
                }
            } footer: {
                Text("登出會清除此裝置顯示的名稱與 email；固定圈與事件資料不受影響。請先在家人頁停止即時位置分享，iCloud 帳號本身由系統設定管理。")
            }
        }
        .navigationTitle("Apple 帳號")
        .navigationBarTitleDisplayMode(.inline)
        .task { await sync.refreshAccountStatus() }
        .confirmationDialog("確定要登出嗎？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("登出", role: .destructive) {
                Task {
                    UserDefaults.standard.set(false, forKey: SettingsKeys.liveLocationSharingEnabled)
                    LocationService.shared.syncLiveLocationSharing(isEnabled: false)
                    if UserDefaults.standard.string(forKey: SettingsKeys.liveLocationDeviceID) != nil {
                        await sync.stopLiveLocationSharing(context: context)
                    }
                    appleEmail = ""
                    displayName = ""
                    showSignIn = true
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只會清除本機顯示的帳號資訊，不會刪除任何資料。")
        }
        .fullScreenCover(isPresented: $showSignIn) {
            AppleSignInSheet()
        }
    }

    /// Sign in with Apple 只在「首次授權」提供姓名與 email，之後都是 nil——
    /// 所以只在拿到非空值時覆寫，重按不會把已存的資料洗掉。
    private func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            signInError = nil
            if let email = credential.email, !email.isEmpty {
                appleEmail = email
            }
            if let components = credential.fullName {
                let formatted = PersonNameComponentsFormatter().string(from: components)
                // 名稱只在使用者還沒自己設定時帶入，不覆蓋現有稱呼
                if !formatted.isEmpty && displayName.isEmpty {
                    displayName = formatted
                }
            }
            if appleEmail.isEmpty {
                signInError = "Apple 只在首次授權時提供 email。若要重新帶入：iPhone 設定 → Apple 帳號 → 登入與安全性 → 使用 Apple 登入的 App → 移除安心圈後再授權一次。"
            }
        case .failure(let error):
            // 使用者按取消也會走到這裡，不當成錯誤吵他
            if (error as? ASAuthorizationError)?.code != .canceled {
                signInError = "授權失敗：\(error.localizedDescription)"
            }
        }
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
    /// 「允許通知」按下後的結果（nil＝尚未按過）——按了沒反應等於壞掉，必須有可見回饋
    @State private var notificationGranted: Bool?

    var body: some View {
        Form {
            Section("提醒偏好") {
                Toggle("啟用本機提醒", isOn: $alertsEnabled)
                Toggle("公共安全事件僅高可信度提醒", isOn: $highConfidenceOnly)
                Toggle("暫停提醒", isOn: $paused)
                Button("允許通知") {
                    Task { notificationGranted = await NotificationScheduler.requestPermission() }
                }
                if let granted = notificationGranted {
                    Label(
                        granted ? "通知已開啟" : "通知未開啟——請到系統「設定 > 通知」中允許安心圈",
                        systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(granted ? HCColor.safe : HCColor.attention)
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
                Text("固定圈、家人與事件資料保存在此裝置；主動開啟的即時圈位置透過家庭 iCloud 同步。刪除 App 會刪除本機資料。")
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
