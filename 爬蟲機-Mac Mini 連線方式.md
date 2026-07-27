# 爬蟲機（Mac Mini, David）— 連線方式

## 這台機器是什麼
2012 年 Mac Mini（i5-2415M / 3.9GB RAM / 507GB HDD），已重灌成 **Linux Mint 22.3 XFCE**，
專門用來跑各專案的資料爬蟲，24 小時開著、放在家裡（不用接螢幕鍵盤操作）。

## 連線方式

在**這台控制用的 Mac**（有裝這份文件、有設定過 SSH 別名的這台）上，終端機直接打：

```bash
ssh macmini
```

不用輸入密碼、不用打 IP——已經設定成 SSH 金鑰驗證 + 連線別名。

**細節**（正常不用管，除錯才需要看）：
- 帳號：`david`
- 目前 IP：`192.168.0.149`（區網位址，只有跟這台 Mac Mini 在同一個 Wi-Fi/路由器下的裝置能連到；如果換路由器或重開機後連不到，去 Mac Mini 螢幕前打 `hostname -I` 查新 IP，再更新下面這個設定檔）
- 連線別名設定在**這台控制電腦**的 `~/.ssh/config`：
  ```
  Host macmini
      HostName 192.168.0.149
      User david
      IdentityFile ~/.ssh/id_ed25519_macmini
      IdentitiesOnly yes
  ```
- 私鑰檔案：`~/.ssh/id_ed25519_macmini`（只存在這台控制電腦上，換一台電腦要連線就要重新產生金鑰、重新裝到 Mac Mini 的 `~/.ssh/authorized_keys`）
- 防火牆：Mac Mini 上開著 `ufw`，已放行 SSH（22 埠）

## 這台機器上的目錄慣例

```
~/crawlers/
  <專案名稱>/
    <資料源名稱>/
      fetch_xxx.py
      latest.json
    logs/
```

新增專案照這個規則分資料夾，不要把不同專案的爬蟲混在一起放。詳見 Mac Mini 上的 `~/crawlers/README.md`。

## 目前已部署的爬蟲

**havencircle 專案**：
- `~/crawlers/havencircle/ncdr/fetch_ncdr.py` — 抓 NCDR 民生示警平台（免申請、免 API Key），
  過濾出跟家庭安全相關的類別（火災、地震、颱風、淹水、土石流、豪雨、強風、高溫、停水、水庫放流等），
  輸出到同資料夾的 `latest.json`
- 已設定 **cron 每 5 分鐘自動執行一次**，log 寫在 `~/crawlers/havencircle/logs/ncdr.log`

**檢查爬蟲還活著**：
```bash
ssh macmini "tail -20 ~/crawlers/havencircle/logs/ncdr.log"
ssh macmini "cat ~/crawlers/havencircle/ncdr/latest.json"
```

## 安全備忘

- 密碼沒有寫在這份文件、也沒有寫在任何檔案裡——全部改用 SSH 金鑰驗證
- 這台機器只需要「連得出去抓資料」，不需要被外部連進來，所以沒有對外開放任何 port、沒有設定 Port Forwarding 或 Tunnel
