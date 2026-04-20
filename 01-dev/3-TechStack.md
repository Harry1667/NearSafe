# NearSafe Tech Stack v1-B · 家人守護版

> 對應 PRD v1-B。已根據 CEO review 從 PWA 改為 React Native 原生。

## 0. 結論 (TL;DR)

| 層 | 選擇 | 為什麼 |
|----|------|------|
| Mobile | **Expo (React Native)** + TypeScript | 推播可靠性是家人版命門, PWA iOS 限制致命 |
| Backend | **Node.js + Fastify 5** + TypeScript | 輕、快、生態成熟、使用者熟 |
| DB | **PostgreSQL 16 + PostGIS 3.4** | ST_DWithin 半徑查詢一行 SQL |
| ORM | **Drizzle** + postgres.js | TS first, PostGIS raw SQL 友善 (Prisma 對 geography 支援差) |
| Queue/Cache | **Redis 7 + BullMQ** | AI pipeline + 去重 + rate limit |
| AI | **Claude Haiku 4.5** (主), Sonnet 4.6 (escalate) | 分類/摘要便宜快; <5% 爭議才升級 |
| 推播 | **FCM (Android + iOS via Firebase)** | 跨平台統一, Line Notify API for 行動按鈕 |
| 外部 | **Line Notify API** | 通知行動按鈕「傳 Line」「安全詢問」依賴 |
| 地理編碼 | **Google Geocoding** (有快取) | 台灣地址 → 經緯度, 積極快取控成本 |
| CI | GitHub Actions (之後再上) | V1 還不需要 |
| 部署 | Oracle 鳳凰城 + Docker Compose + Cloudflare | 使用者現有環境 |

---

## 1. 架構總覽

```
┌──────────────────────────────────────────────────────────┐
│  資料來源層                                               │
│  中央社 RSS · 消防署 API · 警政 · (V2: Threads/PTT)      │
└──────────────────┬───────────────────────────────────────┘
                   ↓
┌──────────────────────────────────────────────────────────┐
│  Ingestion Pipeline (BullMQ worker)                      │
│  抓取 (cron 2min) → AI 分類 → 地點解析 → 去重 → events   │
└──────────────────┬───────────────────────────────────────┘
                   ↓
┌──────────────────────────────────────────────────────────┐
│  Matching Engine                                         │
│  ST_DWithin(event, watched_location) → push tasks       │
│  套用: 使用者敏感度 / 勿擾時段 / 事件類型 filter         │
└──────────────────┬───────────────────────────────────────┘
                   ↓
┌──────────────────────────────────────────────────────────┐
│  Push Service (FCM)                                      │
│  含 action buttons: tel:/, line://, safety_check, map    │
└──────────────────┬───────────────────────────────────────┘
                   ↓
┌──────────────────────────────────────────────────────────┐
│  Mobile (Expo RN)                                        │
│  首頁 (地圖 + care feed) · 關心的人 · 設定              │
│  + QR 邀請流程 · device_id 管理 · 通知行動 deep link     │
└──────────────────────────────────────────────────────────┘
```

---

## 2. Monorepo 結構 (已建)

```
02-web/
├── apps/
│   ├── api/                    # Fastify backend
│   │   ├── src/
│   │   │   ├── index.ts
│   │   │   ├── env.ts          # zod 驗證
│   │   │   ├── db/             # Drizzle client + schema
│   │   │   ├── plugins/        # device middleware
│   │   │   ├── routes/         # health, invites, ...
│   │   │   └── lib/            # 共用工具
│   │   └── drizzle/            # Migration SQL
│   └── mobile/                 # Expo
│       ├── app/                # Expo Router
│       └── app.json
├── packages/
│   └── shared/                 # 共用 TS 型別
└── infra/
    └── docker-compose.yml      # Postgres + PostGIS + Redis
```

---

## 3. 資料來源 (最大風險點)

### V1 優先 (實際會用)
| 優先 | 來源 | 延遲 | 法務 | 備註 |
|------|------|------|------|------|
| 🟢 1 | 中央社 RSS | 10-30 min | 清楚 | 最穩定 |
| 🟢 2 | 消防署開放資料 | 近即時 | 清楚 | 火災為主 |
| 🟡 3 | 警政署公開資訊 | 小時級 | 清楚 | 暴力事件較慢 |
| 🟡 4 | 公路總局即時路況 | 近即時 | 清楚 | 大型交通 |

**V1 先只用 🟢 2 個來源 + 限定雙北 + 桃竹苗 + 中彰投 + 雲嘉南 + 高屏**。

### V2 以後
- Threads/X 關鍵字 (合規性需先確認)
- 使用者回報 (需 AI + 人工複核, 冷啟動後才有意義)

---

## 4. AI Pipeline

### 三階段 prompt
1. **分類** (全跑): 原文 → `{is_safety_event, category, severity, confidence}`
2. **地點解析**: regex 先試, 抓不到才問 AI, 結果丟 Google Geocoding
3. **摘要生成** (通過嚴重度門檻才跑): 原文 → ≤40 字推播短句 + 建議行動

### 成本估算 (1000 活躍 / 天)
- 每日原始事件 ~500 則
- Stage 1: 500 × 500 token ≈ 250K token → ~$0.25/天
- Stage 3 (通過率 ~10%): 50 × 1000 token ≈ 50K token → ~$0.05/天
- **AI 月成本 ~$10**

貴的其實是 **Geocoding** ($5/1000 calls)。必積極快取「常出現地標 / 路口」。

---

## 5. 資料庫 Schema (已建)

6 張表, 5 個 index:

- `users` — device_id 匿名使用者 + push_token
- `watched_locations` — 關注地點 + geography(Point, 4326) + GIST index
- `relationships` — 家人雙向同意 + unique pair
- `invite_codes` — 8 字元短碼 + 24h 過期 + 單次
- `events` — 事件 + geography + GIST + fingerprint unique
- `notifications` — 推播紀錄 + feedback + action_taken

詳見 `02-web/apps/api/src/db/schema.ts`。

### 核心匹配查詢
```sql
SELECT wl.watcher_user_id, wl.id, ST_Distance(wl.point, $1) AS dist_m
FROM watched_locations wl
WHERE ST_DWithin(wl.point, $1, wl.radius_m)
  AND wl.is_paused = false;
```
GIST index 下萬筆規模毫秒級。

---

## 6. Mobile (Expo RN)

### 已安裝
- `expo` 52, `expo-router`, `expo-status-bar`
- `react-native-safe-area-context`, `react-native-screens`

### 將要安裝 (邀請流程 + 推播)
- `expo-secure-store` — 存 device_id
- `expo-camera` — QR 掃碼
- `expo-linking` — deep link `nearsafe://invite/XXX`
- `expo-notifications` — 推播接收 + action buttons
- `expo-device` — 取裝置資訊 (for push registration)
- QR 產生: `react-native-qrcode-svg` + `react-native-svg`
- 地圖: `react-native-maps` (V1 後期才需)

### 不用 / 避免
- ❌ Web Push / PWA API (已淘汰)
- ❌ background location (違背紅線, 且 Apple 審核風險)

---

## 7. 推播系統

### 採 FCM 統一 (不直連 APNs)
- Android: FCM 原生
- iOS: FCM → APNs 代發 (Firebase 負責 token 交換)
- 好處: 後端只管 FCM HTTP v1 API, 不管 Apple key 輪替
- 缺點: 依賴 Firebase (免費但得有 Google 帳號)

### Action buttons (iOS + Android)
- iOS: `UNNotificationCategory` + `UNNotificationAction`
- Android: `Notification.Action` + `PendingIntent`
- Expo 抽象: `Notifications.setNotificationCategoryAsync()`

### 行動按鈕對應
| 按鈕 | 動作 |
|------|------|
| 致電 | `tel:${phone}` (需先存家人電話, V2 才加) |
| 傳 Line | Line URL scheme (`line://msg/text/...`) |
| 安全詢問 | 呼叫 Backend → Line Notify 代發 |
| 查看地圖 | deep link 回 app |

---

## 8. 部署 (Oracle 鳳凰城)

```
Cloudflare (台灣 edge)
  ↓
Nginx (reverse proxy + TLS)
  ↓
Docker Compose:
  ├─ api-server        (Fastify)
  ├─ worker            (BullMQ AI pipeline)
  ├─ postgres+postgis
  ├─ redis
  └─ watchtower        (自動更新)
```

### 延遲考量
- 台灣 → 鳳凰城 RTT ~150-180ms
- 靜態資源: Cloudflare 台灣 edge
- 推播: FCM 伺服器轉送, 機房位置影響極小
- API 請求 (邀請、設定): 150ms 可接受 (非高頻)

---

## 9. 成本估算 (1000 活躍)

| 項目 | 月 | 備註 |
|------|----|------|
| Oracle VM (現有) | $0 | 已有 |
| Cloudflare Free | $0 | |
| Firebase (FCM) | $0 | 免費額度夠 |
| Claude Haiku | ~$10 | 見 §4 |
| Google Geocoding | ~$15 | 積極快取 |
| Line Notify | $0 | 免費 |
| **合計** | **~$25/月** | 每用戶 $0.025 |

10K 用戶 → ~$80-120/月。

---

## 10. 技術風險與 Plan B

| 風險 | 可能 | 影響 | Plan B |
|------|------|------|--------|
| 新聞 RSS 延遲太久 | 高 | 高 | V2 接 Threads / X |
| AI 分類誤報 >20% | 中 | 致命 | Kill-switch + 人工複核佇列 |
| Geocoding 爆炸 | 中 | 中 | 自建 nominatim (OSM) |
| FCM iOS 被限制 (推播靜音) | 低 | 高 | 直連 APNs + 轉送 |
| Line Notify 關閉 | 低 | 中 | 改 Line Messaging API (需公司帳號) |
| 法務 (爬蟲版權) | 中 | 高 | V1 只 RSS + 政府 Open API |

---

## 11. 開發里程碑

| 階段 | 週數 | 產出 |
|------|------|------|
| **M1 資料 pipeline** | 2 週 | 爬 RSS + 消防 → AI 分類 → 寫 DB, SQL 可查 |
| **M2 匹配 + 推播** | 1 週 | 手動塞事件 → 測試裝置收到有行動按鈕的推播 |
| **M3 Mobile MVP** | 2 週 | 3 頁完整 + 邀請流程 QR 完成 |
| **M4 內測** | 1 週 | 5 家庭、30 人, 實際使用收 retention 指標 |
| **M5 調校 + 上線** | 2 週 | PH / Threads 北漂圈公開 |

**8 週到公開 MVP** (1 人全職, 含 CC pair)。

---

## 12. V2+ 預留

- 付費訂閱 tier (家庭方案)
- 群眾回報 + AI/人工複核
- Widget + Apple Watch
- 熱圖 / 事件統計
- 國際化 (日本首發, 類似 persona)
- 企業版 (校園 / 物業 B2B)
