<?php
// cron_check 的純狀態轉換測試：不讀正式資料、不呼叫 FCM、不需要任何憑證。
// 執行：php website/apns/test_cron_check.php
define('CRON_CHECK_LIB_ONLY', true);
require __DIR__ . '/cron_check.php';

function check(bool $condition, string $message): void {
    if (!$condition) {
        fwrite(STDERR, "FAIL: {$message}\n");
        exit(1);
    }
}

$directory = sys_get_temp_dir() . '/havencircle-cron-test-' . bin2hex(random_bytes(4));
mkdir($directory, 0700, true);
$stateFile = $directory . '/state.json';

// 首次部署只建立基線，不能把既有事件一次推給所有人。
check(state_diff($stateFile, ['news-1' => 'not-eligible']) === [], 'first run must seed only');
// 同一篇新聞被 AI 升級成可播報時，id 沒變也必須被看見。
$upgrade = state_diff($stateFile, ['news-1' => state_signature(['fire', 'high', 0.95])]);
check($upgrade === ['news-1'], 'eligible upgrade must be detected');
check(state_diff($stateFile, ['news-1' => state_signature(['fire', 'high', 0.95])]) === [], 'same state must not repeat');
// 帳本毀損時必須 fail closed，不能把目前所有可播報事件當成第一次出現。
file_put_contents($stateFile, '{broken');
check(state_diff($stateFile, ['news-1' => 'new-state']) === [], 'broken state file must fail closed');
check(file_get_contents($stateFile) === '{broken', 'broken state file must not be overwritten');
// API 未標時區的政府時間視為台灣時間；這個剛發生的資料不可被 UTC 誤判成過舊。
$taipeiNow = (new DateTimeImmutable('now', new DateTimeZone('Asia/Taipei')))->format('Y/m/d H:i:s');
check(is_recent_timestamp($taipeiNow, 60), 'Taiwan local timestamp must be recent');

unlink($stateFile);
unlink($stateFile . '.lock');
rmdir($directory);
echo "cron_check state tests passed\n";
