import Foundation

/// 「你現在該怎麼做」——依事件類型給穩定、可預期的建議行動文字。
/// 刻意不解析 LLM 產出的 `detail` 描述：那段文字會隨來源與生成內容變動，
/// 建議行動必須每次看到同類型事件都一樣、可信賴，不能因為 AI 這次寫得比較模糊就漏掉關鍵動作。
enum EventActionAdvice {
    /// 對應事件詳情頁「建議行動」獨立框；已結束事件直接沿用既有文案，
    /// 讓「建議行動框」與其他地方（statusSection）共用同一句話、不各自維護一份。
    static func advice(for event: LocalSafetyEvent) -> String {
        guard !event.isEnded else { return "此事件已結束，無需進一步行動。" }
        switch event.eventType {
        case EventCategory.fire:
            return "遠離起火點與濃煙、往上風處移動；受困或目擊請撥 119。"
        case EventCategory.publicSafety:
            return "立即遠離現場、尋找掩蔽、勿圍觀；目擊或遇險請撥 110。"
        case EventCategory.traffic:
            return "避開事故路段、小心改道；如有人受傷請撥 119。"
        case EventCategory.disaster:
            return disasterAdvice(title: event.title)
        default:
            return "留意周遭狀況、遠離危險區域，緊急狀況請撥 110 或 119。"
        }
    }

    /// 「天災」是點狀事件管線裡最寬的分類（地震、淹水、颱風、空品、停水停電瓦斯等皆歸此類，
    /// 見 NewsEventProvider 的分類註解），eventType 本身不夠細，改看標題關鍵字再細分。
    private static func disasterAdvice(title: String) -> String {
        if title.contains("地震") {
            return "就地掩護、遠離窗戶與外牆，搖晃停止後再移動。"
        }
        if title.contains("淹水") || title.contains("積水") {
            return "遠離低窪與地下空間、勿涉水或開車進積水。"
        }
        if title.contains("停水") || title.contains("停電") || title.contains("斷電") || title.contains("瓦斯") {
            return "留意官方公告；聞到瓦斯味勿開關電器、開窗並撥 119。"
        }
        return "留意最新警報、遠離危險區域，必要時撥 119。"
    }
}
