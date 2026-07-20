import Foundation

/// 呼叫自家 Oracle AI 安全代理（clip.twloop.com / ProxyCLI 的前置）。
///
/// 安全設計：App **從不持有** ProxyCLI 的真正金鑰——那把機密只留在 Oracle 伺服器，
/// App 只帶一把低權限 `appKey` 打自家代理。就算 appKey 被拆出來，也只能打這支
/// 代理（伺服器端有限流、可隨時撤銷換 key），拿不到上游 ProxyCLI token，更打不了 AI 帳單。
/// 換金鑰＝改伺服器設定檔，App 不用更新。
/// 註：`appKey` 仍嵌在 App 內、理論上可被拆出，故它是「低價值、可撤銷」憑證；
/// 真正的裝置級防濫用（確認請求來自正版 App）日後可上 App Attest。
enum AIService {
    private static let endpoint = URL(string: "https://havencircle.looptw.com/ai/chat.php")!
    // 低權限存取金鑰（對應 Oracle _ai_config.php 的 APP_AI_KEY）。
    // 這不是機密金鑰——真正的 ProxyCLI token 在伺服器，永不下發到此。
    private static let appKey = "84bc635b7e5b02cb71ffc686a848d8e270554e0aeede9e25"

    struct AIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// 送一段 prompt 給 AI，取回文字結果。
    /// - Parameters:
    ///   - prompt: 提示詞（伺服器端上限 4000 字）
    ///   - effort: 可選運算強度（low/medium/high），不指定由閘道決定
    static func complete(prompt: String, effort: String? = nil) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        var body: [String: Any] = ["prompt": prompt]
        if let effort { body["effort"] = effort }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError(message: "AI 服務無回應")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 429 { throw AIError(message: "AI 請求太頻繁，請稍後再試") }
            throw AIError(message: "AI 服務暫時無法使用（\(http.statusCode)）")
        }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = obj?["content"] as? String, !content.isEmpty else {
            throw AIError(message: "AI 沒有回傳內容")
        }
        return content
    }
}
