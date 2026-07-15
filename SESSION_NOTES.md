# SESSION_NOTES

## 2026-07-15

### 完成事項

**規劃**
- 產品功能缺口分析（10 項），寫入對話並整理成 `DEVELOPMENT_PLAN.md`（6 階段規劃）
- 後端決策定案：CloudKit + CKShare（使用者選定）

**階段 0–3 全部完成**（每階段一個 commit，均通過 xcodebuild 與模擬器驗證）
- 階段 0（`a72fad8`）：單檔原型拆為 Models/Views/Services/Support；修 try!、假暫停旗標、刪除索引 bug、alertTypes 改陣列
- 階段 1（`1e83eca`）：AlertPolicy 集中提醒決策（含「為何收到」理由）、事件狀態機＋解除通知、每日安全摘要、演練模式、資料時效標示、SmokeTest 冒煙掛鉤
- 階段 2（`2beb2e0`）：EventPipeline mock 資料管線（去重/可信度評分/生活圈比對，SwiftData 實測通過）、RegionAlert 行政區災害層、內嵌雙北緊急資源 JSON、HistoryView 區域回顧
- 階段 3（`b5aaf69`）：FamilySyncService（CloudKit 自訂 zone + CKShare）、SafetyCheckInView 安否回報＋已讀回條、CloudSharingSheet 邀請、share 接受的 scene delegate；修掉兩個根因 bug——SwiftData 誤試 CloudKit 鏡像（設 `cloudKitDatabase: .none`）、降級鏈漏刪 -wal/-shm

**介面優化（使用者逐項驗收）**
- 第一批（`5019271`）：修「需要注意」分類與標籤不符 bug、事件摘要補齊（歸屬＋相對時間）、地圖家人切換器、鏡頭 .automatic、暫停狀態可見性
- 第二批（`689cf7b`）：半版事件摘要（presentationDetents）、家人頁邀請捷徑（TabRouter）、Onboarding 地址搜尋＋行政區自動判斷
- 導航重整（`db391c8`）：分頁改〔提醒中心｜回顧｜安全地圖(置中/預設)｜家人｜設定〕、地圖全螢幕化（浮層＋底部橫向卡片）、圖層與過濾選單、家人＋安否合併為 FamilyHubView
- 提醒中心加回精簡地圖卡 EventsMiniMap（`afd4ab8`）
- View 層移除 os Logger 直接依賴（`73a8296`），根治 Xcode 索引誤報

### 未完成 / 已知問題

1. **CKShare 跨帳號流程未驗證**：需兩台不同 iCloud 帳號的實機＋已佈建 container。已知疑點：`FamilySyncService.markRead` 在成員端組 recordID 的 zone owner 可能不對（應改用 fetchPings 保留的原始 CKRecord.ID）。詳見 `CLOUDKIT_SETUP.md`
2. Xcode 編輯器可能殘留舊的 os import 誤報診斷（程式碼已根治），使用者端需 ⌘Q 重開 Xcode + ⌘B 清除
3. 階段 4（真實資料源：NCDR CAP / CWA / 消防開放資料＋APNs 推播）、階段 5（上線硬化）未開始
4. 生活圈只能新增不能編輯（原型限制，編輯＝刪除重建）

### 下次起點

- 優先：拿實機跑通階段 3 CloudKit 流程（照 `CLOUDKIT_SETUP.md` 設定），修 markRead zone 疑點
- 然後：階段 4 從 NCDR 災害示警 CAP 開放資料開始接（替換 MockWeatherBureauProvider）
- 使用者可能的 UI 後續：地圖底部卡片改可收合、迷你地圖改唯讀跳轉（都已口頭提過選項，等使用者反饋）

### 技術備忘（本 session 驗證過的環境事實）

- 專案用 Xcode 16+ 同步資料夾（PBXFileSystemSynchronizedRootGroup），新增檔案不用改 pbxproj
- Swift 6.2 預設 MainActor + MemberImportVisibility：用 os Logger 插值的檔案必須自己 `import os`（View 層改走 AppLog 包裝已免疫）
- 驗證流程：`xcodebuild -project HavenCircle.xcodeproj -scheme HavenCircle -destination 'platform=iOS Simulator,id=58EB62E3-88E2-4827-B286-95382DD94AD7' build`（iPhone 17 Pro / iOS 26.5 模擬器）
- 冒煙測試（DEBUG）：`xcrun simctl launch <udid> com.gomiigo.CamMenuApp.HavenCircle --smoke-onboard --smoke-drill --smoke-cloud --start-tab <0-4>`；注意 simctl 背景啟動時 async Task 不會跑，`--smoke-cloud` 需前景
- log 查詢：`log show --predicate 'subsystem == "com.gomiigo.CamMenuApp.HavenCircle"'`（.info 級別要加 --info）
- SwiftData 資料庫直查：模擬器 App 容器內 `default.store`（sqlite3 可讀，表名 ZLOCALSAFETYEVENT 等）
