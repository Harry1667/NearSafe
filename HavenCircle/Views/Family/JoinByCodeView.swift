import SwiftUI

/// 用 8 位邀請碼加入家庭圈：兌換連結 → 抓分享 metadata → 接受。
struct JoinByCodeView: View {
    @Environment(FamilySyncService.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isJoining = false
    @State private var joinError: String?
    @State private var joined = false

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
        }
    }

    private func join() async {
        isJoining = true
        joinError = nil
        defer { isJoining = false }
        do {
            let shareURL = try await JoinCodeService.redeem(code: code)
            try await sync.acceptShare(from: shareURL)
            // 接受階段的錯誤寫在 sync.state（沿用既有慣例），這裡讀出來呈現
            if case .error(let message) = sync.state {
                joinError = "加入失敗：\(message)"
            } else {
                joined = true
            }
        } catch {
            joinError = error.localizedDescription
        }
    }
}
