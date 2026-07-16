<?php
// 建立 8 位邀請碼：收 CKShare 連結，發一組短碼，存成檔案（碼→連結，含效期）。
// 公開端點（App 端無法保管密鑰），防濫用手段：只收 icloud.com 分享連結、
// 72 小時效期、總量上限、每次建立順手清掉過期檔。
header('Content-Type: application/json; charset=utf-8');

const CODE_TTL_SECONDS = 72 * 3600;
const MAX_ACTIVE_CODES = 10000;
// 不含 0/O/1/I/L 的字元表，避免唸給家人聽時搞混
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'method not allowed']);
    exit;
}

$body = json_decode(file_get_contents('php://input'), true);
$url = $body['url'] ?? '';
$parts = parse_url($url);
$host = strtolower($parts['host'] ?? '');
if (($parts['scheme'] ?? '') !== 'https'
    || !($host === 'icloud.com' || str_ends_with($host, '.icloud.com'))) {
    http_response_code(400);
    echo json_encode(['error' => 'only icloud.com share links are accepted']);
    exit;
}

$dataDir = __DIR__ . '/../data';
if (!is_dir($dataDir)) {
    mkdir($dataDir, 0775, true);
}

// 清過期檔＋計數（規模小，glob 掃一輪即可）
$active = 0;
foreach (glob($dataDir . '/*.json') as $file) {
    $entry = json_decode(@file_get_contents($file), true);
    if (!$entry || ($entry['expires_at'] ?? 0) < time()) {
        @unlink($file);
    } else {
        $active++;
    }
}
if ($active >= MAX_ACTIVE_CODES) {
    http_response_code(503);
    echo json_encode(['error' => 'too many active codes, try later']);
    exit;
}

// 產生不重複的 8 位碼
$code = '';
for ($attempt = 0; $attempt < 10; $attempt++) {
    $candidate = '';
    for ($i = 0; $i < 8; $i++) {
        $candidate .= ALPHABET[random_int(0, strlen(ALPHABET) - 1)];
    }
    if (!file_exists($dataDir . '/' . $candidate . '.json')) {
        $code = $candidate;
        break;
    }
}
if ($code === '') {
    http_response_code(500);
    echo json_encode(['error' => 'code generation failed']);
    exit;
}

$expiresAt = time() + CODE_TTL_SECONDS;
file_put_contents($dataDir . '/' . $code . '.json', json_encode([
    'url'        => $url,
    'created_at' => time(),
    'expires_at' => $expiresAt,
]));

echo json_encode([
    'code'       => $code,
    'expires_at' => gmdate('Y-m-d\TH:i:s\Z', $expiresAt),
]);
