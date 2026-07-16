#!/usr/bin/env python3
"""NCDR 民生示警爬蟲 v2：官方查詢 API 為主，公開 Atom feed 為備援。

主路徑（需 api_key.txt）：
  datastore 取即時清單 → 按 capCode 白名單過濾 → dump 逐筆取完整內容（JSON，
  含 instruction 應變指引與行政區 geocode，資料比公開 feed 的 CAP XML 更完整）。
備援路徑：官方 API 任何一步失敗 → 退回 v1 的公開 feed + CAP XML 流程。

輸出 latest.json（格式與 v1 相容，events 多了 instruction 欄位），並推送 Oracle。
"""

import json
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path

API_BASE = "https://alerts.ncdr.nat.gov.tw/api"
API_KEY_PATH = Path(__file__).parent / "api_key.txt"

FEED_URL = "https://alerts.ncdr.nat.gov.tw/JSONAtomFeeds.ashx"
OUTPUT_PATH = Path(__file__).parent / "latest.json"
CAP_NS = {"cap": "urn:oasis:names:tc:emergency:cap:1.2"}

INGEST_URL = "https://havencircle.looptw.com/crawler/api/ingest.php"
INGEST_KEY_PATH = Path(__file__).parent / "ingest_key.txt"

# capCode 白名單（官方 /api/dataset 代碼表，2026-07-16 取得）。
# 原 13 類中文白名單的對應代碼，加上對家庭安全明顯有價值的新類別。
RELEVANT_CAPCODES = {
    "TY": "颱風", "EQ": "地震", "EQF": "地震速報", "TS": "海嘯",
    "FL": "淹水", "DF": "土石流", "RA": "豪雨", "th": "雷雨",
    "SW": "強風", "htW": "高溫", "CS": "低溫",
    "HW": "河川高水位", "RD": "水庫放流", "floodDiversion": "分洪警報",
    "barrierLake": "堰塞湖警戒",
    "Fire": "火災", "evacuation": "疏散避難", "AR": "防空", "nuclear": "輻射災害",
    "TPE_water": "停水", "TWC_water": "停水", "electric": "電力中斷",
    "Mobiles": "行動電話中斷", "CM": "傳染病", "WSC": "停班停課",
}

# v1 的中文白名單（備援路徑用）
RELEVANT_CATEGORIES = {
    "颱風", "地震", "海嘯", "淹水", "土石流",
    "火災", "豪雨", "強風", "高溫", "停水",
    "水庫放流", "行動電話中斷", "傳染病",
}


# ---------- 官方 API 主路徑 ----------

def api_get(path, **params):
    key = API_KEY_PATH.read_text(encoding="utf-8").strip()
    params["apikey"] = key
    params["format"] = "json"
    url = f"{API_BASE}/{path}?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=20) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_via_api():
    """回傳 (events, total_in_feed, skipped, duplicate)"""
    listing = api_get("datastore", limit=300)
    if not listing.get("success"):
        raise RuntimeError(f"datastore 回傳 success=false：{str(listing)[:200]}")
    items = listing.get("result") or []

    events = []
    skipped = 0
    seen = set()
    duplicates = 0
    for item in items:
        code = item.get("capCode")
        if code not in RELEVANT_CAPCODES:
            skipped += 1
            continue
        capid = item.get("capid")
        if not capid:
            continue
        if capid in seen:
            duplicates += 1
            continue
        seen.add(capid)

        try:
            dump = api_get("dump/datastore", capid=capid)
        except Exception as ex:
            print(f"[警告] dump 失敗 {capid}：{ex}", file=sys.stderr)
            continue

        info_list = dump.get("info") or []
        if not info_list:
            continue
        # 取 zh-TW 的 info（多語系示警會有多個 info 區塊）
        info = next((i for i in info_list if i.get("language") == "zh-TW"), info_list[0])

        areas = info.get("area") or []
        area_desc = "、".join(a.get("areaDesc", "") for a in areas if a.get("areaDesc"))
        circle = next((a.get("circle") for a in areas if a.get("circle")), "") or ""
        polygon = next((a.get("polygon") for a in areas if a.get("polygon")), "") or ""

        events.append({
            "identifier": dump.get("identifier") or capid,
            "sender": dump.get("sender"),
            "event": info.get("event"),
            "urgency": info.get("urgency"),
            "severity": info.get("severity"),
            "certainty": info.get("certainty"),
            # 用 info 層的時間（帶 +08:00 時區），datastore 清單層的沒有時區、App 端解析會失敗
            "effective": info.get("effective"),
            "expires": info.get("expires"),
            "senderName": info.get("senderName"),
            "headline": info.get("headline"),
            "description": info.get("description"),
            "instruction": info.get("instruction"),
            "areaDesc": area_desc,
            "circle": circle,
            "polygon": polygon,
            "category": RELEVANT_CAPCODES[code],
            "feedId": capid,
        })
    return events, len(items), skipped, duplicates


# ---------- 公開 feed 備援路徑（v1 原邏輯） ----------

def fetch_feed():
    with urllib.request.urlopen(FEED_URL, timeout=15) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_cap(url):
    with urllib.request.urlopen(url, timeout=15) as resp:
        return resp.read()


def parse_cap(xml_bytes):
    root = ET.fromstring(xml_bytes)
    info = root.find("cap:info", CAP_NS)
    if info is None:
        return None
    area = info.find("cap:area", CAP_NS)
    area_desc = area.findtext("cap:areaDesc", default="", namespaces=CAP_NS) if area is not None else ""
    circle = area.findtext("cap:circle", default="", namespaces=CAP_NS) if area is not None else ""
    polygon = area.findtext("cap:polygon", default="", namespaces=CAP_NS) if area is not None else ""
    return {
        "identifier": root.findtext("cap:identifier", namespaces=CAP_NS),
        "sender": root.findtext("cap:sender", namespaces=CAP_NS),
        "event": info.findtext("cap:event", namespaces=CAP_NS),
        "urgency": info.findtext("cap:urgency", namespaces=CAP_NS),
        "severity": info.findtext("cap:severity", namespaces=CAP_NS),
        "certainty": info.findtext("cap:certainty", namespaces=CAP_NS),
        "effective": info.findtext("cap:effective", namespaces=CAP_NS),
        "expires": info.findtext("cap:expires", namespaces=CAP_NS),
        "senderName": info.findtext("cap:senderName", namespaces=CAP_NS),
        "headline": info.findtext("cap:headline", namespaces=CAP_NS),
        "description": info.findtext("cap:description", namespaces=CAP_NS),
        "instruction": info.findtext("cap:instruction", namespaces=CAP_NS),
        "areaDesc": area_desc,
        "circle": circle,
        "polygon": polygon,
    }


def fetch_via_feed():
    feed = fetch_feed()
    entries = feed.get("entry", [])
    if isinstance(entries, dict):
        entries = [entries]

    results = []
    skipped = 0
    seen_ids = set()
    duplicate_ids = 0
    for e in entries:
        term = e.get("category", {}).get("@term", "")
        if term not in RELEVANT_CATEGORIES:
            skipped += 1
            continue
        feed_id = e.get("id")
        if feed_id in seen_ids:
            duplicate_ids += 1
            continue
        seen_ids.add(feed_id)
        cap_url = e.get("link", {}).get("@href")
        if not cap_url:
            continue
        try:
            parsed = parse_cap(fetch_cap(cap_url))
        except Exception as ex:
            print(f"[警告] 解析失敗 {cap_url}：{ex}", file=sys.stderr)
            continue
        if parsed:
            parsed["category"] = term
            parsed["feedId"] = feed_id
            results.append(parsed)
    return results, len(entries), skipped, duplicate_ids


# ---------- 推送與主流程 ----------

def push_to_oracle(output):
    """失敗只警告、不中斷：本機檔案已寫成功才是基本盤，Oracle 波動不該讓 cron 整支失敗。"""
    if not INGEST_KEY_PATH.exists():
        print(f"[警告] 找不到 {INGEST_KEY_PATH}，跳過推送 Oracle", file=sys.stderr)
        return
    key = INGEST_KEY_PATH.read_text(encoding="utf-8").strip()
    body = json.dumps(output, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        INGEST_URL,
        data=body,
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "X-Ingest-Key": key,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            print(f"[推送] Oracle 已接收：{resp.read().decode('utf-8')}")
    except urllib.error.HTTPError as ex:
        detail = ex.read().decode("utf-8", errors="replace")
        print(f"[警告] 推送 Oracle 失敗 HTTP {ex.code}：{detail}", file=sys.stderr)
    except Exception as ex:
        print(f"[警告] 推送 Oracle 失敗：{ex}", file=sys.stderr)


def run():
    source = "official-api"
    try:
        if not API_KEY_PATH.exists():
            raise RuntimeError(f"找不到 {API_KEY_PATH}")
        events, total, skipped, duplicates = fetch_via_api()
    except Exception as ex:
        # 官方 API 掛掉不該讓資料斷流：退回公開 feed，並在輸出標明來源
        print(f"[警告] 官方 API 失敗，退回公開 feed：{ex}", file=sys.stderr)
        source = "public-feed-fallback"
        try:
            events, total, skipped, duplicates = fetch_via_feed()
        except Exception as ex2:
            print(f"[錯誤] 備援 feed 也失敗：{ex2}", file=sys.stderr)
            sys.exit(1)  # 保留上一次成功的 latest.json，不用空結果覆蓋

    output = {
        "fetchedAt": datetime.now().isoformat(),
        "source": source,
        "totalInFeed": total,
        "relevantCount": len(events),
        "skippedCount": skipped,
        "duplicateIdSkipped": duplicates,
        "events": events,
    }
    OUTPUT_PATH.write_text(
        json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"[完成] 來源 {source}：共 {total} 筆，相關 {len(events)} 筆，已寫入 {OUTPUT_PATH}")
    push_to_oracle(output)
    return output


if __name__ == "__main__":
    run()
