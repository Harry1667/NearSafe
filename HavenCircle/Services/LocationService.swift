import Foundation
import CoreLocation
import Observation
import os // Swift 6.2 MemberImportVisibility：用 os.Logger 插值的檔案必須自行 import

/// 定位服務有三種清楚分離的用途：
/// (1) 地圖藍點與一次性取位；(2) 本機即時圈更新；(3) 使用者主動開啟的家庭位置分享。
/// 家庭分享開啟時使用約 100 公尺精度／距離門檻，並允許背景更新；關閉後立即停止標準定位。
/// 顯著位置變更保留作為省電喚醒與本機即時圈的降級路徑。
@Observable
@MainActor
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// 一次性取位的等待者（同時間只允許一個，新請求會讓舊的以 nil 結束）
    private var oneShot: CheckedContinuation<CLLocation?, Never>?
    private var oneShotTimeout: Task<Void, Never>?
    /// 跟隨圈回呼：顯著位置變更到達時呼叫（由 AppDelegate 啟動時掛上）
    var onFollowLocationUpdate: ((CLLocation) -> Void)?
    /// 家庭即時位置分享回呼；只有使用者明確開啟分享時才呼叫。
    var onLiveLocationUpdate: ((CLLocation) -> Void)?
    private var hasFollowCircle = false
    private var liveSharingEnabled = false

    override private init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = true
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
        self.hasFollowCircle = hasFollowCircle
        reconcileMonitoring()
    }

    /// 即時圈分享開關。標準定位只在分享期間運作；分享狀態與停止入口由 App 內持續清楚顯示。
    func syncLiveLocationSharing(isEnabled: Bool) {
        liveSharingEnabled = isEnabled
        reconcileMonitoring()
    }

    /// 安否回報用：一次性取得目前位置；未授權或取不到一律回 nil，不擋回報流程
    func currentLocation() async -> CLLocation? {
        guard isAuthorized else { return nil }
        // 一分鐘內的快取位置直接用，省一次 GPS 熱機
        if let cached = manager.location, cached.timestamp > .now.addingTimeInterval(-60) {
            return cached
        }
        return await withCheckedContinuation { continuation in
            oneShotTimeout?.cancel()
            oneShot?.resume(returning: nil)
            oneShot = continuation
            manager.requestLocation()
            oneShotTimeout = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(12))
                } catch {
                    return
                }
                guard let self, let waiting = self.oneShot else { return }
                self.oneShot = nil
                waiting.resume(returning: nil)
            }
        }
    }

    // MARK: - CLLocationManagerDelegate（manager 建立在主執行緒，回呼也在主執行緒）

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        reconcileMonitoring()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        oneShotTimeout?.cancel()
        oneShotTimeout = nil
        // 一次性取位與跟隨圈共用這個回呼：兩邊都要餵到
        oneShot?.resume(returning: latest)
        oneShot = nil
        onFollowLocationUpdate?(latest)
        if liveSharingEnabled {
            onLiveLocationUpdate?(latest)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLog.data.error("一次性取位失敗：\(error.localizedDescription)")
        oneShotTimeout?.cancel()
        oneShotTimeout = nil
        oneShot?.resume(returning: nil)
        oneShot = nil
    }

    private func reconcileMonitoring() {
        guard isAuthorized else {
            manager.stopUpdatingLocation()
            manager.stopMonitoringSignificantLocationChanges()
            manager.allowsBackgroundLocationUpdates = false
            return
        }

        if liveSharingEnabled {
            manager.allowsBackgroundLocationUpdates = authorization == .authorizedAlways
            // Always 授權下可在背景更新而不常駐藍色狀態膠囊；When In Use 的顯示仍由系統決定。
            // 隱私透明度由家人頁的「即時圈分享中」文字、最後更新時間與停止按鈕承擔。
            manager.showsBackgroundLocationIndicator = false
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
        }

        if hasFollowCircle || liveSharingEnabled {
            manager.startMonitoringSignificantLocationChanges()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
        }
    }
}
