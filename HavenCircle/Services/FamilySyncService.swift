import Foundation
import CoreLocation
import SwiftData
import os

/// 登入 / 家庭圈狀態，供 UI 呈現對應提示
enum FamilySyncState: Equatable {
    case unknown
    case noAccount          // 未登入 Firebase Auth（Sign in with Apple）
    case ready              // 已登入，尚未建立或加入家庭圈
    case sharing            // 已是某個家庭圈的成員
    case error(String)
}

/// Firebase Firestore 家庭圈同步服務。
///
/// 設計：
/// - 身份用 Firebase Auth 的 uid（[AuthService]）——跨裝置、換手機都穩定，取代舊 CloudKit 的
///   本機隨機 participantID 與 CKCurrentUserDefaultName。
/// - 家庭圈根、成員、即時位置、安否回報都存 Firestore（[FirestoreFamilyBackend]）。
/// - 8 碼邀請碼取代 CKShare：建立者產生碼、家人輸碼加入，跨 iCloud 帳號都能用。
/// - 即時位置為「同意式」：使用者開啟分享才寫入 locations 子集合，隨時可停。
///
/// 保留舊架構的本機投影：把家人即時位置投影成 SwiftData 即時圈（[applyLiveLocationSnapshots]），
/// 讓既有的警報比對、地圖、摘要不必另外維護一套資料。
@MainActor
@Observable
final class FamilySyncService {
    private(set) var state: FamilySyncState = .unknown
    private(set) var pings: [SafetyPing] = []
    private(set) var liveLocations: [FamilyLiveLocation] = []
    private(set) var liveLocationError: String?
    /// 家人目前仍在求救中的清單（已篩掉自己、已篩 isStillUrgent）。
    private(set) var activeSOSAlerts: [SOSAlert] = []
    /// 本人是否正在求救中；預設從 UserDefaults 還原（跨 App 重啟保留），
    /// 讓首頁在 App 被強制關閉又重開後，能直接顯示「求救中」卡片而不是又冒出「發出求救」按鈕。
    private(set) var mySOSActive: Bool = UserDefaults.standard.bool(forKey: SettingsKeys.mySOSActive)
    /// 求救／解除求救失敗時的人話錯誤訊息，供首頁顯示（不 silent fail）。
    private(set) var sosError: String?
    /// 目前家庭圈的邀請碼（給 UI 顯示、分享給家人）；未在家庭圈時為 nil
    private(set) var currentInviteCode: String?
    /// 目前邀請碼的到期時間（C4：InviteOptionsView 顯示「效期至」用）。
    /// nil 代表「舊邀請碼沒有 expiresAt 欄位」（長期有效）或尚未讀到，兩者 UI 上顯示同一種文案。
    private(set) var currentInviteCodeExpiresAt: Date?
    /// 目前家庭圈的名稱（A4 header 用）；未在家庭圈或尚未讀到時為 nil
    private(set) var familyName: String?
    /// 目前家庭圈的成員 uid 清單（雲端真相）；未在家庭圈時為空陣列。
    /// FamilyListView 等畫面判斷「單人／多人」一律看這個，不看本機 LocalFamilyMember 筆數——
    /// 本機清單是投影，會落後於雲端（見 [isSolo]）。
    private(set) var memberUids: [String] = []
    /// 目前登入者是否為這個家庭圈的圈主（雲端真相）；未在家庭圈或尚未載入完成時為 false。
    /// 用於「退出家庭圈」判斷要走一般退出還是解散（見 [leaveFamily]）。
    private(set) var isFamilyOwner: Bool = false

    // 位置寫入去抖狀態（沿用舊邏輯，避免 GPS 抖動造成寫入風暴）
    private var lastPublishedLocation: CLLocation?
    private var lastPublishedAt: Date?
    private var lastPublishedRadius: Int?
    /// MainActor 在 await 期間仍可重入；只允許一筆位置寫入在途，避免重複建立同一 doc
    private var liveLocationPublishInFlight = false

    /// SOS 週期性位置更新的背景 Task（activateSOS 啟動、cancelSOS 呼叫 .cancel() 停止，
    /// 或本地判斷超過 8 小時自動停止）。App 重啟後若 mySOSActive 還原為 true，
    /// [resumeSOSLoopIfNeeded] 會在有 familyID 可用時重新啟動它。
    private var sosUpdateTask: Task<Void, Never>?

    /// Firebase 身份（未登入為 nil）
    private var uid: String? { AuthService.shared.uid }

    /// 目前所屬家庭圈的 Firestore familyId（本機快取；換裝置由 uid 反查還原）
    private var currentFamilyID: String? {
        get { UserDefaults.standard.string(forKey: SettingsKeys.currentFamilyID) }
        set {
            let defaults = UserDefaults.standard
            if let newValue {
                defaults.set(newValue, forKey: SettingsKeys.currentFamilyID)
            } else {
                defaults.removeObject(forKey: SettingsKeys.currentFamilyID)
            }
        }
    }

    var ownLiveLocation: FamilyLiveLocation? {
        guard let uid else { return nil }
        return liveLocations.first { $0.participantID == uid && $0.isSharing }
    }

    /// D1：「是否已加入或建立家庭圈」的單一真相來源。FamilyListView 等畫面的空狀態／
    /// 家人清單分支一律看這個，不看本機 LocalFamilyMember 筆數——後者是本機投影，
    /// 剛加入、refreshFamilyMembers 還沒跑完時會落後，導致「明明已加入卻還顯示邀請空狀態」的錯覺。
    var isInFamilyCircle: Bool { currentFamilyID != nil }

    /// 單人／多人判斷的共用規則（取代 FamilyListView／FamilyHubView／HomeStatusView 各自一份）：
    /// 已在家庭圈時看雲端 memberUids（至少含自己一人，尚未載入完成時保守視為單人，
    /// 避免「載入前一瞬間」誤判成多人而閃現錯的畫面）；未在家庭圈時退回本機成員數（沿用舊行為）。
    func isSolo(localMembers: [LocalFamilyMember]) -> Bool {
        if isInFamilyCircle {
            return max(memberUids.count, 1) < 2
        }
        return localMembers.filter { !$0.isPlace }.count < 2
    }

    private var displayName: String {
        UserDefaults.standard.string(forKey: SettingsKeys.profileDisplayName)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - 帳號 / 家庭狀態

    func refreshAccountStatus() async {
        guard AuthService.shared.isSignedIn, let uid else {
            state = .noAccount
            isFamilyOwner = false
            return
        }
        do {
            if currentFamilyID == nil {
                // 本機沒存 familyId 就用 uid 反查（換裝置、重裝後還原所屬家庭）
                if let family = try await FirestoreFamilyBackend.findFamily(forUid: uid) {
                    currentFamilyID = family.id
                    await applyFamily(family)
                }
            } else if let familyID = currentFamilyID {
                // 每次都重讀根文件，讓 familyName/memberUids（A4 header、D1 單人判斷）保持新鮮，
                // 而不是只在「邀請碼尚未快取」時才補讀一次。
                let family = try await FirestoreFamilyBackend.fetchFamily(familyId: familyID)
                await applyFamily(family)
            }
        } catch {
            AppLog.cloud.error("查詢所屬家庭失敗：\(error.localizedDescription)")
        }
        state = currentFamilyID == nil ? .ready : .sharing
        resumeSOSLoopIfNeeded()
    }

    /// 把家庭圈根文件套用到本服務暴露的欄位（邀請碼／名稱／成員 uid 清單），
    /// 並附帶讀一次邀請碼的到期時間（C4）。到期時間存在 inviteCodes/{code} 文件而不是家庭
    /// 根文件上，所以這裡多一次讀取；讀取失敗（例如剛好離線）不擋主流程，頂多這次先顯示
    /// nil，下次呼叫再補上，不影響其他欄位。
    private func applyFamily(_ family: FamilyCircleDoc) async {
        currentInviteCode = family.inviteCode
        familyName = family.name
        memberUids = family.memberUids
        isFamilyOwner = family.ownerUid == uid
        currentInviteCodeExpiresAt = try? await FirestoreFamilyBackend.fetchInviteCodeExpiry(code: family.inviteCode)
    }

    // MARK: - 建立 / 加入家庭圈（邀請碼取代 CKShare）

    /// 建立家庭圈（成為圈主）並產生邀請碼。回傳建立好的家庭圈。
    /// context 有給的話，建立完立即刷新一次成員清單（A2 呼叫點）；
    /// 內部自動建立（見 [ensureFamily]）不一定有 context 可用，留 nil 不強求。
    @discardableResult
    func createFamily(name: String = "我的家庭", context: ModelContext? = nil) async throws -> FamilyCircleDoc {
        guard let uid else { throw FamilyBackendError.notSignedIn }
        let family = try await FirestoreFamilyBackend.createFamily(
            ownerUid: uid,
            ownerDisplayName: displayName.isEmpty ? "圈主" : displayName,
            familyName: name
        )
        currentFamilyID = family.id
        await applyFamily(family)
        state = .sharing
        if let context {
            await refreshFamilyMembers(context: context)
        }
        return family
    }

    /// 用 8 碼邀請碼加入家庭圈。context 有給的話，加入成功立即刷新成員清單（A2 呼叫點）。
    func joinFamily(code: String, context: ModelContext? = nil) async throws {
        guard let uid else { throw FamilyBackendError.notSignedIn }
        let familyID = try await FirestoreFamilyBackend.joinFamily(
            code: code,
            uid: uid,
            displayName: displayName.isEmpty ? "家人" : displayName
        )
        currentFamilyID = familyID
        if let family = try? await FirestoreFamilyBackend.fetchFamily(familyId: familyID) {
            await applyFamily(family)
        }
        state = .sharing
        await fetchPings()
        if let context {
            await refreshFamilyMembers(context: context)
        }
    }

    /// 重新產生邀請碼（C3）：只有圈主能真正生效（對照 firestore.rules `inviteCodes/{code}`
    /// 的 `isOwner` 刪除權；非圈主呼叫舊碼刪不掉，但 UI 本來就只對圈主顯示這顆按鈕，見
    /// InviteOptionsView 用 [isFamilyOwner] 判斷）。成功後立即更新 currentInviteCode／
    /// currentInviteCodeExpiresAt，讓 QR code 與分享文案馬上換成新碼，不必等下次刷新。
    func regenerateInviteCode() async throws {
        guard let familyID = currentFamilyID else { return }
        let result = try await FirestoreFamilyBackend.regenerateInviteCode(familyId: familyID)
        currentInviteCode = result.code
        currentInviteCodeExpiresAt = result.expiresAt
    }

    /// 確保有家庭圈可寫入；沒有就自動建一個（給「還沒建家庭圈就發位置／回報」的情境）。回傳 familyId。
    private func ensureFamily() async throws -> String {
        if let familyID = currentFamilyID { return familyID }
        return try await createFamily().id
    }

    /// 邀請動線共用起點：FamilyListView「邀請家人」與事件詳情頁 C1 情境卡都從這裡開始——
    /// 還沒有家庭圈就建立一個（成為圈主）；已有的話原樣沿用現有邀請碼，不重建。
    /// 回傳「這是不是第一次建立家庭圈」，讓呼叫端決定要不要先接身分選擇（RoleSelectView）
    /// 再開邀請碼畫面——這個 UI 順序留在各畫面自己決定，這裡只管「確保家庭圈存在」這件事。
    @discardableResult
    func ensureInviteReady(context: ModelContext? = nil) async throws -> Bool {
        let isFirstFamily = currentInviteCode == nil
        if isFirstFamily {
            _ = try await createFamily(context: context)
        }
        return isFirstFamily
    }

    // MARK: - 家庭成員清單（A1）

    /// 從 Firestore 抓最新家庭圈根文件與成員清單，把「非本人」的成員 upsert 成本機
    /// LocalFamilyMember，並偵測「新成員加入」發本機通知（A3）。
    ///
    /// 鍵用 sharedIdentityKey（已查證：applyLiveLocationSnapshots 存的就是 Firebase uid，
    /// 兩邊共用同一把鍵，不需要新增欄位）。
    ///
    /// 保守處理「成員退出」：家庭裡已不存在的遠端成員，本機紀錄不自動刪除——刪除是破壞性操作，
    /// 且目前後端沒有明確的「已退出」語意（只是 memberUids 陣列裡少了這個 uid，也可能只是
    /// 暫時性的讀取或該筆成員文件還沒建立完成），貿然清掉本機資料(包含其固定圈設定)風險更大。
    func refreshFamilyMembers(context: ModelContext) async {
        guard let familyID = currentFamilyID, let selfUID = uid else { return }
        do {
            let family = try await FirestoreFamilyBackend.fetchFamily(familyId: familyID)
            await applyFamily(family)

            let remoteMembers = try await FirestoreFamilyBackend.fetchMembers(familyId: familyID)
            var localMembers = (try? context.fetch(FetchDescriptor<LocalFamilyMember>())) ?? []
            var changed = false

            for remote in remoteMembers where remote.id != selfUID {
                let resolvedName = remote.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = resolvedName.isEmpty ? "家人" : resolvedName
                if let existing = localMembers.first(where: { $0.sharedIdentityKey == remote.id }) {
                    if existing.name != name {
                        existing.name = name
                        changed = true
                    }
                } else {
                    let member = LocalFamilyMember(name: name, relationship: "家庭成員")
                    member.sharedIdentityKey = remote.id
                    context.insert(member)
                    localMembers.append(member)
                    changed = true
                }
            }
            if changed { context.saveReporting() }

            await notifyNewMembers(remoteMembers, selfUID: selfUID)
        } catch {
            AppLog.cloud.error("刷新家庭成員清單失敗：\(error.localizedDescription)")
        }
    }

    /// A3：跟上次同步已知的成員 uid 比對，非首次同步時出現的新 uid → 發本機通知慶祝。
    /// 首次同步（鍵不存在）只登記、不通知，避免剛加入一個既有大家庭就被歷史成員洗版。
    private func notifyNewMembers(_ remoteMembers: [FamilyMemberDoc], selfUID: String) async {
        let defaults = UserDefaults.standard
        let key = SettingsKeys.knownFamilyMemberUids
        let previouslyKnown = defaults.stringArray(forKey: key)
        let isFirstSync = previouslyKnown == nil
        var knownSet = Set(previouslyKnown ?? [])

        if !isFirstSync {
            let newcomers = remoteMembers.filter { $0.id != selfUID && !knownSet.contains($0.id) }
            for member in newcomers {
                let name = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayName = name.isEmpty ? "家人" : name
                // interruptionLevel 用 active（timeSensitive 預設 false）：這不是災害警報，
                // 不該突破勿擾模式。
                await NotificationScheduler.scheduleAlert(
                    title: "\(displayName) 已加入你的家庭圈 🎉",
                    body: "你們現在可以互相回報平安了。",
                    id: "member-joined-\(member.id)",
                    kind: "家庭成員加入"
                )
            }
        }
        knownSet.formUnion(remoteMembers.map(\.id))
        defaults.set(Array(knownSet), forKey: key)
    }

    // MARK: - 家庭即時圈

    /// 把這台手機最新的位置寫進家庭圈的 locations 子集合。
    /// 100 公尺內且 30 秒內的重複更新會合併，避免寫入風暴。
    func publishLiveLocation(
        _ location: CLLocation,
        displayName: String,
        radiusMeters: Int,
        context: ModelContext
    ) async {
        guard AuthService.shared.isSignedIn, let uid else {
            liveLocationError = "請先用 Apple 帳號登入，才能把即時位置分享給家人"
            return
        }
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            liveLocationError = "請先設定你的顯示名稱"
            return
        }
        let locationAge = max(0, -location.timestamp.timeIntervalSinceNow)
        guard locationAge <= 120,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 500 else {
            return
        }
        if let lastPublishedLocation, let lastPublishedAt,
           location.distance(from: lastPublishedLocation) < 100,
           lastPublishedRadius == radiusMeters,
           lastPublishedAt > Date.now.addingTimeInterval(-30) {
            return
        }
        guard !liveLocationPublishInFlight else { return }
        liveLocationPublishInFlight = true
        defer { liveLocationPublishInFlight = false }

        do {
            let familyID = try await ensureFamily()
            let localCircles = (try? context.fetch(FetchDescriptor<LocalLifeCircle>())) ?? []
            let district = localCircles.first {
                $0.isFollowMe && $0.member?.isCurrentUser == true
            }?.district ?? Districts.unspecified

            // 隱私與救援的取捨：寫入原始座標，不加雜訊模糊化——這是家人要據以趕去救人的位置。
            // 降低暴露改用其他手段：擷取端 ~100m 精度、預設關閉且可隨時停止、Security Rules 限同家庭可讀。
            try await FirestoreFamilyBackend.publishLocation(
                familyId: familyID,
                uid: uid,
                displayName: trimmedName,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                radiusMeters: max(300, min(radiusMeters, 3_000)),
                district: district
            )
            lastPublishedLocation = location
            lastPublishedAt = .now
            lastPublishedRadius = radiusMeters
            liveLocationError = nil
            state = .sharing
            await fetchLiveLocations(context: context)
        } catch {
            liveLocationError = "即時位置同步失敗：\(error.localizedDescription)"
            AppLog.cloud.error("即時位置同步失敗：\(error.localizedDescription)")
        }
    }

    /// 開啟本機位置分享的全套動作（B3-2）：LiveCircleSharingSection 的手動開關與
    /// PostJoinActivationView 的入圈後激活頁共用同一份實作，不要各寫一份——
    /// 要權限、寫入啟用旗標（給 App 啟動時的監聽判斷讀）、開始監聽、發布一次目前座標。
    /// 呼叫端若在意「iCloud／登入尚未就緒」（見 LiveCircleSharingSection.iCloudUnavailable）
    /// 要自己先擋，這裡不重複判斷——入圈後的激活頁在呼叫這裡之前必然已登入（joinFamily 前提）。
    func enableLiveLocationSharing(radiusMeters: Int, context: ModelContext) async {
        UserDefaults.standard.set(true, forKey: SettingsKeys.liveLocationSharingEnabled)
        LocationService.shared.requestAlwaysPermission()
        LocationService.shared.syncLiveLocationSharing(isEnabled: true)
        guard let location = await LocationService.shared.currentLocation() else { return }
        await publishLiveLocation(
            location,
            displayName: displayName,
            radiusMeters: radiusMeters,
            context: context
        )
    }

    /// 停止分享：標記雲端記錄停用，並清掉本機自己的即時圈。
    func stopLiveLocationSharing(context: ModelContext) async {
        let localCircles = (try? context.fetch(FetchDescriptor<LocalLifeCircle>())) ?? []
        for circle in localCircles where circle.kind == .live && circle.member?.isCurrentUser == true {
            context.delete(circle)
        }
        context.saveReporting()
        await EventPipeline.refresh(context: context)

        lastPublishedLocation = nil
        lastPublishedAt = nil
        lastPublishedRadius = nil
        liveLocationError = nil

        guard let uid, let familyID = currentFamilyID else { return }
        do {
            try await FirestoreFamilyBackend.stopLocation(familyId: familyID, uid: uid)
            await fetchLiveLocations(context: context)
        } catch {
            AppLog.cloud.error("停止即時位置分享失敗：\(error.localizedDescription)")
        }
    }

    /// 讀取家庭圈所有成員位置，並投影成本機 SwiftData 即時圈。
    func fetchLiveLocations(context: ModelContext) async {
        guard let familyID = currentFamilyID else { return }
        do {
            let locations = try await FirestoreFamilyBackend.fetchLocations(familyId: familyID)
            liveLocations = locations.sorted { $0.displayName < $1.displayName }
            let changed = applyLiveLocationSnapshots(liveLocations, context: context)
            if changed {
                context.saveReporting()
                await EventPipeline.refresh(context: context)
            }
        } catch {
            AppLog.cloud.error("讀取即時位置失敗：\(error.localizedDescription)")
        }
    }

    /// 把家人即時位置投影成本機 SwiftData 即時圈，讓警報比對／地圖／摘要共用同一套圈資料。
    private func applyLiveLocationSnapshots(
        _ locations: [FamilyLiveLocation],
        context: ModelContext
    ) -> Bool {
        let selfUID = uid ?? ""
        var members = (try? context.fetch(FetchDescriptor<LocalFamilyMember>())) ?? []
        var circles = (try? context.fetch(FetchDescriptor<LocalLifeCircle>())) ?? []
        let activeLocations = locations.filter(\.isSharing)
        let activeIDs = Set(activeLocations.map(\.id))
        var changed = false

        for circle in circles where circle.sharedLocationID != nil {
            guard let sourceID = circle.sharedLocationID, !activeIDs.contains(sourceID) else { continue }
            context.delete(circle)
            changed = true
        }

        for location in activeLocations {
            let member: LocalFamilyMember
            if let matched = members.first(where: { $0.sharedIdentityKey == location.participantID }) {
                member = matched
            } else if location.participantID == selfUID,
                      let current = members.first(where: \.isCurrentUser) {
                member = current
                member.sharedIdentityKey = location.participantID
            } else if let named = members.first(where: {
                !$0.isPlace && $0.sharedIdentityKey == nil && $0.name == location.displayName
            }) {
                member = named
                member.sharedIdentityKey = location.participantID
            } else {
                member = LocalFamilyMember(name: location.displayName, relationship: "家庭成員")
                member.sharedIdentityKey = location.participantID
                context.insert(member)
                members.append(member)
                changed = true
            }

            let circle: LocalLifeCircle
            if let existing = circles.first(where: { $0.sharedLocationID == location.id }) {
                circle = existing
            } else if location.participantID == selfUID,
                      let ownLive = member.lifeCircles.first(where: \.isFollowMe) {
                circle = ownLive
                circle.sharedLocationID = location.id
            } else {
                circle = LocalLifeCircle(
                    circleKey: "shared-\(location.id)",
                    name: location.participantID == selfUID
                        ? "我的即時圈"
                        : "\(location.displayName)的即時圈",
                    encryptedAddress: "位置由家人手機共享",
                    latitude: location.latitude,
                    longitude: location.longitude,
                    radiusMeters: location.radiusMeters,
                    alertTypes: EventCategory.defaultSelection,
                    member: member
                )
                context.insert(circle)
                circles.append(circle)
                changed = true
            }

            if circle.latitude != location.latitude
                || circle.longitude != location.longitude
                || circle.radiusMeters != location.radiusMeters
                || circle.locationUpdatedAt != location.updatedAt
                || circle.district != location.district {
                circle.latitude = location.latitude
                circle.longitude = location.longitude
                circle.radiusMeters = location.radiusMeters
                circle.locationUpdatedAt = location.updatedAt
                circle.district = location.district
                changed = true
            }
            let isOwnLocation = location.participantID == selfUID
            if circle.kind != .live
                || circle.sharedLocationID != location.id
                || circle.isFollowMe != isOwnLocation
                || circle.encryptedAddress != "位置由家人手機共享"
                || circle.member !== member {
                changed = true
            }
            circle.kind = .live
            circle.isFollowMe = isOwnLocation
            circle.sharedLocationID = location.id
            circle.encryptedAddress = "位置由家人手機共享"
            circle.member = member
        }
        return changed
    }

    // MARK: - 安否回報

    /// 送出一則安否回報。位置為回報者「自願附上」的一次性座標（nil＝沒附）。
    ///
    /// 回傳成敗（保命級 P0 修復）：舊版未登入時只默默設 state 就 return、
    /// 呼叫端（EventDetailView／NotificationDelegate／SafetyCheckInView）完全拿不到結果，
    /// 導致未登入或失敗時 UI 仍無條件顯示「已送出」的假成功。選 `Bool` 而非 `throws`：
    /// 三個呼叫端都只需要「成功了嗎」的是非題去決定要不要顯示回饋，不需要區分錯誤型別
    /// （人話文案已在下面就地轉換好、經由 [state] 帶出），throws 只會讓呼叫端多包一層
    /// do/catch 卻沒有額外資訊可用。
    @discardableResult
    func postPing(
        senderName: String,
        status: SafetyStatus,
        note: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        placeName: String? = nil
    ) async -> Bool {
        guard let uid else {
            state = .error("請先用 Apple 帳號登入，才能回報平安給家人")
            return false
        }
        do {
            let familyID = try await ensureFamily()
            _ = try await FirestoreFamilyBackend.postPing(
                familyId: familyID,
                senderUid: uid,
                senderName: senderName,
                status: status,
                note: note,
                latitude: latitude,
                longitude: longitude,
                placeName: placeName
            )
            await fetchPings()
            return true
        } catch {
            AppLog.cloud.error("送出安否回報失敗：\(error.localizedDescription)")
            state = .error(Self.humanPingErrorMessage(error))
            return false
        }
    }

    /// 安否回報失敗的人話文案（統一錯誤文案原則）：逾時的真相是「不確定送沒送出」——
    /// Firestore 離線佇列可能事後補送成功，一律用「可能未送出」＋教使用者怎麼自行確認，
    /// 不寫「已失敗」也不假裝成功。原始錯誤已在上一行進 AppLog，這裡只轉譯給使用者看的字串。
    private static func humanPingErrorMessage(_ error: Error) -> String {
        if error is SafetyPingTimeoutError {
            return "網路不穩，回報可能未送出——連上網路後會自動重試，家人清單出現你的回報才算成功"
        }
        return "回報失敗，請再試一次"
    }

    /// 讀取家庭圈所有安否回報（依時間新到舊），並對新回報發本機通知。
    func fetchPings() async {
        guard let familyID = currentFamilyID else { return }
        do {
            pings = try await FirestoreFamilyBackend.fetchPings(familyId: familyID)
            await notifyIncomingPings(pings)
        } catch {
            AppLog.cloud.error("讀取安否回報失敗：\(error.localizedDescription)")
        }
    }

    /// 家人回報通知：抓到「別人新送出」的回報時發本機通知。
    /// 已看過的回報 ID 存本機（上限 300）；首次同步只登記不通知，避免剛加入就被歷史回報洗版。
    private func notifyIncomingPings(_ latest: [SafetyPing]) async {
        let defaults = UserDefaults.standard
        let seenKey = "seenSafetyPingIDs"
        let myName = defaults.string(forKey: SettingsKeys.profileDisplayName) ?? ""
        let previouslySeen = defaults.stringArray(forKey: seenKey)
        let isFirstSync = previouslySeen == nil
        var seenSet = Set(previouslySeen ?? [])
        var seenList = previouslySeen ?? []

        for ping in latest where !seenSet.contains(ping.id) {
            seenSet.insert(ping.id)
            seenList.append(ping.id)
            guard !isFirstSync, ping.senderName != myName else { continue }
            let (title, body): (String, String) = switch ping.status {
            case .safe:
                ("\(ping.senderName)已回報平安",
                 ping.note.isEmpty ? "已收到平安回報。" : ping.note)
            case .inDanger:
                ("\(ping.senderName)回報：尚未脫離危險",
                 (ping.note.isEmpty ? "" : "\(ping.note)。") + "請持續關注並保持聯繫。")
            case .needHelp:
                ("\(ping.senderName)回報：需要協助",
                 (ping.note.isEmpty ? "" : "\(ping.note)。") + "請立即聯繫確認狀況。")
            case .pleaseReport:
                ("\(ping.senderName)想確認你是否平安",
                 "收到警報後，\(ping.senderName)發起了平安確認；請開啟 App 回報你的狀態。")
            }
            let urgent = ping.status != .safe
            await NotificationScheduler.scheduleAlert(
                title: title, body: body, id: "ping-\(ping.id)",
                timeSensitive: urgent,
                kind: "家人安否" // 家人安否視同重大：吵醒門檻設「僅重大」或安靜時段內仍會吵醒
            )
        }

        if seenList.count > 300 { seenList.removeFirst(seenList.count - 300) }
        defaults.set(seenList, forKey: seenKey)
    }

    /// 標記某則回報為「我已讀」（已讀回條）
    func markRead(pingID: String, readerName: String) async {
        guard let familyID = currentFamilyID else { return }
        do {
            try await FirestoreFamilyBackend.markPingRead(
                familyId: familyID,
                pingId: pingID,
                readerName: readerName
            )
            await fetchPings()
        } catch {
            AppLog.cloud.error("更新安否回報已讀狀態失敗：\(error.localizedDescription)")
        }
    }

    // MARK: - SOS 一鍵求救

    /// 發出求救：需已登入（未登入給明確錯誤訊息，不 silent fail）。取得目前位置
    /// （[LocationService.currentLocation] 內建約 12 秒逾時、未授權或取不到一律回 nil）；
    /// 拿不到位置仍要能發出「求救狀態」本身——這是保命功能，位置是加分不是必要條件，
    /// 拿不到就用 0,0 明顯標記「沒有座標」（見 [SOSAlert.hasLocation]），並在本機提示。
    /// 成功後啟動週期性位置更新迴圈（見 [startSOSLocationLoop]），直到 [cancelSOS] 或
    /// 本地判斷超過 8 小時為止。
    func activateSOS(context: ModelContext) async {
        guard AuthService.shared.isSignedIn, let uid else {
            sosError = "請先用 Apple 帳號登入，才能發出求救給家人"
            return
        }
        let name = displayName.isEmpty ? "家人" : displayName
        do {
            let familyID = try await ensureFamily()
            let location = await LocationService.shared.currentLocation()
            try await FirestoreFamilyBackend.publishSOS(
                familyId: familyID,
                uid: uid,
                displayName: name,
                latitude: location?.coordinate.latitude ?? 0,
                longitude: location?.coordinate.longitude ?? 0
            )
            sosError = location == nil
                ? "已發出求救，但無法取得你的位置——請確認定位權限已開啟，之後取得位置會自動補上。"
                : nil
            mySOSActive = true
            UserDefaults.standard.set(true, forKey: SettingsKeys.mySOSActive)
            startSOSLocationLoop(familyID: familyID, uid: uid, name: name)
        } catch {
            AppLog.cloud.error("發出求救失敗：\(error.localizedDescription)")
            sosError = Self.humanSOSErrorMessage(error)
        }
    }

    /// 解除求救：停止週期性更新 Task、標記本機與雲端狀態。context 目前 SOS 沒有 SwiftData
    /// 投影可清（純 Firestore struct，不進 SwiftData schema），保留參數是為了跟
    /// activateSOS／其他家庭圈方法的呼叫慣例一致，供未來需要時使用。
    func cancelSOS(context: ModelContext) async {
        sosUpdateTask?.cancel()
        sosUpdateTask = nil
        mySOSActive = false
        UserDefaults.standard.set(false, forKey: SettingsKeys.mySOSActive)
        guard let uid, let familyID = currentFamilyID else { return }
        do {
            try await FirestoreFamilyBackend.resolveSOS(familyId: familyID, uid: uid)
            sosError = nil
        } catch {
            AppLog.cloud.error("解除求救失敗：\(error.localizedDescription)")
            sosError = "解除求救時網路連線有問題，請稍後再試一次；家人可能仍會看到你在求救中。"
        }
    }

    /// 讀取家庭圈所有成員的求救狀態，篩掉自己與已不再緊急的（isStillUrgent），
    /// 並對「新出現的」求救觸發一則本機通知（見 [notifyIncomingSOS] 去重邏輯）。
    func fetchActiveSOSAlerts(context: ModelContext) async {
        guard let familyID = currentFamilyID else { return }
        do {
            let alerts = try await FirestoreFamilyBackend.fetchActiveSOSAlerts(familyId: familyID)
            let urgent = alerts
                .filter(\.isStillUrgent)
                .filter { $0.participantID != uid }
                .sorted { $0.updatedAt > $1.updatedAt }
            activeSOSAlerts = urgent
            await notifyIncomingSOS(urgent)
        } catch {
            AppLog.cloud.error("讀取求救狀態失敗：\(error.localizedDescription)")
        }
    }

    /// 週期性位置更新：每 90 秒重新取得位置並更新 Firestore 求救文件，只要 mySOSActive
    /// 仍為真就持續，直到 [cancelSOS] 呼叫 `.cancel()`，或本地判斷這次求救已經開始超過
    /// 8 小時（保守的本地保險絲，避免忘記解除的求救無限期消耗電力；家人端「這筆是否還算
    /// 緊急」則交由 [SOSAlert.isStillUrgent] 獨立判斷，兩者門檻一致但用途不同）。
    private func startSOSLocationLoop(familyID: String, uid: String, name: String) {
        sosUpdateTask?.cancel()
        let loopStartedAt = Date.now
        sosUpdateTask = Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(for: .seconds(90))
                } catch {
                    return // 被 cancelSOS 取消
                }
                guard let self, self.mySOSActive else { return }
                guard Date.now.timeIntervalSince(loopStartedAt) < 8 * 3600 else { return }
                if let location = await LocationService.shared.currentLocation() {
                    try? await FirestoreFamilyBackend.publishSOS(
                        familyId: familyID,
                        uid: uid,
                        displayName: name,
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                }
            }
        }
    }

    /// App 重啟後若仍在求救中（mySOSActive 從 UserDefaults 還原為 true），重新啟動週期性
    /// 位置更新迴圈——否則重開 App 後求救狀態還在但位置不再更新，家人看到的座標會愈來愈舊。
    /// 已有 Task 在跑（例如同一次執行期間重複呼叫 refreshAccountStatus）就不重啟。
    private func resumeSOSLoopIfNeeded() {
        guard mySOSActive, sosUpdateTask == nil, let uid, let familyID = currentFamilyID else { return }
        startSOSLocationLoop(familyID: familyID, uid: uid, name: displayName.isEmpty ? "家人" : displayName)
    }

    /// 求救求救失敗的人話文案：逾時的真相是「不確定送沒送出」，緊急狀況下要教使用者
    /// 立刻改用其他管道（電話、簡訊），不能只等 App 這一條路徑。
    private static func humanSOSErrorMessage(_ error: Error) -> String {
        if error is SOSTimeoutError {
            return "網路不穩，求救可能未送出——連上網路後會自動重試；情況緊急請同時嘗試電話或簡訊聯繫家人。"
        }
        return "發出求救失敗，請再試一次；情況緊急請同時嘗試電話或簡訊聯繫家人。"
    }

    /// 求救通知：抓到「別人新發出」的求救時發本機通知。去重鍵含 startedAt（不是只用
    /// participantID）：同一人解除後重新求救會拿到新的 startedAt，視為「新的一次」重新
    /// 通知；同一次求救持續的位置更新（updatedAt 一直變但 startedAt 不變）則不會重複吵。
    /// 已通知過的鍵存本機（上限 300，比照 [notifyIncomingPings]）；首次同步只登記不通知，
    /// 避免剛加入就被既有的求救紀錄洗版。
    private func notifyIncomingSOS(_ latest: [SOSAlert]) async {
        let defaults = UserDefaults.standard
        let seenKey = "seenSOSAlertKeys"
        let previouslySeen = defaults.stringArray(forKey: seenKey)
        let isFirstSync = previouslySeen == nil
        var seenSet = Set(previouslySeen ?? [])
        var seenList = previouslySeen ?? []

        for alert in latest {
            let key = "\(alert.participantID)#\(Int(alert.startedAt.timeIntervalSince1970))"
            guard !seenSet.contains(key) else { continue }
            seenSet.insert(key)
            seenList.append(key)
            guard !isFirstSync else { continue }
            // interruptionLevel 用 timeSensitive（kind: 家人安否 視同重大）：求救比一般
            // 家人安否更急，理應能突破勿擾模式。
            await NotificationScheduler.scheduleAlert(
                title: "⚠️ \(alert.displayName)發出求救",
                body: "開啟 App 查看即時位置與導航；非即時通知，回到前景才會看到最新狀態。",
                id: "sos-\(key)",
                timeSensitive: true,
                kind: "家人安否"
            )
        }
        if seenList.count > 300 { seenList.removeFirst(seenList.count - 300) }
        defaults.set(seenList, forKey: seenKey)
    }

    // MARK: - 退出／解散家庭圈（帳號刪除流程／主動退出用）

    /// 退出（一般成員／圈主但還有其他成員）或解散（圈主且只剩自己一人）目前的家庭圈。
    ///
    /// 判斷依據：[isFamilyOwner] ＋ [memberUids]（雲端真相，同 [isSolo] 的判法）——
    /// 圈主且 memberUids 只剩自己一人時走解散（[FirestoreFamilyBackend.deleteFamily]，
    /// 對照 firestore.rules 允許圈主 delete 根文件那條）；其餘情況走一般退出
    /// （[FirestoreFamilyBackend.leaveFamily]，只把自己移出 memberUids）。
    ///
    /// Firestore 呼叫失敗會原樣往上拋，呼叫端（FamilyListView 的「退出家庭圈」按鈕）要接住
    /// 顯示人話錯誤，不能 silent fail；帳號整個刪除那條路徑（SettingsView.deleteEverything）
    /// 呼叫這裡時刻意用 `try?` 吞掉錯誤——那條路徑就算離線，本機清除仍要能完成，
    /// 不該被雲端呼叫失敗卡住。
    ///
    /// context 有給的話（一般由「退出家庭圈」按鈕呼叫），額外清掉同步而來的家人本機投影
    /// （見 [purgeSyncedFamilyProjection]），保留使用者手動新增的家人與所有其他本機資料——
    /// 這條路徑跟整個刪帳號不同，是「只離開這個家庭圈，其他本機資料保留」。
    func leaveFamily(context: ModelContext? = nil) async throws {
        if let uid, let familyID = currentFamilyID {
            if isFamilyOwner, memberUids.count <= 1 {
                try await FirestoreFamilyBackend.deleteFamily(familyId: familyID, uid: uid)
            } else {
                try await FirestoreFamilyBackend.leaveFamily(familyId: familyID, uid: uid)
            }
        }
        if let context {
            purgeSyncedFamilyProjection(context: context)
        }
        pings = []
        liveLocations = []
        // 離開／解散家庭圈：這個家庭圈的求救狀態不再與我相關，停掉背景更新迴圈與本機旗標
        // （雲端 sos 文件已由 FirestoreFamilyBackend.leaveFamily/deleteFamily 清掉）。
        sosUpdateTask?.cancel()
        sosUpdateTask = nil
        mySOSActive = false
        UserDefaults.standard.set(false, forKey: SettingsKeys.mySOSActive)
        activeSOSAlerts = []
        currentFamilyID = nil
        currentInviteCode = nil
        currentInviteCodeExpiresAt = nil
        familyName = nil
        memberUids = []
        isFamilyOwner = false
        // 清掉 CloudKit 舊架構殘留的鍵
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: SettingsKeys.activeFamilyZoneName)
        defaults.removeObject(forKey: SettingsKeys.activeFamilyOwnerName)
        defaults.removeObject(forKey: SettingsKeys.knownFamilyMemberUids)
        await refreshAccountStatus()
    }

    /// 清掉「同步而來」的家人本機投影：sharedIdentityKey 非 nil（代表是雲端家庭圈成員投影
    /// 出來的，見 [refreshFamilyMembers] / [applyLiveLocationSnapshots]）且不是本人、
    /// 不是重要地點的紀錄。手動新增的家人（sharedIdentityKey == nil）刻意保留——
    /// 那是使用者自己建的本機資料，跟「這台裝置屬於哪個雲端家庭圈」無關。
    private func purgeSyncedFamilyProjection(context: ModelContext) {
        guard let members = try? context.fetch(FetchDescriptor<LocalFamilyMember>()) else { return }
        var changed = false
        for member in members where !member.isCurrentUser && !member.isPlace && member.sharedIdentityKey != nil {
            context.delete(member)
            changed = true
        }
        if changed { context.saveReporting() }
    }
}
