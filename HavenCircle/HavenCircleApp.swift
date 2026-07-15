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
    private let modelContainer: ModelContainer
    @State private var familySync = FamilySyncService()

    init() {
        modelContainer = Self.makeContainer()
        // 前景也要顯示通知橫幅（演練模式必要）
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
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
                .environment(familySync)
                .task {
                    #if DEBUG
                    SmokeTest.runIfNeeded(context: modelContainer.mainContext)
                    #endif
                    // 啟動即跑一次資料管線（mock 來源；階段 4 換成真實來源）
                    await EventPipeline.refresh(context: modelContainer.mainContext)
                    await familySync.refreshAccountStatus()
                }
                // 家人接受 CKShare 邀請後，由 scene delegate 經 NotificationCenter 轉交處理
                .onReceive(NotificationCenter.default.publisher(for: .didAcceptFamilyShare)) { note in
                    guard let metadata = note.object as? CKShare.Metadata else { return }
                    Task { await familySync.accept(metadata) }
                }
        }
        .modelContainer(modelContainer)
    }
}
