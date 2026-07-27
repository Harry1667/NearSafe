#!/usr/bin/env python3
"""內政部消防署「災情訊息」爬蟲：全國救災救護指揮中心即時發布的災情初(結)報。

角色：跟 fetch_taichung_fire.py（只有台中、只有火災）互補——這支涵蓋全台、
涵蓋火災／車禍／地震／瓦斯洩漏／山域事故等消防署會發布初報的所有案類，
是官方第一手（跟 NCDR 同等級的信任來源，非新聞轉述）。

資料來源：https://www.nfa.gov.tw/pro/index.php?code=list&ids=114
  純 HTML table，每列：標題（含分類/日期時間/地點/描述/狀態）、發布單位、發布時間（民國年）。
  標題格式範例：
    【住宅火災】【24日06:21臺中市南區光輝街住宅火災，已撲滅，無傷亡】初(結)報
    【地震】【23日06:19雲林縣政府南南東方11.1公里(雲林縣古坑鄉)發生芮氏規模3.5地震，無災情】初(結)報
  少數特殊公告（如「萬里溪堰塞湖」）沒有【】括號格式，視為無法解析的列直接略過，
  不勉強套格式硬解、避免解析出錯誤欄位。

去重：以（標題全文）為鍵，跨次執行不重複（seen.json 持久化，近 3 天）。
輸出 latest.json，並推送 Oracle（ingest.php?dataset=nfa）。

純標準函式庫，無外部依賴（比照 fetch_taichung_fire.py）。任何一步失敗只印錯不 crash，
讓 cron 下次重試；本機檔案寫成功是基本盤，Oracle 波動不該讓整支失敗。
"""

import hashlib
import json
import re
import ssl
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

TZ_TAIPEI = timezone(timedelta(hours=8))

SOURCE_URL = "https://www.nfa.gov.tw/pro/index.php?code=list&ids=114"
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) HavenCircle-crawler/1.0"

# nfa.gov.tw 伺服器本身憑證鏈不完整（缺中繼憑證），curl 用系統信任庫一樣驗證失敗，
# 已排除是本機信任庫問題——這是對方站台的既有設定問題，非我方風險。
# 這裡只放寬「這一個已知網域」的憑證驗證，不是全域關閉；抓的是公開災情公告頁，
# 唯讀、無憑證/個資交換，MITM 風險僅止於「有心人竄改公開災情文字」這種低價值攻擊面。
_NFA_UNVERIFIED_CONTEXT = ssl.create_default_context()
_NFA_UNVERIFIED_CONTEXT.check_hostname = False
_NFA_UNVERIFIED_CONTEXT.verify_mode = ssl.CERT_NONE

OUTPUT_PATH = Path(__file__).parent / "latest.json"
SEEN_PATH = Path(__file__).parent / "seen.json"
SEEN_TTL_DAYS = 3

INGEST_URL = "https://havencircle.looptw.com/crawler/api/ingest.php?dataset=nfa"
INGEST_KEY_PATH = Path(__file__).parent / "ingest_key.txt"

# 標題格式：【分類】【DD日HH:MM + 內容】狀態尾註（初(結)報／結報／初報，可能沒有）
TITLE_RE = re.compile(
    r"^\s*[​]?【(?P<category>[^】]+)】"
    r"【(?P<day>\d{1,2})日(?P<hm>\d{2}:\d{2})(?P<detail>.+)】"
    r"\s*(?P<statusTag>初\(結\)報|結報|初報)?\s*$"
)

# 縣市正規化：跟 fetch_news.py 同一份對照表（各腳本自成一體，不共用 import，比照既有慣例）
COUNTY_NORMALIZE = {
    "台北": "台北市", "臺北": "台北市", "新北": "新北市", "桃園": "桃園市",
    "台中": "台中市", "臺中": "台中市", "台南": "台南市", "臺南": "台南市",
    "高雄": "高雄市", "基隆": "基隆市",
    "新竹市": "新竹市", "新竹縣": "新竹縣", "新竹": "新竹市",
    "苗栗": "苗栗縣", "彰化": "彰化縣", "南投": "南投縣", "雲林": "雲林縣",
    "嘉義市": "嘉義市", "嘉義縣": "嘉義縣", "嘉義": "嘉義市",
    "屏東": "屏東縣", "宜蘭": "宜蘭縣", "花蓮": "花蓮縣",
    "台東": "台東縣", "臺東": "台東縣", "澎湖": "澎湖縣", "金門": "金門縣",
    "連江": "連江縣", "馬祖": "連江縣",
}
COUNTY_TOKENS = sorted(COUNTY_NORMALIZE.keys(), key=len, reverse=True)
# 前綴字元刻意排除「縣市區鄉鎮」這五個行政層級字——台灣的鄉鎮市區名稱本身
# 不會含這些字，這樣才不會把前面殘留的縣市字尾（「台中市」的「市」、
# 括號內重複出現的「雲林縣」）誤吃進下一個地名的比對範圍（實測踩過的 bug）。
DISTRICT_RE = re.compile(r"(?:(?![縣市區鄉鎮])[一-鿿]){1,3}(?:區|鄉|鎮|市)")

# 民國年「115-07-24」→ 西元 2026-07-24
ROC_DATE_RE = re.compile(r"^(\d{2,3})-(\d{2})-(\d{2})$")

# table 每列的三欄：標題(含連結或純文字)、發布單位、發布時間
ROW_RE = re.compile(
    r"<tr>\s*<td[^>]*>\s*(?:<a[^>]*>)?\s*(?P<title>[^<]+?)\s*(?:</a>)?\s*</td>"
    r"\s*<td[^>]*>\s*(?P<unit>[^<]*?)\s*</td>"
    r"\s*<td[^>]*>\s*(?P<pubdate>[^<]*?)\s*</td>\s*</tr>",
    re.DOTALL,
)


def log(msg):
    ts = datetime.now(TZ_TAIPEI).strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


def fetch_page():
    req = urllib.request.Request(SOURCE_URL, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=25, context=_NFA_UNVERIFIED_CONTEXT) as resp:
        return resp.read().decode("utf-8", errors="replace")


def county_from_text(text):
    """回傳 (縣市正規化名稱, 該 token 在原文的結束位置)；找不到回 (None, 0)。
    結束位置供 district_from_text 從縣市名「之後」才開始找鄉鎮區，
    避免縣市名自己的「市」字尾被 district 正規式重複吃掉（見下方 bug 說明）。
    """
    best_pos, best_token = None, None
    for token in COUNTY_TOKENS:
        pos = text.find(token)
        if pos == -1:
            continue
        if best_pos is None or pos < best_pos:
            best_pos, best_token = pos, token
    if best_token is None:
        return None, 0
    return COUNTY_NORMALIZE[best_token], best_pos + len(best_token)


def district_from_text(text, search_from):
    """只在縣市名結束位置之後找鄉鎮市區，避免「台中市」的「市」被誤判成 district
    （之前的 bug：district 正規式從字串開頭掃，比對到縣市名本身）。
    DISTRICT_RE 全部是非捕獲群組（見定義處排除縣市區鄉鎮字元的說明），用 group(0)。"""
    m = DISTRICT_RE.search(text, pos=search_from)
    return m.group(0) if m else ""


def roc_to_iso_date(pubdate_text):
    """「115-07-24」→ (2026, 7, 24)；解析失敗回 None，呼叫端退回抓取當下日期。"""
    m = ROC_DATE_RE.match(pubdate_text.strip())
    if not m:
        return None
    roc_year, month, day = m.groups()
    return int(roc_year) + 1911, int(month), int(day)


def build_occurred_at(pubdate_text, title_day, title_hm):
    """
    標題只給「幾號幾點」（無月份），發布時間欄給民國年月日——用發布時間的年月，
    標題的日＋時分組出完整時間。發布時間解析失敗就用抓取當下時間打底（不讓整筆掉資料）。
    """
    parsed = roc_to_iso_date(pubdate_text)
    now = datetime.now(TZ_TAIPEI)
    year, month = (parsed[0], parsed[1]) if parsed else (now.year, now.month)
    try:
        hour, minute = (int(part) for part in title_hm.split(":", 1))
    except (AttributeError, TypeError, ValueError):
        hour, minute = now.hour, now.minute
    try:
        dt = datetime(year, month, title_day, hour, minute, tzinfo=TZ_TAIPEI)
    except ValueError:
        # 標題日期跨月（例如月底案件、發布時間已跨到下月）——退回發布時間全部三個欄位
        if parsed:
            dt = datetime(parsed[0], parsed[1], parsed[2], hour, minute, tzinfo=TZ_TAIPEI)
        else:
            dt = now
    # 標題日 > 發布時間日超過一週：極可能是「跨月」（發布時間是次月初，標題日是上月底），
    # 月份往前推一個月修正
    if parsed and title_day > parsed[2] + 7:
        month_back = month - 1 if month > 1 else 12
        year_back = year if month > 1 else year - 1
        try:
            dt = datetime(year_back, month_back, title_day, hour, minute, tzinfo=TZ_TAIPEI)
        except ValueError:
            pass
    return dt


def parse_records(html):
    records = []
    for m in ROW_RE.finditer(html):
        raw_title = m.group("title").strip()
        unit = m.group("unit").strip()
        pubdate = m.group("pubdate").strip()
        if not raw_title or raw_title in ("標題",):  # 跳過表頭列
            continue
        title_m = TITLE_RE.match(raw_title)
        if not title_m:
            # 無法解析格式（如「萬里溪堰塞湖」這類純文字公告）——略過不硬解，
            # 避免把不明結構的內容錯誤標成某個分類或某個地點
            continue
        category = title_m.group("category").strip()
        detail = title_m.group("detail").strip().lstrip("，,")
        day = int(title_m.group("day"))
        hm = title_m.group("hm")
        county, county_end = county_from_text(detail)
        district = district_from_text(detail, county_end)
        occurred_at = build_occurred_at(pubdate, day, hm)
        status_tag = title_m.group("statusTag") or ""
        is_resolved = status_tag in ("結報", "初(結)報") or any(
            kw in detail for kw in ("已撲滅", "已獲救", "完成止漏", "無災情", "順利救出")
        )
        records.append({
            "id": record_id(raw_title),
            "title": raw_title,
            "category": category,
            "detail": detail,
            "county": county,
            "district": district,
            "unit": unit,
            "occurredAt": occurred_at.isoformat(),
            "isResolved": is_resolved,
            "statusTag": status_tag,
        })
    return records


def record_id(title):
    """公開穩定 ID：供 App 去重；不包含人名、地址以外的新資訊。"""
    return hashlib.sha1(title.encode("utf-8")).hexdigest()[:16]


def record_key(row):
    return row.get("id") or record_id(row["title"])


def load_seen():
    if not SEEN_PATH.exists():
        return {}
    try:
        return json.loads(SEEN_PATH.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}


def save_seen(seen):
    cutoff = (datetime.now(TZ_TAIPEI) - timedelta(days=SEEN_TTL_DAYS)).isoformat()
    pruned = {k: v for k, v in seen.items() if v >= cutoff}
    SEEN_PATH.write_text(json.dumps(pruned, ensure_ascii=False), encoding="utf-8")


def push_to_oracle(output):
    if not INGEST_KEY_PATH.exists():
        log(f"[警告] 找不到 {INGEST_KEY_PATH.name}，跳過推送 Oracle")
        return
    key = INGEST_KEY_PATH.read_text(encoding="utf-8").strip()
    body = json.dumps(output, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        INGEST_URL,
        data=body,
        headers={"Content-Type": "application/json", "X-Ingest-Key": key},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            log(f"[推送] Oracle 已接收：{resp.read().decode('utf-8')}")
    except urllib.error.URLError as e:
        log(f"[警告] 推送 Oracle 失敗（不中斷）：{e}")


def main():
    seen = load_seen()
    now_iso = datetime.now(TZ_TAIPEI).isoformat()

    try:
        html = fetch_page()
    except (urllib.error.URLError, TimeoutError) as e:
        log(f"[警告] 抓取失敗：{e}")
        return

    records = parse_records(html)
    fresh = [r for r in records if record_key(r) not in seen]
    for r in records:
        seen[record_key(r)] = now_iso

    output = {
        "fetchedAt": now_iso,
        "source": "內政部消防署-全國災情訊息",
        "sourceUrl": SOURCE_URL,
        "events": records,
    }
    OUTPUT_PATH.write_text(
        json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    save_seen(seen)
    log(f"[完成] 解析 {len(records)} 件（本次新增 {len(fresh)} 件）→ {OUTPUT_PATH}")
    push_to_oracle(output)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001
        log(f"[錯誤] 未預期例外：{e}")
        sys.exit(1)
