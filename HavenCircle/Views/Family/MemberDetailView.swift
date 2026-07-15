import SwiftUI

struct MemberDetailView: View {
    let member: LocalFamilyMember
    @State private var adding = false

    var body: some View {
        List {
            Section {
                Text("僅儲存生活圈，未啟用即時位置追蹤")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("生活圈") {
                ForEach(member.lifeCircles) { circle in
                    VStack(alignment: .leading) {
                        Text(circle.name).font(.headline)
                        Text("\(circle.encryptedAddress) · 半徑 \(circle.radiusMeters) 公尺")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("提醒：\(circle.alertTypes.joined(separator: "、"))")
                            .font(.caption)
                            .foregroundStyle(.indigo)
                    }
                }
            }
            Button("新增生活圈", systemImage: "plus.circle.fill") { adding = true }
        }
        .navigationTitle(member.name)
        .sheet(isPresented: $adding) { CircleEditorView(member: member) }
    }
}
