<?php
// 爬蟲對外金鑰後臺：瀏覽器打開 → 輸入管理密碼 → 填入要更新的金鑰 → 儲存。
// 儲存寫入同層 _keys.php（PHP 陣列，直接存取網址不外洩）；
// Mac Mini 的 sync_keys.py 每 10 分鐘拉取並覆寫本地金鑰檔，爬蟲下次執行即用新值。
//
// 安全設計：本頁「永不顯示」現有金鑰值——GET 只給密碼欄與空白輸入框，
// 「留空＝不變更」，避免任何人開啟此網址就看到金鑰。只有輸入正確密碼才會寫入。
// 紅線：這裡管理的是「對外資料源金鑰」（政府開放資料授權碼），不是付費／私有 token。
require __DIR__ . '/_config.php';

date_default_timezone_set('Asia/Taipei');

$keysFile = __DIR__ . '/_keys.php';
$logFile  = __DIR__ . '/keys_admin.log';
$fields = [
    'cwa_key'      => '中央氣象署 CWA 授權碼（CWA- 開頭）',
    'ncdr_api_key' => 'NCDR 災害示警 API 金鑰（約一年到期）',
    'moenv_key'    => '環境部 MOENV 空品 API 金鑰',
];

$message = null;
$isError = false;
$statusAfterSave = null; // 儲存成功後顯示各欄「已更新／維持原值／未設定」，仍不顯示實際值

$loadKeys = function () use ($keysFile) {
    $k = is_file($keysFile) ? (require $keysFile) : [];
    return is_array($k) ? $k : [];
};

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $pass = $_POST['key'] ?? '';
    if (!hash_equals(KEYS_ADMIN_KEY, $pass)) {
        sleep(1); // 拖慢暴力嘗試
        @file_put_contents($logFile, gmdate('Y-m-d\TH:i:s\Z') . " auth_failed\n", FILE_APPEND | LOCK_EX);
        http_response_code(403);
        $message = '密碼錯誤';
        $isError = true;
    } else {
        $keys = $loadKeys();
        $new = $keys;
        $statusAfterSave = [];
        foreach (array_keys($fields) as $name) {
            $v = trim($_POST[$name] ?? '');
            if ($v !== '') {
                $new[$name] = $v;
                $statusAfterSave[$name] = '已更新';
            } else {
                $statusAfterSave[$name] = isset($keys[$name]) && $keys[$name] !== '' ? '維持原值' : '未設定';
            }
        }
        // 產生 PHP 檔內容：單引號字串，addslashes 防止值裡意外的 ' 或 \ 破壞語法
        $lines = [
            '<?php',
            '// 由 keys_admin.php 寫入，請勿手動編輯。直接存取此檔網址會被 PHP 執行、輸出空白。',
            'return [',
        ];
        foreach ($new as $name => $val) {
            $lines[] = "    '" . addslashes($name) . "' => '" . addslashes((string)$val) . "',";
        }
        $lines[] = '];';
        $content = implode("\n", $lines) . "\n";

        if (is_file($keysFile)) { @copy($keysFile, $keysFile . '.bak'); }
        $tmp = $keysFile . '.tmp';
        if (file_put_contents($tmp, $content, LOCK_EX) === false || !rename($tmp, $keysFile)) {
            http_response_code(500);
            $message = '寫入失敗（檢查 _keys.php 所在目錄權限是否為 www:www）';
            $isError = true;
            $statusAfterSave = null;
        } else {
            @file_put_contents($logFile, gmdate('Y-m-d\TH:i:s\Z') . " saved\n", FILE_APPEND | LOCK_EX);
            $message = '已儲存。Mac Mini 下次同步（每 10 分鐘）後生效。';
        }
    }
}
?>
<!DOCTYPE html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>HavenCircle 爬蟲金鑰</title>
<style>
    body { font-family: -apple-system, "Noto Sans TC", sans-serif; max-width: 640px; margin: 2rem auto; padding: 0 1rem; background: #f6f8f7; color: #1a2b26; }
    h1 { font-size: 1.2rem; }
    label { display: block; margin-top: 1rem; font-size: 0.9rem; }
    input { width: 100%; padding: 0.6rem; border: 1px solid #c5d4cf; border-radius: 8px; box-sizing: border-box; margin-top: 0.35rem; font-size: 0.95rem; }
    button { margin-top: 1.25rem; padding: 0.6rem 1.5rem; background: #0F8A6B; color: #fff; border: 0; border-radius: 8px; font-size: 1rem; cursor: pointer; }
    .msg { padding: 0.75rem 1rem; border-radius: 8px; margin: 1rem 0; }
    .ok { background: #dcf3ea; color: #0a5c47; }
    .err { background: #fde8e8; color: #9b1c1c; }
    .hint { font-size: 0.8rem; color: #5b6f68; }
    .status { font-size: 0.85rem; color: #0a5c47; margin: 0.25rem 0 0; }
    .fieldhint { font-size: 0.75rem; color: #5b6f68; margin-top: 0.15rem; }
</style>
</head>
<body>
<h1>爬蟲對外金鑰管理</h1>
<p class="hint">更新政府開放資料的授權碼（CWA／NCDR／環境部）。填入新金鑰後儲存，Mac Mini 每 10 分鐘同步一次。<b>留空的欄位保持原值不變。</b>本頁不會顯示現有金鑰。</p>
<?php if ($message !== null): ?>
<div class="msg <?= $isError ? 'err' : 'ok' ?>"><?= htmlspecialchars($message, ENT_QUOTES, 'UTF-8') ?></div>
<?php endif; ?>
<?php if ($statusAfterSave !== null): ?>
<div class="status">
<?php foreach ($fields as $name => $desc): ?>
    <?= htmlspecialchars($name, ENT_QUOTES, 'UTF-8') ?>：<?= htmlspecialchars($statusAfterSave[$name], ENT_QUOTES, 'UTF-8') ?><br>
<?php endforeach; ?>
</div>
<?php endif; ?>
<form method="post" autocomplete="off">
    <label>管理密碼
        <input type="password" name="key" autocomplete="current-password" required>
    </label>
    <?php foreach ($fields as $name => $desc): ?>
    <label><?= htmlspecialchars($name, ENT_QUOTES, 'UTF-8') ?>
        <input type="text" name="<?= htmlspecialchars($name, ENT_QUOTES, 'UTF-8') ?>" placeholder="留空＝不變更" autocomplete="off" spellcheck="false">
        <div class="fieldhint"><?= htmlspecialchars($desc, ENT_QUOTES, 'UTF-8') ?></div>
    </label>
    <?php endforeach; ?>
    <button type="submit">儲存變更</button>
</form>
</body>
</html>
