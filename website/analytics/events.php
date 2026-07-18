<?php
// 匿名事件接收端點：App 定期把「事件名 × 次數」的小批次 POST 上來。
// 最少資料守則：不收 IP、不收識別碼、不收位置——收到後立刻併進當日計數器，原始請求不落地。
//
// 這個端點不設密鑰：統計本來就要讓所有安裝者的 App 直接呼叫（與 apns/register.php 同理）。
// 防濫用措施：請求大小上限 8KB、單批最多 20 個事件、事件名白名單格式、單事件次數上限 1000。
require __DIR__ . '/_analytics.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'method not allowed']);
    exit;
}

$raw = file_get_contents('php://input');
if (strlen($raw) > 8192) {
    http_response_code(413);
    echo json_encode(['error' => 'payload too large']);
    exit;
}

$input = json_decode($raw, true);
$events = $input['events'] ?? null;
if (!is_array($events) || $events === [] || count($events) > 20) {
    http_response_code(400);
    echo json_encode(['error' => 'invalid events']);
    exit;
}

// 事件名只收小寫英數與底線（如 app_open、notification_opened），其他一律丟棄
$counts = [];
foreach ($events as $event) {
    $name = $event['name'] ?? '';
    $count = $event['count'] ?? 1;
    if (!is_string($name) || !preg_match('/^[a-z0-9_]{1,40}$/', $name)) { continue; }
    if (!is_int($count) || $count < 1) { continue; }
    $counts[$name] = ($counts[$name] ?? 0) + min($count, 1000);
}
if ($counts === []) {
    http_response_code(400);
    echo json_encode(['error' => 'no valid events']);
    exit;
}

// App 版本與 iOS 大版本：只留「1.0 (3)」「iOS 26」這種粒度，粗到無法識別任何人
$sanitize = fn($value, $max) => substr(preg_replace('/[^0-9A-Za-z .]/', '', (string) ($value ?? '')), 0, $max);
$app = $input['app'] ?? [];
$ver = $sanitize($app['ver'] ?? '', 12);
$build = $sanitize($app['build'] ?? '', 8);
$osMajor = $sanitize($app['os'] ?? '', 4);
$versionLabel = $ver !== '' ? trim("$ver ($build)") : '';
$osLabel = $osMajor !== '' ? 'iOS ' . explode('.', $osMajor)[0] : '';

if (!analytics_merge_batch($counts, $versionLabel, $osLabel)) {
    http_response_code(500);
    echo json_encode(['error' => 'store failed']);
    exit;
}

echo json_encode(['status' => 'ok']);
