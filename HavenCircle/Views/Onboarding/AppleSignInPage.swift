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
                request.requestedScopes = [.fullName, .email]
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
            Text("不登入也能使用完整的地圖與警報功能；家人安否回報需要 iCloud，之後隨時可以再登入。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
    }

    /// Apple 只在首次授權提供姓名與 email；只在拿到非空值時覆寫
    private func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            signInError = nil
            if let email = credential.email, !email.isEmpty {
                appleEmail = email
            }
            if let components = credential.fullName {
                let formatted = PersonNameComponentsFormatter().string(from: components)
                if !formatted.isEmpty && displayName.isEmpty {
                    displayName = formatted
                }
            }
            onSignedIn()
        case .failure(let error):
            // 使用者按取消不當錯誤吵他
            if (error as? ASAuthorizationError)?.code != .canceled {
                signInError = "登入失敗：\(error.localizedDescription)。請確認這支 iPhone 已在系統設定登入 Apple 帳號。"
            }
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
    }
}
