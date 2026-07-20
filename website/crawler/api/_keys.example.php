<?php
// 範本：實際的 _keys.php 只存在於 Oracle 伺服器、不進 repo（見 crawler/.gitignore）。
// 由 keys_admin.php 寫入與維護；直接以網址存取 _keys.php 會被 PHP 執行、輸出空白，不外洩。
//
// 這裡放的是「對外資料源」的授權碼（政府開放資料），不是付費／私有 token。
return [
    'cwa_key'      => 'CWA-XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX', // 中央氣象署授權碼
    'ncdr_api_key' => 'REPLACE_WITH_NCDR_API_KEY',               // NCDR 災害示警 API 金鑰（約一年到期）
    'moenv_key'    => 'REPLACE_WITH_MOENV_API_KEY',              // 環境部空品 API 金鑰
];
