import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

/// 邀請方式：顯示家庭圈的 8 碼邀請碼——可唸、可抄、可拷貝、可掃 QR、可用系統分享。
/// 家人在「用邀請碼加入家庭圈」輸入這組碼即可加入，跨 iCloud 帳號都適用。
struct InviteOptionsView: View {
    @Environment(FamilySyncService.self) private var sync
    @Environment(\.dismiss) private var dismiss

    private var inviteCode: String? { sync.currentInviteCode }

    var body: some View {
        NavigationStack {
            List {
                if let code = inviteCode {
                    codeSection(code: code)
                    qrSection(code: code)
                    Section {
                        ShareLink(item: shareText(code: code)) {
                            Label("用訊息或 AirDrop 分享邀請碼", systemImage: "square.and.arrow.up")
                        }
                    }
                } else {
                    Section {
                        HStack {
                            ProgressView()
                            Text("正在建立家庭圈邀請碼⋯")
                        }
                    }
                }
            }
            .navigationTitle("邀請家人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("完成") { dismiss() }
            }
            .analyticsScreen("invite_options")
        }
    }

    private func codeSection(code: String) -> some View {
        Section("你的家庭邀請碼") {
            HStack {
                Text(code)
                    .font(.system(.largeTitle, design: .monospaced).bold())
                    .kerning(4)
                Spacer()
                Button("拷貝", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = code
                }
                .labelStyle(.iconOnly)
            }
            Text("家人在「家人」分頁點「用邀請碼加入家庭圈」輸入這組碼即可加入。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func qrSection(code: String) -> some View {
        Section("或掃 QR code") {
            HStack {
                Spacer()
                if let image = Self.qrImage(for: joinURL(code: code)) {
                    Image(uiImage: image)
                        .interpolation(.none) // QR 要銳利邊緣，禁用平滑縮放
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .accessibilityLabel("家庭圈邀請碼 QR code")
                } else {
                    Label("QR code 產生失敗", systemImage: "xmark.circle")
                        .foregroundStyle(HCColor.danger)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            Text("已裝 App 的家人直接用相機掃描即可跳轉加入；沒裝的人掃到會看到下載連結。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// B1：QR 內容改編碼成 deep link（取代純文字碼），讓「掃碼」跟「輸碼」不再是兩套體驗——
    /// 已裝 App 時系統相機辨識出 havencircle:// 就能直接跳轉到加入流程（AppTabs.route）。
    private func joinURL(code: String) -> String {
        "havencircle://join?code=\(code)"
    }

    private func shareText(code: String) -> String {
        "來加入我們的安心圈，災害來的時候互相知道平安。邀請碼：\(code)。" +
        "已裝 App 的話，用相機掃我畫面上的 QR code 就能直接加入；" +
        "或在 App 的「家人」分頁點「我收到了邀請碼」輸入。"
    }

    /// 用 CoreImage 產生 QR code（放大 12 倍再轉點陣，避免模糊）
    private static func qrImage(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
