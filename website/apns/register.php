<?php
// APNs 權杖登記端點：App 拿到裝置權杖後 POST 上來，伺服器才知道要推給誰。
// 零追蹤守則：只收「權杖＋環境」，不收任何位置、姓名、生活圈——
// 伺服器只會對所有裝置廣播「無聲喚醒」，警報是否與這位使用者相關，永遠由裝置自己判斷。
//
// 這個端點不設密鑰：權杖登記本來就要讓所有安裝者的 App 直接呼叫。
// 防濫用措施：格式驗證（只收 hex）＋總量上限 500（超過淘汰最久沒更新的）。
require __DIR__ . '/_apns_lib.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'method not allowed']);
    exit;
}

$input = json_decode(file_get_contents('php://input'), true);
$token = strtolower(trim($input['token'] ?? ''));
$env = $input['env'] ?? 'sandbox';

// 權杖是 hex 字串（目前 64 字，Apple 保留加長空間 → 上限放寬到 200）
if (!preg_match('/^[0-9a-f]{64,200}$/', $token)) {
    http_response_code(400);
    echo json_encode(['error' => 'invalid token format']);
    exit;
}
if (!in_array($env, ['sandbox', 'production'], true)) {
    http_response_code(400);
    echo json_encode(['error' => 'invalid env']);
    exit;
}

$tokens = apns_load_tokens();
$tokens[$token] = ['env' => $env, 'updated_at' => gmdate('Y-m-d\TH:i:s\Z')];

// 總量上限：淘汰最久沒更新的（正常使用者每次開 App 都會重新登記，活躍的不會被淘汰）
if (count($tokens) > 500) {
    uasort($tokens, fn($a, $b) => strcmp($a['updated_at'] ?? '', $b['updated_at'] ?? ''));
    $tokens = array_slice($tokens, count($tokens) - 500, null, true);
}

if (!apns_save_tokens($tokens)) {
    http_response_code(500);
    echo json_encode(['error' => 'store failed']);
    exit;
}

echo json_encode(['status' => 'ok', 'count' => count($tokens)]);
