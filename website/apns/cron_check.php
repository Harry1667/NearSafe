<?php
// 新警報偵測（cron 每 5 分鐘跑一次，只能從命令列執行）：
// 讀 NCDR 官方警報存檔 latest.json，比對上次看過的 identifier 集合，
// 有新警報 → 對所有裝置廣播「無聲喚醒」，讓每台裝置自己抓資料、自己比對生活圈。
//
// 產品鐵律：只看 NCDR 官方資料集。媒體報導（latest_news.json）永遠不觸發推播。
//
// crontab（ubuntu 使用者）：
//   */5 * * * * sudo -n -u www php /www/wwwroot/havencircle.looptw.com/apns/cron_check.php
if (php_sapi_name() !== 'cli') {
    http_response_code(404);
    exit;
}
require __DIR__ . '/_apns_lib.php';

$latestFile = __DIR__ . '/../crawler/data/latest.json';
if (!file_exists($latestFile)) {
    apns_log('cron_check: latest.json 不存在，跳過');
    exit;
}
$envelope = json_decode(file_get_contents($latestFile), true);
$events = $envelope['data']['events'] ?? [];
$currentIds = array_values(array_filter(array_map(fn($e) => $e['identifier'] ?? null, $events)));

$seenFile = APNS_PRIVATE_DIR . '/seen_identifiers.json';

// 首次執行：只記錄現有警報、不推播——避免一部署就對著存量警報亂轟一輪
if (!file_exists($seenFile)) {
    file_put_contents($seenFile, json_encode($currentIds), LOCK_EX);
    apns_log('cron_check: 首次執行，記錄 ' . count($currentIds) . ' 筆現有警報（不推播）');
    exit;
}

$seen = json_decode(file_get_contents($seenFile), true);
if (!is_array($seen)) { $seen = []; }

$fresh = array_diff($currentIds, $seen);
if (empty($fresh)) {
    exit; // 沒新警報，安靜結束（不寫 log，避免 5 分鐘一行塞爆）
}

// 記錄集合要「累積」而不是覆蓋成當前清單：警報過期從 latest.json 消失後，
// 若之後同 identifier 又出現（不會，但防禦性處理），也不該重推。上限 1000 防無限成長。
$seen = array_slice(array_values(array_unique(array_merge($seen, $currentIds))), -1000);
file_put_contents($seenFile, json_encode($seen), LOCK_EX);

$payload = ['aps' => ['content-available' => 1], 'reason' => 'new-alert'];
$result = apns_broadcast($payload, 'background');
apns_log(sprintf(
    'cron_check: %d 筆新警報（%s）→ 廣播喚醒 sent=%d failed=%d removed=%d%s',
    count($fresh),
    implode(',', array_slice($fresh, 0, 3)) . (count($fresh) > 3 ? '…' : ''),
    $result['sent'], $result['failed'], $result['removed'],
    in_array('key-not-installed', $result['errors'], true) ? '（APNs 金鑰尚未安裝，實際未發送）' : ''
));
