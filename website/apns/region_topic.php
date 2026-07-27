<?php
// FCM 主題名的伺服器端計算，必須與 App 的 RegionTopic.swift「完全一致」。
// 一旦兩邊正規化或雜湊規則不同，同一個區會算出不同主題、通知永遠對不上，且很難察覺。
// 已用跨語言測試驗證：region_topic("台中市","中區") 與 Swift 版產出相同字串。

// 全台廣播主題（地震／海嘯／颱風等全區有感事件）。所有裝置都訂閱。
const REGION_TOPIC_ALL = 'hc_all';
// 環境監測主題。高 AQI 是區域性現象，但原始測站資料只有縣市、不能安全地猜到
// 使用者所在行政區；因此只用來無聲喚醒 App 重新拉取資料，再由裝置端的生活圈判斷。
// 這個主題不帶任何使用者位置，和 hc_all 一樣不會讓伺服器知道誰住在哪裡。
const REGION_TOPIC_ENVIRONMENT = 'hc_environment';

/// 正規化：臺→台、去前後空白（與 RegionTopic.swift 的 normalize 完全相同）。
function region_normalize(string $s): string {
    return trim(str_replace('臺', '台', $s));
}

/// 由「縣市＋區」算出主題名，例如 region_topic("台中市", "中區")。
function region_topic(string $county, string $town): string {
    $canonical = region_normalize($county) . region_normalize($town);
    return 'hc_r_' . substr(sha1($canonical), 0, 16);
}

/// 從 NCDR 事件的 areaDesc 抽出所有「縣市＋區」對，回傳去重後的主題陣列。
/// areaDesc 例：「新北市汐止區復興里、新北市汐止區白雲里」→ [台中市中區的主題...]。
function region_topics_from_area(string $areaDesc): array {
    $topics = [];
    // 以中文頓號/逗號拆段，每段抓「縣市」+「鄉鎮市區」
    $segments = preg_split('/[、,，]/u', $areaDesc);
    foreach ($segments as $seg) {
        if (preg_match('/^\s*(.+?[縣市])(.+?[鄉鎮市區])/u', $seg, $m)) {
            $topics[region_topic($m[1], $m[2])] = true; // 用 key 去重
        }
    }
    return array_keys($topics);
}

/// 縣市→有效區名 對照表（由 TaiwanDistricts.json 產生，與 App 的行政區名一致）。
function news_town_map(): array {
    static $map = null;
    if ($map === null) {
        $f = __DIR__ . '/TaiwanTowns.json';
        $decoded = is_file($f) ? json_decode(file_get_contents($f), true) : null;
        $map = is_array($decoded) ? $decoded : [];
    }
    return $map;
}

/// 把新聞（可能不乾淨）的 county+district 正規化成「有效行政區」的主題陣列。
/// 處理：多區（「三峽、樹林」→ 兩個）、缺後綴（「北屯」→「北屯區」）。對不上有效區名者略過。
/// 這是關鍵：只有算出「與 App 訂閱一致」的乾淨區名主題，通知才送得到。
function news_region_topics(string $county, string $districtField): array {
    $map = news_town_map();
    $countyKey = region_normalize($county);
    $validTowns = $map[$countyKey] ?? [];
    if (empty($validTowns)) { return []; }

    $validSet = [];
    foreach ($validTowns as $t) { $validSet[region_normalize($t)] = true; } // 正規化後的有效區名集合

    $topics = [];
    foreach (preg_split('/[、,，\/]/u', $districtField) as $part) {
        $p = region_normalize($part);
        if ($p === '') { continue; }
        $matched = null;
        if (isset($validSet[$p])) {
            $matched = $p;                                  // 已是有效區名（如「板橋區」）
        } else {
            foreach (['區', '市', '鄉', '鎮'] as $suffix) { // 缺後綴：補上試（如「北屯」→「北屯區」）
                if (isset($validSet[$p . $suffix])) { $matched = $p . $suffix; break; }
            }
        }
        if ($matched !== null) { $topics[region_topic($countyKey, $matched)] = true; }
    }
    return array_keys($topics);
}
