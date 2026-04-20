/**
 * 邀請家人 - 設定者端
 * 產生 8 字元短碼 + QR Code + 分享
 */
import { useEffect, useState } from 'react';
import { View, Text, StyleSheet, Pressable, ActivityIndicator, Share, Alert } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import QRCode from 'react-native-qrcode-svg';
import { api, ApiError } from '../../lib/api';

type State =
  | { kind: 'loading' }
  | { kind: 'ready'; code: string; qrPayload: string; expiresAt: string }
  | { kind: 'error'; message: string };

export default function CreateInviteScreen() {
  const [state, setState] = useState<State>({ kind: 'loading' });

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await api.invites.create();
        if (!cancelled) {
          setState({ kind: 'ready', code: res.code, qrPayload: res.qrPayload, expiresAt: res.expiresAt });
        }
      } catch (err) {
        const message = err instanceof ApiError ? err.message : '網路錯誤, 請稍後再試';
        if (!cancelled) setState({ kind: 'error', message });
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  async function handleShare(payload: string, code: string) {
    try {
      await Share.share({
        message: `我用 NearSafe 關心你。\n\n打開 app 掃描 QR 或輸入邀請碼: ${code}\n\n或點連結: ${payload}`,
      });
    } catch (err) {
      Alert.alert('分享失敗', String(err));
    }
  }

  return (
    <SafeAreaView style={styles.container} edges={['bottom']}>
      {state.kind === 'loading' && (
        <View style={styles.center}>
          <ActivityIndicator />
          <Text style={styles.loadingText}>產生邀請碼中...</Text>
        </View>
      )}

      {state.kind === 'error' && (
        <View style={styles.center}>
          <Text style={styles.errorTitle}>無法產生邀請碼</Text>
          <Text style={styles.errorMsg}>{state.message}</Text>
        </View>
      )}

      {state.kind === 'ready' && (
        <View style={styles.center}>
          <Text style={styles.hint}>請家人打開 NearSafe 掃描這個 QR, 或輸入下方 8 字元邀請碼</Text>

          <View style={styles.qrBox}>
            <QRCode value={state.qrPayload} size={220} />
          </View>

          <Text style={styles.code} selectable>{state.code}</Text>
          <Text style={styles.expiry}>
            有效期限: {new Date(state.expiresAt).toLocaleString('zh-TW')}
          </Text>

          <Pressable style={styles.shareBtn} onPress={() => handleShare(state.qrPayload, state.code)}>
            <Text style={styles.shareBtnText}>透過 Line / 簡訊傳給家人</Text>
          </Pressable>
        </View>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff' },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24, gap: 16 },
  loadingText: { color: '#64748b' },
  errorTitle: { fontSize: 18, fontWeight: '600', color: '#991b1b' },
  errorMsg: { color: '#475569', textAlign: 'center' },
  hint: { color: '#475569', textAlign: 'center', marginBottom: 8 },
  qrBox: {
    padding: 16,
    backgroundColor: '#fff',
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#e2e8f0',
  },
  code: {
    fontSize: 32,
    fontWeight: '700',
    letterSpacing: 4,
    fontFamily: 'Courier',
    color: '#0f172a',
    marginTop: 8,
  },
  expiry: { fontSize: 12, color: '#94a3b8' },
  shareBtn: {
    marginTop: 16,
    paddingVertical: 14,
    paddingHorizontal: 24,
    backgroundColor: '#0f172a',
    borderRadius: 12,
  },
  shareBtnText: { color: '#fff', fontSize: 16, fontWeight: '600' },
});
