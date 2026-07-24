import SwiftUI
import SwiftData

/// 家人清單：以「人」為中心呈現——災害時真正要看的是「誰在哪、平不平安」，
/// 不是一排參數設定。版面仿 Apple 家庭共享：頂部固定「我的帳號」卡，
/// 下方才是家庭圈內容，依「是否已加入家庭圈」分三種狀態：
/// - 未加入任何家庭圈：情境卡直球講「為什麼需要」＋邀請大按鈕
///   （2026-07 實測回饋：「想要自己的位置也需要登入，第三頁是做壞的」正是這個畫面）。
/// - 已加入但只有自己一人：「等待家人加入」卡（邀請碼＋再次分享），不重複顯示邀請大按鈕。
/// - 已加入且有其他成員：家庭圈 header（名稱＋人數）＋本人卡＋每位家人一張卡＋重要地點另起小節。
///
/// 分支判斷一律看 [FamilySyncService.isInFamilyCircle] / [FamilySyncService.isSolo]（雲端真相），
/// 不看本機 LocalFamilyMember 筆數——本機清單是投影，剛加入時會落後於雲端，
/// 用本機筆數判斷會出現「明明已加入卻還看到邀請空狀態」的錯覺（2026-07-24 實測撞到的 bug）。
struct FamilyListView: View {
    @Environment(\.modelContext) private var context
    @Environment(FamilySyncService.self) private var sync
    @Environment(TabRouter.self) private var router
    @Environment(EntitlementStore.self) private var entitlementStore
    @Query private var members: [LocalFamilyMember]
    @AppStorage(SettingsKeys.profileDisplayName) private var displayName = ""
    @AppStorage(SettingsKeys.appleAccountEmail) private var appleAccountEmail = ""

    @State private var adding = false
    @State private var addingPlace = false
    /// 成員／地點額度閘門觸發時開這個付費頁（見 [gateAddFamilyMember] / [gateAddPlace]）
    @State private var showPaywall = false
    /// 剛儲存的家人/地點：編輯器收合後接著替它開固定圈編輯器（兩段式流程合併成一段）
    @State private var newMemberForCircle: LocalFamilyMember?

    // 邀請流程（空狀態的主 CTA）
    @State private var signInGate = SignInGate()
    @State private var showInviteOptions = false
    @State private var showJoinByCode = false
    @State private var showRoleSelect = false
    @State private var isInviting = false
    @State private var inviteError: String?
    /// B2：deep link（QR／havencircle://join）帶進來的邀請碼，交給 JoinByCodeView 預填並自動查詢
    @State private var prefilledJoinCode: String?

    // 退出／解散家庭圈
    @State private var showLeaveConfirm = false
    @State private var isLeavingFamily = false
    @State private var leaveError: String?

    /// D1：是否已加入或建立家庭圈——優先於本機成員數的分支依據
    private var isInFamilyCircle: Bool { sync.isInFamilyCircle }
    /// D1：已在家庭圈內是否只有自己一人（雲端 memberUids 為準）
    private var isCircleSolo: Bool { sync.isSolo(localMembers: members) }
    /// D2：是否已用 Apple 帳號登入（沿用 LiveCircleSharingSection 同款判法）
    private var isSignedIn: Bool { sync.state != .noAccount }

    private var me: LocalFamilyMember? { members.first(where: \.isCurrentUser) }
    private var familyMembers: [LocalFamilyMember] {
        members.filter { !$0.isPlace && !$0.isCurrentUser }
    }
    private var places: [LocalFamilyMember] {
        members.filter(\.isPlace)
    }
    private var myDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "我" : trimmed
    }
    private var familyCircleDisplayName: String {
        let name = sync.familyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "我的家庭圈" : name
    }

    var body: some View {
        List {
            myAccountSection
            if !isInFamilyCircle {
                emptyStateSection
                // 單人也能用：這正是使用者要的「我的即時圈」——純本地，不用登入
                FollowCircleToggleSection()
                addPlaceCard
                placesSection
            } else if isCircleSolo {
                waitingForFamilyCard
                FollowCircleToggleSection(disambiguateFromSharing: true)
                LiveCircleSharingSection()
                addPlaceCard
                placesSection
                leaveFamilySection
            } else {
                familyCircleHeaderSection
                familyMembersSection
                FollowCircleToggleSection(disambiguateFromSharing: true)
                LiveCircleSharingSection()
                placesSection
                InviteFamilySection()
                leaveFamilySection
            }
        }
        .toolbar {
            Menu {
                Button("新增家人", systemImage: "person.badge.plus") { gateAddFamilyMember() }
                Button("新增重要地點", systemImage: "mappin.and.ellipse") { gateAddPlace() }
            } label: {
                Label("新增", systemImage: "plus")
                    .fontWeight(.medium)
            }
        }
        .signInPreflight(signInGate)
        .sheet(isPresented: $adding) { MemberEditorView(onSaved: scheduleCircleEditor) }
        .sheet(isPresented: $addingPlace) {
            // 名字用點擊選擇取代打字（少一步輸入畫面）；選定後直接建立地點成員，
            // 沿用既有的兩段式時序接固定圈編輯器
            PlaceSelectView { name, _ in
                addingPlace = false
                createPlace(name: name)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                // iPad 會忽略隱含尺寸而放大成整頁 sheet，這裡收斂成 form 尺寸
                .presentationSizing(.form)
        }
        .sheet(item: $newMemberForCircle) { member in
            CircleEditorView(member: member)
        }
        .sheet(isPresented: $showInviteOptions) {
            InviteOptionsView()
                // iPad 會忽略隱含尺寸而放大成整頁 sheet，這裡收斂成 form 尺寸
                .presentationSizing(.form)
        }
        .sheet(isPresented: $showJoinByCode, onDismiss: { prefilledJoinCode = nil }) {
            JoinByCodeView(prefilledCode: prefilledJoinCode)
                .presentationSizing(.form)
        }
        .fullScreenCover(isPresented: $showRoleSelect) {
            RoleSelectView(
                onSelect: { role in
                    applyRole(role)
                    showRoleSelect = false
                    showInviteOptions = true
                },
                onSkip: {
                    showRoleSelect = false
                    showInviteOptions = true
                }
            )
        }
        .task {
            await sync.refreshAccountStatus()
            await sync.refreshFamilyMembers(context: context)
        }
        .refreshable {
            await sync.refreshAccountStatus()
            await sync.refreshFamilyMembers(context: context)
        }
        // B2：deep link 帶碼進來（QR 掃描／havencircle://join）——切到本頁後這裡接手，
        // 未登入先走登入預告卡，登入完成才開加入流程；消耗式旗標，用過就清空避免重觸發。
        .task(id: router.pendingJoinCode) {
            guard let code = router.pendingJoinCode else { return }
            router.pendingJoinCode = nil
            signInGate.perform {
                prefilledJoinCode = code
                showJoinByCode = true
            }
        }
        .confirmationDialog(leaveDialogTitle, isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button(isCircleSolo && sync.isFamilyOwner ? "解散家庭圈" : "退出家庭圈", role: .destructive) {
                Task { await performLeaveFamily() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(leaveDialogMessage)
        }
        // iPad：整份清單限寬置中，避免按鈕與列卡撐滿 13 吋全寬（iPhone 上無感）；
        // 外圍再鋪同款群組底色，否則 List 底色只到 600pt，左右會露出不同色階的接縫
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - D2：我的帳號卡（固定頂部，未入圈／已入圈都顯示）

    private var myAccountSection: some View {
        Section {
            HStack(spacing: HCSpacing.x3) {
                Text(roleEmoji(for: myDisplayName))
                    .font(.system(size: 30))
                    .frame(width: 48, height: 48)
                    .background(.secondary.opacity(0.08), in: Circle())
                VStack(alignment: .leading, spacing: HCSpacing.x1) {
                    Text(myDisplayName).font(.body.weight(.semibold))
                    Text(accountSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !isSignedIn {
                    Button("登入") {
                        signInGate.isPresentingPreflight = true
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .hcCard()
        } header: {
            Text("我的帳號")
        }
        .listRowInsets(
            EdgeInsets(
                top: HCSpacing.x1,
                leading: HCSpacing.x4,
                bottom: HCSpacing.x1,
                trailing: HCSpacing.x4
            )
        )
        .listRowBackground(Color.clear)
    }

    private var accountSubtitle: String {
        guard isSignedIn else { return "尚未登入" }
        return appleAccountEmail.isEmpty ? "已使用 Apple 帳號登入" : appleAccountEmail
    }

    // MARK: - 空狀態（還沒加入任何家庭圈）

    /// 情境卡置頂：直球講「為什麼需要」，不是功能清單——這正是使用者罵「沒有引導」的畫面，
    /// 不能再放一排並列 Section 讓人自己猜入口在哪。
    private var emptyStateSection: some View {
        Section {
            VStack(spacing: HCSpacing.x4) {
                ZStack {
                    Circle()
                        .fill(HCColor.brand.opacity(0.10))
                        .frame(width: 72, height: 72)
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(HCColor.brand)
                }
                Text("災害來的時候，一個人知道不夠。")
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Button {
                    signInGate.perform { await startInviteFlow() }
                } label: {
                    Label("邀請家人", systemImage: "person.crop.circle.badge.plus")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isInviting)
                if isInviting {
                    ProgressView()
                }
                if let inviteError {
                    Text(inviteError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("我收到了邀請碼") {
                    signInGate.perform {
                        prefilledJoinCode = nil
                        showJoinByCode = true
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, HCSpacing.x2)
            .hcCard()
        }
        .listRowInsets(
            EdgeInsets(
                top: HCSpacing.x1,
                leading: HCSpacing.x4,
                bottom: HCSpacing.x1,
                trailing: HCSpacing.x4
            )
        )
        .listRowBackground(Color.clear)
    }

    /// 次要卡：一個人也能守護「不是自己」的地方（爸媽家、公司）。
    private var addPlaceCard: some View {
        Section {
            Button {
                gateAddPlace()
            } label: {
                HStack(spacing: HCSpacing.x3) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .background(.secondary.opacity(0.08), in: Circle())
                    VStack(alignment: .leading, spacing: HCSpacing.x1) {
                        Text("新增重要地點").font(.body.weight(.medium))
                        Text("爸媽家、公司，都能設警戒圈")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .hcCard()
            }
            .buttonStyle(.plain)
        }
        .listRowInsets(
            EdgeInsets(
                top: HCSpacing.x1,
                leading: HCSpacing.x4,
                bottom: HCSpacing.x1,
                trailing: HCSpacing.x4
            )
        )
        .listRowBackground(Color.clear)
    }

    /// 建立家庭圈（若尚未建立）並開啟邀請碼畫面。首次建立家庭圈成功後先接身分選擇（C3），
    /// 選完／略過再開邀請碼畫面。
    private func startInviteFlow() async {
        isInviting = true
        inviteError = nil
        defer { isInviting = false }
        do {
            // 建/沿用家庭圈的決策抽到 FamilySyncService.ensureInviteReady（C1 情境卡共用同一份）
            let isFirstFamily = try await sync.ensureInviteReady(context: context)
            if isFirstFamily {
                showRoleSelect = true
            } else {
                showInviteOptions = true
            }
        } catch {
            inviteError = "建立家庭圈失敗：\(error.localizedDescription)"
            AppLog.cloudError("建立家庭圈失敗：\(error.localizedDescription)")
        }
    }

    private func applyRole(_ role: FamilyRole) {
        displayName = role.label
        if let me {
            me.name = role.label
            context.saveReporting()
        }
        Analytics.track("role_selected")
    }

    // MARK: - C4：等待家人加入（已入圈但只有自己一人）

    private var waitingForFamilyCard: some View {
        Section {
            VStack(spacing: HCSpacing.x4) {
                ZStack {
                    Circle()
                        .fill(HCColor.brand.opacity(0.10))
                        .frame(width: 72, height: 72)
                    Image(systemName: "hourglass")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(HCColor.brand)
                }
                Text("等待家人加入")
                    .font(.title3.weight(.bold))
                if let code = sync.currentInviteCode {
                    Text(code)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .tracking(HCSpacing.x1)
                        .padding(.horizontal, HCSpacing.x4)
                        .padding(.vertical, HCSpacing.x2)
                        .background(
                            .primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: HCRadius.control, style: .continuous)
                        )
                }
                Text("把邀請碼給家人，或讓他們掃你畫面上的 QR code 就能加入。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    showInviteOptions = true
                } label: {
                    Label("再次分享", systemImage: "square.and.arrow.up")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, HCSpacing.x2)
            .hcCard()
        }
        .listRowInsets(
            EdgeInsets(
                top: HCSpacing.x1,
                leading: HCSpacing.x4,
                bottom: HCSpacing.x1,
                trailing: HCSpacing.x4
            )
        )
        .listRowBackground(Color.clear)
    }

    // MARK: - A4：家庭圈 header（已入圈且多人）

    private var familyCircleHeaderSection: some View {
        Section {
            HStack(spacing: HCSpacing.x3) {
                Image(systemName: "house.fill")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(HCColor.brand)
                VStack(alignment: .leading, spacing: HCSpacing.x1) {
                    Text(familyCircleDisplayName)
                        .font(.title3.weight(.bold))
                    Text("\(max(sync.memberUids.count, 1)) 位成員")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, HCSpacing.x1)
        }
    }

    @ViewBuilder
    private var familyMembersSection: some View {
        if !familyMembers.isEmpty {
            Section("家人") {
                ForEach(familyMembers) { member in
                    NavigationLink {
                        MemberDetailView(member: member)
                    } label: {
                        memberRow(member)
                    }
                    .hcCard()
                    .listRowInsets(
                        EdgeInsets(
                            top: HCSpacing.x1,
                            leading: HCSpacing.x4,
                            bottom: HCSpacing.x1,
                            trailing: HCSpacing.x4
                        )
                    )
                    .listRowBackground(Color.clear)
                    .swipeActions {
                        Button(role: .destructive) {
                            context.delete(member)
                            context.saveReporting()
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func memberRow(_ member: LocalFamilyMember) -> some View {
        let circleCount = member.lifeCircles.count
        return HStack(spacing: HCSpacing.x3) {
            Text(roleEmoji(for: member.name))
                .font(.system(size: 24))
                .frame(width: 40, height: 40)
                .background(.secondary.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: HCSpacing.x1) {
                Text(member.name).font(.body.weight(.medium))
                Text("\(lastPingText(member)) · \(locationStatusText(member))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(circleCount) 圈")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var placesSection: some View {
        if !places.isEmpty {
            Section("重要地點") {
                ForEach(places) { place in
                    NavigationLink {
                        MemberDetailView(member: place)
                    } label: {
                        HStack(spacing: HCSpacing.x3) {
                            Image(systemName: "mappin.circle.fill")
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: HCSpacing.x1) {
                                Text(place.name)
                                let fixedCount = place.lifeCircles.filter { $0.kind == .fixed }.count
                                Text("\(fixedCount) 個固定圈")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            context.delete(place)
                            context.saveReporting()
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - C：退出／解散家庭圈

    /// 已入圈兩態（單人／多人）底部都會出現的破壞性動作區。
    private var leaveFamilySection: some View {
        Section {
            Button(role: .destructive) {
                leaveError = nil
                showLeaveConfirm = true
            } label: {
                HStack {
                    Text(isCircleSolo && sync.isFamilyOwner ? "解散家庭圈" : "退出家庭圈")
                    Spacer()
                    if isLeavingFamily {
                        ProgressView()
                    }
                }
            }
            .disabled(isLeavingFamily)
            if let leaveError {
                Text(leaveError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// C2：文案分流——一般成員／圈主但還有其他成員／圈主且只剩自己（會直接解散）。
    private var leaveDialogTitle: String {
        isCircleSolo && sync.isFamilyOwner ? "確定要解散家庭圈嗎？" : "確定要退出家庭圈嗎？"
    }

    private var leaveDialogMessage: String {
        if isCircleSolo && sync.isFamilyOwner {
            return "你是唯一成員，退出後這個家庭圈會直接解散。"
        }
        let base = "退出後你將看不到家人的位置與回報，家人也看不到你。你的帳號與本機資料都會保留。"
        if sync.isFamilyOwner {
            return base + "你建立的家庭圈會留給其他成員繼續使用。"
        }
        return base
    }

    /// C3/C4：離開前先停止即時位置分享（避免 currentFamilyID 變 nil 後，背景定位更新
    /// 又透過 ensureFamily() 意外建立一個新家庭圈），再呼叫 FamilySyncService 統一入口
    /// （內部依 isFamilyOwner／memberUids 自動決定退出或解散，並清掉同步而來的家人投影）。
    /// 失敗要顯示人話錯誤，不得 silent fail。
    private func performLeaveFamily() async {
        isLeavingFamily = true
        leaveError = nil
        defer { isLeavingFamily = false }
        if UserDefaults.standard.bool(forKey: SettingsKeys.liveLocationSharingEnabled) {
            UserDefaults.standard.set(false, forKey: SettingsKeys.liveLocationSharingEnabled)
            LocationService.shared.syncLiveLocationSharing(isEnabled: false)
            await sync.stopLiveLocationSharing(context: context)
        }
        do {
            try await sync.leaveFamily(context: context)
        } catch {
            leaveError = "網路連線有問題，請稍後再試一次。"
            AppLog.cloudError("退出家庭圈失敗：\(error.localizedDescription)")
        }
    }

    /// 身分 emoji：成員名對得上 FamilyRole.all 的用其 emoji（爸爸、媽媽⋯），對不上一律用中性黃臉。
    private func roleEmoji(for name: String) -> String {
        FamilyRole.all.first(where: { $0.label == name })?.emoji ?? FamilyRole.customEmoji
    }

    /// 這位家人最新的安否回報時間（比對署名；還沒回報過就明講，不是留白讓人猜）
    private func lastPingText(_ member: LocalFamilyMember) -> String {
        guard let ping = sync.pings
            .filter({ $0.senderName == member.name })
            .max(by: { $0.createdAt < $1.createdAt }) else {
            return "尚未回報"
        }
        return ping.createdAt.formatted(.relative(presentation: .named))
    }

    /// 位置狀態：分享中／過期／未開啟——三態直接對應即時圈是否存在、是否仍在有效時效內。
    private func locationStatusText(_ member: LocalFamilyMember) -> String {
        guard let live = member.lifeCircles.first(where: { $0.kind == .live }) else {
            return "未開啟"
        }
        return live.isActiveForAlerts ? "分享中" : "過期"
    }

    /// 等前一張 sheet 的收合動畫結束再開固定圈編輯器；
    /// 立刻 present 會撞上仍在收合中的 sheet 而被系統丟棄
    private func scheduleCircleEditor(_ member: LocalFamilyMember) {
        Task {
            try? await Task.sleep(for: .milliseconds(550))
            newMemberForCircle = member
        }
    }

    // MARK: - 付費閘門（成員／地點額度）

    /// 「新增家人」入口共用閘門：額度用滿且非 Guardian+ 就改開付費頁，不放行手動新增表單。
    /// 注意：邀請碼加入他人家庭圈的路徑不經過這裡（見 [EntitlementStore.canAddFamilyMember] 說明）。
    private func gateAddFamilyMember() {
        guard entitlementStore.canAddFamilyMember(currentCount: familyMembers.count) else {
            Analytics.track("paywall_from_member_limit")
            showPaywall = true
            return
        }
        adding = true
    }

    /// 「新增重要地點」入口共用閘門：FamilyListView 的 toolbar 與 addPlaceCard 都呼叫這裡，
    /// 保證兩處判斷的額度定義永遠一致。
    private func gateAddPlace() {
        guard entitlementStore.canAddPlace(currentCount: places.count) else {
            Analytics.track("paywall_from_place_limit")
            showPaywall = true
            return
        }
        addingPlace = true
    }

    /// PlaceSelectView 選定名稱後直接建立地點成員（不再經過 MemberEditorView 的打字表單），
    /// 接著沿用既有兩段式時序接固定圈編輯器。
    private func createPlace(name: String) {
        let member = LocalFamilyMember(name: name, relationship: "重要地點", kind: "place")
        context.insert(member)
        context.saveReporting()
        Analytics.track("place_added")
        scheduleCircleEditor(member)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        FamilyListView()
    }
    .modelContainer(PreviewSupport.container())
    .environment(FamilySyncService())
    .environment(TabRouter())
    .environment(EntitlementStore())
}
#endif
