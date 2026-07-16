import SwiftUI
import SwiftData

struct MemberEditorView: View {
    /// "person"＝家人；"place"＝獨立重要地點（如老家、倉庫）——重用同一結構，只換文案
    var kind: String = "person"
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var relationship = "家人"

    private var isPlace: Bool { kind == "place" }

    var body: some View {
        NavigationStack {
            Form {
                TextField(isPlace ? "地點名稱（如：老家）" : "名稱", text: $name)
                if !isPlace {
                    TextField("關係", text: $relationship)
                }
                Text(isPlace
                     ? "重要地點跟家人一樣會收到警報、顯示在地圖上，適合放沒有人用手機、但你想看著的地方（老家、倉庫、店面）。儲存後記得幫它設定位置範圍。"
                     : "這只會建立此裝置中的家人資料與生活圈，不會邀請對方或同步安否回報。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle(isPlace ? "新增重要地點" : "新增本機家人資料")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        context.insert(LocalFamilyMember(
                            name: name.isEmpty ? (isPlace ? "重要地點" : "家人") : name,
                            relationship: isPlace ? "重要地點" : relationship,
                            kind: kind
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
