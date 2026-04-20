這是一份為 AI Agent 定製的 **「全鏈路基礎設施架構圖 (April 2026)」**。

它整合了你的 **Cloudflare DNS 層**、**Nginx 代理層** 與 **後端服務層**。你可以將這段 Markdown 內容存入任何 AI 的知識庫，它看完後就能精準判斷該如何幫你建置新網站，而不會搞混 Port 或路徑。

## ⚠️ AI 協作須知（給 AI 看的）

1. **使用者不會寫代碼**。所有指令、設定檔、程式碼都必須寫到可以直接複製貼上的程度。
2. **回覆用繁體中文**。
3. **每一步都要說清楚在哪裡操作**（aaPanel 後台 / SSH 終端 / Cloudflare / 本機終端）。
4. **本文件底部有敏感資訊（密碼、SSH key、GitHub token），絕對不要在回覆中引用或顯示這些內容。**
5. **如果需要伺服器資訊**，給使用者可以複製的終端指令，讓他貼回結果。不要猜測。
6. **這個檔案不可以上傳git**

---

# 🌐 looptw.com 全鏈路基礎設施架構 (AI Memory Module)

## 1. 外部流量層 (Edge & DNS)
- **服務商**: Cloudflare
- **解析模式**: **DNS Only (灰色小雲朵)**
  - *注意：目前 SSL 由伺服器端的 aaPanel Nginx (Let's Encrypt) 處理，非 Cloudflare Proxy。*
- **主域名**: `looptw.com` (IP: `137.131.7.230`)
- **子域名清單**:
  - `mentora.looptw.com` -> 伺服器入口
  - `mathbox.looptw.com` -> 伺服器入口
  - `survivalwallet.looptw.com` -> 伺服器入口
  - `zhijian.looptw.com` -> 伺服器入口

## 2. 伺服器核心規格 (Origin Server)
- **環境**: Ubuntu 24.04.4 LTS (Noble Numbat), Kernel 6.17.0-1007-oracle, ARM64 (aarch64)
- **面板**: aaPanel 8.0.1
- **入口**: Nginx 1.24.0 (with HTTP/2, Stream SSL, Lua, Cache Purge modules)
- **OpenSSL**: 1.1.1w
- **後端管理**: PM2 (Node.js) / PHP-FPM (PHP)
- **PHP**: 8.3.30 (NTS), 含 sqlite3, pdo_sqlite, curl, gd, mbstring, openssl, zip
- **PHP-FPM Socket**: `/tmp/php-cgi-83.sock`
- **Nginx PHP 設定**: `include enable-php-83.conf;` (自動處理 `*.php` → `/tmp/php-cgi-83.sock`)
- **磁碟**: 193GB 總容量, 181GB 可用 (7% 使用率)
- **記憶體**: 11% 使用率
- **檔案擁有者**: 所有 web 檔案必須是 `www:www`

## 3. 專案路由與門牌號碼 (Internal Routing Map)


| 域名 (Domain) | 內部路徑 (Root Path) | 類型 | 內部 Port | 進程名稱 (PM2) |
| :--- | :--- | :--- | :--- | :--- |
| `mentora.looptw.com` | `/www/wwwroot/mentora.looptw.com/02-web` | Next.js | **3000** | `mentora-web` |
| `mathbox.looptw.com` | `/www/wwwroot/mathbox.looptw.com/02-web` | Node ESM | **3001** | `mathbox-web` |
| `survivalwallet.looptw.com` | `/www/wwwroot/survivalwallet.looptw.com` | React SPA + PHP API | **N/A** | N/A (PHP-FPM) |

## 4. AI 部署自動化指令集 (Agent Deployment SOP)

### A. 若要新增 Node.js 專案
1. **Port 分配**: 必須檢查現有 Port，下一個預設為 **3002**。
2. **PM2 啟動**: `PORT=[PORT] pm2 start server.mjs --name [name]`。
3. **Nginx 轉發設定**:
   ```nginx
   location / {
       proxy_pass http://127.0.0.1:[PORT];
       proxy_http_version 1.1;
       proxy_set_header Upgrade $http_upgrade;
       proxy_set_header Connection "upgrade";
       proxy_set_header Host $host;
   }
   ```

### B. 若要新增 SPA/PHP 專案
1. **aaPanel 建站**: 添加站點 → 域名填子域名 → PHP 選 8.3。
2. **Nginx 路由**: 配置文件中加入 `try_files $uri $uri/ /index.html;` (解決 React/Vue Router 重新整理 404)。
3. **PHP 處理**: aaPanel 預設的 `include enable-php-83.conf;` 已涵蓋，不需額外設定 `location ~ \.php`。
4. **WASM 支援**: 如果專案用了 `.wasm` 檔案（如 sql.js），需在 Nginx 加：
   ```nginx
   location ~ \.wasm$ {
       types { application/wasm wasm; }
       expires 30d;
   }
   ```
5. **資料庫目錄保護**: 如果有 SQLite 資料庫：
   ```nginx
   location /database {
       deny all;
       return 404;
   }
   ```
6. **權限設定**: `chown -R www:www [path]`。
7. **SSL**: DNS A 記錄指向 `137.131.7.230` 後，在 aaPanel → SSL → Let's Encrypt 申請。

## 5. 已知環境限制 (Critical Constraints)
- **隱藏檔清理**: 部署前必須清除 Mac 生成的二進位垃圾檔：`find . -name "._*" -delete`。
- **SSL 協議**: 全站強制 HTTPS，由 aaPanel Let's Encrypt 管理。新站必須先設好 DNS A 記錄才能申請。
- **SSL 申請限流**: Let's Encrypt 連續失敗 5 次後需等 1 小時才能重試。
- **API 驗證**: SurvivalWallet 的 `api.php` 裡的 `$PASSWORD` 必須跟前端 `.env` 的 `VITE_SYNC_TOKEN` 一致。
- **ARM 相容性**: 機器為 ARM64，部分需編譯的 C++ Addons 需確保有 ARM 版本。
- **Node.js**: 透過 aaPanel 安裝，在 SSH 終端直接打 `node` 會找不到。需要用 aaPanel 的 Node 管理介面或 PM2。
- **Cloudflare DNS**: 目前用 DNS Only 模式（灰色雲朵），SSL 由伺服器端處理。如果切成橘色雲朵（Proxy），SSL 設定會衝突。
- **Nginx 配置注意**: `include enable-php-83.conf;` 是一個 location block，不能再嵌套在另一個 `location` 裡面，否則 Nginx 會報錯。

---

## 6. 已驗證的完整 Nginx 配置範本 (SPA + PHP API)

以下是 SurvivalWallet 實際使用的配置，可作為未來 SPA 專案的範本：

```nginx
server
{
    listen 80;
    server_name [DOMAIN];
    index index.php index.html index.htm default.php default.htm default.html;
    root /www/wwwroot/[DOMAIN];

    # aaPanel 自動產生的區塊（不要刪）
    include /www/server/panel/vhost/nginx/well-known/[DOMAIN].conf;
    include enable-php-83.conf;
    include /www/server/panel/vhost/rewrite/[DOMAIN].conf;

    # SPA fallback
    location / {
        try_files $uri $uri/ /index.html;
    }

    # 禁止存取敏感檔案
    location ~ ^/(\.user.ini|\.htaccess|\.git|\.env|\.svn) {
        return 404;
    }

    # 禁止存取資料庫目錄
    location /database {
        deny all;
        return 404;
    }

    # Service Worker 不快取
    location = /sw.js {
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        expires off;
    }

    # WASM MIME type
    location ~ \.wasm$ {
        types { application/wasm wasm; }
        expires 30d;
    }

    # 靜態資源快取
    location ~ .*\.(gif|jpg|jpeg|png|bmp|swf|svg)$ {
        expires 30d;
    }
    location ~ .*\.(js|css)?$ {
        expires 12h;
    }

    access_log /www/wwwlogs/[DOMAIN].log;
    error_log /www/wwwlogs/[DOMAIN].error.log;
}
```

---

## 7. Cloudflare DNS 操作步驟（新增子域名時必做）

1. 登入 https://dash.cloudflare.com
2. 點選 `looptw.com`
3. 左邊選「DNS」→「記錄」
4. 點「新增記錄」
5. 填入：
   - 類型：`A`
   - 名稱：填子域名前綴（例如 `survivalwallet`）
   - IPv4 位址：`137.131.7.230`
   - Proxy 狀態：**關閉**（灰色雲朵，DNS Only）
   - TTL：自動
6. 點「儲存」
7. 等 1-5 分鐘 DNS 生效後，再去 aaPanel 申請 SSL

> ⚠️ 不要開橘色雲朵（Cloudflare Proxy），否則 SSL 會跟伺服器端的 Let's Encrypt 衝突。

---

## 8. 故障排除（常見問題）

### 網站打開是白畫面或 404
- 檢查 Nginx 有沒有加 `try_files $uri $uri/ /index.html;`
- 檢查 `index.html` 是不是在網站根目錄（不要多包一層資料夾）

### 資料重新整理後消失
- 檢查 `api.php` 的 `$PASSWORD` 跟前端 `VITE_SYNC_TOKEN` 是否一致
- SSH 進伺服器檢查：`ls -la /www/wwwroot/[DOMAIN]/database/`
  - 如果 database 目錄不存在或沒有 `.sqlite` 檔案 → 權限問題
  - 執行：`chown -R www:www /www/wwwroot/[DOMAIN]/database/`

### SSL 申請失敗
- 先確認 DNS A 記錄已加且生效：`ping [DOMAIN]` 看 IP 是不是 `137.131.7.230`
- Let's Encrypt 失敗 5 次後要等 1 小時才能重試
- 確認 Cloudflare 是灰色雲朵（DNS Only）

### Nginx 儲存報錯
- 最常見原因：`include enable-php-83.conf;` 被放進了另一個 `location` 區塊裡面
- 這個 include 本身就是一個 location block，不能嵌套
- 把它放在 server 層級（跟其他 location 平行），不要放進任何 location 裡面

### PHP api.php 回傳 404 或空白
- 確認 aaPanel 的站點有選 PHP 8.3
- 確認 Nginx 配置有 `include enable-php-83.conf;`
- 在瀏覽器直接打開 `http://[DOMAIN]/api.php?action=load`
  - 看到「未授權」→ PHP 正常，密碼驗證有在跑
  - 看到空白或 404 → PHP 沒有被執行

---

## 9. 新專案部署檢查清單

每次建新網站，照這個順序打勾：

- [ ] Cloudflare 加 A 記錄（灰色雲朵）
- [ ] aaPanel 添加站點（選 PHP 8.3）
- [ ] 上傳檔案到網站根目錄
- [ ] 修改 Nginx 配置（複製第 6 節範本，改 [DOMAIN]）
- [ ] Nginx 儲存成功（沒有紅色報錯）
- [ ] 如果有 api.php → 確認 `$PASSWORD` 跟前端一致
- [ ] 如果有 database 目錄 → `chown -R www:www database/`
- [ ] `ping [DOMAIN]` 確認 DNS 生效
- [ ] aaPanel → SSL → Let's Encrypt 申請
- [ ] 瀏覽器打開 `https://[DOMAIN]` 確認正常
- [ ] 手機打開測試

---

**Last Synced**: 2026-04-09
**Status**: 穩定運行中 (Mentora, MathBox, SurvivalWallet)

---

### 💡 如何使用這個檔案？
下次你開啟一個新的 AI 對話時，直接把這段貼給它並說：
> 「這是我目前的伺服器與 Cloudflare 架構記憶檔，請根據這個結構幫我規劃新專案 [專案名稱] 的部署步驟。」

---

## 🔒 敏感資訊（以下內容禁止 AI 在回覆中引用或顯示）

aapanal:登入網址： https://137.131.7.230:19262/31ff8ce4
帳號： opoenmit
密碼： a1259a47


進入伺服器：
ssh -i ~/Documents/important\ file/ssh-key-2026-04-08.key ubuntu@137.131.7.230
sudo su


github key：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



