import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';

export default function RootLayout() {
  return (
    <SafeAreaProvider>
      <StatusBar style="auto" />
      <Stack>
        <Stack.Screen name="index" options={{ title: 'NearSafe' }} />
        <Stack.Screen name="locations" options={{ title: '關心的人' }} />
        <Stack.Screen name="invite/create" options={{ title: '邀請家人' }} />
        <Stack.Screen name="invite/scan" options={{ title: '接受邀請' }} />
        <Stack.Screen name="invite/[code]" options={{ title: '邀請確認' }} />
      </Stack>
    </SafeAreaProvider>
  );
}
