import SwiftUI
import SwiftData

/// 家人分頁：生活圈管理與安否回報合併在同一個介面，用分段控制切換
struct FamilyHubView: View {
    let myName: String
    @State private var mode: Mode = .circles

    enum Mode: String, CaseIterable {
        case circles = "生活圈"
        case checkIn = "安否回報"
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .circles:
                    FamilyListView(onInvite: { mode = .checkIn })
                case .checkIn:
                    SafetyCheckInView(myName: myName)
                }
            }
            .navigationTitle("家人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("顯示內容", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
        }
    }
}

#Preview {
    FamilyHubView(myName: "我")
        .modelContainer(PreviewSupport.container())
        .environment(FamilySyncService())
}
