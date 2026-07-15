#if DEBUG
import SwiftData

/// 僅供 Xcode Preview 使用的記憶體資料庫；正式程式碼不可用 try!
@MainActor
enum PreviewSupport {
    static func container() -> ModelContainer {
        // swiftlint:disable:next force_try — Preview 專用，失敗直接讓 Preview 掛掉即可
        try! ModelContainer(
            for: LocalSafetyEvent.self, LocalFamilyMember.self, LocalLifeCircle.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
#endif
