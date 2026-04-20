import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';

export default function RootLayout() {
  return (
    <SafeAreaProvider>
      <StatusBar style="auto" />
      <Stack>
        <Stack.Screen name="index" options={{ title: 'NearSafe' }} />
        <Stack.Screen name="locations" options={{ title: '關注的人' }} />
      </Stack>
    </SafeAreaProvider>
  );
}
