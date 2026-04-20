/**
 * NearSafe API client
 *
 * 自動帶 X-Device-Id header, 統一錯誤處理。
 * API base URL 從 app.json extra 取 (EXPO_PUBLIC_API_URL 或 dev fallback)。
 */
import Constants from 'expo-constants';
import { getOrCreateDeviceId } from './device';

const API_URL =
  process.env.EXPO_PUBLIC_API_URL ||
  Constants.expoConfig?.extra?.apiUrl ||
  'http://localhost:3000';

export class ApiError extends Error {
  constructor(public readonly status: number, public readonly body: unknown, message: string) {
    super(message);
    this.name = 'ApiError';
  }
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const deviceId = await getOrCreateDeviceId();
  const headers = new Headers(init.headers);
  headers.set('X-Device-Id', deviceId);
  headers.set('Content-Type', 'application/json');

  const res = await fetch(`${API_URL}${path}`, { ...init, headers });
  const bodyText = await res.text();
  let body: unknown = undefined;
  if (bodyText) {
    try {
      body = JSON.parse(bodyText);
    } catch {
      body = bodyText;
    }
  }

  if (!res.ok) {
    const message =
      body && typeof body === 'object' && body !== null && 'error' in body
        ? String((body as { error: unknown }).error)
        : `HTTP ${res.status}`;
    throw new ApiError(res.status, body, message);
  }

  return body as T;
}

// ============ Invites ============
export interface CreateInviteResponse {
  code: string;
  qrPayload: string;
  expiresAt: string;
}

export interface InvitePreview {
  code: string;
  watcherDisplayName: string | null;
  expiresAt: string;
}

export const api = {
  invites: {
    create: () => request<CreateInviteResponse>('/invites', { method: 'POST' }),
    preview: (code: string) => request<InvitePreview>(`/invites/${encodeURIComponent(code)}`),
    accept: (code: string) =>
      request<{ ok: true; relationshipId: string }>(
        `/invites/${encodeURIComponent(code)}/accept`,
        { method: 'POST' },
      ),
    reject: (code: string) =>
      request<{ ok: true }>(`/invites/${encodeURIComponent(code)}/reject`, { method: 'POST' }),
  },

  health: () => request<{ status: string; ts: string }>('/health'),
};
