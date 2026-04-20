/**
 * 邀請預覽 + 接受/拒絕
 * 支援兩種入口: 掃碼 ( /invite/scan → router.push ) 或 deep link (nearsafe://invite/XXX)
 */
import { useEffect, useState } from 'react';
import { View, Text, StyleSheet, Pressable, ActivityIndicator, Alert } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { api, ApiError } from '../../lib/api';

type State =
  | { kind: 'loading' }
  | { kind: 'ready'; watcherName: string; expiresAt: string }
  | { kind: 'invalid'; message: string }
  | { kind: 'submitting' }
  | { kind: 'done'; outcome: 'accepted' | 'rejected' };

export default function InvitePreviewScreen() {
  const { code } = useLocalSearchParams<{ code: string }>();
  const router = useRouter();
  const [state, setState] = useState<State>({ kind: 'loading' });

  useEffect(() => {
    if (!code) {
      setState({ kind: 'invalid', message: '無邀請碼' });
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const preview = await api.invites.preview(code);
        if (!cancelled) {
          setState({
            kind: 'ready',
            watcherName: preview.watcherDisplayName ?? '一位家人',
            expiresAt: preview.expiresAt,
          });
        }
      } catch (err) {
        if (cancelled) return;
        const message = err instanceof ApiError ? err.message : '網路錯誤';
        setState({ kind: 'invalid', message });
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [code]);

  async function handleAccept() {
    if (!code) return;
    setState({ kind: 'submitting' });
    try {
      await api.invites.accept(code);
      setState({ kind: 'done', outcome: 'accepted' });
    } catch (err) {
      const message = err instanceof ApiError ? err.message : '網路錯誤';
      Alert.alert('接受失敗', message);
      setState({ kind: 'invalid', message });
    }
  }

  async function handleReject() {
    if (!code) return;
    setState({ kind: 'submitting' });
    try {
      await api.invites.reject(code);
      setState({ kind: 'done', outcome: 'rejected' });
    } catch (err) {
      const message = err instanceof ApiError ? err.message : '網路錯誤';
      Alert.alert('拒絕失敗', message);
      setState({ kind: 'invalid', message });
    }
  }

  return (
    <SafeAreaView style={styles.container} edges={['bottom']}>
      <View style={styles.center}>
        {state.kind === 'loading' && (
          <>
            <ActivityIndicator />
            <Text style={styles.muted}>確認邀請中...</Text>
          </>
        )}

        {state.kind === 'invalid' && (
          <>
            <Text style={styles.title}>邀請無效</Text>
            <Text style={styles.muted}>{state.message}</Text>
            <Pressable style={styles.secondaryBtn} onPress={() => router.back()}>
              <Text style={styles.secondaryBtnText}>返回</Text>
            </Pressable>
          </>
        )}

        {state.kind === 'ready' && (
          <>
            <Text style={styles.eyebrow}>邀請碼 {code}</Text>
            <Text style={styles.title}>{state.watcherName} 想關心你</Text>
            <Text style={styles.body}>
              接受後, 當你家附近發生大型火災、暴力或重大交通事故時, {state.watcherName} 會收到推播通知,
              可以立刻打電話關心你。
            </Text>
            <Text style={styles.muted}>
              · 我們不會追蹤你的實時位置{'\n'}
              · 你隨時可以從「關心你的人」清單移除
            </Text>

            <View style={styles.btnRow}>
              <Pressable style={styles.rejectBtn} onPress={handleReject}>
                <Text style={styles.rejectBtnText}>拒絕</Text>
              </Pressable>
              <Pressable style={styles.acceptBtn} onPress={handleAccept}>
                <Text style={styles.acceptBtnText}>接受</Text>
              </Pressable>
            </View>
          </>
        )}

        {state.kind === 'submitting' && (
          <>
            <ActivityIndicator />
            <Text style={styles.muted}>處理中...</Text>
          </>
        )}

        {state.kind === 'done' && state.outcome === 'accepted' && (
          <>
            <Text style={styles.title}>✓ 已接受</Text>
            <Text style={styles.body}>你現在在對方「關心的人」清單上了。</Text>
            <Pressable style={styles.primaryBtn} onPress={() => router.replace('/')}>
              <Text style={styles.primaryBtnText}>回首頁</Text>
            </Pressable>
          </>
        )}

        {state.kind === 'done' && state.outcome === 'rejected' && (
          <>
            <Text style={styles.title}>已拒絕</Text>
            <Text style={styles.muted}>邀請不會影響你的任何資料。</Text>
            <Pressable style={styles.primaryBtn} onPress={() => router.replace('/')}>
              <Text style={styles.primaryBtnText}>回首頁</Text>
            </Pressable>
          </>
        )}
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff' },
  center: { flex: 1, padding: 24, justifyContent: 'center', gap: 16 },
  eyebrow: { color: '#64748b', fontSize: 12, letterSpacing: 2 },
  title: { fontSize: 24, fontWeight: '700', color: '#0f172a' },
  body: { fontSize: 16, color: '#334155', lineHeight: 24 },
  muted: { fontSize: 13, color: '#64748b', lineHeight: 20 },
  btnRow: { flexDirection: 'row', gap: 12, marginTop: 24 },
  acceptBtn: {
    flex: 1,
    backgroundColor: '#0f172a',
    paddingVertical: 14,
    borderRadius: 12,
    alignItems: 'center',
  },
  acceptBtnText: { color: '#fff', fontSize: 16, fontWeight: '600' },
  rejectBtn: {
    flex: 1,
    backgroundColor: '#f1f5f9',
    paddingVertical: 14,
    borderRadius: 12,
    alignItems: 'center',
  },
  rejectBtnText: { color: '#475569', fontSize: 16, fontWeight: '600' },
  primaryBtn: {
    marginTop: 24,
    backgroundColor: '#0f172a',
    paddingVertical: 14,
    borderRadius: 12,
    alignItems: 'center',
  },
  primaryBtnText: { color: '#fff', fontSize: 16, fontWeight: '600' },
  secondaryBtn: {
    marginTop: 24,
    backgroundColor: '#f1f5f9',
    paddingVertical: 14,
    paddingHorizontal: 32,
    borderRadius: 12,
  },
  secondaryBtnText: { color: '#475569', fontSize: 16, fontWeight: '600' },
});
