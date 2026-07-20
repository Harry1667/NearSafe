<?php
// 範本：實際的 _ai_config.php 只存在於 Oracle 伺服器、不進 repo（.gitignore）。
// 部署時在伺服器複製此檔為 _ai_config.php 並填入真實值。
//
// 這裡的機密永遠不下發到 App——App 只拿 APP_AI_KEY（低權限、可撤銷）。
define('PROXYCLI_URL', 'https://clip.twloop.com/api/chat'); // ProxyCLI REST 端點
define('PROXYCLI_TOKEN', 'REPLACE_WITH_PROXYCLI_BEARER_TOKEN'); // 靜態 Bearer，換 key 只改這裡
define('PROXYCLI_PROJECT', 'harry-HavenCircle'); // ProxyCLI 上已存在的專案（用量標籤）
define('APP_AI_KEY', 'REPLACE_WITH_APP_ACCESS_KEY'); // App 端存取金鑰；輪替只改這裡＋App 端
define('RATE_LIMIT', 20); // 每 IP 每 60 秒上限
