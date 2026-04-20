/**
 * NearSafe API entry point
 */
import Fastify from 'fastify';
import cors from '@fastify/cors';
import sensible from '@fastify/sensible';
import { env } from './env.js';
import { healthRoutes } from './routes/health.js';
import { inviteRoutes } from './routes/invites.js';
import { devicePlugin } from './plugins/device.js';

const app = Fastify({
  logger: {
    level: env.NODE_ENV === 'production' ? 'info' : 'debug',
    transport: env.NODE_ENV === 'development' ? { target: 'pino-pretty' } : undefined,
  },
});

// 中介層
await app.register(cors, { origin: true });
await app.register(sensible);
await app.register(devicePlugin);

// 路由
await app.register(healthRoutes);
await app.register(inviteRoutes);

// 啟動
try {
  await app.listen({ port: env.API_PORT, host: env.API_HOST });
  app.log.info(`🚀 NearSafe API listening on http://${env.API_HOST}:${env.API_PORT}`);
} catch (err) {
  app.log.error(err);
  process.exit(1);
}

// Graceful shutdown
for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, async () => {
    app.log.info(`收到 ${signal}, 關閉中...`);
    await app.close();
    process.exit(0);
  });
}
