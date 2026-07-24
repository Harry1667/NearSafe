import SwiftUI
import AuthenticationServices

/// Apple 登入頁（共用）：新手教學的登入步驟、登出後的登入介面都用這一頁。
/// 軟門檻設計：登入帶入名稱與 email 供家人辨識；跳過也能使用全部警報功能。
struct AppleSignInPage: View {
    /// 登入成功後呼叫（跳過由外層的工具列按鈕處理）
    var onSignedIn: () -> Void

    @AppStorage(SettingsKeys.profileDisplayName) private var displayName = ""
    @AppStorage(SettingsKeys.appleAccountEmail) private var appleEmail = ""
    @State private var signInError: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(HCColor.brand)
            VStack(spacing: 8) {
                Text("用 Apple 帳號登入")
                    .font(.title2.bold())
                Text("登入後會帶入你的名稱與 email，家人回報平安時更容易認得你。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            SignInWithAppleButton(.signIn) { request in
                // nonce + requestedScopes 由 AuthService 統一設定（Firebase 憑證交換需要 nonce）
                AuthService.shared.prepareAppleRequest(request)
            } onCompletion: { result in
                handleSignIn(result)
            }
            .frame(height: 50)
            .padding(.horizontal, 32)

            if let signInError {
                Text(signInError)
                    .font(.caption)
                    .foregroundStyle(HCColor.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Text("不登入也能使用完整的地圖與警報功能；家人安否回報需要登入 Apple 帳號，之後隨時可以再登入。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
    }

    /// Apple 只在首次授權提供姓名與 email；只在拿到非空值時覆寫。
    /// 拿到憑證後，再用 idToken 換 Firebase Auth 憑證登入，取得穩定的 uid（家庭圈身份主鍵）。
    private func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            signInError = nil
            // 先存本機顯示資訊（Apple 只在首次授權給 email／姓名，錯過不再有）
            if let email = credential.email, !email.isEmpty {
                appleEmail = email
            }
            if let components = credential.fullName {
                let formatted = PersonNameComponentsFormatter().string(from: components)
                if !formatted.isEmpty && displayName.isEmpty {
                    displayName = formatted
                }
            }
            // 用 idToken + nonce 換 Firebase 憑證登入；成功才算真的登入
            Task {
                do {
                    _ = try await AuthService.shared.completeAppleSignIn(credential)
                    onSignedIn()
                } catch {
                    // 原始錯誤只進 log；UI 一律顯示轉譯過的人話（見 AuthService.userFacingMessage）
                    signInError = AuthService.userFacingMessage(for: error, context: "登入失敗")
                }
            }
        case .failure(let error):
            // 取消／裝置未登入／網路問題都交給共用轉譯判斷；使用者主動取消時會回傳 nil，不吵他
            signInError = AuthService.userFacingMessage(for: error, context: "登入失敗")
        }
    }
}

/// 登出後呈現的獨立登入介面（fullScreenCover 用）
struct AppleSignInSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AppleSignInPage(onSignedIn: { dismiss() })
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("跳過") { dismiss() }
                    }
                }
        }
        // fullScreenCover 呈現：NavigationStack 根層同樣沒有明確鋪底，
        // 保險起見補上系統底色，避免深色模式下與底下畫面疊透明（同 RoleSelectView 的坑）。
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}
