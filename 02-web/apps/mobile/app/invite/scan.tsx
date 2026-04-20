/**
 * 接受邀請 - 被邀請者端
 * 兩種路徑: 掃 QR Code 或手動輸入 8 字元
 */
import { useState } from 'react';
import { View, Text, StyleSheet, Pressable, TextInput, Alert } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { CameraView, useCameraPermissions } from 'expo-camera';
import { useRouter } from 'expo-router';

const DEEP_LINK_PREFIX = 'nearsafe://invite/';

function extractCode(raw: string): string | null {
  const trimmed = raw.trim();
  if (trimmed.startsWith(DEEP_LINK_PREFIX)) {
    return trimmed.slice(DEEP_LINK_PREFIX.length).toUpperCase();
  }
  // 純 8 字元短碼
  if (/^[A-Z2-9]{6,16}$/i.test(trimmed)) {
    return trimmed.toUpperCase();
  }
  return null;
}

export default function ScanInviteScreen() {
  const router = useRouter();
  const [permission, requestPermission] = useCameraPermissions();
  const [scanned, setScanned] = useState(false);
  const [manualCode, setManualCode] = useState('');

  function goToPreview(code: string) {
    setScanned(true);
    router.push({ pathname: '/invite/[code]', params: { code } });
  }

  function handleBarcode(data: string) {
    if (scanned) return;
    const code = extractCode(data);
    if (!code) {
      Alert.alert('無效 QR Code', '這不是 NearSafe 的邀請碼');
      return;
    }
    goToPreview(code);
  }

  function handleManualSubmit() {
    const code = extractCode(manualCode);
    if (!code) {
      Alert.alert('格式不對', '邀請碼是 8 個英數字, 例如 ABCD2345');
      return;
    }
    goToPreview(code);
  }

  if (!permission) {
    return (
      <SafeAreaView style={styles.container}>
        <Text>載入中...</Text>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container} edges={['bottom']}>
      {permission.granted ? (
        <View style={styles.cameraBox}>
          <CameraView
            style={styles.camera}
            facing="back"
            onBarcodeScanned={scanned ? undefined : (evt) => handleBarcode(evt.data)}
            barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
          />
          <Text style={styles.scanHint}>將家人寄來的 QR Code 對準鏡頭</Text>
        </View>
      ) : (
        <View style={styles.permissionBox}>
          <Text style={styles.permissionText}>需要相機權限來掃描邀請碼</Text>
          <Pressable style={styles.primaryBtn} onPress={requestPermission}>
            <Text style={styles.primaryBtnText}>開啟相機權限</Text>
          </Pressable>
        </View>
      )}

      <View style={styles.manualBox}>
        <Text style={styles.manualLabel}>或手動輸入 8 字元邀請碼</Text>
        <TextInput
          style={styles.input}
          value={manualCode}
          onChangeText={setManualCode}
          autoCapitalize="characters"
          autoCorrect={false}
          placeholder="ABCD2345"
          placeholderTextColor="#cbd5e1"
          maxLength={16}
        />
        <Pressable
          style={[styles.primaryBtn, !manualCode && styles.primaryBtnDisabled]}
          onPress={handleManualSubmit}
          disabled={!manualCode}
        >
          <Text style={styles.primaryBtnText}>繼續</Text>
        </Pressable>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff' },
  cameraBox: { flex: 1 },
  camera: { flex: 1 },
  scanHint: {
    position: 'absolute',
    bottom: 16,
    alignSelf: 'center',
    color: '#fff',
    backgroundColor: 'rgba(0,0,0,0.5)',
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 999,
  },
  permissionBox: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24, gap: 16 },
  permissionText: { textAlign: 'center', color: '#475569' },
  manualBox: { padding: 20, borderTopWidth: 1, borderTopColor: '#e2e8f0', gap: 12 },
  manualLabel: { color: '#475569', fontSize: 14 },
  input: {
    borderWidth: 1,
    borderColor: '#cbd5e1',
    borderRadius: 12,
    paddingHorizontal: 16,
    paddingVertical: 12,
    fontSize: 20,
    letterSpacing: 4,
    fontFamily: 'Courier',
  },
  primaryBtn: {
    backgroundColor: '#0f172a',
    paddingVertical: 14,
    borderRadius: 12,
    alignItems: 'center',
  },
  primaryBtnDisabled: { opacity: 0.4 },
  primaryBtnText: { color: '#fff', fontSize: 16, fontWeight: '600' },
});
