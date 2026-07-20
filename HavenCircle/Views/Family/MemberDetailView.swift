import SwiftUI
import SwiftData

struct MemberDetailView: View {
    let member: LocalFamilyMember
    @Environment(\.modelContext) private var context
    @State private var adding = false
    @State private var editing: LocalLifeCircle?

    var body: some View {
        List {
            if member.isCurrentUser {
                // 自己的詳情頁直接放即時圈控制，不再是「請回家人頁開啟」的死路文字
                LiveCircleSharingSection()
            } else {
                Section("即時圈") {
                    let liveCircles = member.lifeCircles.filter { $0.kind == .live }
                    if liveCircles.isEmpty {
                        Text("等待這位家人在自己的手機上開啟位置分享")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(liveCircles) { circle in
                            circleRow(circle)
                        }
                    }
                }
            }
            Section("固定圈") {
                let fixedCircles = member.lifeCircles.filter { $0.kind == .fixed }
                if fixedCircles.isEmpty {
                    Text("尚未設定住家、倉庫或其他固定資產")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(fixedCircles) { circle in
                        Button { editing = circle } label: { circleRow(circle) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    context.delete(circle)
                                    context.saveReporting()
                                } label: {
                                    Label("刪除", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            Button("新增固定圈", systemImage: "plus.circle.fill") { adding = true }
        }
        .navigationTitle(member.name)
        .sheet(isPresented: $adding) { CircleEditorView(member: member) }
        .sheet(item: $editing) { circle in
            CircleEditorView(member: member, circle: circle)
        }
    }

    private func circleRow(_ circle: LocalLifeCircle) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(circle.name).font(.headline)
                Label(circle.kind.title, systemImage: circle.kind.iconName)
                    .font(.caption2.bold())
                    .foregroundStyle(circle.kind == .live ? HCColor.safe : HCColor.brand)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (circle.kind == .live ? HCColor.safe : HCColor.brand).opacity(0.12),
                        in: Capsule()
                    )
            }
            Text("\(circle.addressText) · 警戒半徑 \(circle.radiusMeters) 公尺")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if circle.kind == .live {
                Label(
                    circle.locationFreshnessText,
                    systemImage: circle.isActiveForAlerts ? "checkmark.circle.fill" : "clock.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(circle.isActiveForAlerts ? HCColor.safe : HCColor.attention)
            }
            Text("提醒：\(circle.alertTypes.joined(separator: "、")) · \(circle.scheduleText)")
                .font(.caption)
                .foregroundStyle(HCColor.brand)
        }
    }
}
