import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

/// 邀請方式：顯示家庭圈的 8 碼邀請碼——可唸、可抄、可拷貝、可掃 QR、可用系統分享。
/// 家人在「用邀請碼加入家庭圈」輸入這組碼即可加入，跨 iCloud 帳號都適用。
struct InviteOptionsView: View {
    @Environment(FamilySyncService.self) private var sync
    @Environment(\.dismiss) private var dismiss

    /// C3：重新產生進行中狀態；避免重複點擊送出多個請求。
    @State private var isRegenerating = false
    /// C3：重新產生失敗的人話錯誤（不直接丟 error.localizedDescription 給使用者看）。
    @State private var regenerateError: String?

    private var inviteCode: String? { sync.currentInviteCode }

    var body: some View {
        NavigationStack {
            List {
                if let code = inviteCode {
                    codeSection(code: code)
                    expirySection
                    qrSection(code: code)
                    Section {
                        ShareLink(item: shareText(code: code)) {
                            Label("用訊息或 AirDrop 分享邀請碼", systemImage: "square.and.arrow.up")
                                .font(.body.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HCColor.brand)
                        .controlSize(.large)
                    }
                    .listRowBackground(Color.clear)
                    // C5：重新產生只有圈主看得到——非圈主沒有權限刪舊碼（rules 的
                    // isOwner），顯示了按也沒用，反而讓人以為自己能改碼。
                    if sync.isFamilyOwner {
                        regenerateSection
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
            .listSectionSpacing(HCSpacing.x6)
            .navigationTitle("邀請家人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("完成") { dismiss() }
            }
            .analyticsScreen("invite_options")
        }
    }

    /// C4：顯示邀請碼效期；nil（舊碼沒有 expiresAt 欄位，或尚未讀到）一律顯示長期有效文案。
    private var expirySection: some View {
        Section {
            if let expiresAt = sync.currentInviteCodeExpiresAt {
                Label(
                    "效期至\(Self.expiryDateFormatter.string(from: expiresAt))",
                    systemImage: "clock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Label("長期有效（建議重新產生）", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .listRowBackground(Color.clear)
    }

    private var regenerateSection: some View {
        Section {
            if isRegenerating {
                HStack {
                    ProgressView()
                    Text("正在產生新邀請碼⋯")
                }
            } else {
                Button {
                    Task { await regenerate() }
                } label: {
                    Label("重新產生邀請碼", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            if let regenerateError {
                Label(regenerateError, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(HCColor.danger)
                    .padding(HCSpacing.x2)
                    .background(
                        HCColor.danger.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: HCRadius.chip, style: .continuous)
                    )
            }
        } footer: {
            Text("重新產生後，舊邀請碼會立即失效，請把新碼分享給還沒加入的家人。")
        }
    }

    private func regenerate() async {
        isRegenerating = true
        regenerateError = nil
        defer { isRegenerating = false }
        do {
            try await sync.regenerateInviteCode()
        } catch {
            regenerateError = "重新產生邀請碼失敗，請檢查網路後再試一次。"
            AppLog.cloudError("重新產生邀請碼失敗：\(error.localizedDescription)")
        }
    }

    private static let expiryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M 月 d 日"
        formatter.locale = Locale(identifier: "zh_TW")
        return formatter
    }()

    private func codeSection(code: String) -> some View {
        Section("你的家庭邀請碼") {
            VStack(spacing: HCSpacing.x4) {
                Text(code)
                    .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                    .kerning(HCSpacing.x1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                Button {
                    UIPasteboard.general.string = code
                } label: {
                    Label("拷貝邀請碼", systemImage: "doc.on.doc")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, HCSpacing.x4)
            .hcCard()
            Text("家人在「家人」分頁點「用邀請碼加入家庭圈」輸入這組碼即可加入。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(
            EdgeInsets(
                top: HCSpacing.x1,
                leading: HCSpacing.x4,
                bottom: HCSpacing.x1,
                trailing: HCSpacing.x4
            )
        )
        .listRowBackground(Color.clear)
    }

    private func qrSection(code: String) -> some View {
        Section("或掃 QR code") {
            VStack(spacing: HCSpacing.x4) {
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
                Text("已裝 App 的家人直接用相機掃描即可跳轉加入；沒裝的人掃到會看到下載連結。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, HCSpacing.x4)
            .hcCard()
        }
        .listRowInsets(
            EdgeInsets(
                top: HCSpacing.x1,
                leading: HCSpacing.x4,
                bottom: HCSpacing.x1,
                trailing: HCSpacing.x4
            )
        )
        .listRowBackground(Color.clear)
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
