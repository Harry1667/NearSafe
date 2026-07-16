import Foundation
import CloudKit
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

    private let container: CKContainer
    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    init() {
        container = CKContainer(identifier: Self.containerID)
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
            state = .sharing
            await fetchPings()
        } catch {
            AppLog.cloud.error("接受家庭邀請失敗：\(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - 安否回報

    /// 送出一則安否回報。寫入時掛在家庭圈根記錄下（parent），確保納入分享範圍。
    func postPing(senderName: String, status: SafetyStatus, note: String = "") async {
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
        for db in [container.privateCloudDatabase, container.sharedCloudDatabase] {
            do {
                collected += try await fetchPings(from: db)
            } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
                continue  // 該 database 尚無此 zone，屬正常情形
            } catch {
                AppLog.cloud.error("讀取安否回報失敗：\(error.localizedDescription)")
            }
        }
        pings = collected.sorted { $0.createdAt > $1.createdAt }
    }

    private func fetchPings(from db: CKDatabase) async throws -> [SafetyPing] {
        let query = CKQuery(
            recordType: SafetyPing.Field.recordType,
            predicate: NSPredicate(value: true)
        )
        query.sortDescriptors = [NSSortDescriptor(key: SafetyPing.Field.createdAt, ascending: false)]
        let (results, _) = try await db.records(matching: query)
        return results.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return Self.ping(from: record)
        }
    }

    /// 標記某則回報為「我已讀」（已讀回條）
    func markRead(pingID: String, readerName: String) async {
        for db in [container.privateCloudDatabase, container.sharedCloudDatabase] {
            do {
                let recordID = CKRecord.ID(recordName: pingID, zoneID: zoneID)
                let record = try await db.record(for: recordID)
                var readBy = (record[SafetyPing.Field.readBy] as? [String]) ?? []
                guard !readBy.contains(readerName) else { return }
                readBy.append(readerName)
                record[SafetyPing.Field.readBy] = readBy
                _ = try await db.save(record)
                await fetchPings()
                return
            } catch {
                continue  // 換另一個 database 試
            }
        }
    }

    private func resolveDatabaseAndRoot() async throws -> (CKDatabase, CKRecord.ID) {
        // 擁有者：private database 有根記錄；成員：shared database
        let privateDB = container.privateCloudDatabase
        let rootID = CKRecord.ID(recordName: Self.rootRecordName, zoneID: zoneID)
        if (try? await privateDB.record(for: rootID)) != nil {
            return (privateDB, rootID)
        }
        // 成員端：在 shared database 找到分享進來的 zone
        let sharedDB = container.sharedCloudDatabase
        let zones = try await sharedDB.allRecordZones()
        guard let sharedZone = zones.first else {
            throw CKError(.zoneNotFound)
        }
        return (sharedDB, CKRecord.ID(recordName: Self.rootRecordName, zoneID: sharedZone.zoneID))
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
            readBy: record[SafetyPing.Field.readBy] as? [String] ?? []
        )
    }
}
