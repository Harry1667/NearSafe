# NearSafe — Claude 專案說明

## 產品定位（最重要）
**NearSafe 是「家人守護版」安全推播 app**, 不是通用市民安全雷達。
完整決策記錄: `~/.gstack/projects/9-NearSafe/ceo-plans/2026-04-20-family-guardian.md`

核心情境:
- 北漂子女 → 家鄉父母 (主)
- 家長 → 補習中小孩 (副)
- 推播必含行動按鈕: 致電 / 傳 Line / 安全詢問
- 雙向同意機制 (QR Code 邀請 + 隨時可拒絕)

## 目錄約定
- `01-dev/` — 策略文件 (PRD, UserFlow, TechStack, CEO plan refs)
- `02-web/` — 程式碼 monorepo (npm workspaces)

## 技術棧
- Mobile: React Native (Expo) + TypeScript — **不是 PWA**
- Backend: Node.js + Fastify + TypeScript
- DB: PostgreSQL 16 + PostGIS (Docker)
- ORM: Drizzle
- Queue: Redis + BullMQ
- AI: Claude Haiku 4.5 (分類/摘要主力)
- 推播: FCM + APNs 原生
- 外部: Line Notify API

## V1 Scope (已鎖定)
事件類型只有 3 類: **火災 / 暴力 / 大型交通**。不要擴充。

## 紅線 (絕不破)
- ❌ 不追實時定位 (只存關注地點, 不追人)
- ❌ 不洩漏「誰關注你」名單給第三方
- ❌ 不接廣告 SDK / tracker
- ❌ 不做「家人今天沒回你」類的 dark pattern

## KPI (內測期就要看)
- D7 retention ≥ 40%
- 每週有效推播 / 用戶 = 1-3 則
- 推播 → 行動率 ≥ 30%

## Kill-switch
- 內測 D1 retention <60% → 回頭改 scope
- 誤報率 >20% → pipeline 不能用
- 上線 30 天未達 500 用戶 → persona 錯

## 尚未驗證的前置 (使用者選擇跳過)
- T1: 資料源頻率驗證
- T2: 北漂子女訪談
風險由使用者承擔, 開發過程觀察 KPI 即時調整。

## 開發慣例
- 註解用繁體中文
- 優先 async/await, 不用 callback
- 錯誤處理要明確, 不 silent fail
- 回應精簡、條列式、先結論
- Docker: `docker compose down && docker compose up -d`

## Memory
本專案的跨 session 記憶在:
`~/.claude/projects/-Users-harryhwa-Documents-0-Dev-0-WebDev-9-NearSafe/memory/`

## 目前進度 (2026-04-20)
見 `SESSION_NOTES.md` 取得完整狀態。摘要:

**已完成**
- 02-web/ monorepo 骨架 (npm workspaces) 跑得起來
- API: `/health`, `/health/db`, 4 個 `/invites/*` endpoints
- Drizzle schema 6 表 + migration SQL 產出 (未 apply)
- Device ID 中介層 (X-Device-Id)
- Mobile 2 個 stub 頁 (Expo + Router)

**待辦關鍵阻塞**
- 尚未 `git commit` baseline
- Docker 未裝 → migration 未套 → `/health/db` 仍 503
- `01-dev/1-PRD.md` + `3-TechStack.md` 仍是原案通用雷達 (非家人守護版)
