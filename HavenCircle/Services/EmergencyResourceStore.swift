import Foundation
import CoreLocation
import os

/// 緊急資源載入與查詢。
/// 注意：目前為「示例資料」（知名地標與醫院的概略座標），
/// 上線前應改接內政部與地方政府開放資料，UI 上已標示此限制。
@MainActor
enum EmergencyResourceStore {
    static let all: [EmergencyResource] = load()

    static var shelters: [EmergencyResource] { all.filter { $0.kind == ResourceKind.shelter } }
    static var hospitals: [EmergencyResource] { all.filter { $0.kind == ResourceKind.hospital } }

    /// 離指定位置最近的某類資源
    static func nearest(kind: String, latitude: Double, longitude: Double) -> (resource: EmergencyResource, distanceMeters: Int)? {
        let point = CLLocation(latitude: latitude, longitude: longitude)
        let candidates = all
            .filter { $0.kind == kind }
            .map { resource in
                (resource, point.distance(from: CLLocation(latitude: resource.latitude, longitude: resource.longitude)))
            }
        guard let best = candidates.min(by: { $0.1 < $1.1 }) else { return nil }
        return (best.0, Int(best.1))
    }

    private static func load() -> [EmergencyResource] {
        guard let url = Bundle.main.url(forResource: "EmergencyResources", withExtension: "json") else {
            AppLog.data.error("找不到 EmergencyResources.json，緊急資源功能停用")
            return []
        }
        do {
            return try JSONDecoder().decode([EmergencyResource].self, from: Data(contentsOf: url))
        } catch {
            AppLog.data.error("緊急資源資料解析失敗：\(error.localizedDescription)")
            return []
        }
    }
}
