# APNs 推播測試操作說明

> 對應 App 端垂直切片（2026-07-16）：App 啟動即註冊 APNs 並把裝置權杖存本機；
> 設定頁「示範與開發」區可複製權杖；點擊通知會 deep link 到提醒中心。
> 後端（Oracle）發送服務尚未建置，本文件說明如何**不寫後端**就驗證整條推播路徑。

## 路徑總覽

```
Apple Push Console（手動發送） ──► APNs ──► 實機收到推播 ──► 點擊 ──► App 開啟提醒中心
```

App 端已完成的部分：
- `HavenCircleApp.swift`：啟動時 `registerForRemoteNotifications()`
- `ShareAcceptance.swift`（AppDelegate）：收到權杖轉十六進位存 `UserDefaults`（鍵：`apnsDeviceToken`）
- 設定頁 → 示範與開發 → 「APNs 裝置權杖」點一下複製
- `NotificationDelegate.didReceive`：點通知 → `havencircle://alerts` → 提醒中心分頁

## 方法一：Apple Push Console（實機，推薦）

前置：實機安裝 Development 簽名的 build（entitlements 已含 `aps-environment: development`）。

1. 實機開 App → 設定分頁 → 「示範與開發」→ 點權杖複製（AirDrop / 備忘錄同步到 Mac）
2. 用開發者帳號登入 [icloud.developer.apple.com/dashboard](https://icloud.developer.apple.com/dashboard/)
3. 選 App ID `com.gomiigo.CamMenuApp.HavenCircle` → **Push Notifications Console**
4. Create New Notification：
   - Environment：**Development**（簽名環境要對，不然回 `BadDeviceToken`）
   - Device Token：貼上剛複製的權杖
   - Payload：

   ```json
   {
     "aps": {
       "alert": {
         "title": "地震速報：臺北市南港區",
         "body": "官方確認事件落在「住家」提醒範圍內，請留意家人狀況。"
       },
       "sound": "default"
     }
   }
   ```

5. Send → 實機鎖屏應在數秒內收到 → 點擊通知 → App 直接開在提醒中心

## 方法二：模擬器（免開發者帳號、免實機）

模擬器不走真 APNs，但 `simctl push` 走同一條系統通知管線，可驗證「收到→點擊→deep link」：

```bash
# 存成 demo.apns（"Simulator Target Bundle" 讓拖曳安裝也能用）
cat > demo.apns <<'EOF'
{
  "Simulator Target Bundle": "com.gomiigo.CamMenuApp.HavenCircle",
  "aps": {
    "alert": {
      "title": "地震速報：臺北市南港區",
      "body": "官方確認事件落在「住家」提醒範圍內，請留意家人狀況。"
    },
    "sound": "default"
  }
}
EOF

xcrun simctl push 58EB62E3-88E2-4827-B286-95382DD94AD7 com.gomiigo.CamMenuApp.HavenCircle demo.apns
```

## 方法三：App 內模擬按鈕（Demo 現場最穩）

設定頁 → 示範與開發 → 「模擬警報通知（示範用）」：本機通知延遲 5 秒發送，
留時間鎖定螢幕展示鎖屏通知。標題帶【示範】字樣——對評審誠實標示這是本機示範，
不冒充伺服器推播。

## 方法四：伺服器主動推送（正式架構，2026-07-16 上線）

整條鏈：App 啟動自動上傳權杖 → Oracle `/apns/register.php` 登記 →
cron（每 5 分鐘）比對 NCDR `latest.json` 的警報 identifier → 有新警報就對
所有裝置廣播「無聲喚醒」→ 裝置被叫醒後自己跑資料管線、比對生活圈、
相關才發本機通知。

**零追蹤設計**：伺服器只存權杖，不存位置／生活圈；喚醒是無差別廣播，
「這則警報跟我家有沒有關係」永遠只在裝置上判斷。

**產品鐵律**：cron 只看 NCDR 官方資料集；媒體報導（news）永遠不觸發推播。

伺服器端檔案（`website/apns/`，部署於 havencircle.looptw.com/apns/）：

| 檔案 | 用途 |
|---|---|
| `register.php` | App 上傳權杖（開放端點，格式驗證＋上限 500） |
| `notify_all.php` | 手動廣播（需 `X-Admin-Key`；`mode=alert` 可發可見通知供 Demo） |
| `cron_check.php` | cron 每 5 分鐘偵測新警報 → 自動廣播無聲喚醒 |
| `data/` | 權杖清單、.p8 私鑰、log（nginx deny all，外部抓不到） |

手動廣播測試（admin key 在伺服器 `_apns_config.php`）：

```bash
# 無聲喚醒（正式模式）
curl -X POST https://havencircle.looptw.com/apns/notify_all.php \
  -H "X-Admin-Key: <admin-key>" -d '{}'

# 可見通知（Demo 用）
curl -X POST https://havencircle.looptw.com/apns/notify_all.php \
  -H "X-Admin-Key: <admin-key>" \
  -d '{"mode":"alert","title":"安心圈","body":"這是伺服器推送測試"}'
```

## 已知限制（下一步）

- **APNs 金鑰尚未安裝**：需到 developer.apple.com → Keys 生成 APNs Auth Key（.p8），
  把檔案放到伺服器 `apns/data/AuthKey.p8`、Key ID 填入 `_apns_config.php` 後，
  發送才會真正生效（在那之前 cron 會記錄「金鑰尚未安裝」並跳過）
- Development（Xcode 直裝）走 sandbox 環境、TestFlight/上架走 production，
  App 會依 build 型態自動帶對環境，伺服器據此選擇 APNs 主機
- 無聲喚醒（content-available）受 iOS 節流：頻率上限大約每小時數次，
  且低電量模式可能延遲——這是 Apple 的系統行為，所有 App 一視同仁
