<?php
// NCDR 資料推送接收端（捕捉模式）：先原封不動把推送內容存檔，
// 等看過真實 payload 格式後再接進資料管線。
// 註冊在 NCDR 的接收端 URL 形如：https://.../crawler/api/push.php?token=<PUSH_TOKEN>
require __DIR__ . '/_config.php';

header('Content-Type: application/json; charset=utf-8');

$token = $_GET['token'] ?? '';
if (!hash_equals(PUSH_TOKEN, $token)) {
    http_response_code(403);
    echo json_encode(['error' => 'forbidden']);
    exit;
}

// 有些推送服務會先用 GET/HEAD 驗證接收端存活，一律回 200
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode(['status' => 'alive']);
    exit;
}

$pushDir = __DIR__ . '/../data/push';
if (!is_dir($pushDir)) {
    mkdir($pushDir, 0775, true);
}

// 保留最近 500 筆，超過刪最舊的（防塞爆磁碟）
$existing = glob($pushDir . '/*.json');
if (count($existing) >= 500) {
    sort($existing); // 檔名含時間戳，字典序＝時間序
    foreach (array_slice($existing, 0, count($existing) - 499) as $old) {
        @unlink($old);
    }
}

$record = [
    'received_at'  => gmdate('Y-m-d\TH:i:s\Z'),
    'content_type' => $_SERVER['CONTENT_TYPE'] ?? '',
    'headers'      => array_filter($_SERVER, fn($k) => str_starts_with($k, 'HTTP_'), ARRAY_FILTER_USE_KEY),
    'body'         => file_get_contents('php://input'),
];

$file = sprintf('%s/%s-%s.json', $pushDir, gmdate('Ymd-His'), bin2hex(random_bytes(4)));
if (file_put_contents($file, json_encode($record, JSON_UNESCAPED_UNICODE)) === false) {
    http_response_code(500);
    echo json_encode(['error' => 'store failed']);
    exit;
}

echo json_encode(['status' => 'ok']);
