import SwiftUI
import SwiftData

/// 地圖與提醒中心共用的區域警報橫幅
struct RegionAlertBanner: View {
    let alert: RegionAlert
    let members: [LocalFamilyMember]

    var body: some View {
        HStack(spacing: HCSpacing.x3) {
            Image(systemName: alert.iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HCColor.attention)
                .frame(width: 34, height: 34)
                .background(HCColor.attention.opacity(0.12), in: RoundedRectangle(cornerRadius: HCRadius.badge, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text("\(alert.kind)警報：\(alert.title)")
                    .font(.subheadline.bold())
                Text(matchedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .padding(HCSpacing.x3)
        .background(HCColor.attention.opacity(0.10), in: RoundedRectangle(cornerRadius: HCRadius.card, style: .continuous))
    }

    private var matchedText: String {
        let matched = alert.matchedCircles(members: members)
        guard !matched.isEmpty else { return "影響 \(districtSummary)" }
        let names = matched.map { "\($0.memberName)（\($0.circleName)）" }.joined(separator: "、")
        return "影響 \(names) 所在行政區"
    }

    /// 影響範圍截斷：前 3 個行政區＋「等 N 個地區」——NCDR 大範圍警報動輒列數十個鄉鎮，
    /// 整串塞進副標會把卡片撐到五六行；完整清單留在詳情頁
    private var districtSummary: String {
        let districts = alert.affectedDistricts
        guard districts.count > 3 else { return districts.joined(separator: "、") }
        return districts.prefix(3).joined(separator: "、") + " 等 \(districts.count) 個地區"
    }
}

struct RegionAlertDetailView: View {
    let alert: RegionAlert
    let members: [LocalFamilyMember]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("\(alert.statusText)・\(alert.severity)", systemImage: alert.iconName)
                        .foregroundStyle(alert.isEnded ? Color.secondary : HCColor.attention)
                    Text(alert.guidance)
                }
                Section("影響範圍") {
                    Text(alert.affectedDistricts.joined(separator: "、"))
                    ForEach(alert.matchedCircles(members: members), id: \.circleName) { match in
                        Label("\(match.memberName)・\(match.circleName)", systemImage: "person.crop.circle")
                            .font(.subheadline)
                    }
                }
                Section("來源") {
                    LabeledContent("發布單位", value: alert.sourceName)
                    LabeledContent("發布時間", value: alert.issuedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("最近更新", value: alert.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    if let url = URL(string: alert.sourceURL) {
                        Link("查看原始來源", destination: url)
                    }
                }
            }
            .navigationTitle(alert.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
