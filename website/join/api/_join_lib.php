<?php
// 邀請碼所存的 CKShare 連結：以 AES-256-GCM 加密後才落地。
// 目的：就算 join/data/*.json 檔案單獨外洩（備份、目錄誤讀），沒有金鑰也還原不出可用的家庭邀請連結。
// 金鑰只在伺服器 _config.php（不進 git）。相容：無 enc: 前綴的舊明文原樣回傳，導入不破壞既有資料。
require __DIR__ . '/_config.php';

function join_encrypt($plain) {
    $key = hex2bin(JOIN_CRYPT_KEY);
    if ($key === false || strlen($key) !== 32) { return null; }
    $iv = random_bytes(12);
    $tag = '';
    $cipher = openssl_encrypt($plain, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $iv, $tag);
    if ($cipher === false) { return null; }
    return 'enc:' . base64_encode($iv . $tag . $cipher);
}

function join_decrypt($stored) {
    if (strncmp($stored, 'enc:', 4) !== 0) { return $stored; } // 相容舊明文
    $raw = base64_decode(substr($stored, 4), true);
    if ($raw === false || strlen($raw) < 28) { return null; }
    $key = hex2bin(JOIN_CRYPT_KEY);
    if ($key === false || strlen($key) !== 32) { return null; }
    $iv     = substr($raw, 0, 12);
    $tag    = substr($raw, 12, 16);
    $cipher = substr($raw, 28);
    $plain = openssl_decrypt($cipher, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $iv, $tag);
    return $plain === false ? null : $plain;
}
