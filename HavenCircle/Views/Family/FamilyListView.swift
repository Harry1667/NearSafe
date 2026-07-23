import SwiftUI
import SwiftData

/// 家人清單：以「人」為中心呈現——災害時真正要看的是「誰在哪、平不平安」，
/// 不是一排參數設定。空狀態與有家人狀態的引導完全不同：
/// - 空狀態（只有本人／重要地點，沒有真人家人）：情境卡直球講「為什麼需要」＋邀請大按鈕，
///   不顯示 LiveCircleSharingSection——一個人分享位置沒有對象看，只會撞登入牆
///   （2026-07 實測回饋：「想要自己的位置也需要登入，第三頁是做壞的」正是這個畫面）。
/// - 有家人狀態：本人卡固定最上（含位置分享開關）、每位家人一張卡、重要地點另起小節。
struct FamilyListView: View {
    @Environment(\.modelContext) private var context
    @Environment(FamilySyncService.self) private var sync
    @Query private var members: [LocalFamilyMember]
    @AppStorage(SettingsKeys.profileDisplayName) private var displayName = ""

    @State private var adding = false
    @State private var addingPlace = false
    /// 剛儲存的家人/地點：編輯器收合後接著替它開固定圈編輯器（兩段式流程合併成一段）
    @State private var newMemberForCircle: LocalFamilyMember?

    // 邀請流程（空狀態的主 CTA）
    @State private var signInGate = SignInGate()
    @State private var showInviteOptions = false
    @State private var showJoinByCode = false
    @State private var showRoleSelect = false
    @State private var isInviting = false
    @State private var inviteError: String?

    /// 判法與 HomeStatusView.isSoloUser 完全一致：只算「人」不算「重要地點」——
    /// 這裡、FamilyHubView、HomeStatusView 若各自定義計數邏輯，就會養出兩套真相。
    private var isSoloUser: Bool {
        members.filter { !$0.isPlace }.count < 2
    }

    private var me: LocalFamilyMember? { members.first(where: \.isCurrentUser) }
    private var familyMembers: [LocalFamilyMember] {
        members.filter { !$0.isPlace && !$0.isCurrentUser }
    }
    private var places: [LocalFamilyMember] {
        members.filter(\.isPlace)
    }

    var body: some View {
        List {
            if isSoloUser {
                emptyStateSection
                // 單人也能用：這正是使用者要的「我的即時圈」——純本地，不用登入
                FollowCircleToggleSection()
                addPlaceCard
                placesSection
            } else {
                myCardSection
                familyMembersSection
                placesSection
                InviteFamilySection()
            }
        }
        .toolbar {
            Menu {
                Button("新增家人", systemImage: "person.badge.plus") { adding = true }
                Button("新增重要地點", systemImage: "mappin.and.ellipse") { addingPlace = true }
            } label: {
                Label("新增", systemImage: "plus")
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
        .sheet(item: $newMemberForCircle) { member in
            CircleEditorView(member: member)
        }
        .sheet(isPresented: $showInviteOptions) { InviteOptionsView() }
        .sheet(isPresented: $showJoinByCode) { JoinByCodeView() }
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
        .task { await sync.refreshAccountStatus() }
        // iPad：整份清單限寬置中，避免按鈕與列卡撐滿 13 吋全寬（iPhone 上無感）；
        // 外圍再鋪同款群組底色，否則 List 底色只到 600pt，左右會露出不同色階的接縫
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - 空狀態（還沒有真人家人）

    /// 情境卡置頂：直球講「為什麼需要」，不是功能清單——這正是使用者罵「沒有引導」的畫面，
    /// 不能再放一排並列 Section 讓人自己猜入口在哪。
    private var emptyStateSection: some View {
        Section {
            VStack(spacing: HCSpacing.x3) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(HCColor.brand)
                Text("災害來的時候，一個人知道不夠。")
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Button {
                    signInGate.perform { await startInviteFlow() }
                } label: {
                    Label("邀請家人", systemImage: "person.crop.circle.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInviting)
                if isInviting {
                    ProgressView()
                }
                if let inviteError {
                    Text(inviteError)
                        .font(.caption)
                        .foregroundStyle(HCColor.danger)
                        .multilineTextAlignment(.center)
                }
                Button("我收到了邀請碼") {
                    signInGate.perform { showJoinByCode = true }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, HCSpacing.x4)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    /// 次要卡：一個人也能守護「不是自己」的地方（爸媽家、公司）。
    private var addPlaceCard: some View {
        Section {
            Button {
                addingPlace = true
            } label: {
                HStack(spacing: HCSpacing.x3) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.title2)
                        .foregroundStyle(HCColor.medical)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("新增重要地點").font(.body.weight(.medium))
                        Text("爸媽家、公司，都能設警戒圈")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// 建立家庭圈（若尚未建立）並開啟邀請碼畫面。首次建立家庭圈成功後先接身分選擇（C3），
    /// 選完／略過再開邀請碼畫面。
    private func startInviteFlow() async {
        isInviting = true
        inviteError = nil
        defer { isInviting = false }
        do {
            let isFirstFamily = sync.currentInviteCode == nil
            if isFirstFamily {
                _ = try await sync.createFamily()
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

    // MARK: - 有家人狀態

    /// 本人卡固定最上：名字＋「這是你」＋緊接著位置分享開關（沿用 LiveCircleSharingSection，
    /// 實作成本最低——它本身就是完整的 Section，不需要拆開重寫 toggle 邏輯）。
    @ViewBuilder
    private var myCardSection: some View {
        if let me {
            Section("我") {
                HStack(spacing: HCSpacing.x3) {
                    Text(roleEmoji(for: me.name))
                        .font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(me.name).font(.body.weight(.semibold))
                        Text("這是你").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            // 本地跟隨圈（免登入）放在分享給家人（LiveCircleSharingSection／Firebase）之前，
            // 兩者是兩碼事：前者只在這支手機決定警戒圈跟不跟人走，後者才是同步給家人看
            FollowCircleToggleSection(disambiguateFromSharing: true)
            LiveCircleSharingSection()
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
                .font(.system(size: 26))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).font(.body.weight(.medium))
                Text("\(lastPingText(member)) · \(locationStatusText(member))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(circleCount) 圈")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, HCSpacing.x1)
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
                                .foregroundStyle(HCColor.medical)
                            VStack(alignment: .leading, spacing: 2) {
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

    /// PlaceSelectView 選定名稱後直接建立地點成員（不再經過 MemberEditorView 的打字表單），
    /// 接著沿用既有兩段式時序開固定圈編輯器。
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
}
#endif
