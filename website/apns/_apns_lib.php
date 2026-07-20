<?php
// APNs 共用函式庫：權杖存取、ES256 JWT 簽發、HTTP/2 推播發送。
// 被 register.php / notify_all.php / cron_check.php 引用，不直接對外服務。
require __DIR__ . '/_apns_config.php';

// MARK: - 權杖儲存（tokens.json：{ "<hex token>": {"env":"sandbox|production","updated_at":"..."} }）

function apns_tokens_file(): string {
    return APNS_PRIVATE_DIR . '/tokens.json';
}

function apns_load_tokens(): array {
    $file = apns_tokens_file();
    if (!file_exists($file)) { return []; }
    $data = json_decode(file_get_contents($file), true);
    return is_array($data) ? $data : []; // 壞檔視同空檔，不讓一次寫壞永久卡死
}

function apns_save_tokens(array $tokens): bool {
    $file = apns_tokens_file();
    $tmp = $file . '.tmp';
    if (file_put_contents($tmp, json_encode($tokens, JSON_PRETTY_PRINT), LOCK_EX) === false) {
        return false;
    }
    return rename($tmp, $file); // 同檔案系統 rename 是原子操作
}

// MARK: - ES256 JWT（Apple 規定：同一把 JWT 20 分鐘內不可重簽、60 分鐘內有效 → 快取 45 分鐘）

function apns_base64url(string $raw): string {
    return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
}

/// openssl_sign 產出的 ECDSA 簽章是 DER 封裝，JWT 要的是 r‖s 各 32 bytes 的原始格式
function apns_der_to_raw(string $der): string {
    // P-256 簽章的 DER 長度必小於 128 bytes，長度欄一定是短格式（單一 byte）
    $offset = 2;                       // 跳過 SEQUENCE tag + length
    $offset++;                         // INTEGER tag (r)
    $rlen = ord($der[$offset++]);
    $r = substr($der, $offset, $rlen);
    $offset += $rlen;
    $offset++;                         // INTEGER tag (s)
    $slen = ord($der[$offset++]);
    $s = substr($der, $offset, $slen);
    // 去掉 DER 為表示正數補的前導 0x00，再左補零到固定 32 bytes
    $r = ltrim($r, "\x00");
    $s = ltrim($s, "\x00");
    return str_pad($r, 32, "\x00", STR_PAD_LEFT) . str_pad($s, 32, "\x00", STR_PAD_LEFT);
}

/// 回傳可用的 JWT；金鑰未安裝時回 null（呼叫端據此優雅跳過，不炸整條 cron）
function apns_jwt(): ?string {
    if (APNS_KEY_ID === '' || !file_exists(APNS_KEY_FILE)) {
        return null;
    }
    $cacheFile = APNS_PRIVATE_DIR . '/jwt_cache.json';
    if (file_exists($cacheFile)) {
        $cache = json_decode(file_get_contents($cacheFile), true);
        if (is_array($cache) && isset($cache['iat'], $cache['jwt']) && time() - $cache['iat'] < 45 * 60) {
            return $cache['jwt'];
        }
    }
    $key = openssl_pkey_get_private(file_get_contents(APNS_KEY_FILE));
    if ($key === false) {
        error_log('APNs: .p8 私鑰無法解析');
        return null;
    }
    $header = apns_base64url(json_encode(['alg' => 'ES256', 'kid' => APNS_KEY_ID]));
    $claims = apns_base64url(json_encode(['iss' => APNS_TEAM_ID, 'iat' => time()]));
    $input = $header . '.' . $claims;
    if (!openssl_sign($input, $der, $key, OPENSSL_ALGO_SHA256)) {
        error_log('APNs: JWT 簽章失敗');
        return null;
    }
    $jwt = $input . '.' . apns_base64url(apns_der_to_raw($der));
    @file_put_contents($cacheFile, json_encode(['iat' => time(), 'jwt' => $jwt]), LOCK_EX);
    return $jwt;
}

// MARK: - 發送

/// 對單一裝置發推播。回 ['status' => HTTP 狀態碼, 'reason' => Apple 回的錯誤原因（成功時空字串）]。
/// $pushType 'background'（無聲喚醒，priority 必須 5）或 'alert'（可見通知，priority 10）。
function apns_send(string $token, string $env, array $payload, string $pushType = 'background'): array {
    $jwt = apns_jwt();
    if ($jwt === null) {
        return ['status' => 0, 'reason' => 'key-not-installed'];
    }
    $host = $env === 'production' ? 'api.push.apple.com' : 'api.sandbox.push.apple.com';
    $headers = [
        'authorization: bearer ' . $jwt,
        'apns-topic: ' . APNS_TOPIC,
        'apns-push-type: ' . $pushType,
        'apns-priority: ' . ($pushType === 'background' ? '5' : '10'),
        'apns-expiration: ' . (time() + 3600), // 1 小時內送達即可，過期作廢（警報過時無意義）
        'content-type: application/json',
    ];
    $ch = curl_init("https://{$host}/3/device/{$token}");
    curl_setopt_array($ch, [
        CURLOPT_HTTP_VERSION   => CURL_HTTP_VERSION_2_0, // APNs 只講 HTTP/2
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => json_encode($payload, JSON_UNESCAPED_UNICODE),
        CURLOPT_HTTPHEADER     => $headers,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 15,
    ]);
    $body = curl_exec($ch);
    $status = curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    $curlErr = curl_error($ch);
    curl_close($ch);
    if ($body === false) {
        return ['status' => 0, 'reason' => 'curl: ' . $curlErr];
    }
    $reason = '';
    if ($status !== 200) {
        $decoded = json_decode($body, true);
        $reason = $decoded['reason'] ?? $body;
    }
    return ['status' => $status, 'reason' => $reason];
}

/// 對所有已登記裝置廣播。失效權杖（BadDeviceToken/Unregistered/ExpiredToken）自動移除。
/// 回 ['sent' => n, 'failed' => n, 'removed' => n, 'errors' => 前幾筆錯誤原因]。
function apns_broadcast(array $payload, string $pushType = 'background'): array {
    $tokens = apns_load_tokens();
    $sent = 0; $failed = 0; $removed = 0; $errors = [];
    foreach ($tokens as $token => $meta) {
        $result = apns_send($token, $meta['env'] ?? 'sandbox', $payload, $pushType);
        if ($result['status'] === 200) {
            $sent++;
        } elseif (in_array($result['reason'], ['BadDeviceToken', 'Unregistered', 'ExpiredToken'], true)) {
            unset($tokens[$token]); // 裝置已解除安裝或權杖換代，留著只會一直打空炮
            $removed++;
        } else {
            $failed++;
            if (count($errors) < 5) { $errors[] = $result['reason']; }
        }
    }
    if ($removed > 0) { apns_save_tokens($tokens); }
    return ['sent' => $sent, 'failed' => $failed, 'removed' => $removed, 'errors' => $errors];
}

// MARK: - 危險級判定

/// 判斷單一 NCDR 事件是否屬於「危險級、需對所有裝置發可見推播」。
/// 危險級＝全區有感或立即致命的災型（地震/海嘯/火災/土石流/颱風）；
/// 已結案/已解除者不推（避免為非緊急事件對全國亂轟）。
/// 回傳可見推播 payload，非危險級或已結案回 null。
/// 產品取捨：這條路對所有裝置廣播、無法在顯示前依「你的生活圈」本機過濾，
/// 是「危險寧可多送不可漏」換來的——僅套用於少數危險級災型，其餘維持 App 內顯示。
function apns_danger_payload(array $e): ?array {
    static $DANGER = [
        '地震' => '⚠️ 地震速報', '海嘯' => '🌊 海嘯警報', '火災' => '🔥 火災警報',
        '土石流' => '⛰️ 土石流警戒', '颱風' => '🌀 颱風警報',
    ];
    $kind = (string)($e['category'] ?? $e['event'] ?? '');
    $title = null;
    foreach ($DANGER as $k => $t) {
        if ($kind !== '' && strpos($kind, $k) !== false) { $title = $t; break; }
    }
    if ($title === null) { return null; } // 非危險級

    // 已結案/已解除：不對全國廣播
    $text = ($e['headline'] ?? '') . ' ' . ($e['description'] ?? '');
    foreach (['已結案', '結案', '已解除', '解除'] as $m) {
        if (strpos($text, $m) !== false) { return null; }
    }

    $area = (string)($e['areaDesc'] ?? '');
    $body = trim(($e['headline'] ?? $kind) . ($area !== '' ? ' · ' . $area : ''));
    return [
        'aps' => [
            'alert' => ['title' => $title, 'body' => $body],
            'sound' => 'default',
            'interruption-level' => 'time-sensitive', // 危險級可穿過專注模式
        ],
        'kind' => 'danger-alert',
        'identifier' => (string)($e['identifier'] ?? ''),
    ];
}

// MARK: - 記錄

function apns_log(string $message): void {
    $line = gmdate('Y-m-d\TH:i:s\Z') . ' ' . $message . PHP_EOL;
    @file_put_contents(APNS_PRIVATE_DIR . '/apns.log', $line, FILE_APPEND | LOCK_EX);
}
