# 新聞重大事故爬蟲（news-crawler）

> 此目錄是舊版備份，已停止部署。正式版本與測試位於
> `tools/crawler/fetch_news.py`、`tools/crawler/test_fetch_news.py`；
> 請勿從本目錄覆蓋 Mac Mini。

「安心圈」的媒體報導資料線。在官方示警（NCDR）之外，用新聞 RSS 補「事發到官方發布」的時間差。

## 與 NCDR 爬蟲的關係（信任分層）

| 資料線 | 信任層 | 推播 | 說明 |
|---|---|---|---|
| NCDR 爬蟲 | 官方層 | 可推播 | 政府正式示警，權威來源 |
| **本爬蟲（新聞）** | **持續確認中層** | **永不推播** | 媒體報導，速度快但未經官方確認；每則必帶來源標示 |

新聞事件只作為地圖/清單上的「持續確認中」參考資訊，`trust` 欄位固定為 `media-report`，App 端據此決定呈現方式與是否禁止推播。

## 運作方式

1. 抓 4 個 RSS 來源（中央社社會/地方、自由時報社會、ETtoday 社會），單一 feed 失敗記 log 繼續跑其他 feed
2. **第一段：規則式分類（永遠執行）**
   - 排除詞（只比對標題）：判決/判刑/起訴/定讞/收押/羈押/交保/開庭/彈劾/質詢/追思… → 司法與政治後續直接丟棄
   - 納入詞（比對標題＋描述）：火警/爆炸/車禍/追撞/淹水/墜樓/槍擊/停電/地震… 至少命中一個才算事故
   - 縣市抽取：中央社電頭「（中央社記者XXX**高雄**16日電）」regex 抽地名，正規化成縣市名；非中央社來源掃標題
3. **第二段：LLM 分類（有 `AI_PROXY_TOKEN` 才跑）**
   - 對規則通過者逐則呼叫 ProxyCLI（claude-haiku-4-5），要求只回一行 JSON
   - 回傳解析失敗、confidence < 0.6、或 category 不在白名單 → 丟棄 LLM 結果、退回規則結果（`extraction: "rules"`）
   - 沒有 token / API 掛掉：自動退回純規則路徑，**絕不 crash**
4. 去重：同 id 不重複（`seen.json` 滾動 2000 筆）；跨來源用標題正規化後「前 12 字相同或 difflib ratio > 0.6」合併，合併時 `corroboration` +1、`sourceName` 以頓號串接保留全部來源

## 輸出檔案

### `latest.json`（本次新發現的事件）

| 欄位 | 意義 |
|---|---|
| `fetchedAt` | 本次抓取時間（ISO8601，台北時區） |
| `sources[]` | 每個 feed 的抓取結果：`name`/`feed`/`url`/`ok`/`items`，失敗時多一個 `error` |
| `totalFetched` | 本次各 feed 解析出的總則數 |
| `skippedSeen` | 已在 seen.json、直接略過的則數 |
| `incidentCount` | 判定為事故的事件數（去重合併後） |
| `droppedByRules` / `droppedByLLM` | 被規則 / 被 LLM 排除的則數 |
| `events[].id` | guid（優先）或 link 的 SHA-1 前 16 碼，穩定雜湊 |
| `events[].title` / `publishedAt` | 標題、發布時間（ISO8601） |
| `events[].sourceName` | 來源媒體名；多來源合併時以「、」串接（例：`中央社、ETtoday`） |
| `events[].sourceURL` | 文章原始連結（**App 端必須顯示來源標示**） |
| `events[].county` / `district` / `place` | 縣市（正規化全名）/ 鄉鎮市區 / 地點描述；抽不到為 null。規則路徑通常只有 county |
| `events[].category` | 火災｜交通｜天災｜公共安全｜民生 |
| `events[].confidence` | LLM 信心值（0–1）；規則路徑固定 0.5 |
| `events[].extraction` | `llm` 或 `rules`（此則欄位的抽取方式） |
| `events[].trust` | 固定 `media-report`（持續確認中層，永不推播） |
| `events[].corroboration` | 報導此事件的來源數（≥2 表示多家媒體交叉印證） |

### `seen.json`（狀態檔）

已處理過的 item id 清單，滾動上限 2000 筆。重跑不重複產出事件、也不重複燒 LLM 額度。**每次跑完 `latest.json` 只含「新」事件**，下游（上傳/合併服務）要自行累積。

## 本機測試

```bash
cd "/Volumes/ADATA 256GB/0-Dev/person-work/3-AppDev/iosaicamp/HavenCircle/tools/news-crawler"
python3 fetch_news.py            # 無 token → 純規則路徑
rm -f seen.json                  # 想重測時清掉狀態檔
```

## 部署到爬蟲機（Linux Mint）——2026-07-16 已完成，以下是實際佈署紀錄

> LLM 走 **ProxyCLI gRPC SDK（cli.twloop.com:443/TLS）**，不是 REST——
> 實測 REST 8080 從外部連不到（防火牆）。REST 程式路徑保留作備援。

1. 檔案（`~/crawlers/havencircle/news/`）：`fetch_news.py` ＋ SDK 三件套
   `proxy.py`、`aiproxy_pb2.py`、`aiproxy_pb2_grpc.py`（取自 use_proxycli/）。

2. 依賴：pb2 檔需要 protobuf ≥ 5.27，apt 版太舊，用目錄內 venv：

   ```bash
   sudo apt-get install -y python3-venv   # ensurepip
   python3 -m venv .venv && .venv/bin/pip install grpcio protobuf
   # 簡轉繁兜底（LLM 摘要偶爾冒簡體字，prompt 押不住，用 OpenCC 機械轉換保險）
   .venv/bin/pip install opencc-python-reimplemented
   ```

3. token 放 `.env`（chmod 600，內容 `export AI_PROXY_TOKEN=…` 與
   `export AI_PROXY_PROJECT=harry-HavenCircle`）。沒 token 也能跑，
   只是走純規則路徑、抽不出 district/place。
   注意：ProxyCLI 的 `group` 為必填，程式內已固定送 `news-crawler`。

4. cron 每 15 分鐘（已掛）。`flock -n` 防止首輪全量 LLM 長跑（7 分鐘以上）
   與下一輪重疊；穩態每輪只處理新增則數，數十秒內結束：

   ```cron
   */15 * * * * cd ~/crawlers/havencircle/news && flock -n .lock -c ". ./.env && .venv/bin/python3 fetch_news.py" >> ~/crawlers/havencircle/logs/news.log 2>&1
   ```

5. 產出的 `latest.json` 交給後續上傳/合併流程（與 NCDR 爬蟲同機、同慣例）。exit code：全部 feed 都掛才回 1，可供監控。

首跑驗證（2026-07-16）：130 則 → 事故 30 則，其中 25 則 LLM 抽取
（confidence 0.95+、含鄉鎮層級），county 空白由規則路徑的 11 降到 3，
LLM 另補殺 1 則規則誤放。

## 已知限制

- 排除詞只看標題：標題沒有司法詞的後續報導（如「無照酒駕欠罰款11萬…繳清」）會漏進來，靠 LLM 段補殺；純規則路徑會有少量此類誤放
- 規則路徑 `confidence` 固定 0.5、`district`/`place` 為 null，縣市靠中央社電頭與標題掃描，非中央社且標題無地名的事件 county 會是 null
- 娛樂圈車禍等「真事故但新聞價值偏八卦」的項目規則路徑不會排除（它確實是事故）
