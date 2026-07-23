import Foundation

/// 使用者在事件詳情頁按過「這類警報以後不吵醒我」的事件類別（eventType／kind）集合。
/// 這只降低吵醒層級（interruptionLevel：時效性→一般），不影響通知是否送達——
/// 「發不發」是 AlertPolicy／EventPipeline 的職權，這裡只管「吵不吵醒」。
/// 寫法比照 EventVisibility（同樣是裝置端顯示/行為偏好），鍵名刻意不同以免互相覆蓋。
enum AlertWakePrefs {
    private static let mutedKindsKey = "mutedWakeEventKinds"

    static func isMuted(_ kind: String) -> Bool {
        mutedKinds.contains(kind)
    }

    static func mute(_ kind: String) {
        var kinds = mutedKinds
        kinds.insert(kind)
        UserDefaults.standard.set(Array(kinds), forKey: mutedKindsKey)
    }

    private static var mutedKinds: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: mutedKindsKey) ?? [])
    }

    /// 清空靜音紀錄（刪除帳號與資料流程用）
    static func reset() {
        UserDefaults.standard.removeObject(forKey: mutedKindsKey)
    }
}
