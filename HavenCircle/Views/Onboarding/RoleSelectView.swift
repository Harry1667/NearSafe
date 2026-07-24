import SwiftUI

/// 家庭身分：新手用「選方塊」代替打字，一眼選出自己在家裡是誰。
/// label 同時當成這個人的顯示名稱（安否回報署名、家人清單顯示都用它）。
struct FamilyRole: Identifiable, Hashable {
    var id: String { label }
    let label: String
    let emoji: String

    /// 核心家庭身分：精簡到 6 個，且全用預設黃臉、互不撞臉（emoji 唯一能同時
    /// 做到「風格一致」又「彼此可分」的一組——成年男女、男女孩、老年男女）。
    /// 哥哥姊姊、寶寶、看護等其餘稱呼走「其他稱呼」自訂（2026-07-23 模擬走查：
    /// 硬加方塊會撞臉，開放自訂一格就能涵蓋所有家庭組成）。
    static let all: [FamilyRole] = [
        FamilyRole(label: "爸爸", emoji: "👨"),
        FamilyRole(label: "媽媽", emoji: "👩"),
        FamilyRole(label: "兒子", emoji: "👦"),
        FamilyRole(label: "女兒", emoji: "👧"),
        FamilyRole(label: "阿公", emoji: "👴"),
        FamilyRole(label: "阿嬤", emoji: "👵"),
    ]

    /// 自訂稱呼統一用的中性黃臉（與六方塊風格一致）。
    static let customEmoji = "🙂"
}

/// 身分選擇頁：定位之後問「你在家裡是誰」，用方塊點選、不打字。
/// 點一個方塊＝選定並直接進下一步（最少點擊）；身分之後可在設定改。
/// 副標寫「家人平常怎麼叫你」——身分是相對的（同一人既是媽媽也是阿嬤），
/// 以「家裡的稱呼」為準就沒有二選一的困境（2026-07-23 模擬走查修正）。
struct RoleSelectView: View {
    /// 選好身分後呼叫，帶著選定的身分交給上層完成設定。
    var onSelect: (FamilyRole) -> Void
    /// 以彈窗呈現時的「稍後再說」出路（nil＝不顯示，例如強制流程）。略過不清除待辦，之後仍會再問。
    var onSkip: (() -> Void)?

    /// 「其他稱呼」輸入框
    @State private var showCustomInput = false
    @State private var customName = ""

    private let columns = [
        GridItem(.flexible(), spacing: HCSpacing.x3),
        GridItem(.flexible(), spacing: HCSpacing.x3),
        GridItem(.flexible(), spacing: HCSpacing.x3),
    ]

    var body: some View {
        VStack(spacing: 0) {
            if let onSkip {
                HStack {
                    Spacer()
                    Button("稍後再說", action: onSkip)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, HCSpacing.x4)
                .padding(.top, HCSpacing.x4)
            }
            VStack(spacing: HCSpacing.x2) {
                Text("你在家裡是誰？")
                    .font(.title2.weight(.bold))
                Text("選家人平常對你的稱呼，\n他們就能一眼認出你。之後可在設定更改。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, onSkip == nil ? HCSpacing.x6 : HCSpacing.x3)
            .padding(.horizontal, HCSpacing.x6)

            ScrollView {
                LazyVGrid(columns: columns, spacing: HCSpacing.x3) {
                    ForEach(FamilyRole.all) { role in
                        roleTile(role)
                    }
                    customTile
                }
                .padding(HCSpacing.x4)
            }
        }
        // iPad 上限制內容欄寬度並置中，避免固定 3 欄的方塊在 13 吋螢幕上被拉得過大
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity)
        // fullScreenCover 呈現、根層又只有 VStack（無 List/Form/NavigationStack 自帶不透明底），
        // 真機深色模式下會整層透明、跟底下畫面疊成鬼畫面——鋪一層系統底色，深淺色都對。
        .background(Color(.systemBackground).ignoresSafeArea())
        .analyticsScreen("role_select")
        .alert("家人怎麼叫你？", isPresented: $showCustomInput) {
            TextField("例如：姊姊、寶寶、阿姨", text: $customName)
            Button("就用這個") {
                let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                onSelect(FamilyRole(label: name, emoji: FamilyRole.customEmoji))
            }
            Button("取消", role: .cancel) { customName = "" }
        } message: {
            Text("輸入家裡常用的稱呼即可")
        }
    }

    private func roleTile(_ role: FamilyRole) -> some View {
        Button {
            onSelect(role)
        } label: {
            tileLabel(emoji: role.emoji, title: role.label)
        }
        .buttonStyle(RoleTileButtonStyle())
        .accessibilityLabel(role.label)
    }

    /// 第七格：六個核心身分之外的所有稱呼（姊姊、寶寶、看護⋯）走自訂輸入。
    private var customTile: some View {
        Button {
            showCustomInput = true
        } label: {
            tileLabel(emoji: FamilyRole.customEmoji, title: "其他稱呼")
        }
        .buttonStyle(RoleTileButtonStyle())
        .accessibilityLabel("其他稱呼，自行輸入")
    }

    private func tileLabel(emoji: String, title: String) -> some View {
        VStack(spacing: HCSpacing.x2) {
            Text(emoji)
                .font(.system(size: 44))
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .hcCard()
        .aspectRatio(1, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: HCRadius.card, style: .continuous))
    }
}

/// 方塊維持安靜的灰階卡面，手指按下時才用品牌色描邊與縮放確認選取。
private struct RoleTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: HCRadius.card, style: .continuous)
                    .stroke(
                        configuration.isPressed ? HCColor.brand : Color(.separator),
                        lineWidth: configuration.isPressed ? 2 : 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .shadow(
                color: configuration.isPressed ? HCColor.brand.opacity(0.14) : .clear,
                radius: 8,
                y: 4
            )
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

#if DEBUG
#Preview {
    RoleSelectView(onSelect: { _ in })
}
#endif
