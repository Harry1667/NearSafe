#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fetch_news.py — 「安心圈」新聞重大事故爬蟲

用途：
    在官方示警（NCDR）之外，用新聞 RSS 補「事發到官方發布」的時間差。
    產出的事件只進 App 的「持續確認中」信任層（trust = media-report，永不推播），
    每則事件都帶清楚的來源標示（sourceName + sourceURL）。

設計慣例（與既有 NCDR 爬蟲相同）：
    - Python 3 純標準函式庫，不裝任何 pip 套件
    - 例外：LLM 分類走 ProxyCLI REST API（urllib 呼叫）；
      token 從環境變數 AI_PROXY_TOKEN 讀，沒有 token 自動退回規則式分類，絕不 crash
    - 單一 feed 失敗記 log 後繼續跑其他 feed，不 silent fail
    - 建議由 cron 每 15 分鐘跑一次（各 feed ttl 皆 <= 15 分鐘，不會過度抓取）

輸出：
    latest.json — 本次新發現的事故事件（UTF-8、ensure_ascii=False）
    seen.json   — 已處理過的 item id（滾動上限 2000 筆），重跑不重複產出
"""

import difflib
import email.utils
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone, timedelta

# ---------------------------------------------------------------------------
# 基本設定
# ---------------------------------------------------------------------------

# 台北時區（爬蟲機可能是 UTC，所有時間戳統一 +08:00）
TZ_TAIPEI = timezone(timedelta(hours=8))

# 抓取用 User-Agent（部分新聞站會擋預設的 Python-urllib）
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
)

# 抓取逾時（秒）
FETCH_TIMEOUT = 20

# LLM（ProxyCLI）設定：token 由環境變數提供，沒有就走純規則路徑
AI_PROXY_URL = "http://cli.twloop.com:8080/api/chat"
AI_PROXY_TOKEN = os.environ.get("AI_PROXY_TOKEN", "").strip()
AI_PROXY_PROJECT = os.environ.get("AI_PROXY_PROJECT", "harry-HavenCircle").strip()

# ProxyCLI gRPC SDK（把 proxy.py＋aiproxy_pb2*.py 放進同目錄即自動啟用）。
# 實測 REST 8080 從外部連不到（防火牆），gRPC 443/TLS 才是通的路；
# SDK 缺檔或缺 grpcio 時自動退回 REST，再不行退規則分類，絕不 crash。
try:
    from proxy import ai as _sdk_ai
except Exception:
    _sdk_ai = None
LLM_TIMEOUT = 30
LLM_MIN_CONFIDENCE = 0.6  # LLM 信心低於此值 → 丟棄 LLM 結果、退回規則結果

# seen.json 滾動上限
SEEN_MAX = 2000

# 資料來源（皆為 RSS 2.0，已實測存活）
FEEDS = [
    {"name": "中央社", "feed": "社會", "url": "https://feeds.feedburner.com/rsscna/social"},
    {"name": "中央社", "feed": "地方", "url": "https://feeds.feedburner.com/rsscna/local"},
    {"name": "自由時報", "feed": "社會", "url": "https://news.ltn.com.tw/rss/society.xml"},
    {"name": "ETtoday", "feed": "社會", "url": "https://feeds.feedburner.com/ettoday/society"},
]

# ---------------------------------------------------------------------------
# 分類詞庫（第一段：規則式，永遠執行）
# ---------------------------------------------------------------------------

# 排除詞：司法後續、政治攻防、追悼紀念——這些不是「進行中的現場事故」。
# 注意：只比對「標題」。事故報導的內文常出現「依公共危險罪嫌起訴」之類字眼，
# 若連內文一起排除會誤殺大量真事故。
EXCLUDE_WORDS = [
    # 司法流程
    "判決", "判刑", "判處", "宣判", "判賠", "求刑", "起訴", "定讞", "上訴",
    "偵結", "收押", "羈押", "交保", "抗告", "緩刑", "開庭", "聲請", "二審", "三審",
    # 政治與輿論後續
    "彈劾", "質詢", "民調", "罷免",
    # 追悼紀念
    "追思", "紀念", "告別式", "公祭",
]

# 納入詞：依 App 分類（火災/交通/天災/公共安全/民生）分組，
# 依序比對，第一個命中的組別即為 category。
# 比對範圍：標題＋描述（描述常補足標題沒寫的事故詞）。
INCLUDE_CATEGORIES = [
    ("火災", ["火警", "火災", "失火", "起火", "縱火", "爆炸", "氣爆", "閃燃"]),
    ("交通", ["車禍", "追撞", "自撞", "對撞", "擦撞", "翻覆", "翻車", "酒駕",
              "逆向", "撞", "出軌", "落軌", "墜機", "迫降", "連環撞"]),
    ("天災", ["淹水", "地震", "土石流", "落石", "山崩", "走山", "斷橋",
              "暴雨", "豪雨", "溢流", "潰堤", "海嘯"]),
    ("民生", ["停電", "斷電", "停水", "斷水", "跳電", "瓦斯外洩"]),
    ("公共安全", ["坍塌", "倒塌", "崩塌", "溺水", "溺斃", "墜樓", "墜谷", "墜落",
                  "砍", "刺傷", "傷人", "槍擊", "開槍", "挾持", "隨機",
                  "外洩", "毒氣", "命案", "失蹤", "尋獲", "疏散", "封閉",
                  "警戒", "爆裂物", "鬥毆", "襲擊"]),
]

# 誤判防護：這些較短的納入詞若出現在下列慣用語中，不算命中
# （例：「撞名」「砍價」不是事故）
FALSE_HIT_GUARDS = {
    "撞": ["撞名", "撞臉", "撞衫", "撞期", "撞色"],
    "砍": ["砍價", "砍單", "砍預算", "砍半", "砍掉重練"],
    "封閉": ["封閉式", "封閉性"],
}

# ---------------------------------------------------------------------------
# 縣市正規化（電頭與標題抽取共用）
# ---------------------------------------------------------------------------

# key = 電頭/標題可能出現的地名 token，value = 正規化縣市名
# 比對時依 key 長度由長到短（「新竹市」要先於「新竹」命中）
COUNTY_NORMALIZE = {
    "台北": "台北市", "臺北": "台北市",
    "新北": "新北市",
    "桃園": "桃園市",
    "台中": "台中市", "臺中": "台中市",
    "台南": "台南市", "臺南": "台南市",
    "高雄": "高雄市",
    "基隆": "基隆市",
    "新竹市": "新竹市", "新竹縣": "新竹縣", "新竹": "新竹市",
    "苗栗": "苗栗縣",
    "彰化": "彰化縣",
    "南投": "南投縣",
    "雲林": "雲林縣",
    "嘉義市": "嘉義市", "嘉義縣": "嘉義縣", "嘉義": "嘉義市",
    "屏東": "屏東縣",
    "宜蘭": "宜蘭縣",
    "花蓮": "花蓮縣",
    "台東": "台東縣", "臺東": "台東縣",
    "澎湖": "澎湖縣",
    "金門": "金門縣",
    "連江": "連江縣", "馬祖": "連江縣",
}
# 由長到短排序的 token 清單（供 endswith / 掃描使用）
COUNTY_TOKENS = sorted(COUNTY_NORMALIZE.keys(), key=len, reverse=True)

# 中央社電頭格式：「（中央社記者王淑芬高雄16日電）」或「（中央社台北16日電）」
# 抽出「記者名（可無）＋地名」到「N日」之間的片段，再用縣市 token 從尾端比對
CNA_DATELINE_RE = re.compile(r"[（(]中央社(?:記者)?([^）)]{0,30}?)(\d{1,2})日[^）)]{0,15}?電[）)]")


def log(msg):
    """統一 log 格式（stderr，帶台北時間戳），cron 可導向 log 檔"""
    ts = datetime.now(TZ_TAIPEI).strftime("%Y-%m-%d %H:%M:%S")
    print("[{}] {}".format(ts, msg), file=sys.stderr)


# ---------------------------------------------------------------------------
# 抓取與解析
# ---------------------------------------------------------------------------

def fetch_url(url, timeout=FETCH_TIMEOUT):
    """抓取 URL，回傳 bytes；失敗丟例外（由呼叫端決定要不要繼續）"""
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def strip_html(text):
    """去掉描述裡的 HTML 標籤與多餘空白（自由時報/ETtoday 描述常夾 <img> 等）"""
    text = re.sub(r"<[^>]+>", " ", text or "")
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def parse_rss(data):
    """
    解析 RSS 2.0，回傳 item 的 dict 清單。
    CDATA 由 ElementTree 自動處理（自由時報 title 是 CDATA 也沒問題）。
    """
    root = ET.fromstring(data)
    items = []
    for item in root.iter("item"):
        def text_of(tag):
            node = item.find(tag)
            return (node.text or "").strip() if node is not None and node.text else ""

        items.append({
            "title": strip_html(text_of("title")),
            "description": strip_html(text_of("description")),
            "link": text_of("link"),
            "guid": text_of("guid"),
            "pubDate": text_of("pubDate"),
        })
    return items


def stable_id(item):
    """以 guid（優先）或 link 產生穩定雜湊 id"""
    key = item.get("guid") or item.get("link") or item.get("title", "")
    return hashlib.sha1(key.encode("utf-8")).hexdigest()[:16]


def parse_pubdate(s):
    """RFC 822 pubDate → ISO8601（台北時區）；解析失敗就用現在時間"""
    try:
        dt = email.utils.parsedate_to_datetime(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=TZ_TAIPEI)
        return dt.astimezone(TZ_TAIPEI).isoformat()
    except Exception:
        return datetime.now(TZ_TAIPEI).isoformat()


# ---------------------------------------------------------------------------
# 縣市抽取
# ---------------------------------------------------------------------------

def county_from_cna_dateline(description):
    """
    從中央社電頭抽縣市（規則路徑的金礦）。
    例：「（中央社記者王淑芬高雄16日電）」→ 片段「王淑芬高雄」→ 尾端命中「高雄」→ 高雄市
    """
    m = CNA_DATELINE_RE.search(description or "")
    if not m:
        return None
    fragment = m.group(1)  # 記者名（可無）＋地名
    for token in COUNTY_TOKENS:  # 長 token 優先（新竹市 > 新竹）
        if fragment.endswith(token):
            return COUNTY_NORMALIZE[token]
    return None


def county_from_text(text):
    """
    從標題/描述掃縣市 token（非中央社來源的退路）。
    取最靠前的命中；同位置長 token 優先。
    """
    best_pos, best_token = None, None
    for token in COUNTY_TOKENS:
        pos = (text or "").find(token)
        if pos == -1:
            continue
        if best_pos is None or pos < best_pos:
            best_pos, best_token = pos, token
    return COUNTY_NORMALIZE[best_token] if best_token else None


# ---------------------------------------------------------------------------
# 第一段：規則式分類（永遠執行）
# ---------------------------------------------------------------------------

def rules_classify(title, description):
    """
    回傳 (是否事故, category, 命中詞)。
    - 排除詞只看標題（內文常出現「起訴」等字眼，看內文會誤殺真事故）
    - 納入詞看標題＋描述
    """
    for word in EXCLUDE_WORDS:
        if word in title:
            return False, None, word

    haystack = title + " " + description
    for category, words in INCLUDE_CATEGORIES:
        for word in words:
            if word not in haystack:
                continue
            # 誤判防護：命中的若全是慣用語（撞名/砍價…）就不算
            guards = FALSE_HIT_GUARDS.get(word)
            if guards:
                stripped = haystack
                for g in guards:
                    stripped = stripped.replace(g, "")
                if word not in stripped:
                    continue
            return True, category, word

    return False, None, None


# ---------------------------------------------------------------------------
# 第二段：LLM 分類（有 AI_PROXY_TOKEN 才跑）
# ---------------------------------------------------------------------------

LLM_PROMPT_TEMPLATE = """你是災害事故新聞分類器。判斷下面這則台灣新聞是否為「正在發生或剛發生的現場事故/災害」（司法判決、起訴、政治攻防、紀念活動都不算）。

標題：{title}
描述：{description}

只回覆一行 JSON，不要任何其他文字，格式：
{{"is_incident": true或false, "county": "縣市全名（如 台中市）或null", "district": "鄉鎮市區或null", "place": "地點簡述或null", "category": "火災|交通|天災|公共安全|民生 其中之一", "confidence": 0到1的數字}}"""


def call_proxy_llm(prompt):
    """
    呼叫 ProxyCLI 取得純文字回應：優先 gRPC SDK（443/TLS），沒有 SDK 才走 REST。
    任何錯誤都丟例外，由呼叫端 fallback 到規則結果（不 crash、不 silent fail）。
    """
    if _sdk_ai is not None:
        return _sdk_ai(
            prompt,
            provider="claude",
            model="claude-haiku-4-5",
            project=AI_PROXY_PROJECT,
            group="news-crawler",  # ProxyCLI 必填欄位，儀表板依此分項統計用量
        )
    body = json.dumps({
        "prompt": prompt,
        "provider": "claude",
        "model": "claude-haiku-4-5",
    }).encode("utf-8")
    req = urllib.request.Request(
        AI_PROXY_URL,
        data=body,
        headers={
            "Authorization": "Bearer " + AI_PROXY_TOKEN,
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=LLM_TIMEOUT) as resp:
        raw = resp.read().decode("utf-8", errors="replace")

    # 回應可能是 JSON 包裝（content/response/text…其中一個 key），也可能直接是文字
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict):
            for key in ("content", "response", "message", "text", "result", "answer", "output"):
                val = parsed.get(key)
                if isinstance(val, str) and val.strip():
                    return val
            # dict 但找不到已知 key → 原樣回傳字串讓上層試著抽 JSON
            return raw
        if isinstance(parsed, str):
            return parsed
    except (ValueError, TypeError):
        pass
    return raw


def llm_classify(title, description):
    """
    對規則通過的單則新聞問 LLM。
    回傳解析成功且 confidence >= 門檻的 dict；否則回 None（上層退回規則結果）。
    """
    prompt = LLM_PROMPT_TEMPLATE.format(title=title, description=description)
    try:
        answer = call_proxy_llm(prompt)
    except Exception as e:
        log("LLM 呼叫失敗（退回規則結果）：{}".format(e))
        return None

    # 從回應中抽第一段 {...}（LLM 偶爾會多話）
    m = re.search(r"\{.*\}", answer, re.DOTALL)
    if not m:
        log("LLM 回應無 JSON（退回規則結果）：{}".format(answer[:120]))
        return None
    try:
        result = json.loads(m.group(0))
    except ValueError:
        log("LLM JSON 解析失敗（退回規則結果）：{}".format(m.group(0)[:120]))
        return None

    if not isinstance(result, dict) or "is_incident" not in result:
        log("LLM 回應缺少 is_incident（退回規則結果）")
        return None

    try:
        confidence = float(result.get("confidence") or 0)
    except (TypeError, ValueError):
        confidence = 0.0
    if confidence < LLM_MIN_CONFIDENCE:
        log("LLM confidence {} < {}（退回規則結果）".format(confidence, LLM_MIN_CONFIDENCE))
        return None

    result["confidence"] = confidence
    # county 若非 null 也順手正規化（LLM 可能回「台中」而非「台中市」）
    county = result.get("county")
    if isinstance(county, str) and county:
        for token in COUNTY_TOKENS:
            if county.startswith(token):
                result["county"] = COUNTY_NORMALIZE[token]
                break
    else:
        result["county"] = None
    valid_categories = {c for c, _ in INCLUDE_CATEGORIES}
    if result.get("category") not in valid_categories:
        return None  # 分類不在白名單 → 不可信，退回規則
    return result


# ---------------------------------------------------------------------------
# 去重
# ---------------------------------------------------------------------------

def normalize_title(title):
    """標題正規化：去掉標點、空白、全形符號，只留中英數字，供跨來源比對"""
    return re.sub(r"[^\w一-鿿]+", "", title or "").lower()


def find_duplicate(event, accepted):
    """
    跨來源找同一事件：正規化標題「前 12 字相同」或 difflib ratio > 0.6。
    回傳命中的既有 event，找不到回 None。
    """
    norm_new = normalize_title(event["title"])
    for old in accepted:
        norm_old = normalize_title(old["title"])
        if norm_new[:12] and norm_new[:12] == norm_old[:12]:
            return old
        if difflib.SequenceMatcher(None, norm_new, norm_old).ratio() > 0.6:
            return old
    return None


def merge_duplicate(existing, new_event):
    """合併重複事件：corroboration +1、來源名串接（看得出多來源）、補缺欄位"""
    existing["corroboration"] += 1
    names = [n.strip() for n in existing["sourceName"].split("、")]
    if new_event["sourceName"] not in names:
        existing["sourceName"] = existing["sourceName"] + "、" + new_event["sourceName"]
    # 既有欄位缺值時，用新來源的值補上（縣市/地點越齊越好）
    for key in ("county", "district", "place"):
        if not existing.get(key) and new_event.get(key):
            existing[key] = new_event[key]


# ---------------------------------------------------------------------------
# 狀態檔（seen.json）
# ---------------------------------------------------------------------------

def load_seen(path):
    """讀已處理 id 清單；檔案不存在或壞掉都回空（壞掉要記 log）"""
    if not os.path.exists(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        ids = data.get("ids", [])
        return ids if isinstance(ids, list) else []
    except (ValueError, OSError) as e:
        log("seen.json 讀取失敗（視為全新狀態）：{}".format(e))
        return []


def save_seen(path, ids):
    """存已處理 id，滾動只留最後 SEEN_MAX 筆"""
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"ids": ids[-SEEN_MAX:]}, f, ensure_ascii=False)


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

def main(feeds=None, out_dir=None):
    feeds = feeds if feeds is not None else FEEDS
    out_dir = out_dir or os.path.dirname(os.path.abspath(__file__))
    latest_path = os.path.join(out_dir, "latest.json")
    seen_path = os.path.join(out_dir, "seen.json")

    use_llm = bool(AI_PROXY_TOKEN)
    log("啟動：LLM 分類 {}（AI_PROXY_TOKEN {}）".format(
        "開啟" if use_llm else "關閉，走純規則路徑",
        "已設定" if use_llm else "未設定"))

    seen_ids = load_seen(seen_path)
    seen_set = set(seen_ids)

    sources_report = []
    events = []
    total_fetched = 0
    skipped_seen = 0
    dropped_by_rules = 0
    dropped_by_llm = 0

    for feed in feeds:
        # 單一 feed 失敗：記 log、標 ok=false，繼續跑其他 feed
        try:
            data = fetch_url(feed["url"])
            items = parse_rss(data)
        except Exception as e:
            log("feed 抓取/解析失敗（跳過此 feed）：{} {} — {}".format(
                feed["name"], feed["feed"], e))
            sources_report.append({
                "name": feed["name"], "feed": feed["feed"], "url": feed["url"],
                "ok": False, "items": 0, "error": str(e),
            })
            continue

        sources_report.append({
            "name": feed["name"], "feed": feed["feed"], "url": feed["url"],
            "ok": True, "items": len(items),
        })
        total_fetched += len(items)
        log("feed OK：{} {} — {} 則".format(feed["name"], feed["feed"], len(items)))

        for item in items:
            item_id = stable_id(item)
            if item_id in seen_set:
                skipped_seen += 1
                continue
            # 無論後續是否採用，都記為已處理（重跑不重複產出、也不重複問 LLM）
            seen_set.add(item_id)
            seen_ids.append(item_id)

            title, description = item["title"], item["description"]

            # 第一段：規則式（永遠執行）
            is_incident, category, hit_word = rules_classify(title, description)
            if not is_incident:
                dropped_by_rules += 1
                continue

            # 規則路徑的縣市：中央社電頭優先，其次掃標題
            county = county_from_cna_dateline(description) or county_from_text(title)

            event = {
                "id": item_id,
                "title": title,
                "publishedAt": parse_pubdate(item["pubDate"]),
                "sourceName": feed["name"],
                "sourceURL": item["link"],
                "county": county,
                "district": None,
                "place": None,
                "category": category,
                "confidence": 0.5,          # 規則路徑的預設信心值
                "extraction": "rules",
                "trust": "media-report",    # 媒體報導層：只進「持續確認中」，永不推播
                "corroboration": 1,
            }

            # 第二段：LLM（有 token 才跑；失敗/低信心 → 保留規則結果）
            if use_llm:
                llm = llm_classify(title, description)
                if llm is not None:
                    if not llm.get("is_incident"):
                        dropped_by_llm += 1
                        continue
                    event.update({
                        "county": llm.get("county") or county,
                        "district": llm.get("district") or None,
                        "place": llm.get("place") or None,
                        "category": llm["category"],
                        "confidence": llm["confidence"],
                        "extraction": "llm",
                    })

            # 跨來源去重：同一事件合併、corroboration +1
            dup = find_duplicate(event, events)
            if dup is not None:
                merge_duplicate(dup, event)
                log("合併重複事件：「{}」({}) → 「{}」".format(
                    title[:20], feed["name"], dup["title"][:20]))
            else:
                events.append(event)

    # 輸出 latest.json
    output = {
        "fetchedAt": datetime.now(TZ_TAIPEI).isoformat(),
        "sources": sources_report,
        "totalFetched": total_fetched,
        "skippedSeen": skipped_seen,
        "incidentCount": len(events),
        "droppedByRules": dropped_by_rules,
        "droppedByLLM": dropped_by_llm,
        "events": events,
    }
    with open(latest_path, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
    save_seen(seen_path, seen_ids)

    log("完成：抓 {} 則（略過已見 {}）→ 事故 {} 則｜規則排除 {}｜LLM 排除 {}".format(
        total_fetched, skipped_seen, len(events), dropped_by_rules, dropped_by_llm))
    log("輸出：{}".format(latest_path))

    # 全部 feed 都掛才算失敗（exit code 給 cron 監控用）
    all_failed = bool(feeds) and all(not s["ok"] for s in sources_report)
    return 1 if all_failed else 0


if __name__ == "__main__":
    sys.exit(main())
