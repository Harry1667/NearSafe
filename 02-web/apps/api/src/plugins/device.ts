/**
 * Device ID 中介層
 *
 * V1 不做帳號, 直接用 mobile 端產生的 UUID (存 SecureStore / AsyncStorage) 當 device_id,
 * 透過 X-Device-Id header 帶過來。
 *
 * 找不到對應 user 就自動建立一個 (第一次使用)。
 *
 * 注意: 這個方案在「同人換手機」會變成不同 user。V1 先接受這個限制,
 * V2 再加「邀請家人」時順便做帳號綁定。
 */
import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import fp from 'fastify-plugin';
import { eq } from 'drizzle-orm';
import { db } from '../db/client.js';
import { users } from '../db/schema.js';

export interface AuthedUser {
  id: string;
  deviceId: string;
  displayName: string | null;
}

declare module 'fastify' {
  interface FastifyRequest {
    user?: AuthedUser;
  }
}

async function resolveUser(deviceId: string): Promise<AuthedUser> {
  const existing = await db.select().from(users).where(eq(users.deviceId, deviceId)).limit(1);
  const found = existing.at(0);
  if (found) {
    return { id: found.id, deviceId: found.deviceId, displayName: found.displayName };
  }

  // 第一次看到這個 device, 建使用者
  const [created] = await db
    .insert(users)
    .values({ deviceId })
    .returning();

  if (!created) {
    // 理論不會進來 (insert with returning 必定有值)
    throw new Error('使用者建立失敗');
  }

  return { id: created.id, deviceId: created.deviceId, displayName: created.displayName };
}

export const devicePlugin: FastifyPluginAsync = fp(async (app) => {
  // Fastify 5: decorateRequest 需 getter 或 undefined
  app.decorateRequest('user', undefined);

  app.addHook('preHandler', async (req: FastifyRequest, reply) => {
    // /health 路由不需要 device id
    if (req.url.startsWith('/health')) return;

    const deviceId = req.headers['x-device-id'];
    if (typeof deviceId !== 'string' || deviceId.length < 8 || deviceId.length > 128) {
      reply.status(400);
      throw new Error('缺少或非法的 X-Device-Id header');
    }

    req.user = await resolveUser(deviceId);
  });
});

/**
 * 在 route handler 內保證 user 已 resolved
 */
export function requireUser(req: FastifyRequest): AuthedUser {
  if (!req.user) throw new Error('user 未解析, 中介層未掛載?');
  return req.user;
}
