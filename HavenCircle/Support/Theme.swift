import SwiftUI
import UIKit

// MARK: - 設計 token 層
// 三方設計討論（2026-07-16）的共識產物：視覺方向「沉著守護」——
// 平時 90% 畫面用低彩度品牌色與中性色，只有真正的危險才用警示色；
// 「事件類型」用圖示表達、「可信度」用顏色表達，兩套視覺通道不互搶。
// 所有畫面的顏色、間距、圓角一律取自這裡，不再各自硬編。

extension Color {
    /// 深淺模式雙色（0xRRGGBB）——暗色不是亮色反相，而是獨立調過對比的色值
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// 語意色票：命名說「用途」不說「顏色」，之後換色不用改呼叫端
enum HCColor {
    /// 品牌主色（深群青）：CTA、選取狀態、生活圈。與 AccentColor.colorset 同值。
    static let brand = Color(light: 0x3657D6, dark: 0x89A0FF)
    /// 無需注意、回報平安、操作成功
    static let safe = Color(light: 0x18794E, dark: 0x5ED49A)
    /// 確認中、需留意、時段外
    static let attention = Color(light: 0xA96400, dark: 0xFFC56E)
    /// 明確危險、官方確認的警報
    static let danger = Color(light: 0xC83E3E, dark: 0xFF8A80)
    /// 區域警報最低層級（留意/提醒）的塗色——比 attention 再低一階
    static let notice = Color(light: 0xB89500, dark: 0xF5D76E)
    /// 統計參考圖層（治安等歷史資料）：刻意用冷色與紅橙色系的「即時警示」區隔
    static let reference = Color(light: 0x5856D6, dark: 0x7D7AFF)
    /// 醫療資源（急救責任醫院）標記
    static let medical = Color(light: 0x0E7C86, dark: 0x5BC8D2)
}

/// 間距刻度：4 的倍數，卡片內距一律 x4（16pt）
enum HCSpacing {
    static let x1: CGFloat = 4
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    static let x4: CGFloat = 16
    static let x6: CGFloat = 24
}

/// 圓角只留五檔——全 App 圓角不一致是「各畫面各自發明卡片」的主因
enum HCRadius {
    /// 列表行首的小型 icon 徽章
    static let badge: CGFloat = 8
    static let chip: CGFloat = 12
    static let control: CGFloat = 16
    static let card: CGFloat = 16
    static let sheet: CGFloat = 28
}

/// 全域外觀：導航標題改圓體（SF Rounded）——「沉著守護」的柔和感從標題字型貫穿全 App，
/// 一次設定所有 NavigationStack 生效，不用每頁各自改
enum HCAppearance {
    static func apply() {
        let navBar = UINavigationBar.appearance()
        navBar.largeTitleTextAttributes = [.font: roundedFont(style: .largeTitle, weight: .bold)]
        navBar.titleTextAttributes = [.font: roundedFont(style: .headline, weight: .semibold)]
    }

    /// 取系統動態字級的尺寸，再套 rounded design——直接指定 pointSize 會失去「放大字體」的無障礙支援
    private static func roundedFont(style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: style).pointSize
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = font.fontDescriptor.withDesign(.rounded) else { return font }
        return UIFont(descriptor: descriptor, size: size)
    }
}

extension View {
    /// 統一卡片：淡底＋連續圓角。不用 Material 疊 Material（會掉幀且對比不足）。
    func hcCard() -> some View {
        self
            .padding(HCSpacing.x3)
            .background(
                .secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: HCRadius.card, style: .continuous)
            )
    }
}

// MARK: - 區域警報嚴重度的視覺對應（單一事實來源：警報卡、地圖塗層、圖例共用）

extension RegionAlert {
    /// 嚴重度排序：危急(3)＞警戒(2)＞注意(1)＞留意/提醒(0)。NCDR severity 是封閉集合。
    static func severityRank(_ severity: String) -> Int {
        switch severity {
        case "危急": 3
        case "警戒": 2
        case "注意": 1
        default: 0
        }
    }

    /// 嚴重度顏色：危急/警戒＝danger、注意＝attention、其餘＝notice。
    /// 警報卡與地圖塗層必須同一套，使用者才能把「卡片的紅」和「地圖的紅」對起來。
    static func severityColor(rank: Int) -> Color {
        switch rank {
        case 2...: HCColor.danger
        case 1: HCColor.attention
        default: HCColor.notice
        }
    }

    var severityRank: Int { Self.severityRank(severity) }
    var severityColor: Color { Self.severityColor(rank: severityRank) }
}

// MARK: - 事件分類的視覺對應（圖示＝類型、顏色＝可信度，分工明確）

extension EventCategory {
    /// 類型圖示：只用歷代都有的 SF Symbols，避免舊系統開天窗
    static func icon(for type: String) -> String {
        switch type {
        case fire: "flame.fill"
        case traffic: "car.fill"
        case disaster: "cloud.bolt.rain.fill"
        case publicSafety: "exclamationmark.shield.fill"
        default: "exclamationmark.circle.fill"
        }
    }
}
