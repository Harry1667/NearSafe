import Foundation
import SwiftData
import os

/// 集中管理的 Logger：錯誤一律明確記錄，不做 silent fail
enum AppLog {
    private static let subsystem = "com.gomiigo.CamMenuApp.HavenCircle"
    static let data = Logger(subsystem: subsystem, category: "data")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    static let cloud = Logger(subsystem: subsystem, category: "cloud")
}

extension ModelContext {
    /// 儲存並記錄失敗原因（取代散落各處的 try? save()）
    func saveReporting() {
        do {
            try save()
        } catch {
            AppLog.data.error("SwiftData 儲存失敗：\(error.localizedDescription)")
        }
    }
}
