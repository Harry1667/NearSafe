import SwiftUI
import SwiftData

/// 本人裝置的即時圈控制。分享必須在每位家人的手機上各自開啟，其他人不能代開。
struct LiveCircleSharingSection: View {
    @Environment(FamilySyncService.self) private var sync
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
                Label(
                    iCloudUnavailable ? "尚未登入 Apple 帳號，分享功能目前不可用" : "即時位置分享已停止",
                    systemImage: iCloudUnavailable ? "person.crop.circle.badge.exclamationmark" : "location.slash"
                )
                    .font(.caption)
                    .foregroundStyle(iCloudUnavailable ? HCColor.attention : Color.secondary)
            }

            if let error = sync.liveLocationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(HCColor.attention)
            }
        } header: {
            Text("我的即時圈")
        } footer: {
            Text("位置只同步給家庭圈成員（以 Apple 帳號登入辨識），並可隨時停止。畫面會顯示最後更新時間；超過 15 分鐘即視為過期，不參與提醒判斷。")
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
            // 開啟邏輯抽到 FamilySyncService（B3-2 與入圈後激活頁 PostJoinActivationView 共用一份）
            await sync.enableLiveLocationSharing(radiusMeters: radiusMeters, context: context)
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
