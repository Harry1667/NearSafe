import SwiftUI
import CloudKit
import CoreImage.CIFilterBuiltins
import UIKit

/// 邀請方式選單：QR code（相機掃了就能加入）、8 位邀請碼（用唸的也行）、系統分享面板。
/// 三種方式底層都是同一條 CKShare 連結，只是遞送手段不同。
struct InviteOptionsView: View {
    let share: CKShare
    let container: CKContainer

    @Environment(\.dismiss) private var dismiss
    @State private var showSystemShare = false
    @State private var inviteCode: String?
    @State private var codeError: String?
    @State private var isGeneratingCode = false

    var body: some View {
        NavigationStack {
            List {
                if let url = share.url {
                    qrSection(url: url)
                    codeSection(url: url)
                } else {
                    // 理論上 makeShare 存檔成功後一定有 url；保留降級路徑不讓畫面開天窗
                    Section {
                        Label("分享連結尚未就緒，請改用下方系統分享", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(HCColor.attention)
                    }
                }
                Section {
                    Button("用訊息或 AirDrop 邀請", systemImage: "square.and.arrow.up") {
                        showSystemShare = true
                    }
                }
            }
            .navigationTitle("邀請家人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("完成") { dismiss() }
            }
            .sheet(isPresented: $showSystemShare) {
                CloudSharingSheet(share: share, container: container)
            }
        }
    }

    private func qrSection(url: URL) -> some View {
        Section("掃 QR code 加入") {
            HStack {
                Spacer()
                if let image = Self.qrImage(for: url.absoluteString) {
                    Image(uiImage: image)
                        .interpolation(.none) // QR 要銳利邊緣，禁用平滑縮放
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .accessibilityLabel("家庭圈邀請 QR code")
                } else {
                    Label("QR code 產生失敗", systemImage: "xmark.circle")
                        .foregroundStyle(HCColor.danger)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            Text("請家人用 iPhone 相機掃描，點開連結即可加入。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func codeSection(url: URL) -> some View {
        Section("或用 8 位邀請碼") {
            if let inviteCode {
                HStack {
                    Text(inviteCode)
                        .font(.system(.title, design: .monospaced).bold())
                        .kerning(3)
                    Spacer()
                    Button("拷貝", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = inviteCode
                    }
                    .labelStyle(.iconOnly)
                }
                Text("家人在「家人」分頁點「用邀請碼加入」輸入即可，72 小時內有效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await generateCode(url: url) }
                } label: {
                    HStack {
                        Label("產生邀請碼", systemImage: "textformat.123")
                        if isGeneratingCode {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isGeneratingCode)
                if let codeError {
                    Text(codeError)
                        .font(.caption)
                        .foregroundStyle(HCColor.danger)
                }
            }
        }
    }

    private func generateCode(url: URL) async {
        isGeneratingCode = true
        codeError = nil
        defer { isGeneratingCode = false }
        do {
            inviteCode = try await JoinCodeService.createCode(for: url)
        } catch {
            codeError = error.localizedDescription
        }
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
