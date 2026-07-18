import Foundation
import CoreLocation

/// 媒體報導事件來源：中繼站新聞爬蟲（中央社／自由／ETtoday 的現場事故，
/// 經 LLM 分類與地點抽取）。產品守則：媒體報導未經官方確認，
/// `isOfficial = false` → 只進「持續確認中」層，**只顯示、永不推播**（AlertPolicy 會擋）。
/// 每則事件都帶 sourceName＋sourceURL，詳情頁的「來源」區會如實列出。
struct NewsEventProvider: EventProvider {
    let sourceName = "媒體報導"

    private let endpoint = URL(string: "https://havencircle.looptw.com/crawler/api/latest.php?dataset=news")!

    /// 顯示壽命：發布後 12 小時。新聞的守護價值在即時性，過了半天還掛著只會誤導
    private static let ttlSeconds: TimeInterval = 12 * 3_600

    func fetchReports() async throws -> [RawEventReport] {
        let (data, response) = try await URLSession.shared.data(from: endpoint)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NCDRProviderError.badResponse
        }
        let envelope = try JSONDecoder().decode(NewsEnvelope.self, from: data)

        return envelope.data.events.compactMap { event in
            // 沒有縣市的事件不收：無法比對生活圈也無法上圖，硬顯示只會製造焦慮
            guard let county = event.county, !county.isEmpty else { return nil }
            guard let published = Self.parseDate(event.publishedAt) else { return nil }
            let ttl = published.addingTimeInterval(Self.ttlSeconds).timeIntervalSinceNow
            guard ttl > 0 else { return nil }
            guard let anchor = Self.coordinate(county: county, district: event.district) else { return nil }

            let location = [county, event.district ?? "", event.place ?? ""]
                .filter { !$0.isEmpty }
                .joined()
            return RawEventReport(
                // 優先用爬蟲 LLM 產的 10–12 字短摘要（地點＋事件重點）；
                // 舊資料或 LLM 未產出時退回原始新聞標題，永不因缺欄位丟事件
                title: event.summary?.isEmpty == false ? event.summary! : event.title,
                eventType: Self.eventType(for: event.category),
                approximateLocation: location,
                latitude: anchor.latitude,
                longitude: anchor.longitude,
                // 座標是行政區推定不是事發點：區級 3 公里、僅縣市級 15 公里，誠實標示不確定度
                precisionMeters: (event.district?.isEmpty == false) ? 3_000 : 15_000,
                sourceName: event.sourceLabel,
                sourceURL: event.sourceURL,
                isOfficial: false, // 媒體報導：永不推播
                occurredAt: published,
                ttlSeconds: ttl
            )
        }
    }

    /// 爬蟲分類 → App 的 MVP 四類
    static func eventType(for category: String?) -> String {
        switch category {
        case "火災": EventCategory.fire
        case "交通": EventCategory.traffic
        case "公共安全": EventCategory.publicSafety
        default: EventCategory.disaster // 天災、民生
        }
    }

    /// 事件錨點：優先用行政區邊界外框中心（縣市名對得上才用，避免同名區誤置），
    /// 抽不到區時退回縣市代表點
    static func coordinate(county: String, district: String?) -> CLLocationCoordinate2D? {
        if let district, !district.isEmpty {
            let candidates = DistrictBoundaries.shared.districts(named: district)
            let match = candidates.first { normalize($0.county) == normalize(county) }
            if let ring = match?.rings.first, !ring.isEmpty {
                let lats = ring.map(\.latitude)
                let lons = ring.map(\.longitude)
                return CLLocationCoordinate2D(
                    latitude: (lats.min()! + lats.max()!) / 2,
                    longitude: (lons.min()! + lons.max()!) / 2
                )
            }
        }
        return Self.countyCenters[normalize(county)]
    }

    static func normalize(_ name: String) -> String {
        name.replacingOccurrences(of: "臺", with: "台")
    }

    /// 縣市代表點（政府所在地概略座標）：只在抽不到行政區時使用，
    /// precisionMeters 會標 15 公里讓不確定度可見
    static let countyCenters: [String: CLLocationCoordinate2D] = [
        "台北市": .init(latitude: 25.0375, longitude: 121.5637),
        "新北市": .init(latitude: 25.0124, longitude: 121.4625),
        "桃園市": .init(latitude: 24.9937, longitude: 121.3010),
        "台中市": .init(latitude: 24.1477, longitude: 120.6736),
        "台南市": .init(latitude: 22.9999, longitude: 120.2270),
        "高雄市": .init(latitude: 22.6273, longitude: 120.3014),
        "基隆市": .init(latitude: 25.1276, longitude: 121.7392),
        "新竹市": .init(latitude: 24.8138, longitude: 120.9675),
        "新竹縣": .init(latitude: 24.8387, longitude: 121.0177),
        "苗栗縣": .init(latitude: 24.5602, longitude: 120.8214),
        "彰化縣": .init(latitude: 24.0518, longitude: 120.5161),
        "南投縣": .init(latitude: 23.9609, longitude: 120.9719),
        "雲林縣": .init(latitude: 23.7092, longitude: 120.4313),
        "嘉義市": .init(latitude: 23.4801, longitude: 120.4491),
        "嘉義縣": .init(latitude: 23.4518, longitude: 120.2555),
        "屏東縣": .init(latitude: 22.5519, longitude: 120.5487),
        "宜蘭縣": .init(latitude: 24.7021, longitude: 121.7378),
        "花蓮縣": .init(latitude: 23.9872, longitude: 121.6016),
        "台東縣": .init(latitude: 22.7583, longitude: 121.1444),
        "澎湖縣": .init(latitude: 23.5712, longitude: 119.5793),
        "金門縣": .init(latitude: 24.4321, longitude: 118.3171),
        "連江縣": .init(latitude: 26.1505, longitude: 119.9499),
    ]

    private static func parseDate(_ raw: String) -> Date? {
        // 爬蟲輸出帶時區的 ISO8601（偶有小數秒），兩種格式都試
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: raw) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw)
    }
}

// MARK: - 中繼站信封解碼

private struct NewsEnvelope: Decodable {
    let data: NewsPayload
}

private struct NewsPayload: Decodable {
    let events: [NewsEvent]
}

private struct NewsEvent: Decodable {
    let id: String
    let title: String
    let publishedAt: String
    let sourceURL: String
    let county: String?
    let district: String?
    let place: String?
    let category: String?
    /// LLM 產的短摘要（10–12 字）。必須是 Optional：舊資料沒有這欄，缺欄硬解會讓整批事件消失
    let summary: String?
    /// sourceName 可能是字串（單一來源）或陣列（跨來源合併），寬鬆解碼
    private let sourceName: SourceName?

    var sourceLabel: String {
        switch sourceName {
        case .single(let name): name
        case .multiple(let names): names.joined(separator: "、")
        case nil: "媒體報導"
        }
    }

    private enum SourceName: Decodable {
        case single(String)
        case multiple([String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let name = try? container.decode(String.self) {
                self = .single(name)
            } else {
                self = .multiple(try container.decode([String].self))
            }
        }
    }
}
