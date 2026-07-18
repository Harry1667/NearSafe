#!/usr/bin/env python3
"""CWA 中央氣象署開放資料爬蟲：顯著有感地震報告＋颱風警報/路徑。

角色：補 NCDR CAP 拿不到的細節——地震規模/深度/各地震度、颱風路徑與預報。
NCDR 仍是警報主幹，這支只提供加值細節，App 端可在事件詳情顯示。

需要 cwa_key.txt（與本檔同目錄）：
  1. 免費註冊氣象會員：https://pweb.cwa.gov.tw/emember/register （只需 email）
  2. 登入 https://opendata.cwa.gov.tw/user/authkey 點「取得授權碼」（即時核發，CWA- 開頭）
  3. 授權碼存成 cwa_key.txt
額度：一般會員 24 小時 2 萬次；本爬蟲每次跑 4 個呼叫，cron 每 10 分鐘一次
一天約 576 次，遠低於上限。

輸出 latest_cwa.json，並推送 Oracle（ingest.php?dataset=cwa）。
cwa_key.txt 不存在時印提示後直接結束（exit 0）——cron 可先掛著等註冊完成。
"""

import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

API_BASE = "https://opendata.cwa.gov.tw/api/v1/rest/datastore"
KEY_PATH = Path(__file__).parent / "cwa_key.txt"
OUTPUT_PATH = Path(__file__).parent / "latest_cwa.json"

INGEST_URL = "https://havencircle.looptw.com/crawler/api/ingest.php?dataset=cwa"
INGEST_KEY_PATH = Path(__file__).parent / "ingest_key.txt"

# dataid 出自官方 OpenAPI 規格（opendata.cwa.gov.tw/apidoc/v1，2026-07-18 驗證）
DATASETS = {
    "significantQuakes": ("E-A0015-001", {"limit": 20, "sort": "OriginTime"}),  # 顯著有感地震報告
    "localQuakes": ("E-A0016-001", {"limit": 20, "sort": "OriginTime"}),        # 小區域有感地震
    "typhoonWarning": ("W-C0034-001", {}),                                      # 颱風警報
    "typhoonTracks": ("W-C0034-005", {}),                                       # 熱帶氣旋路徑（分析＋預報）
}


def api_get(api_key, dataid, params):
    query = dict(params)
    query["Authorization"] = api_key
    query["format"] = "JSON"
    url = f"{API_BASE}/{dataid}?" + urllib.parse.urlencode(query)
    with urllib.request.urlopen(url, timeout=20) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    if payload.get("success") not in (True, "true"):
        raise RuntimeError(f"{dataid} 回傳 success != true：{str(payload)[:200]}")
    return payload.get("records")


def push_to_oracle(output):
    """失敗只警告、不中斷：本機檔案寫成功是基本盤，Oracle 波動不該讓 cron 整支失敗。"""
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
    if not KEY_PATH.exists():
        print(f"[提示] 尚未設定 {KEY_PATH}（CWA 授權碼），跳過本次執行。"
              "註冊步驟見本檔開頭註解。")
        return None

    api_key = KEY_PATH.read_text(encoding="utf-8").strip()
    datasets = {}
    errors = {}
    for name, (dataid, params) in DATASETS.items():
        # 單一 dataset 失敗記錄後繼續：地震 API 掛掉不該連颱風資料一起斷
        try:
            datasets[name] = api_get(api_key, dataid, params)
            print(f"[完成] {name}（{dataid}）")
        except Exception as ex:
            errors[name] = str(ex)
            print(f"[警告] {name}（{dataid}）失敗：{ex}", file=sys.stderr)

    if not datasets:
        # 全滅才失敗退出，保留上一次成功的 latest_cwa.json
        print("[錯誤] 所有 CWA dataset 都抓取失敗", file=sys.stderr)
        sys.exit(1)

    output = {
        "fetchedAt": datetime.now().isoformat(),
        "source": "cwa-open-data",
        "datasets": datasets,
        "errors": errors or None,
    }
    OUTPUT_PATH.write_text(
        json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"[完成] 共 {len(datasets)}/{len(DATASETS)} 個 dataset，已寫入 {OUTPUT_PATH}")
    push_to_oracle(output)
    return output


if __name__ == "__main__":
    run()
