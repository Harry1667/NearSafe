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

## 已知限制（下一步）

- 權杖目前只存本機，尚未上傳伺服器；Oracle 端「權杖登記＋行政區比對＋自動發送」是階段 4 的後半
- Development 權杖與 Production 權杖不同；上架後要用 Production 環境重測
