import Foundation

/// UserDefaults / @AppStorage 鍵值集中定義，避免字串打錯造成設定失效
enum SettingsKeys {
    static let alertsEnabled = "alertsEnabled"
    static let alertsPaused = "alertsPaused"
    static let highConfidenceOnly = "highConfidenceOnly"
    static let digestEnabled = "digestEnabled"
    static let digestHour = "digestHour"
    static let profileDisplayName = "profileDisplayName"
    static let profileContactNote = "profileContactNote"
    /// 最後一次資料更新時間（timeIntervalSince1970；0 表示尚未更新過）
    static let lastDataRefresh = "lastDataRefresh"
}

/// 資料時效：所有會刷新事件資料的路徑都應呼叫這裡
enum DataFreshness {
    static func markRefreshedNow() {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: SettingsKeys.lastDataRefresh)
    }
}
