import SwiftUI
import SwiftData

/// 安心頁——App 的第一畫面。
/// 90% 的開啟只為確認一件事：「家人都平安嗎」。這頁把答案做成 3 秒可讀完的三段式：
/// 大字狀態語句 → 家人列 → 背景看守摘要，底部一顆「回報我平安」。
/// 想深究的人再進地圖或事件列表——狀態優先、細節下鑽。
struct HomeStatusView: View {
    let myName: String
    @Environment(FamilySyncService.self) private var sync
    @Environment(TabRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var members: [LocalFamilyMember]
    @Query private var events: [LocalSafetyEvent]
    @Query private var regionAlerts: [RegionAlert]
    @State private var showCheckIn = false
    @State private var selectedEvent: LocalSafetyEvent?
    @State private var breathing = false

    /// 與地圖頁共用同一個聚合（SafetyStatus）：兩頁對「平安與否」的說法永遠一致，
    /// 且一律以未過濾事件計算——假性安心是這頁最不可犯的錯
    private var status: SafetyOverview {
        SafetyOverview.compute(events: events, regionAlerts: regionAlerts, members: members)
    }

    private var staleLiveCircleCount: Int {
        members.flatMap(\.lifeCircles).filter {
            $0.kind == .live && !$0.isActiveForAlerts
        }.count
    }

    private var pageStatusColor: Color {
        if !status.isAllClear { return HCColor.danger }
        return staleLiveCircleCount > 0 ? HCColor.attention : HCColor.safe
    }

    var body: some View {
        // 導航堆疊綁在 router 上：deep link（widget/通知的 alerts）能直接推入提醒中心
        NavigationStack(path: Bindable(router).homePath) {
            ScrollView {
                VStack(spacing: HCSpacing.x6) {
                    statusHero
                        .tourAnchor(.statusHero)
                    if !members.isEmpty {
                        familySection
                            .tourAnchor(.familyList)
                    }
                    watchSummaryRow
                        .tourAnchor(.watchRow)
                    historyRow
                        .tourAnchor(.historyRow)
                }
                .padding(.horizontal, HCSpacing.x4)
                .padding(.top, HCSpacing.x4)
            }
            .navigationTitle("安心圈")
            // 情緒底色：狀態色從頁面頂部滲下來的極淡漸層——平安是守護綠、
            // 有事件變警示紅，「變臉」從盾牌擴散到整頁氛圍，但淡到不搶警示色的戲
            .background(alignment: .top) {
                LinearGradient(
                    colors: [
                        pageStatusColor.opacity(0.12),
                        .clear,
                    ],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.6)
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: status.isAllClear)
            }
            .toolbar {
                Button("設定", systemImage: "gearshape") { router.showSettings = true }
            }
            .navigationDestination(for: TabRouter.HomeDestination.self) { destination in
                switch destination {
                case .events: EventListView()
                case .history: HistoryView()
                }
            }
            .safeAreaInset(edge: .bottom) { checkInButton }
            .sheet(isPresented: $showCheckIn) {
                NavigationStack { SafetyCheckInView(myName: myName) }
            }
            .sheet(item: $selectedEvent) {
                EventDetailView(event: $0, members: members)
            }
        }
    }

    // MARK: - 大字狀態

    @ViewBuilder
    private var statusHero: some View {
        if status.isAllClear {
            let needsLocationUpdate = staleLiveCircleCount > 0
            let clearColor = needsLocationUpdate ? HCColor.attention : HCColor.safe
            VStack(spacing: HCSpacing.x4) {
                ZStack {
                    // 守護圈環：同心圓 motif（與地圖盾牌、Onboarding 同一簽名語言）
                    Circle().stroke(clearColor.opacity(0.10), lineWidth: 2).frame(width: 168, height: 168)
                    Circle().stroke(clearColor.opacity(0.22), lineWidth: 2).frame(width: 132, height: 132)
                    Circle()
                        .fill(clearColor.gradient)
                        .frame(width: 96, height: 96)
                        .shadow(color: clearColor.opacity(0.35), radius: 18, y: 6)
                    Image(systemName: needsLocationUpdate ? "location.slash.fill" : "checkmark.shield.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                }
                // 呼吸動效：緩慢、低幅度——安心不是興奮；reduceMotion 時靜止
                .scaleEffect(breathing ? 1.03 : 1.0)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
                    value: breathing
                )
                .onAppear { breathing = true }
                .accessibilityHidden(true)

                Text(needsLocationUpdate ? "部分即時圈待更新" : "警戒圈一切平安")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text(needsLocationUpdate
                     ? "\(staleLiveCircleCount) 個即時圈超過 15 分鐘未更新，舊位置不會用來判斷警報。"
                     : "目前沒有需要注意的事件，安心圈持續看守中。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, HCSpacing.x6)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        } else {
            // 有事件靠近生活圈：全 App 唯一「變臉」的時刻
            VStack(spacing: HCSpacing.x4) {
                ZStack {
                    Circle()
                        .fill(HCColor.danger.gradient)
                        .frame(width: 96, height: 96)
                        .shadow(color: HCColor.danger.opacity(0.35), radius: 18, y: 6)
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                Text("\(status.attentionCount) 件事件靠近警戒圈")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(HCColor.danger)
                    .multilineTextAlignment(.center)
                Text("官方已確認的事件落在提醒範圍內，點開地圖確認位置與建議。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    router.selection = TabRouter.mapTab
                } label: {
                    Label("查看地圖", systemImage: "map.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(HCColor.danger)
            }
            .padding(.vertical, HCSpacing.x4)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 家人列

    private var familySection: some View {
        VStack(alignment: .leading, spacing: HCSpacing.x2) {
            ForEach(members) { member in
                memberRow(member)
            }
            Divider()
            Text("未收到安否回報不代表發生危險；請一併查看最後回報與即時位置更新時間。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .hcCard()
    }

    private func memberRow(_ member: LocalFamilyMember) -> some View {
        let nearbyEvent = nearestNearbyEvent(for: member)
        let hasNearbyEvent = nearbyEvent != nil
        let hasStaleLiveCircle = member.lifeCircles.contains {
            $0.kind == .live && !$0.isActiveForAlerts
        }
        let ping = latestPing(for: member)
        let rowColor = hasNearbyEvent
            ? HCColor.danger
            : (hasStaleLiveCircle ? HCColor.attention : HCColor.safe)
        return Button {
            selectedEvent = nearbyEvent
        } label: {
            HStack(spacing: HCSpacing.x3) {
                Image(systemName: member.isPlace ? "mappin.circle.fill" : "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(member.isPlace ? HCColor.medical : HCColor.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name).font(.body.weight(.medium))
                    Text(memberStatusText(member, nearbyEvent: nearbyEvent, ping: ping))
                        .font(.caption)
                        .foregroundStyle(hasNearbyEvent || hasStaleLiveCircle ? rowColor : .secondary)
                }
                Spacer()
                // 狀態點：文字＋顏色雙通道（色弱可辨靠文字，不只靠這顆點）
                Circle()
                    .fill(rowColor)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                if hasNearbyEvent {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HCColor.danger)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasNearbyEvent)
        .padding(.vertical, HCSpacing.x1)
        .frame(minHeight: 44) // 觸控與可讀性下限
        .accessibilityElement(children: .combine)
        .accessibilityHint(hasNearbyEvent ? "點兩下查看圈內最近的事件詳情" : "")
    }

    /// 同一個圈內可能同時有多件事件；首頁先打開離該成員警戒圈最近的一件，
    /// 完整清單仍可從「背景看守」或地圖查看。
    private func nearestNearbyEvent(for member: LocalFamilyMember) -> LocalSafetyEvent? {
        SafetyOverview.activeEvents(events)
            .filter { event in
                event.isOfficiallyConfirmed
                    && !AlertPolicy.evaluate(event: event, members: [member]).matches.isEmpty
            }
            .min {
                nearestCircleDistance($0, [member]) < nearestCircleDistance($1, [member])
            }
    }

    /// 這位家人最新的安否回報（比對署名；地點類成員不會有回報）
    private func latestPing(for member: LocalFamilyMember) -> SafetyPing? {
        sync.pings
            .filter { $0.senderName == member.name }
            .max(by: { $0.createdAt < $1.createdAt })
    }

    private func memberStatusText(_ member: LocalFamilyMember, nearbyEvent: LocalSafetyEvent?, ping: SafetyPing?) -> String {
        var parts: [String] = []
        if let event = nearbyEvent {
            // 寫清楚是哪個圈、多遠、什麼事件——只寫「圈內有事件」不足以判斷要不要行動
            if let match = AlertPolicy.evaluate(event: event, members: [member])
                .matches.min(by: { $0.distanceMeters < $1.distanceMeters }) {
                let distanceText = match.distanceMeters >= 1_000
                    ? String(format: "約 %.1f 公里", Double(match.distanceMeters) / 1_000)
                    : "約 \(match.distanceMeters) 公尺"
                parts.append("「\(match.circleName)」\(distanceText)處：\(event.title)")
            } else {
                parts.append("圈內事件：\(event.title)")
            }
        } else {
            parts.append(member.isPlace ? "範圍內無事件" : "圈內無事件")
        }
        if let liveCircle = member.lifeCircles.first(where: { $0.kind == .live }) {
            parts.append(liveCircle.locationFreshnessText)
        }
        if !member.isPlace, let ping {
            let ago = ping.createdAt.formatted(.relative(presentation: .named))
            parts.append("\(ago)回報平安")
        }
        return parts.joined(separator: "・")
    }

    // MARK: - 背景看守摘要

    private var watchSummaryRow: some View {
        Button {
            router.openHome(.events)
        } label: {
            HStack {
                Image(systemName: "eye.fill")
                    .foregroundStyle(HCColor.brand)
                Text("背景看守中：未驗證線索 \(status.confirmingCount)・其他區域 \(status.elsewhereCount)・區域警報 \(status.regionAlertCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .hcCard()
        }
        .buttonStyle(.plain)
    }

    /// 回顧入口：低頻查閱不配一級分頁，降為安心頁的一列
    private var historyRow: some View {
        Button {
            router.openHome(.history)
        } label: {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(HCColor.brand)
                Text("回顧過去 30 天")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .hcCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - 回報平安

    private var checkInButton: some View {
        Button {
            showCheckIn = true
        } label: {
            Label("回報我平安", systemImage: "checkmark.shield.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(HCColor.brand)
        .tourAnchor(.checkInButton)
        .padding(.horizontal, HCSpacing.x4)
        .padding(.bottom, HCSpacing.x2)
        .background(.bar)
    }
}

#if DEBUG
#Preview {
    HomeStatusView(myName: "測試者")
        .modelContainer(PreviewSupport.container())
        .environment(FamilySyncService())
        .environment(TabRouter())
}
#endif
