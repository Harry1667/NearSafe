<?php
// 兌換 8 位邀請碼：回傳對應的 CKShare 連結。碼不分大小寫。
header('Content-Type: application/json; charset=utf-8');
require __DIR__ . '/_join_lib.php';

$code = strtoupper(trim($_GET['code'] ?? ''));
if (!preg_match('/^[A-HJ-NP-Z2-9]{8}$/', $code)) {
    http_response_code(400);
    echo json_encode(['error' => 'invalid code format']);
    exit;
}

$file = __DIR__ . '/../data/' . $code . '.json';
$entry = file_exists($file) ? json_decode(file_get_contents($file), true) : null;

if (!$entry || ($entry['expires_at'] ?? 0) < time()) {
    if ($entry) {
        @unlink($file); // 已過期就順手清掉
    }
    http_response_code(404);
    echo json_encode(['error' => 'code not found or expired']);
    exit;
}

$url = join_decrypt($entry['url'] ?? '');
if ($url === null || $url === '') {
    http_response_code(404);
    echo json_encode(['error' => 'code not found or expired']);
    exit;
}
echo json_encode(['url' => $url]);
