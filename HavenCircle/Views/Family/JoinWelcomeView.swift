import SwiftUI

/// C3：加入家庭圈成功後的慶祝畫面。fullScreenCover 呈現，「繼續」接著才是身分選擇（RoleSelectView）。
/// 這是修「加入後沒有任何提示」的核心一步——舊版加入成功只有一行畫面內小字，
/// 使用者根本沒感覺到「有效」，這裡刻意用整頁儀式感取代。
struct JoinWelcomeView: View {
    /// 按「繼續」後呼叫（由 JoinByCodeView 接著開身分選擇）
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: HCSpacing.x6) {
            Spacer()
            Text("🎉")
                .font(.system(size: 72))
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("歡迎加入！")
                    .font(.largeTitle.weight(.bold))
                Text("災害靠近時，你和家人會互相知道平安。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                onContinue()
            } label: {
                Text("繼續")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, HCSpacing.x4)
        }
        .padding(.horizontal, HCSpacing.x6)
        .padding(.top, HCSpacing.x6)
        // iPad：fullScreenCover 沒有 presentationSizing 可用，內容欄自己限寬置中，
        // 避免整頁儀式感在 13 吋螢幕上被拉伸得又空又怪
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview {
    JoinWelcomeView(onContinue: {})
}
#endif
