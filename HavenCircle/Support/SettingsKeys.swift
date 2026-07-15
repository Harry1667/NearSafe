import Foundation

/// UserDefaults / @AppStorage 鍵值集中定義，避免字串打錯造成設定失效
enum SettingsKeys {
    static let alertsEnabled = "alertsEnabled"
    static let alertsPaused = "alertsPaused"
    static let highConfidenceOnly = "highConfidenceOnly"
}
