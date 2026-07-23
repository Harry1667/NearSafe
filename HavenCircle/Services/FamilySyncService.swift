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
    /// 目前家庭圈的邀請碼（給 UI 顯示、分享給家人）；未在家庭圈時為 nil
    private(set) var currentInviteCode: String?

    // 位置寫入去抖狀態（沿用舊邏輯，避免 GPS 抖動造成寫入風暴）
    private var lastPublishedLocation: CLLocation?
    private var lastPublishedAt: Date?
    private var lastPublishedRadius: Int?
    /// MainActor 在 await 期間仍可重入；只允許一筆位置寫入在途，避免重複建立同一 doc
    private var liveLocationPublishInFlight = false

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

    private var displayName: String {
        UserDefaults.standard.string(forKey: SettingsKeys.profileDisplayName)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - 帳號 / 家庭狀態

    func refreshAccountStatus() async {
        guard AuthService.shared.isSignedIn, let uid else {
            state = .noAccount
            return
        }
        // 本機沒存 familyId 就用 uid 反查（換裝置、重裝後還原所屬家庭）
        if currentFamilyID == nil {
            do {
                if let family = try await FirestoreFamilyBackend.findFamily(forUid: uid) {
                    currentFamilyID = family.id
                    currentInviteCode = family.inviteCode
                }
            } catch {
                AppLog.cloud.error("查詢所屬家庭失敗：\(error.localizedDescription)")
            }
        } else if currentInviteCode == nil, let familyID = currentFamilyID {
            currentInviteCode = try? await FirestoreFamilyBackend.fetchFamily(familyId: familyID).inviteCode
        }
        state = currentFamilyID == nil ? .ready : .sharing
    }

    // MARK: - 建立 / 加入家庭圈（邀請碼取代 CKShare）

    /// 建立家庭圈（成為圈主）並產生邀請碼。回傳建立好的家庭圈。
    @discardableResult
    func createFamily(name: String = "我的家庭") async throws -> FamilyCircleDoc {
        guard let uid else { throw FamilyBackendError.notSignedIn }
        let family = try await FirestoreFamilyBackend.createFamily(
            ownerUid: uid,
            ownerDisplayName: displayName.isEmpty ? "圈主" : displayName,
            familyName: name
        )
        currentFamilyID = family.id
        currentInviteCode = family.inviteCode
        state = .sharing
        return family
    }

    /// 用 8 碼邀請碼加入家庭圈。
    func joinFamily(code: String) async throws {
        guard let uid else { throw FamilyBackendError.notSignedIn }
        let familyID = try await FirestoreFamilyBackend.joinFamily(
            code: code,
            uid: uid,
            displayName: displayName.isEmpty ? "家人" : displayName
        )
        currentFamilyID = familyID
        currentInviteCode = try? await FirestoreFamilyBackend.fetchFamily(familyId: familyID).inviteCode
        state = .sharing
        await fetchPings()
    }

    /// 確保有家庭圈可寫入；沒有就自動建一個（給「還沒建家庭圈就發位置／回報」的情境）。回傳 familyId。
    private func ensureFamily() async throws -> String {
        if let familyID = currentFamilyID { return familyID }
        return try await createFamily().id
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
    func postPing(
        senderName: String,
        status: SafetyStatus,
        note: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        placeName: String? = nil
    ) async {
        guard let uid else {
            state = .error("請先用 Apple 帳號登入，才能回報平安給家人")
            return
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
        } catch {
            AppLog.cloud.error("送出安否回報失敗：\(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
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

    // MARK: - 退出家庭圈（帳號刪除流程／主動退出用）

    func leaveFamily() async {
        if let uid, let familyID = currentFamilyID {
            do {
                try await FirestoreFamilyBackend.leaveFamily(familyId: familyID, uid: uid)
            } catch {
                AppLog.cloud.error("退出家庭圈失敗：\(error.localizedDescription)")
            }
        }
        pings = []
        liveLocations = []
        currentFamilyID = nil
        currentInviteCode = nil
        // 清掉 CloudKit 舊架構殘留的鍵
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: SettingsKeys.activeFamilyZoneName)
        defaults.removeObject(forKey: SettingsKeys.activeFamilyOwnerName)
        await refreshAccountStatus()
    }
}
