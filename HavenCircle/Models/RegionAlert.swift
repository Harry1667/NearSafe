import Foundation
import SwiftData

/// 區域型警報（地震、颱風、豪雨特報）。
/// 台灣最重要的災害多半不是點狀事件——這類警報以行政區為單位發布，
/// 套不進「事件點＋半徑」模型，所以需要獨立的資料層。
@Model
final class RegionAlert {
    @Attribute(.unique) var alertKey: String
    var title: String
    /// 警報種類（颱風、地震、豪雨…）
    var kind: String
    var affectedDistricts: [String]
    var severity: String
    /// 應變建議（顯示在警報詳情與通知內文）
    var guidance: String
    var sourceName: String
    var sourceURL: String
    var issuedAt: Date
    var updatedAt: Date
    var expiresAt: Date
    var status: String = EventStatus.active.rawValue

    init(
        alertKey: String,
        title: String,
        kind: String,
        affectedDistricts: [String],
        severity: String,
        guidance: String,
        sourceName: String,
        sourceURL: String,
        issuedAt: Date = .now,
        expiresAt: Date
    ) {
        self.alertKey = alertKey
        self.title = title
        self.kind = kind
        self.affectedDistricts = affectedDistricts
        self.severity = severity
        self.guidance = guidance
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.issuedAt = issuedAt
        self.updatedAt = issuedAt
        self.expiresAt = expiresAt
    }
}

extension RegionAlert {
    /// 警報分組（顯示分區與地圖塗層取捨用；對應爬蟲端的四組分類）。
    /// 用 kind 靜態對應而不動資料模型：kind 清單由我們自己的爬蟲白名單決定，是封閉集合。
    static func group(forKind kind: String) -> String {
        switch kind {
        case "火災", "疏散避難", "防空", "輻射災害", "傳染病", "急門診通報", "縣市災情通報":
            "公共安全"
        case "停水", "電力中斷", "行動電話中斷", "市話通訊中斷", "停班停課", "枯旱預警":
            "民生"
        case "道路封閉", "鐵路事故", "高速公路路況", "聯絡道淹水封閉", "強風管制路段", "地下道積淹水", "捷運營運":
            "交通"
        default:
            "天災"
        }
    }

    var group: String { Self.group(forKind: kind) }

    /// 依警報類型給圖示（審查發現：三處寫死雨雲，高溫/地震/火災全顯示下雨）。
    /// 只用歷代都有的 SF Symbols，避免舊系統圖示開天窗。
    var iconName: String {
        switch kind {
        case "颱風": "hurricane"
        case "地震", "地震速報": "waveform.path.ecg"
        case "海嘯", "河川高水位", "水庫放流", "分洪警報", "堰塞湖警戒",
             "水位警戒", "區排警戒", "水位警示", "淹水", "淹水感測": "water.waves"
        case "豪雨", "雷雨": "cloud.bolt.rain.fill"
        case "強風", "強風管制路段": "wind"
        case "高溫": "thermometer.sun.fill"
        case "低溫": "thermometer.snowflake"
        case "濃霧": "cloud.fog.fill"
        case "土石流": "mountain.2.fill"
        case "火山": "flame.circle.fill"
        case "火災": "flame.fill"
        case "疏散避難": "figure.run"
        case "防空": "shield.lefthalf.filled"
        case "輻射災害": "exclamationmark.triangle.fill"
        case "傳染病", "急門診通報": "cross.case.fill"
        case "停水", "枯旱預警": "drop.fill"
        case "電力中斷": "bolt.slash.fill"
        case "行動電話中斷", "市話通訊中斷": "antenna.radiowaves.left.and.right"
        case "停班停課": "briefcase.fill"
        case "鐵路事故", "捷運營運": "tram.fill"
        case "道路封閉", "高速公路路況", "聯絡道淹水封閉", "地下道積淹水": "car.fill"
        default: "exclamationmark.circle.fill"
        }
    }

    var isEnded: Bool {
        status == EventStatus.resolved.rawValue || expiresAt <= .now
    }

    var statusText: String {
        isEnded ? EventStatus.resolved.rawValue : EventStatus.active.rawValue
    }

    /// 受影響的生活圈（以行政區比對）
    func matchedCircles(
        members: [LocalFamilyMember]
    ) -> [(memberName: String, circleName: String, isCurrentUser: Bool, isPlace: Bool)] {
        members.flatMap { member in
            member.lifeCircles
                .filter { $0.isActiveForAlerts && affectedDistricts.contains($0.district) }
                .map { (member.name, $0.name, member.isCurrentUser, member.isPlace) }
        }
    }
}
