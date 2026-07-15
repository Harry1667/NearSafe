import Foundation
import SwiftData

@Model
final class LocalLifeCircle {
    @Attribute(.unique) var circleKey: String
    var name: String
    /// 精確住址（上線前應加密保存；原型先以明文欄位佔位）
    var encryptedAddress: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Int
    /// 這個生活圈要接收的事件類型（改為陣列，取代舊版頓號分隔字串）
    var alertTypes: [String]
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

/// 事件類型清單（MVP 四類）
enum EventCategory {
    static let fire = "火災"
    static let traffic = "重大交通事故"
    static let disaster = "天災"
    static let publicSafety = "公共安全"
    static let all = [fire, traffic, disaster, publicSafety]
    /// 生活圈預設接收的類型（暴力／公共安全預設只在高可信度時提醒，由設定另行控制）
    static let defaultSelection = [fire, traffic, disaster]
}
