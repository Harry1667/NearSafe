/**
 * NearSafe 共用型別 - API 與 mobile 共用
 * 依 CEO plan 2026-04-20, V1 只支援 3 類事件
 */

// ============ 事件類型 ============
export const SAFETY_CATEGORIES = ['fire', 'violence', 'traffic'] as const;
export type SafetyCategory = (typeof SAFETY_CATEGORIES)[number];

export const CATEGORY_LABELS_ZH: Record<SafetyCategory, string> = {
  fire: '火災',
  violence: '暴力事件',
  traffic: '重大交通',
};

// ============ 嚴重度 ============
// 1-5, AI 分類輸出。誤報成本高, 家人版預設只推 >= 3
export type Severity = 1 | 2 | 3 | 4 | 5;

// ============ 地理位置 ============
export interface GeoPoint {
  lat: number;
  lng: number;
}

// ============ 關注地點 ============
export type WatchRadius = 1000 | 3000 | 5000; // metres

export interface WatchedLocation {
  id: string;
  userId: string;
  name: string; // "家"、"爸爸家"
  address: string;
  point: GeoPoint;
  radiusM: WatchRadius;
  isPaused: boolean;
  createdAt: string; // ISO 8601
}

// ============ 使用者關係 (家人守護版核心) ============
export type RelationshipStatus = 'pending' | 'accepted' | 'rejected' | 'revoked';

export interface Relationship {
  id: string;
  watcherUserId: string; // 設定關注的人 (北漂子女)
  watchedUserId: string; // 被關注的人 (家鄉父母)
  status: RelationshipStatus;
  createdAt: string;
  respondedAt: string | null;
}

// ============ 邀請碼 (QR Code 的底層資料) ============
export interface InviteCode {
  code: string; // 短碼, 24h 有效, 單次使用
  watcherUserId: string;
  expiresAt: string;
  consumedAt: string | null;
}

// ============ 事件 ============
export interface SafetyEvent {
  id: string;
  category: SafetyCategory;
  severity: Severity;
  point: GeoPoint;
  title: string;
  summary: string; // AI 生成短句, ≤40 字
  sources: Array<{ name: string; url: string }>;
  occurredAt: string;
  createdAt: string;
}

// ============ 推播 payload ============
export interface PushPayload {
  eventId: string;
  watchedLocationId: string;
  distanceM: number;
  targetUserName: string; // "爸爸"、"小明"
  category: SafetyCategory;
  title: string;
  body: string;
  actions: PushAction[];
}

// 通知行動按鈕 - 家人版的核心 feature
export type PushActionType = 'call' | 'line' | 'safety_check' | 'view_map';

export interface PushAction {
  type: PushActionType;
  label: string;
  // 依 type 不同, payload 不同
  payload: Record<string, string>;
}

// ============ 推播回饋 ============
export type FeedbackType = 'helpful' | 'too_noisy';

// ============ 使用者設定 ============
export interface UserSettings {
  enabledCategories: SafetyCategory[];
  frequency: 'strict' | 'normal' | 'curated'; // 嚴格/一般/超嚴選
  quietHours: { start: string; end: string } | null; // "23:00" - "07:00"
}
