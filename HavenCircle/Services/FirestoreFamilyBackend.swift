import Foundation
import FirebaseFirestore

// MARK: - Firestore 家庭圈資料模型（純 struct，Firestore 文件的 Swift 投影）

/// 家庭圈根文件（Firestore: families/{familyId}）
struct FamilyCircleDoc: Identifiable, Equatable {
    let id: String            // = familyId（Firestore 文件 ID）
    var name: String
    var ownerUid: String
    var inviteCode: String    // 8 碼邀請碼（取代 CKShare 連結）
    var memberUids: [String]  // 冗餘存成員 uid 陣列，供 Security Rules 快速判斷成員身份
    var createdAt: Date
}

/// 家庭成員文件（Firestore: families/{familyId}/members/{uid}）
struct FamilyMemberDoc: Identifiable, Equatable {
    let id: String            // = 成員 uid
    var displayName: String
    var role: String          // "owner" / "member"
    var joinedAt: Date

    var isOwner: Bool { role == "owner" }
}

/// 邀請碼預覽（C1）：加入前先讓使用者確認「要加入誰的家庭圈」，不加入就不寫任何資料。
/// 舊邀請碼（建立於本欄位補上之前）沒有 familyName/ownerName，對應欄位為 nil，
/// 呼叫端要處理「兩者皆 nil」的降級文案。
struct InvitePreview: Equatable {
    let familyId: String
    let familyName: String?
    let ownerName: String?
}

// MARK: - 錯誤

enum FamilyBackendError: LocalizedError {
    case notSignedIn
    case invalidInviteCode
    case familyNotFound

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "請先用 Apple 帳號登入，才能建立或加入家庭圈。"
        case .invalidInviteCode:
            return "邀請碼不正確或已失效，請向家人確認後重新輸入。"
        case .familyNotFound:
            return "找不到對應的家庭圈，可能已被解散。"
        }
    }
}

// MARK: - Firestore 家庭圈後端

/// 家庭圈的 Firestore 資料層（無狀態的操作集合）。
///
/// 身份一律用呼叫端傳入的 Firebase uid（來自 [AuthService]），這一層不自己碰 AuthService，
/// 方便測試與非 MainActor 呼叫。所有讀寫都透過 [FirestoreConfig.store] 指向具名資料庫 default。
enum FirestoreFamilyBackend {

    /// 建立家庭圈：產生 familyId 與 8 碼邀請碼，寫入根文件、擁有者成員、邀請碼索引。
    /// 回傳建立好的家庭圈文件。
    static func createFamily(
        ownerUid: String,
        ownerDisplayName: String,
        familyName: String
    ) async throws -> FamilyCircleDoc {
        let db = FirestoreConfig.store()
        let familyRef = db.collection(FirestoreConfig.Path.families).document()
        let code = generateInviteCode()
        let now = Date()

        try await familyRef.setData([
            "name": familyName,
            "ownerUid": ownerUid,
            "inviteCode": code,
            "memberUids": [ownerUid],
            "createdAt": Timestamp(date: now)
        ])
        try await familyRef.collection(FirestoreConfig.Path.members).document(ownerUid).setData([
            "displayName": ownerDisplayName,
            "role": "owner",
            "joinedAt": Timestamp(date: now)
        ])
        // 邀請碼索引：家人輸入碼 → 查到 familyId。獨立 collection 讓「用碼查家庭」不必掃全表。
        // familyName/ownerName（C1）額外寫入：讓對方輸碼後能在加入前看到「要加入誰的家庭圈」，
        // 不必先加入才知道加錯人。
        try await db.collection(FirestoreConfig.Path.inviteCodes).document(code).setData([
            "familyId": familyRef.documentID,
            "createdAt": Timestamp(date: now),
            "familyName": familyName,
            "ownerName": ownerDisplayName
        ])

        return FamilyCircleDoc(
            id: familyRef.documentID,
            name: familyName,
            ownerUid: ownerUid,
            inviteCode: code,
            memberUids: [ownerUid],
            createdAt: now
        )
    }

    /// 用邀請碼加入家庭圈。回傳加入的 familyId。
    static func joinFamily(
        code: String,
        uid: String,
        displayName: String
    ) async throws -> String {
        let db = FirestoreConfig.store()
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        let codeDoc = try await db.collection(FirestoreConfig.Path.inviteCodes).document(normalized).getDocument()
        guard codeDoc.exists, let familyId = codeDoc.data()?["familyId"] as? String else {
            throw FamilyBackendError.invalidInviteCode
        }
        let familyRef = db.collection(FirestoreConfig.Path.families).document(familyId)
        // 併發安全：arrayUnion 不會重複加入同一個 uid。
        do {
            try await familyRef.updateData([
                "memberUids": FieldValue.arrayUnion([uid])
            ])
        } catch let error as NSError where error.domain == FirestoreErrorDomain
            && error.code == FirestoreErrorCode.permissionDenied.rawValue {
            // 邀請碼合法（inviteCodes 讀取通過）卻在寫入 memberUids 時被拒——rules 對這個更新
            // 分支只檢查 `resource.data`（文件現有內容），家庭圈一旦被圈主解散
            // （[deleteFamily]）根文件不存在，`resource.data` 求值出錯，一律回 permission-denied。
            // 在這個呼叫路徑下，這幾乎唯一可能的成因就是「家庭圈已解散」，轉譯成更精確的錯誤。
            throw FamilyBackendError.familyNotFound
        }
        try await familyRef.collection(FirestoreConfig.Path.members).document(uid).setData([
            "displayName": displayName,
            "role": "member",
            "joinedAt": Timestamp(date: Date())
        ], merge: true)
        return familyId
    }

    /// 離開家庭圈：從 memberUids 移除自己，並刪掉自己的成員與位置文件。
    static func leaveFamily(familyId: String, uid: String) async throws {
        let db = FirestoreConfig.store()
        let familyRef = db.collection(FirestoreConfig.Path.families).document(familyId)
        try await familyRef.updateData(["memberUids": FieldValue.arrayRemove([uid])])
        try? await familyRef.collection(FirestoreConfig.Path.members).document(uid).delete()
        try? await familyRef.collection(FirestoreConfig.Path.locations).document(uid).delete()
    }

    /// 解散家庭圈：只有圈主能呼叫（對照 firestore.rules `families/{familyId}` 的
    /// `allow delete: if ... resource.data.ownerUid == request.auth.uid`）。
    ///
    /// 刪根文件前先盡力清掉「自己」的成員／位置子文件（rules 允許本人寫入自己的
    /// members/{uid}、locations/{uid}，寫入含刪除）。
    ///
    /// 已知限制（刻意不處理，留註解說明）：
    /// - 其他成員的 members/{uid}、locations/{uid} 子文件不會被清掉——rules 只允許
    ///   本人寫入自己的子文件，圈主沒有權限代刪；根文件一旦刪除，這些子文件會變成
    ///   沒有母文件的孤兒資料，但因為所有讀取路徑都先查根文件是否存在，不會再被
    ///   任何功能讀到。
    /// - 所有 pings/{pingId} 一律禁止刪除（rules `allow delete: if false`），解散後
    ///   同樣變成孤兒資料，無法清除。
    /// - inviteCodes/{code} 索引禁止 update/delete，解散後這組碼會永久指向一個已刪除
    ///   的 familyId。[lookupInvite] 本身讀不到家庭根文件（非成員讀取一律 permission-denied，
    ///   無法藉此判斷是否存在），因此「優雅失敗」改在 [joinFamily] 實際寫入 memberUids 時
    ///   偵測——那次寫入被拒時會轉譯成 [FamilyBackendError.familyNotFound] 讓 UI 優雅顯示，
    ///   不會讓使用者誤以為能加入一個早就解散的家庭圈。
    static func deleteFamily(familyId: String, uid: String) async throws {
        let db = FirestoreConfig.store()
        let familyRef = db.collection(FirestoreConfig.Path.families).document(familyId)
        try? await familyRef.collection(FirestoreConfig.Path.members).document(uid).delete()
        try? await familyRef.collection(FirestoreConfig.Path.locations).document(uid).delete()
        try await familyRef.delete()
    }

    /// 讀取家庭圈根文件。
    static func fetchFamily(familyId: String) async throws -> FamilyCircleDoc {
        let db = FirestoreConfig.store()
        let doc = try await db.collection(FirestoreConfig.Path.families).document(familyId).getDocument()
        guard doc.exists, let family = family(from: doc) else {
            throw FamilyBackendError.familyNotFound
        }
        return family
    }

    /// 讀取家庭圈所有成員。
    static func fetchMembers(familyId: String) async throws -> [FamilyMemberDoc] {
        let db = FirestoreConfig.store()
        let snapshot = try await db.collection(FirestoreConfig.Path.families)
            .document(familyId)
            .collection(FirestoreConfig.Path.members)
            .getDocuments()
        return snapshot.documents.compactMap(member(from:))
            .sorted { $0.joinedAt < $1.joinedAt }
    }

    /// 找出這個 uid 目前所屬的家庭圈（用 memberUids 陣列查詢）。
    /// 回傳第一個符合的家庭圈；沒有則 nil。用於換裝置或本機沒存 familyId 時的還原。
    static func findFamily(forUid uid: String) async throws -> FamilyCircleDoc? {
        let db = FirestoreConfig.store()
        let snapshot = try await db.collection(FirestoreConfig.Path.families)
            .whereField("memberUids", arrayContains: uid)
            .limit(to: 1)
            .getDocuments()
        return snapshot.documents.first.flatMap(family(from:))
    }

    // MARK: - 邀請碼

    /// 邀請碼合法字元集：刻意排除易混淆字元（0/O、1/I、Z/2 等）。
    /// 抽成共用常數讓輸入端（JoinByCodeView）能驗證字元合法性，不只是驗長度。
    static let inviteCodeCharset = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    /// 產生 8 碼邀請碼。
    static func generateInviteCode() -> String {
        let charset = Array(inviteCodeCharset)
        return String((0..<8).map { _ in charset.randomElement()! })
    }

    /// 邀請碼格式是否合法（8 碼、全落在合法字元集）。純本機檢查，不打網路，
    /// 讓 UI 能在送出查詢前先擋掉明顯打錯的輸入，給出「格式不對」這種更精準的錯誤文案。
    static func isValidInviteCodeFormat(_ code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count == 8 else { return false }
        let allowed = Set(inviteCodeCharset)
        return trimmed.allSatisfy(allowed.contains)
    }

    /// 加入前確認（C1）：只讀 inviteCodes 索引，不寫入任何資料、不會讓人「不小心就加入了」。
    /// 舊邀請碼沒有 familyName/ownerName 欄位時，對應回傳 nil，交由呼叫端決定降級文案。
    ///
    /// ⚠️ 這裡刻意不多讀一次 `families/{familyId}` 來確認根文件是否還在：
    /// rules 的 `families/{familyId}` 讀取要求 `isMember(familyId)`，而 `isMember` 內部又對
    /// 同一份文件做一次 `get()`——非成員（正是這裡的呼叫情境：還沒加入就要先看預覽）讀取任何
    /// families 文件一律 `permission-denied`，不論該文件是否存在，無法用來判斷「已解散」。
    /// 因此「家庭圈已被圈主解散」這個情況，實際能可靠偵測到的時機是 [joinFamily] 真正嘗試
    /// 寫入 memberUids 的那一刻（見那裡的錯誤轉換），這裡維持只讀 inviteCodes 索引本身。
    static func lookupInvite(code: String) async throws -> InvitePreview {
        let db = FirestoreConfig.store()
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let codeDoc = try await db.collection(FirestoreConfig.Path.inviteCodes).document(normalized).getDocument()
        guard codeDoc.exists, let data = codeDoc.data(), let familyId = data["familyId"] as? String else {
            throw FamilyBackendError.invalidInviteCode
        }
        return InvitePreview(
            familyId: familyId,
            familyName: data["familyName"] as? String,
            ownerName: data["ownerName"] as? String
        )
    }

    // MARK: - 即時位置（同意式：只有開啟分享的人才會被寫入 locations 子集合）

    /// 寫入／更新這個成員的即時位置。merge 讓重複更新只改動座標欄位。
    static func publishLocation(
        familyId: String,
        uid: String,
        displayName: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Int,
        district: String
    ) async throws {
        let db = FirestoreConfig.store()
        try await db.collection(FirestoreConfig.Path.families).document(familyId)
            .collection(FirestoreConfig.Path.locations).document(uid).setData([
                "displayName": displayName,
                "latitude": latitude,
                "longitude": longitude,
                "radiusMeters": radiusMeters,
                "district": district,
                "updatedAt": Timestamp(date: Date()),
                "isSharing": true
            ], merge: true)
    }

    /// 停止分享：標記 isSharing=false（家人下次刷新會移除此人的即時圈）。
    static func stopLocation(familyId: String, uid: String) async throws {
        let db = FirestoreConfig.store()
        try await db.collection(FirestoreConfig.Path.families).document(familyId)
            .collection(FirestoreConfig.Path.locations).document(uid).setData([
                "isSharing": false,
                "updatedAt": Timestamp(date: Date())
            ], merge: true)
    }

    /// 讀取家庭圈所有成員的即時位置。
    static func fetchLocations(familyId: String) async throws -> [FamilyLiveLocation] {
        let db = FirestoreConfig.store()
        let snap = try await db.collection(FirestoreConfig.Path.families).document(familyId)
            .collection(FirestoreConfig.Path.locations).getDocuments()
        return snap.documents.compactMap(liveLocation(from:))
    }

    // MARK: - 安否回報

    @discardableResult
    static func postPing(
        familyId: String,
        senderUid: String,
        senderName: String,
        status: SafetyStatus,
        note: String,
        latitude: Double?,
        longitude: Double?,
        placeName: String?
    ) async throws -> String {
        let db = FirestoreConfig.store()
        let ref = db.collection(FirestoreConfig.Path.families).document(familyId)
            .collection(FirestoreConfig.Path.pings).document()
        var data: [String: Any] = [
            "senderUid": senderUid,
            "senderName": senderName,
            "status": status.rawValue,
            "note": note,
            "createdAt": Timestamp(date: Date()),
            "readBy": [String]()
        ]
        // 位置為回報者「自願附上」的一次性座標，nil＝沒附
        if let latitude, let longitude {
            data["latitude"] = latitude
            data["longitude"] = longitude
            data["placeName"] = placeName ?? ""
        }
        try await ref.setData(data)
        return ref.documentID
    }

    /// 讀取家庭圈所有安否回報（依時間新到舊；單欄排序不需複合索引）。
    static func fetchPings(familyId: String) async throws -> [SafetyPing] {
        let db = FirestoreConfig.store()
        let snap = try await db.collection(FirestoreConfig.Path.families).document(familyId)
            .collection(FirestoreConfig.Path.pings)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        return snap.documents.compactMap(ping(from:))
    }

    /// 標記某則回報為「某家人已讀」（已讀回條）。arrayUnion 天然去重。
    static func markPingRead(familyId: String, pingId: String, readerName: String) async throws {
        let db = FirestoreConfig.store()
        try await db.collection(FirestoreConfig.Path.families).document(familyId)
            .collection(FirestoreConfig.Path.pings).document(pingId).updateData([
                "readBy": FieldValue.arrayUnion([readerName])
            ])
    }

    // MARK: - 文件 → struct

    private static func family(from doc: DocumentSnapshot) -> FamilyCircleDoc? {
        guard let data = doc.data(),
              let name = data["name"] as? String,
              let ownerUid = data["ownerUid"] as? String,
              let inviteCode = data["inviteCode"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        else { return nil }
        return FamilyCircleDoc(
            id: doc.documentID,
            name: name,
            ownerUid: ownerUid,
            inviteCode: inviteCode,
            memberUids: data["memberUids"] as? [String] ?? [],
            createdAt: createdAt
        )
    }

    private static func member(from doc: QueryDocumentSnapshot) -> FamilyMemberDoc? {
        let data = doc.data()
        guard let displayName = data["displayName"] as? String,
              let role = data["role"] as? String,
              let joinedAt = (data["joinedAt"] as? Timestamp)?.dateValue()
        else { return nil }
        return FamilyMemberDoc(
            id: doc.documentID,
            displayName: displayName,
            role: role,
            joinedAt: joinedAt
        )
    }

    /// Firestore 位置文件 → FamilyLiveLocation（文件 ID = 成員 uid，同時當 participantID）
    private static func liveLocation(from doc: QueryDocumentSnapshot) -> FamilyLiveLocation? {
        let data = doc.data()
        guard let displayName = data["displayName"] as? String,
              let latitude = data["latitude"] as? Double,
              let longitude = data["longitude"] as? Double,
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        else { return nil }
        return FamilyLiveLocation(
            id: doc.documentID,
            participantID: doc.documentID,
            displayName: displayName,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: (data["radiusMeters"] as? Int) ?? 1_000,
            district: data["district"] as? String ?? Districts.unspecified,
            updatedAt: updatedAt,
            isSharing: data["isSharing"] as? Bool ?? false
        )
    }

    /// Firestore 回報文件 → SafetyPing
    private static func ping(from doc: QueryDocumentSnapshot) -> SafetyPing? {
        let data = doc.data()
        guard let senderName = data["senderName"] as? String,
              let statusRaw = data["status"] as? String,
              let status = SafetyStatus(rawValue: statusRaw),
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        else { return nil }
        return SafetyPing(
            id: doc.documentID,
            senderName: senderName,
            status: status,
            note: data["note"] as? String ?? "",
            createdAt: createdAt,
            readBy: data["readBy"] as? [String] ?? [],
            latitude: data["latitude"] as? Double,
            longitude: data["longitude"] as? Double,
            placeName: (data["placeName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        )
    }
}
