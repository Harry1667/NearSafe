import Foundation
import CloudKit
import CoreLocation
import SwiftData
import os

/// iCloud 帳號 / 同步狀態，供 UI 呈現對應提示
enum FamilySyncState: Equatable {
    case unknown
    case noAccount          // 未登入 iCloud（模擬器常見）
    case ready              // 可用，但尚未建立或加入家庭
    case sharing            // 已是某個家庭圈的擁有者或成員
    case error(String)
}

/// CloudKit + CKShare 家庭連結服務。
///
/// 設計：
/// - 擁有者在自己的 private database 建一個自訂 zone，內含一筆「家庭圈」根記錄。
/// - 對根記錄建立 CKShare，透過 UICloudSharingController 產生邀請連結／QR。
/// - 安否回報（SafetyPing）以根記錄為 parent 寫入同一 zone，因此自動納入分享範圍。
/// - 家人接受邀請後，用 shared database 存取同一 zone；雙方讀寫同一批 SafetyPing。
///
/// 測試邊界：CKShare 的跨帳號流程無法在模擬器或單一 iCloud 帳號下端到端驗證，
/// 需要兩台登入不同 iCloud 帳號的實機、已佈建的 CloudKit container 與付費開發者帳號。
/// 本服務對「未登入 iCloud」等情境做了明確降級，不會讓 App 崩潰。
@MainActor
@Observable
final class FamilySyncService {
    static let containerID = "iCloud.com.gomiigo.CamMenuApp.HavenCircle"
    static let zoneName = "FamilyCircleZone"
    static let rootRecordType = "FamilyCircle"
    static let rootRecordName = "family-root"

    private(set) var state: FamilySyncState = .unknown
    private(set) var pings: [SafetyPing] = []
    private(set) var liveLocations: [FamilyLiveLocation] = []
    private(set) var liveLocationError: String?

    private let container: CKContainer
    private var lastPublishedLocation: CLLocation?
    private var lastPublishedAt: Date?
    private var lastPublishedRadius: Int?
    /// MainActor 在 `await` 期間仍可重入；首次開啟分享時，手動取位與 CLLocationManager
    /// 回呼可能同時進來。只允許一筆 CloudKit upsert 在途，避免重複 insert 同一 record。
    private var liveLocationPublishInFlight = false
    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    private var selectedSharedZoneID: CKRecordZone.ID? {
        let defaults = UserDefaults.standard
        guard
            let zoneName = defaults.string(forKey: SettingsKeys.activeFamilyZoneName),
            let ownerName = defaults.string(forKey: SettingsKeys.activeFamilyOwnerName),
            !zoneName.isEmpty,
            !ownerName.isEmpty
        else { return nil }
        return CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
    }

    init() {
        container = CKContainer(identifier: Self.containerID)
    }

    private var participantID: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: SettingsKeys.liveLocationDeviceID) {
            return existing
        }
        let created = UUID().uuidString
        defaults.set(created, forKey: SettingsKeys.liveLocationDeviceID)
        return created
    }

    var ownLiveLocation: FamilyLiveLocation? {
        liveLocations.first { $0.participantID == participantID && $0.isSharing }
    }

    // MARK: - 帳號狀態

    func refreshAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                state = .ready
            case .noAccount:
                state = .noAccount
            default:
                state = .error("iCloud 帳號目前無法使用（狀態 \(status.rawValue)）")
            }
        } catch {
            AppLog.cloud.error("查詢 iCloud 帳號狀態失敗：\(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - 建立/取得家庭圈

    /// 確保自訂 zone 與家庭圈根記錄存在（擁有者端）
    @discardableResult
    func ensureFamilyRoot() async throws -> CKRecord {
        let db = container.privateCloudDatabase
        try await ensureZone(in: db)
        let rootID = CKRecord.ID(recordName: Self.rootRecordName, zoneID: zoneID)
        do {
            return try await db.record(for: rootID)
        } catch let error as CKError where error.code == .unknownItem {
            let root = CKRecord(recordType: Self.rootRecordType, recordID: rootID)
            root["createdAt"] = Date.now
            return try await db.save(root)
        }
    }

    private func ensureZone(in db: CKDatabase) async throws {
        do {
            _ = try await db.recordZone(for: zoneID)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            _ = try await db.save(CKRecordZone(zoneID: zoneID))
        }
    }

    /// 建立分享。回傳的 (share, container) 交給 UICloudSharingController 產生邀請。
    func makeShare() async throws -> (CKShare, CKContainer) {
        guard selectedSharedZoneID == nil else {
            throw FamilyInvitationError.onlyOwnerCanInvite
        }
        let root = try await ensureFamilyRoot()
        let db = container.privateCloudDatabase
        // 若已存在分享，直接沿用
        if let existingShareRef = root.share {
            let share = try await db.record(for: existingShareRef.recordID) as? CKShare
            if let share { return (share, container) }
        }
        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "安心圈家庭" as CKRecordValue
        share.publicPermission = .none
        _ = try await db.modifyRecords(saving: [root, share], deleting: [])
        state = .sharing
        return (share, container)
    }

    /// 為不知道 Apple 帳號／電話的家人建立一次性私人邀請。
    /// 一般 CKShare URL 在 publicPermission == .none 時不能讓陌生收件者加入；QR 與邀請碼必須用這條 URL。
    func makeOneTimeInvitation(for originalShare: CKShare) async throws -> URL {
        let db = container.privateCloudDatabase
        var share = originalShare

        for attempt in 0..<2 {
            let participant = CKShare.Participant.oneTimeURLParticipant()
            participant.permission = .readWrite
            share.addParticipant(participant)

            do {
                guard let savedShare = try await db.save(share) as? CKShare else {
                    throw FamilyInvitationError.savedRecordWasNotShare
                }
                guard let url = savedShare.oneTimeURL(for: participant.participantID) else {
                    throw FamilyInvitationError.oneTimeURLUnavailable
                }
                return url
            } catch let error as CKError where error.code == .serverRecordChanged && attempt == 0 {
                guard let latest = try await db.record(for: originalShare.recordID) as? CKShare else {
                    throw FamilyInvitationError.savedRecordWasNotShare
                }
                share = latest
            }
        }

        throw FamilyInvitationError.oneTimeURLUnavailable
    }

    // MARK: - 接受分享（家人端）

    /// 從分享連結接受邀請（8 位邀請碼兌換後走這條；點連結則由 scene delegate 走 accept(_:)）。
    /// 只有「抓取 metadata」會拋錯；接受階段的錯誤沿用 accept(_:) 的慣例寫進 state。
    func acceptShare(from url: URL) async throws {
        let metadata: CKShare.Metadata = try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareMetadataOperation(shareURLs: [url])
            var fetched: CKShare.Metadata?
            operation.perShareMetadataResultBlock = { _, result in
                if case .success(let metadata) = result { fetched = metadata }
            }
            operation.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    if let fetched {
                        continuation.resume(returning: fetched)
                    } else {
                        continuation.resume(throwing: CKError(.unknownItem))
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
        await accept(metadata)
    }

    func accept(_ metadata: CKShare.Metadata) async {
        do {
            _ = try await container.accept(metadata)
            // 這台裝置可能在加入前已建立自己的空白 private 家庭圈。記住剛接受的 shared zone，
            // 後續定位與安否回報才不會被寫回另一個圈。
            let acceptedZoneID = metadata.hierarchicalRootRecordID?.zoneID ?? metadata.share.recordID.zoneID
            let defaults = UserDefaults.standard
            defaults.set(acceptedZoneID.zoneName, forKey: SettingsKeys.activeFamilyZoneName)
            defaults.set(acceptedZoneID.ownerName, forKey: SettingsKeys.activeFamilyOwnerName)
            state = .sharing
            await fetchPings()
        } catch {
            AppLog.cloud.error("接受家庭邀請失敗：\(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - 家庭即時圈

    /// 把這台手機最新的位置寫成 CKShare 裡的一筆穩定記錄。
    /// 100 公尺內且 30 秒內的重複更新會合併，避免 GPS 抖動造成 CloudKit 寫入風暴。
    func publishLiveLocation(
        _ location: CLLocation,
        displayName: String,
        radiusMeters: Int,
        context: ModelContext
    ) async {
        guard state != .noAccount else {
            liveLocationError = "請先登入 iCloud，才能把即時位置分享給家庭成員"
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
        guard !liveLocationPublishInFlight else {
            return
        }
        liveLocationPublishInFlight = true
        defer { liveLocationPublishInFlight = false }

        do {
            let (db, rootID) = try await resolveDatabaseAndRoot(createIfNeeded: true)
            let recordID = CKRecord.ID(
                recordName: "live-\(participantID)",
                zoneID: rootID.zoneID
            )
            let record: CKRecord
            let isNewRecord: Bool
            do {
                record = try await db.record(for: recordID)
                isNewRecord = false
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: FamilyLiveLocation.Field.recordType, recordID: recordID)
                record.setParent(rootID)
                isNewRecord = true
            }

            let localCircles = (try? context.fetch(FetchDescriptor<LocalLifeCircle>())) ?? []
            let district = localCircles.first {
                $0.isFollowMe && $0.member?.isCurrentUser == true
            }?.district ?? Districts.unspecified

            func applyLatestValues(to target: CKRecord) {
                target[FamilyLiveLocation.Field.participantID] = participantID
                target[FamilyLiveLocation.Field.displayName] = trimmedName
                // 隱私與救援的取捨：即時位置寫入的是原始座標，「刻意不再加雜訊模糊化」——
                // 這是家人要據以趕去救人的位置，模糊化反而傷害用途。降低暴露改用其他手段：
                // 擷取端已設 ~100m 精度（kCLLocationAccuracyHundredMeters）、資料只進使用者自己的
                // iCloud（僅受邀家人可讀、開發者拿不到）、預設關閉且可隨時停止分享。
                target[FamilyLiveLocation.Field.latitude] = location.coordinate.latitude
                target[FamilyLiveLocation.Field.longitude] = location.coordinate.longitude
                target[FamilyLiveLocation.Field.radiusMeters] = max(300, min(radiusMeters, 3_000))
                target[FamilyLiveLocation.Field.district] = district
                target[FamilyLiveLocation.Field.updatedAt] = location.timestamp
                target[FamilyLiveLocation.Field.isSharing] = true
            }

            applyLatestValues(to: record)
            do {
                _ = try await db.save(record)
            } catch let error as CKError where isNewRecord && Self.isInsertConflict(error) {
                // 另一個執行個體已在「查無記錄」與 save 之間建立同一筆 record。
                // 抓回帶 server change tag 的版本再更新，讓首次分享保持冪等。
                let serverRecord = try await db.record(for: recordID)
                applyLatestValues(to: serverRecord)
                _ = try await db.save(serverRecord)
            }

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

    private static func isInsertConflict(_ error: CKError) -> Bool {
        switch error.code {
        case .serverRecordChanged, .constraintViolation:
            return true
        default:
            // 部分 CloudKit 版本只在底層訊息揭露 duplicate insert；保留跨版本降級。
            return error.localizedDescription.localizedCaseInsensitiveContains(
                "record to insert already exists"
            )
        }
    }

    /// 停止分享會立刻把雲端記錄標成停用；其他家人的下一次刷新會移除該即時圈。
    func stopLiveLocationSharing(context: ModelContext) async {
        let localCircles = (try? context.fetch(FetchDescriptor<LocalLifeCircle>())) ?? []
        for circle in localCircles where circle.kind == .live && circle.member?.isCurrentUser == true {
            context.delete(circle)
        }
        context.saveReporting()
        await EventPipeline.refresh(context: context)

        guard state != .noAccount else {
            lastPublishedLocation = nil
            lastPublishedAt = nil
            lastPublishedRadius = nil
            liveLocationError = nil
            return
        }

        do {
            let (db, rootID) = try await resolveDatabaseAndRoot()
            let recordID = CKRecord.ID(recordName: "live-\(participantID)", zoneID: rootID.zoneID)
            do {
                let record = try await db.record(for: recordID)
                record[FamilyLiveLocation.Field.isSharing] = false
                record[FamilyLiveLocation.Field.updatedAt] = Date.now
                _ = try await db.save(record)
            } catch let error as CKError where error.code == .unknownItem {
                // 從未成功上傳過，直接清本機狀態即可。
            }
            lastPublishedLocation = nil
            lastPublishedAt = nil
            lastPublishedRadius = nil
            liveLocationError = nil
            await fetchLiveLocations(context: context)
        } catch {
            liveLocationError = "停止分享失敗：\(error.localizedDescription)"
            AppLog.cloud.error("停止即時位置分享失敗：\(error.localizedDescription)")
        }
    }

    /// 讀取 private/shared zone 的位置記錄，並把每人最新位置投影成本機 SwiftData 即時圈，
    /// 讓既有警報比對、地圖與摘要不必各自維護第二套圈資料。
    func fetchLiveLocations(context: ModelContext) async {
        guard state != .noAccount else { return }

        var collected: [FamilyLiveLocation] = []
        var completedQuery = false

        // 自己的 record name 由 participantID 決定，可直接 fetch，避免剛寫入時受查詢索引
        // 傳播延遲影響 UI；其他家人的未知 record IDs 仍由 zone query 取得。
        do {
            let (ownDB, rootID) = try await resolveDatabaseAndRoot()
            let ownRecordID = CKRecord.ID(
                recordName: "live-\(participantID)",
                zoneID: rootID.zoneID
            )
            let ownRecord = try await ownDB.record(for: ownRecordID)
            if let ownLocation = Self.liveLocation(from: ownRecord) {
                collected.append(ownLocation)
            }
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            // 尚未成功分享過，屬正常。
        } catch {
            AppLog.cloud.error("直接讀取自己的即時位置失敗：\(error.localizedDescription)")
        }

        let privateDB = container.privateCloudDatabase
        do {
            collected += try await fetchLiveLocations(
                from: privateDB,
                zoneID: zoneID
            )
            completedQuery = true
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            // 尚未建立家庭圈屬正常。
        } catch {
            AppLog.cloud.error("讀取私人即時位置失敗：\(error.localizedDescription)")
        }

        let sharedDB = container.sharedCloudDatabase
        do {
            let zones = try await sharedDB.allRecordZones().filter { $0.zoneID.zoneName == Self.zoneName }
            for zone in zones {
                collected += try await fetchLiveLocations(
                    from: sharedDB,
                    zoneID: zone.zoneID
                )
                completedQuery = true
            }
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            // 尚未加入別人的家庭圈屬正常。
        } catch {
            AppLog.cloud.error("讀取共享即時位置失敗：\(error.localizedDescription)")
        }

        var newestByParticipant: [String: FamilyLiveLocation] = [:]
        for location in collected {
            if let kept = newestByParticipant[location.participantID],
               kept.updatedAt >= location.updatedAt { continue }
            newestByParticipant[location.participantID] = location
        }
        liveLocations = newestByParticipant.values.sorted { $0.displayName < $1.displayName }

        guard completedQuery else { return }
        let changed = applyLiveLocationSnapshots(liveLocations, context: context)
        if changed {
            context.saveReporting()
            await EventPipeline.refresh(context: context)
        }
    }

    private func fetchLiveLocations(
        from db: CKDatabase,
        zoneID: CKRecordZone.ID
    ) async throws -> [FamilyLiveLocation] {
        let query = CKQuery(
            recordType: FamilyLiveLocation.Field.recordType,
            // TRUEPREDICATE 會讓 CloudKit 轉查 system field `recordName`，若 Dashboard
            // 未把它標成 Queryable 就回 CKError 12。所有合法記錄必有 participantID，
            // 以必填欄位查全表可避開 system-field index 依賴。
            predicate: NSPredicate(
                format: "%K != %@",
                FamilyLiveLocation.Field.participantID,
                ""
            )
        )
        let (results, _) = try await db.records(matching: query, inZoneWith: zoneID)
        var parsed: [FamilyLiveLocation] = []
        for (_, result) in results {
            switch result {
            case .success(let record):
                if let location = Self.liveLocation(from: record) {
                    parsed.append(location)
                }
            case .failure:
                break
            }
        }
        return parsed
    }

    private func applyLiveLocationSnapshots(
        _ locations: [FamilyLiveLocation],
        context: ModelContext
    ) -> Bool {
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
            } else if location.participantID == participantID,
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
            } else if location.participantID == participantID,
                      let ownLive = member.lifeCircles.first(where: \.isFollowMe) {
                circle = ownLive
                circle.sharedLocationID = location.id
            } else {
                circle = LocalLifeCircle(
                    circleKey: "shared-\(location.id)",
                    name: location.participantID == participantID
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
            let isOwnLocation = location.participantID == participantID
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

    /// 送出一則安否回報。寫入時掛在家庭圈根記錄下（parent），確保納入分享範圍。
    /// - Parameters:
    ///   - latitude/longitude/placeName: 回報者「自願附上」的一次性位置（nil＝沒附）。
    ///     由呼叫端在回報當下取得並反向地理編碼，這裡只負責寫入。
    func postPing(
        senderName: String,
        status: SafetyStatus,
        note: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        placeName: String? = nil
    ) async {
        do {
            let (db, rootID) = try await resolveDatabaseAndRoot()
            let record = CKRecord(
                recordType: SafetyPing.Field.recordType,
                recordID: CKRecord.ID(recordName: "ping-\(UUID().uuidString)", zoneID: rootID.zoneID)
            )
            record[SafetyPing.Field.senderName] = senderName
            record[SafetyPing.Field.status] = status.rawValue
            record[SafetyPing.Field.note] = note
            record[SafetyPing.Field.createdAt] = Date.now
            record[SafetyPing.Field.readBy] = [String]()
            if let latitude, let longitude {
                record[SafetyPing.Field.latitude] = latitude
                record[SafetyPing.Field.longitude] = longitude
                record[SafetyPing.Field.placeName] = placeName ?? ""
            }
            record.setParent(CKRecord.ID(recordName: Self.rootRecordName, zoneID: rootID.zoneID))
            _ = try await db.save(record)
            await fetchPings()
        } catch {
            AppLog.cloud.error("送出安否回報失敗：\(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
    }

    /// 讀取家庭圈所有安否回報（同時查 private 與 shared database，涵蓋擁有者與成員兩端）
    func fetchPings() async {
        var collected: [SafetyPing] = []
        do {
            collected += try await fetchPings(
                from: container.privateCloudDatabase,
                zoneID: zoneID
            )
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            // 尚未建立家庭圈。
        } catch {
            AppLog.cloud.error("讀取私人安否回報失敗：\(error.localizedDescription)")
        }

        let sharedDB = container.sharedCloudDatabase
        do {
            let zones = try await sharedDB.allRecordZones().filter { $0.zoneID.zoneName == Self.zoneName }
            for zone in zones {
                collected += try await fetchPings(from: sharedDB, zoneID: zone.zoneID)
            }
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            // 尚未加入家庭分享。
        } catch {
            AppLog.cloud.error("讀取共享安否回報失敗：\(error.localizedDescription)")
        }
        pings = collected.sorted { $0.createdAt > $1.createdAt }
        await notifyIncomingPings(pings)
    }

    /// 家人回報通知：抓到「別人新送出」的安否回報時發本機通知——
    /// 「已回報平安」讓你放心、「尚未脫離危險／需要協助」提醒你持續關注。
    /// 已看過的回報 ID 存本機（上限 300）；首次同步只登記不通知，避免剛加入家庭圈就被歷史回報洗版。
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
            // 自己的回報不用通知自己
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
            // 「請回報平安」的請求與「尚未脫離危險」的回報都屬於危險溝通，用時效性通知
            let urgent = ping.status != .safe
            await NotificationScheduler.scheduleAlert(
                title: title, body: body, id: "ping-\(ping.id)",
                timeSensitive: urgent
            )
        }

        if seenList.count > 300 { seenList.removeFirst(seenList.count - 300) }
        defaults.set(seenList, forKey: seenKey)
    }

    private func fetchPings(
        from db: CKDatabase,
        zoneID: CKRecordZone.ID
    ) async throws -> [SafetyPing] {
        let query = CKQuery(
            recordType: SafetyPing.Field.recordType,
            predicate: NSPredicate(
                format: "%K > %@",
                SafetyPing.Field.createdAt,
                Date.distantPast as NSDate
            )
        )
        let (results, _) = try await db.records(matching: query, inZoneWith: zoneID)
        return results.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return Self.ping(from: record)
        }
    }

    /// 標記某則回報為「我已讀」（已讀回條）
    func markRead(pingID: String, readerName: String) async {
        do {
            // 成員端 shared zone 的 ownerName 是分享擁有者，不是 CKCurrentUserDefaultName。
            // 先解析實際 database/root，才能用正確 zoneID 找到回報。
            let (db, rootID) = try await resolveDatabaseAndRoot()
            let recordID = CKRecord.ID(recordName: pingID, zoneID: rootID.zoneID)
            // 多位家人可能同時已讀；遇 CloudKit 版本衝突時重新讀取合併，最多三次。
            for attempt in 0..<3 {
                let record = try await db.record(for: recordID)
                var readBy = (record[SafetyPing.Field.readBy] as? [String]) ?? []
                guard !readBy.contains(readerName) else { return }
                readBy.append(readerName)
                record[SafetyPing.Field.readBy] = readBy
                do {
                    _ = try await db.save(record)
                    await fetchPings()
                    return
                } catch let error as CKError where error.code == .serverRecordChanged && attempt < 2 {
                    continue
                }
            }
        } catch {
            AppLog.cloud.error("更新安否回報已讀狀態失敗：\(error.localizedDescription)")
        }
    }

    // MARK: - 退出／刪除家庭圈（帳號刪除流程用）

    /// 清掉這個帳號在 CloudKit 上的家庭圈足跡：
    /// 擁有者＝刪整個自訂 zone（分享與所有回報一併消失）；
    /// 成員＝刪 shared database 裡的 zone（等於退出分享）。
    /// 兩邊都是「有就刪、沒有就算了」，錯誤記 log 不中斷——刪除流程不能卡在雲端清理上。
    func leaveFamily() async {
        do {
            try await container.privateCloudDatabase.deleteRecordZone(withID: zoneID)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            // 本來就沒建過家庭圈，屬正常
        } catch {
            AppLog.cloud.error("刪除家庭圈 zone 失敗：\(error.localizedDescription)")
        }
        do {
            let sharedDB = container.sharedCloudDatabase
            for zone in try await sharedDB.allRecordZones() where zone.zoneID.zoneName == Self.zoneName {
                try await sharedDB.deleteRecordZone(withID: zone.zoneID)
            }
        } catch {
            AppLog.cloud.error("退出共享家庭圈失敗：\(error.localizedDescription)")
        }
        pings = []
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: SettingsKeys.activeFamilyZoneName)
        defaults.removeObject(forKey: SettingsKeys.activeFamilyOwnerName)
        await refreshAccountStatus()
    }

    private func resolveDatabaseAndRoot(
        createIfNeeded: Bool = false
    ) async throws -> (CKDatabase, CKRecord.ID) {
        // 接受邀請的成員必須優先使用剛加入的 shared zone。否則這台裝置若曾建立過自己的
        // private 家庭圈，下面的 private root 會把定位與安否回報送進錯誤的圈。
        let sharedDB = container.sharedCloudDatabase
        if let selectedSharedZoneID {
            let zones = try await sharedDB.allRecordZones()
            if let selectedZone = zones.first(where: { $0.zoneID == selectedSharedZoneID }) {
                return (
                    sharedDB,
                    CKRecord.ID(recordName: Self.rootRecordName, zoneID: selectedZone.zoneID)
                )
            }
            // CloudKit 剛接受分享時可能仍在同步 zone；不要降級寫入另一個 private 家庭圈。
            throw CKError(.zoneNotFound)
        }

        // 擁有者：private database 有根記錄；沒有 private root 的舊版成員：尋找 shared database。
        let privateDB = container.privateCloudDatabase
        let rootID = CKRecord.ID(recordName: Self.rootRecordName, zoneID: zoneID)
        if (try? await privateDB.record(for: rootID)) != nil {
            return (privateDB, rootID)
        }
        let zones = try await sharedDB.allRecordZones()
        if let sharedZone = zones.first(where: { $0.zoneID.zoneName == Self.zoneName }) {
            let defaults = UserDefaults.standard
            defaults.set(sharedZone.zoneID.zoneName, forKey: SettingsKeys.activeFamilyZoneName)
            defaults.set(sharedZone.zoneID.ownerName, forKey: SettingsKeys.activeFamilyOwnerName)
            return (sharedDB, CKRecord.ID(recordName: Self.rootRecordName, zoneID: sharedZone.zoneID))
        }
        if createIfNeeded {
            let root = try await ensureFamilyRoot()
            return (privateDB, root.recordID)
        }
        throw CKError(.zoneNotFound)
    }

    private static func liveLocation(from record: CKRecord) -> FamilyLiveLocation? {
        guard
            let participantID = record[FamilyLiveLocation.Field.participantID] as? String,
            let displayName = record[FamilyLiveLocation.Field.displayName] as? String,
            let latitude = (record[FamilyLiveLocation.Field.latitude] as? NSNumber)?.doubleValue,
            let longitude = (record[FamilyLiveLocation.Field.longitude] as? NSNumber)?.doubleValue,
            let updatedAt = record[FamilyLiveLocation.Field.updatedAt] as? Date
        else { return nil }

        return FamilyLiveLocation(
            id: record.recordID.recordName,
            participantID: participantID,
            displayName: displayName,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: (record[FamilyLiveLocation.Field.radiusMeters] as? NSNumber)?.intValue ?? 1_000,
            district: record[FamilyLiveLocation.Field.district] as? String ?? Districts.unspecified,
            updatedAt: updatedAt,
            isSharing: (record[FamilyLiveLocation.Field.isSharing] as? NSNumber)?.boolValue ?? false
        )
    }

    private static func ping(from record: CKRecord) -> SafetyPing? {
        guard
            let senderName = record[SafetyPing.Field.senderName] as? String,
            let statusRaw = record[SafetyPing.Field.status] as? String,
            let status = SafetyStatus(rawValue: statusRaw),
            let createdAt = record[SafetyPing.Field.createdAt] as? Date
        else { return nil }
        return SafetyPing(
            id: record.recordID.recordName,
            senderName: senderName,
            status: status,
            note: record[SafetyPing.Field.note] as? String ?? "",
            createdAt: createdAt,
            readBy: record[SafetyPing.Field.readBy] as? [String] ?? [],
            latitude: record[SafetyPing.Field.latitude] as? Double,
            longitude: record[SafetyPing.Field.longitude] as? Double,
            placeName: (record[SafetyPing.Field.placeName] as? String).flatMap { $0.isEmpty ? nil : $0 }
        )
    }
}

private enum FamilyInvitationError: LocalizedError {
    case onlyOwnerCanInvite
    case savedRecordWasNotShare
    case oneTimeURLUnavailable

    var errorDescription: String? {
        switch self {
        case .onlyOwnerCanInvite:
            return "只有家庭圈建立者可以邀請新成員，請由圈主的手機產生邀請。"
        case .savedRecordWasNotShare:
            return "CloudKit 沒有回傳有效的家庭分享，請稍後再試。"
        case .oneTimeURLUnavailable:
            return "私人邀請連結尚未就緒，請稍後再試或改用訊息邀請。"
        }
    }
}
