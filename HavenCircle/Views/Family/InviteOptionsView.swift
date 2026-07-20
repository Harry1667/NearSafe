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
                if let image = Self.qrImage(for: code) {
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
            Text("讓家人用相機掃描，讀到的就是這組邀請碼。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func shareText(code: String) -> String {
        "加入我的安心圈家庭，邀請碼：\(code)。下載 App 後在「家人」分頁輸入即可互相回報平安。"
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
