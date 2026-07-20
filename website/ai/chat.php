<?php
// 安心圈 App 的 AI 安全代理：App 打這裡，這裡藏著 ProxyCLI（clip.twloop.com）憑證去呼叫 AI，只回結果。
//
// 為什麼要這一層：ProxyCLI 的 Bearer token 是機密，一旦下發到 App 就會被拆封包偷走盜刷。
// 所以 token 只留在伺服器（_ai_config.php，不進 repo），App 只帶一把「低權限 App Key」——
// 那把 key 就算被拆出來，也只能打這支代理（有限流、可隨時撤銷改 key），拿不到真正的 ProxyCLI token。
// 換 ProxyCLI token 或 App Key：改 _ai_config.php 即可，App 不用更新。
require __DIR__ . '/_ai_config.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'method not allowed']);
    exit;
}

// App 端驗證：低權限金鑰（防路人白嫖，非防拆解——真正的裝置級防濫用日後上 App Attest）
$appKey = $_SERVER['HTTP_X_APP_KEY'] ?? '';
if (!hash_equals(APP_AI_KEY, $appKey)) {
    http_response_code(403);
    echo json_encode(['error' => 'forbidden']);
    exit;
}

// 簡易限流：每 IP 每 60 秒最多 RATE_LIMIT 次，防單點暴衝把 AI 額度打爆。
$dataDir = __DIR__ . '/data';
if (!is_dir($dataDir)) { @mkdir($dataDir, 0755, true); }
$ip = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
$rlFile = $dataDir . '/rl-' . hash('sha256', $ip) . '.json';
$now = time();
$window = [];
if (is_file($rlFile)) {
    $decoded = json_decode((string) file_get_contents($rlFile), true);
    if (is_array($decoded)) { $window = $decoded; }
}
$window = array_values(array_filter($window, fn($t) => $t > $now - 60)); // 只留近 60 秒
if (count($window) >= RATE_LIMIT) {
    http_response_code(429);
    echo json_encode(['error' => 'rate limited', 'retry_after' => 60]);
    exit;
}
$window[] = $now;
file_put_contents($rlFile, json_encode($window), LOCK_EX);

// 讀取並驗證 prompt
$raw = file_get_contents('php://input');
$in = json_decode($raw, true);
$prompt = is_array($in) ? trim((string) ($in['prompt'] ?? '')) : '';
if ($prompt === '' || mb_strlen($prompt) > 4000) {
    http_response_code(400);
    echo json_encode(['error' => 'invalid prompt']);
    exit;
}
// effort 允許 App 指定，但走白名單，避免亂傳
$effort = $in['effort'] ?? null;
if (!in_array($effort, ['low', 'medium', 'high'], true)) { $effort = null; }

// 轉呼叫 ProxyCLI（token/project 藏在伺服器，App 從未看過）
$payload = ['prompt' => $prompt, 'project' => PROXYCLI_PROJECT, 'group' => 'app'];
if ($effort !== null) { $payload['effort'] = $effort; }

$ch = curl_init(PROXYCLI_URL);
curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => 60,
    CURLOPT_HTTPHEADER => [
        'Content-Type: application/json',
        'Authorization: Bearer ' . PROXYCLI_TOKEN,
    ],
    CURLOPT_POSTFIELDS => json_encode($payload, JSON_UNESCAPED_UNICODE),
]);
$resp = curl_exec($ch);
$curlErr = curl_error($ch);
curl_close($ch);

if ($resp === false) {
    http_response_code(502);
    echo json_encode(['error' => 'upstream unreachable', 'detail' => $curlErr]);
    exit;
}
$data = json_decode($resp, true);
if (!is_array($data) || empty($data['ok'])) {
    http_response_code(502);
    echo json_encode(['error' => 'upstream error', 'detail' => $data['error'] ?? null]);
    exit;
}

// 只回 App 需要的：內容＋實際用的模型（不透露 token 或內部細節）
echo json_encode([
    'ok' => true,
    'content' => $data['content'] ?? '',
    'model' => $data['actual_model'] ?? null,
], JSON_UNESCAPED_UNICODE);
