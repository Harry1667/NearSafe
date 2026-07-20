#!/usr/bin/env python3
"""
從 Oracle 同步「對外資料源金鑰」到本機，讓爬蟲免改程式碼、免 SSH 即可更新金鑰。

流程：用既有的 ingest_key 向 Oracle 的 key.php 取回 cwa／ncdr／moenv 金鑰，
覆寫本機對應的 *_key.txt。爬蟲程式完全不動、照舊讀本機金鑰檔。

安全與韌性：
- 授權沿用爬蟲既有的 X-Ingest-Key，本機不新增任何祕密。
- Oracle 取不到、逾時或回空值時「保留原檔」不覆寫——Oracle 短暫故障不會清空金鑰、不中斷爬蟲。
- 只在值有變動時才寫入，且採原子替換（tmp→replace），避免爬蟲讀到寫一半的檔。

部署：放在 /home/david/crawlers/havencircle/sync_keys.py，cron 每 10 分鐘執行。
搭配 Oracle 端 keys_admin.php（密碼後台）即可遠端輪替金鑰。
"""
import json
import sys
import urllib.request
from pathlib import Path

BASE = Path(__file__).resolve().parent  # /home/david/crawlers/havencircle
KEY_URL = "https://havencircle.looptw.com/crawler/api/key.php"
INGEST_KEY_PATH = BASE / "ncdr" / "ingest_key.txt"

# 遠端金鑰名 → 本機金鑰檔（爬蟲讀取的路徑）
TARGETS = {
    "cwa_key": BASE / "cwa" / "cwa_key.txt",
    "ncdr_api_key": BASE / "ncdr" / "api_key.txt",
    "moenv_key": BASE / "moenv" / "moenv_key.txt",
}


def fetch(name, ingest_key):
    """向 Oracle 取單一金鑰；失敗會拋例外，由呼叫端決定保留原檔。"""
    req = urllib.request.Request(
        f"{KEY_URL}?name={name}",
        headers={"X-Ingest-Key": ingest_key},
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        obj = json.loads(resp.read().decode("utf-8"))
    return str(obj.get("value", ""))


def main():
    if not INGEST_KEY_PATH.exists():
        print(f"[錯誤] 找不到 {INGEST_KEY_PATH}，無法向 Oracle 認證", file=sys.stderr)
        return 1
    ingest_key = INGEST_KEY_PATH.read_text(encoding="utf-8").strip()

    changed = 0
    for name, dest in TARGETS.items():
        try:
            value = fetch(name, ingest_key).strip()
        except Exception as exc:  # 網路／逾時／JSON 皆保留原檔
            print(f"[警告] 取 {name} 失敗，保留原檔：{exc}", file=sys.stderr)
            continue
        if not value:
            print(f"[警告] {name} 回傳空值，保留原檔", file=sys.stderr)
            continue

        current = dest.read_text(encoding="utf-8").strip() if dest.exists() else None
        if current == value:
            continue  # 無變動，不動檔案

        dest.parent.mkdir(parents=True, exist_ok=True)
        tmp = dest.with_suffix(dest.suffix + ".tmp")
        tmp.write_text(value + "\n", encoding="utf-8")
        tmp.chmod(0o600)
        tmp.replace(dest)  # 同檔案系統 replace 為原子操作
        print(f"[更新] {name} → {dest.name}")
        changed += 1

    if changed:
        print(f"[完成] 更新 {changed} 個金鑰")
    return 0


if __name__ == "__main__":
    sys.exit(main())
