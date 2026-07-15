import SwiftUI
import SwiftData

/// 地圖與提醒中心共用的區域警報橫幅
struct RegionAlertBanner: View {
    let alert: RegionAlert
    let members: [LocalFamilyMember]

    var body: some View {
        HStack {
            Image(systemName: "cloud.bolt.rain.fill").foregroundStyle(.orange)
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
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private var matchedText: String {
        let matched = alert.matchedCircles(members: members)
        guard !matched.isEmpty else { return "影響 \(alert.affectedDistricts.joined(separator: "、"))" }
        let names = matched.map { "\($0.memberName)（\($0.circleName)）" }.joined(separator: "、")
        return "影響 \(names) 所在行政區"
    }
}

struct RegionAlertDetailView: View {
    let alert: RegionAlert
    let members: [LocalFamilyMember]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("\(alert.statusText)・\(alert.severity)", systemImage: "cloud.bolt.rain.fill")
                        .foregroundStyle(alert.isEnded ? Color.secondary : Color.orange)
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
