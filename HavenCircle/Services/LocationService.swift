import Foundation
import CoreLocation
import Observation
import os // Swift 6.2 MemberImportVisibility：用 os.Logger 插值的檔案必須自行 import

/// 定位服務——產品鐵律：**不做背景追蹤**。
/// 只有兩個用途：(1) 地圖顯示自己的藍點（when-in-use 權限）、
/// (2) 安否回報時「自願」一次性取得位置附在回報裡。
/// 沒有 startUpdatingLocation 的常駐更新，家人位置只來自他們主動回報的那一刻。
@Observable
@MainActor
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// 一次性取位的等待者（同時間只允許一個，新請求會讓舊的以 nil 結束）
    private var oneShot: CheckedContinuation<CLLocation?, Never>?

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
        oneShot?.resume(returning: locations.last)
        oneShot = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLog.data.error("一次性取位失敗：\(error.localizedDescription)")
        oneShot?.resume(returning: nil)
        oneShot = nil
    }
}
