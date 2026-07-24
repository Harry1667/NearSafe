import SwiftUI

/// 升級（Guardian+）定價頁——目前為 UI 版面，尚未接 StoreKit 金流。
/// 升級按鈕先顯示「即將推出」；實際訂閱待驗證留存後再接 IAP（見 MONETIZATION_PLAN.md）。
/// 設計原則：核心安全警報「兩邊都免費」的訊息要最醒目，付費牆只擋規模與便利。
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    /// 選中的方案：年訂為主（低頻安全 App 用「一年的安心」對抗月訂 churn）
    @State private var yearlySelected = true
    @State private var showComingSoon = false

    // 免費 vs 進階 分層（對照 MONETIZATION_PLAN.md）
    private let tiers: [(feature: String, free: String, plus: String)] = [
        ("核心災害警報", "全開", "全開"),
        ("家庭成員", "6 位", "無上限"),
        ("生活圈 / 警戒區", "2 個", "無上限"),
        ("關心的據點（老家/學校）", "1 個", "多據點"),
        ("歷史回顧", "30 天", "完整"),
        ("即時圈分享", "基本", "長時不限"),
        ("所在地進階資料源", "每日摘要", "即時推播"),
        ("自訂靜音時段", "—", "✓"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    safetyFreeBanner
                    comparisonCard
                    pricingCards
                    ctaButton
                    finePrint
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .navigationTitle("升級 Guardian+")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .analyticsScreen("paywall")
            .alert("訂閱功能即將推出", isPresented: $showComingSoon) {
                Button("好", role: .cancel) {}
            } message: {
                Text("付費方案正在準備中。核心安全警報現在、未來都完全免費。")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 46))
                .foregroundStyle(HCColor.notice)
            Text("守護更多人、更大範圍")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text("免費就能保護一個完整家庭；當你要照顧三代同堂、多個據點、看更久的歷史時，用 Guardian+ 解鎖。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    /// 最醒目的一條：安全永遠免費（倫理與信任的核心訊息）
    private var safetyFreeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(HCColor.safe)
            Text("火災、地震、颱風等**保命警報永遠免費**，付費只解鎖規模與便利。")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HCColor.safe.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var comparisonCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("功能").font(.footnote.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                Text("免費").font(.footnote.weight(.semibold)).frame(width: 76)
                Text("Guardian+").font(.footnote.weight(.bold)).foregroundStyle(HCColor.brand).frame(width: 84)
            }
            .padding(.vertical, 10)
            Divider()
            ForEach(tiers, id: \.feature) { row in
                HStack {
                    Text(row.feature).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.free).font(.footnote).foregroundStyle(.secondary).frame(width: 76)
                    Text(row.plus).font(.footnote.weight(.semibold)).foregroundStyle(HCColor.brand).frame(width: 84)
                }
                .padding(.vertical, 9)
                if row.feature != tiers.last?.feature { Divider() }
            }
        }
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var pricingCards: some View {
        VStack(spacing: 12) {
            planCard(title: "年訂", price: "NT$690", note: "約 NT$58/月 · 附 7 天免費試用", badge: "最超值", selected: yearlySelected) {
                yearlySelected = true
            }
            planCard(title: "月訂", price: "NT$90", note: "每月自動續訂 · 隨時可取消", badge: nil, selected: !yearlySelected) {
                yearlySelected = false
            }
        }
    }

    private func planCard(title: String, price: String, note: String, badge: String?, selected: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 14) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? HCColor.brand : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline)
                        if let badge {
                            Text(badge).font(.caption2.weight(.bold))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(HCColor.notice.opacity(0.2), in: Capsule())
                                .foregroundStyle(HCColor.notice)
                        }
                    }
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(price).font(.title3.weight(.bold))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? HCColor.brand : Color(.separator), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var ctaButton: some View {
        Button {
            showComingSoon = true
        } label: {
            Text(yearlySelected ? "開始 7 天免費試用" : "訂閱 Guardian+")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(HCColor.brand, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
        }
    }

    private var finePrint: some View {
        VStack(spacing: 6) {
            Text("試用結束前可隨時取消，不收費。訂閱透過 App Store 付款，可在系統設定中管理。")
            Text("安心圈不是 110／119 或緊急救難服務。")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
    }
}

#Preview {
    PaywallView()
}
