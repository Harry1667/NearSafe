/**
 * 環境變數載入 + 驗證
 * 使用 zod 在啟動時就 fail-fast, 不允許 silent undefined
 *
 * Monorepo: 從 repo root (02-web/) 的 .env 讀, 不是 apps/api/ 本地的
 */
import { config as loadDotenv } from 'dotenv';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { z } from 'zod';

const __dirname = dirname(fileURLToPath(import.meta.url));
// apps/api/src/ → ../../../
loadDotenv({ path: resolve(__dirname, '../../../.env') });

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  API_PORT: z.coerce.number().int().positive().default(3000),
  API_HOST: z.string().default('0.0.0.0'),
  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url(),
  ANTHROPIC_API_KEY: z.string().min(1).optional(), // AI pipeline 之後才用到
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  console.error('❌ 環境變數驗證失敗:');
  console.error(parsed.error.format());
  process.exit(1);
}

export const env = parsed.data;
