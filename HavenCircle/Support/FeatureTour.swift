import SwiftUI
import os // Swift 6.2 MemberImportVisibility：用 os.Logger 插值的檔案必須自行 import

// MARK: - 功能導覽（coach marks）
// 黑色半透明遮罩＋聚光燈挖洞，逐步介紹安心頁每個元件與使用流程。
// 觸發：Onboarding 完成後首次進主畫面（homeTourPending 旗標消耗制）；設定頁可重看。

/// 導覽目標：目標元件用 .tourAnchor(_:) 登記自己的位置，遮罩層據此挖洞
enum TourTarget: String {
    case statusHero
    case familyList
    case watchRow
    case historyRow
    case checkInButton
    /// 分頁列是 TabView 私有結構拿不到 anchor，用畫面底部矩形近似
    case tabBar
}

struct TourStep {
    let target: TourTarget
    let title: String
    let message: String
}

/// 收集各目標元件位置的 PreferenceKey（由子視圖向上匯報）
struct TourAnchorKey: PreferenceKey {
    static var defaultValue: [TourTarget: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// 把自己登記為導覽目標
    func tourAnchor(_ target: TourTarget) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [target: $0] }
    }
}

/// 挖洞遮罩：全畫面黑底＋目標區圓角開窗（even-odd 填色）
private struct CutoutMask: Shape {
    let cutout: CGRect
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(in: cutout, cornerSize: CGSize(width: 16, height: 16), style: .continuous)
        return path
    }
}

struct FeatureTourView: View {
    let anchors: [TourTarget: Anchor<CGRect>]
    /// nil＝導覽未進行；由 AppTabs 持有
    @Binding var stepIndex: Int?

    private static let allSteps: [TourStep] = [
        .init(target: .statusHero, title: "一眼看到全家狀態",
              message: "打開 App 第一眼：綠盾牌＝生活圈平安。有官方事件靠近時，這裡會整個變成紅色警示並帶你去看地圖。"),
        .init(target: .familyList, title: "家人與重要地點",
              message: "每位家人一行：圈內有沒有事件、最後一次回報平安是什麼時候。綠點＝目前無事。"),
        .init(target: .watchRow, title: "背景看守中",
              message: "沒讓你分心的事件都收在這——確認中的媒體報導、其他區域的官方事件、區域警報。點它進提醒中心看全部。"),
        .init(target: .historyRow, title: "回顧過去 7 天",
              message: "發生過什麼、何時解除，都留有紀錄，隨時回頭查。"),
        .init(target: .checkInButton, title: "報個平安",
              message: "災後最重要的一顆按鈕：一鍵告訴全家「我平安」，可選擇附上當下位置（只在按下的那一刻分享一次）。"),
        .init(target: .tabBar, title: "地圖與家人",
              message: "「安全地圖」看事件位置與警報範圍；「家人」管理生活圈、新增重要地點、邀請家人。"),
    ]

    /// 只導覽畫面上真的存在的元件（例如還沒有家人時跳過家人列）
    private var steps: [TourStep] {
        Self.allSteps.filter { anchors[$0.target] != nil || $0.target == .tabBar }
    }

    var body: some View {
        GeometryReader { proxy in
            let _ = {
                let missing = Self.allSteps.map(\.target).filter { anchors[$0] == nil && $0 != .tabBar }
                if !missing.isEmpty {
                    AppLog.pipeline.info("導覽缺錨點：\(missing.map(\.rawValue).joined(separator: ","))")
                }
            }()
            if let index = stepIndex, steps.indices.contains(index) {
                let step = steps[index]
                let rect = cutoutRect(for: step.target, in: proxy)
                ZStack(alignment: .topLeading) {
                    CutoutMask(cutout: rect)
                        .fill(Color.black.opacity(0.72), style: FillStyle(eoFill: true))
                        .contentShape(Rectangle())
                        .onTapGesture { advance() } // 點遮罩任意處＝下一步
                    // 聚光邊框：讓被介紹的元件在黑幕上發亮
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                    card(step: step, index: index, near: rect, in: proxy)
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: stepIndex)
    }

    /// 目標挖洞範圍：anchor 外擴 8pt；分頁列用畫面底部近似
    private func cutoutRect(for target: TourTarget, in proxy: GeometryProxy) -> CGRect {
        if target == .tabBar {
            return CGRect(x: 12, y: proxy.size.height - 104, width: proxy.size.width - 24, height: 88)
        }
        guard let anchor = anchors[target] else { return .zero }
        return proxy[anchor].insetBy(dx: -8, dy: -8)
    }

    /// 說明卡：目標在上半場放下方、在下半場放上方，避免遮住主角
    private func card(step: TourStep, index: Int, near rect: CGRect, in proxy: GeometryProxy) -> some View {
        let placeBelow = rect.midY < proxy.size.height / 2
        return VStack(alignment: .leading, spacing: HCSpacing.x2) {
            Text(step.title)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text(step.message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("略過導覽") { stepIndex = nil }
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("\(index + 1) / \(steps.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                Button(index + 1 == steps.count ? "完成" : "下一步") { advance() }
                    .font(.callout.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(HCColor.brand, in: Capsule())
            }
            .padding(.top, 4)
        }
        .padding(HCSpacing.x4)
        .background(Color(white: 0.12).opacity(0.95), in: RoundedRectangle(cornerRadius: HCRadius.card, style: .continuous))
        .padding(.horizontal, HCSpacing.x4)
        .frame(maxWidth: .infinity)
        .offset(y: placeBelow ? min(rect.maxY + 16, proxy.size.height - 260)
                              : max(rect.minY - 236, 60))
    }

    private func advance() {
        guard let index = stepIndex else { return }
        if index + 1 < steps.count {
            stepIndex = index + 1
        } else {
            stepIndex = nil
        }
    }
}
