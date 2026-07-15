import SwiftUI
import SwiftData

/// 首次設定：建立本人與第一個生活圈
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var placeName = "住家"
    @State private var address = "台北市南港區"
    @State private var radius = 1000

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 54))
                        .foregroundStyle(.indigo)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    Text("守護家人的日常生活圈。")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                    Text("資料只儲存在這支手機；不會追蹤任何人的即時位置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                Section("先建立你的生活圈") {
                    TextField("你的名稱", text: $name)
                    TextField("地點名稱", text: $placeName)
                    TextField("城市或地址", text: $address)
                    Stepper("提醒半徑：\(radius) 公尺", value: $radius, in: 300...3000, step: 100)
                }
                Section {
                    Button("完成設定") { finishSetup() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("歡迎使用安心圈")
        }
    }

    private func finishSetup() {
        let me = LocalFamilyMember(name: name.isEmpty ? "我" : name, relationship: "擁有者")
        context.insert(me)
        context.insert(LocalLifeCircle(
            name: placeName.isEmpty ? "住家" : placeName,
            encryptedAddress: address,
            latitude: 25.0525,
            longitude: 121.6072,
            radiusMeters: radius,
            alertTypes: EventCategory.defaultSelection,
            member: me
        ))
        context.saveReporting()
    }
}

#Preview {
    OnboardingView()
        .modelContainer(PreviewSupport.container())
}
