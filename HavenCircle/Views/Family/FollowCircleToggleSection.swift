import SwiftUI
import SwiftData
import CoreLocation

/// 「警報跟著我」：純本地功能，跟「分享位置給家人」（LiveCircleSharingSection／Firebase）
/// 是兩碼事——這裡完全不經 SignInPreflight、不碰 AuthService。開啟只是在本機維持一個
/// isFollowMe 的 LocalLifeCircle，讓警戒圈跟著這支手機的顯著位置變更移動
/// （FollowCircleService 負責移動時更新圈心＋重跑比對）；不需要登入、不會同步給任何人。
///
/// ON/OFF 不是「建立/刪除」，而是「同一顆圈的兩種狀態」：關掉不代表使用者不要警戒圈了，
/// 只是不要它跟著人移動——圈留在最後位置變成固定圈，名稱跟著換（我的身邊／我的附近），
/// 之後開回來就翻回 isFollowMe=true，不重新取位置、不重建圈。這樣使用者才不會因為
/// 關掉跟隨就失去唯一的警戒圈（也不會在地圖上把辛苦拖曳調整過的圈心弄丟）。
struct FollowCircleToggleSection: View {
    /// 開啟時的圈名；FirstRunSetup 建立預設圈時也用這個名稱，兩處共用同一組常數，
    /// 避免各自硬寫字串日後改一個忘了改另一個。
    static let onName = "我的身邊"
    /// 關閉時的圈名（沿用舊 FirstRunSetup 的預設圈命名，語意上就是「固定下來的附近」）。
    static let offName = "我的附近"

    /// 「有家人」卡片會緊接著 LiveCircleSharingSection（標題「分享這支手機的位置」）放在一起，
    /// 兩個都提到「位置」容易混淆，這裡加註「只在這支手機」；單人空狀態旁邊沒有其他位置類
    /// 開關，不需要這段註記（少字紀律，能不加字就不加）。
    var disambiguateFromSharing: Bool = false

    @Environment(\.modelContext) private var context
    @Query private var members: [LocalFamilyMember]
    @Query private var circles: [LocalLifeCircle]

    @State private var isWorking = false
    @State private var hint: String?

    /// 本人身上「警報跟著我」這顆專屬圈：無論目前開或關都是同一顆資料列，只用固定的
    /// 兩個名稱＋isCurrentUser 辨識，不靠 isFollowMe（那個欄位本身就是要被切換的狀態，
    /// 不能拿來當「找到哪一顆」的依據）。
    private var myFollowCircle: LocalLifeCircle? {
        circles.first {
            $0.member?.isCurrentUser == true
                && ($0.name == Self.onName || $0.name == Self.offName)
        }
    }

    private var isOn: Bool { myFollowCircle?.isFollowMe ?? false }

    private var title: String {
        disambiguateFromSharing ? "警報跟著我（只在這支手機）" : "警報跟著我"
    }

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { isOn }, set: toggle)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text("你移動時，警戒圈跟著你")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isWorking)
            if isWorking {
                HStack(spacing: HCSpacing.x2) {
                    ProgressView()
                    Text("正在取得目前位置…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(HCColor.attention)
            }
        }
    }

    private func toggle(_ on: Bool) {
        hint = nil
        if on {
            enableFollowCircle()
        } else {
            disableFollowCircle()
        }
    }

    /// 開：已經有本人的專屬圈（不管剛剛是關的狀態）就直接翻回 isFollowMe=true＋改名，
    /// 圈心留在原地——不必重新取位置，之後移動再由 FollowCircleService 接手更新。
    /// 真的完全沒有這顆圈（理論上不會發生，FirstRunSetup 一定會建）才現取位置建新的。
    private func enableFollowCircle() {
        if let circle = myFollowCircle {
            circle.isFollowMe = true
            circle.name = Self.onName
            context.saveReporting()
            LocationService.shared.syncFollowMonitoring(hasFollowCircle: true)
            Analytics.track("follow_circle_enabled")
            return
        }
        // 從未問過權限才主動問；被拒過就交給下面的 currentLocation 自然回 nil，不再吵第二次
        if LocationService.shared.authorization == .notDetermined {
            LocationService.shared.requestPermissionIfNeeded()
        }
        isWorking = true
        Task {
            defer { isWorking = false }
            guard let location = await LocationService.shared.currentLocation() else {
                hint = "無法取得目前位置，請確認已允許定位權限後再試一次。"
                return
            }
            let me = currentUserMember()
            let circle = LocalLifeCircle(
                name: Self.onName,
                encryptedAddress: "位置由這支手機分享",
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                radiusMeters: 1_000,
                alertTypes: EventCategory.defaultSelection,
                member: me
            )
            circle.isFollowMe = true
            circle.kind = .live
            circle.locationUpdatedAt = .now
            context.insert(circle)
            context.saveReporting()
            LocationService.shared.syncFollowMonitoring(hasFollowCircle: true)
            await EventPipeline.refresh(context: context)
            Analytics.track("follow_circle_enabled")
        }
    }

    /// 關：不刪圈——把 isFollowMe 設 false、改名成固定圈語意的「我的附近」，圈留在
    /// 最後位置。純本機操作，不牽動 Firebase 或分享狀態。
    private func disableFollowCircle() {
        guard let circle = myFollowCircle, circle.isFollowMe else { return } // 已經是關的就不重複動作/不重複埋點
        circle.isFollowMe = false
        circle.name = Self.offName
        context.saveReporting()
        LocationService.shared.syncFollowMonitoring(
            hasFollowCircle: FollowCircleService.hasFollowCircle(context: context)
        )
        Task { await EventPipeline.refresh(context: context) }
        Analytics.track("follow_circle_disabled")
    }

    /// 理論上 FirstRunSetup 一定會建立 isCurrentUser 成員；防禦性地在缺漏時補建一個，
    /// 避免跟隨圈掛不到人身上。
    private func currentUserMember() -> LocalFamilyMember {
        if let existing = members.first(where: \.isCurrentUser) { return existing }
        let me = LocalFamilyMember(name: "我", relationship: "擁有者")
        me.isCurrentUser = true
        context.insert(me)
        return me
    }
}
