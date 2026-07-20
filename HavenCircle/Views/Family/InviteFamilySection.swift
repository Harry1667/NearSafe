import SwiftUI

/// 邀請家人的共用區塊：一鍵建立家庭圈並顯示邀請碼。
/// 存在理由：舊流程是「生活圈清單的按鈕 → 切到安否回報段 → 再點工具列第二顆按鈕」
/// 的雙層間接，使用者找不到真正的邀請入口；現在任何畫面嵌這個 Section 就能直接邀請。
/// 未登入時原地顯示引導，不把人丟到別的分頁自己想辦法。
struct InviteFamilySection: View {
    @Environment(FamilySyncService.self) private var sync
    @Environment(TabRouter.self) private var router

    @State private var showInviteOptions = false
    @State private var isWorking = false
    @State private var shareError: String?
    @State private var showJoinByCode = false

    var body: some View {
        Section {
            switch sync.state {
            case .noAccount:
                Label("家庭功能需要登入 iCloud", systemImage: "icloud.slash")
                    .foregroundStyle(HCColor.attention)
                Text("登入後可邀請家人、同步安否回報，並自行選擇是否分享即時位置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("查看 Apple 帳號狀態", systemImage: "gearshape") {
                    router.showSettings = true
                }
            default:
                Button {
                    Task { await startInvite() }
                } label: {
                    HStack {
                        Label("邀請家人加入安心圈", systemImage: "person.crop.circle.badge.plus")
                        if isWorking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isWorking || sync.state == .unknown)
                Button("用邀請碼加入家庭圈", systemImage: "textformat.123") {
                    showJoinByCode = true
                }
                if let shareError {
                    Text(shareError)
                        .font(.caption)
                        .foregroundStyle(HCColor.danger)
                }
                Text("邀請支援 QR code、8 位邀請碼或訊息連結；家人輸入邀請碼後就能互相回報平安。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showInviteOptions) {
            InviteOptionsView()
        }
        .sheet(isPresented: $showJoinByCode) {
            JoinByCodeView()
        }
        .task { await sync.refreshAccountStatus() }
    }

    /// 建立家庭圈（若尚未建立）並開啟邀請碼畫面。
    private func startInvite() async {
        isWorking = true
        shareError = nil
        defer { isWorking = false }
        do {
            // 已在家庭圈就沿用現有邀請碼；還沒有就建立一個新家庭圈
            if sync.currentInviteCode == nil {
                _ = try await sync.createFamily()
            }
            showInviteOptions = true
        } catch {
            // 失敗要讓使用者看到，不能只寫 log（silent fail 禁令）
            shareError = "建立家庭圈失敗：\(error.localizedDescription)"
            AppLog.cloudError("建立家庭圈失敗：\(error.localizedDescription)")
        }
    }
}
