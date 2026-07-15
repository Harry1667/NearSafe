import Foundation
import SwiftData
import os

// MARK: - 來源協定

/// 原始事件回報：來源擷取後、進入去重與可信度評分前的統一格式
struct RawEventReport {
    let title: String
    let eventType: String
    let approximateLocation: String
    let latitude: Double
    let longitude: Double
    let precisionMeters: Int
    let sourceName: String
    let sourceURL: String
    let isOfficial: Bool
    let occurredAt: Date
    let ttlSeconds: TimeInterval
}

protocol EventProvider {
    var sourceName: String { get }
    func fetchReports() async throws -> [RawEventReport]
}

struct RawRegionAlert {
    let alertKey: String
    let title: String
    let kind: String
    let affectedDistricts: [String]
    let severity: String
    let guidance: String
    let sourceName: String
    let sourceURL: String
    let ttlSeconds: TimeInterval
}

protocol RegionAlertProvider {
    var sourceName: String { get }
    func fetchAlerts() async throws -> [RawRegionAlert]
}

// MARK: - 管線

/// 資料管線：來源擷取 → 去重 → 可信度評分 → 生活圈比對 → 通知 → 封存。
/// 階段 2 用確定性的 mock 來源把管線「形狀」建好；
/// 階段 4 接 NCDR/CWA/消防開放資料時只替換 provider，不動管線本身。
@MainActor
enum EventPipeline {
    static let providers: [any EventProvider] = [
        MockFireDepartmentProvider(),
        MockCommunityProvider(),
    ]
    static let regionProviders: [any RegionAlertProvider] = [
        MockWeatherBureauProvider(),
    ]

    static func refresh(context: ModelContext) async {
        let members = (try? context.fetch(FetchDescriptor<LocalFamilyMember>())) ?? []
        await ingestPointEvents(context: context, members: members)
        await ingestRegionAlerts(context: context, members: members)
        await sweep(context: context, members: members)
        context.saveReporting()
        DataFreshness.markRefreshedNow()

        let events = (try? context.fetch(FetchDescriptor<LocalSafetyEvent>())) ?? []
        await NotificationScheduler.refreshDailyDigest(
            summary: DigestComposer.summary(events: events, members: members)
        )
    }

    // MARK: 點狀事件

    private static func ingestPointEvents(context: ModelContext, members: [LocalFamilyMember]) async {
        var reports: [RawEventReport] = []
        for provider in providers {
            do {
                reports += try await provider.fetchReports()
            } catch {
                // 來源健康度：擷取失敗要留下紀錄，不能整條管線靜默失敗
                AppLog.pipeline.error("來源擷取失敗（\(provider.sourceName)）：\(error.localizedDescription)")
            }
        }

        let grouped = Dictionary(grouping: reports, by: signature(of:))
        for (sig, group) in grouped {
            let trust = trustLevel(for: group)
            let key = "evt-\(sig)"
            let descriptor = FetchDescriptor<LocalSafetyEvent>(
                predicate: #Predicate { $0.eventKey == key }
            )
            if let existing = ((try? context.fetch(descriptor)) ?? []).first {
                // 使用者標記結束的事件不再喚醒
                guard !existing.isEnded else { continue }
                existing.updatedAt = .now
                if trustRank(trust) > trustRank(existing.trustStatus) {
                    existing.trustStatus = trust
                }
                // 尚未推播過的事件再評估一次（涵蓋事後才新增生活圈、或可信度剛升級的情況）
                if !existing.hasNotified {
                    await NotificationScheduler.notifyIfNeeded(for: existing, members: members)
                }
            } else {
                // 建立新事件：來源欄位優先採用官方回報
                guard let primary = group.first(where: \.isOfficial) ?? group.first else { continue }
                let event = LocalSafetyEvent(
                    eventKey: key,
                    title: primary.title,
                    eventType: primary.eventType,
                    occurredAt: group.map(\.occurredAt).min() ?? .now,
                    approximateLocation: primary.approximateLocation,
                    latitude: primary.latitude,
                    longitude: primary.longitude,
                    precisionMeters: primary.precisionMeters,
                    sourceName: primary.sourceName,
                    sourceURL: primary.sourceURL,
                    trustStatus: trust,
                    severity: trust == TrustStatus.confirming ? "持續確認中" : "需要注意",
                    deduplicationGroup: sig,
                    expiresAt: .now.addingTimeInterval(group.map(\.ttlSeconds).max() ?? 86_400)
                )
                context.insert(event)
                await NotificationScheduler.notifyIfNeeded(for: event, members: members)
            }
        }
    }

    /// 去重簽名：類型＋約 500 公尺網格。相近位置、同類型的回報視為同一事件。
    private static func signature(of report: RawEventReport) -> String {
        let gridLat = (report.latitude / 0.005).rounded() * 0.005
        let gridLon = (report.longitude / 0.005).rounded() * 0.005
        return "\(report.eventType)@\(String(format: "%.3f", gridLat)),\(String(format: "%.3f", gridLon))"
    }

    /// 可信度評分：官方 > 多來源交叉驗證 > 單一未驗證線索
    private static func trustLevel(for group: [RawEventReport]) -> String {
        if group.contains(where: \.isOfficial) { return TrustStatus.officialConfirmed }
        if Set(group.map(\.sourceName)).count >= 2 { return TrustStatus.crossVerified }
        return TrustStatus.confirming
    }

    private static func trustRank(_ trust: String) -> Int {
        switch trust {
        case TrustStatus.officialConfirmed: 3
        case TrustStatus.crossVerified: 2
        default: 1
        }
    }

    // MARK: 區域警報

    private static func ingestRegionAlerts(context: ModelContext, members: [LocalFamilyMember]) async {
        var raws: [RawRegionAlert] = []
        for provider in regionProviders {
            do {
                raws += try await provider.fetchAlerts()
            } catch {
                AppLog.pipeline.error("區域警報擷取失敗（\(provider.sourceName)）：\(error.localizedDescription)")
            }
        }
        for raw in raws {
            let key = raw.alertKey
            let descriptor = FetchDescriptor<RegionAlert>(predicate: #Predicate { $0.alertKey == key })
            if let existing = ((try? context.fetch(descriptor)) ?? []).first {
                guard !existing.isEnded else { continue }
                existing.updatedAt = .now
            } else {
                let alert = RegionAlert(
                    alertKey: raw.alertKey,
                    title: raw.title,
                    kind: raw.kind,
                    affectedDistricts: raw.affectedDistricts,
                    severity: raw.severity,
                    guidance: raw.guidance,
                    sourceName: raw.sourceName,
                    sourceURL: raw.sourceURL,
                    expiresAt: .now.addingTimeInterval(raw.ttlSeconds)
                )
                context.insert(alert)
                let matched = alert.matchedCircles(members: members)
                if !matched.isEmpty {
                    let names = matched.map { "\($0.memberName)（\($0.circleName)）" }.joined(separator: "、")
                    await NotificationScheduler.scheduleAlert(
                        title: "\(raw.kind)警報：\(raw.title)",
                        body: "影響 \(names) 所在行政區。\(raw.guidance)",
                        id: raw.alertKey
                    )
                }
            }
        }
    }

    // MARK: 過期清理與封存

    private static func sweep(context: ModelContext, members: [LocalFamilyMember]) async {
        let events = (try? context.fetch(FetchDescriptor<LocalSafetyEvent>())) ?? []
        let sevenDaysAgo = Date.now.addingTimeInterval(-7 * 86_400)
        for event in events {
            // 過期的進行中事件自動解除；曾經推播過的要補發解除通知
            if !event.isResolved && event.isExpired {
                event.resolve()
                if event.hasNotified {
                    await NotificationScheduler.notifyResolved(for: event)
                }
            }
            // 結束超過 7 天 → 封存（保留供歷史回顧，不再出現在提醒中心）
            if event.isEnded && event.occurredAt < sevenDaysAgo && !event.isArchived {
                event.isArchived = true
            }
        }
        let alerts = (try? context.fetch(FetchDescriptor<RegionAlert>())) ?? []
        for alert in alerts where alert.status == EventStatus.active.rawValue && alert.expiresAt <= .now {
            alert.status = EventStatus.resolved.rawValue
        }
    }
}

// MARK: - Mock 來源（階段 4 換成 NCDR / CWA / 消防開放資料）

/// 模擬官方來源：消防與警廣
struct MockFireDepartmentProvider: EventProvider {
    let sourceName = "台北市政府消防局（模擬）"

    func fetchReports() async throws -> [RawEventReport] {
        [
            RawEventReport(
                title: "火警通報", eventType: EventCategory.fire,
                approximateLocation: "信義區松仁路附近",
                latitude: 25.0333, longitude: 121.5688, precisionMeters: 500,
                sourceName: sourceName, sourceURL: "https://www.119.gov.taipei/",
                isOfficial: true, occurredAt: .now.addingTimeInterval(-1_080), ttlSeconds: 86_400
            ),
            RawEventReport(
                title: "重大交通事故", eventType: EventCategory.traffic,
                approximateLocation: "南港區市民大道八段",
                latitude: 25.0510, longitude: 121.6060, precisionMeters: 400,
                sourceName: "警察廣播電台（模擬）", sourceURL: "https://www.pbs.gov.tw/",
                isOfficial: true, occurredAt: .now.addingTimeInterval(-3_600), ttlSeconds: 43_200
            ),
        ]
    }
}

/// 模擬社群來源：驗證「多來源交叉驗證」與「未驗證線索不推播」兩條路徑
struct MockCommunityProvider: EventProvider {
    let sourceName = "社群回報（模擬）"

    func fetchReports() async throws -> [RawEventReport] {
        [
            // 兩個獨立來源回報同一地點 → 管線應升級為「多來源交叉驗證」
            RawEventReport(
                title: "大樓冒煙", eventType: EventCategory.fire,
                approximateLocation: "大安區和平東路二段",
                latitude: 25.0264, longitude: 121.5435, precisionMeters: 800,
                sourceName: "市民回報平台 A（模擬）", sourceURL: "https://example.com/report-a",
                isOfficial: false, occurredAt: .now.addingTimeInterval(-1_800), ttlSeconds: 21_600
            ),
            RawEventReport(
                title: "疑似火警冒煙", eventType: EventCategory.fire,
                approximateLocation: "大安區和平東路二段",
                latitude: 25.0262, longitude: 121.5437, precisionMeters: 800,
                sourceName: "地方社團 B（模擬）", sourceURL: "https://example.com/report-b",
                isOfficial: false, occurredAt: .now.addingTimeInterval(-1_500), ttlSeconds: 21_600
            ),
            // 單一未驗證線索 → 持續確認中，僅 App 內顯示
            RawEventReport(
                title: "路口聚眾糾紛", eventType: EventCategory.publicSafety,
                approximateLocation: "萬華區西門町",
                latitude: 25.0421, longitude: 121.5079, precisionMeters: 600,
                sourceName: "網路論壇（模擬）", sourceURL: "https://example.com/forum",
                isOfficial: false, occurredAt: .now.addingTimeInterval(-900), ttlSeconds: 21_600
            ),
        ]
    }
}

/// 模擬中央氣象署：區域型天災警報
struct MockWeatherBureauProvider: RegionAlertProvider {
    let sourceName = "中央氣象署（模擬）"

    func fetchAlerts() async throws -> [RawRegionAlert] {
        [
            RawRegionAlert(
                alertKey: "cwa-heavyrain-demo",
                title: "大雨特報",
                kind: "天災",
                affectedDistricts: ["信義區", "南港區", "內湖區", "汐止區"],
                severity: "注意",
                guidance: "山區請留意坍方與落石，低窪地區慎防積水。",
                sourceName: sourceName,
                sourceURL: "https://www.cwa.gov.tw/",
                ttlSeconds: 21_600
            ),
        ]
    }
}
