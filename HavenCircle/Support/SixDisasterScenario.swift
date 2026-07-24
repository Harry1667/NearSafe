#if DEBUG
import Foundation
import SwiftData
import os // Swift 6.2 MemberImportVisibility：用 os.Logger 插值的檔案必須自行 import

/// 六災難情境測試（僅 DEBUG）：一鍵建立「家人＋固定資產＋六種災難」的完整測試場景，
/// 驗證影響圈模型在不同災型／不同圈上的判定與推播。
///
/// 用法（模擬器）：
///   xcrun simctl launch <udid> <bundle-id> --seed-six-disasters   # 建立場景（冪等，就地更新）
///   xcrun simctl launch <udid> <bundle-id> --clear-six-disasters  # 清除場景
///
/// 場景設計（每個點狀災難都放在「該災型影響圈剛好搆得到」的距離，驗證判定式邊界）：
///   媽媽／公司圈（信義區）  ← 械鬥 2.0km（公共安全影響半徑 1500：1000+300+1500=2800 內）
///   阿嬤／阿嬤家圈（板橋區）← 車禍 1.2km（交通影響半徑 300：1000+300+300=1600 內）
///   倉庫（固定資產，新莊區）← 大煙霧 1.5km（天災影響半徑 1000：1000+500+1000=2500 內）
///   我／住家圈（文山區）    ← 火災 0.8km（火災影響半徑 1000：1000+500+1000=2500 內）
///   颱風／地震             ← 區域警報，涵蓋全部四個行政區
@MainActor
enum SixDisasterScenario {
    static let keyPrefix = "demo-sixdis-"

    static func runIfRequested(context: ModelContext) async {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--clear-six-disasters") {
            clear(context: context)
            return
        }
        guard args.contains("--seed-six-disasters") else { return }
        await seed(context: context)
    }

    /// 清除場景（設定頁按鈕與啟動參數共用）
    static func clear(context: ModelContext) {
        do {
            try context.transaction {
                removeAll(context: context)
            }
        } catch {
            AppLog.data.error("清除六災難測試場景失敗：\(error.localizedDescription)")
            return
        }
        AppLog.data.info("六災難測試場景已清除")
    }

    /// 建立場景（設定頁按鈕與啟動參數共用；冪等，重跑就地更新）
    static func seed(context: ModelContext) async {
        // MARK: 家人與固定資產（警戒圈半徑統一 1km、訂閱全部四災型）
        let storedMembers = (try? context.fetch(FetchDescriptor<LocalFamilyMember>())) ?? []
        func upsertMember(key: String, name: String, relationship: String, kind: String = "person") -> LocalFamilyMember {
            if let member = storedMembers.first(where: { $0.memberKey == key }) {
                member.name = name
                member.relationship = relationship
                member.kind = kind
                return member
            }
            let member = LocalFamilyMember(memberKey: key, name: name, relationship: relationship, kind: kind)
            context.insert(member)
            return member
        }

        let mom = upsertMember(key: keyPrefix + "mom", name: "媽媽", relationship: "母親")
        let grandma = upsertMember(key: keyPrefix + "grandma", name: "阿嬤", relationship: "祖母")
        let warehouse = upsertMember(
            key: keyPrefix + "warehouse",
            name: "倉庫",
            relationship: "重要資產",
            kind: "place"
        )

        let circles: [(LocalFamilyMember, String, String, Double, Double)] = [
            (mom, "公司", "信義區", 25.0330, 121.5654),
            (grandma, "阿嬤家", "板橋區", 25.0095, 121.4590),
            (warehouse, "倉庫", "新莊區", 25.0359, 121.4322),
        ]
        let existingCircles = (try? context.fetch(FetchDescriptor<LocalLifeCircle>())) ?? []
        for (member, name, district, lat, lon) in circles {
            let key = keyPrefix + name
            let circle: LocalLifeCircle
            if let stored = existingCircles.first(where: { $0.circleKey == key }) {
                circle = stored
                circle.name = name
                circle.encryptedAddress = district
                circle.latitude = lat
                circle.longitude = lon
                circle.radiusMeters = 1_000
                circle.alertTypes = EventCategory.all
                circle.member = member
            } else {
                circle = LocalLifeCircle(
                    circleKey: key,
                    name: name,
                    encryptedAddress: district,
                    latitude: lat,
                    longitude: lon,
                    radiusMeters: 1_000,
                    alertTypes: EventCategory.all,
                    member: member
                )
                context.insert(circle)
            }
            circle.district = district
            circle.kind = .fixed
        }
        // 既有的住家圈也補訂閱全部災型（預設只訂火災＋天災，收不到械鬥/車禍測試）
        for circle in existingCircles where !circle.circleKey.hasPrefix(keyPrefix) {
            circle.alertTypes = EventCategory.all
        }

        // MARK: 四個點狀災難（全部官方已確認 → 會推播；效期 2 小時）
        let expiry = Date.now.addingTimeInterval(2 * 3_600)
        let pointEvents: [LocalSafetyEvent] = [
            LocalSafetyEvent(
                eventKey: keyPrefix + "fire",
                title: "【測試】公寓頂樓火警",
                eventType: EventCategory.fire,
                occurredAt: .now,
                approximateLocation: "文山區住家北方約 800 公尺",
                latitude: 24.9970, longitude: 121.5698692, precisionMeters: 500,
                sourceName: "測試情境", sourceURL: "https://havencircle.looptw.com",
                trustStatus: TrustStatus.officialConfirmed, severity: "需要注意",
                deduplicationGroup: keyPrefix + "fire", expiresAt: expiry,
                detail: "文山區一棟五層公寓頂樓起火，濃煙自頂樓竄出，消防單位已派遣多輛消防車到場灌救，正疏散周邊住戶。附近居民請緊閉門窗、避免吸入濃煙，並讓出通道供救災車輛通行。"
            ),
            LocalSafetyEvent(
                eventKey: keyPrefix + "smoke",
                title: "【測試】工廠大火濃煙",
                eventType: EventCategory.disaster,
                occurredAt: .now,
                approximateLocation: "新莊區倉庫西方約 1.5 公里",
                latitude: 25.0359, longitude: 121.4174, precisionMeters: 500,
                sourceName: "測試情境", sourceURL: "https://havencircle.looptw.com",
                trustStatus: TrustStatus.officialConfirmed, severity: "需要注意",
                deduplicationGroup: keyPrefix + "smoke", expiresAt: expiry,
                detail: "新莊區一處工廠發生大火，燃燒產生的濃煙向東擴散，周邊空氣品質監測站測得數值明顯上升。下風處民眾請減少外出、關閉門窗與空調外循環，有呼吸道疾病者應特別留意。"
            ),
            LocalSafetyEvent(
                eventKey: keyPrefix + "brawl",
                title: "【測試】街頭持械鬥毆",
                eventType: EventCategory.publicSafety,
                occurredAt: .now,
                approximateLocation: "信義區公司北方約 2 公里",
                latitude: 25.0510, longitude: 121.5654, precisionMeters: 300,
                sourceName: "測試情境", sourceURL: "https://havencircle.looptw.com",
                trustStatus: TrustStatus.officialConfirmed, severity: "需要注意",
                deduplicationGroup: keyPrefix + "brawl", expiresAt: expiry,
                detail: "信義區街頭發生多人持械鬥毆，警方已到場控制現場並帶回相關人員，事發路段一度交通壅塞。民眾請避免圍觀、遠離衝突區域，若目擊後續狀況可撥打 110 報案。"
            ),
            LocalSafetyEvent(
                eventKey: keyPrefix + "crash",
                title: "【測試】聯結車撞機車",
                eventType: EventCategory.traffic,
                occurredAt: .now,
                approximateLocation: "板橋區阿嬤家北方約 1.2 公里",
                latitude: 25.0203, longitude: 121.4590, precisionMeters: 300,
                sourceName: "測試情境", sourceURL: "https://havencircle.looptw.com",
                trustStatus: TrustStatus.officialConfirmed, severity: "需要注意",
                deduplicationGroup: keyPrefix + "crash", expiresAt: expiry,
                detail: "板橋區一處路口發生聯結車與機車碰撞事故，警方封閉部分車道進行排除與現場處理，該路段回堵。用路人請改道行駛、減速慢行，並留意現場交通指揮。"
            ),
        ]
        let existingEvents = (try? context.fetch(FetchDescriptor<LocalSafetyEvent>())) ?? []
        var storedPointEvents: [LocalSafetyEvent] = []
        for template in pointEvents {
            if let event = existingEvents.first(where: { $0.eventKey == template.eventKey }) {
                event.title = template.title
                event.eventType = template.eventType
                event.occurredAt = template.occurredAt
                event.updatedAt = .now
                event.approximateLocation = template.approximateLocation
                event.latitude = template.latitude
                event.longitude = template.longitude
                event.precisionMeters = template.precisionMeters
                event.sourceName = template.sourceName
                event.sourceURL = template.sourceURL
                event.trustStatus = template.trustStatus
                event.severity = template.severity
                event.detail = template.detail
                event.deduplicationGroup = template.deduplicationGroup
                event.expiresAt = template.expiresAt
                event.status = EventStatus.active.rawValue
                event.isDrill = template.isDrill
                event.hasNotified = false
                event.isArchived = false
                storedPointEvents.append(event)
            } else {
                context.insert(template)
                storedPointEvents.append(template)
            }
        }

        // MARK: 颱風＋地震（區域警報：官方影響範圍就是行政區清單）
        let allDistricts = ["文山區", "信義區", "板橋區", "新莊區"]
        let regionSeeds = [
            RegionAlert(
                alertKey: keyPrefix + "typhoon",
                title: "【測試】颱風海上陸上警報",
                kind: "颱風",
                affectedDistricts: allDistricts,
                severity: "警戒",
                guidance: "強風豪雨影響，請固定戶外物品、避免非必要外出，並留意停班停課資訊。",
                sourceName: "測試情境", sourceURL: "https://havencircle.looptw.com",
                expiresAt: expiry
            ),
            RegionAlert(
                alertKey: keyPrefix + "quake",
                title: "【測試】有感地震速報：北部地區最大震度 4 級",
                kind: "地震",
                affectedDistricts: allDistricts,
                severity: "注意",
                guidance: "請檢查住家周邊有無掉落物與瓦斯洩漏，留意後續餘震。",
                sourceName: "測試情境", sourceURL: "https://havencircle.looptw.com",
                expiresAt: expiry
            ),
        ]
        let existingAlerts = (try? context.fetch(FetchDescriptor<RegionAlert>())) ?? []
        for template in regionSeeds {
            if let alert = existingAlerts.first(where: { $0.alertKey == template.alertKey }) {
                alert.title = template.title
                alert.kind = template.kind
                alert.affectedDistricts = template.affectedDistricts
                alert.severity = template.severity
                alert.guidance = template.guidance
                alert.sourceName = template.sourceName
                alert.sourceURL = template.sourceURL
                alert.issuedAt = .now
                alert.updatedAt = .now
                alert.expiresAt = template.expiresAt
                alert.status = EventStatus.active.rawValue
            } else {
                context.insert(template)
            }
        }

        context.saveReporting()

        // 走真實推播決策：官方已確認＋圈內 → 每個點狀災難各發一則本機通知
        let members = (try? context.fetch(FetchDescriptor<LocalFamilyMember>())) ?? []
        for event in storedPointEvents {
            await NotificationScheduler.notifyIfNeeded(for: event, members: members)
        }
        context.saveReporting()
        // 桌面小工具同步：種子直接寫資料庫、不經管線，要自己刷新快照
        WidgetSnapshotWriter.refresh(context: context)
        AppLog.data.info("六災難測試場景已建立（4 點狀＋2 區域）")
    }

    /// 清除場景：種子事件、警報、家人與其警戒圈全部移除（既有資料不動）
    private static func removeAll(context: ModelContext) {
        let events = (try? context.fetch(FetchDescriptor<LocalSafetyEvent>())) ?? []
        for event in events where event.eventKey.hasPrefix(keyPrefix) { context.delete(event) }
        let alerts = (try? context.fetch(FetchDescriptor<RegionAlert>())) ?? []
        for alert in alerts where alert.alertKey.hasPrefix(keyPrefix) { context.delete(alert) }
        let circles = (try? context.fetch(FetchDescriptor<LocalLifeCircle>())) ?? []
        for circle in circles where circle.circleKey.hasPrefix(keyPrefix) { context.delete(circle) }
        let members = (try? context.fetch(FetchDescriptor<LocalFamilyMember>())) ?? []
        for member in members where member.memberKey.hasPrefix(keyPrefix) { context.delete(member) }
    }
}
#endif
