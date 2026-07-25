import Foundation
import SwiftData

enum LifeCircleKind: String, CaseIterable {
    case live
    case fixed

    var title: String {
        switch self {
        case .live: "即時圈"
        case .fixed: "固定地點"
        }
    }

    var iconName: String {
        switch self {
        case .live: "location.fill"
        case .fixed: "mappin.and.ellipse"
        }
    }
}

@Model
final class LocalLifeCircle {
    @Attribute(.unique) var circleKey: String
    var name: String
    /// 精確住址，以 AES-GCM 加密後儲存（見 AddressCrypto）。
    /// 請勿直接讀寫此欄位；改用 `addressText`（解密讀取）與 `setAddress(_:)`（加密寫入）。
    /// 相容：無密文前綴的舊明文/即時圈固定文案會被原樣回傳。
    var encryptedAddress: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Int
    /// 這個生活圈要接收的事件類型（改為陣列，取代舊版頓號分隔字串）
    var alertTypes: [String]
    /// 時段感知：只在指定作息時段推播（例如公司圈只在上班時間）。
    /// 時段外的官方事件仍會顯示在 App 內，只是不推播——這是對抗通知疲勞的主要機制。
    var scheduleEnabled: Bool = false
    /// 適用星期（Calendar.weekday 慣例：1=週日 … 7=週六）
    var scheduleWeekdays: [Int] = [1, 2, 3, 4, 5, 6, 7]
    var scheduleStartHour: Int = 0
    var scheduleEndHour: Int = 24
    /// 所在行政區（供區域型警報比對；「未指定」表示不參與區域警報）
    var district: String = "未指定"
    /// 圈類型：fixed＝固定資產／地點，live＝由家人手機共享的移動警戒圈。
    /// 保留 isFollowMe 供舊資料遷移；本機擁有者的 live circle 會同時設為 true。
    var kindRawValue: String = "fixed"
    var isFollowMe: Bool = false
    /// 即時圈的位置時效與 CloudKit 來源。固定圈兩欄皆為 nil。
    var locationUpdatedAt: Date?
    var sharedLocationID: String?
    var member: LocalFamilyMember?

    init(
        circleKey: String = UUID().uuidString,
        name: String,
        encryptedAddress: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Int,
        alertTypes: [String],
        member: LocalFamilyMember? = nil
    ) {
        self.circleKey = circleKey
        self.name = name
        self.encryptedAddress = encryptedAddress
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.alertTypes = alertTypes
        self.member = member
    }
}

extension LocalLifeCircle {
    var kind: LifeCircleKind {
        get { isFollowMe || kindRawValue == LifeCircleKind.live.rawValue ? .live : .fixed }
        set { kindRawValue = newValue.rawValue }
    }

    /// 即時位置超過 15 分鐘未更新，就不能再用來觸發安全判斷。
    /// 圈仍保留在畫面上並明示過期，避免把舊座標冒充現在位置。
    ///
    /// 例外：isFollowMe 圈一律視為有效，不吃 15 分鐘規則。
    /// 上面的 `kind` getter只要 isFollowMe==true 就一定回報 `.live`（無論 kindRawValue
    /// 存了什麼），但「live」在這個 model 裡其實疊了兩種更新頻率完全不同的語意：
    /// (1) 家人持續分享位置給我看的圈——位置來自對方裝置頻繁回報，15 分鐘沒更新代表
    ///     對方可能已停止分享，過期判斷合理；(2) 本機「警報跟著我」跟隨圈——只在顯著
    ///     位置變更（約移動 500 公尺）時才更新，使用者原地不動幾小時是正常狀態，不是
    ///     圈失效。用同一條「15 分鐘」規則會把「沒有移動」誤判成「位置過期」，導致
    ///     警戒圈悄悄退出警報比對——這是假性安心的反面，比誤報更危險。
    var isActiveForAlerts: Bool {
        guard kind == .live, !isFollowMe else { return true }
        guard let locationUpdatedAt else { return false }
        return locationUpdatedAt > Date.now.addingTimeInterval(-15 * 60)
    }

    var locationFreshnessText: String {
        guard kind == .live else { return "固定位置" }
        guard let locationUpdatedAt else { return "尚未取得位置" }
        guard isActiveForAlerts else { return "位置已過期" }
        // 相對時間鎖定繁中：App 字串全是寫死的中文，系統格式器卻跟著裝置語言跑，
        // 英文系統會拼出「1 minute ago 更新」這種中英混雜句
        var style = Date.RelativeFormatStyle(presentation: .named)
        style.locale = Locale(identifier: "zh_TW")
        return "\(locationUpdatedAt.formatted(style))更新"
    }

    /// 事件發生時間是否落在這個生活圈的提醒時段內
    func isWithinSchedule(at date: Date = .now) -> Bool {
        guard scheduleEnabled else { return true }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        return scheduleWeekdays.contains(weekday)
            && hour >= scheduleStartHour
            && hour < scheduleEndHour
    }

    /// 顯示用的時段描述
    var scheduleText: String {
        guard scheduleEnabled else { return "全天提醒" }
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let days = scheduleWeekdays.sorted().compactMap { $0 >= 1 && $0 <= 7 ? names[$0 - 1] : nil }
        return "週\(days.joined(separator: "、")) \(scheduleStartHour):00–\(scheduleEndHour):00"
    }

    /// 住址明文存取：底層 `encryptedAddress` 存密文，這裡負責解密。
    /// 相容舊明文與即時圈固定文案（無密文前綴者原樣回傳），詳見 AddressCrypto。
    var addressText: String {
        AddressCrypto.decrypt(encryptedAddress)
    }

    /// 寫入使用者輸入的住址（加密後存入 `encryptedAddress`）。
    func setAddress(_ plaintext: String) {
        encryptedAddress = AddressCrypto.encrypt(plaintext)
    }
}

/// 事件類型清單（MVP 四類）
enum EventCategory {
    static let fire = "火災"
    static let traffic = "重大交通事故"
    static let disaster = "天災"
    static let publicSafety = "公共安全"
    static let all = [fire, traffic, disaster, publicSafety]
    /// 生活圈預設接收的類型。
    /// 公共安全（槍擊、械鬥、攻擊等治安事件）先前未列入預設，導致這類真實事件即使
    /// 有資料來源也永遠比對不到任何生活圈、等同對使用者隱形——這是覆蓋漏抓，
    /// 危害不亞於漏報天災，故補上。
    /// 「重大交通事故」目前沒有政府即時資料源，不列入預設——勾了卻永遠收不到是空承諾，
    /// 接上資料源後再加回。
    static let defaultSelection = [fire, disaster, publicSafety]
}
