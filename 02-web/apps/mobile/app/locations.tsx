/**
 * 關注的人列表 (家人守護版核心頁)
 * V1 stub: 展示 "爸爸" + "媽媽" 兩個示範卡片
 */
import { View, Text, StyleSheet, Pressable, ScrollView } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

interface WatchedPersonStub {
  name: string;
  address: string;
  radiusKm: number;
  status: '已連線' | '待對方確認';
  recentEventsCount: number;
}

const STUB_DATA: WatchedPersonStub[] = [
  { name: '爸爸', address: '台中市西屯區', radiusKm: 3, status: '已連線', recentEventsCount: 0 },
  { name: '媽媽', address: '台中市西屯區', radiusKm: 3, status: '已連線', recentEventsCount: 0 },
];

export default function LocationsScreen() {
  return (
    <SafeAreaView style={styles.container} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.list}>
        {STUB_DATA.map((person) => (
          <View key={person.name} style={styles.card}>
            <View style={styles.cardHeader}>
              <Text style={styles.name}>{person.name}</Text>
              <Text style={[styles.badge, person.status === '已連線' ? styles.badgeOk : styles.badgeWait]}>
                {person.status}
              </Text>
            </View>
            <Text style={styles.meta}>{person.address} · 半徑 {person.radiusKm} km</Text>
            <Text style={styles.events}>
              過去 7 天事件: {person.recentEventsCount}
            </Text>
          </View>
        ))}

        <Pressable style={styles.addButton}>
          <Text style={styles.addButtonText}>+ 邀請家人</Text>
        </Pressable>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff' },
  list: { padding: 16, gap: 12 },
  card: {
    padding: 16,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#e2e8f0',
  },
  cardHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  name: { fontSize: 18, fontWeight: '600' },
  badge: { fontSize: 12, paddingHorizontal: 8, paddingVertical: 2, borderRadius: 8, overflow: 'hidden' },
  badgeOk: { backgroundColor: '#dcfce7', color: '#166534' },
  badgeWait: { backgroundColor: '#fef3c7', color: '#92400e' },
  meta: { marginTop: 6, color: '#64748b' },
  events: { marginTop: 6, color: '#475569', fontSize: 13 },
  addButton: {
    marginTop: 12,
    padding: 16,
    borderRadius: 12,
    borderWidth: 2,
    borderStyle: 'dashed',
    borderColor: '#cbd5e1',
    alignItems: 'center',
  },
  addButtonText: { color: '#475569', fontSize: 16, fontWeight: '600' },
});
