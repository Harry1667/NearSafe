import SwiftUI
import SwiftData

/// 用 8 位邀請碼加入家庭圈：查 Firestore 邀請碼索引 → 加入該家庭的成員。
struct JoinByCodeView: View {
    @Environment(FamilySyncService.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var members: [LocalFamilyMember]
    @AppStorage(SettingsKeys.profileDisplayName) private var displayName = ""

    @State private var code = ""
    @State private var isJoining = false
    @State private var joinError: String?
    @State private var joined = false
    /// 加入成功後接身分選擇（C3）：新加入的人多半還沒被問過「你在家裡是誰」
    @State private var showRoleSelect = false

    private var isCodeValid: Bool {
        code.trimmingCharacters(in: .whitespaces).count == 8
    }

    var body: some View {
        NavigationStack {
            Form {
                if joined {
                    Section {
                        Label("已加入家庭圈！", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(HCColor.safe)
                        Text("現在可以在「安否回報」跟家人互報平安。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("輸入家人給你的 8 位邀請碼") {
                        TextField("例如 AB12CD34", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.system(.title2, design: .monospaced))
                            .onChange(of: code) { _, newValue in
                                // 只留合法字元、最多 8 碼，貼上帶空格也能正常
                                code = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(8))
                            }
                        Button {
                            Task { await join() }
                        } label: {
                            HStack {
                                Label("加入家庭圈", systemImage: "person.2.badge.plus")
                                if isJoining {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(!isCodeValid || isJoining)
                        if let joinError {
                            Text(joinError)
                                .font(.caption)
                                .foregroundStyle(HCColor.danger)
                        }
                    }
                }
            }
            .navigationTitle("用邀請碼加入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button(joined ? "完成" : "取消") { dismiss() }
            }
            .fullScreenCover(isPresented: $showRoleSelect) {
                RoleSelectView(
                    onSelect: { role in
                        applyRole(role)
                        showRoleSelect = false
                    },
                    onSkip: { showRoleSelect = false }
                )
            }
        }
    }

    private func join() async {
        isJoining = true
        joinError = nil
        defer { isJoining = false }
        do {
            try await sync.joinFamily(code: code)
            joined = true
            showRoleSelect = true
        } catch {
            joinError = error.localizedDescription
        }
    }

    private func applyRole(_ role: FamilyRole) {
        displayName = role.label
        if let me = members.first(where: \.isCurrentUser) {
            me.name = role.label
            context.saveReporting()
        }
        Analytics.track("role_selected")
    }
}
