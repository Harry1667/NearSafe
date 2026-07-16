import Foundation

/// 治安參考統計（警政署季度犯罪資料，經 Oracle 中繼站）。
/// 定位：**歷史統計參考，不是警報**——季更、行政區級聚合，
/// 顯示上必須與即時災害警報嚴格區隔（不推播、預設關閉、避免紅色系）。
struct CrimeDistrict: Decodable {
    let county: String
    let town: String
    let total: Int
}

struct CrimeReference: Decodable {
    let period: String
    let districts: [CrimeDistrict]
}

enum CrimeReferenceService {
    private static let endpoint = URL(string: "https://havencircle.looptw.com/crawler/api/latest.php?dataset=crime")!

    static func fetch() async throws -> CrimeReference {
        let (data, response) = try await URLSession.shared.data(from: endpoint)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NCDRProviderError.badResponse
        }
        struct Envelope: Decodable { let data: CrimeReference }
        return try JSONDecoder().decode(Envelope.self, from: data).data
    }
}
