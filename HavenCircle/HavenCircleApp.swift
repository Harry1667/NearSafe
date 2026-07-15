//
//  HavenCircleApp.swift
//  HavenCircle
//

import SwiftUI
import SwiftData
import UserNotifications
import os

@main
struct HavenCircleApp: App {
    private let modelContainer: ModelContainer

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
        let config = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            AppLog.data.error("ModelContainer 建立失敗，嘗試重建本機資料庫：\(error.localizedDescription)")
            try? FileManager.default.removeItem(at: config.url)
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
                .task {
                    #if DEBUG
                    SmokeTest.runIfNeeded(context: modelContainer.mainContext)
                    #endif
                    // 啟動即跑一次資料管線（mock 來源；階段 4 換成真實來源）
                    await EventPipeline.refresh(context: modelContainer.mainContext)
                }
        }
        .modelContainer(modelContainer)
    }
}
