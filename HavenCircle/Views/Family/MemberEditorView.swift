import SwiftUI
import SwiftData

struct MemberEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var relationship = "家人"

    var body: some View {
        NavigationStack {
            Form {
                TextField("名稱", text: $name)
                TextField("關係", text: $relationship)
                Text("這只會建立此裝置中的家人資料與生活圈，不會邀請對方或同步安否回報。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("新增本機家人資料")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        context.insert(LocalFamilyMember(
                            name: name.isEmpty ? "家人" : name,
                            relationship: relationship
                        ))
                        context.saveReporting()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
