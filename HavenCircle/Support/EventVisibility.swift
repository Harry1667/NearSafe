import Foundation

/// 使用者在此裝置選擇略過的相似事件群組。
/// 這是顯示偏好，不會改變官方事件、來源資料或其他家人的畫面。
enum EventVisibility {
    private static let suppressedGroupsKey = "suppressedEventGroups"

    static func isSuppressed(_ event: LocalSafetyEvent) -> Bool {
        suppressedGroups.contains(event.deduplicationGroup)
    }

    static func suppressSimilar(to event: LocalSafetyEvent) {
        var groups = suppressedGroups
        groups.insert(event.deduplicationGroup)
        UserDefaults.standard.set(Array(groups), forKey: suppressedGroupsKey)
    }

    private static var suppressedGroups: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: suppressedGroupsKey) ?? [])
    }
}
