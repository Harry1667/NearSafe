/**
 * 首頁 - 地圖 + 最近事件 (V1 先 stub, 顯示骨架)
 */
import { View, Text, StyleSheet, Pressable } from 'react-native';
import { Link } from 'expo-router';
import { SafeAreaView } from 'react-native-safe-area-context';

export default function HomeScreen() {
  return (
    <SafeAreaView style={styles.container} edges={['bottom']}>
      <View style={styles.mapPlaceholder}>
        <Text style={styles.mapPlaceholderText}>🗺️ 地圖</Text>
        <Text style={styles.mapPlaceholderSub}>(Leaflet/RN Maps 整合待做)</Text>
      </View>

      <View style={styles.card}>
        <Text style={styles.cardTitle}>過去 7 天一切平安</Text>
        <Text style={styles.cardSub}>沒有發生需要提醒你的事件</Text>
      </View>

      <Link href="/locations" asChild>
        <Pressable style={styles.button}>
          <Text style={styles.buttonText}>管理關注的人</Text>
        </Pressable>
      </Link>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff' },
  mapPlaceholder: {
    flex: 1,
    backgroundColor: '#eef2f7',
    justifyContent: 'center',
    alignItems: 'center',
  },
  mapPlaceholderText: { fontSize: 32 },
  mapPlaceholderSub: { marginTop: 8, color: '#64748b' },
  card: {
    padding: 20,
    backgroundColor: '#f0fdf4',
    marginHorizontal: 16,
    marginTop: 16,
    borderRadius: 12,
  },
  cardTitle: { fontSize: 16, fontWeight: '600', color: '#166534' },
  cardSub: { marginTop: 4, color: '#15803d' },
  button: {
    margin: 16,
    padding: 16,
    backgroundColor: '#0f172a',
    borderRadius: 12,
    alignItems: 'center',
  },
  buttonText: { color: '#fff', fontSize: 16, fontWeight: '600' },
});
