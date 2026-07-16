<?php
// 管理端點：對所有已登記裝置廣播推播。需要 X-Admin-Key，外人打不動。
//
// 兩種模式：
//   （預設）silent — 無聲喚醒 {aps:{content-available:1}}：裝置被叫醒後自己抓資料、
//            自己比對生活圈、只有真的相關才跳本機通知。這是正式營運用的模式。
//   alert  — 可見通知（需帶 title/body）：Demo 與測試用，直接在鎖屏跳橫幅。
require __DIR__ . '/_apns_lib.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'method not allowed']);
    exit;
}
$key = $_SERVER['HTTP_X_ADMIN_KEY'] ?? '';
if (!hash_equals(APNS_ADMIN_KEY, $key)) {
    http_response_code(403);
    echo json_encode(['error' => 'forbidden']);
    exit;
}

$input = json_decode(file_get_contents('php://input'), true) ?: [];
$mode = $input['mode'] ?? 'silent';

if ($mode === 'alert') {
    $title = trim($input['title'] ?? '');
    $body = trim($input['body'] ?? '');
    if ($title === '' || $body === '') {
        http_response_code(400);
        echo json_encode(['error' => 'alert mode requires title and body']);
        exit;
    }
    $payload = ['aps' => ['alert' => ['title' => $title, 'body' => $body], 'sound' => 'default']];
    $result = apns_broadcast($payload, 'alert');
} else {
    // reason 讓 App 端知道被喚醒的原因（目前只有 new-alert 一種，保留擴充空間）
    $payload = ['aps' => ['content-available' => 1], 'reason' => 'new-alert'];
    $result = apns_broadcast($payload, 'background');
}

apns_log("notify_all mode={$mode} sent={$result['sent']} failed={$result['failed']} removed={$result['removed']}");
echo json_encode(['status' => 'ok', 'mode' => $mode] + $result, JSON_UNESCAPED_UNICODE);
