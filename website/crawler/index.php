<?php
// 簡易狀態頁：讓人一眼看到爬蟲資料是否新鮮，並提供 API 端點說明。
$file = __DIR__ . '/data/latest.json';
$payload = null;
if (file_exists($file)) {
    $payload = json_decode(file_get_contents($file), true);
}

$receivedAt = $payload['received_at'] ?? null;
$count      = $payload['count'] ?? null;
$staleMinutes = null;
if ($receivedAt) {
    $staleMinutes = round((time() - strtotime($receivedAt)) / 60);
}
?>
<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>HavenCircle 爬蟲狀態</title>
<style>
  :root{--ink:#14232f;--navy:#123048;--muted:#5e6e79;--cream:#f6f4ee;--line:#d7d9d3;--lime:#c9e65e;--orange:#ff7b57}
  *{box-sizing:border-box}
  body{margin:0;background:var(--cream);color:var(--ink);font-family:"Noto Sans TC",Manrope,sans-serif;padding:60px 20px}
  .wrap{max-width:640px;margin:0 auto}
  h1{font-size:28px;letter-spacing:-1px;margin:0 0 6px}
  .sub{color:var(--muted);font-size:14px;margin:0 0 34px}
  .card{background:#fff;border:1px solid var(--line);border-radius:16px;padding:26px;margin-bottom:18px}
  .status{display:flex;align-items:center;gap:10px;font-size:15px;font-weight:700}
  .dot{width:10px;height:10px;border-radius:50%}
  .dot.ok{background:var(--lime)}
  .dot.warn{background:var(--orange)}
  .dot.off{background:#c94040}
  .meta{margin-top:14px;font-size:13px;color:var(--muted);line-height:1.9}
  .meta b{color:var(--ink)}
  code{background:var(--cream);border:1px solid var(--line);border-radius:6px;padding:2px 7px;font-size:12.5px}
  table{width:100%;border-collapse:collapse;font-size:13px}
  td{padding:9px 0;border-bottom:1px solid var(--line);vertical-align:top}
  td:first-child{color:var(--muted);width:120px}
  a{color:var(--navy)}
</style>
</head>
<body>
<div class="wrap">
  <h1>HavenCircle 爬蟲狀態</h1>
  <p class="sub">政府災害示警資料接收端 · 內部監看頁</p>

  <div class="card">
    <?php if (!$payload): ?>
      <div class="status"><span class="dot off"></span>尚未收到任何資料</div>
      <p class="meta">Mac Mini 爬蟲還沒推送過，或推送失敗，檢查爬蟲端 log。</p>
    <?php else:
      $isStale = $staleMinutes !== null && $staleMinutes > 30;
    ?>
      <div class="status">
        <span class="dot <?= $isStale ? 'warn' : 'ok' ?>"></span>
        <?= $isStale ? '資料可能過期' : '資料新鮮' ?>
      </div>
      <div class="meta">
        <table>
          <tr><td>最後更新</td><td><b><?= htmlspecialchars($receivedAt) ?></b>（UTC，約 <?= $staleMinutes ?> 分鐘前）</td></tr>
          <tr><td>示警筆數</td><td><b><?= $count === null ? '—' : $count ?></b></td></tr>
        </table>
      </div>
    <?php endif; ?>
  </div>

  <div class="card">
    <div class="status" style="font-size:14px">API 端點</div>
    <div class="meta">
      <table>
        <tr><td>接收（爬蟲用）</td><td><code>POST /crawler/api/ingest.php</code><br>需帶 <code>X-Ingest-Key</code> header</td></tr>
        <tr><td>拉取（App 用）</td><td><code>GET /crawler/api/latest.php</code> → <a href="/crawler/api/latest.php">看原始 JSON</a></td></tr>
      </table>
    </div>
  </div>
</div>
</body>
</html>
