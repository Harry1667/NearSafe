import Foundation

/// 8 位邀請碼服務：把 CKShare 連結換成好唸好輸入的短碼（Oracle 中繼站保管對照，72 小時效期）。
/// 隱私邊界：伺服器只看得到「分享連結」本身，看不到家庭成員、位置等任何內容資料——
/// 連結要配合 iCloud 帳號被邀請才有用。
enum JoinCodeService {
    private static let createURL = URL(string: "https://havencircle.looptw.com/join/api/create.php")!
    private static let redeemBase = "https://havencircle.looptw.com/join/api/redeem.php"

    enum JoinCodeError: LocalizedError {
        case badResponse
        case codeNotFound

        var errorDescription: String? {
            switch self {
            case .badResponse: "邀請碼服務暫時無法使用，請稍後再試"
            case .codeNotFound: "邀請碼不存在或已過期（效期 72 小時）"
            }
        }
    }

    /// 擁有者端：把分享連結換成 8 位邀請碼
    static func createCode(for shareURL: URL) async throws -> String {
        var request = URLRequest(url: createURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["url": shareURL.absoluteString])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw JoinCodeError.badResponse
        }
        struct CreateResponse: Decodable { let code: String }
        return try JSONDecoder().decode(CreateResponse.self, from: data).code
    }

    /// 加入端：8 位邀請碼換回分享連結
    static func redeem(code: String) async throws -> URL {
        let cleaned = code.trimmingCharacters(in: .whitespaces).uppercased()
        var components = URLComponents(string: redeemBase)!
        components.queryItems = [URLQueryItem(name: "code", value: cleaned)]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse else { throw JoinCodeError.badResponse }
        guard http.statusCode == 200 else { throw JoinCodeError.codeNotFound }

        struct RedeemResponse: Decodable { let url: String }
        let urlString = try JSONDecoder().decode(RedeemResponse.self, from: data).url
        guard let url = URL(string: urlString) else { throw JoinCodeError.badResponse }
        return url
    }
}
