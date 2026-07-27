# App Store 上架素材（2026-07-24 定稿草案）

> 用法：ASC → App 資訊／版本頁，照欄位貼上。字數都已對齊 Apple 限制。
> 鐵則：任何文案不得出現「地震預警／提前警報」字樣——我們是**災後家人平安閉環**，
> 不是 EEW，審查與公평交易上都不能暗示能搶在地震波之前。

## App 名稱（30 字元內）
```
安心圈－家人平安與災害警報
```
（英文市場顯示名可留 HavenCircle；主要市場台灣用中文名）

## 副標題（30 字元內）
```
災害通知・家人定位・平安回報
```

## 類別
- 主類別：**生活風格（Lifestyle）**（Life360 同類）
- 次類別：**天氣（Weather）**

## 年齡分級
問卷全部「無」→ **4+**

## 描述（4000 字元內）
```
台灣每年都有地震、颱風、豪雨。災害發生的那一刻，你最想知道的只有一件事：家人平安嗎？

安心圈把「官方災害資訊」和「家人互報平安」放進同一個 App——警報進來，全家一目了然；一鍵回報平安，不用在群組裡狂打電話。

【災害警報，永遠免費】
・彙整中央災害示警（NCDR）與氣象署（CWA）官方資料：地震、颱風、豪雨、停班停課等
・依你設定的守護地點推播：家、學校、公司，涵蓋範圍內的警報第一時間通知
・保命相關的警報推播不分免費或付費，全部免費——這是我們的承諾

【家人圈：平安回報閉環】
・邀請碼或 QR Code 一掃入圈，像加入 Apple 家庭一樣簡單
・災害發生後，一鍵回報「我平安」，全家即時看到彼此狀態
・可選擇分享即時位置，讓家人知道你在哪（可隨時關閉）

【安全地圖】
・最近的避難收容所、醫院位置
・24 小時內周遭事件一覽
・行政區警報範圍圖層，一眼看懂影響區域

【主畫面小工具】
・不開 App 也能看到目前警戒狀態

【Guardian+（進階版）】
・不限家人數與守護地點數
・事件歷史回溯 365 天
・未來將推出城市安全情報
免費版即可使用完整警報推播、6 位家人、2 個守護地點與 30 天歷史。

【隱私】
・使用 Sign in with Apple，可隱藏真實信箱
・位置分享完全由你控制，可隨時關閉
・不出售資料、無廣告追蹤
隱私政策：https://havencircle.looptw.com/privacy/

資料來源：國家災害防救科技中心（NCDR）、交通部中央氣象署（CWA）等公開資訊。
本 App 為資訊彙整服務，警報以官方發布為準；請勿將本 App 作為唯一避難判斷依據。
```

## 促銷文字（170 字元內，可隨時改不用送審）
```
新上線：家人圈平安回報＋安全地圖。災害警報推播永遠免費，邀請家人一起加入安心圈。
```

## 關鍵字（100 字元內，半形逗號分隔）
```
地震,颱風,豪雨,災害,警報,防災,避難,家人,定位,平安,通報,停班停課,安全,天氣,示警
```
（不填「安心圈」「HavenCircle」——App 名稱本身已被索引，填了浪費字元）

## 網址欄位
- 支援網址（Support URL）：`https://havencircle.looptw.com/`
- 行銷網址（Marketing URL，可留空）：`https://havencircle.looptw.com/`
- 隱私政策網址：`https://havencircle.looptw.com/privacy/`

## Copyright
```
© 2026 gomiigo
```

## 審查備註（App Review Notes，中英雙語）
```
[English]
HavenCircle is a family disaster-safety app for Taiwan. It aggregates official
disaster alerts (NCDR / Central Weather Administration open data) and lets family
members report "I'm safe" to each other after an event.

How to test the family features with a single device:
1. Sign in with Apple (no demo account needed — any Apple ID works).
2. On first run, choose a role, then the app creates your personal circle.
3. Family tab → "邀請家人" (Invite family) shows an invite code and QR code.
   Joining normally requires a second device; the rest of the app is fully
   usable solo.
4. Background location (Guideline 2.5.4): the app only requests "Always"
   location when the user explicitly turns on "即時圈" (Live Circle) sharing in
   the Family tab — this is opt-in and OFF by default. When enabled, background
   updates let the app keep the user's shared location current for family
   members without requiring the app to stay open, and let the app flag the
   shared location as "expired" once it is more than 15 minutes old. Users who
   never enable Live Circle sharing are only ever asked for "When In Use"
   location, used solely to show nearby shelters/hospitals on the map. Sharing
   can be turned off at any time from the Family tab.
5. Push notifications deliver disaster alerts for the user's saved places.
   Alerts come from our relay server which polls official Taiwan government
   open-data feeds (NCDR / CWA).

In-app purchases (Guardian+): subscription unlocks unlimited family members /
saved places and 365-day history. All safety alert notifications are free —
the paywall never gates any life-safety feature.

The app does NOT claim earthquake early warning. It aggregates official
post-event alerts only.

[中文]
安心圈為台灣家庭災害安全 App。單一裝置測試方式：以任一 Apple ID 透過
Sign in with Apple 登入即可完整體驗；家人加入需第二台裝置，但邀請碼／QR
畫面可直接檢視。

背景定位說明（對應 Guideline 2.5.4）：只有使用者在家人頁主動開啟「即時圈」位置
分享時，App 才會要求「永遠」定位權限，預設關閉、完全由使用者選擇開啟。開啟後
需要背景更新位置，讓家人不用開著 App 也看得到最新位置，並在位置超過 15 分鐘
未更新時明確提示「已過期」，避免用舊位置誤導家人。沒有開啟即時圈的使用者，
App 只會要求「使用期間」定位，用於在地圖上顯示附近的避難所／醫院。位置分享
可隨時在家人頁關閉。

警報推播來自官方公開資料（NCDR／氣象署），App 不宣稱地震預警。
訂閱 Guardian+ 只解鎖數量與歷史上限，所有保命警報功能免費。
```

## 截圖需求清單（兩種尺寸各 5–8 張）
| # | 畫面 | 標語（疊字用） |
|---|---|---|
| 1 | 首頁警戒狀態（綠色安全態） | 全家的安心，一眼看見 |
| 2 | 安全地圖（避難所＋事件 pin） | 最近的避難所在哪，先知道 |
| 3 | 家人圈成員列表（含平安狀態） | 一鍵回報平安，不用狂打電話 |
| 4 | 事件詳情＋平安回報按鈕 | 警報進來，家人互報平安 |
| 5 | 邀請家人（QR Code 畫面） | 掃一下，家人入圈 |
| 6 | Widget＋通知（合成圖，選配） | 不開 App 也安心 |
| 7 | 付費牆（選配，誠實展示） | 警報永遠免費 |

規格：iPhone 6.9"（1320×2868，iPhone 17 Pro Max 模擬器）必備；
iPad 13"（2064×2752）必備（App 支援 iPad）。6.5" 可由 6.9" 自動縮放，不必另拍。
素材路徑：`docs/appstore/screenshots/`（raw 模擬器截圖），套框加標語後再上傳。

## 送審前 ASC 待辦順序
1. 簽付費應用程式合約（稅務＋銀行）→ 沒簽 IAP 無法送審
2. 建 IAP 商品三個（monthly 90／yearly 690＋14 天試用＋首年 490 intro／lifetime 1490 非消耗型，全開家庭共享），ID 必須與 `HavenCircle.storekit` 完全一致
3. 填 App 隱私問卷（見 `ASC隱私問卷答案.md`）
4. 上傳截圖＋貼文案＋審查備註
5. 選 TestFlight 已驗證的 build → 送審（首購 IAP 要與 App 版本一起送）
```
