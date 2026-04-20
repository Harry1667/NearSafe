---
name: hdw-proxycli
description: |
  AI Proxy CLI 管理與除錯。管理 proxy-cli 服務（gRPC + 儀表板），
  處理 provider 切換、憑證、fallback chain、部署、觀測、備份/還原。
  Use when: "proxycli", "proxy-cli", "AI proxy", "gRPC proxy",
  "provider fallback", "claude quota", "gemini quota", "openai quota",
  "clip.twloop.com", "port 50051", "port 8091", "effort", "routing",
  "備份 DB", "prometheus metrics", "auto route"
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - AskUserQuestion
---

# /proxycli — AI Proxy CLI 管理 Skill

管理 proxy-cli 服務（gRPC + dashboard），多 provider 動態切換、觀測、部署。

## ⚠️ Claude CLI Provider — ToS 灰區（2026-04-19 大清理）

本專案用 `claude --print` 包裝 Claude Code subscription。這在 Anthropic ToS 上屬灰區，**2026-04 實測帳號被 Anthropic 封鎖**。以下行為**已從程式碼移除，不可重新加回來**：

1. **❌ 偽造 OAuth token 欄位** — `_patch_claude_creds()` 已於 2026-04-19 刪除。不可寫死 `rateLimitTier = "default_claude_max_20x"` 或 `subscriptionType = "max"`；不可主動呼叫 `api.anthropic.com/api/oauth/claude_cli/roles` 抓 `org_uuid` 回寫 token 檔案。
2. **❌ 多組 OAuth slot 輪替** — `_discover_slots` 只載入 slot-0；dashboard 新增 slot API 回 403；OAuth web flow 新帳號會**覆蓋 slot-0**（不再建 slot-N）；SQLite restore 只還原 `slot_id=0`。
3. **❌ 排程式 health probe** — `_probe_task` / `_health_probe_loop` / `health_probe()` 全刪，改走 lazy detection（請求失敗時 `_is_auth_error` / `_is_quarantine_error` 即時偵測）。`config.yaml` 的 `health_probe_interval` 已 deprecated（保留 key 避免破壞舊 config）。
4. **❌ `src/direct.py` 用 OAuth Bearer token 打 Anthropic API** — `_call_claude()` 已改成 `_call_claude_apikey()`，只接受 `ANTHROPIC_API_KEY` env var 付費模式。沒有 env var 時 Claude direct API 路徑直接 return None，流量走 fallback chain。
5. **❌ 單帳號日用量無上限** — `db.py:check_provider_quota` 強制 claude 預設 300k tokens/day cap；超過觸發 fallback chain（自動跳過任何用 Claude OAuth 的路徑）。
6. **🔒 帳號風控訊號偵測** — `_is_quarantine_error` 偵測 `suspended` / `abuse` / `risk review` / `device verification` / `account anomaly` / `challenge` / `policy violation` 等 keyword，命中後 slot 被**永久隔離**（`mark_quarantined`），不進 fallback、不可由 `mark_healthy` 恢復，只能由管理員手動在 dashboard 清除。

**若 Claude 帳號再次被封：**
- 把 Claude 從 `auto_router.py` 主路由移除，讓 direct API provider（DeepSeek / OpenAI / Gemini）接管
- **不要換帳號重跑** — Anthropic 可從 IP + 行為指紋識別
- 考慮付費 Anthropic API Key（設 `ANTHROPIC_API_KEY` env var 啟用 `_call_claude_apikey` 合規路徑）

詳見專案倉庫的 `CLAUDE.md` / `DESIGN.md`「ToS 灰區」章節。

## 服務資訊

| 項目 | 值 |
|------|------|
| 伺服器 | **NAS DS923+（192.168.0.126）**（2026-04-18 從 aapanel 搬回 NAS） |
| Docker 路徑 | `/volume1/docker/proxy-cli/` |
| SSH 別名 | `nas`（key: `~/.ssh/id_ed25519_nas`，port 33333，user `docker`）|
| 本地路徑 | `/Users/macpro-david/Library/CloudStorage/Dropbox/84-WebCode/01-mac/1-info/proxy-cli` |
| 容器名稱 | `ai-proxy`（compose service `proxy`）|
| gRPC port | `0.0.0.0:50051`（NPM `cli.twloop.com` 反代 — ⚠️ **必須用 `grpc_pass`，不是 `proxy_pass`**；見「常見問題」外網 gRPC 段）|
| Dashboard port | `0.0.0.0:8091 → 8080`（NPM `clip.twloop.com` 反代）|
| OAuth relay | container 80 / 1455 EXPOSE，**host 80 已被 DSM 佔用，目前未對外**；creds 從 aapanel 搬來不需重新 OAuth |
| 域名 | `clip.twloop.com` (HTTP) / `cli.twloop.com` (gRPC)，由 NAS NPM 反代 |
| 資源上限 | RAM 2g（NAS kernel 不支援 CPU CFS，無 cpus 限制） |
| 日誌輪轉 | json-file，10MB × 3 份 |
| 舊位置（已停） | aapanel `/opt/docker/proxy-cli/`（容器 stop 但檔案保留作回滾備援） |

### NAS 部署常用指令

```bash
# 部署（rsync + build）— 注意 NAS 用 docker 帳號 PATH 沒 /usr/bin/rsync，要加 --rsync-path
rsync -avz --rsync-path=/usr/bin/rsync \
  --exclude='.env' --exclude='__pycache__' --exclude='.git' \
  --exclude='*.pyc' --exclude='.DS_Store' --exclude='.venv' \
  --exclude='data/' --exclude='creds/' --exclude='certs/' \
  --exclude='deploy-aapanel/' --exclude='*.csv' --exclude='*.log' \
  --exclude='proto/aiproxy_pb2.py' --exclude='proto/aiproxy_pb2_grpc.py' \
  --exclude='.pytest_cache/' --exclude='.claude/' --exclude='.gstack/' \
  -e "ssh -p 33333 -i ~/.ssh/id_ed25519_nas -o StrictHostKeyChecking=no" \
  ./ docker@192.168.0.126:/volume1/docker/proxy-cli/

# build + restart — ⚠️ 必須用 -f deploy-nas/docker-compose.yml
# 專案根目錄的 docker-compose.yml 是 Mac 開發用（有 cpus 限制，NAS kernel 不支援）
ssh nas "cd /volume1/docker/proxy-cli && /usr/local/bin/docker compose -f deploy-nas/docker-compose.yml up -d --build"

# 查 log
ssh nas "/usr/local/bin/docker logs ai-proxy --tail 50"

# 健康檢查
ssh nas "curl -s http://localhost:8091/healthz && curl -s http://localhost:8091/ready"

# 推單一檔案到 NAS（scp 必須加 -O，sftp subsystem 被禁）
scp -O -P 33333 -i ~/.ssh/id_ed25519_nas config.yaml docker@192.168.0.126:/volume1/docker/proxy-cli/config.yaml
```

### NAS-specific 注意事項

- **scp 必須 `-O`**：DSM 把 sftp subsystem 關了，新版 scp 走 sftp 會失敗。
- **rsync 必須 `--rsync-path=/usr/bin/rsync`**：non-interactive ssh PATH 沒帶到 rsync。
- **`rm` 被 docker 帳號 .profile 攔截**：覆寫檔案改用 mv 改名再 scp。
- **CPU CFS 不支援**：compose 不能設 `cpus: "x.x"`，啟動會 `NanoCPUs can not be set` 報錯。
- **OAuth 重登入需先停 DSM**：80/1455 host port 被 DSM 佔用，要重新 OAuth 得改 DSM port 或借容器內網跑。
- **🔴 DSM ACL 會把 bind mount 變 read-only**（2026-04-19 踩到）：host 端 `ls -la` 顯示 `drwxrwxrwx+`（有 `+` = NFSv4 ACL），**但容器內 `app` user 依然寫不了檔**。症狀：
  - codex 每次請求卡 180s timeout，log 出 `failed to create session: Permission denied` on `/home/app/.codex/sessions`
  - gemini token refresh 失敗：`Permission denied: '/home/app/.gemini/oauth_creds.json'`
  - **修法**：`entrypoint.sh` 以 root 啟動時加 `chmod -R u+w,g+w /home/app/.{claude,gemini,codex} 2>/dev/null || true`（已 commit 32d6d56）。診斷指令：`docker exec -u app ai-proxy sh -c 'echo x > /home/app/.codex/test 2>&1'`，若 `Permission denied` 就是中招。

## Provider（10 個）

| Provider | 類型 | CLI 命令 | 憑證位置 | Fallback model |
|----------|------|----------|----------|---------------|
| claude | CLI OAuth + API | `claude` | `~/.claude/.credentials.json` | `claude-haiku-4-5` |
| gemini | CLI OAuth + API | `gemini` | `~/.gemini/oauth_creds.json` | `gemini-2.5-flash` |
| openai | CLI OAuth（codex）| `codex` | `~/.codex/auth.json` | `gpt-4o-mini` |
| deepseek | API Key only | — | API Key 在 dashboard / env | `deepseek-chat` |
| mistral | API Key only | — | 同上 | — |
| groq | API Key only | — | 同上 | — |
| xai | API Key only | — | 同上 | — |
| together | API Key only | — | 同上 | — |
| fireworks | API Key only | — | 同上 | — |
| cohere | API Key only | — | 同上 | — |

> `openai.enabled: true` 是 fallback chain 必要條件；CLI-based 三家都關閉後仍能用 API-only provider（需要 API Key）。

## 客戶端連線方式（兩種情境）

**選對路徑比效能重要** — 走錯路徑可能讓同 NAS 的流量繞出去再繞回來，也可能讓外網連線誤用內網 IP 失敗。

### 情境 1：同 NAS 不同 container → 走 docker network 內網

客戶端跑在 NAS 上另一個 container（e.g. 新開的 web app 想呼叫 ai-proxy）。

**做法：加入同一個 docker network，用容器名連線**

```yaml
# 新 container 的 docker-compose.yml（關鍵片段）
services:
  my-app:
    networks:
      - deploy-nas_default   # 加入 ai-proxy 所在的 network
    environment:
      - PROXY_ADDR=ai-proxy:50051   # ⚠️ 用容器內部 port 50051，不是對外 8091

networks:
  deploy-nas_default:
    external: true           # 外部已存在的 network，不要重建
```

```python
# 客戶端（明碼 gRPC，不走 TLS）
import grpc
channel = grpc.insecure_channel("ai-proxy:50051")
meta = [("authorization", f"Bearer {TOKEN}")]
```

**優點：** 零延遲、不走 NPM、不耗 NAS 對外頻寬。
**替代（IP 直連）：** `grpc.insecure_channel("192.168.32.1:50051")` 可用但 IP 可能隨重啟變動，建議用容器名。

### 情境 1.5：REST 備援（debug 用，非生產推薦）

`POST https://clip.twloop.com/api/chat`（Bearer token）— HTTP/1.1，穿 NPM `proxy_pass` 沒有 gRPC 的 HTTP/2 frame 問題。

```bash
curl -X POST https://clip.twloop.com/api/chat \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"prompt":"hi","project":"debug","group":"test"}'
# 回：{"ok":true,"content":"...","input_tokens":N,"output_tokens":N,"latency_ms":N}
```

**✅ Response shape（2026-04-19 修正後，跟 gRPC 一致）：** 包含 `ok / content / input_tokens / output_tokens / latency_ms / actual_provider / actual_model / tokens_estimated`。fallback 發生時 `actual_provider != provider`，用量記錄也會歸類到真實 provider（之前 `provider=request 值` 會讓 fallback 統計失真，已一併修正）。

**何時可以用：**
- gRPC 通道出問題時的臨時 escape hatch（例如 NPM `grpc_pass` 壞掉）
- 驗證「帳號 / token / provider 是否正常」的純 debug 流量
- 一次性 shell 測試、運維腳本

**何時絕對不要用：**
- 生產 client 不要把 REST 當主要路徑。用 gRPC + 情境 2 的正統做法，否則失去 fallback tracking。
- Anti-pattern：「gRPC 連不上就切換 REST」屬於**應用層繞過基礎設施問題**。正解是去 NPM admin 加 `grpc_pass`（詳見「常見問題 → 外網 gRPC 連不上」），5 分鐘修好，所有 client 一起受惠。

### 情境 2：外網客戶端（Tokyo VPS / 家外 / 他人電腦）→ 走 `cli.twloop.com:443`

客戶端無法進 NAS 內網，必須透過 Cloudflare → NAS NPM → ai-proxy。

**做法：連 `cli.twloop.com:443`（TLS 加密），NPM 端做 `grpc_pass` 轉發**

```python
# 客戶端（TLS gRPC）
import grpc
channel = grpc.secure_channel(
    "cli.twloop.com:443",
    grpc.ssl_channel_credentials(),  # 用系統 CA，Let's Encrypt 自動信任
)
meta = [("authorization", f"Bearer {TOKEN}")]
```

**前提：** NPM 的 `cli.twloop.com` 必須配 `grpc_pass`（不是 `proxy_pass`），詳見「常見問題 → 外網 gRPC 客戶端連不上 / RST_STREAM」。

### 決策表

| 問題 | 情境 1 | 情境 2 |
|------|--------|--------|
| 延遲 | < 1ms | 20-100ms（看外網）|
| 需要 TLS 憑證？ | 不需要（內網明碼）| 需要（`grpc.ssl_channel_credentials()`）|
| 連線字串 | `ai-proxy:50051` | `cli.twloop.com:443` |
| `insecure_channel` vs `secure_channel` | insecure | secure |
| NPM 參與？ | ❌ | ✅ |
| 容器必須加 network？ | ✅（`deploy-nas_default`）| ❌ |
| 失敗症狀 | DNS 解析失敗 / connection refused | RST_STREAM / `unexpected HTTP status` |

### ⚠️ 反模式（不要做）

- **同 NAS container 卻連 `cli.twloop.com:443`**：繞出去再繞回來，多 3 跳、吃頻寬、吃 NPM CPU。
- **外網客戶端卻連 `192.168.32.1:50051`**：連不到（私有 IP），會卡在 SYN 階段 timeout。
- **同 NAS 卻不加 network 直接用容器名**：Docker DNS 查不到，`Name or service not known`。

## Fallback 機制

請求不指定 `provider` 時（**推薦**）：
1. `usable_providers()` 偵測可用的 pool
2. `resolve_model_for_providers()` 依 tier/quality 挑最合適的
3. 失敗（auth_expired / cli_error / exhausted）→ fallback chain：
   - **優先 CLI pool**（有 codex 憑證就用，吃免費 OAuth 額度）
   - 再試 direct API（需 API Key）

Fallback chain（`claude` 失敗時依序嘗試）：
```
claude → openai(codex) → deepseek → groq → mistral → xai
       → together → fireworks → cohere → gemini
```

## API 端點速查

### 公開（不需 auth）

| 端點 | 用途 |
|------|------|
| `GET /healthz` | Liveness — process alive，永遠 200 |
| `GET /ready` | Readiness — 任一 provider 有 healthy slot 才 200，否則 503 |
| `GET /metrics` | Prometheus exposition format（slots、requests/tokens 24h、latency p50/p95/p99） |
| `GET /api/health` | 詳細 pool 狀態（原有，更完整） |
| `GET /api/usage?days=7` | 用量 + 延遲分位數 |
| `GET /api/recent?limit=20&offset=0&user=&provider=&status=` | 最近請求，支援搜尋/翻頁 |
| `GET /api/breakdown?by=user\|project\|provider\|model&days=7` | 分類統計 |
| `GET /api/routing-stats?days=7` | auto-route 決策分層統計（訓練資料） |
| `GET /api/claude-risk` | Claude ToS 風險卡片資料（今日 token / cap % / 紅綠燈 / 7 日趨勢） |
| `POST /api/chat` | REST 備援入口（Bearer token auth），回 `actual_provider/actual_model`（2026-04-19 修正） |
| `POST /api/chat/stream` | REST SSE streaming，`done` 事件含 `actual_provider/actual_model` |
| `POST /api/chat/tools` | REST function calling（含 `actual_provider/actual_model`） |

### Admin only（需要有 `name: admin` 的 HTTP token）

| 端點 | 用途 |
|------|------|
| `GET /api/backup` | 下載 `usage.db` 快照（VACUUM INTO 保證一致性） |
| `POST /api/restore` | 上傳 `.db` 還原（integrity_check + schema 驗證 + os.replace 原子 swap） |
| `GET /api/users.csv` | 匯出用戶列表（含 token）為 CSV |

> **⚠️ 安全建議：不要建 admin 用戶。**
> admin token 若洩漏 = 整個 SQLite 可被下載（所有用戶 token + 用量歷史）。
> 這些操作都能用 SSH + docker exec 從 NAS 內部完成，SSH 本身已有金鑰認證 +
> port 33333 + docker user 無 sudo 的多層防護，比 HTTP admin token 安全。
>
> **實務：**
> - `config.yaml` 的 `users: [{name: admin, token: ...}]` 只是**檔案種子**，
>   實際 auth 走 SQLite `users` 表。SQLite 沒有 `name='admin'` 這筆時，
>   HTTP admin 功能等同停用（想用的人拿到 Unauthenticated）。
> - 要做備份 / 還原 / CSV 匯出 → 用下方「SSH 版本」指令（不需 HTTP token）。
>
> **SSH 等效指令：**
> ```bash
> # 備份（= /api/backup）
> ssh nas "/usr/local/bin/docker exec ai-proxy sqlite3 /app/data/usage.db \
>   '.backup /tmp/bk.db' && cat /tmp/bk.db" > local-backup.db
>
> # 還原（= /api/restore）
> scp -O -P 33333 -i ~/.ssh/id_ed25519_nas backup.db \
>   docker@192.168.0.126:/volume1/docker/proxy-cli/data/usage.db.new
> ssh nas "/usr/local/bin/docker exec ai-proxy sh -c \
>   'mv /app/data/usage.db.new /app/data/usage.db'"
> ssh nas "/usr/local/bin/docker restart ai-proxy"
>
> # CSV 匯出（= /api/users.csv）
> ssh nas "/usr/local/bin/docker exec ai-proxy sqlite3 -header -csv \
>   /app/data/usage.db 'SELECT * FROM users'" > users.csv
> ```

## 新的請求參數

### `effort`（Claude thinking budget，v3.1.0 SDK）

```python
from proxy import ai
# 簡單分類，降延遲 + 省成本
ai("這段程式碼有 bug 嗎？", effort="low", project="work-A", group="review")

# 標準（預設）
ai("寫一個 Python 排序函式", project="work-A", group="code")

# 深度推理
ai("證明分散式鎖的安全性與活性", effort="high", project="work-A", group="analysis")
```

Server 端映射到 Claude API 的 `thinking.budget_tokens`：
- `low` = 1024 tokens
- `medium` = 8192 tokens
- `high` = 32768 tokens

> **重要**：effort 設定時會**跳過 CLI 直接走 direct API**（CLI 不支援 thinking）。
> 需要在 dashboard 設定 `CLAUDE_API_KEY` 或 `ANTHROPIC_API_KEY` 才會生效，否則失敗 fallback 到下一個 provider。

### 智能路由（`routing.auto`）

`config.yaml` 中 `routing.auto: true` 開啟後，**client 沒指定 `model` 也沒指定 `tier`** 時，
server 依 prompt 自動分類：

| 訊號 | 分流 |
|------|------|
| 簡單關鍵字（yes/no、classify、是否）| `basic` → Haiku |
| 複雜關鍵字（step by step、推理、證明）| `best` → Opus |
| System prompt > 2000 字（agent 場景）| `best` |
| 含 ≥2 個程式碼區塊 | `good` → Sonnet |
| 總長度 < 200 | `basic` |
| 總長度 > 4000 | `best` |
| 其他 | `good` |

每次決策會寫入 `routing_decisions` 表，供未來 ML router 訓練用（`/api/routing-stats` 可查分層成效）。

## 觀測 / Prometheus

```bash
# 直接拉 metrics
ssh nas "curl -s http://localhost:8091/metrics"
```

輸出範例：
```
proxy_slots_healthy{provider="claude"} 3
proxy_slots_total{provider="claude"} 3
proxy_pool_idle{provider="claude"} 4
proxy_requests_total_24h 156
proxy_tokens_total_24h 98234
proxy_request_latency_ms{quantile="0.5"} 11090.0
proxy_request_latency_ms{quantile="0.95"} 51197.0
proxy_request_latency_ms{quantile="0.99"} 78000.0
```

Grafana 接法：Prometheus 設 scrape target `proxy-cli:8080/metrics`，或經 Nginx 反代 `clip.twloop.com/metrics`。

## 備份 / 還原

### Dashboard UI
開 clip.twloop.com → 左側「系統」→「資料庫備份」→ 下載 / 還原 按鈕
（首次會要 admin token）

### 命令列
```bash
# 備份（下載成 .db 檔）
curl -sL -o backup.db -H "Authorization: Bearer $ADMIN_TOKEN" \
    https://clip.twloop.com/api/backup

# 還原
curl -X POST -H "Authorization: Bearer $ADMIN_TOKEN" \
     -F "file=@backup.db" \
     https://clip.twloop.com/api/restore
```

還原流程：上傳 → 暫存檔 → `PRAGMA integrity_check` + schema 驗證 → 關閉現有連線 → `os.replace` 原子 swap → 重新 init。失敗會保留原 DB。

## 常見問題

### `Claude CLI 進入 stdin 互動模式`
- 原因：Claude CLI 認為需要互動式輸入（通常 auth 失效或版本問題）
- 錯誤類型 `cli_error`，會觸發 fallback chain
- **確認**：`config.yaml` 中 `openai.enabled: true`，fallback 會自動試 codex

> **⚠️ 陷阱 1**：`codex exec` 正常輸出也會有 `Reading additional input from stdin...`，
> 這**不是錯誤**。`_is_stdin_prompt_notice` 已限定只對 `provider == "claude"` 生效。
> 若日後改 stdin 偵測邏輯，務必保持此 provider 判斷。

> **⚠️ 陷阱 2**：`_parse_codex_output` 解析 JSON Lines：
> - 內容來自 `item.completed` 事件的 `item.text`（`type == "agent_message"`）
> - token 數來自 `turn.completed` 事件的**頂層** `usage`，不在 `turn` 裡面
> - codex 版本更新輸出格式時需同步更新

> **⚠️ 陷阱 3**：`/api/health` 的 `available: true` ≠ auth 有效。
> pool 初始化後 available 為 true，但憑證過期時實際請求仍 401。
> 確認 auth 真的可用：`echo test | claude --print`

### `/ready` 回 503
- 表示無 healthy slot（所有 provider 憑證都失效或 disabled）
- 查 `GET /api/health` 看每個 provider 的 `healthy_slots` 和 `auth_ok`
- 多半是 Claude token 過期 → 跑下面的重新登入流程

### Claude token 過期 → 重新登入

> **⚠️ 陷阱 4（歷史：`_patch_claude_creds` 已於 2026-04-19 刪除）**：
> 過去 Tokyo aapanel 上 `statsig.anthropic.com` 被 Cloudflare 封鎖，CLI 會誤報 "Not logged in"。
> 原本有 `_patch_claude_creds()` 自動補欄位，但這**等於偽造訂閱層級**，2026-04 實測導致帳號被封。
>
> **✅ 現在的處理方式**：
> - `creds_incomplete` 錯誤 → 直接降級為 `auth_expired`
> - Dashboard 顯示「憑證欄位缺失，請重登」紅燈
> - 使用者走 OAuth web flow（`clip.twloop.com` 側邊欄「登入 Claude」按鈕），新 token 覆蓋 slot-0
>
> **❌ 禁止**：不得補寫 `rateLimitTier` / `subscriptionType` / `organizationUuid` 等欄位，
> 不得呼叫 `api.anthropic.com/api/oauth/claude_cli/roles`。詳見專案倉庫 `CLAUDE.md`「ToS 灰區」。

**重新登入流程（容器內互動式，需終端機）**：
```bash
# 方法 1：Dashboard（推薦，最簡單）
# 開 https://clip.twloop.com → 側邊欄「登入 Claude」按鈕 → 瀏覽器 OAuth flow

# 方法 2：容器內 CLI 登入（方法 1 失效時）
ssh -t nas "/usr/local/bin/docker exec -it ai-proxy su app -c 'claude /login'"
# 完成後：
ssh nas "/usr/local/bin/docker restart ai-proxy"
```

**驗證新 token 可用**：
```bash
ssh nas "/usr/local/bin/docker exec ai-proxy bash -c 'HOME=/home/app claude --print --output-format json --model claude-haiku-4-5 \"hi\" 2>&1 | python3 -c \"import json,sys; print(json.load(sys.stdin).get(\\\"result\\\",\\\"\\\")[:60])\"'"
```

### 🔴 外網 gRPC 客戶端連不上 / RST_STREAM（NPM 需 grpc_pass，不是 proxy_pass）

**症狀：**
- 外網 gRPC 客戶端（e.g. Tokyo VPS 上的 agent-social）打 `cli.twloop.com:443` 收到 `RST_STREAM` / `INTERNAL_ERROR`
- 內網直連 `192.168.0.126:50051` 正常
- Dashboard（`clip.twloop.com`）HTTP 路徑也正常

**原因：**
NPM 預設用 `proxy_pass`（HTTP/1.1 & HTTP/2 一般 request），gRPC frame 會被當普通 HTTP/2 訊息處理 → 後端拒絕 → RST_STREAM。

**修法（NPM Admin UI，推薦）：**

1. 開 http://192.168.0.126:9081 （admin 帳號密碼登入）
2. Hosts → Proxy Hosts → 找到 `cli.twloop.com` → Edit
3. **Custom locations** tab → 新增一個 location 或改既有的：
   - Location: `/`
   - Scheme: **不要選 http/https，這裡要手刻**（NPM UI 沒有 grpc scheme 選項）
4. 切到 **Advanced** tab → **Custom Nginx Configuration** 貼入：

   ```nginx
   # gRPC 反代（HTTP/2 + gRPC frame 正確處理）
   location / {
       grpc_pass grpc://192.168.32.1:50051;   # 容器內網 IP，見下方註記
       grpc_read_timeout 300s;
       grpc_send_timeout 300s;
       error_page 502 = /error502grpc;
   }

   location = /error502grpc {
       internal;
       default_type application/grpc;
       add_header grpc-status 14;
       add_header content-length 0;
       return 204;
   }
   ```
5. **SSL** tab → 確認已發 Let's Encrypt 憑證、勾 **Force SSL**、勾 **HTTP/2 Support**
6. Save → NPM 會自動 reload nginx

**⚠️ 重要：`grpc://` 不是 `grpcs://`**
專案 `config.yaml` 的 `tls_enabled: false`，gRPC 伺服器明碼跑（NPM 端做 TLS 終止 + 明碼轉發給容器）。如果寫 `grpcs://` 會 handshake 失敗。

**Backend IP（`192.168.32.1`）怎麼確認：**
```bash
# 從 docker log 看容器訪問來源 IP（NPM 容器發出的）
ssh nas "/usr/local/bin/docker logs ai-proxy --tail 20 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u"
# 或查 docker 網路
ssh nas "/usr/local/bin/docker network inspect bridge | grep -A2 ai-proxy"
```
DSM 的 docker bridge 網段通常是 `192.168.32.0/20`，ai-proxy 容器常拿到 `192.168.32.X`。若 NPM 跟 ai-proxy 在**同一個 compose network**（`deploy-nas_default`）則可直接用 `ai-proxy:8080` 但 gRPC port 是 50051 不是 8080，且 NPM 容器不一定連到該網路 → 保險用 host network IP `192.168.32.1:50051`（host 側 port mapping）。

**驗證（本機 Mac）：**
```bash
# 用 grpcurl 測試外網 gRPC 連線
grpcurl -d '{}' cli.twloop.com:443 aiproxy.AIProxy/HealthCheck
# 預期：回傳 healthy 狀態 JSON
# 若回 RST_STREAM 或 "unexpected HTTP status code" → NPM 還沒生效
```

**為什麼 clip.twloop.com（HTTP dashboard）沒事？**
因為它是一般 HTTP/HTTPS，NPM 的 `proxy_pass` 處理得了。gRPC 才需要特殊 handling。

### 🔴 外網 `HealthCheck` 通但 `Complete` hang（多向量診斷法，2026-04-19 踩過）

**症狀：** 工程師從 Tokyo VPS 報 Bun + `@grpc/grpc-js`：
- HealthCheck ~200ms OK
- Complete 60s deadline exceeded，container log 沒有任何 Complete 進來的痕跡
- 同 token 同 VPS REST `/api/chat` 4s 正常

**第一反應 ≠ root cause**：不要急著改 NPM `grpc_pass` 配置或改 server trailer handling。大概率是 **client vantage 特有問題**（網路路徑、client lib 版本、MTU），不是 server 或 NPM bug。

**三向量測試**（用來切分責任）：

| 向量 | 指令 | 解讀 |
|---|---|---|
| A) 容器內 localhost | `docker exec ai-proxy python3 -c "...stub.Complete(...)"` | 通 → backend 沒問題 |
| B) Mac 外網 grpcurl | `grpcurl -d '{...}' -H "authorization: Bearer $T" cli.twloop.com:443 aiproxy.AIProxy/Complete` | 通 → NPM 沒問題 |
| C) 工程師 VPS grpcurl | 同上在他那台機跑 | 若這個也 hang → 100% 是他端網路 / MTU |

**A 和 B 都通 = NPM/backend 清白**，責任推回 client 端。

**client 端 checklist（給工程師）：**

1. **PMTU 黑洞**（Lightsail ↔ 台灣 IP 常見）：路徑中某跳 drop ICMP，大 DATA frame silent drop。小 response (HealthCheck) 通、大 response (Complete ~500 bytes 含 headers+trailers) 死。
   ```bash
   sudo ip route change default via <GW> dev <IF> advmss 1200
   # 或 sysctl net.ipv4.tcp_mtu_probing=1
   ```

2. **`@grpc/grpc-js` / Bun 版本**：我方驗證 Bun 1.3.11 + `@grpc/grpc-js` 1.10+ 都通。升最新試。

3. **Proto 同步**：對 MD5。v3.1 之後 `CompletionResponse` 新增 `actual_provider`/`actual_model` 兩欄。不同步不會 hang（forward-compat），但可以順便對。

4. **GRPC_TRACE debug**：`GRPC_TRACE=http,flowctl GRPC_VERBOSITY=DEBUG` 跑一次，看是 SETTINGS/WINDOW_UPDATE 之後死（flow control）還是 DATA frame 發不出（MTU）。

**千萬不要做的事：**
- 不要因為這個徵狀就去改 NPM `grpc_pass` 配置（前面別節已講解正確配置，再改也不會好）
- 不要改 `server.py` Complete handler 加 flush/trailer hack（handler 跟 HealthCheck 同 servicer class，代碼路徑只差一個 await）
- 不要降 deadline 或加 retry（根因是網路 drop，retry 只是把 timeout 變更久）

### 🔴 codex 每次 180s timeout / gemini refresh 寫入失敗（DSM ACL read-only bind mount）

**症狀：**
- `POST /api/chat` 指定 `provider=openai` 卡 ~180s 後 `curl: (28) Operation timed out`
- log 有 `failed to create session: Permission denied (os error 13)` on `/home/app/.codex/sessions`
- 或 `Permission denied: '/home/app/.gemini/oauth_creds.json'`（token refresh 寫回失敗）
- claude 可能正常（讀 token 就夠），但 long-term 也會因為 refresh 失敗壞掉

**根因：** Synology DSM 的 NFSv4 ACL。host 看起來 `drwxrwxrwx+`，但 bind mount 進容器後 `app` user 實際是 read-only。POSIX perm bits 騙人。

**一分鐘快檢：**
```bash
ssh nas "/usr/local/bin/docker exec -u app ai-proxy sh -c 'echo x > /home/app/.codex/test 2>&1'"
# "Permission denied" → 中招
```

**修法（已 commit 32d6d56）：** `entrypoint.sh` root 啟動時 `chmod -R u+w,g+w /home/app/.{claude,gemini,codex}`。重啟後即修復。

**臨時 hotfix（來不及 rebuild）：**
```bash
ssh nas "/usr/local/bin/docker exec -u root ai-proxy chmod -R u+w,g+w /home/app/.claude /home/app/.gemini /home/app/.codex"
```

### 🔴 hotfix 部署 src/*.py 後容器 crashloop（`PermissionError: '/app/src/*.py'`）

**症狀：** 用 `scp → docker cp` 熱更新 Python 檔（不走 rebuild）後容器起不來，log 連環出：
```
PermissionError: [Errno 13] Permission denied: '/app/src/server.py'
```

**根因：** DSM ACL 同一個坑的變形 — host 側 scp 出來的檔案 perms 是 `600`（只 root 讀），`docker cp` 進 image 時保留 600，app user 讀不到。entrypoint 的 chmod 只管 `/home/app/*` 不管 `/app/src`。

**修法：**
```bash
# 1. host 端先 chmod 644（關鍵！docker cp 會帶 perms 進去）
ssh nas "chmod 644 /volume1/docker/proxy-cli/src/*.py /volume1/docker/proxy-cli/proto/*.py"

# 2. stop → cp → chown → start
ssh nas "\
  /usr/local/bin/docker stop ai-proxy && \
  /usr/local/bin/docker start ai-proxy && sleep 3 && \
  /usr/local/bin/docker cp /volume1/docker/proxy-cli/src/server.py ai-proxy:/app/src/server.py && \
  /usr/local/bin/docker cp /volume1/docker/proxy-cli/src/dashboard.py ai-proxy:/app/src/dashboard.py && \
  /usr/local/bin/docker exec -u root ai-proxy sh -c 'chown -R app:app /app/src /app/proto && chmod -R u+r,g+r /app/src /app/proto' && \
  /usr/local/bin/docker restart ai-proxy"
```

**正規做法（日後 rebuild 就沒這問題）：** `docker compose -f deploy-nas/docker-compose.yml up -d --build`（Dockerfile 的 COPY + `chown -R app:app /app` 搞定）。熱更新只是 debug 加速手段，**不是生產流程**。

### 工程師回報「claude 過期時沒 fallback，錯誤直接回 client」

**症狀：** client 收到「claude 憑證已過期」，按理應 fallback 到其他 provider。

**先別改 fallback 邏輯 — 99% 是以下三種狀況之一：**

1. **Fallback chain 全部失效**：`execute_with_fallback` 流程是 CLI → direct API → project fallback_model → FALLBACK_CHAIN。若 chain 上所有 provider CLI 都壞（典型 = DSM ACL bug 那段時間 codex/gemini 都寫不了 session/token），且沒設對應的 API Key env var，chain 回 None，原 claude error 被退回 client。**不是 fallback 邏輯 bug**，是真的沒備援了。驗證：看 `/api/creds` 是否全綠。

2. **瞬時 race**：claude token 剛過期 → 先打到的 request 會走完 fallback，但同一秒內先撈到 `pool.available=True`（slot 還沒被 `mark_failed`）的 request 會走短路徑。回避：client 側保留 retry-once（engineer 已加）。

3. **設定錯**：`config.yaml` 或 env 沒給 fallback provider 可用憑證。`/api/creds` 看哪些 provider `healthy_slots=0`。

**code reference：**
- `src/pool.py:970` `execute_with_fallback` 主流程
- `src/pool.py:1086` `_try_fallback_chain` 跑 chain
- `src/pool.py:835` `FALLBACK_CHAIN` 順序

### 工程師回報「/api/recent 的 group 欄位空字串」

**不是 bug，欄位名稱看錯**。server 回的是 `group_name`（snake_case），不是 `group`。

驗證：
```bash
curl -s "http://192.168.0.126:8091/api/recent?limit=3&project=agent-social" -H "Authorization: Bearer $TOKEN" | python3 -m json.tool | grep group_name
# 預期看到 "group_name": "<value>"
```

SQLite 欄位也是 `group_name` 不是 `group`（`group` 是 SQL keyword 會衝突）。Client SDK 如果 typed 成 `r.group` 會永遠 undefined，改用 `r.group_name`。

### `actual_source` 欄位（2026-04-19 新增）

`CompletionResponse` / REST `/api/chat` response 都有 `actual_source: "cli" | "api" | "cache"`：

- `cli`：走 Claude Code / Gemini CLI / codex OAuth（免費額度，ToS 灰區）
- `api`：走付費 API Key（`ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / ...）
- `cache`：記憶體 prompt 快取命中（無實際 provider call）

Client 要分開計「免費 OAuth 流量 vs 付費 API 流量」就讀這欄。Commit 7015a1b。

### TLS 憑證快到期
啟動時 log 會顯示剩餘天數，`<30 天` warning、`<7 天` error：
```
TLS 憑證將在 15 天內到期 (2026-05-02T00:00:00+00:00)
```
更新憑證後 `docker restart ai-proxy`。

### Slot 被 quarantine（帳號風控訊號，2026-04-19 新增）

**症狀：** log 出現 `CRITICAL ... slot-N 被永久隔離（帳號風控訊號）`，或 dashboard Claude 風險卡片顯示 🔴 紅燈 + 錯誤訊息含「suspended」/「abuse」/「risk review」等字串。

**意義：** Anthropic backend 對該 OAuth 帳號發出風控訊號。再繼續用會觸發更嚴厲的封鎖（全面停權）。

**處理步驟：**
1. **不要急著清除 quarantine** — 先確認真的是誤判，還是 Anthropic 真的在查
2. 停止該帳號**至少 24 小時**（讓流量行為消失在 risk engine 的觀察窗口）
3. 檢查 `/api/recent?provider=claude` 看最近 24h 流量模式（是否超過 cap？有沒有異常 spike？）
4. 如確認是誤判，手動清除 quarantine：目前**無 dashboard UI，需直接操作容器**
   ```bash
   ssh nas "/usr/local/bin/docker restart ai-proxy"
   # 重啟會清掉記憶體中的 quarantined 狀態（但 risk 訊號會再來 = 沒根治）
   ```
5. 若持續觸發 → 換到 Anthropic 付費 API Key（`ANTHROPIC_API_KEY` env var，走 `_call_claude_apikey` ToS 合規路徑）

### Daily cap 被觸發

**症狀：** log 出現 `Provider claude 今日 Token 已達上限 (NNN/300000)`，dashboard 風險卡片顯示 🟡 或 🔴。

**意義：** 今日累積 Claude token 超過預設 300k cap（避免被 Anthropic 認定為異常使用）。流量會**自動 fallback** 到其他 provider（DeepSeek / OpenAI / Gemini），使用者應看得到回應。

**處理：**
- 若 cap 設太低：dashboard「配額」→ 新增 `target_type=provider, target_name=claude, daily_tokens=500000`（調高）
- 若 cap 合理但被異常流量吃光：查 `/api/recent?provider=claude&days=1` 看是誰在狂用
- 等午夜 UTC 00:00（台灣 08:00）counter 自動重置

## 讀取實際 provider / model

`CompletionResponse` 內建兩個欄位，不論請求是否指定 provider、是否觸發 fallback：

| 欄位 | 型別 | 說明 |
|------|------|------|
| `actual_provider` | string | 實際執行的 provider（fallback 後會不同於請求） |
| `actual_model` | string | 實際使用的模型 ID |

### Python SDK（use_proxycli）
```python
from proxy import ai_detail
result = ai_detail("用一句話介紹你自己", project="web-app", group="chatbot")
print(result["content"])
print(f"provider: {result['actual_provider']}")  # e.g. "openai"（fallback）
print(f"model:    {result['actual_model']}")     # e.g. "gpt-4o-mini"
```

### 直接用 gRPC（Python）
```python
import grpc, aiproxy_pb2 as pb, aiproxy_pb2_grpc as rpc

channel = grpc.insecure_channel("clip.twloop.com:50051")
stub = rpc.AIProxyStub(channel)
meta = [("authorization", "Bearer <token>")]

resp = stub.Complete(
    pb.CompletionRequest(
        prompt="用一句話介紹你自己",
        project="web-app",
        group="chatbot",         # v3.0.0 起必填
        # 不指定 provider，自動挑可用的
        # effort="low",          # 可選（Claude thinking）
    ),
    metadata=meta,
)
print(resp.content, resp.actual_provider, resp.actual_model)
```

### Node.js
```js
client.Complete(
  { prompt: "用一句話介紹你自己", project: "web-app", group: "chatbot", effort: "" },
  meta,
  (err, resp) => {
    if (err) return console.error(err.message);
    console.log(resp.content, resp.actual_provider, resp.actual_model);
  }
);
```

### TypeScript（型別參考）
```ts
interface CompletionResponse {
  content: string;
  input_tokens: number;
  output_tokens: number;
  tokens_estimated: boolean;
  latency_ms: number;
  actual_provider: string;   // fallback 時會與請求不同
  actual_model: string;
}
```

## 部署流程

### 快速部署（改程式碼）
```bash
cd /Users/macpro-david/Library/CloudStorage/Dropbox/84-WebCode/01-mac/1-info/proxy-cli

rsync -avz --rsync-path=/usr/bin/rsync \
  --exclude='.env' --exclude='__pycache__' --exclude='.git' \
  --exclude='*.pyc' --exclude='.DS_Store' --exclude='data/' --exclude='creds/' \
  --exclude='certs/' --exclude='*.log' --exclude='*.csv' \
  --exclude='.venv/' --exclude='.pytest_cache/' --exclude='.gstack/' \
  --exclude='.claude/' --exclude='deploy-aapanel/' \
  -e "ssh -p 33333 -i ~/.ssh/id_ed25519_nas -o StrictHostKeyChecking=no" \
  ./ docker@192.168.0.126:/volume1/docker/proxy-cli/ && \
ssh nas "cd /volume1/docker/proxy-cli && /usr/local/bin/docker compose -f deploy-nas/docker-compose.yml up -d --build"
```

⚠️ **必須用 `-f deploy-nas/docker-compose.yml`** — 專案根目錄的 `docker-compose.yml` 是 Mac 開發用（含 `cpus` 限制），NAS kernel 不支援 CPU CFS 會啟動失敗。

### 只更新 config.yaml（不重建）
```bash
scp -O -P 33333 -i ~/.ssh/id_ed25519_nas config.yaml docker@192.168.0.126:/volume1/docker/proxy-cli/config.yaml
ssh nas "/usr/local/bin/docker restart ai-proxy"
```

### 部署後驗證 checklist
```bash
# 1. 容器啟動
ssh nas "/usr/local/bin/docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep proxy"

# 2. Liveness + Readiness
ssh nas "curl -s http://localhost:8091/healthz && echo && curl -s http://localhost:8091/ready"

# 3. Provider 狀態
ssh nas "curl -s http://localhost:8091/api/health | python3 -c \"import json,sys; d=json.load(sys.stdin); print({k:v.get('healthy_slots',0) for k,v in d.items() if isinstance(v,dict) and 'healthy_slots' in v})\""

# 4. Metrics
ssh nas "curl -s http://localhost:8091/metrics | head -20"

# 5. Log（找 error / TLS warning）
ssh nas "/usr/local/bin/docker logs ai-proxy --tail 30 2>&1 | grep -iE 'tls|error|warn|ready'"

# 6. 資源消耗
ssh nas "/usr/local/bin/docker stats --no-stream ai-proxy --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'"

# 7. 🔴 外網 gRPC 實際連線（2026-04-19 新增 — 容易漏掉的驗收點）
# 從 Mac 本機（不是 NAS）測試：若 NPM 沒配 grpc_pass 會拿到 RST_STREAM
grpcurl -d '{}' cli.twloop.com:443 aiproxy.AIProxy/HealthCheck
# 預期：回傳 JSON；若錯誤 → 去 NPM UI 修 cli.twloop.com custom location 加 grpc_pass
# 詳見「常見問題 → 外網 gRPC 客戶端連不上 / RST_STREAM」
```

## 憑證管理

> **⚠️ 關鍵：必須用 `app` user 登入，不能用 root**
>
> 容器內服務以 `app` user 執行，憑證必須寫到 `/home/app/.claude/`。
> 用 root 登入會寫到 `/root/.claude/`，服務讀不到。

### 新增 / 重新登入憑證
```bash
# Claude
ssh -t nas "/usr/local/bin/docker exec -it ai-proxy su app -c 'claude /login'"

# Codex (OpenAI)
ssh -t nas "/usr/local/bin/docker exec -it ai-proxy su app -c 'codex login'"

# Gemini
ssh -t nas "/usr/local/bin/docker exec -it ai-proxy su app -c 'gemini auth login'"
```

### 確認憑證路徑
```bash
ssh nas "/usr/local/bin/docker exec ai-proxy ls -la /home/app/.claude/.credentials.json /home/app/.gemini/oauth_creds.json /home/app/.codex/auth.json"
```

### Slots（**多帳號輪替已於 2026-04-19 停用**）

⚠️ **ToS 合規**：本系統**只支援 slot-0 單帳號**。

- `~/.claude/slots/slot-N/` 下的憑證會被 load_slots 忽略，只會 log warning
- Dashboard 新增 slot API 回 403，UI 會隱藏「新增帳號」按鈕
- OAuth web flow 新帳號覆蓋 slot-0（相同 refresh_token 也更新 slot-0）
- SQLite restore 只還原 `slot_id=0`，其他 slot 跳過並 log

**遺留檔案清理**（從 aapanel 搬到 NAS 時可能有殘留 slot-1/slot-2）：
```bash
# docker 帳號無 rm 權限，需用 admin SSH 登入
ssh -p 33333 admin@192.168.0.126 "sudo rm -rf /volume1/docker/proxy-cli/creds/claude/slots /volume1/docker/proxy-cli/creds/gemini/slots"
```

### 從本機推送憑證（dashboard 無法互動式登入時）

**前置：** ssh-key 到 NAS（`ssh-copy-id -p 33333 admin@192.168.0.126`），並在 `~/.ssh/config` 加 alias：
```
Host nas
  HostName 192.168.0.126
  Port 33333
  User docker            # docker 帳號能寫 /volume1/docker/proxy-cli/creds/*（因 DSM ACL 開放 1000:1000）
  IdentityFile ~/.ssh/id_ed25519_nas
Host nas-admin           # sudo 操作用這個
  HostName 192.168.0.126
  Port 33333
  User admin
  IdentityFile ~/.ssh/id_ed25519_nas
```

**Claude（macOS）：** 憑證在 Keychain，不在檔案系統。直接 pipe 上 NAS：
```bash
security find-generic-password -s "Claude Code-credentials" -w | \
  ssh nas "cat > /volume1/docker/proxy-cli/creds/claude/.credentials.json"
```

**Claude（Linux）：** 走檔案路徑：
```bash
scp -O ~/.claude/.credentials.json nas:/volume1/docker/proxy-cli/creds/claude/.credentials.json
```

**Gemini：** 需要 3 個檔案：
```bash
scp -O ~/.gemini/oauth_creds.json ~/.gemini/google_accounts.json ~/.gemini/settings.json \
  nas:/volume1/docker/proxy-cli/creds/gemini/
```

**Codex：** 只要一個：
```bash
scp -O ~/.codex/auth.json nas:/volume1/docker/proxy-cli/creds/codex/auth.json
```

**重啟 + 驗證：**
```bash
ssh nas "/usr/local/bin/docker restart ai-proxy"
sleep 10
curl -s http://192.168.0.126:8091/api/creds | python3 -c "
import json,sys
d=json.load(sys.stdin)
for p in ['claude','gemini','openai']:
    v=d[p]; print(f'{p}: valid={v[\"valid\"]} healthy={v[\"healthy_slots\"]}/{v[\"total_slots\"]}')
"
```
預期 3 個都 `valid=True healthy=1/1`。

**⚠️ 推完憑證後務必端到端測一次**（只看 `/api/creds` 綠燈會漏掉 DSM ACL read-only 坑）：
```bash
TOKEN=<任一 user token>
for P in claude gemini openai; do
  case $P in claude) M=haiku;; gemini) M=gemini-2.5-flash;; openai) M=gpt-4o-mini;; esac
  curl -sS -X POST http://192.168.0.126:8091/api/chat \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"provider\":\"$P\",\"model\":\"$M\",\"prompt\":\"Say PONG\",\"max_tokens\":128,\"project\":\"_activation\"}" \
    --max-time 120
  echo
done
```
openai 卡 180s timeout → 看「codex 每次 180s timeout」那節。

## config.yaml 完整範本

```yaml
server:
  grpc_port: 50051
  dashboard_port: 8080
  tls_enabled: false
  tls_cert: certs/server.crt
  tls_key: certs/server.key

users:
- name: admin
  token: <admin-token>         # 備份/還原/CSV 匯出 需要的就是這個 token
- name: user1
  token: <user1-token>

projects:
- web-app
- data-pipeline

pool:
  min_size: 2                  # 目前未生效（保留）
  max_size: 4
  max_queue_depth: 10
  request_timeout: 60
  queue_timeout: 30            # 目前未生效（保留）
  # health_probe_interval: 已 deprecated（2026-04-19 ToS 合規：排程 probe 全部移除）
  # 保留 key 避免破壞舊 config，但系統不再讀取。
  race_mode: false             # true = 多 slot 並行競速（⚠️ 單 slot 政策下無意義，保留 flag 不會觸發）

routing:
  auto: false                  # true = client 未指定 model+tier 時依 prompt 自動分類

providers:
  claude:
    enabled: true              # false = 不初始化 pool
    command: claude
    fallback_model: claude-haiku-4-5
  gemini:
    enabled: true
    command: gemini
    fallback_model: gemini-2.5-flash
  openai:
    enabled: true              # 必須 true 才能用 codex fallback
    command: codex
    fallback_model: gpt-4o-mini

cache:
  max_size: 200
  ttl: 300                     # 秒

security:
  rate_limit_per_minute: 0     # 0 = 不限流
  max_tokens_per_request: 8192
```

## Dashboard UI 指引

左側邊欄（clip.twloop.com）：

| 區塊 | 功能 |
|------|------|
| **Claude 風險監控**（2026-04-19 新增） | 今日 token 累積 / 300k cap % + 🟢🟡🔴 紅綠燈 + 連續 3 日 > 200k 警告 banner（30s 刷新）|
| 認證管理 | OAuth 登入按鈕 / 手動上傳憑證（⚠️ 多 slot 功能已停用，新增按鈕已隱藏） |
| 專案 | 切換專案 scope，新增/刪除專案 |
| 系統 | 健康探測 + **資料庫備份**（需建立 admin 用戶才能用；推薦走 SSH 等效指令避免 HTTP token 洩漏風險） |
| 用戶 | 列表 + 新增 + **匯出 CSV（admin）** |
| API Key | 各 provider 的 API Key 設定 + 輪替策略（含 `ANTHROPIC_API_KEY`，啟用後 Claude direct API 走合規付費路徑）|
| 配額 | 用戶/專案級 daily token/request 上限（加上 provider-level cap，預設 claude 300k/day）|
| 模型 | 啟用/停用、per-project 指定 model、刷新 registry |

主內容區：
- 最近請求表支援**搜尋**（user/provider/status）+ **翻頁**（上/下頁按鈕）
- 用量 breakdown：按用戶 / 專案 / 小組 / 模型 / provider / 來源（CLI/API/cache）
- 延遲：avg + p50/p95/p99（來自 `/api/usage`）

## 工具鏈版本

- use_proxycli SDK：`v3.1.0`（`effort` 參數、`group` 必填）
- proto：含 `effort` field
- Dashboard：含備份/還原、搜尋/翻頁、CSV 匯出、智能路由統計
- Python：3.11-slim
- 核心依賴：`aiohttp 3.11`、`aiosqlite 0.20`、`grpcio 1.80`、`tiktoken 0.8`

## 查 log（常用 grep）

```bash
# 全部最新
ssh nas "/usr/local/bin/docker logs ai-proxy --tail 100"

# fallback / error / 授權 / slot 事件
ssh nas "/usr/local/bin/docker logs ai-proxy --tail 200 2>&1 | grep -iE 'fallback|error|warn|授權|slot'"

# auto-route 決策
ssh nas "/usr/local/bin/docker logs ai-proxy --tail 200 2>&1 | grep 'auto-route'"

# TLS 到期
ssh nas "/usr/local/bin/docker logs ai-proxy 2>&1 | grep -iE 'tls|憑證'"

# 最近 30 分鐘
ssh nas "/usr/local/bin/docker logs ai-proxy --since 30m"

# ToS 合規訊號（2026-04-19 新增）— 驗證部署後沒有 regression
# 應該沒有任何輸出
ssh nas "/usr/local/bin/docker logs ai-proxy 2>&1 | grep -iE '健康探測|patch_claude_creds|rateLimitTier'"

# Quarantine 事件（帳號風控訊號命中）
ssh nas "/usr/local/bin/docker logs ai-proxy 2>&1 | grep -iE '被永久隔離|quarantine|account_quarantine'"

# Daily cap 觸發
ssh nas "/usr/local/bin/docker logs ai-proxy 2>&1 | grep -iE 'daily_cap|今日 Token 已達上限|provider.*quota 查詢失敗'"

# 遺留 slot 清理提醒
ssh nas "/usr/local/bin/docker logs ai-proxy 2>&1 | grep -iE '遺留.*slot|ToS 政策忽略'"
```

## 自我更新規則（skill 維護）

**任何人使用此 skill 完成以下操作後，必須立即更新此檔案：**

1. **新增 provider** → 更新「Provider」表格
2. **移除或停用既有行為** → 在對應章節標註「已於 YYYY-MM-DD 刪除 / 停用」並留原因
3. **修改部署方式** → 更新「部署流程」章節
4. **新增 API endpoint** → 更新「API 端點速查」表格
5. **發現新的 ToS 紅旗行為** → 加到頂端「ToS 灰區」禁止清單
6. **Anthropic / Google 新增 telemetry / 錯誤訊息** → 更新 `_is_quarantine_error` keyword 清單

更新方式：直接用 Write 或 Edit 工具修改此檔案 `/Users/macpro-david/.claude/skills/hdw-proxycli/SKILL.md`
