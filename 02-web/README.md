# NearSafe — 02-web/

家人守護版 safety app 的 monorepo。

## 結構

```
02-web/
├── apps/
│   ├── api/      # Fastify backend
│   └── mobile/   # Expo React Native
├── packages/
│   └── shared/   # 共用型別
├── infra/
│   └── docker-compose.yml
└── package.json  # npm workspaces
```

## 快速開始

```bash
# 1. 安裝依賴
cd 02-web
npm install

# 2. 複製 env
cp .env.example .env
# 填 ANTHROPIC_API_KEY 等

# 3. 啟動 DB + Redis (需 Docker Desktop)
npm run db:up

# 4. 啟動 API
npm run dev:api

# 5. 另一個 terminal 啟動 mobile
npm run dev:mobile
```

## 服務埠
- API: `http://localhost:3000`
- Postgres: `localhost:5432`
- Redis: `localhost:6379`
- Expo Dev Server: Expo 預設 (8081)

## 相關文件
- 產品方向: `../01-dev/1-PRD.md`
- 技術決策: `../01-dev/3-TechStack.md`
- CEO plan: `~/.gstack/projects/9-NearSafe/ceo-plans/2026-04-20-family-guardian.md`
