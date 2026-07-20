# App Store Connect「App 隱私權」問卷答案對照表

> 位置：App Store Connect → 你的 App → App 隱私權（App Privacy）→ 開始回答
> 依據：2026-07-18 的程式碼實況（含新上線的匿名統計 analytics/events.php）。
> 送審前請本人過目一次；若之後加了新資料收集（例如崩潰回報 SDK），要回來同步改。

## Apple 的「收集」定義（先讀這段才看得懂下面的答案）

Apple 定義的「收集（collect）」＝資料**離開裝置**且**開發者拿得到**。
兩個關鍵推論：

1. **存在使用者自己 iCloud（CloudKit 私有／共享資料庫）的資料不算收集**——開發者無法讀取使用者私有容器的內容。家人姓名、固定圈住址座標、即時圈位置、安否回報都屬於這類。
2. **完全在裝置上處理的資料不算收集**——警報比對（NCDR 事件 vs 警戒圈）永遠在裝置端做，關心的行政區、警戒圈設定都沒有上傳到 HavenCircle 伺服器。

因此問卷「理論最小答案」只有兩項（裝置 ID＋使用資料）。
但下面第 1 項「位置」建議**保守申報**，理由見該節。

---

## 問卷第一題：你是否收集資料？

**答：是（Yes）**——APNs 權杖與匿名使用統計確實傳到自家伺服器。

## 逐項資料類型

### 1. 位置 → 精確位置（Precise Location）【建議保守申報】

| 問卷欄位 | 填答 |
|---|---|
| 是否收集 | **是**（保守申報；嚴格定義下可不報，見下） |
| 用途 | **App 功能（App Functionality）** |
| 是否與使用者身分連結 | **否（Not linked to you）** |
| 是否用於追蹤 | **否** |

為什麼保守申報：即時圈位置只寫入使用者自己的家庭 CloudKit（開發者拿不到），嚴格照 Apple 定義可以不申報。但 App 有 Always 定位權限＋背景定位 Background Mode，審查員一眼就看得到；申報「位置—App 功能—不連結身分—不追蹤」不會傷害隱私形象，反而避免「有背景定位卻宣稱不收位置」被打回來要求解釋的來回。若你想採嚴格立場（不申報位置），務必在送審備註欄把 CloudKit 私有容器的架構講清楚。

### 2. 識別碼 → 裝置 ID（Device ID）【必報】

| 問卷欄位 | 填答 |
|---|---|
| 是否收集 | **是** |
| 用途 | **App 功能** |
| 是否與使用者身分連結 | **否** |
| 是否用於追蹤 | **否** |

依據：APNs 裝置權杖上傳到 `havencircle.looptw.com/apns/register.php` 並存在伺服器（tokens.json），這是開發者拿得到的裝置識別碼。伺服器只用它廣播無聲喚醒，不與任何個人資料關聯（伺服器根本沒有其他個人資料可關聯）。

### 3. 使用資料 → 產品互動（Product Interaction）【必報，2026-07-18 新增】

| 問卷欄位 | 填答 |
|---|---|
| 是否收集 | **是** |
| 用途 | **分析（Analytics）** |
| 是否與使用者身分連結 | **否** |
| 是否用於追蹤 | **否** |

依據：新上線的 `analytics/events.php` 匿名統計。只收「事件名 × 次數 ＋ App 版本 ＋ iOS 大版本」，伺服器端只累加當日計數器：不存 IP、不存識別碼、不發 cookie、無任何跨日可關聯的 ID。「不與身分連結」完全站得住腳。

### 4. Firebase Analytics 相關【2026-07-19 新增，接了 Firebase 就必報】

接入 Firebase Analytics（**無廣告識別碼版**，已於執行期 log 確認 `IDFA will not be accessible`）後，**多了一個第三方（Google）收資料**，問卷要補：

| 資料類型 | 填答 | 說明 |
|---|---|---|
| 識別碼 → **其他識別碼**（Firebase App Instance ID） | 收集：是／用途：分析／連結身分：**否**／追蹤：**否**（見下方條件） | Firebase 產生的偽匿名 instance ID，非 IDFA、非帳號 |
| 使用資料 → 產品互動 | 同第 3 節，但**收方多了 Google** | app_open、畫面停留等 |
| 診斷（Diagnostics） | 收集：是／用途：分析／連結身分：否／追蹤：否 | Firebase 會收當機/效能類基本診斷 |

**維持「不用於追蹤」的兩個必要條件（缺一就得改標成 Tracking）**：
1. **IDFA 不收**——已用 `FirebaseAnalytics`（非 `FirebaseAnalyticsIdentitySupport`）做到，log 已證實。
2. **Firebase console 要關掉廣告相關功能**：進 Firebase console →（分析）設定，關閉 **Google Signals／廣告個人化（Ad Personalization）**。只要開了廣告個人化，資料就被視為跨情境追蹤，**必須**改標「Data Used to Track You」。⚠️ 這一步要你去 console 確認，我看不到也點不到。

> Google 的 Firebase SDK 自帶隱私宣告檔（`PrivacyInfo.xcprivacy`），Apple 會一併讀取；但**你自己 App 的問卷仍要如上補齊**，兩者不互相取代。

### 5. 不申報的類型（以及為什麼）

| 類型 | 為什麼不報 |
|---|---|
| 聯絡資訊（姓名等） | 家人姓名只存本機 SwiftData 與使用者自家 CloudKit，開發者拿不到 |
| 使用者內容 | 固定圈、住址座標、安否回報同上——CloudKit 私有／共享資料庫 |
| 診斷（Diagnostics） | 診斷金手指與 log 上傳已在上架清理時整批移除，App 不回傳任何診斷資料 |
| 瀏覽／搜尋紀錄、財務、健康、訊息、照片…… | App 根本沒碰 |

## 問卷第二題：是否用於追蹤（Tracking）？

**答：否——但有一個前提條件。** 沒有任何資料跨 App／網站用於廣告或資料仲介。**前提：Firebase console 的 Google Signals／廣告個人化必須維持關閉**（見第 4 節），且已用無 IDFA 版。只要滿足這兩點，仍可答「否」。**若日後在 Firebase 開了廣告功能，這題就要改成「是」、隱私標籤會出現「Data Used to Track You」**——那等於放棄安心圈的零追蹤賣點，非必要別開。

---

## 送審備註欄（App Review Notes）建議一併寫的三件事

1. **背景定位（Guideline 2.5.4）**：「即時圈」是使用者本人主動開啟的家庭位置分享，需要背景定位在移動時更新警戒圈；未開啟即時圈時 App 不要求 Always 權限。
2. **CKShare 跨帳號**：家庭共享需兩個 iCloud 帳號才能體驗，附上 Demo 影片連結（錄雙機流程時順便錄一段給審查員）。
3. **位置資料流向**：位置只寫入使用者自己的 iCloud（CloudKit 私有／共享資料庫），HavenCircle 伺服器只中繼公開災害警報與匿名統計，拿不到任何位置。

## 對應的既有文件

- `HavenCircle/PrivacyInfo.xcprivacy`：已申報 UserDefaults（CA92.1）。注意：xcprivacy 的 `NSPrivacyCollectedDataTypes` 目前是空的，若照上表申報位置／裝置ID／產品互動，**xcprivacy 也要同步補**（兩邊不一致雖不會自動被拒，但審查工具會比對）。
- App 內「法律與隱私」中心與官網三份法律文件：已涵蓋「不建立移動軌跡」敘事，與上表一致；新增匿名統計後，隱私權政策建議補一句「匿名使用統計（不含 IP 與識別碼）」。
