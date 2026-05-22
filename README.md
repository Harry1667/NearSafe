# NearSafe

家人守護版安全推播 App — 當關注地點發生火災、暴力或重大交通事故，立即推播給家人，附一鍵致電 / 傳 LINE。

## 核心情境
- 北漂子女 → 家鄉父母
- 家長 → 補習中的孩子

## 功能
- 關注地點設定（追蹤地點，不追蹤人）
- 雙向同意機制（QR Code 邀請 + 隨時可退出）
- 推播含行動按鈕：致電 / 傳 LINE / 安全確認
- V1 事件類型：火災 / 暴力 / 大型交通事故

## 技術棧
- **Mobile**：React Native（Expo）+ TypeScript
- **Backend**：Node.js + Fastify + TypeScript
- **DB**：PostgreSQL 16 + PostGIS + Drizzle ORM
- **Queue**：Redis + BullMQ
- **AI**：Claude Haiku 4.5（事件分類 / 摘要）
- **推播**：FCM + APNs

## 快速開始
```bash
cd 02-web
npm install
docker compose -f infra/docker-compose.yml up -d
npm run dev
```
