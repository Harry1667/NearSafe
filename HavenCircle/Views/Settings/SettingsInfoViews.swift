import SwiftUI

/// 資料來源頁：告訴使用者警報從哪來、多新鮮——這是安全 App 的信任基礎。
struct DataSourceView: View {
    var body: some View {
        List {
            Section("即時災害示警") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NCDR 民生示警平台").font(.subheadline.bold())
                    Text("國家災害防救科技中心彙整 28 個政府機關、43 類災害示警（颱風、地震、淹水、火災、停水等），本 App 每 5 分鐘同步一次。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DataFreshnessLabel()
                if let url = URL(string: "https://alerts.ncdr.nat.gov.tw/") {
                    Link("前往 NCDR 民生示警平台", destination: url)
                }
            }
            Section("緊急應變資源") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("避難收容所與急救責任醫院").font(.subheadline.bold())
                    Text("避難收容所來自內政部消防署「避難收容處所點位檔」（全國約 5,900 處）；急救責任醫院來自衛福部分區名單（全國 205 家），座標取自內政部國土測繪中心。全部內建於 App，斷網時仍可查詢與導航。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("環境與統計圖層") {
                Text("空氣品質：環境部空品測站即時資料，每小時更新。治安參考：內政部警政署刑事案件統計，每季更新（統計≠即時安全程度）。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("資料怎麼到你手上") {
                Text("政府示警 → 安心圈中繼站（整理與去重）→ 你的手機（依警戒圈與可信度篩選）。中繼站只傳遞公開示警；你主動開啟的即時圈位置另外只會存到 Firebase 雲端家庭圈資料庫（只有你的家庭圈成員能讀取），不會經過這台警報中繼站。")
                    .font(.footnote)
            }
            Section("目前限制（誠實告知）") {
                Text("即時交通事故與治安事件目前沒有政府公開的即時資料源；有新來源可用時會在更新中加入。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("資料來源")
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen("data_source")
    }
}

/// 關於頁：版本、官網與隱私原則。
struct AboutView: View {
    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version)（\(build)）"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("版本", value: versionText)
                if let url = URL(string: "https://havencircle.looptw.com") {
                    Link("官方網站", destination: url)
                }
            }
            Section("隱私原則") {
                Label("固定圈與事件資料儲存在這支手機", systemImage: "iphone")
                Label("即時圈必須由本人開啟，並可隨時停止", systemImage: "location.fill")
                Label("家人位置只存在 Firebase 雲端家庭圈資料庫，只有你的家庭圈成員能讀取", systemImage: "lock.fill")
            }
            .font(.subheadline)
            Section("法律文件") {
                NavigationLink("隱私權政策") { LegalDocumentView(document: .privacy) }
                NavigationLink("用戶協議") { LegalDocumentView(document: .userAgreement) }
                NavigationLink("使用條款") { LegalDocumentView(document: .terms) }
            }
            Section {
                Text("安心圈不是 110、119 或緊急救難服務。遇立即危險請直接撥打 110 或 119。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("關於安心圈")
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen("about")
    }
}
