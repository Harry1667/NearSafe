#!/usr/bin/env bash
# 產生 iPad 版 5 張 Beacon 風格行銷截圖的 HTML（畫布 2064x2752）
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

gen() {
  local name="$1" headline="$2" src="$3"
  cat > "${name}.html" <<HTML
<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8" />
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Noto+Serif+TC:wght@700;900&display=swap" />
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: 2064px; height: 2752px; overflow: hidden; background: #050403; }
  .canvas {
    position: relative; width: 2064px; height: 2752px;
    background: radial-gradient(circle at 50% 24%, #2b2113 0%, #140f08 45%, #050403 78%), #050403;
  }
  .headline {
    position: absolute; top: 150px; left: 90px; right: 90px; text-align: center;
    font-family: "Noto Serif TC", "Songti TC", serif; font-weight: 900; letter-spacing: -2px;
    color: #F6C94A; font-size: 118px; line-height: 1.18;
    text-shadow: 0 0 46px rgba(246, 201, 74, 0.35);
  }
  .tablet {
    position: absolute; top: 560px; left: 282px; width: 1500px; height: 2000px;
    border-radius: 96px; background: #000; padding: 20px;
    box-shadow: 0 0 0 3px rgba(246, 201, 74, 0.55), 0 0 110px 22px rgba(246, 201, 74, 0.38),
      0 0 260px 70px rgba(246, 201, 74, 0.22), 0 50px 140px rgba(0, 0, 0, 0.6);
  }
  .tablet .screen-wrap {
    position: relative; width: 100%; height: 100%; border-radius: 78px; overflow: hidden; background: #000;
  }
  .tablet .screen-wrap img.shot {
    display: block; width: 100%; height: 100%; object-fit: cover; object-position: top;
  }
</style>
</head>
<body>
  <div class="canvas">
    <div class="headline">${headline}</div>
    <div class="tablet">
      <div class="screen-wrap">
        <img class="shot" src="${src}" />
      </div>
    </div>
  </div>
</body>
</html>
HTML
  echo "wrote ${name}.html"
}

gen "01_map" "掌握全台<br/>安全動態" "src_02_map.png"
gen "02_home" "一鍵報平安" "src_01_home.png"
gen "03_eventlist" "隨時發現<br/>周遭危險" "src_03_eventlist.png"
gen "04_eventdetail" "閱讀詳細<br/>事件報告" "src_04_eventdetail.png"
gen "05_family" "邀請家人<br/>一起守護" "src_05_family.png"
