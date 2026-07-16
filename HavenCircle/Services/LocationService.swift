import Foundation
import CoreLocation
import Observation
import os // Swift 6.2 MemberImportVisibility：用 os.Logger 插值的檔案必須自行 import

/// 定位服務——產品守則：**位置永遠只留在這台手機，不上傳、不分享**。
/// 三個用途：(1) 地圖顯示自己的藍點（when-in-use 權限）、
/// (2) 安否回報時「自願」一次性取得位置附在回報裡、
/// (3) 使用者明確開啟的「跟隨圈」：用系統「顯著位置變更」（約移動 500 公尺才喚醒，
///     省電，需「永遠允許」權限）更新自己的警示圈圈心，只寫本機資料庫。
/// 沒有 startUpdatingLocation 的常駐精確追蹤；家人位置只來自他們主動回報的那一刻。
@Observable
@MainActor
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// 一次性取位的等待者（同時間只允許一個，新請求會讓舊的以 nil 結束）
    private var oneShot: CheckedContinuation<CLLocation?, Never>?
    /// 跟隨圈回呼：顯著位置變更到達時呼叫（由 AppDelegate 啟動時掛上）
    var onFollowLocationUpdate: ((CLLocation) -> Void)?

    override private init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.delegate = self
        authorization = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    /// 地圖藍點用：只負責要權限，位置由 MapKit 的 UserAnnotation 自行取得
    func requestPermissionIfNeeded() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// 跟隨圈用：要求「永遠允許」（顯著位置變更要在背景喚醒 App 必須是 Always）。
    /// 從未問過會先出 when-in-use 對話框，之後系統會再問升級；已是 when-in-use 則直接問升級
    func requestAlwaysPermission() {
        manager.requestAlwaysAuthorization()
    }

    /// 依「是否存在跟隨圈」開關顯著位置變更監聽。
    /// 呼叫時機：App 啟動（含背景被喚醒）、跟隨圈建立或刪除後。
    /// 顯著位置變更不需要 UIBackgroundModes location，系統會在必要時自行重啟 App
    func syncFollowMonitoring(hasFollowCircle: Bool) {
        if hasFollowCircle {
            manager.startMonitoringSignificantLocationChanges()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
        }
    }

    /// 安否回報用：一次性取得目前位置；未授權或取不到一律回 nil，不擋回報流程
    func currentLocation() async -> CLLocation? {
        guard isAuthorized else { return nil }
        // 一分鐘內的快取位置直接用，省一次 GPS 熱機
        if let cached = manager.location, cached.timestamp > .now.addingTimeInterval(-60) {
            return cached
        }
        return await withCheckedContinuation { continuation in
            oneShot?.resume(returning: nil)
            oneShot = continuation
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate（manager 建立在主執行緒，回呼也在主執行緒）

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        // 一次性取位與跟隨圈共用這個回呼：兩邊都要餵到
        oneShot?.resume(returning: latest)
        oneShot = nil
        onFollowLocationUpdate?(latest)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLog.data.error("一次性取位失敗：\(error.localizedDescription)")
        oneShot?.resume(returning: nil)
        oneShot = nil
    }
}
