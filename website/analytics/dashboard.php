<?php
// 匿名統計看板：輸入管理密鑰後顯示最近 30 天的事件計數、版本與 iOS 分佈。
// 純伺服器端渲染，無外部依賴；沒有密鑰只會看到登入表單。
require __DIR__ . '/_analytics.php';

$authed = false;
$key = $_POST['key'] ?? '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $key !== '') {
    if (hash_equals(ANALYTICS_ADMIN_KEY, $key)) {
        $authed = true;
    } else {
        sleep(1); // 拖慢暴力嘗試
        http_response_code(403);
    }
}

$days = [];          // [日期 => 彙總]，只留有資料的日子
$eventTotals = [];   // 30 天事件總計
$versionTotals = [];
$osTotals = [];
if ($authed) {
    for ($i = 0; $i < 30; $i++) {
        $day = date('Y-m-d', strtotime("-$i day"));
        $agg = analytics_load_day($day);
        if ($agg === null) { continue; }
        $days[$day] = $agg;
        foreach ($agg['events'] ?? [] as $name => $count) { $eventTotals[$name] = ($eventTotals[$name] ?? 0) + $count; }
        foreach ($agg['versions'] ?? [] as $label => $count) { $versionTotals[$label] = ($versionTotals[$label] ?? 0) + $count; }
        foreach ($agg['os'] ?? [] as $label => $count) { $osTotals[$label] = ($osTotals[$label] ?? 0) + $count; }
    }
    arsort($eventTotals);
    arsort($versionTotals);
    arsort($osTotals);
}

$h = fn($text) => htmlspecialchars((string) $text, ENT_QUOTES, 'UTF-8');
?>
<!DOCTYPE html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>HavenCircle 匿名統計</title>
<style>
    body { font-family: -apple-system, "Noto Sans TC", sans-serif; max-width: 860px; margin: 2rem auto; padding: 0 1rem; background: #f6f8f7; color: #1a2b26; }
    h1 { font-size: 1.2rem; }
    h2 { font-size: 1rem; margin-top: 2rem; }
    table { border-collapse: collapse; width: 100%; background: #fff; border-radius: 8px; overflow: hidden; }
    th, td { padding: 0.5rem 0.75rem; border-bottom: 1px solid #e3ece9; text-align: left; font-size: 0.85rem; }
    th { background: #eaf3f0; }
    td.num { text-align: right; font-variant-numeric: tabular-nums; }
    input[type=password] { width: 100%; max-width: 420px; padding: 0.6rem; border: 1px solid #c5d4cf; border-radius: 8px; }
    button { margin-top: 0.75rem; padding: 0.6rem 1.5rem; background: #0F8A6B; color: #fff; border: 0; border-radius: 8px; font-size: 1rem; cursor: pointer; }
    .hint { font-size: 0.8rem; color: #5b6f68; }
</style>
</head>
<body>
<h1>HavenCircle 匿名統計（最近 30 天）</h1>
<?php if (!$authed): ?>
<?php if ($_SERVER['REQUEST_METHOD'] === 'POST'): ?><p class="hint">密鑰錯誤。</p><?php endif; ?>
<form method="post">
    <label>管理密鑰<br><input type="password" name="key" required></label>
    <br><button type="submit">查看</button>
</form>
<p class="hint">統計不含 IP、識別碼與位置；只有當日事件計數、App 版本與 iOS 大版本分佈。</p>
<?php else: ?>

<h2>事件總計</h2>
<table><tr><th>事件</th><th>30 天總次數</th></tr>
<?php foreach ($eventTotals as $name => $count): ?>
<tr><td><?= $h($name) ?></td><td class="num"><?= $h($count) ?></td></tr>
<?php endforeach; if ($eventTotals === []): ?><tr><td colspan="2">還沒有資料</td></tr><?php endif; ?>
</table>

<h2>每日明細</h2>
<table><tr><th>日期</th><th>事件計數</th></tr>
<?php foreach ($days as $day => $agg): ?>
<tr><td><?= $h($day) ?></td><td>
<?php
$parts = [];
$dayEvents = $agg['events'] ?? [];
arsort($dayEvents);
foreach ($dayEvents as $name => $count) { $parts[] = $h($name) . ' × ' . $h($count); }
echo $parts === [] ? '—' : implode('、', $parts);
?>
</td></tr>
<?php endforeach; if ($days === []): ?><tr><td colspan="2">還沒有資料</td></tr><?php endif; ?>
</table>

<h2>App 版本分佈（批次數）</h2>
<table><tr><th>版本</th><th>批次數</th></tr>
<?php foreach ($versionTotals as $label => $count): ?>
<tr><td><?= $h($label) ?></td><td class="num"><?= $h($count) ?></td></tr>
<?php endforeach; if ($versionTotals === []): ?><tr><td colspan="2">還沒有資料</td></tr><?php endif; ?>
</table>

<h2>iOS 版本分佈（批次數）</h2>
<table><tr><th>iOS</th><th>批次數</th></tr>
<?php foreach ($osTotals as $label => $count): ?>
<tr><td><?= $h($label) ?></td><td class="num"><?= $h($count) ?></td></tr>
<?php endforeach; if ($osTotals === []): ?><tr><td colspan="2">還沒有資料</td></tr><?php endif; ?>
</table>

<?php endif; ?>
</body>
</html>
