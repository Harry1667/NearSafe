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
    /// （CloudKit 舊架構遺留，Firebase 版改用 currentFamilyID；保留鍵名供舊資料清理）
    static let activeFamilyZoneName = "activeFamilyZoneName"
    static let activeFamilyOwnerName = "activeFamilyOwnerName"
    /// 目前所屬家庭圈的 Firestore familyId（取代上面兩個 CloudKit zone 鍵）。
    /// 本機快取；換裝置／重裝時由 Firebase uid 反查還原。
    static let currentFamilyID = "currentFamilyID"
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
    /// 通知頻率等級（AlertFrequency 的 rawValue）：小＝只推危險級／中＝標準（預設）／大＝連早期未確認線索也推
    static let alertFrequencyLevel = "alertFrequencyLevel"
}

/// 通知頻率（依事件嚴重度分級）。使用者在 Onboarding 與設定頁可調；
/// 實際過濾集中在 AlertPolicy.evaluate（單一決策點），避免變成「有 UI 卻沒接線」的死開關。
enum AlertFrequency: Int, CaseIterable, Identifiable {
    case low = 0        // 小：只推危險級（火災／地震／海嘯／颱風／公共安全）
    case standard = 1   // 中：危險級＋提醒級（高溫／降雨／停水…）＝預設
    case high = 2       // 大：再放寬到未經官方／多來源確認的早期線索

    var id: Int { rawValue }

    /// 目前設定值（鍵不存在時預設「中」，與舊版行為一致）
    static var current: AlertFrequency {
        let raw = UserDefaults.standard.object(forKey: SettingsKeys.alertFrequencyLevel) as? Int
        return raw.flatMap(AlertFrequency.init(rawValue:)) ?? .standard
    }

    /// 分段控制顯示的短標籤（小／中／大）
    var shortLabel: String {
        switch self {
        case .low: return "小"
        case .standard: return "中"
        case .high: return "大"
        }
    }

    /// 一句話說明目前選擇會收到哪些通知，直接顯示給使用者
    var explanation: String {
        switch self {
        case .low:
            return "只有火災、地震、海嘯、颱風、公共安全等危險事件才會通知；高溫、降雨、停水等一般提醒只在 App 內顯示。"
        case .standard:
            return "危險事件即時通知，高溫、降雨、停水等一般提醒也會通知。多數人適用。"
        case .high:
            return "除了上述，連尚未經官方或多來源確認的早期線索也會通知——更早知道，但可能偶有誤報。"
        }
    }
}

/// 資料時效：所有會刷新事件資料的路徑都應呼叫這裡
enum DataFreshness {
    static func markRefreshedNow() {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: SettingsKeys.lastDataRefresh)
    }
}
