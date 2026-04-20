/**
 * /health - liveness + DB 連線檢查
 */
import type { FastifyPluginAsync } from 'fastify';
import { sql } from 'drizzle-orm';
import { db } from '../db/client.js';

export const healthRoutes: FastifyPluginAsync = async (app) => {
  app.get('/health', async () => {
    return { status: 'ok', ts: new Date().toISOString() };
  });

  app.get('/health/db', async (_req, reply) => {
    try {
      const result = await db.execute(sql`SELECT 1 as ok`);
      return { status: 'ok', result: result.at(0) };
    } catch (err) {
      // 錯誤要明確, 不 silent fail
      const message = err instanceof Error ? err.message : String(err);
      reply.status(503);
      return { status: 'error', message };
    }
  });
};
