import Foundation
import CoreLocation
import MapKit
import os

/// 緊急資源載入與查詢。
/// 資料來源（2026-07 建置，皆為政府開放資料，座標取自官方欄位、未自行 geocode）：
/// - 避難收容所：內政部消防署「避難收容處所點位檔」（data.gov.tw/dataset/73242）
/// - 急救責任醫院：衛福部「急救責任醫院分區名單」＋內政部國土測繪中心醫療設施座標
/// 資料清洗（2026-07-23 重做）：座標必須落在「所屬鄉鎮的行政區界 bbox＋5 公里容忍」內，
/// 界外者剔除（原始檔有 239 筆登打錯置，例如整批新屋區活動中心座標在馬祖外海——
/// 保底指路指去錯的點會直接毀掉信任，寧缺勿錯）。清洗腳本比對 TaiwanDistricts.json。
@MainActor
enum EmergencyResourceStore {
    static let all: [EmergencyResource] = load()

    static var shelters: [EmergencyResource] { all.filter { $0.kind == ResourceKind.shelter } }
    static var hospitals: [EmergencyResource] { all.filter { $0.kind == ResourceKind.hospital } }

    /// 指定鏡頭範圍內、離中心最近的資源。
    /// 全國近 6,000 筆不能全部丟給 MapKit（會拖垮繪製），由呼叫端限量顯示。
    static func resources(kind: String, in region: MKCoordinateRegion, limit: Int) -> [EmergencyResource] {
        let latHalf = region.span.latitudeDelta / 2
        let lonHalf = region.span.longitudeDelta / 2
        let center = region.center
        return all
            .filter {
                $0.kind == kind
                    && abs($0.latitude - center.latitude) <= latHalf
                    && abs($0.longitude - center.longitude) <= lonHalf
            }
            .sorted {
                // 用度數平方距離排序即可（範圍小，不需要真實測地距離）
                let d0 = pow($0.latitude - center.latitude, 2) + pow($0.longitude - center.longitude, 2)
                let d1 = pow($1.latitude - center.latitude, 2) + pow($1.longitude - center.longitude, 2)
                return d0 < d1
            }
            .prefix(limit)
            .map { $0 }
    }

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
