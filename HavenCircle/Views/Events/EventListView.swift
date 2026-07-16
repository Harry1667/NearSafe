import SwiftUI
import SwiftData

/// 提醒中心：按「需要注意 / 持續確認中 / 已結束」分類（對應產品規格的通知頁分類）
struct EventListView: View {
    @Environment(\.modelContext) private var context
    @Environment(TabRouter.self) private var router
    @Query(sort: \LocalSafetyEvent.occurredAt, order: .reverse) private var events: [LocalSafetyEvent]
    @Query private var members: [LocalFamilyMember]
    @Query private var regionAlerts: [RegionAlert]
    @State private var showDrill = false
    @State private var selected: LocalSafetyEvent?
    @State private var selectedAlert: RegionAlert?

    private var visibleEvents: [LocalSafetyEvent] {
        events.filter { !$0.isArchived && !EventVisibility.isSuppressed($0) }
    }
    /// 需要注意＝官方確認「且真的落在某個生活圈的提醒範圍」（分類標籤與邏輯必須一致）
    private var attention: [LocalSafetyEvent] {
        visibleEvents
            .filter { !$0.isEnded && $0.isOfficiallyConfirmed && isInAnyCircle($0) }
            .sorted { nearestCircleDistance($0, members) < nearestCircleDistance($1, members) }
    }
    /// 官方確認、但離所有生活圈較遠的事件另立分類，不冒充「需要注意」。
    /// 加距離上限：超過 NearbyScope 的全國事件再拆到「全台其他」摺疊清單，避免灌成雜訊。
    private var elsewhere: [LocalSafetyEvent] {
        visibleEvents
            .filter {
                !$0.isEnded && $0.isOfficiallyConfirmed && !isInAnyCircle($0)
                    && nearestCircleDistance($0, members) <= NearbyScope.maxMeters
            }
            .sorted { nearestCircleDistance($0, members) < nearestCircleDistance($1, members) }
    }

    /// 離所有生活圈超過上限的全國官方事件（預設摺疊）
    private var nationwide: [LocalSafetyEvent] {
        visibleEvents
            .filter {
                !$0.isEnded && $0.isOfficiallyConfirmed && !isInAnyCircle($0)
                    && nearestCircleDistance($0, members) > NearbyScope.maxMeters
            }
            .sorted { $0.occurredAt > $1.occurredAt }
    }
    private var confirming: [LocalSafetyEvent] {
        visibleEvents.filter { !$0.isEnded && !$0.isOfficiallyConfirmed }
    }
    private var ended: [LocalSafetyEvent] {
        Array(visibleEvents.filter(\.isEnded).prefix(20))
    }

    private func isInAnyCircle(_ event: LocalSafetyEvent) -> Bool {
        !AlertPolicy.evaluate(event: event, members: members).matches.isEmpty
    }

    /// 進行中的區域警報，依 kind＋title 去重取最新——NCDR 同一場警報常拆成多筆
    /// （鄉鎮清單不同、標題相同），全部列出會讓提醒中心看起來像同一則洗版
    private var activeRegionAlerts: [RegionAlert] {
        var newest: [String: RegionAlert] = [:]
        for alert in regionAlerts where !alert.isEnded {
            let key = "\(alert.kind)|\(alert.title)"
            if let kept = newest[key], kept.updatedAt >= alert.updatedAt { continue }
            newest[key] = alert
        }
        return newest.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    // 分頁減編（合成案 C2）後本頁由安心頁 push，導航堆疊由上層提供，
    // 自己不再包 NavigationStack（巢狀堆疊會讓 push/pop 行為錯亂）
    var body: some View {
        List {
            miniMapSection
            if visibleEvents.isEmpty && activeRegionAlerts.isEmpty {
                Section {
                    safeStateHero
                        .listRowBackground(Color.clear)
                }
            }
            regionAlertSection
            section(title: "需要注意", subtitle: "官方確認且位於生活圈提醒範圍內", items: attention)
            section(title: "持續確認中", subtitle: "資料尚未充分驗證，不會推播", items: confirming)
            section(title: "附近動態", subtitle: "官方事件，離生活圈 30 公里內", items: elsewhere)
            nationwideSection
            section(title: "已結束", subtitle: "已解除或已過期的事件", items: ended)
        }
        .navigationTitle("提醒中心")
        .toolbar {
            Button("演練", systemImage: "bell.and.waves.left.and.right") { showDrill = true }
        }
        // 手動下拉刷新：重跑一次資料管線
        .refreshable { await EventPipeline.refresh(context: context) }
        .sheet(isPresented: $showDrill) { DrillView() }
        .sheet(item: $selected) { EventDetailView(event: $0, members: members) }
        .sheet(item: $selectedAlert) { RegionAlertDetailView(alert: $0, members: members) }
    }

    /// 品牌簽名：平安不是「沒有內容」，是產品最想傳達的一刻——同心圓環＝守護圈完好。
    /// 圓環 motif 與 Onboarding hero、地圖盾牌 chip 呼應，構成貫穿全 App 的視覺識別
    private var safeStateHero: some View {
        VStack(spacing: HCSpacing.x3) {
            ZStack {
                Circle()
                    .stroke(HCColor.safe.opacity(0.18), lineWidth: 2)
                    .frame(width: 96, height: 96)
                Circle()
                    .stroke(HCColor.safe.opacity(0.4), lineWidth: 2)
                    .frame(width: 74, height: 74)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(HCColor.safe.gradient, in: Circle())
            }
            .accessibilityHidden(true)
            Text("生活圈一切平安")
                .font(.system(.headline, design: .rounded))
            Text("目前沒有需要注意的事件，守護持續進行中。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HCSpacing.x6)
    }

    /// 頂部精簡地圖：只放進行中的事件，點標記開詳情
    @ViewBuilder
    private var miniMapSection: some View {
        let active = visibleEvents.filter { !$0.isEnded }
        if !active.isEmpty {
            Section {
                EventsMiniMap(
                    events: active,
                    members: members,
                    onSelect: { selected = $0 },
                    onExpand: { router.selection = TabRouter.mapTab }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    /// 區域警報依分組分區顯示（天災→公共安全→民生→交通，安全相關優先排前）。
    /// 每組最多直接顯示 3 則，其餘收進摺疊清單——警報是背景資訊，不該淹沒事件列表
    @ViewBuilder
    private var regionAlertSection: some View {
        let grouped = Dictionary(grouping: activeRegionAlerts, by: \.group)
        ForEach(["天災", "公共安全", "民生", "交通"], id: \.self) { group in
            if let alerts = grouped[group], !alerts.isEmpty {
                Section("區域警報・\(group)（\(alerts.count)）") {
                    ForEach(alerts.prefix(3)) { alert in
                        regionAlertRow(alert)
                    }
                    if alerts.count > 3 {
                        DisclosureGroup("其餘 \(alerts.count - 3) 則") {
                            ForEach(alerts.dropFirst(3)) { alert in
                                regionAlertRow(alert)
                            }
                        }
                    }
                }
            }
        }
    }

    /// 警報卡自帶底色與圓角，列背景改透明避免「卡中卡」的雙層框
    private func regionAlertRow(_ alert: RegionAlert) -> some View {
        Button {
            selectedAlert = alert
        } label: {
            RegionAlertBanner(alert: alert, members: members)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: HCSpacing.x1, leading: HCSpacing.x4, bottom: HCSpacing.x1, trailing: HCSpacing.x4))
    }

    /// 全台其他官方示警：預設摺疊——它們是真資料，但不該與「附近」搶注意力
    @ViewBuilder
    private var nationwideSection: some View {
        if !nationwide.isEmpty {
            Section {
                DisclosureGroup("全台其他官方示警（\(nationwide.count)）") {
                    ForEach(Array(nationwide.prefix(15))) { event in
                        Button {
                            selected = event
                        } label: {
                            EventRow(event: event, members: members)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } footer: {
                Text("離所有生活圈超過 30 公里的官方事件收在這裡，避免稀釋與你相關的訊號。")
            }
        }
    }

    @ViewBuilder
    private func section(title: String, subtitle: String, items: [LocalSafetyEvent]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { event in
                    Button {
                        selected = event
                    } label: {
                        EventRow(event: event, members: members)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { delete(at: $0, in: items) }
            } header: {
                VStack(alignment: .leading) {
                    Text("\(title)（\(items.count)）")
                    Text(subtitle).font(.caption2).textCase(nil)
                }
            }
        }
    }

    /// 刪除索引對「該分類的清單」取，不能用完整 events 陣列
    private func delete(at offsets: IndexSet, in items: [LocalSafetyEvent]) {
        for index in offsets {
            context.delete(items[index])
        }
        context.saveReporting()
    }
}

#Preview {
    EventListView()
        .modelContainer(PreviewSupport.container())
        .environment(TabRouter())
}
