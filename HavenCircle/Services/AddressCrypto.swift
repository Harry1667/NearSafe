import Foundation
import CryptoKit
import Security

/// 生活圈住址的應用層加密：AES-GCM，金鑰存 iOS Keychain（裝置本機、不同步 iCloud）。
///
/// 設計原則（安全 App 的資料絕不可因加密錯誤而遺失）：
/// - 密文以 `enc:v1:` 前綴標記；解密時「沒有前綴」的字串（舊明文、即時圈固定文案）原樣回傳，
///   所以導入這層加密不會破壞任何既有資料，是相容的漸進遷移。
/// - 任何加解密失敗都不丟例外給 UI：加密失敗退化成存明文（可用但未加密），
///   解密失敗回空字串（不顯示亂碼），住址永不因此消失。
/// - 金鑰只在本機 Keychain；刪除 App 會連金鑰一起消失、舊密文即無法還原——
///   但住址本來就只存在本機／使用者自己的 iCloud，重裝後重新輸入即可，不涉及伺服器。
enum AddressCrypto {
    private static let prefix = "enc:v1:"
    private static let keychainAccount = "com.gomiigo.HavenCircle.addressKey"

    /// 加密明文住址，回傳帶前綴的密文字串；空字串原樣回傳。
    static func encrypt(_ plaintext: String) -> String {
        guard !plaintext.isEmpty else { return plaintext }
        guard let key = loadOrCreateKey(),
              let data = plaintext.data(using: .utf8),
              let sealed = try? AES.GCM.seal(data, using: key),
              let combined = sealed.combined else {
            return plaintext // 加密失敗就存明文，不阻斷存檔（退化但不遺失資料）
        }
        return prefix + combined.base64EncodedString()
    }

    /// 解密；沒有前綴的字串（舊明文、固定文案）原樣回傳，解不開回空字串。
    static func decrypt(_ stored: String) -> String {
        guard stored.hasPrefix(prefix) else { return stored }
        let b64 = String(stored.dropFirst(prefix.count))
        guard let key = loadOrCreateKey(),
              let combined = Data(base64Encoded: b64),
              let box = try? AES.GCM.SealedBox(combined: combined),
              let opened = try? AES.GCM.open(box, using: key),
              let text = String(data: opened, encoding: .utf8) else {
            return "" // 金鑰遺失等狀況：回空字串，不在畫面上顯示密文亂碼
        }
        return text
    }

    // MARK: - Keychain 金鑰管理

    private static func loadOrCreateKey() -> SymmetricKey? {
        if let existing = loadKey() { return existing }
        let key = SymmetricKey(size: .bits256)
        return storeKey(key) ? key : nil
    }

    private static func loadKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func storeKey(_ key: SymmetricKey) -> Bool {
        let data = key.withUnsafeBytes { Data($0) }
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            // 首次解鎖後即可用（含背景通知/小工具讀取住址），且不同步到 iCloud Keychain
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemDelete(attrs as CFDictionary) // 先刪同帳號舊項，避免 duplicate 失敗
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }
}
