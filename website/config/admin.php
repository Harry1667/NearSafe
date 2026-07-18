<?php
// 遠端設定編輯後臺：瀏覽器打開 → 輸入管理密鑰 → 編輯 app.json → 儲存。
// 儲存時：驗證 JSON 格式與必要欄位 → 自動蓋上 updatedAt → 備份舊檔 → 原子寫入。
// App 端拿到新設定後即時生效，不必重新送審——這是「熱更設定」的唯一入口。
//
// 紅線提醒（Apple Guideline 2.5.2）：這裡只能放「設定／開關／文案／數值」，
// 不可放任何可執行碼；也不可放祕密金鑰（app.json 是公開檔，任何人都抓得到）。
require __DIR__ . '/_config.php';

date_default_timezone_set('Asia/Taipei');

$message = null;   // 顯示在頁面上的結果訊息
$isError = false;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $key = $_POST['key'] ?? '';
    $json = $_POST['json'] ?? '';

    if (!hash_equals(CONFIG_ADMIN_KEY, $key)) {
        sleep(1); // 拖慢暴力嘗試
        @file_put_contents(
            CONFIG_PRIVATE_DIR . '/admin.log',
            gmdate('Y-m-d\TH:i:s\Z') . " auth_failed\n",
            FILE_APPEND | LOCK_EX
        );
        http_response_code(403);
        $message = '密鑰錯誤';
        $isError = true;
    } else {
        $data = json_decode($json, true);
        if (!is_array($data)) {
            $message = 'JSON 格式錯誤：' . json_last_error_msg();
            $isError = true;
        } elseif (!isset($data['schemaVersion']) || !is_int($data['schemaVersion']) || $data['schemaVersion'] < 1) {
            $message = 'schemaVersion 必須是 ≥1 的整數（App 端靠它判斷能不能解析）';
            $isError = true;
        } elseif (isset($data['minimumBuild']) && !is_int($data['minimumBuild'])) {
            $message = 'minimumBuild 必須是整數';
            $isError = true;
        } else {
            // 伺服器自動蓋時間戳，人工不用維護
            $data['updatedAt'] = gmdate('Y-m-d\TH:i:s\Z');
            $encoded = json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

            // 備份舊檔（保留最近 20 份，出錯可回滾）
            if (!is_dir(CONFIG_PRIVATE_DIR)) { @mkdir(CONFIG_PRIVATE_DIR, 0755, true); }
            if (file_exists(CONFIG_LIVE_FILE)) {
                @copy(CONFIG_LIVE_FILE, CONFIG_PRIVATE_DIR . '/backup-' . date('Ymd-His') . '.json');
                $backups = glob(CONFIG_PRIVATE_DIR . '/backup-*.json') ?: [];
                sort($backups);
                foreach (array_slice($backups, 0, max(0, count($backups) - 20)) as $old) { @unlink($old); }
            }

            // 原子寫入：先寫 tmp 再 rename，App 永遠不會抓到寫到一半的檔
            $tmp = CONFIG_LIVE_FILE . '.tmp';
            if (file_put_contents($tmp, $encoded . "\n", LOCK_EX) === false || !rename($tmp, CONFIG_LIVE_FILE)) {
                http_response_code(500);
                $message = '寫入失敗（檢查目錄權限是否為 www:www）';
                $isError = true;
            } else {
                @file_put_contents(
                    CONFIG_PRIVATE_DIR . '/admin.log',
                    gmdate('Y-m-d\TH:i:s\Z') . " saved\n",
                    FILE_APPEND | LOCK_EX
                );
                $message = '已儲存並生效（updatedAt 已自動更新）';
            }
        }
    }
}

$current = file_exists(CONFIG_LIVE_FILE) ? file_get_contents(CONFIG_LIVE_FILE) : "{\n}";
?>
<!DOCTYPE html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>HavenCircle 遠端設定</title>
<style>
    body { font-family: -apple-system, "Noto Sans TC", sans-serif; max-width: 720px; margin: 2rem auto; padding: 0 1rem; background: #f6f8f7; color: #1a2b26; }
    h1 { font-size: 1.2rem; }
    textarea { width: 100%; height: 24rem; font-family: ui-monospace, Menlo, monospace; font-size: 0.85rem; padding: 0.75rem; border: 1px solid #c5d4cf; border-radius: 8px; box-sizing: border-box; }
    input[type=password] { width: 100%; padding: 0.6rem; border: 1px solid #c5d4cf; border-radius: 8px; box-sizing: border-box; }
    button { margin-top: 0.75rem; padding: 0.6rem 1.5rem; background: #0F8A6B; color: #fff; border: 0; border-radius: 8px; font-size: 1rem; cursor: pointer; }
    .msg { padding: 0.75rem 1rem; border-radius: 8px; margin: 1rem 0; }
    .ok { background: #dcf3ea; color: #0a5c47; }
    .err { background: #fde8e8; color: #9b1c1c; }
    .hint { font-size: 0.8rem; color: #5b6f68; }
</style>
</head>
<body>
<h1>HavenCircle 遠端設定（app.json）</h1>
<p class="hint">儲存後 App 下次啟動／刷新即套用。只放設定與開關，不放程式碼、不放金鑰。</p>
<?php if ($message !== null): ?>
<div class="msg <?= $isError ? 'err' : 'ok' ?>"><?= htmlspecialchars($message, ENT_QUOTES, 'UTF-8') ?></div>
<?php endif; ?>
<form method="post">
    <label>管理密鑰<br><input type="password" name="key" autocomplete="current-password" required></label>
    <p></p>
    <textarea name="json" spellcheck="false"><?= htmlspecialchars($current, ENT_QUOTES, 'UTF-8') ?></textarea>
    <br><button type="submit">驗證並儲存</button>
</form>
</body>
</html>
