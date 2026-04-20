/**
 * Drizzle schema - V1 家人守護版
 * 對應 packages/shared 型別
 *
 * 注意: PostGIS 的 geography 欄位 Drizzle 原生支援有限,
 * 這裡用 customType + raw SQL 處理。
 */
import { customType, pgTable, text, uuid, timestamp, boolean, integer, jsonb, pgEnum, index, uniqueIndex } from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';

// PostGIS geography(Point, 4326) 自訂型別
const geographyPoint = customType<{ data: { lat: number; lng: number }; driverData: string }>({
  dataType() {
    return 'geography(Point, 4326)';
  },
  toDriver(value) {
    // 寫入: 產生 WKT (Well-Known Text) 格式
    return `POINT(${value.lng} ${value.lat})`;
  },
  fromDriver(value) {
    // Postgres 回傳 WKB (hex), 實際使用時通常用 ST_X/ST_Y 查詢, 這裡只做 fallback
    return { lat: 0, lng: 0 };
  },
});

// ============ Enums ============
export const safetyCategoryEnum = pgEnum('safety_category', ['fire', 'violence', 'traffic']);
export const relationshipStatusEnum = pgEnum('relationship_status', ['pending', 'accepted', 'rejected', 'revoked']);
export const feedbackTypeEnum = pgEnum('feedback_type', ['helpful', 'too_noisy']);

// ============ Tables ============

// 使用者 (V1 匿名, 靠 device_id)
export const users = pgTable('users', {
  id: uuid('id').primaryKey().default(sql`uuid_generate_v4()`),
  deviceId: text('device_id').notNull().unique(),
  displayName: text('display_name'), // "爸爸"、"小明" 等, 用於推播文案
  pushToken: text('push_token'), // FCM token
  pushPlatform: text('push_platform'), // 'ios' | 'android'
  settings: jsonb('settings').notNull().default(sql`'{}'::jsonb`),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
});

// 關注地點
export const watchedLocations = pgTable('watched_locations', {
  id: uuid('id').primaryKey().default(sql`uuid_generate_v4()`),
  watcherUserId: uuid('watcher_user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  // 若這個地點「對應」某個被關注者 (家人版核心), 指向 relationships.id
  relationshipId: uuid('relationship_id').references(() => relationships.id, { onDelete: 'set null' }),
  name: text('name').notNull(),
  address: text('address').notNull(),
  point: geographyPoint('point').notNull(),
  radiusM: integer('radius_m').notNull(),
  isPaused: boolean('is_paused').notNull().default(false),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
}, (table) => ({
  // GIST index, ST_DWithin 靠這個在萬筆地點上毫秒級
  pointIdx: index('watched_locations_point_gist').using('gist', table.point),
  watcherIdx: index('watched_locations_watcher_idx').on(table.watcherUserId),
}));

// 雙向關係 (家人同意機制)
export const relationships = pgTable('relationships', {
  id: uuid('id').primaryKey().default(sql`uuid_generate_v4()`),
  watcherUserId: uuid('watcher_user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  watchedUserId: uuid('watched_user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  status: relationshipStatusEnum('status').notNull().default('pending'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  respondedAt: timestamp('responded_at', { withTimezone: true }),
}, (table) => ({
  // 同一對 (watcher, watched) 只能有一組非 revoked 關係 — 這裡用 unique, revoked 後移除再建
  pairUnique: uniqueIndex('relationships_pair_unique').on(table.watcherUserId, table.watchedUserId),
}));

// 邀請碼 (QR Code)
export const inviteCodes = pgTable('invite_codes', {
  code: text('code').primaryKey(), // 短碼, unique
  watcherUserId: uuid('watcher_user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  consumedAt: timestamp('consumed_at', { withTimezone: true }),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
});

// 事件
export const events = pgTable('events', {
  id: uuid('id').primaryKey().default(sql`uuid_generate_v4()`),
  category: safetyCategoryEnum('category').notNull(),
  severity: integer('severity').notNull(), // 1-5
  point: geographyPoint('point').notNull(),
  title: text('title').notNull(),
  summary: text('summary').notNull(),
  sources: jsonb('sources').notNull().default(sql`'[]'::jsonb`),
  fingerprint: text('fingerprint').notNull().unique(), // 去重 hash
  occurredAt: timestamp('occurred_at', { withTimezone: true }).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
}, (table) => ({
  pointIdx: index('events_point_gist').using('gist', table.point),
  occurredIdx: index('events_occurred_idx').on(table.occurredAt.desc()),
}));

// 推播記錄 (含行動按鈕點擊、回饋)
export const notifications = pgTable('notifications', {
  id: uuid('id').primaryKey().default(sql`uuid_generate_v4()`),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  eventId: uuid('event_id').notNull().references(() => events.id, { onDelete: 'cascade' }),
  watchedLocationId: uuid('watched_location_id').notNull().references(() => watchedLocations.id, { onDelete: 'cascade' }),
  distanceM: integer('distance_m').notNull(),
  feedback: feedbackTypeEnum('feedback'),
  actionTaken: text('action_taken'), // 'call' | 'line' | 'safety_check' | 'view_map' | null
  sentAt: timestamp('sent_at', { withTimezone: true }).notNull().defaultNow(),
});
