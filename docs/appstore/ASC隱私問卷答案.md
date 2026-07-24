# App Store Connect「App 隱私」問卷答案表（2026-07-24）

> 用法：ASC → 你的 App → 左側「App 隱私」→ 開始編輯。照本表逐題點選。
> 依據：程式碼實地盤點（Firestore 位置寫入、Firebase Auth、APNs 中繼、Analytics），與 App 內
> `PrivacyInfo.xcprivacy`（2026-07-24 重寫版）、隱私政策網頁三邊一致。**不要憑印象改答案**，
> 改了任何一邊，其他兩邊要同步改。

## 第一題：是否從這個 App 收集資料？
**答：是（Yes, we collect data from this app）**

## 要勾選的資料類型（共 6 項）

| ASC 資料類型 | 勾選 | 用途（Purposes） | 連結身分？ | 用於追蹤？ |
|---|---|---|---|---|
| 位置 → **精確位置**（Precise Location） | ✅ | App 功能（App Functionality） | **是** | 否 |
| 聯絡資訊 → **姓名**（Name） | ✅ | App 功能 | **是** | 否 |
| 聯絡資訊 → **電子郵件**（Email Address） | ✅ | App 功能 | **是** | 否 |
| 識別碼 → **使用者 ID**（User ID） | ✅ | App 功能 | **是** | 否 |
| 識別碼 → **裝置 ID**（Device ID） | ✅ | App 功能 | **否** | 否 |
| 使用資料 → **產品互動**（Product Interaction） | ✅ | 分析（Analytics） | **否** | 否 |

其餘所有類型（健康、財務、通訊錄、照片、訊息、瀏覽紀錄、搜尋紀錄、粗略位置、
診斷、其他資料…）一律**不勾**。

## 每項的事實依據（審查若問，照這個答）

- **精確位置（連結身分）**：家人圈位置分享與平安回報座標寫入 Firestore
  `families/{id}/locations/{uid}`、`pings`，以 Firebase Auth uid 為文件鍵。使用者可隨時關閉分享。
- **姓名（連結身分）**：使用者自訂顯示名稱隨成員文件寫入 Firestore，供家人辨識。
- **電子郵件（連結身分）**：Sign in with Apple 憑證交給 Firebase Auth，帳號紀錄含 email
  （使用者可用 Apple 私密轉發信箱）。開發者自建伺服器不另存。
- **使用者 ID（連結身分）**：Firebase Auth uid，雲端家庭資料的主鍵。
- **裝置 ID（不連結）**：APNs 裝置權杖上傳開發者推播中繼伺服器（只有 token＋環境別）；
  FCM 註冊權杖由 Google 持有。兩者都不與帳號綁定。
- **產品互動（不連結）**：Firebase Analytics 事件與畫面瀏覽（未呼叫 setUserID）＋
  自建端點的匿名事件計數（僅事件名／次數／App 版本／OS 版本）。

## 追蹤（Tracking）題
**全部答否。** 無廣告 SDK、無 ATT、資料不與第三方共享做跨 App 追蹤。

## 隱私政策網址欄位
`https://havencircle.looptw.com/privacy/`

## 一致性檢查清單（送審前最後跑一次）
- [ ] ASC 問卷 6 項 ＝ PrivacyInfo.xcprivacy 6 項（類型、連結、追蹤逐一對得上）
- [ ] 隱私政策網頁與 App 內 LegalDocuments 同版本（都說位置存 Firebase，不再有 iCloud 舊描述）
- [ ] 若日後加 Crashlytics／廣告／setUserID，三邊同步重填
