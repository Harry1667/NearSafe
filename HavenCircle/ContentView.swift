import SwiftUI
import SwiftData

/// App 根畫面：尚未建立任何家人時走首次設定，否則進入主分頁
struct ContentView: View {
    @Query private var members: [LocalFamilyMember]

    var body: some View {
        if members.isEmpty {
            OnboardingView()
        } else {
            AppTabs()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewSupport.container())
}
