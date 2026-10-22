import CoreGraphics
import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// EnhanceDialog (Plan M2-10-06 T3c, KD-5) — the AI enhancement dialog:
// the central before/after preview, the operation/model choice (upscale:
// the bundled fast tier + the release quality tier; denoise: DRUNet +
// strength), the release-model download row (the M2-10-01 store's status
// machine), the tile progress, and the close-after cancel semantics (the
// Lumen ai_dialog.py:177-185 paradigm — a busy close cancels at the next
// tile checkpoint and closes when the run settles; never a hard kill).
//
// THE MODEL OWNS EVERYTHING — this view is a thin projection (the panel
// precedent). The entry wiring (grid right-click / editor menu) and the
// production seams (frame provider / worker closures) land with
// M2-10-07; the dialog is presentable now.
// ─────────────────────────────────────────────────────────────────────────────

struct EnhanceDialog: View {
    @State private var model: EnhanceDialogModel
    @Environment(\.dismiss) private var dismiss

    private let upscaleChoices: [(label: String, profileID: String)] = [
        ("快速 · realesr-general-x4v3（内置）",
         ModelAssetCatalog.realesrGeneralX4V3FP16.profileID),
        ("高画质 · Real-ESRGAN x4plus（下载）",
         ModelAssetCatalog.realESRGANX4PlusFP16.profileID),
    ]
    private let denoiseChoices: [(label: String, profileID: String)] = [
        ("高画质 · DRUNet 细节保留（下载）",
         ModelAssetCatalog.drunetColorFP16.profileID),
    ]

    init(model: EnhanceDialogModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            Text("左：处理前细节 / 右：AI 处理后的细节（中央 192×192 原像素）")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                previewPane(model.beforePreview, placeholder: "原始细节")
                previewPane(model.afterPreview, placeholder: "处理后细节")
            }
            .frame(height: 200)

            controls

            modelStatusRow

            progressArea

            HStack {
                Button(model.isBusy ? "取消运算" : "关闭") {
                    model.closeRequested()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("预览中央细节") {
                    Task { await model.runPreview() }
                }
                .disabled(model.isBusy || !model.selectedModelReady)
                Button("生成增强副本", action: { Task { await model.runFullCopy() } })
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isBusy || !model.selectedModelReady)
            }
        }
        .padding(18)
        .frame(width: 480)
        .task { await model.refreshModelStatus() }
        .onChange(of: model.shouldClose) { _, shouldClose in
            if shouldClose { dismiss() }
        }
    }

    private var title: String {
        switch model.choice {
        case .upscale: return "AI 超分辨率 / SUPER RESOLUTION"
        case .denoise: return "AI 去杂色 / DENOISE"
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch model.choice {
        case .upscale:
            Picker("算法", selection: profileBinding) {
                ForEach(
                    upscaleChoices, id: \.profileID
                ) { choice in
                    Text(choice.label).tag(choice.profileID)
                }
            }
            Text("副本尺寸为原图 4×（像素数 16 倍）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .denoise(_, let strength):
            Picker("算法", selection: profileBinding) {
                ForEach(
                    denoiseChoices, id: \.profileID
                ) { choice in
                    Text(choice.label).tag(choice.profileID)
                }
            }
            HStack {
                Text("去杂色强度 \(Int(strength))")
                Slider(
                    value: strengthBinding, in: 0...100, step: 1)
            }
            Text("35 为噪声基准；强度为模型输出与原图的混合比例。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var profileBinding: Binding<String> {
        Binding(
            get: { model.choice.profileID },
            set: { newValue in
                switch model.choice {
                case .upscale:
                    model.choice = .upscale(profileID: newValue)
                case .denoise(_, let strength):
                    model.choice = .denoise(profileID: newValue, strength: strength)
                }
                Task { await model.refreshModelStatus() }
            })
    }

    private var strengthBinding: Binding<Double> {
        Binding(
            get: {
                if case .denoise(_, let strength) = model.choice { return strength }
                return 35
            },
            set: { newValue in
                if case .denoise(let profileID, _) = model.choice {
                    model.choice = .denoise(profileID: profileID, strength: newValue)
                }
            })
    }

    @ViewBuilder
    private var modelStatusRow: some View {
        switch model.modelStatuses[model.choice.profileID] {
        case .bundled, .installed, nil:
            EmptyView()
        case .notInstalled:
            HStack {
                Text("该模型需要下载（约 33–65 MB）。").font(.caption)
                Spacer()
                Button("下载并启用") {
                    Task { await model.downloadSelectedModel() }
                }
                .disabled(model.isBusy)
            }
        case .downloading(let fraction):
            ProgressView(value: fraction) {
                Text("下载中 \(Int(fraction * 100))%").font(.caption)
            }
        case .corrupt:
            HStack {
                Text("已安装文件损坏，重新下载可自愈。").font(.caption)
                Spacer()
                Button("重新下载") {
                    Task { await model.downloadSelectedModel() }
                }
            }
        case .digestUnpublished:
            Text("该模型尚未发布（待上架）。").font(.caption)
        }
    }

    @ViewBuilder
    private var progressArea: some View {
        switch model.phase {
        case .running(let percent):
            ProgressView(value: Double(percent), total: 100) {
                Text(statusText).font(.caption)
            }
        case .previewRunning:
            ProgressView(value: 5, total: 100) {
                Text(statusText).font(.caption)
            }
        case .done(let name):
            Label("已生成副本 \(name)，已插入项目网格。", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        case .cancelled:
            Label("已取消，未生成副本。", systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .idle, .previewReady:
            Text("先预览中央 192×192 原像素，再生成完整副本。原图零触碰。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch model.phase {
        case .previewRunning: return "正在计算预览…"
        case .running(let percent):
            return percent <= 15
                ? "正在读取全尺寸原片…"
                : "正在计算 · 分块进度 \(percent)%"
        default: return ""
        }
    }

    private func previewPane(
        _ frame: EnhanceFrame?, placeholder: String
    ) -> some View {
        VStack {
            if let frame, let image = Self.displayImage(frame) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 170)
            } else {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: 170)
                    .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    /// The frame → NSImage display face (the uint16 encode path keeps the
    /// preview honest — what you see is what the copy carries).
    static func displayImage(_ frame: EnhanceFrame) -> NSImage? {
        var pixels = [UInt16](repeating: 0, count: frame.width * frame.height * 4)
        for index in 0..<(frame.width * frame.height) {
            for channel in 0..<4 {
                let value = min(max(frame.rgba[index * 4 + channel], 0), 1)
                pixels[index * 4 + channel] = UInt16(
                    Int((value * 65535.0).rounded()))
            }
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: frame.width, height: frame.height,
                bitsPerComponent: 16, bitsPerPixel: 64,
                bytesPerRow: frame.width * 8,
                space: CGColorSpace(name: CGColorSpace.displayP3)!,
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGBitmapInfo.byteOrder16Little.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true,
                intent: .defaultIntent)
        else { return nil }
        let nsImage = NSImage(
            cgImage: image, size: NSSize(width: frame.width, height: frame.height))
        return nsImage
    }
}
