import SwiftData
import CoreLocation

/// 新手第一次開 App 的資料地基：確保有一個「本人」成員與一個預設警戒圈。
///
/// 為什麼要在這裡就建：地圖上的「你的警戒圈」需要一個真實的圈才畫得出來、才能拖曳調整、才能被教學卡介紹。
/// 身分（爸爸／媽媽…）稍後才選，所以本人先叫「我」，選完身分再改名（見 AppTabs.applyRole）。
///
/// 預設就是「跟著人」（2026-07 使用者拍板）：圈是 isFollowMe 跟隨圈，不是打字建一個固定地址——
/// 這才是使用者要的「我的即時圈」。之後可在家人頁用「警報跟著我」開關關掉（圈留著變固定圈，
/// 見 FollowCircleToggleSection），但一開始就該是跟著人的狀態，不必自己先去開一次。
enum FirstRunSetup {
    /// 拒絕定位、或還取不到位置時的預設圈心：台北車站。
    static let taipeiStation = CLLocationCoordinate2D(latitude: 25.0478, longitude: 121.5170)
    /// 預設警戒半徑（公尺）＝1 公里。
    static let defaultRadiusMeters = 1_000

    /// 若尚無「本人」成員，就建立本人＋一個預設 1 公里跟隨圈（isFollowMe=true，圈心先放
    /// 台北車站，之後背景取得實際位置再校正；之後移動 500 公尺以上由 FollowCircleService 接手）。
    /// 已存在本人則不重複建立。
    @MainActor
    static func ensureDefaultCircle(context: ModelContext) {
        let members = (try? context.fetch(FetchDescriptor<LocalFamilyMember>())) ?? []
        guard !members.contains(where: \.isCurrentUser) else { return }

        let me = LocalFamilyMember(name: "我", relationship: "擁有者")
        me.isCurrentUser = true
        context.insert(me)

        let circle = LocalLifeCircle(
            name: FollowCircleToggleSection.onName,
            encryptedAddress: "位置由這支手機分享",
            latitude: taipeiStation.latitude,
            longitude: taipeiStation.longitude,
            radiusMeters: defaultRadiusMeters,
            alertTypes: EventCategory.defaultSelection,
            member: me
        )
        circle.isFollowMe = true
        circle.kind = .live
        context.insert(circle)
        context.saveReporting()
        // 跟隨圈監聽開關跟著圈的存在與否走（同 FollowCircleToggleSection／舊 OnboardingView 實作）
        LocationService.shared.syncFollowMonitoring(hasFollowCircle: true)

        // 背景校正：授權定位者，把圈心從台北車站移到實際位置（取不到就維持台北車站，
        // 之後移動 500 公尺以上會由 FollowCircleService 接手更新）。
        Task { @MainActor in
            guard let location = await LocationService.shared.currentLocation() else { return }
            circle.latitude = location.coordinate.latitude
            circle.longitude = location.coordinate.longitude
            circle.locationUpdatedAt = location.timestamp
            context.saveReporting()
        }
    }
}
