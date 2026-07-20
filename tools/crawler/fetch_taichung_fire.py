#!/usr/bin/env python3
"""台中市消防局「即時災情」爬蟲：抓 119 派遣清單中的火災事件。

角色：NCDR NFA_Fire 只給「重大/示警級」火災；台中消防局 caselist 給的是
每一件 119 派遣的秒級動態（NCDR 拿不到的顆粒度）。這支只取「案類＝火災」，
救護/勤務類（急病、創傷等個人醫療）刻意排除——既非鄰里安全事件，也涉個資。

資料來源：https://www.fire.taichung.gov.tw/caselist/index.asp?Parser=99,8,226
  純 HTML（UTF-8），每筆是一個 <li>，欄位是 <span class="list_word" data-th="…">值</span>。
  發生地點的 <button> 帶 js_addr="台中市X區…"（含縣市的完整地址）與 js_time，
  比刮自由文字乾淨，行政區直接從 js_addr 取。

去重：以（受理時間, 發生地點）為鍵，跨頁與跨次執行都不重複（seen.json 持久化）。
輸出 latest.json，並推送 Oracle（ingest.php?dataset=taichung_fire）。

純標準函式庫，無外部依賴（比照 fetch_ncdr.py）。任何一步失敗只印錯不 crash，
讓 cron 下次重試；本機檔案寫成功是基本盤，Oracle 波動不該讓整支失敗。
"""

import json
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

TZ_TAIPEI = timezone(timedelta(hours=8))

# caselist 頁；分頁參數是 Parser 值末端第 9 個位置的數字：99,8,226,,,,,,,,N
# （站方用 8 個空逗號占位再接頁碼；寫成 ,,N 會落在錯位置回傳空頁——已實測驗證）
BASE_URL = "https://www.fire.taichung.gov.tw/caselist/index.asp?Parser=99,8,226"
PAGE_SUFFIX = ",,,,,,,,{page}"
# 救護量遠大於火災，火災會很快被擠出第 1 頁；每次多掃幾頁再靠去重收斂，避免漏接
PAGES_PER_RUN = 6
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) HavenCircle-crawler/1.0"

# 只取家庭安全相關的案類。救護（急病/創傷/患者服務…）屬個人醫療，排除。
# 需要車禍時再加——車禍在此站是「案類＝緊急救護、案別＝車禍」，得另用案別判斷。
RELEVANT_CASE_TYPES = {"火災"}

OUTPUT_PATH = Path(__file__).parent / "latest.json"
SEEN_PATH = Path(__file__).parent / "seen.json"
# 去重記憶只保留近 3 天，避免 seen.json 無限膨脹
SEEN_TTL_DAYS = 3

INGEST_URL = "https://havencircle.looptw.com/crawler/api/ingest.php?dataset=taichung_fire"
INGEST_KEY_PATH = Path(__file__).parent / "ingest_key.txt"

# 每筆記錄的欄位。案別的 data-th 沒有全形冒號（站方 HTML 不一致），故容許冒號可有可無。
FIELD_RE = {
    "acceptedAt": r'data-th="受理時間："[^>]*>([^<]+)<',
    "caseType": r'data-th="案類："[^>]*>([^<]+)<',
    "caseSub": r'data-th="案別[："]?[^>]*>([^<]+)<',
    "unit": r'data-th="派遣分隊："[^>]*>([^<]+)<',
    "status": r'data-th="執行狀況："[^>]*>([^<]+)<',
}
# 發生地點取 button 的 js_addr（含縣市完整地址），比 span 內混雜的自由文字乾淨
ADDR_RE = re.compile(r'js_addr="([^"]+)"')
# 台中市各行政區都以「區」結尾（南屯區、霧峰區…）
DISTRICT_RE = re.compile(r"台中市([一-鿿]{1,3}區)")


def log(msg):
    ts = datetime.now(TZ_TAIPEI).strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


def fetch_page(page):
    url = BASE_URL + PAGE_SUFFIX.format(page=page)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=25) as resp:
        return resp.read().decode("utf-8", errors="replace")


def parse_records(html):
    """把每個 <li> 切出來，逐筆抽欄位。只回傳案類在白名單內的。"""
    records = []
    # 以 <li 為界切塊；跳過表頭（list_head，無 list_word）
    for chunk in re.split(r"<li\b", html):
        if "list_word" not in chunk:
            continue
        row = {}
        for key, pattern in FIELD_RE.items():
            m = re.search(pattern, chunk)
            row[key] = m.group(1).strip() if m else ""
        addr_m = ADDR_RE.search(chunk)
        row["location"] = addr_m.group(1).strip() if addr_m else ""
        if not row["acceptedAt"] or not row["caseType"]:
            continue
        if row["caseType"] not in RELEVANT_CASE_TYPES:
            continue
        dist_m = DISTRICT_RE.search(row["location"])
        row["district"] = dist_m.group(1) if dist_m else ""
        records.append(row)
    return records


def record_key(row):
    return f"{row['acceptedAt']}|{row['location']}"


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
    """失敗只警告不中斷：本機寫檔是基本盤，Oracle 波動不該讓 cron 整支失敗。"""
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

    all_records = []
    fetched_pages = 0
    for page in range(1, PAGES_PER_RUN + 1):
        try:
            html = fetch_page(page)
        except (urllib.error.URLError, TimeoutError) as e:
            log(f"[警告] 第 {page} 頁抓取失敗（略過）：{e}")
            continue
        fetched_pages += 1
        all_records.extend(parse_records(html))

    # 跨頁去重（同一筆火災可能同時出現在相鄰頁）
    uniq = {}
    for row in all_records:
        uniq[record_key(row)] = row

    fresh = [row for key, row in uniq.items() if key not in seen]
    for key in uniq:
        seen[key] = now_iso

    # 輸出「本次掃到的全部火災事件」（不只新的），讓 Oracle 端保有近況快照；
    # log 另報新增筆數，方便觀察站方更新頻率
    events = sorted(uniq.values(), key=lambda r: r["acceptedAt"], reverse=True)
    output = {
        "fetchedAt": now_iso,
        "source": "台中市消防局-即時災情",
        "caseTypes": sorted(RELEVANT_CASE_TYPES),
        "pagesScanned": fetched_pages,
        "events": events,
    }
    OUTPUT_PATH.write_text(
        json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    save_seen(seen)
    log(
        f"[完成] 掃 {fetched_pages}/{PAGES_PER_RUN} 頁，火災 {len(events)} 件"
        f"（本次新增 {len(fresh)} 件）→ {OUTPUT_PATH}"
    )
    push_to_oracle(output)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001 — cron 守門：任何未預期例外都印出而非讓排程靜默死掉
        log(f"[錯誤] 未預期例外：{e}")
        sys.exit(1)
