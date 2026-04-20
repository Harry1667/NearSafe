# NearSafe Session Notes

---

## 2026-04-20 (Sun) — Day 1: pivot + 骨架

### 完成
**策略**
- `/plan-ceo-review` 完整跑完 (SCOPE EXPANSION mode)
- **產品 Pivot**: 通用市民安全雷達 → 「家人守護版」
- CEO plan doc: `~/.gstack/projects/9-NearSafe/ceo-plans/2026-04-20-family-guardian.md`
- 4 個 expansion 決策全部 accepted:
  - React Native 原生 (非 PWA)
  - QR Code 家人邀請 + 同意機制
  - 通知行動按鈕 (致電 / Line / 安全詢問)
  - 冷啟動 persona: 北漂子女 → 中南部父母

**基礎建設**
- `git init` at project root + `.gitignore` + 專案級 `CLAUDE.md`
- 5 份跨 session memory 建好 (`~/.claude/projects/.../memory/`)

**02-web/ monorepo (npm workspaces)**
- `apps/api/` — Fastify 5 + TS + Drizzle ORM + Zod, 已跑起來
- `apps/mobile/` — Expo 52 + RN + Expo Router, 2 個 stub 頁
- `packages/shared/` — 共用 TypeScript 型別 (SafetyEvent, WatchedLocation, Relationship, ...)
- `infra/docker-compose.yml` — PostgreSQL 16 + PostGIS 3.4 + Redis 7

**資料庫**
- Drizzle schema: 6 表 (users, watched_locations, relationships, invite_codes, events, notifications)
- 3 enum (safety_category, relationship_status, feedback_type)
- 5 index (含 2 個 GIST 空間索引 + relationships 唯一對 + events 時間 desc)
- Migration SQL 已產出: `apps/api/drizzle/0000_sloppy_romulus.sql`

**API endpoints**
- Device ID 中介層 (X-Device-Id header → 自動建 user)
- `POST /invites` — 產生邀請碼 (8 字元、去視覺混淆、24h 過期、單次使用、碰撞 retry)
- `GET /invites/:code` — 被邀請者看預覽 (410 過期/已用)
- `POST /invites/:code/accept` — 接受邀請 (transaction, 防自邀、防重複關係)
- `POST /invites/:code/reject` — 拒絕
- `GET /health` + `/health/db`

**Smoke test 全通過**
- ✅ `/health` → 200
- ✅ Device 中介層擋無 header → 400
- ✅ DB 沒跑時 → 500 ECONNREFUSED

### 未完成 / 已知風險
- ❌ **尚未 git commit** (整個 session 的變更都在 working tree)
- ❌ **Docker Desktop 未安裝** → migration 未 apply, `/health/db` 仍 503
- ⚠️ **T1/T2 驗證跳過** (使用者自承風險):
  - T1 資料源頻率驗證未跑
  - T2 北漂子女訪談未做
- ❌ Mobile 完全未接 API
- ❌ 無業務 endpoints: `/watched-locations`, `/notifications`
- ❌ 無資料 pipeline (爬蟲、Haiku 分類、去重)
- ❌ 無推播系統 (FCM/APNs)
- ❌ 無任何測試 (unit + integration)
- ⚠️ `01-dev/1-PRD.md` 仍是原案通用雷達, 未改寫為家人守護版
- ⚠️ `01-dev/3-TechStack.md` 仍寫 PWA, 未改寫為 React Native

### 下次起點 (優先順序)

**立刻做**
1. `git add -A && git commit` — 把本次骨架存成 baseline
2. 裝 Docker Desktop: `brew install --cask docker` → 啟動
3. `npm run db:up` + `cd apps/api && npm run db:migrate` → 驗證 `/health/db` 200

**文件同步**
4. 改寫 `01-dev/1-PRD.md` 為家人守護版 (3 個新情境, 3 類事件, 邀請流程)
5. 改寫 `01-dev/3-TechStack.md` 為 React Native (砍 PWA 段落)

**下一個開發切片 (擇一)**
- A) `POST /watched-locations` — PostGIS 寫入 + 半徑驗證
- B) Mobile 接 API — device_id SecureStore + 邀請流程 UI (QR 產生 + 掃碼)
- C) 資料 pipeline MVP — 中央社 RSS → Haiku 分類 → 寫 events 表
