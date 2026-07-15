import SwiftUI
import SwiftData

/// 家人與生活圈清單（由 FamilyHubView 承載，與安否回報共用同一個分頁）
struct FamilyListView: View {
    /// 點「邀請家人」時切到安否回報段（邀請流程在那裡）
    var onInvite: () -> Void
    @Environment(\.modelContext) private var context
    @Query private var members: [LocalFamilyMember]
    @State private var adding = false

    var body: some View {
        List {
            Section {
                Button(action: onInvite) {
                    Label("邀請家人加入安心圈", systemImage: "person.crop.circle.badge.plus")
                }
                Text("家人接受邀請後，事件發生時可互相回報平安。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(members) { member in
                NavigationLink {
                    MemberDetailView(member: member)
                } label: {
                    HStack {
                        Image(systemName: "person.fill").foregroundStyle(.indigo)
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
            Button("新增家人", systemImage: "person.badge.plus") { adding = true }
        }
        .sheet(isPresented: $adding) { MemberEditorView() }
    }
}

#Preview {
    NavigationStack {
        FamilyListView(onInvite: {})
    }
    .modelContainer(PreviewSupport.container())
}
