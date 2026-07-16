import SwiftUI
import CloudKit

/// 邀請家人的共用區塊：一鍵直接觸發 CKShare 分享面板。
/// 存在理由：舊流程是「生活圈清單的按鈕 → 切到安否回報段 → 再點工具列第二顆按鈕」
/// 的雙層間接，使用者找不到真正的邀請入口；現在任何畫面嵌這個 Section 就能直接邀請。
/// 未登入 iCloud 時原地顯示引導，不把人丟到別的分頁自己想辦法。
struct InviteFamilySection: View {
    @Environment(FamilySyncService.self) private var sync
    @Environment(TabRouter.self) private var router

    @State private var shareSheet: ShareBundle?
    @State private var isWorking = false
    @State private var shareError: String?
    @State private var showJoinByCode = false

    struct ShareBundle: Identifiable {
        let id = UUID()
        let share: CKShare
        let container: CKContainer
    }

    var body: some View {
        Section {
            switch sync.state {
            case .noAccount:
                Label("邀請家人需要先登入 iCloud", systemImage: "icloud.slash")
                    .foregroundStyle(.orange)
                Button("查看 Apple 帳號狀態", systemImage: "gearshape") {
                    router.selection = TabRouter.settingsTab
                }
            default:
                Button {
                    Task { await startShare() }
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
                        .foregroundStyle(.red)
                }
                Text("邀請支援 QR code、8 位邀請碼或訊息連結；家人接受後就能互相回報平安。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(item: $shareSheet) { bundle in
            InviteOptionsView(share: bundle.share, container: bundle.container)
        }
        .sheet(isPresented: $showJoinByCode) {
            JoinByCodeView()
        }
        .task { await sync.refreshAccountStatus() }
    }

    private func startShare() async {
        isWorking = true
        shareError = nil
        defer { isWorking = false }
        do {
            let (share, container) = try await sync.makeShare()
            shareSheet = ShareBundle(share: share, container: container)
        } catch {
            // 失敗要讓使用者看到，不能只寫 log（silent fail 禁令）
            shareError = "建立邀請失敗：\(error.localizedDescription)"
            AppLog.cloudError("建立分享失敗：\(error.localizedDescription)")
        }
    }
}
