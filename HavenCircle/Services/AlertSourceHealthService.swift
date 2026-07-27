import Foundation

/// 公開警報中繼端點的健康快照，供「設定 > 資料來源」直接顯示。
/// 只讀公開事件的批次時間與筆數，不傳送使用者、家庭圈或位置資料。
struct AlertSourceStatus: Identifiable, Sendable {
    enum Health: String, Sendable {
        case healthy = "正常更新"
        case delayed = "更新延遲"
        case unavailable = "暫時無法取得"
    }

    let id: String
    let name: String
    let sourceDescription: String
    let trustLabel: String
    let expectedUpdateText: String
    let updatedAt: Date?
    let itemCount: Int?
    let health: Health
    let detail: String?
}

enum AlertSourceHealthService {
    private struct Definition: Sendable {
        let id: String
        let name: String
        let sourceDescription: String
        let trustLabel: String
        let expectedUpdateText: String
        let endpoint: URL
        let delayedAfter: TimeInterval
    }

    private static let definitions: [Definition] = [
        Definition(
            id: "ncdr",
            name: "NCDR 民生示警平台",
            sourceDescription: "28 個政府機關的災害、民生與交通示警",
            trustLabel: "官方來源",
            expectedUpdateText: "約每 1 分鐘",
            endpoint: URL(string: "https://havencircle.looptw.com/crawler/api/latest.php")!,
            delayedAfter: 5 * 60
        ),
        Definition(
            id: "nfa",
            name: "內政部消防署全國災情",
            sourceDescription: "火災、車禍、瓦斯與山域事故初報",
            trustLabel: "官方來源",
            expectedUpdateText: "約每 2 分鐘",
            endpoint: URL(string: "https://havencircle.looptw.com/crawler/api/latest.php?dataset=nfa")!,
            delayedAfter: 10 * 60
        ),
        Definition(
            id: "cwa",
            name: "中央氣象署地震報告",
            sourceDescription: "有感與顯著地震報告；依受影響縣市展開生活圈行政區",
            trustLabel: "官方來源",
            expectedUpdateText: "約每 5 分鐘",
            endpoint: URL(string: "https://havencircle.looptw.com/crawler/api/latest.php?dataset=cwa")!,
            delayedAfter: 15 * 60
        ),
        Definition(
            id: "taichung_fire",
            name: "台中市消防局即時災情",
            sourceDescription: "台中市 119 火災受理資訊，僅顯示行政區概略位置",
            trustLabel: "官方來源",
            expectedUpdateText: "約每 2 分鐘",
            endpoint: URL(string: "https://havencircle.looptw.com/crawler/api/latest.php?dataset=taichung_fire")!,
            delayedAfter: 10 * 60
        ),
        Definition(
            id: "news",
            name: "新聞事故線索",
            sourceDescription: "多家媒體 RSS／公開即時頁，經規則與 AI 分類",
            trustLabel: "未驗證；多來源一致時會明確標示",
            expectedUpdateText: "約每 15 分鐘",
            endpoint: URL(string: "https://havencircle.looptw.com/crawler/api/latest.php?dataset=news")!,
            delayedAfter: 45 * 60
        ),
        Definition(
            id: "aqi",
            name: "環境部空氣品質監測",
            sourceDescription: "全台 AQI 測站；達警戒門檻才形成提醒",
            trustLabel: "官方來源",
            expectedUpdateText: "每小時",
            endpoint: URL(string: "https://havencircle.looptw.com/crawler/api/latest.php?dataset=aqi")!,
            delayedAfter: 2 * 3_600
        ),
        Definition(
            id: "crime",
            name: "警政署治安統計",
            sourceDescription: "行政區治安統計圖層，供了解趨勢，不是即時案件通報",
            trustLabel: "官方統計來源",
            expectedUpdateText: "依政府資料發布週期",
            endpoint: URL(string: "https://havencircle.looptw.com/crawler/api/latest.php?dataset=crime")!,
            delayedAfter: 45 * 24 * 3_600
        ),
    ]

    static func fetchAll() async -> [AlertSourceStatus] {
        await withTaskGroup(of: (Int, AlertSourceStatus).self) { group in
            for (index, definition) in definitions.enumerated() {
                group.addTask {
                    (index, await fetch(definition))
                }
            }
            var results: [(Int, AlertSourceStatus)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func fetch(_ definition: Definition) async -> AlertSourceStatus {
        do {
            var request = URLRequest(url: definition.endpoint)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NCDRProviderError.badResponse
            }

            let payload = root["data"] as? [String: Any]
            let rawDate = (root["received_at"] as? String)
                ?? (payload?["fetchedAt"] as? String)
                ?? (payload?["fetched_at"] as? String)
            let updatedAt = rawDate.flatMap(parseDate)
            var count = (root["count"] as? NSNumber)?.intValue
            let age = updatedAt.map { Date.now.timeIntervalSince($0) }
            var health: AlertSourceStatus.Health =
                age.map { $0 <= definition.delayedAfter ? .healthy : .delayed } ?? .delayed

            var detail: String?
            if definition.id == "nfa", let rows = payload?["events"] as? [[String: Any]] {
                let active = rows.filter { (($0["isResolved"] as? Bool) ?? true) == false }
                count = active.count
                detail = "本批 \(rows.count) 筆，App 目前只保留 \(active.count) 筆未結束案件。"
            } else if definition.id == "taichung_fire", let rows = payload?["events"] as? [[String: Any]] {
                let active = rows.filter { row in
                    let status = (row["status"] as? String) ?? ""
                    return !status.contains("返隊") && !status.contains("結束") && !status.contains("解除")
                }
                count = active.count
                detail = "本批 \(rows.count) 筆，App 目前顯示 \(active.count) 筆未結束案件。"
            } else if definition.id == "cwa", let datasets = payload?["datasets"] as? [String: Any] {
                let local = (datasets["localQuakes"] as? [String: Any])?["Earthquake"] as? [[String: Any]] ?? []
                let significant = (datasets["significantQuakes"] as? [String: Any])?["Earthquake"] as? [[String: Any]] ?? []
                let numbers = Set((local + significant).compactMap { $0["EarthquakeNo"] as? Int })
                count = numbers.count
                detail = "近期地震報告 \(numbers.count) 筆；App 只會對剛發生且受影響行政區的地震形成警報。"
            } else if definition.id == "aqi", let rows = payload?["stations"] as? [[String: Any]] {
                let alerted = rows.filter { (($0["aqi"] as? NSNumber)?.intValue ?? 0) >= 150 }
                detail = "目前監測 \(rows.count) 站，\(alerted.count) 站達提醒門檻。"
            } else if definition.id == "crime" {
                detail = "這是統計參考圖層，不會發送即時警報。"
            }
            if definition.id == "news",
               let sourceRows = payload?["sources"] as? [[String: Any]] {
                let activeNames = sourceRows.compactMap { row -> String? in
                    guard (row["ok"] as? Bool) == true else { return nil }
                    return row["name"] as? String
                }
                var seenNames = Set<String>()
                let names = activeNames.filter { seenNames.insert($0).inserted }
                let failedNames = sourceRows.compactMap { row -> String? in
                    guard (row["ok"] as? Bool) != true else { return nil }
                    return row["name"] as? String
                }
                var parts: [String] = []
                if names.isEmpty {
                    health = .unavailable
                    parts.append("本輪沒有可用的新聞來源")
                } else {
                    parts.append("目前接入：\(names.joined(separator: "、"))")
                }
                if !failedNames.isEmpty {
                    parts.append("抓取失敗：\(failedNames.joined(separator: "、"))")
                }
                if let pipeline = payload?["pipelineHealth"] as? [String: Any],
                   (pipeline["llmCircuitOpen"] as? Bool) == true {
                    let pending = (pipeline["pendingLLMRetry"] as? NSNumber)?.intValue ?? 0
                    parts.append("AI 分類暫時降級，\(pending) 則等待重試")
                }
                detail = parts.joined(separator: "；")
            }

            return AlertSourceStatus(
                id: definition.id,
                name: definition.name,
                sourceDescription: definition.sourceDescription,
                trustLabel: definition.trustLabel,
                expectedUpdateText: definition.expectedUpdateText,
                updatedAt: updatedAt,
                itemCount: count,
                health: health,
                detail: detail
            )
        } catch {
            return AlertSourceStatus(
                id: definition.id,
                name: definition.name,
                sourceDescription: definition.sourceDescription,
                trustLabel: definition.trustLabel,
                expectedUpdateText: definition.expectedUpdateText,
                updatedAt: nil,
                itemCount: nil,
                health: .unavailable,
                detail: "無法讀取來源狀態，App 會保留上次已取得的事件。"
            )
        }
    }

    private static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
