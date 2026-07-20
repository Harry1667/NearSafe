import SwiftUI
import CoreLocation

/// 安否回報中心：雙向閉環的回報端。
/// - 上半：我一鍵回報「我平安 / 需要協助」
/// - 下半：家人的回報清單與已讀回條
/// - 工具列：邀請家人加入家庭圈（CKShare）
struct SafetyCheckInView: View {
    @Environment(FamilySyncService.self) private var sync
    @Environment(TabRouter.self) private var router
    let myName: String

    @State private var showInviteOptions = false
    @State private var note = ""
    @State private var isWorking = false
    /// 回報時附上目前位置（自願、一次性）。用 AppStorage 記住偏好，預設關（隱私優先）
    @AppStorage("checkInAttachLocation") private var attachLocation = false
    /// 邀請失敗時的可見錯誤——只寫 log 的話，使用者看到的是「按了沒反應＝App 壞了」
    @State private var shareError: String?

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
            if isWorking {
                ProgressView()
            } else {
                Button("邀請家人", systemImage: "person.badge.plus") {
                    Task { await startShare() }
                }
                .disabled(sync.state == .noAccount)
            }
        }
        .alert("邀請家人失敗", isPresented: .init(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
        .sheet(isPresented: $showInviteOptions) {
            InviteOptionsView()
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
                    .foregroundStyle(HCColor.attention)
                Text("安否回報需要 iCloud 才能在家人之間同步。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("前往設定查看 Apple 帳號", systemImage: "gearshape") {
                    router.showSettings = true
                }
            }
        case .error(let message):
            Section {
                Label("同步發生問題", systemImage: "exclamationmark.icloud")
                    .foregroundStyle(HCColor.danger)
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
        Section {
            TextField("補充說明（選填）", text: $note)
            Toggle(isOn: $attachLocation) {
                Label("附上我的目前位置", systemImage: "location")
            }
            .onChange(of: attachLocation) { _, isOn in
                // 開啟當下就要權限，別等到按回報才跳系統框打斷流程
                if isOn { LocationService.shared.requestPermissionIfNeeded() }
            }
            ForEach(SafetyStatus.selfReportable, id: \.self) { status in
                Button {
                    Task { await report(status) }
                } label: {
                    Label(status.rawValue, systemImage: status.systemImage)
                        .foregroundStyle(status == .safe ? HCColor.safe : HCColor.danger)
                }
                .disabled(isWorking)
            }
        } header: {
            Text("回報我的狀態")
        } footer: {
            Text("位置只在你按下回報的那一刻取得並分享一次，安心圈不會持續追蹤任何人的位置。")
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
                    .foregroundStyle(ping.status == .safe ? HCColor.safe : HCColor.danger)
                Text(ping.senderName).font(.subheadline.bold())
                Spacer()
                Text(ping.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(ping.status.rawValue).font(.caption).foregroundStyle(.secondary)
            if !ping.note.isEmpty {
                Text(ping.note).font(.caption)
            }
            if ping.hasLocation {
                Label(ping.placeName ?? "已附上位置", systemImage: "mappin.and.ellipse")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
            // 已在家庭圈就沿用現有邀請碼；還沒有就建立一個新家庭圈
            if sync.currentInviteCode == nil {
                _ = try await sync.createFamily()
            }
            showInviteOptions = true
        } catch {
            AppLog.cloudError("建立家庭圈失敗：\(error.localizedDescription)")
            shareError = "無法建立家庭圈邀請：\(error.localizedDescription)\n請確認已登入且網路正常後再試一次。"
        }
    }

    private func report(_ status: SafetyStatus) async {
        isWorking = true
        defer { isWorking = false }
        // 自願附位置：取不到（未授權/逾時）就照常回報，定位失敗不能擋「我平安」
        var latitude: Double?
        var longitude: Double?
        var placeName: String?
        if attachLocation, let location = await LocationService.shared.currentLocation() {
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude
            placeName = await Self.reverseGeocode(location)
        }
        await sync.postPing(
            senderName: myName, status: status, note: note,
            latitude: latitude, longitude: longitude, placeName: placeName
        )
        note = ""
    }

    /// 回報端做一次反向地理編碼，家人看到的是「台北市信義區」而不是座標。
    /// 失敗回 nil（回報列會退回顯示「已附上位置」），不重試不阻塞。
    private static func reverseGeocode(_ location: CLLocation) async -> String? {
        guard let place = await MapReverseGeocoder.lookup(location) else { return nil }
        let district = OnboardingView.guessDistrict(from: place.searchableText)
        return place.approximateLabel(district: district)
    }
}
