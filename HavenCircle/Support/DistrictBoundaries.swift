import Foundation
import CoreLocation

/// 台灣鄉鎮市區邊界（內嵌資源 TaiwanDistricts.json）。
/// 來源：內政部鄉鎮市區界線（政府資料開放授權），經 Douglas-Peucker 簡化到約 200 公尺容差
/// （20MB → 341KB）——塗色顯示用，不做精確定位判斷。
/// 用途：區域警報的「行政區塗層」——把受影響的行政區整片著色，取代誤導性的單點標記。
struct DistrictBoundaries {
    struct District {
        let county: String
        let town: String
        /// 每個 ring 是一圈外框座標（MultiPolygon 拆成多個 ring；洞已忽略，塗色用途可接受）
        let rings: [[CLLocationCoordinate2D]]
    }

    static let shared = DistrictBoundaries()

    /// 以區名索引（例「大雅區」→ 各縣市同名區的清單）。
    /// 已知限制：RegionAlert 只存區名不含縣市，同名區（如各縣市的「東區」）會一起亮，
    /// 寧可多塗不漏塗——這是安全 App 的正確取捨方向。
    private let byTown: [String: [District]]

    /// 全國鄉鎮市區名清單（排序去重），供生活圈行政區選單與警報比對使用
    var allTownNames: [String] { byTown.keys.sorted() }

    private init() {
        guard let url = Bundle.main.url(forResource: "TaiwanDistricts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let collection = try? JSONDecoder().decode(FeatureCollection.self, from: data) else {
            AppLog.dataError("TaiwanDistricts.json 載入失敗，區域警報塗層停用")
            byTown = [:]
            return
        }
        var index: [String: [District]] = [:]
        for feature in collection.features {
            let rings: [[CLLocationCoordinate2D]]
            switch feature.geometry.type {
            case "Polygon":
                guard let coords = feature.geometry.polygonCoordinates else { continue }
                rings = [Self.ring(coords.first ?? [])] // 只取外框，忽略洞
            case "MultiPolygon":
                guard let coords = feature.geometry.multiPolygonCoordinates else { continue }
                rings = coords.compactMap { poly in poly.first.map(Self.ring) }
            default:
                continue
            }
            let district = District(county: feature.properties.county,
                                    town: feature.properties.town,
                                    rings: rings.filter { $0.count >= 4 })
            index[feature.properties.town, default: []].append(district)
        }
        byTown = index
    }

    /// 依區名找邊界（可能對到多個縣市的同名區）
    func districts(named town: String) -> [District] {
        byTown[town] ?? []
    }

    private static func ring(_ coords: [[Double]]) -> [CLLocationCoordinate2D] {
        coords.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0]) // GeoJSON 是 [經度, 緯度]
        }
    }
}

// MARK: - GeoJSON 解碼（座標維度不同，手動分流）

private struct FeatureCollection: Decodable {
    let features: [Feature]
}

private struct Feature: Decodable {
    let properties: Properties
    let geometry: Geometry
}

private struct Properties: Decodable {
    let county: String
    let town: String
}

private struct Geometry: Decodable {
    let type: String
    let polygonCoordinates: [[[Double]]]?
    let multiPolygonCoordinates: [[[[Double]]]]?

    enum CodingKeys: String, CodingKey {
        case type, coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        switch type {
        case "Polygon":
            polygonCoordinates = try container.decode([[[Double]]].self, forKey: .coordinates)
            multiPolygonCoordinates = nil
        case "MultiPolygon":
            polygonCoordinates = nil
            multiPolygonCoordinates = try container.decode([[[[Double]]]].self, forKey: .coordinates)
        default:
            polygonCoordinates = nil
            multiPolygonCoordinates = nil
        }
    }
}
