import SwiftUI

/// 地圖上每個「守護對象」（家人／地點）的專屬顏色。
///
/// 背景：舊版地圖只依「圈的類型」上色——所有人的即時圈都是同一種綠、所有固定地點
/// 都是同一種藍，多個家人同時顯示時完全分不清哪個圈是誰的。2026-07-24 使用者拍板
/// 「不同的圈子給不同的顏色」，改成依「人」而非「類型」上色。
///
/// 設計：
/// - 色盤第一格保留給「本人」，沿用既有的 HCColor.safe 綠色語意（使用者已經習慣
///   這個顏色代表自己），本人的圈（不論即時或固定）一律顯示這個綠色。
/// - 其餘成員依穩定鍵（優先用 LocalFamilyMember.memberKey，沒有 member 時退回
///   LocalLifeCircle.circleKey；兩者都是 SwiftData `@Attribute(.unique)` 的持久字串 id）
///   算 hash 取色，同一個人／圈每次開 App 顏色都一樣；不同人碰撞機率低（7 色可選、
///   hash mod 7），碰撞可接受（規格明訂）。
/// - 刻意避開紅／橙／黃：RegionAlert 嚴重度用色是「危急＝紅、注意＝橙、留意＝黃」
///   （見 Theme.swift severityColor），圈的顏色若落在這三色，使用者會誤以為圈本身
///   代表警報等級——這是本色盤唯一的硬性排除規則。
/// - 「即時位置已過期」的灰色語意不變，過期判斷在呼叫端（SafetyMapView）用
///   `renderedColor = isActiveForAlerts ? color : .gray` 蓋掉這裡算出的顏色，不受本色盤影響。
enum CircleColorPalette {
    /// 索引 0 保留給本人；索引 1...6 依 hash 分給其他成員。
    /// 全部來自系統色（Color.xxx），避免自訂色在深色模式下的對比度風險。
    static let colors: [Color] = [
        HCColor.safe, // 0：本人專屬，沿用既有綠色
        .blue,
        .purple,
        .teal,
        .pink,
        .indigo,
        .brown,
    ]

    /// 依「穩定鍵」與「是否本人」取色。
    /// - Parameters:
    ///   - key: 這個人／圈的持久 id 字串（member.memberKey 或退回 circle.circleKey）。
    ///   - isCurrentUser: 是不是本人；本人固定拿綠色，不受 hash 影響。
    static func color(for key: String, isCurrentUser: Bool) -> Color {
        guard !isCurrentUser else { return colors[0] }
        let candidateCount = colors.count - 1 // 扣掉本人專屬的索引 0
        guard candidateCount > 0 else { return colors[0] }
        let bucket = Int(stableHash(key) % UInt64(candidateCount))
        return colors[1 + bucket]
    }

    /// 穩定字串 hash（djb2 變體）。
    /// 不能用 Swift 內建的 `String.hashValue`／`Hasher`：兩者都會依處理程序隨機種子
    /// 打散（防雜湊洪水攻擊的設計），同一個字串在不同次 App 啟動會算出不同值——
    /// 那樣「同一個圈每次開 App 顏色一致」的規格就做不到，所以自己刻一個不受隨機種子
    /// 影響的版本，只吃 UTF8 bytes 累加，天生就是決定性的。
    private static func stableHash(_ s: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in s.utf8 {
            hash = (hash << 5) &+ hash &+ UInt64(byte) // hash*33 + byte，經典 djb2
        }
        return hash
    }
}
