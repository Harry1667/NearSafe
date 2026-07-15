import SwiftUI
import SwiftData

struct FamilyListView: View {
    @Environment(\.modelContext) private var context
    @Query private var members: [LocalFamilyMember]
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
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
            .navigationTitle("家人與生活圈")
            .toolbar {
                Button("新增家人", systemImage: "person.badge.plus") { adding = true }
            }
            .sheet(isPresented: $adding) { MemberEditorView() }
        }
    }
}

#Preview {
    FamilyListView()
        .modelContainer(PreviewSupport.container())
}
