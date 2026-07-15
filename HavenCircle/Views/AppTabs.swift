import SwiftUI
import SwiftData

struct AppTabs: View {
    var body: some View {
        TabView {
            SafetyMapView()
                .tabItem { Label("安全地圖", systemImage: "map.fill") }
            EventListView()
                .tabItem { Label("提醒中心", systemImage: "bell.badge.fill") }
            FamilyListView()
                .tabItem { Label("家人", systemImage: "person.2.fill") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "slider.horizontal.3") }
        }
        .tint(.indigo)
    }
}

#Preview {
    AppTabs()
        .modelContainer(PreviewSupport.container())
}
