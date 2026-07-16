<?php
// 接收 Mac Mini 爬蟲推送的最新示警資料，寫入 data/latest.json（原子寫入，避免讀寫競態）。
require __DIR__ . '/_config.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'method not allowed']);
    exit;
}

$key = $_SERVER['HTTP_X_INGEST_KEY'] ?? '';
if (!hash_equals(INGEST_KEY, $key)) {
    http_response_code(403);
    echo json_encode(['error' => 'forbidden']);
    exit;
}

$raw = file_get_contents('php://input');
$data = json_decode($raw, true);
if (json_last_error() !== JSON_ERROR_NONE || !is_array($data)) {
    http_response_code(400);
    echo json_encode(['error' => 'invalid json']);
    exit;
}

$dataDir = __DIR__ . '/../data';
if (!is_dir($dataDir)) {
    mkdir($dataDir, 0775, true);
}

$payload = [
    'received_at' => gmdate('Y-m-d\TH:i:s\Z'),
    'count'       => is_array($data['events'] ?? $data['alerts'] ?? null) ? count($data['events'] ?? $data['alerts']) : null,
    'data'        => $data,
];

$tmpFile   = $dataDir . '/latest.json.tmp';
$finalFile = $dataDir . '/latest.json';

if (file_put_contents($tmpFile, json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)) === false) {
    http_response_code(500);
    echo json_encode(['error' => 'write failed']);
    exit;
}
rename($tmpFile, $finalFile); // 同檔案系統內 rename 是原子操作，讀取端不會讀到寫一半的檔案

echo json_encode([
    'status'      => 'ok',
    'received_at' => $payload['received_at'],
    'count'       => $payload['count'],
]);
