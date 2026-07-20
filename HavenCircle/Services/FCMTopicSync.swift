import Foundation
import SwiftData
import CoreLocation
import FirebaseMessaging
import os // AppLog.notifications 的 os.Logger 插值需自行 import（Swift 6.2 MemberImportVisibility）

/// FCM 行政區主題訂閱同步。
///
/// 由使用者的生活圈算出「該訂閱哪些行政區主題」，與上次訂閱做差集，訂新的、退掉不要的。
/// 主題名用 RegionTopic 計算（與伺服器 region_topic.php 完全一致）。
///
/// 隱私關鍵：訂閱關係（哪支手機關心哪些區）保存在 FCM（Google）端，
/// 本 App 的 Oracle 伺服器「完全不掌握」——伺服器只知道「發給訂閱某區的人」，不知道那是誰。
/// 這就是選 FCM 主題制的理由：連我們自己的伺服器被駭，也洩不出使用者關心哪些區。
enum FCMTopicSync {
    private static let storeKey = "fcmSubscribedTopics"

    /// 依目前所有生活圈同步訂閱。只有集合有變動時才呼叫 FCM，避免無謂請求。
    @MainActor
    static func sync(circles: [LocalLifeCircle]) {
        var desired: Set<String> = [RegionTopic.all] // 全台有感事件（地震/海嘯/颱風）人人都訂
        for circle in circles {
            let center = CLLocationCoordinate2D(latitude: circle.latitude, longitude: circle.longitude)
            guard CLLocationCoordinate2DIsValid(center),
                  !(center.latitude == 0 && center.longitude == 0) else { continue }
            let radius = Double(max(circle.radiusMeters, 100))
            // 圈半徑碰到的每一區都訂（含邊界鄰區，解漏接）
            for d in DistrictBoundaries.shared.districtsTouching(center: center, radiusMeters: radius) {
                desired.insert(RegionTopic.forRegion(county: d.county, town: d.town))
            }
        }

        let previous = Set(UserDefaults.standard.stringArray(forKey: storeKey) ?? [])
        guard desired != previous else { return } // 無變動不動作

        for topic in desired.subtracting(previous) { Messaging.messaging().subscribe(toTopic: topic) }
        for topic in previous.subtracting(desired) { Messaging.messaging().unsubscribe(fromTopic: topic) }
        UserDefaults.standard.set(Array(desired), forKey: storeKey)
        AppLog.notifications.info("FCM 主題同步：共訂閱 \(desired.count) 個主題")
    }

    /// 便利版：自己從容器抓生活圈再同步（供 App 回前景等時機呼叫）。
    @MainActor
    static func sync(container: ModelContainer) {
        let circles = (try? container.mainContext.fetch(FetchDescriptor<LocalLifeCircle>())) ?? []
        sync(circles: circles)
    }

    /// FCM 權杖刷新時呼叫：權杖一換，Google 端的舊主題訂閱全部失效，
    /// 但本機「已訂閱」快取還記著舊狀態，會讓 sync 誤判「無變動」而跳過重訂，
    /// 導致新權杖其實沒訂上任何主題、收不到地區推播。故先清快取，強制全部重新訂閱。
    @MainActor
    static func resync(container: ModelContainer) {
        UserDefaults.standard.removeObject(forKey: storeKey)
        sync(container: container)
    }
}
