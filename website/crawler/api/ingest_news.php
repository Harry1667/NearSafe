<?php
// 接收 Mac Mini「新聞事故爬蟲」推送。與 ingest.php 的差異：
// 新聞爬蟲每輪只推「這一輪的新事件」，所以這裡要「合併累積」而不是整檔覆蓋——
// 以事件 id 合併（新蓋舊）、淘汰發布超過 24 小時的、上限 300 筆，
// 再以與其他資料集相同的信封格式原子寫入 latest_news.json 供 latest.php 供應。
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
$incoming = json_decode($raw, true);
if (json_last_error() !== JSON_ERROR_NONE || !is_array($incoming)
    || !isset($incoming['events']) || !is_array($incoming['events'])) {
    http_response_code(400);
    echo json_encode(['error' => 'invalid json']);
    exit;
}

$dataDir = __DIR__ . '/../data';
if (!is_dir($dataDir)) {
    mkdir($dataDir, 0775, true);
}
$finalFile = $dataDir . '/latest_news.json';

// 讀既有存檔（信封格式 {received_at, count, data:{events:[…]}}），壞檔視同空檔重建
$existing = [];
if (file_exists($finalFile)) {
    $prev = json_decode(file_get_contents($finalFile), true);
    if (is_array($prev) && isset($prev['data']['events']) && is_array($prev['data']['events'])) {
        $existing = $prev['data']['events'];
    }
}

// 以 id 合併：同 id 新蓋舊（爬蟲端已做跨來源合併，重推代表資訊更新）
$byId = [];
foreach ($existing as $e) {
    if (isset($e['id'])) { $byId[$e['id']] = $e; }
}
foreach ($incoming['events'] as $e) {
    if (isset($e['id'])) { $byId[$e['id']] = $e; }
}

// 淘汰 24 小時前發布的事件：新聞的守護價值在即時性，舊聞只會誤導
$cutoff = time() - 24 * 3600;
$merged = array_values(array_filter($byId, function ($e) use ($cutoff) {
    $ts = isset($e['publishedAt']) ? strtotime($e['publishedAt']) : false;
    return $ts !== false && $ts >= $cutoff;
}));

// 新到舊排序＋上限 300 筆（防爆量；正常量級一天數十則）
usort($merged, function ($a, $b) {
    return strtotime($b['publishedAt'] ?? '1970-01-01') <=> strtotime($a['publishedAt'] ?? '1970-01-01');
});
$merged = array_slice($merged, 0, 300);

$payload = [
    'received_at' => gmdate('Y-m-d\TH:i:s\Z'),
    'count'       => count($merged),
    'data'        => [
        'fetchedAt'      => $incoming['fetchedAt'] ?? null,
        'sources'        => $incoming['sources'] ?? [],
        'totalFetched'   => $incoming['totalFetched'] ?? null,
        'totalEligible'  => $incoming['totalEligible'] ?? null,
        'skippedSeen'    => $incoming['skippedSeen'] ?? null,
        'incidentCount'  => $incoming['incidentCount'] ?? null,
        'droppedByRules' => $incoming['droppedByRules'] ?? null,
        'droppedByLLM'   => $incoming['droppedByLLM'] ?? null,
        'pipelineHealth' => $incoming['pipelineHealth'] ?? null,
        'events'         => $merged,
    ],
];

$tmpFile = $finalFile . '.tmp';
if (file_put_contents($tmpFile, json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)) === false) {
    http_response_code(500);
    echo json_encode(['error' => 'write failed']);
    exit;
}
rename($tmpFile, $finalFile); // 同檔案系統內 rename 是原子操作

// 新聞同 id 可能先以規則降級落地、AI 重試後才升級為可播報；每次合併完成後都交給
// cron_check 比對「播報狀態指紋」。背景執行不延遲爬蟲回應；部分主機會在 PHP
// disable_functions 停用 exec（直接呼叫會變 Fatal Error），這時交由每分鐘 cron 補上。
if (function_exists('exec')) {
    @exec('php ' . escapeshellarg(__DIR__ . '/../../apns/cron_check.php') . ' > /dev/null 2>&1 &');
} else {
    error_log('HavenCircle ingest_news: exec unavailable; scheduled cron_check will handle this update');
}

echo json_encode([
    'status'   => 'ok',
    'received' => count($incoming['events']),
    'stored'   => count($merged),
]);
