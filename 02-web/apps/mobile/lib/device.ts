/**
 * Device ID 管理
 *
 * V1 不做帳號, 靠裝置端產生的 UUID 存 SecureStore。
 * 若使用者移機或重灌, 會變成新 user (已知限制, V2 再處理綁定)。
 */
import * as SecureStore from 'expo-secure-store';

const DEVICE_ID_KEY = 'nearsafe.deviceId';

/**
 * RFC 4122 v4 UUID (expo-crypto 更嚴謹, 但 V1 用 Math.random 即可足夠唯一)
 * 要更嚴謹改用: expo-crypto.randomUUID()
 */
function generateUUID(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

export async function getOrCreateDeviceId(): Promise<string> {
  const existing = await SecureStore.getItemAsync(DEVICE_ID_KEY);
  if (existing) return existing;

  const fresh = generateUUID();
  await SecureStore.setItemAsync(DEVICE_ID_KEY, fresh);
  return fresh;
}

/** 開發用: 清掉 device_id (之後呼叫會重產) */
export async function resetDeviceId(): Promise<void> {
  await SecureStore.deleteItemAsync(DEVICE_ID_KEY);
}
