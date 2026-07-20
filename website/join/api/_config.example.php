<?php
// 範本：實際 _config.php 只存在 Oracle 伺服器、不進 repo（見 join/api/.gitignore）。
// 部署時複製為 _config.php 並填入真實金鑰（32 bytes = 64 個 hex 字元）。
// 產生方式：openssl rand -hex 32
define('JOIN_CRYPT_KEY', 'REPLACE_WITH_64_HEX_CHARS');
