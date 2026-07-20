<?php
// 供 Mac Mini 爬蟲執行時取回「對外資料源金鑰」（CWA／NCDR／環境部）。
// 授權：沿用爬蟲既有的 X-Ingest-Key（＝INGEST_KEY），Mac Mini 端不需新增任何祕密。
// 金鑰實際值存在同層 _keys.php（PHP 回傳陣列；直接以網址存取會被 PHP 執行、輸出空白，不外洩）。
require __DIR__ . '/_config.php';

header('Content-Type: application/json; charset=utf-8');

$key = $_SERVER['HTTP_X_INGEST_KEY'] ?? '';
if (!hash_equals(INGEST_KEY, $key)) {
    http_response_code(403);
    echo json_encode(['error' => 'forbidden']);
    exit;
}

$name = $_GET['name'] ?? '';
$allowed = ['cwa_key', 'ncdr_api_key', 'moenv_key'];
if (!in_array($name, $allowed, true)) {
    http_response_code(400);
    echo json_encode(['error' => 'unknown key name']);
    exit;
}

$keysFile = __DIR__ . '/_keys.php';
$keys = is_file($keysFile) ? (require $keysFile) : [];
$value = is_array($keys) ? (string)($keys[$name] ?? '') : '';

echo json_encode(['ok' => true, 'name' => $name, 'value' => $value]);
