import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// RawDecodePanelView (Plan M2-3-3 T4, KD-4/D2) — the RAW Decode tab's CIRAW
// parameter panel: the NR slider family (amount / luminance / chroma /
// sharpness), the decoder-version choice (default/v8/v9 — the Alcedo
//「demosaic」entry's CIRAW reality), the boost slider, the typed v9
// downgrade hint and the identity Reset.
//
// REQUEST CHAIN (checker E2): a slider edit writes the session overrides
// through the WorkspaceModel carrier and re-issues `EditorState.load` (the
// ONE decode request chain) — the readback lands in `RAWTechnicalParams`,
// the HistoryHash folds drift the pipe cache key, the PREVIEW re-renders.
// Session-scoped by contract (a closed editor drops the map); sidecar
// persistence = M2-4.
// ─────────────────────────────────────────────────────────────────────────────

struct RawDecodePanelView: View {

    let workspace: WorkspaceModel
    let decoder: RAWDecoder
    let metalContext: MetalContext?

    @Environment(EditorState.self) private var editorState

    /// The panel's local edit face (re-seeded per image from the session
    /// carrier; committed on every change).
    @State private var noiseAmount: Double?
    @State private var luminance: Double?
    @State private var chroma: Double?
    @State private var sharpness: Double?
    @State private var boost: Double?
    @State private var versionRequest: RAWTechnicalOverrides.DecoderRequest = .automatic

    /// True while a re-decode is in flight (the busy caption).
    @State private var isReloading = false

    var body: some View {
        Form {
            Section(String(localized: "rawdecode_nr_section", defaultValue: "Noise reduction")) {
                sliderRow(
                    label: String(localized: "rawdecode_nr_amount", defaultValue: "Amount"),
                    value: $noiseAmount, marker: "editor.rawdecode.nr.amount")
                sliderRow(
                    label: String(localized: "rawdecode_nr_luminance", defaultValue: "Luminance"),
                    value: $luminance, marker: "editor.rawdecode.nr.luminance")
                sliderRow(
                    label: String(localized: "rawdecode_nr_chroma", defaultValue: "Chroma"),
                    value: $chroma, marker: "editor.rawdecode.nr.chroma")
                sliderRow(
                    label: String(localized: "rawdecode_nr_sharpness", defaultValue: "Sharpness"),
                    value: $sharpness, marker: "editor.rawdecode.nr.sharpness")
            }

            Section(String(localized: "rawdecode_decoder_section", defaultValue: "Decoder")) {
                Picker(
                    String(localized: "rawdecode_decoder_version", defaultValue: "Version"),
                    selection: $versionRequest
                ) {
                    Text(String(localized: "rawdecode_decoder_auto", defaultValue: "Default"))
                        .tag(RAWTechnicalOverrides.DecoderRequest.automatic)
                    Text("RAW 8")
                        .tag(RAWTechnicalOverrides.DecoderRequest.forceV8)
                    Text("RAW 9")
                        .tag(RAWTechnicalOverrides.DecoderRequest.forceV9)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("editor.rawdecode.decoder.version")
                if showsV9DowngradeHint {
                    Label(String(
                        localized: "rawdecode_v9_unsupported",
                        defaultValue: "This camera's RAW 9 is unavailable — running RAW 8"),
                        systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(ThemeTokens.textSecondary)
                        .accessibilityIdentifier("editor.rawdecode.v9.hint")
                }
            }

            Section(String(localized: "rawdecode_boost_section", defaultValue: "Boost")) {
                sliderRow(
                    label: String(localized: "rawdecode_boost", defaultValue: "Boost"),
                    value: $boost, marker: "editor.rawdecode.boost")
            }

            Section {
                Button(String(localized: "rawdecode_reset", defaultValue: "Reset")) {
                    noiseAmount = nil
                    luminance = nil
                    chroma = nil
                    sharpness = nil
                    boost = nil
                    versionRequest = .automatic
                    commit()
                }
                .accessibilityIdentifier("editor.rawdecode.reset")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.rawdecode")
        // Re-seed per image (the session carrier is the truth).
        .task(id: editorState.loadedImageURL) { reseed() }
    }

    // MARK: - Rows

    private func sliderRow(
        label: String, value: Binding<Double?>, marker: String
    ) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(ThemeTokens.textPrimary)
            Spacer()
            if value.wrappedValue == nil {
                Text(String(localized: "rawdecode_default", defaultValue: "Default"))
                    .font(.caption)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .frame(minWidth: 44)
                    .accessibilityIdentifier("\(marker).default")
            } else {
                Text("\(value.wrappedValue!, specifier: "%.2f")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .frame(minWidth: 44)
            }
            Slider(
                value: Binding(
                    get: { value.wrappedValue ?? 0 },
                    set: { newValue in
                        value.wrappedValue = newValue
                        commit()
                    }),
                in: 0...1
            )
            .frame(maxWidth: 200)
            .accessibilityIdentifier(marker)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - The request chain

    private var currentOverrides: RAWTechnicalOverrides {
        RAWTechnicalOverrides(
            noiseReductionAmount: noiseAmount,
            luminanceNoiseReduction: luminance,
            colorNoiseReduction: chroma,
            sharpness: sharpness,
            boost: boost,
            decoderVersion: versionRequest)
    }

    /// Write the session carrier + re-issue the decode request (the E2
    /// chain: overrides → load → RAWDecoder → readback → cache-key drift →
    /// PREVIEW re-render).
    private func commit() {
        guard let url = editorState.loadedImageURL else { return }
        let overrides = currentOverrides
        workspace.setRawDecodeOverrides(overrides, for: url)
        isReloading = true
        editorState.load(
            url: url,
            decoder: decoder,
            metal: metalContext,
            logger: EditorState.decodeLogger,
            overrides: overrides)
        isReloading = false
    }

    /// Seed from the session carrier for the CURRENT image.
    private func reseed() {
        guard let url = editorState.loadedImageURL else { return }
        let overrides = workspace.rawDecodeOverrides(for: url)
        noiseAmount = overrides.noiseReductionAmount
        luminance = overrides.luminanceNoiseReduction
        chroma = overrides.colorNoiseReduction
        sharpness = overrides.sharpness
        boost = overrides.boost
        versionRequest = overrides.decoderVersion
    }

    /// The typed downgrade hint: the user forced v9 but the readback used
    /// v8 (the camera/file lacks RAW 9 support — the DecodedImage records
    /// the actually-used version).
    private var showsV9DowngradeHint: Bool {
        versionRequest == .forceV9
            && editorState.image?.decoderVersionUsed == .v8
            && editorState.loadedImageURL != nil
    }
}
