import SwiftUI
import CloudKit

/// 安否回報中心：雙向閉環的回報端。
/// - 上半：我一鍵回報「我平安 / 需要協助」
/// - 下半：家人的回報清單與已讀回條
/// - 工具列：邀請家人加入家庭圈（CKShare）
struct SafetyCheckInView: View {
    @Environment(FamilySyncService.self) private var sync
    let myName: String

    @State private var shareSheet: ShareBundle?
    @State private var note = ""
    @State private var isWorking = false

    struct ShareBundle: Identifiable {
        let id = UUID()
        let share: CKShare
        let container: CKContainer
    }

    var body: some View {
        // 由 FamilyHubView 承載（提供 NavigationStack 與分段切換）
        List {
            accountSection
            if sync.state == .sharing || !sync.pings.isEmpty {
                checkInSection
                familyPingsSection
            }
        }
        .toolbar {
            Button("邀請家人", systemImage: "person.badge.plus") {
                Task { await startShare() }
            }
            .disabled(sync.state == .noAccount || isWorking)
        }
        .sheet(item: $shareSheet) { bundle in
            CloudSharingSheet(share: bundle.share, container: bundle.container)
        }
        .task {
            await sync.refreshAccountStatus()
            await sync.fetchPings()
        }
        .refreshable { await sync.fetchPings() }
    }

    @ViewBuilder
    private var accountSection: some View {
        switch sync.state {
        case .noAccount:
            Section {
                Label("尚未登入 iCloud", systemImage: "icloud.slash")
                    .foregroundStyle(.orange)
                Text("安否回報需要 iCloud 才能在家人之間同步。請到「設定 > Apple 帳號」登入後再回來。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .error(let message):
            Section {
                Label("同步發生問題", systemImage: "exclamationmark.icloud")
                    .foregroundStyle(.red)
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        case .ready:
            Section {
                Text("按右上角「邀請家人」建立你的家庭圈，家人接受後就能互相回報平安。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .sharing, .unknown:
            EmptyView()
        }
    }

    private var checkInSection: some View {
        Section("回報我的狀態") {
            TextField("補充說明（選填）", text: $note)
            ForEach(SafetyStatus.allCases, id: \.self) { status in
                Button {
                    Task { await report(status) }
                } label: {
                    Label(status.rawValue, systemImage: status.systemImage)
                        .foregroundStyle(status == .safe ? .green : .red)
                }
                .disabled(isWorking)
            }
        }
    }

    @ViewBuilder
    private var familyPingsSection: some View {
        Section("家人回報") {
            if sync.pings.isEmpty {
                Text("目前還沒有家人的回報").foregroundStyle(.secondary)
            } else {
                ForEach(sync.pings) { ping in
                    pingRow(ping)
                }
            }
        }
    }

    private func pingRow(_ ping: SafetyPing) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: ping.status.systemImage)
                    .foregroundStyle(ping.status == .safe ? .green : .red)
                Text(ping.senderName).font(.subheadline.bold())
                Spacer()
                Text(ping.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(ping.status.rawValue).font(.caption).foregroundStyle(.secondary)
            if !ping.note.isEmpty {
                Text(ping.note).font(.caption)
            }
            if !ping.readBy.isEmpty {
                Text("已讀：\(ping.readBy.joined(separator: "、"))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .task {
            // 顯示他人回報時，自動標記我已讀（已讀回條）
            if ping.senderName != myName && !ping.readBy.contains(myName) {
                await sync.markRead(pingID: ping.id, readerName: myName)
            }
        }
    }

    private func startShare() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let (share, container) = try await sync.makeShare()
            shareSheet = ShareBundle(share: share, container: container)
        } catch {
            AppLog.cloudError("建立分享失敗：\(error.localizedDescription)")
        }
    }

    private func report(_ status: SafetyStatus) async {
        isWorking = true
        defer { isWorking = false }
        await sync.postPing(senderName: myName, status: status, note: note)
        note = ""
    }
}
