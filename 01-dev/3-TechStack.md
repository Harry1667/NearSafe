# NearSafe Tech Stack

## 0. 核心技術決策（結論先行）

| 層 | V1 選擇 | 原因 |
|----|---------|------|
| 前端 | **PWA（Next.js）** | 單一 codebase、無 App Store 審核、能用 Web Push |
| 後端 | **Node.js + Fastify** | 你熟、生態成熟、Docker 部署簡單 |
| DB | **PostgreSQL + PostGIS** | 地理運算必備，半徑查詢一行 SQL |
| 快取/佇列 | **Redis** | 事件去重、rate limit、BullMQ 背景工作 |
| AI | **Claude Haiku 4.5** | 分類/摘要便宜快速，成本可控 |
| 推播 | **Web Push (VAPID)** | PWA 原生支援，免費 |
| 部署 | **Oracle 鳳凰城 + Docker Compose** | 你現有環境 |
| CDN | **Cloudflare** | 亞洲節點補鳳凰城延遲 |

---

## 1. 架構總覽

```
┌─────────────────────────────────────────────────────────┐
│  資料來源層（外部）                                      │
│  新聞 RSS · 政府 API · 社群關鍵字 · PTT 爬蟲            │
└──────────────────┬──────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────────────┐
│  Ingestion Pipeline（BullMQ worker）                     │
│  1. 抓取（cron 每 2 分鐘）                               │
│  2. AI 分類 + 地點解析（Claude Haiku）                   │
│  3. 去重（Redis 時間+位置+相似度）                       │
│  4. 寫入 events 表（PostGIS point）                      │
└──────────────────┬──────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────────────┐
│  Matching Engine                                         │
│  - 新事件 → 查 PostGIS 半徑內的關注地點                  │
│  - 套用使用者敏感度 / 勿擾時段 / 事件類型 filter         │
│  - 產生推播任務                                          │
└──────────────────┬──────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────────────┐
│  Push Service（Web Push / FCM）                          │
└──────────────────┬──────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────────────┐
│  PWA 前端（Next.js + Leaflet）                           │
│  Service Worker 接推播 · 地圖顯示 · 設定 API             │
└─────────────────────────────────────────────────────────┘
```

---

## 2. 資料來源（最大風險點）

### V1 優先順序
| 優先 | 來源 | 取得方式 | 延遲 | 法務 | 備註 |
|------|------|----------|------|------|------|
| 🟢 1 | 中央社 RSS | RSS feed | 10-30 min | 清楚 | 最穩定 |
| 🟢 2 | 消防署開放資料 | 政府 Open API | 近即時 | 清楚 | 火災/救護統計 |
| 🟢 3 | 警政署公開資訊 | 政府 Open API | 小時級 | 清楚 | 部分有即時 |
| 🟡 4 | ETtoday / UDN | RSS | 10-30 min | RSS 合理使用 | 量大需去重 |
| 🟡 5 | 公路總局即時路況 | API | 近即時 | 清楚 | 大型事故 |
| 🟡 6 | Threads / X 關鍵字 | 官方 API | 即時 | 需合規 | 噪訊多 |
| 🔴 7 | PTT 爬蟲 | 爬蟲 | 即時 | 灰色 | V2 再考慮 |

**V1 先用 🟢 三個來源 + 鎖定台北市**，證明 pipeline 能跑再擴。

### 抓取頻率
- 新聞 RSS：每 2 分鐘
- 政府 API：每 5 分鐘
- 社群（V2）：websocket 即時

---

## 3. AI Pipeline 細節

### 3.1 模型選擇
- **Claude Haiku 4.5**：分類、去重、摘要（主力，便宜快）
- **Claude Sonnet 4.6**：僅嚴重度判斷有爭議時 escalate（<5% 流量）
- 不自訓模型（V1 無此必要）

### 3.2 Prompt 設計（三階段）

**Stage 1 - 分類**（單則新聞 → JSON）
```json
{
  "is_safety_event": true,
  "category": "fire" | "traffic" | "violence" | "hazmat" | "disorder" | "disaster" | null,
  "severity": 1-5,
  "confidence": 0.0-1.0
}
```

**Stage 2 - 地點解析**
- 先用 regex 抓「XX 區 XX 路」
- 抓不到才問 AI，再丟給 Google Geocoding API 轉經緯度

**Stage 3 - 摘要**（通過嚴重度門檻才執行）
```
輸入：原始新聞全文 + 使用者關注地點距離
輸出：≤40 字的推播短句 + 建議行動
```

### 3.3 成本估算（1000 活躍使用者/天）
- 原始事件：約 500 則/天
- Stage 1 全跑：500 × 500 token ≈ 250K token → $0.25/天
- Stage 3 通過率 ~10%：50 × 1000 token ≈ 50K token → $0.05/天
- **AI 月成本 ≈ $10**

→ 真正貴的是 **Geocoding**（$5/1000 calls），需積極快取。

---

## 4. 資料庫 Schema（簡化版）

```sql
-- 使用者（匿名，device_id 為主）
CREATE TABLE users (
  id UUID PRIMARY KEY,
  device_id TEXT UNIQUE,
  push_subscription JSONB,
  settings JSONB,      -- 頻率、勿擾時段、事件類型開關
  created_at TIMESTAMPTZ
);

-- 關注地點
CREATE TABLE watched_locations (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  name TEXT,
  location GEOGRAPHY(POINT),     -- PostGIS
  radius_m INTEGER,              -- 1000/3000/5000
  is_paused BOOLEAN,
  created_at TIMESTAMPTZ
);
CREATE INDEX ON watched_locations USING GIST(location);

-- 事件
CREATE TABLE events (
  id UUID PRIMARY KEY,
  category TEXT,
  severity INTEGER,
  location GEOGRAPHY(POINT),
  title TEXT,
  summary TEXT,                  -- AI 生成短句
  sources JSONB,                 -- 多來源合併後的原文連結
  fingerprint TEXT UNIQUE,       -- 去重用（時間+位置+文字 hash）
  occurred_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ
);
CREATE INDEX ON events USING GIST(location);
CREATE INDEX ON events(occurred_at DESC);

-- 推播記錄（用於回饋訊號與去重）
CREATE TABLE notifications (
  id UUID PRIMARY KEY,
  user_id UUID,
  event_id UUID,
  watched_location_id UUID,
  feedback TEXT,                 -- 'helpful' | 'too_noisy' | null
  sent_at TIMESTAMPTZ
);
```

### 核心匹配查詢（新事件進來時）
```sql
SELECT wl.user_id, wl.id, ST_Distance(wl.location, $1) AS dist_m
FROM watched_locations wl
WHERE ST_DWithin(wl.location, $1, wl.radius_m)
  AND wl.is_paused = false;
```
PostGIS 一行搞定，10 萬使用者 × 10 萬事件仍毫秒級。

---

## 5. 前端技術細節

- **Next.js 15 App Router** + TypeScript
- **Leaflet + OpenStreetMap tiles**（免費，Google Maps 收費太兇）
- **Tailwind CSS + shadcn/ui**
- **Service Worker**：
  - Web Push 接收
  - 離線快取最近 24h 事件
  - 通知點擊深層連結到地圖
- **geolocation API**：只在 App 開啟時用，**不做背景定位**（省電 + 隱私）

---

## 6. 部署架構（Oracle 鳳凰城）

```
Cloudflare (台灣 edge)
  ↓
Nginx (reverse proxy + TLS)
  ↓
Docker Compose
  ├─ nextjs-app        (PWA)
  ├─ api-server        (Fastify)
  ├─ worker            (BullMQ, AI pipeline)
  ├─ postgres + postgis
  ├─ redis
  └─ watchtower        (自動更新)
```

**鳳凰城延遲問題**
- 台灣 → 鳳凰城 RTT 約 150-180ms
- Cloudflare 快取靜態資源 → 首屏無感
- 推播走 Web Push（Google/Apple 伺服器轉送），延遲由雲端服務決定，跟你的伺服器位置無關 ✅
- API 請求（新增地點、調設定）才會受影響，但這些不是高頻操作

→ **鳳凰城對這個 app 完全 OK**

---

## 7. 成本估算（1000 活躍使用者）

| 項目 | 月成本 | 備註 |
|------|--------|------|
| Oracle VM (現有) | $0 | 已有 |
| Cloudflare | $0 | Free tier |
| Claude Haiku API | ~$10 | 見 3.3 |
| Google Geocoding | ~$15 | 積極快取後 |
| 網域 | ~$1 | 攤提 |
| **合計** | **~$26/月** | 每使用者 $0.026 |

擴張到 10K 使用者 → 約 $80-120/月，仍可控。

---

## 8. 開發里程碑（建議）

| 階段 | 週數 | 產出 |
|------|------|------|
| **M1 資料 pipeline** | 2 週 | 爬中央社 + 消防開放資料 → AI 分類 → 寫入 DB，可用 SQL 查 |
| **M2 匹配引擎 + 推播** | 1 週 | 新增測試使用者 → 手動塞事件 → 收到推播 |
| **M3 PWA MVP** | 2 週 | 地圖 + 新增地點 + 設定頁 |
| **M4 內測** | 1 週 | 找 10 個朋友裝，收集回饋 |
| **M5 調校 + 公開** | 2 週 | 調整敏感度、修 bug、上線 |

→ **8 週到公開 MVP**，前提是專職 1 人全職。

---

## 9. 技術風險與 Plan B

| 風險 | 機率 | 影響 | Plan B |
|------|------|------|--------|
| 新聞 RSS 延遲太久失去即時性 | 高 | 高 | 接社群 API 補即時性（V2） |
| AI 誤判率過高 | 中 | 高 | 加人工複核佇列（每日 <20 則） |
| Geocoding 成本爆炸 | 中 | 中 | 自建 nominatim（OSM 開源） |
| Web Push iOS 支援度 | 低 | 中 | iOS 16.4+ 已支援 PWA push，夠用 |
| 法務（爬蟲/版權） | 中 | 高 | V1 只用 RSS + 政府 Open API |

---

## 10. V2 之後的擴展方向
- 群眾回報（使用者可發事件，AI + 人工審核）
- 歷史熱圖（哪些區域高風險）
- 原生 App（React Native，共用 API）
- 國際化（日本、東南亞）
- 訂閱制（家庭方案：共享關注地點）
