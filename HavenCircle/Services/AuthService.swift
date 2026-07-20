import Foundation
import FirebaseAuth
import AuthenticationServices
import CryptoKit
import os // Swift 6.2 MemberImportVisibility：直接使用 os.Logger 插值的檔案必須自行 import

/// Firebase 身份服務：用 Sign in with Apple 登入 Firebase Auth，取得穩定的 uid。
///
/// 設計動機：Firebase 家庭圈用 uid 當成員與位置文件的主鍵，取代舊 CloudKit 架構的
/// participantID（本機隨機 UUID）與 CKCurrentUserDefaultName。uid 是跨裝置、換手機都不變的
/// 真實身份，家庭圈的「誰是誰」才穩得住。
///
/// 隱私邊界：登入只換到一個匿名的 uid 字串；顯示名稱／email 仍存在本機 @AppStorage，
/// 由使用者決定要不要分享給家人（同意式）。
@MainActor
@Observable
final class AuthService {
    static let shared = AuthService()

    /// 目前登入的 Firebase uid（未登入為 nil）。家庭圈所有寫入都以此為身份。
    private(set) var uid: String?
    private(set) var isSignedIn: Bool = false

    /// 當前登入流程使用的原始 nonce。Apple 端用它的 SHA256 簽 idToken，
    /// Firebase 端用原始值驗證，兩者比對防止重放攻擊。
    private var currentNonce: String?

    private init() {
        // Firebase Auth 會持久化 session；啟動時直接還原既有登入狀態，免得每次都要重登。
        if let user = Auth.auth().currentUser {
            uid = user.uid
            isSignedIn = true
        }
    }

    // MARK: - Sign in with Apple 流程

    /// 在 SignInWithAppleButton 的 request 階段呼叫：產生一次性 nonce，
    /// 設定 requestedScopes 與 nonce 的 SHA256。
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// Apple 授權成功後呼叫：用 idToken + 原始 nonce 換 Firebase 憑證並登入，回傳 uid。
    @discardableResult
    func completeAppleSignIn(_ credential: ASAuthorizationAppleIDCredential) async throws -> String {
        guard let nonce = currentNonce else {
            throw AuthError.missingNonce
        }
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw AuthError.missingIdentityToken
        }
        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: credential.fullName
        )
        let result = try await Auth.auth().signIn(with: firebaseCredential)
        currentNonce = nil
        uid = result.user.uid
        isSignedIn = true
        AppLog.cloud.info("Firebase Auth（Sign in with Apple）登入成功")
        return result.user.uid
    }

    /// 登出：清除 Firebase session 與本地身份狀態。
    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            AppLog.cloud.error("Firebase 登出失敗：\(error.localizedDescription)")
        }
        uid = nil
        isSignedIn = false
        currentNonce = nil
    }

    // MARK: - nonce 工具（Firebase 官方 Sign in with Apple 建議實作）

    /// 產生密碼學等級的隨機 nonce 字串。
    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            guard status == errSecSuccess else { continue }
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

enum AuthError: LocalizedError {
    case missingNonce
    case missingIdentityToken

    var errorDescription: String? {
        switch self {
        case .missingNonce:
            return "登入流程遺失驗證碼，請重試一次。"
        case .missingIdentityToken:
            return "無法取得 Apple 身份權杖，請重試一次。"
        }
    }
}
