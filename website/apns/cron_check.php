<?php
// 新警報偵測（cron 每 1 分鐘＋ingest 觸發）：比對上次看過的 id，有新的危險事件 → 透過 FCM 主題推播。
//
// 兩個獨立來源：
//   1) NCDR 官方（latest.json）：全區有感（地震/海嘯/颱風）→ 發全台主題 hc_all；
//      地區性危險（火災/土石流）→ 發事件行政區對應主題。
//   2) 新聞（latest_news.json）：只推「危險類型（火災/天災/公共安全）＋信心度≥0.75＋有縣市區」的，
//      發到該區主題、標明「·新聞」讓使用者知道是媒體報導、未經官方確認。
//
// 分級目的：危險（不論官方或新聞）即時通知到相關的人；瑣事（停水/車禍/民生）不推，避免通知疲勞。
// 隱私：訂閱關係（誰關心哪區）存在 FCM/Google，本伺服器不掌握——被駭也洩不出。
//
// crontab（ubuntu 使用者）：
//   * * * * * sudo -n -u www php /www/wwwroot/havencircle.looptw.com/apns/cron_check.php
if (php_sapi_name() !== 'cli') {
    http_response_code(404);
    exit;
}
require __DIR__ . '/_apns_lib.php';
require __DIR__ . '/_fcm_lib.php';
require __DIR__ . '/region_topic.php';

process_ncdr();
process_news();

/// NCDR 官方危險事件 → FCM（全台或按區）
function process_ncdr(): void {
    $file = __DIR__ . '/../crawler/data/latest.json';
    if (!file_exists($file)) { return; }
    $events = json_decode(file_get_contents($file), true)['data']['events'] ?? [];
    $currentIds = array_values(array_filter(array_map(fn($e) => $e['identifier'] ?? null, $events)));
    $fresh = seen_diff(APNS_PRIVATE_DIR . '/seen_identifiers.json', $currentIds);
    if (empty($fresh)) { return; }

    $byId = [];
    foreach ($events as $e) { if (isset($e['identifier'])) { $byId[$e['identifier']] = $e; } }

    $wideArea = ['地震', '海嘯', '颱風']; // 全區有感 → 全台廣播
    $sent = 0;
    foreach ($fresh as $id) {
        $event = $byId[$id] ?? null;
        if ($event === null) { continue; }
        $payload = apns_danger_payload($event); // null＝非危險級或已結案
        if ($payload === null) { continue; }
        $title = $payload['aps']['alert']['title'];
        $body  = $payload['aps']['alert']['body'];
        $kind  = (string)($event['category'] ?? $event['event'] ?? '');

        $isWide = false;
        foreach ($wideArea as $w) { if (strpos($kind, $w) !== false) { $isWide = true; break; } }

        if ($isWide) {
            $r = fcm_send(['topic' => REGION_TOPIC_ALL], $title, $body, ['identifier' => $id, 'kind' => 'official']);
            apns_log(sprintf('cron_check[NCDR]: 全台 [%s] %s → %s', $id, $title, fcm_result($r)));
        } else {
            $topics = region_topics_from_area((string)($event['areaDesc'] ?? ''));
            if (empty($topics)) {
                apns_log(sprintf('cron_check[NCDR]: 無行政區資訊，未推 [%s] %s', $id, $title));
                continue;
            }
            $r = fcm_send(['condition' => topics_condition($topics)], $title, $body, ['identifier' => $id, 'kind' => 'official']);
            apns_log(sprintf('cron_check[NCDR]: 地區 [%s] %s 區數=%d → %s', $id, $title, min(count($topics), 5), fcm_result($r)));
        }
        if (++$sent >= 5) { break; }
    }
}

/// 危險新聞 → FCM（按區）。只推高信心度、危險類型、有地點者，並標明「·新聞」。
function process_news(): void {
    $file = __DIR__ . '/../crawler/data/latest_news.json';
    if (!file_exists($file)) { return; }
    $events = json_decode(file_get_contents($file), true)['data']['events'] ?? [];
    $currentIds = array_values(array_filter(array_map(fn($e) => $e['id'] ?? null, $events)));
    $fresh = seen_diff(APNS_PRIVATE_DIR . '/seen_news_ids.json', $currentIds);
    if (empty($fresh)) { return; }

    // 推播分級改由新聞爬蟲的 AI 判斷把關（比純規則準）：
    //   類別（火災/天災/公共安全）為底線，再要求 AI 判定 is_ongoing=true 且 severity 夠高。
    //   這解決了「已獲救/已撲滅的事後報導」與「大小事不分級」的問題。交通/民生類仍不推。
    $dangerCats = ['火災' => '🔥 火災', '天災' => '🌪️ 天災', '公共安全' => '⚠️ 公共安全'];
    $pushSeverities = ['high', 'medium']; // 要推的嚴重度（可調；只留 high 會更保守）
    $minConfidence = 0.6;                 // 信心度地板（保險，擋 AI 明顯不確定的）
    $cooldownSeconds = 2 * 3600;          // 同區同類 2 小時內只推一次，收斂重複報導

    // 冷卻紀錄：{ "主題|類型": 上次推播時間 }。載入時順手清掉過期項。
    $cooldownFile = APNS_PRIVATE_DIR . '/news_push_cooldown.json';
    $now = time();
    $cooldown = is_file($cooldownFile) ? (json_decode(file_get_contents($cooldownFile), true) ?: []) : [];
    $cooldown = array_filter($cooldown, fn($ts) => ($now - (int)$ts) < $cooldownSeconds);

    $byId = [];
    foreach ($events as $e) { if (isset($e['id'])) { $byId[$e['id']] = $e; } }

    $sent = 0;
    $changed = false;
    foreach ($fresh as $id) {
        $e = $byId[$id] ?? null;
        if ($e === null) { continue; }
        $cat = (string)($e['category'] ?? '');
        if (!isset($dangerCats[$cat])) { continue; }                       // 非危險類別（底線）
        if (($e['is_ongoing'] ?? false) !== true) { continue; }            // AI 判定已結束/事後報導 → 不推
        $severity = strtolower(trim((string)($e['severity'] ?? '')));
        if (!in_array($severity, $pushSeverities, true)) { continue; }     // AI 判定嚴重度不足 → 不推
        if ((float)($e['confidence'] ?? 0) < $minConfidence) { continue; } // 信心度過低（保險）
        $county = trim((string)($e['county'] ?? ''));
        $district = trim((string)($e['district'] ?? ''));
        if ($county === '' || $district === '') { continue; }              // 無地點：不廣播地方新聞

        // 正規化成「與 App 訂閱一致」的有效區名主題（補後綴、拆多區）；對不上就不推
        $topics = news_region_topics($county, $district);
        if (empty($topics)) {
            apns_log(sprintf('cron_check[news]: 無法對應有效行政區，未推 [%s] %s %s%s', $id, $cat, $county, $district));
            continue;
        }
        sort($topics);
        $cdKey = implode('+', $topics) . '|' . $cat;
        if (isset($cooldown[$cdKey])) {                                    // 同區同類冷卻中：收斂重複報導
            apns_log(sprintf('cron_check[news]: 同區同類冷卻中，略過 [%s] %s %s%s', $id, $cat, $county, $district));
            continue;
        }

        $title = $dangerCats[$cat] . '·新聞';
        $body  = (string)($e['detail'] ?? $e['summary'] ?? $e['title'] ?? '');
        $target = count($topics) === 1 ? ['topic' => $topics[0]] : ['condition' => topics_condition($topics)];
        $r = fcm_send($target, $title, $body, [
            'id' => $id, 'kind' => 'news', 'sourceURL' => (string)($e['sourceURL'] ?? ''),
        ]);
        apns_log(sprintf('cron_check[news]: [%s] %s conf=%s %s%s 區數=%d → %s',
            $id, $cat, (string)($e['confidence'] ?? ''), $county, $district, count($topics), fcm_result($r)));
        if ($r['ok']) { $cooldown[$cdKey] = $now; $changed = true; }
        if (++$sent >= 5) { break; }
    }

    if ($changed) {
        file_put_contents($cooldownFile, json_encode($cooldown), LOCK_EX);
    }
}

// MARK: - 小工具

/// 讀 seen 檔、算出新 id、更新累積 seen（上限 1000）。首次執行只記錄不推（回空陣列）。
function seen_diff(string $seenFile, array $currentIds): array {
    if (!file_exists($seenFile)) {
        file_put_contents($seenFile, json_encode($currentIds), LOCK_EX);
        return []; // 首次部署：只記錄現有，不對存量狂轟
    }
    $seen = json_decode(file_get_contents($seenFile), true);
    if (!is_array($seen)) { $seen = []; }
    $fresh = array_values(array_diff($currentIds, $seen));
    $merged = array_slice(array_values(array_unique(array_merge($seen, $currentIds))), -1000);
    file_put_contents($seenFile, json_encode($merged), LOCK_EX);
    return $fresh;
}

/// 多區用 FCM condition（OR），上限 5 個主題
function topics_condition(array $topics): string {
    $subset = array_slice($topics, 0, 5);
    return implode(' || ', array_map(fn($t) => "'" . $t . "' in topics", $subset));
}

function fcm_result(array $r): string {
    return $r['ok'] ? ('ok ' . $r['name']) : ('FAIL ' . $r['error']);
}
