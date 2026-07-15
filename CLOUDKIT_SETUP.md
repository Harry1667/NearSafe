# CloudKit + CKShare 設定與測試邊界（階段 3）

> 家庭連結（家人邀請 #1、安否回報 #2）走 CloudKit + CKShare。
> 本檔說明：真實運作需要哪些設定、哪些已驗證、哪些只能在實機驗證。

## 架構

- **擁有者**在自己的 iCloud private database 建一個自訂 zone（`FamilyCircleZone`），內含一筆「家庭圈」根記錄。
- 對根記錄建立 **CKShare**，透過 `UICloudSharingController` 產生邀請連結／訊息／AirDrop（涵蓋未安裝 App 家人的 fallback）。
- **安否回報**（`SafetyPing`）以根記錄為 parent 寫入同一 zone，因此自動納入分享範圍。
- **家人**接受邀請後，用 shared database 存取同一 zone；雙方讀寫同一批 `SafetyPing`。
- 已讀回條：檢視他人回報時，把自己的名字加入該 ping 的 `readBy` 欄位。

程式進入點：`Services/FamilySyncService.swift`、`Services/ShareAcceptance.swift`、`Views/Family/SafetyCheckInView.swift`、`Views/Family/CloudSharingSheet.swift`。

## 上線前必做的設定（目前尚未完成，需要付費開發者帳號）

1. **建立 CloudKit container**：在 Apple Developer 後台或 Xcode Signing & Capabilities 加入 iCloud → CloudKit，容器 ID 使用 `iCloud.com.gomiigo.CamMenuApp.HavenCircle`（已寫在 `HavenCircle.entitlements`）。
2. **在 CloudKit Dashboard 定義 schema**：`SafetyPing` record type，欄位 `senderName`(String)、`status`(String)、`note`(String)、`createdAt`(Date/Time)、`readBy`(String List)；`FamilyCircle` root record type。首次以程式寫入時 development 環境會自動建立，之後需 Deploy to Production。
3. **推播能力**：`aps-environment` 已在 entitlements。CKShare 的變更通知需要 APNs；上線時確認 container 已啟用推播。
4. **佈建描述檔**：自動簽章需登入的 Apple ID 對此 container 有權限；用實機以 Xcode 直接 Run 才會真正授予 entitlement。

## 已驗證（模擬器）

- 專案含 CloudKit entitlement 可正常 build 與安裝。
- 無 iCloud 帳號時，`accountStatus()` 回傳 `noAccount`，安否分頁顯示「尚未登入 iCloud」引導、邀請按鈕停用，**App 不崩潰**（截圖存證）。
- SwiftData 本機 store 明確設 `cloudKitDatabase: .none`，與 CKShare 家庭同步互不干擾（修掉了 entitlement 存在時 SwiftData 誤試 CloudKit 鏡像、因 `@Attribute(.unique)` 建立失敗的問題）。

## 只能在實機驗證（需兩台不同 iCloud 帳號的裝置）

以下路徑在模擬器或單一帳號下無法端到端測試，需列入實機測試清單：

- 邀請流程：擁有者 `makeShare()` → `UICloudSharingController` → 家人點連結 → `windowScene(_:userDidAcceptCloudKitShareWith:)` 接受。
- 跨裝置回報：家人 A 送安否 → 家人 B 讀到 → B 的已讀回條回到 A。
- **已知待驗證的疑點**：`FamilySyncService.markRead` 在成員端用 `zoneID`（以目前使用者為 owner）組 recordID，但成員存取的是「擁有者擁有」的 shared zone，owner 名稱不同。實機測試時需改用該 ping 記錄實際所在的 zoneID（從 `fetchPings` 保留原始 `CKRecord.ID`）。此點已知，留待實機修正，不假裝已正確。

## 測試輔助（DEBUG only）

- `--start-tab-safety`：App 直接開在安否分頁（截圖驗證用）。
- `--smoke-onboard` / `--smoke-drill` / `--smoke-cloud`：見 `Support/SmokeTest.swift`。
  注意 `--smoke-cloud` 的 async 檢查在 `simctl launch`（背景）下不會執行，需前景（開 Simulator.app）才會跑。
