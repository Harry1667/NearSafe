#!/usr/bin/env python3
"""警政署犯罪資料爬蟲：抓 data.gov.tw 資料集 14200（8 案類、每季更新、逐案列），
聚合成「鄉鎮市區 × 案類」統計，推送 Oracle 供 App 治安參考圖層使用。

免申請、免金鑰。cron 建議每月跑一次（資料每季才更新，跑多了沒意義）。
設計定位：歷史統計參考，不是即時警報——App 端顯示須與災害警報嚴格區隔。
"""

import csv
import io
import json
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

DATASET_META_URL = "https://data.gov.tw/api/v2/rest/dataset/14200"
OUTPUT_PATH = Path(__file__).parent / "latest_crime.json"

INGEST_URL = "https://havencircle.looptw.com/crawler/api/ingest.php?dataset=crime"
INGEST_KEY_PATH = Path(__file__).parent.parent / "ncdr" / "ingest_key.txt"


def http_get(url, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": "HavenCircle-crawler/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def latest_resource():
    """從資料集後設資料挑出季度編號最大的 CSV 資源"""
    meta = json.loads(http_get(DATASET_META_URL).decode("utf-8"))
    best = None
    best_period = -1
    for res in meta["result"]["distribution"]:
        desc = res.get("resourceDescription", "")
        match = re.match(r"^(\d{5})", desc)
        if not match:
            continue
        period = int(match.group(1))
        url = res.get("resourceDownloadUrl")
        if url and period > best_period:
            best_period = period
            best = (desc, url)
    if not best:
        raise RuntimeError("找不到任何季度資源")
    return best


def normalize(text):
    """臺/台 正規化＋去空白（比對用）"""
    return (text or "").strip().replace("臺", "台")


def aggregate(csv_bytes):
    """逐案列 → (縣市, 鄉鎮市區) × 案類 計數。欄位名稱各季略有差異，用關鍵字比對。"""
    text = csv_bytes.decode("utf-8-sig", errors="replace")
    reader = csv.reader(io.StringIO(text))
    header = next(reader)

    def find_col(*keywords):
        for i, name in enumerate(header):
            if any(k in name for k in keywords):
                return i
        return None

    col_type = find_col("案類", "type")
    col_county = find_col("縣市", "county")
    col_region = find_col("鄉鎮", "區", "region")
    if col_type is None or col_county is None or col_region is None:
        raise RuntimeError(f"欄位比對失敗，表頭為：{header}")

    districts = {}
    total = 0
    for row in reader:
        if len(row) <= max(col_type, col_county, col_region):
            continue
        case_type = row[col_type].strip()
        county = row[col_county].strip()
        region = row[col_region].strip()
        if not case_type or not county:
            continue
        # 部分資料 region 含縣市前綴（例「新北市淡水區」），去掉
        if region.startswith(county):
            region = region[len(county):]
        # 機車竊盜等案件發生地不明時 region 為空，歸「未指定」
        region = region or "未指定"
        key = (county, region)
        districts.setdefault(key, {})
        districts[key][case_type] = districts[key].get(case_type, 0) + 1
        total += 1

    return [
        {
            "county": county,
            "town": town,
            "total": sum(counts.values()),
            "byType": counts,
        }
        for (county, town), counts in sorted(districts.items())
    ], total


def push_to_oracle(output):
    if not INGEST_KEY_PATH.exists():
        print(f"[警告] 找不到 {INGEST_KEY_PATH}，跳過推送", file=sys.stderr)
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
        with urllib.request.urlopen(req, timeout=30) as resp:
            print(f"[推送] Oracle 已接收：{resp.read().decode('utf-8')}")
    except urllib.error.HTTPError as ex:
        print(f"[警告] 推送失敗 HTTP {ex.code}：{ex.read().decode('utf-8', errors='replace')}", file=sys.stderr)
    except Exception as ex:
        print(f"[警告] 推送失敗：{ex}", file=sys.stderr)


def run():
    try:
        desc, url = latest_resource()
        print(f"[資源] {desc}")
        rows, total = aggregate(http_get(url))
    except Exception as ex:
        print(f"[錯誤] 抓取犯罪資料失敗：{ex}", file=sys.stderr)
        sys.exit(1)

    output = {
        "fetchedAt": datetime.now().isoformat(),
        "period": desc,
        "totalCases": total,
        "districts": rows,
    }
    OUTPUT_PATH.write_text(json.dumps(output, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"[完成] {desc}：{total} 案、{len(rows)} 個行政區，已寫入 {OUTPUT_PATH}")
    push_to_oracle(output)


if __name__ == "__main__":
    run()
