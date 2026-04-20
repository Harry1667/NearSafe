/**
 * 邀請碼產生
 *
 * 原則:
 * - 短 (8 字元), 好講好打
 * - 去掉視覺混淆: 0/O, 1/I/l
 * - 靠 DB unique + retry, 不靠長度保證
 * - 單次使用 (consumed_at 設定後失效)
 * - 24h 過期
 */
import { randomInt } from 'node:crypto';

const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // 去掉 I, L, O, 0, 1
const CODE_LENGTH = 8;

export function generateInviteCode(): string {
  let out = '';
  for (let i = 0; i < CODE_LENGTH; i++) {
    out += ALPHABET[randomInt(ALPHABET.length)];
  }
  return out;
}

export const INVITE_TTL_MS = 24 * 60 * 60 * 1000; // 24h
