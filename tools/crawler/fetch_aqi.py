#!/usr/bin/env python3
"""環境部空氣品質爬蟲：抓全台測站 AQI（逐時），推送 Oracle 供 App 地圖圖層使用。

資料源：data.moenv.gov.tw 資料集 aqx_p_432（空氣品質指標 AQI，每小時更新）。
金鑰放同層 moenv_key.txt（600 權限，不進版控）。cron 建議每小時執行。
"""

import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

API_URL = "https://data.moenv.gov.tw/api/v2/aqx_p_432"
KEY_PATH = Path(__file__).parent / "moenv_key.txt"
OUTPUT_PATH = Path(__file__).parent / "latest_aqi.json"

INGEST_URL = "https://havencircle.looptw.com/crawler/api/ingest.php?dataset=aqi"
# ingest 金鑰與 ncdr 爬蟲共用（同一台機器的 ../ncdr/ingest_key.txt）
INGEST_KEY_PATH = Path(__file__).parent.parent / "ncdr" / "ingest_key.txt"


def to_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def to_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def fetch_stations():
    key = KEY_PATH.read_text(encoding="utf-8").strip()
    params = urllib.parse.urlencode({"api_key": key, "limit": 1000, "format": "JSON"})
    with urllib.request.urlopen(f"{API_URL}?{params}", timeout=30) as resp:
        raw = json.loads(resp.read().decode("utf-8"))
    # API 可能回陣列或 {records: [...]} 兩種形狀，都接
    records = raw if isinstance(raw, list) else raw.get("records", [])

    stations = []
    for r in records:
        lat = to_float(r.get("latitude"))
        lon = to_float(r.get("longitude"))
        aqi = to_int(r.get("aqi"))
        # 座標或 AQI 缺漏的測站（維護中）直接略過，不上地圖
        if lat is None or lon is None or aqi is None:
            continue
        stations.append({
            "siteId": r.get("siteid"),
            "name": r.get("sitename"),
            "county": r.get("county"),
            "aqi": aqi,
            "status": r.get("status"),
            "pollutant": r.get("pollutant") or "",
            "pm25": to_float(r.get("pm2.5")),
            "latitude": lat,
            "longitude": lon,
            "publishTime": r.get("publishtime"),
        })
    return stations, len(records)


def push_to_oracle(output):
    if not INGEST_KEY_PATH.exists():
        print(f"[警告] 找不到 {INGEST_KEY_PATH}，跳過推送 Oracle", file=sys.stderr)
        return
    key = INGEST_KEY_PATH.read_text(encoding="utf-8").strip()
    body = json.dumps(output, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        INGEST_URL,
        data=body,
        headers={"Content-Type": "application/json; charset=utf-8", "X-Ingest-Key": key},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            print(f"[推送] Oracle 已接收：{resp.read().decode('utf-8')}")
    except urllib.error.HTTPError as ex:
        print(f"[警告] 推送失敗 HTTP {ex.code}：{ex.read().decode('utf-8', errors='replace')}", file=sys.stderr)
    except Exception as ex:
        print(f"[警告] 推送失敗：{ex}", file=sys.stderr)


def run():
    try:
        stations, total = fetch_stations()
    except Exception as ex:
        print(f"[錯誤] 抓取空品資料失敗：{ex}", file=sys.stderr)
        sys.exit(1)  # 保留上次成功結果，不用空資料覆蓋

    output = {
        "fetchedAt": datetime.now().isoformat(),
        "totalStations": total,
        "validCount": len(stations),
        "stations": stations,
    }
    OUTPUT_PATH.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[完成] 共 {total} 站，有效 {len(stations)} 站，已寫入 {OUTPUT_PATH}")
    push_to_oracle(output)


if __name__ == "__main__":
    run()
