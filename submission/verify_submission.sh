#!/usr/bin/env bash

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PITCH="$ROOT/website/pitch/index.html"
ICON_JSON="$ROOT/HavenCircle/Assets.xcassets/AppIcon.appiconset/Contents.json"
APP_SETTINGS="$ROOT/HavenCircle/Views/Settings/SettingsView.swift"
DEVICE_EVIDENCE="$ROOT/submission/DEVICE_EVIDENCE_PLAN.md"
FAILURES=0

pass() {
  printf 'PASS  %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

require_file() {
  local path="$1"
  local label="$2"
  if [[ -s "$path" ]]; then
    pass "$label"
  else
    fail "${label}（缺少或為空：${path#$ROOT/}）"
  fi
}

reject_pattern() {
  local pattern="$1"
  local label="$2"
  shift 2
  if rg -n "$pattern" "$@" >/dev/null; then
    fail "$label"
    rg -n "$pattern" "$@" | sed 's/^/      /'
  else
    pass "$label"
  fi
}

require_pattern() {
  local pattern="$1"
  local label="$2"
  local file="$3"
  if rg -n "$pattern" "$file" >/dev/null; then
    pass "$label"
  else
    fail "$label"
  fi
}

printf 'HavenCircle submission gate\n'
printf 'Root: %s\n\n' "$ROOT"

SUBMISSION_FILES=(
  "$PITCH"
  "$ROOT/submission/VIDEO_SCRIPT.md"
  "$ROOT/submission/SCREENSHOT_PLAN.md"
)

for legal_page in privacy.html user-agreement.html terms.html; do
  require_file "$ROOT/website/$legal_page" "網站法律文件 $legal_page"
  require_pattern \
    "$legal_page" \
    "官網頁尾連結 $legal_page" \
    "$ROOT/website/index.html"
  require_pattern \
    "$legal_page" \
    "Pitch 頁尾連結 $legal_page" \
    "$PITCH"
done

require_pattern \
  'LegalCenterView' \
  'App 設定具有法律與隱私入口' \
  "$APP_SETTINGS"

require_pattern \
  'APNsRegistrar.unregister' \
  '刪除資料會撤銷 APNs 權杖' \
  "$APP_SETTINGS"

require_file \
  "$DEVICE_EVIDENCE" \
  'APNs／背景定位實機證據計畫'

if php -l "$ROOT/website/apns/unregister.php" >/dev/null 2>&1; then
  pass 'APNs 權杖撤銷端點語法正確'
else
  fail 'APNs 權杖撤銷端點 PHP 語法錯誤'
fi

reject_pattern \
  'ZERO-TRACKING|零位置追蹤|不看家人在哪|不追蹤任何人的位置' \
  '提交素材不得沿用零追蹤舊敘事' \
  "${SUBMISSION_FILES[@]}"

reject_pattern \
  '後端發送建置中|Oracle 端自動發送服務為下一步|App 端垂直切片已就緒・後端' \
  'APNs 狀態不得沿用後端尚未完成的舊說法' \
  "${SUBMISSION_FILES[@]}"

for image in \
  00-home.png \
  01-onboarding.png \
  02-alerts.png \
  03-map.png \
  04-event-detail.png \
  05-family.png; do
  require_file "$ROOT/website/pitch/img/$image" "敘事截圖 $image"
done

if jq -e '.images | any(has("filename"))' "$ICON_JSON" >/dev/null 2>&1; then
  icon_missing=0
  while IFS= read -r filename; do
    if [[ ! -s "$ROOT/HavenCircle/Assets.xcassets/AppIcon.appiconset/$filename" ]]; then
      icon_missing=1
      fail "AppIcon 引用的檔案不存在：$filename"
    fi
  done < <(jq -r '.images[] | .filename // empty' "$ICON_JSON")
  if [[ "$icon_missing" -eq 0 ]]; then
    pass 'AppIcon asset 已連結實際圖檔'
  fi
else
  fail 'AppIcon asset 尚未設定任何 filename'
fi

require_pattern \
  '<b>隊名</b>[：:]' \
  'Pitch 必須明確顯示隊名' \
  "$PITCH"

reject_pattern \
  '請填.*隊名|隊名.*待填|TEAM_NAME' \
  'Pitch 隊名不得使用佔位文字' \
  "$PITCH"

require_pattern \
  'href="https?://[^"]+"[^>]*>[^<]*Demo 影片' \
  'Pitch 必須包含可點擊的 Demo 影片連結' \
  "$PITCH"

if [[ "${1:-}" == "--online" ]]; then
  if curl -fsS --max-time 15 \
    'https://havencircle.looptw.com/crawler/api/latest.php' \
    | jq -e '.data.events | type == "array"' >/dev/null; then
    pass '線上 NCDR 中繼 API 可用'
  else
    fail '線上 NCDR 中繼 API 無法取得有效事件陣列'
  fi
fi

if [[ "${1:-}" == "--build" ]]; then
  DERIVED_DATA_PATH="${HAVENCIRCLE_DERIVED_DATA_PATH:-/tmp/HavenCircleSubmissionGateDerivedData}"
  if xcodebuild -quiet \
    -project "$ROOT/HavenCircle.xcodeproj" \
    -scheme HavenCircle \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    build; then
    pass 'HavenCircle 模擬器建置'
  else
    fail 'HavenCircle 模擬器建置失敗'
  fi
fi

printf '\n'
if [[ "$FAILURES" -eq 0 ]]; then
  printf 'READY  自動提交閘門全部通過；仍須核對 COMPETITION_READINESS.md 的人工實機證據。\n'
  exit 0
fi

printf 'BLOCKED  目前有 %d 個未通過項目。\n' "$FAILURES"
exit 1
