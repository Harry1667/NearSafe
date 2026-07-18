import Foundation

/// UserDefaults / @AppStorage 鍵值集中定義，避免字串打錯造成設定失效
enum SettingsKeys {
    static let alertsEnabled = "alertsEnabled"
    static let alertsPaused = "alertsPaused"
    static let highConfidenceOnly = "highConfidenceOnly"
    static let digestEnabled = "digestEnabled"
    static let digestHour = "digestHour"
    static let profileDisplayName = "profileDisplayName"
    static let liveLocationSharingEnabled = "liveLocationSharingEnabled"
    static let liveCircleRadiusMeters = "liveCircleRadiusMeters"
    static let liveLocationDeviceID = "liveLocationDeviceID"
    /// 接受 CKShare 後目前選用的家庭圈 zone；避免本機曾建立過空白家庭圈時又切回 private zone。
    static let activeFamilyZoneName = "activeFamilyZoneName"
    static let activeFamilyOwnerName = "activeFamilyOwnerName"
    static let profileContactNote = "profileContactNote"
    /// 最後一次資料更新時間（timeIntervalSince1970；0 表示尚未更新過）
    static let lastDataRefresh = "lastDataRefresh"
    /// 新手設定是否完成（獨立旗標，不再以「有沒有家人資料」推斷）
    static let onboardingCompleted = "onboardingCompleted"
    /// Sign in with Apple 授權後存下的帳號 email（僅本機顯示用；CloudKit 拿不到 email）
    static let appleAccountEmail = "appleAccountEmail"
    /// APNs 裝置權杖（十六進位字串）：設定頁「示範與開發」區顯示，供 Push Console 推播測試
    static let apnsDeviceToken = "apnsDeviceToken"
    /// 守護圈開場動效待播旗標：Onboarding 完成時種下，地圖首次出現時消耗（只演一次）
    static let guardianIntroPending = "guardianIntroPending"
    /// 外觀模式（AppearanceMode 的 rawValue）：跟隨系統／淺色／深色
    static let appearanceMode = "appearanceMode"
    /// 功能導覽待播旗標：Onboarding 完成時種下，首次進主畫面消耗；設定頁可重新種下
    static let homeTourPending = "homeTourPending"
    /// 首次設定時明確同意的法律文件版本；條款重大更新時改版號即可重新取得同意
    static let legalAcceptanceVersion = "legalAcceptanceVersion"
    /// 匿名使用統計開關（預設開）：關閉時 Analytics 不記錄也不送出
    static let analyticsEnabled = "analyticsEnabled"
}

/// 資料時效：所有會刷新事件資料的路徑都應呼叫這裡
enum DataFreshness {
    static func markRefreshedNow() {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: SettingsKeys.lastDataRefresh)
    }
}
