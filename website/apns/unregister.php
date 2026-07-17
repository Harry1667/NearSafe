<?php
// APNs 權杖撤銷端點：供 App 的「刪除帳號與所有資料」移除目前裝置權杖。
// 權杖本身就是刪除索引；端點不要求也不接收姓名、位置或帳號資訊。
require __DIR__ . '/_apns_lib.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'method not allowed']);
    exit;
}

$input = json_decode(file_get_contents('php://input'), true);
$token = strtolower(trim($input['token'] ?? ''));

if (!preg_match('/^[0-9a-f]{64,200}$/', $token)) {
    http_response_code(400);
    echo json_encode(['error' => 'invalid token format']);
    exit;
}

$tokens = apns_load_tokens();
$existed = array_key_exists($token, $tokens);
unset($tokens[$token]);

if ($existed && !apns_save_tokens($tokens)) {
    http_response_code(500);
    echo json_encode(['error' => 'storage failure']);
    exit;
}

// 冪等：權杖本來就不存在也視為撤銷完成，避免重試造成假錯誤。
echo json_encode(['ok' => true, 'removed' => $existed]);
