//
//  HavenCircleApp.swift
//  HavenCircle
//

import SwiftUI
import SwiftData
import UserNotifications
import CloudKit
import os

@main
struct HavenCircleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let modelContainer: ModelContainer
    @State private var familySync = FamilySyncService()
    // 外觀模式：使用者可在設定頁強制淺色/深色（預設跟隨系統）
    @AppStorage(SettingsKeys.appearanceMode) private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage(SettingsKeys.profileDisplayName) private var profileDisplayName = ""
    @AppStorage(SettingsKeys.liveLocationSharingEnabled) private var liveLocationSharingEnabled = false
    @AppStorage(SettingsKeys.liveCircleRadiusMeters) private var liveCircleRadiusMeters = 1_000

    init() {
        modelContainer = Self.makeContainer()
        // 無聲推播喚醒的回呼（AppDelegate）需要容器跑資料管線，橋接過去
        AppRuntime.container = modelContainer
        AppRuntime.familySync = familySync
        // 導航標題套圓體，appearance 要在第一個視圖建立前設定才會生效
        HCAppearance.apply()
        // 前景也要顯示通知橫幅（演練模式必要）
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        // 警報通知的「回報我平安／尚未脫離危險」快速按鈕（要在任何通知送出前登記）
        NotificationScheduler.registerCategories()
        // 背景任務處理器必須在啟動完成前登記（Apple 規定），所以放 init 不放 .task
        BackgroundRefresh.register(container: modelContainer)
    }

    /// 建立本機資料庫。取代舊版 try!：schema 變動導致遷移失敗時，
    /// 先刪除舊資料庫重建（原型階段可接受），再不行才退回記憶體模式，
    /// 每一步都記錄原因，不讓 App 無聲閃退。
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([LocalSafetyEvent.self, LocalFamilyMember.self, LocalLifeCircle.self, RegionAlert.self])
        // 明確關閉 SwiftData 的 CloudKit 鏡像：本機模型只存這台裝置，
        // 家庭同步走獨立的 CKShare（FamilySyncService）。
        // 若不指定，SwiftData 偵測到 CloudKit entitlement 會嘗試鏡像，
        // 但本機模型用了 @Attribute(.unique)（CloudKit 不支援）而建立失敗。
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            AppLog.data.error("ModelContainer 建立失敗，嘗試重建本機資料庫：\(error.localizedDescription)")
            // 必須連同 -wal / -shm side-car 檔一起刪，否則殘留的日誌檔會讓重建仍讀到舊 schema
            let storeURL = config.url
            for suffix in ["", "-wal", "-shm"] {
                let url = suffix.isEmpty ? storeURL
                    : storeURL.deletingLastPathComponent()
                        .appendingPathComponent(storeURL.lastPathComponent + suffix)
                try? FileManager.default.removeItem(at: url)
            }
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                AppLog.data.fault("重建仍失敗，退回記憶體模式（資料不會保存）：\(error.localizedDescription)")
                do {
                    return try ModelContainer(
                        for: schema,
                        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
                    )
                } catch {
                    fatalError("無法建立任何資料庫：\(error)")
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // nil（跟隨系統）時不強制，交還系統深淺設定
                .preferredColorScheme(AppearanceMode(rawValue: appearanceMode)?.colorScheme)
                .environment(familySync)
                .task {
                    // 遠端設定放最前面（5 秒逾時）：後面的資料管線要吃它的功能開關
                    await RemoteConfig.refresh()
                    Self.markCurrentUser(
                        context: modelContainer.mainContext,
                        displayName: profileDisplayName
                    )
                    #if DEBUG
                    // 六災難情境測試：--seed-six-disasters／--clear-six-disasters
                    await SixDisasterScenario.runIfRequested(context: modelContainer.mainContext)
                    #endif
                    // 註冊 APNs：權杖與通知權限互相獨立，先拿權杖存著（AppDelegate 回呼），
                    // AppDelegate 取得權杖後會上傳到中繼站；伺服器偵測新官方警報後用 APNs 喚醒。
                    UIApplication.shared.registerForRemoteNotifications()
                    // 啟動即跑一次資料管線（mock 來源；階段 4 換成真實來源）
                    await EventPipeline.refresh(context: modelContainer.mainContext)
                    // 匿名統計：記一次啟動並把累積佇列送出（斷網自動留到下次）
                    Analytics.track("app_open")
                    await Analytics.flush()
                    await familySync.refreshAccountStatus()
                    LocationService.shared.syncLiveLocationSharing(
                        isEnabled: liveLocationSharingEnabled
                    )
                    if liveLocationSharingEnabled {
                        LocationService.shared.requestAlwaysPermission()
                        if let location = await LocationService.shared.currentLocation() {
                            await familySync.publishLiveLocation(
                                location,
                                displayName: profileDisplayName,
                                radiusMeters: liveCircleRadiusMeters,
                                context: modelContainer.mainContext
                            )
                        }
                    } else if UserDefaults.standard.string(
                        forKey: SettingsKeys.liveLocationDeviceID
                    ) != nil {
                        await familySync.stopLiveLocationSharing(
                            context: modelContainer.mainContext
                        )
                    }
                    await familySync.fetchLiveLocations(context: modelContainer.mainContext)
                    while !Task.isCancelled {
                        do {
                            try await Task.sleep(for: .seconds(30))
                        } catch {
                            return
                        }
                        await familySync.fetchLiveLocations(context: modelContainer.mainContext)
                    }
                }
                // 家人接受 CKShare 邀請後，由 scene delegate 經 NotificationCenter 轉交處理
                .onReceive(NotificationCenter.default.publisher(for: .didAcceptFamilyShare)) { note in
                    guard let metadata = note.object as? CKShare.Metadata else { return }
                    Task { await familySync.accept(metadata) }
                }
        }
        .modelContainer(modelContainer)
        // App 進背景時排一次背景刷新（BGTaskScheduler 的請求要在背景前送出才有效）
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                BackgroundRefresh.schedule()
            } else if phase == .active {
                Task {
                    await familySync.fetchLiveLocations(context: modelContainer.mainContext)
                }
                // 回前景時同步 FCM 行政區主題訂閱（生活圈可能已新增/編輯/刪除）
                FCMTopicSync.sync(container: modelContainer)
            }
        }
    }

    private static func markCurrentUser(context: ModelContext, displayName: String) {
        let members = (try? context.fetch(FetchDescriptor<LocalFamilyMember>())) ?? []
        guard !members.contains(where: \.isCurrentUser) else { return }
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let owner = members.first(where: {
            $0.relationship == "擁有者" || (!trimmedName.isEmpty && $0.name == trimmedName)
        }) {
            owner.isCurrentUser = true
            context.saveReporting()
        }
    }
}
