import Foundation

/// 一鍵求救的求救狀態快照。純 struct（不是 SwiftData @Model），比照 [FamilyLiveLocation] /
/// [SafetyPing] 的既有模式——Firestore 文件的 Swift 投影，不進 SwiftData schema，
/// 避免 SwiftData migration 風險（本專案曾因新增 @Model 欄位、覆蓋安裝時舊資料讀新 schema
/// 而真的炸過，這條紅線不能再踩）。
///
/// 「單文件覆寫」設計：每人在 Firestore 只有一份 `families/{familyId}/sos/{uid}` 文件，
/// 持續按讚「求救中」只會覆寫這份文件（更新位置、updatedAt），不是流水帳式累加，
/// 這樣家人讀到的永遠是「這個人現在的求救狀態」而不必自己在一堆歷史紀錄裡找最新一筆。
struct SOSAlert: Identifiable, Equatable {
    let id: String  // 用 participantID（＝文件 ID＝成員 uid）
    let participantID: String
    let displayName: String
    let latitude: Double
    let longitude: Double
    /// 這一次求救「開始」的時間：同一次求救持續更新位置不會改變這個值（見
    /// FirestoreFamilyBackend.publishSOS 的合併邏輯），只有「解除後重新發出」才會前進。
    let startedAt: Date
    let updatedAt: Date
    let isActive: Bool

    /// 8 小時未解除視為過期——即使 sender 的 App 沒機會呼叫解除（例如被強制關閉），
    /// 家人讀到這筆時仍要能判斷「這其實已經過期了」，不完全依賴 isActive 欄位
    /// （比照 [FamilyLiveLocation.isFresh] 的既有防禦模式）。呼叫端（FamilySyncService.
    /// fetchActiveSOSAlerts）用這個屬性篩選要不要顯示，不是自己重新判斷一次過期邏輯。
    var isStillUrgent: Bool {
        isActive && updatedAt > Date.now.addingTimeInterval(-8 * 3600)
    }

    /// 沒有座標的標記：activateSOS 拿不到 GPS 時仍要能發出求救狀態本身，
    /// 這種情況下 latitude/longitude 寫入 0,0——UI（家人端「在地圖開啟」）要用這個判斷
    /// 是否真的有位置可以導航，避免把 0,0（幾內亞灣外海）當成真實座標開地圖。
    var hasLocation: Bool { latitude != 0 || longitude != 0 }

    enum Field {
        static let recordType = "SOSAlert"
        static let participantID = "participantID"
        static let displayName = "displayName"
        static let latitude = "latitude"
        static let longitude = "longitude"
        static let startedAt = "startedAt"
        static let updatedAt = "updatedAt"
        static let isActive = "isActive"
    }
}
