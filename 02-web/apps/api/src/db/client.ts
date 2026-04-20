/**
 * Drizzle + postgres.js client
 * 單一 instance, 整個 API process 共用
 */
import postgres from 'postgres';
import { drizzle } from 'drizzle-orm/postgres-js';
import { env } from '../env.js';

const queryClient = postgres(env.DATABASE_URL, {
  max: 10, // connection pool
  idle_timeout: 20,
  connect_timeout: 10,
});

export const db = drizzle(queryClient);
export { queryClient };
