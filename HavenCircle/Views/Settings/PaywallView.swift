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
                VStack(spacing: 24) {
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
                                .foregroundStyle(HCColor.danger)
                                .multilineTextAlignment(.center)
                        }
                        restoreAndManageButtons
                    }
                    finePrint
                    legalLinks
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
            .task { await store.loadProducts() }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
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

    /// 已是 Guardian+：整頁改為感謝狀態，不再顯示購買 UI。
    private var guardianPlusStatusCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
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
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
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

    @ViewBuilder
    private var pricingCards: some View {
        if let loadError = store.productLoadError {
            VStack(spacing: 10) {
                Text(loadError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重試") {
                    Task { await store.reloadProducts() }
                }
                .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        } else {
            VStack(spacing: 12) {
                planCard(
                    title: "年訂",
                    price: store.yearlyProduct?.displayPrice,
                    note: yearlyNote,
                    badge: "最超值",
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
                if let price {
                    Text(price).font(.title3.weight(.bold))
                } else {
                    // 商品尚未載入完成：先用同尺寸佔位文字避免版面跳動，載入完成即替換
                    Text("NT$00")
                        .font(.title3.weight(.bold))
                        .redacted(reason: .placeholder)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? HCColor.brand : Color(.separator), lineWidth: selected ? 2 : 1)
            )
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
                        .tint(.white)
                } else {
                    Text(ctaTitle)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(HCColor.brand, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
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
        HStack(spacing: 20) {
            Button("恢復購買") {
                Task { await store.restorePurchases() }
            }
            Button("管理訂閱") {
                showManageSubscriptions = true
            }
        }
        .font(.footnote.weight(.semibold))
        .disabled(store.purchaseInProgress)
    }

    private var finePrint: some View {
        VStack(spacing: 6) {
            // 倫理承諾：不分免費或付費，保命警報一律免費——這是信任的底線，寫在付費頁最顯眼的收尾處
            Text("災害警報推播永遠免費，不分免費或付費。")
                .foregroundStyle(.secondary)
            Text("訂閱為自動續訂：除非在到期前至少 24 小時取消，否則會自動以相同方案續約並向 Apple 帳號扣款；可隨時在「設定 > Apple 帳號 > 訂閱」中取消或管理。試用期內取消不收費。")
            Text("安心圈不是 110／119 或緊急救難服務。")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
    }

    private var legalLinks: some View {
        HStack(spacing: 16) {
            NavigationLink("隱私權政策") {
                LegalDocumentView(document: .privacy)
            }
            NavigationLink("使用條款") {
                LegalDocumentView(document: .terms)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

#Preview {
    PaywallView()
        .environment(EntitlementStore())
}
