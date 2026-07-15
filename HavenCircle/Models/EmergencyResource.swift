import Foundation

/// 緊急資源種類
enum ResourceKind {
    static let shelter = "避難收容所"
    static let hospital = "急救責任醫院"
}

/// 緊急資源（避難收容所、急救責任醫院）。
/// 從 bundle 內嵌 JSON 載入——斷網時也要能用，這類資料不能依賴網路。
struct EmergencyResource: Codable, Identifiable {
    let id: String
    let name: String
    let kind: String
    let district: String
    let address: String
    let latitude: Double
    let longitude: Double
}
