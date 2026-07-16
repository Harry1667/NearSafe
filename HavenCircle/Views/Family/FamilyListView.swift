import SwiftUI
import SwiftData

/// 家人與生活圈清單（由 FamilyHubView 承載，與安否回報共用同一個分頁）
struct FamilyListView: View {
    @Environment(\.modelContext) private var context
    @Query private var members: [LocalFamilyMember]
    @State private var adding = false

    var body: some View {
        List {
            // 一鍵直接邀請（共用元件，不再跳轉到安否回報段找第二顆按鈕）
            InviteFamilySection()
            // 空狀態要有明確引導：入口只藏在右上角小圖示的話，長輩絕對找不到
            if members.isEmpty {
                ContentUnavailableView {
                    Label("還沒有家人資料", systemImage: "person.2")
                } description: {
                    Text("新增家人並設定他的生活圈（例如爸媽的住家），有事件靠近時就會提醒你。")
                } actions: {
                    Button("新增家人", systemImage: "person.badge.plus") { adding = true }
                        .buttonStyle(.borderedProminent)
                }
            }
            ForEach(members) { member in
                NavigationLink {
                    MemberDetailView(member: member)
                } label: {
                    HStack {
                        Image(systemName: "person.fill").foregroundStyle(HCColor.brand)
                        VStack(alignment: .leading) {
                            Text(member.name)
                            Text("\(member.lifeCircles.count) 個生活圈 · \(member.relationship)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        context.delete(member)
                        context.saveReporting()
                    } label: {
                        Label("刪除", systemImage: "trash")
                    }
                }
            }
        }
        .toolbar {
            Button("新增本機家人資料", systemImage: "person.badge.plus") { adding = true }
        }
        .sheet(isPresented: $adding) { MemberEditorView() }
    }
}

#Preview {
    NavigationStack {
        FamilyListView()
    }
    .modelContainer(PreviewSupport.container())
    .environment(FamilySyncService())
    .environment(TabRouter())
}
