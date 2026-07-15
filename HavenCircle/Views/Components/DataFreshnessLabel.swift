import SwiftUI

/// 資料時效標示：明確告訴使用者「你看到的資料是幾分鐘前的」。
/// 這是離線降級（階段 4）的第一步——斷網時使用者至少知道資料有多舊。
struct DataFreshnessLabel: View {
    @AppStorage(SettingsKeys.lastDataRefresh) private var lastRefresh: Double = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            Text(text(now: timeline.date))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func text(now: Date) -> String {
        guard lastRefresh > 0 else { return "資料尚未更新" }
        let minutes = max(Int(now.timeIntervalSince1970 - lastRefresh) / 60, 0)
        if minutes < 1 { return "資料剛剛更新" }
        if minutes < 60 { return "資料更新於 \(minutes) 分鐘前" }
        return "資料更新於 \(minutes / 60) 小時前"
    }
}
