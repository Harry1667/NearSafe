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

### 後端資料源規劃與官網上線（同日第二段工作）

**政府災害資料接取規劃**
- 撰寫 `GOVERNMENT_DATA_SOURCES.md`（已實際上網查證，非憑記憶）：
  - **NCDR 民生示警平台**為主幹——免申請、CAP 格式，一次涵蓋火災/地震/颱風/淹水等 43 項示警；即時火災走這裡的 `NFA_Fire`，不必接消防局
  - **CWA 中央氣象署開放資料**——需免費註冊拿授權碼，補充精細地震規模/颱風路徑
  - **消防局無即時火災 API**（只有網頁與年度統計，已查證確認）
  - **data.gov.tw**——抓避難所等靜態清單
  - **架構建議**：用現有 Oracle 機器當中間層（抓資料→解析→去重→存 JSON→發 APNs）；隱私設計＝App 只上傳「關心的行政區」不上傳住址；分兩步（先 pull 拿真資料、後加背景 APNs 推播）
  - 附斷網降級（離線橫幅）與通知去重（同區短時合併）的具體修改建議

**官網上線**
- `website/`（純靜態 HTML/CSS/JS）部署到 https://havencircle.looptw.com ，用 `001-deploy-docs` skill
- 站點/SSL/Nginx 在 aaPanel 已預建好，實際只需上傳檔案：rsync 上傳（Mac 內建 rsync 2.6.9 不支援 `--chown`，改上傳後 SSH `chown -R www:www`）
- **純靜態站不佔應用端口**，走 80/443；上傳後 `nginx -s reload` 才讓 443 生效（先 `nginx -t` 確認不影響其他 30+ 站）
- 驗證：HTTPS 回 HTTP/2 200、HTTP 301 轉址、三張截圖與 CSS/JS 全 200

### 未完成 / 已知問題

1. **CKShare 跨帳號流程未驗證**：需兩台不同 iCloud 帳號的實機＋已佈建 container。已知疑點：`FamilySyncService.markRead` 在成員端組 recordID 的 zone owner 可能不對（應改用 fetchPings 保留的原始 CKRecord.ID）。詳見 `CLOUDKIT_SETUP.md`
2. Xcode 編輯器可能殘留舊的 os import 誤報診斷（程式碼已根治），使用者端需 ⌘Q 重開 Xcode + ⌘B 清除
3. 階段 4（真實資料源：NCDR CAP / CWA / 消防開放資料＋APNs 推播）、階段 5（上線硬化）未開始
4. 生活圈只能新增不能編輯（原型限制，編輯＝刪除重建）

### 下次起點

- 優先：拿實機跑通階段 3 CloudKit 流程（照 `CLOUDKIT_SETUP.md` 設定），修 markRead zone 疑點
- 然後：階段 4 依 `GOVERNMENT_DATA_SOURCES.md`，建議先在 Oracle 上做「抓 NCDR 示警 → 整理成 JSON API」，App 端把 mock provider 換成拉真源（此步不用碰 APNs 就能讓真資料進 App），背景推播留到第二步
- 官網已上線 https://havencircle.looptw.com （純靜態，日後更新＝改 `website/` 後 rsync 覆蓋）
- 使用者可能的 UI 後續：地圖底部卡片改可收合、迷你地圖改唯讀跳轉（都已口頭提過選項，等使用者反饋）

### 技術備忘（本 session 驗證過的環境事實）

- 專案用 Xcode 16+ 同步資料夾（PBXFileSystemSynchronizedRootGroup），新增檔案不用改 pbxproj
- Swift 6.2 預設 MainActor + MemberImportVisibility：用 os Logger 插值的檔案必須自己 `import os`（View 層改走 AppLog 包裝已免疫）
- 驗證流程：`xcodebuild -project HavenCircle.xcodeproj -scheme HavenCircle -destination 'platform=iOS Simulator,id=58EB62E3-88E2-4827-B286-95382DD94AD7' build`（iPhone 17 Pro / iOS 26.5 模擬器）
- 冒煙測試（DEBUG）：`xcrun simctl launch <udid> com.gomiigo.CamMenuApp.HavenCircle --smoke-onboard --smoke-drill --smoke-cloud --start-tab <0-4>`；注意 simctl 背景啟動時 async Task 不會跑，`--smoke-cloud` 需前景
- log 查詢：`log show --predicate 'subsystem == "com.gomiigo.CamMenuApp.HavenCircle"'`（.info 級別要加 --info）
- SwiftData 資料庫直查：模擬器 App 容器內 `default.store`（sqlite3 可讀，表名 ZLOCALSAFETYEVENT 等）

## 2026-07-16

### 完成事項

**NCDR 會員註冊調查**
- 查證 `alerts.ncdr.nat.gov.tw` 會員註冊限制：僅受理公務/公司/學校信箱（gmail/yahoo 等會被拒），機關類別無「個人」選項
- 確認逢甲大學在校生信箱（`@o365.fcu.edu.tw`）符合格式，已用「企業學研」類別送出註冊，**目前卡在帳號審核，審核天數官方未公開**
- **重要發現**：這組會員審核只有在要用官方「示警查詢 API」拿 API Key、或訂閱推播服務時才需要。NCDR 平台的公開 CAP feed（`https://alerts.ncdr.nat.gov.tw/JSONAtomFeeds.ashx`）完全不用申請、不用等審核，現在就能直接抓，已實測成功

**爬蟲機建置：Mac Mini（A1347，i5-2415M，實為 2011 年丐版，非原先以為的 2012 年）**
- 機器已重灌 Linux Mint 22.3 XFCE（帳號 david），改造成專門跑爬蟲的無人值守機器
- 修好兩個原本擋住連線的問題：SSH 服務未啟動（`enable --now ssh`）、ufw 防火牆未放行 22 埠
- 設定 SSH 金鑰驗證取代密碼登入，私鑰放在 `/Users/harryhwa/Documents/important file/macmini-crawler-ssh/`（跟 aaPanel 私鑰同一慣例），控制電腦的 `~/.ssh/config` 設了 `Host macmini` 別名，直接 `ssh macmini` 免密碼連線
- 設定範圍限定的免密碼 sudo（僅 `systemctl`/`apt`/`apt-get`/`ufw`，其餘操作仍需密碼），設定檔在機器上的 `/etc/sudoers.d/david-automation`
- 鎖死系統睡眠/待機（`systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target`），靜音 Mac 硬體開機提示音（改寫 EFI NVRAM 變數 `SystemAudioVolume`，備份存在機器上的 `~/systemaudiovolume_backup.txt`）
- 系統更新完成（387 個套件，含核心 `6.14.0-37` → `6.17.0-40`），已重開機驗證新核心正常開機、爬蟲排程不中斷
- **目錄慣例確立**：`~/crawlers/<專案>/<資料源>/`，先分專案、再分資料源，說明寫在機器上的 `~/crawlers/README.md`
- **HavenCircle 專案的 NCDR 爬蟲已完成並上線**：`~/crawlers/havencircle/ncdr/fetch_ncdr.py`（純 Python 標準函式庫，無額外依賴），過濾出跟家庭安全相關的類別（颱風/地震/海嘯/淹水/土石流/火災/豪雨/強風/高溫/停水/水庫放流/行動電話中斷/傳染病），已處理過真實資料源的怪癖（同一天偶爾多筆事件共用同一個 identifier 且 CAP 連結相同，已用 identifier 去重並記錄跳過筆數）。cron 每 5 分鐘執行一次，log 在 `~/crawlers/havencircle/logs/ncdr.log`
- 搬機器到新位置、斷電重開機後已實測：連線、新核心、爬蟲排程全部正常
- 連線方式說明文件放在控制電腦桌面（`爬蟲機-Mac Mini 連線方式.md`）跟私鑰資料夾裡（`說明.md`），裡面刻意不含任何密碼

### 未完成 / 已知問題

1. **Oracle 端還沒有接收爬蟲資料的服務**：目前 `fetch_ncdr.py` 只把結果存在 Mac Mini 本機的 `latest.json`，還沒有推送到 Oracle、也還沒有給 App 拉取的 API。規劃好但還沒動手：(a) Oracle 上寫一支接收用的 POST endpoint（要有簡單的驗證機制，避免被亂塞假資料）、(b) 給 App 拉取的 GET endpoint、(c) Nginx/SSL 掛載（Oracle 上跑著 30+ 站，改設定前務必 `nginx -t`）
2. **NCDR 會員審核還在等**，審核過後才能拿 API Key／設定推播訂閱，但這不擋路——公開 CAP feed 現在就能用
3. 沿用前一天的未完成項目：CKShare 跨帳號流程未驗證、生活圈只能新增不能編輯
4. **`HavenCircle` git repo 裡還有一批本次 session 開始前就存在、尚未 commit 的本機修改**（`SettingsView.swift` 重寫、新增 `EventVisibility.swift` 等，詳見 `git status`），本次 session 沒有處理這批，也還沒驗證能不能編譯過

### 下次起點

- **優先**：在 Oracle 上把接收 API／serving API／Nginx 掛載這三塊建起來，然後把 `fetch_ncdr.py` 加上「推送給 Oracle」的邏輯（目前只寫本機檔案），這樣才能讓 App 真正拉到真資料
- 之後：等 NCDR 會員審核通過，視需要換成官方 API Key 或加訂閱推播（非必要，公開 feed 已經夠用）
- 有新專案要用 Mac Mini 跑爬蟲時，照 `~/crawlers/README.md` 的慣例開新資料夾，不要跟 havencircle 的混在一起
- 回頭處理 App 端那批還沒 commit 的本機修改（SettingsView 重寫等），先確認能編譯過再決定要不要收進版本控制

## 2026-07-16 深夜 〜 07-17（同一個 session）

### 完成事項

**APNs 伺服器推播全鏈（`99838f6`）**
- Oracle `/apns/`：register.php（權杖登記）、notify_all.php（X-Admin-Key 廣播，admin key 在伺服器 `_apns_config.php`）、cron_check.php（每 5 分鐘比對 NCDR identifier，新警報→無聲喚醒廣播）；資料在 `apns/data/`（nginx deny）
- .p8 金鑰（Key ID B7F7W3Q973）已裝伺服器；本機備份在 `~/Documents/important file/apns-havencircle/`（Apple 不能重下載！）
- App：權杖自動上傳、無聲推播喚醒跑管線；實測 Apple 回 200 sent=1；模擬器收無聲推播不可靠（Apple 限制），實機待測
- nginx：站是「逐目錄開 PHP」，新目錄要加 extension conf（apns.conf 已建）
- 零追蹤架構：伺服器只存權杖、廣播喚醒，比對永遠在裝置上

**功能批（`0b309ad`、`9adb0ba`、`fe5cb74`）**
- 跟隨圈（顯著位置變更、Always 權限、FollowCircleService）、獨立重要地點（member.kind="place"）、圈編輯器與 Onboarding 都有「使用目前位置」
- 新聞 LLM 短摘要 ≤20 字（fetch_news.py summary 欄位＋OpenCC 簡轉繁兜底——LLM 會無視「禁簡體」指令）；App NewsEventProvider 優先顯示 summary；EventPipeline 對既有事件同步新標題

**介面重構「合成案」（C1-C4，`5cfd840`/`d066398`/`e8bc1ed`）**
- 設計流程照 70-deep-planning：3 平行 agent 真分歧提案→premortem→收斂→fresh-context 對抗驗收（抓出 5 個問題）→使用者選定
- 安心頁（HomeStatusView）為啟動頁：大字狀態/家人列/背景看守/回報平安；SafetyOverview 共用聚合（防假性安心，注意：專案已有 enum SafetyStatus 在 SafetyPing.swift，命名撞過一次）
- 分頁五減三（安心/地圖/家人）；提醒中心與回顧降二級（router.homePath push）；設定變全域 sheet（router.showSettings）
- 提醒中心按可信度收合；地圖摘要膠囊化；深淺色/XXXL 字級回歸通過

**其他**
- 功能導覽 coach marks（`3b334aa`）：黑幕聚光燈 6 步；DEBUG `--tour` 參數強制播放；設定頁可重看
- 外觀設定三檔（跟隨系統/淺/深）；APNs 權杖只在 DEBUG 顯示
- 主題：守護綠改 teal 0x0F8A6B/0x4AD6B8＋安心頁狀態色漸層底（`9edebc6`）
- Pitch 頁 https://havencircle.looptw.com/pitch/ 已上線（五畫面，WHY 段註解待實機截圖）

### 未完成／下次起點
1. **系統碟又爆了（清理到一半被中斷）**：已清 DerivedData（騰 1.8G）＋simctl delete unavailable。掃描結果待處理：~/Library/Caches 9.6G（Google 3.2G、VSCode ShipIt 1.3G、Homebrew 1.3G、ms-playwright 1.0G 都可清）、iOS DeviceSupport 5.5G（舊版可刪）、其他模擬器 19G（iPhone 14 Pro Max 6.4G 等；**58EB62E3=iPhone 17 Pro 是 demo 機有資料，勿刪**）
2. 實機測試清單：APNs 無聲喚醒＋可見橫幅、通知權限、跟隨圈背景更新、CKShare 雙機、提醒中心收合手感、04-event-detail 截圖
3. Pitch 頁缺：04 實機截圖（補後取消 index.html 註解、改回六畫面）、家人頁實機重拍、demo 影片連結、隊名
4. 使用者放了 App icon 概念稿在 design/icon-concepts/（獎盃 v1/v2）；若做正式 AppIcon 注意品牌群青 #3657D6 與新 teal
5. 模擬器 demo 資料曾被誤刪，`--smoke-onboard` 可一鍵重建（測試者＋信義區住家圈）

### 踩坑（詳見 LESSONS）
- `xcrun simctl spawn booted defaults write` 會蓋掉 App 沙盒偏好設定的其他 key（onboardingCompleted 等全丟）；且寫入的位置 App 不一定讀得到——改用 DEBUG 啟動參數傳旗標
