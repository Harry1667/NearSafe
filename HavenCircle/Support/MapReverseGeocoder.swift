import Foundation
import CoreLocation
import MapKit

/// MapKit 反向地理編碼結果的最小資料集。
/// 只保留產生行政區標籤需要的文字，避免在 App 狀態中傳遞或保存完整 MapItem。
struct ReverseGeocodedPlace {
    let name: String?
    let fullAddress: String?
    let shortAddress: String?
    let cityName: String?
    let cityWithContext: String?

    /// 行政區比對需要完整地址，但僅在記憶體中短暫使用，不會直接顯示或保存。
    var searchableText: String {
        [fullAddress, shortAddress, cityName, cityWithContext, name]
            .compactMap(\.self)
            .joined(separator: " ")
    }

    /// 對外只顯示縣市／行政區，不回傳門牌等精確位置。
    func approximateLabel(district: String) -> String? {
        let locality = cityName ?? cityWithContext
        let districtName = district == Districts.unspecified ? nil : district
        let parts = [locality, districtName].compactMap(\.self)
        var seen = Set<String>()
        let unique = parts.filter { part in
            !parts.contains(where: { $0 != part && $0.contains(part) }) && seen.insert(part).inserted
        }
        return unique.isEmpty ? nil : unique.joined()
    }
}

enum MapReverseGeocoder {
    static func lookup(_ location: CLLocation) async -> ReverseGeocodedPlace? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        request.preferredLocale = Locale(identifier: "zh-Hant-TW")
        guard let mapItem = try? await request.mapItems.first else { return nil }

        return ReverseGeocodedPlace(
            name: mapItem.name,
            fullAddress: mapItem.address?.fullAddress,
            shortAddress: mapItem.address?.shortAddress,
            cityName: mapItem.addressRepresentations?.cityName,
            cityWithContext: mapItem.addressRepresentations?.cityWithContext
        )
    }
}
