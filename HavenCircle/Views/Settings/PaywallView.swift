import StoreKit
import SwiftUI

/// 升級（Guardian+）定價頁——接 StoreKit 2 真實金流（見 EntitlementStore）。
/// 設計原則：核心安全警報「兩邊都免費」的訊息要最醒目，付費牆只擋規模與便利。
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementStore.self) private var store
    /// 選中的方案：年訂為主（低頻安全 App 用「一年的安心」對抗月訂 churn）
    @State private var yearlySelected = true
    @State private var showManageSubscriptions = false

    // 免費 vs 進階 分層（對照 MONETIZATION_PLAN.md 三方辯論裁決）。
    // 額度數字一律讀 FreeTier.swift，不寫死數字——調整額度只需要改那邊即可讓這張表跟著變。
    // 「自訂靜音時段」已免費上線（不是付費賣點），不得再出現在這張表。
    private var tiers: [(feature: String, free: String, plus: String)] {
        [
            ("核心災害警報", "全開", "全開"),
            ("家庭成員", "\(FreeTier.maxFamilyMembers) 人", "無上限"),
            ("重要地點", "\(FreeTier.maxPlaces) 個", "無上限"),
            ("歷史回顧", "\(FreeTier.historyDays) 天", "\(FreeTier.plusHistoryDays) 天"),
            ("未來進階功能（城市安全情報、週報進階）", "—", "優先享有"),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: HCSpacing.x6) {
                    header
                    safetyFreeBanner
                    if store.isPlus {
                        guardianPlusStatusCard
                    } else {
                        comparisonCard
                        pricingCards
                        ctaButton
                        if let purchaseError = store.purchaseError {
                            Text(purchaseError)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        restoreAndManageButtons
                    }
                    finePrint
                    legalLinks
                }
                .padding(.horizontal, HCSpacing.x4)
                .padding(.bottom, HCSpacing.x6)
            }
            .navigationTitle("升級 Guardian+")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .analyticsScreen("paywall")
            .task { await store.loadProducts() }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        }
    }

    private var header: some View {
        VStack(spacing: HCSpacing.x3) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [HCColor.brand.opacity(0.18), HCColor.brand.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                Circle()
                    .stroke(HCColor.brand.opacity(0.16), lineWidth: 1)
                    .frame(width: 80, height: 80)
                Image(systemName: "crown.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(HCColor.brand)
            }
            Text("守護更多人、更大範圍")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text("免費就能保護一個完整家庭；當你要照顧三代同堂、多個據點、看更久的歷史時，用 Guardian+ 解鎖。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, HCSpacing.x3)
    }

    /// 最醒目的一條：安全永遠免費（倫理與信任的核心訊息）
    private var safetyFreeBanner: some View {
        HStack(alignment: .top, spacing: HCSpacing.x3) {
            Image(systemName: "checkmark.shield.fill")
                .fontWeight(.medium)
                .foregroundStyle(HCColor.brand)
            Text("火災、地震、颱風等**保命警報永遠免費**，付費只解鎖規模與便利。")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hcCard()
    }

    /// 已是 Guardian+：整頁改為感謝狀態，不再顯示購買 UI。
    private var guardianPlusStatusCard: some View {
        VStack(spacing: HCSpacing.x3) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(HCColor.brand)
            Text("你已是 Guardian+")
                .font(.title3.weight(.bold))
            Text("謝謝你的支持，讓安心圈能持續守護更多家庭。你的家庭成員、多個關心據點與完整歷史回顧都已解鎖。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showManageSubscriptions = true
            } label: {
                Text("管理訂閱")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.top, HCSpacing.x1)
        }
        .frame(maxWidth: .infinity)
        .hcCard()
    }

    private var comparisonCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("功能").font(.caption.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                Text("免費").font(.caption.weight(.semibold)).frame(width: 72)
                Text("Guardian+").font(.caption.weight(.bold)).foregroundStyle(HCColor.brand).frame(width: 88)
            }
            .padding(.vertical, HCSpacing.x2)
            Divider()
            ForEach(tiers, id: \.feature) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.feature).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.free).font(.caption).foregroundStyle(.secondary).frame(width: 72)
                    Text(row.plus).font(.caption.weight(.semibold)).foregroundStyle(HCColor.brand).frame(width: 88)
                }
                .padding(.vertical, HCSpacing.x2)
                if row.feature != tiers.last?.feature { Divider() }
            }
        }
        .hcCard()
    }

    @ViewBuilder
    private var pricingCards: some View {
        if let loadError = store.productLoadError {
            VStack(spacing: HCSpacing.x2) {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重試") {
                    Task { await store.reloadProducts() }
                }
                .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .hcCard()
        } else {
            VStack(spacing: HCSpacing.x3) {
                planCard(
                    title: "年訂",
                    price: store.yearlyProduct?.displayPrice,
                    note: yearlyNote,
                    badge: "最划算",
                    selected: yearlySelected
                ) {
                    yearlySelected = true
                }
                planCard(
                    title: "月訂",
                    price: store.monthlyProduct?.displayPrice,
                    note: "每月自動續訂 · 隨時可取消",
                    badge: nil,
                    selected: !yearlySelected
                ) {
                    yearlySelected = false
                }
            }
        }
    }

    /// 年訂副標：優先顯示真實試用天數（讀自 .storekit／App Store Connect 設定的
    /// introductory offer），沒有試用資訊時退回單純的折算文案。
    private var yearlyNote: String {
        var parts: [String] = []
        if let yearly = store.yearlyProduct {
            let monthly = yearly.price / 12
            let formatted = monthly.formatted(yearly.priceFormatStyle)
            parts.append("約 \(formatted)/月")
        }
        if let trialDays = freeTrialDays(for: store.yearlyProduct) {
            parts.append("附 \(trialDays) 天免費試用")
        }
        return parts.isEmpty ? "年繳最划算" : parts.joined(separator: " · ")
    }

    /// 從商品的 introductory offer 讀出免費試用天數；非「免費試用」型態的優惠一律回傳 nil。
    private func freeTrialDays(for product: Product?) -> Int? {
        guard let offer = product?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let value = offer.period.value
        switch offer.period.unit {
        case .day: return value
        case .week: return value * 7
        case .month: return value * 30
        case .year: return value * 365
        @unknown default: return nil
        }
    }

    private func planCard(
        title: String,
        price: String?,
        note: String,
        badge: String?,
        selected: Bool,
        tap: @escaping () -> Void
    ) -> some View {
        Button(action: tap) {
            HStack(spacing: HCSpacing.x3) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? HCColor.brand : .secondary)
                    .font(.title3.weight(.medium))
                VStack(alignment: .leading, spacing: HCSpacing.x1) {
                    HStack(spacing: HCSpacing.x2) {
                        Text(title).font(.body.weight(.semibold))
                        if let badge {
                            Text(badge)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, HCSpacing.x2)
                                .padding(.vertical, HCSpacing.x1)
                                .background(
                                    HCColor.brand.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: HCRadius.chip, style: .continuous)
                                )
                                .foregroundStyle(HCColor.brand)
                        }
                    }
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let price {
                    Text(price).font(.title3.weight(.bold))
                } else {
                    // 商品尚未載入完成：先用同尺寸佔位文字避免版面跳動，載入完成即替換
                    Text("NT$00")
                        .font(.title3.weight(.bold))
                        .redacted(reason: .placeholder)
                }
            }
            .hcCard()
            .overlay(
                RoundedRectangle(cornerRadius: HCRadius.card, style: .continuous)
                    .stroke(selected ? HCColor.brand : Color(.separator), lineWidth: selected ? 2 : 1)
            )
            .shadow(color: selected ? HCColor.brand.opacity(0.12) : .clear, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(price == nil)
    }

    private var ctaButton: some View {
        Button {
            Task { await purchaseSelectedPlan() }
        } label: {
            HStack {
                if store.purchaseInProgress {
                    ProgressView()
                        .tint(yearlySelected ? .white : HCColor.brand)
                } else {
                    Text(ctaTitle)
                        .font(.body.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, HCSpacing.x3)
            .background(
                yearlySelected ? HCColor.brand : Color.clear,
                in: RoundedRectangle(cornerRadius: HCRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: HCRadius.control, style: .continuous)
                    .stroke(yearlySelected ? Color.clear : Color(.separator), lineWidth: 1)
            )
            .foregroundStyle(yearlySelected ? .white : .primary)
        }
        .disabled(store.purchaseInProgress || selectedProduct == nil)
    }

    private var ctaTitle: String {
        if yearlySelected, freeTrialDays(for: store.yearlyProduct) != nil {
            return "開始免費試用"
        }
        return "訂閱 Guardian+"
    }

    private var selectedProduct: Product? {
        yearlySelected ? store.yearlyProduct : store.monthlyProduct
    }

    private func purchaseSelectedPlan() async {
        guard let product = selectedProduct else { return }
        await store.purchase(product)
    }

    private var restoreAndManageButtons: some View {
        HStack(spacing: HCSpacing.x6) {
            Button("恢復購買") {
                Task { await store.restorePurchases() }
            }
            Button("管理訂閱") {
                showManageSubscriptions = true
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .disabled(store.purchaseInProgress)
    }

    private var finePrint: some View {
        VStack(spacing: HCSpacing.x2) {
            // 倫理承諾：不分免費或付費，保命警報一律免費——這是信任的底線，寫在付費頁最顯眼的收尾處
            Text("災害警報推播永遠免費，不分免費或付費。")
                .foregroundStyle(.secondary)
            Text("訂閱為自動續訂：除非在到期前至少 24 小時取消，否則會自動以相同方案續約並向 Apple 帳號扣款；可隨時在「設定 > Apple 帳號 > 訂閱」中取消或管理。試用期內取消不收費。")
            Text("安心圈不是 110／119 或緊急救難服務。")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }

    private var legalLinks: some View {
        HStack(spacing: HCSpacing.x4) {
            NavigationLink("隱私權政策") {
                LegalDocumentView(document: .privacy)
            }
            NavigationLink("使用條款") {
                LegalDocumentView(document: .terms)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

#Preview {
    PaywallView()
        .environment(EntitlementStore())
}
