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

// 多資料集：ncdr（預設，災害示警）與 aqi（環境部空品）各存一份檔案
$dataset = $_GET['dataset'] ?? 'ncdr';
if (!in_array($dataset, ['ncdr', 'aqi', 'crime', 'cwa'], true)) {
    http_response_code(400);
    echo json_encode(['error' => 'unknown dataset']);
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

$items = $data['events'] ?? $data['stations'] ?? $data['districts'] ?? $data['alerts'] ?? null;
$payload = [
    'received_at' => gmdate('Y-m-d\TH:i:s\Z'),
    'count'       => is_array($items) ? count($items) : null,
    'data'        => $data,
];

$basename  = ['ncdr' => 'latest', 'aqi' => 'latest_aqi', 'crime' => 'latest_crime', 'cwa' => 'latest_cwa'][$dataset] ?? 'latest';
$tmpFile   = $dataDir . '/' . $basename . '.json.tmp';
$finalFile = $dataDir . '/' . $basename . '.json';

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
