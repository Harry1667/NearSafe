import SwiftUI
import SwiftData

/// 本人裝置的即時圈控制。分享必須在每位家人的手機上各自開啟，其他人不能代開。
struct LiveCircleSharingSection: View {
    @Environment(FamilySyncService.self) private var sync
    @Environment(TabRouter.self) private var router
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKeys.profileDisplayName) private var displayName = ""
    @AppStorage(SettingsKeys.liveLocationSharingEnabled) private var isSharing = false
    @AppStorage(SettingsKeys.liveCircleRadiusMeters) private var radiusMeters = 1_000
    @State private var isWorking = false

    private var iCloudUnavailable: Bool {
        sync.state == .noAccount
    }

    var body: some View {
        Section {
            Toggle("分享這支手機的位置", isOn: $isSharing)
                .disabled(isWorking || (!isSharing && iCloudUnavailable))
                .onChange(of: isSharing) { _, enabled in
                    Task { await updateSharing(enabled) }
                }

            if iCloudUnavailable {
                Label("請先登入 iCloud，才能與家庭成員分享即時位置", systemImage: "icloud.slash")
                    .font(.caption)
                    .foregroundStyle(HCColor.attention)
                // 與 InviteFamilySection 同一套引導：原地給入口，不把人丟到別處自己想辦法
                Button("查看 Apple 帳號狀態", systemImage: "gearshape") {
                    router.showSettings = true
                }
            }

            if isSharing {
                Stepper(
                    "警戒半徑：\(radiusMeters) 公尺",
                    value: $radiusMeters,
                    in: 300...3_000,
                    step: 100
                )
                .disabled(isWorking)

                HStack {
                    Label(
                        sync.ownLiveLocation?.freshnessText ?? "等待第一次位置更新",
                        systemImage: sync.ownLiveLocation?.isFresh == true
                            ? "location.fill"
                            : "clock.badge.exclamationmark"
                    )
                    .foregroundStyle(sync.ownLiveLocation?.isFresh == true ? HCColor.safe : HCColor.attention)
                    Spacer()
                    if isWorking { ProgressView() }
                }
                .font(.caption)
            } else {
                Label("即時位置分享已停止", systemImage: "location.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = sync.liveLocationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(HCColor.attention)
            }
        } header: {
            Text("我的即時圈")
        } footer: {
            Text("開啟後，這支手機會把位置與警戒半徑同步到家庭 iCloud。只有已加入家庭圈的人看得到；你可隨時停止。即時圈會顯示最後更新時間，超過 15 分鐘未更新就不參與警報判斷。")
        }
        .task(id: radiusMeters) {
            guard isSharing, !iCloudUnavailable else { return }
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                return
            }
            await publishCurrentLocation()
        }
    }

    private func updateSharing(_ enabled: Bool) async {
        guard !enabled || !iCloudUnavailable else {
            isSharing = false
            return
        }
        isWorking = true
        defer { isWorking = false }
        if enabled {
            LocationService.shared.requestAlwaysPermission()
            LocationService.shared.syncLiveLocationSharing(isEnabled: true)
            await publishCurrentLocation()
        } else {
            LocationService.shared.syncLiveLocationSharing(isEnabled: false)
            await sync.stopLiveLocationSharing(context: context)
        }
    }

    private func publishCurrentLocation() async {
        guard let location = await LocationService.shared.currentLocation() else { return }
        await sync.publishLiveLocation(
            location,
            displayName: displayName,
            radiusMeters: radiusMeters,
            context: context
        )
    }
}
