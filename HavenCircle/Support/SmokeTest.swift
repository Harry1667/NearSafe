#if DEBUG
import Foundation
import SwiftData
import os

/// 指令列冒煙測試掛鉤（僅 DEBUG 編譯）：
/// - `--smoke-onboard`：略過首次設定，自動建立本人與生活圈
/// - `--smoke-drill`：啟動後自動跑一次演練決策並寫入 log
///   （只驗證決策邏輯，不實際發通知，避免權限對話框卡住自動化流程）
///
/// 用法：xcrun simctl launch <udid> com.gomiigo.CamMenuApp.HavenCircle --smoke-onboard --smoke-drill
@MainActor
enum SmokeTest {
    static func runIfNeeded(context: ModelContext) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--smoke-onboard") { onboard(context: context) }
        if args.contains("--smoke-drill") { drill(context: context) }
        if args.contains("--smoke-cloud") { Task { await cloud() } }
    }

    /// 驗證 CloudKit 降級：無 iCloud 帳號時，帳號狀態應為 noAccount，
    /// 且送出回報不應讓 App 崩潰（僅記錄錯誤並設為 error 狀態）。
    private static func cloud() async {
        AppLog.cloud.notice("SMOKE cloud：進入（Task 已啟動）")
        let sync = FamilySyncService()
        await sync.refreshAccountStatus()
        AppLog.cloud.notice("SMOKE cloud：帳號狀態 = \(String(describing: sync.state), privacy: .public)")
        await sync.postPing(senderName: "測試者", status: .safe, note: "冒煙測試")
        AppLog.cloud.notice("SMOKE cloud：postPing 後狀態 = \(String(describing: sync.state), privacy: .public)，未崩潰")
    }

    private static func onboard(context: ModelContext) {
        let members = (try? context.fetch(FetchDescriptor<LocalFamilyMember>())) ?? []
        guard members.isEmpty else {
            AppLog.pipeline.notice("SMOKE onboard：已有資料，略過")
            return
        }
        let me = LocalFamilyMember(name: "測試者", relationship: "擁有者")
        context.insert(me)
        // 座標選在信義區，會命中 mock 管線的示範火警事件（距離約 340 公尺）
        let circle = LocalLifeCircle(
            name: "住家",
            encryptedAddress: "台北市信義區",
            latitude: 25.0330,
            longitude: 121.5654,
            radiusMeters: 1000,
            alertTypes: EventCategory.defaultSelection,
            member: me
        )
        circle.district = "信義區"
        context.insert(circle)
        context.saveReporting()
        AppLog.pipeline.notice("SMOKE onboard：完成")
    }

    private static func drill(context: ModelContext) {
        let members = (try? context.fetch(FetchDescriptor<LocalFamilyMember>())) ?? []
        guard let circle = members.flatMap(\.lifeCircles).first else {
            AppLog.pipeline.error("SMOKE drill：失敗，沒有任何生活圈")
            return
        }
        let event = LocalSafetyEvent(
            eventKey: "smoke-drill-\(UUID().uuidString)",
            title: "模擬火警通報",
            eventType: circle.alertTypes.first ?? EventCategory.fire,
            approximateLocation: "\(circle.name)附近（冒煙測試）",
            latitude: circle.latitude + 0.003,
            longitude: circle.longitude,
            precisionMeters: 300,
            sourceName: "安心圈演練系統",
            sourceURL: "https://example.com/drill",
            trustStatus: TrustStatus.officialConfirmed,
            severity: "需要注意",
            deduplicationGroup: "smoke-drill",
            expiresAt: .now.addingTimeInterval(3_600),
            isDrill: true
        )
        context.insert(event)
        context.saveReporting()

        let decision = AlertPolicy.evaluate(event: event, members: members)
        AppLog.pipeline.notice("SMOKE drill：決策 push=\(decision.shouldPush, privacy: .public) reason=\(decision.reason, privacy: .public)")

        event.resolve()
        context.saveReporting()
        AppLog.pipeline.notice("SMOKE drill：解除 status=\(event.statusText, privacy: .public) isEnded=\(event.isEnded, privacy: .public)")
    }
}
#endif
