import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// DrtPanelView (Plan M2-6-3 T2, KD-2 / M2DRT-01) — the Display Transform
// page's live panel, replacing the M2-3 honest-shell placeholder. The
// structure is FEATURE-MAP §5 line-for-line: the Method segmented card
// ALWAYS expanded on top; Color & Encoding (disclosure, expanded by
// default); the ACES 2.0 limiting group (`.aces20` only); the OpenDRT preset
// trio (`.opendrt` only). The Vignette row below stays exactly where it was
// (the checker E1 errata boundary — untouched by this plan).
//
// Technical proper nouns (method/preset/space/EOTF names) are keyed with the
// zh value = the English original (OQ-12-A 不译清单).
//
// AR-01 T3 (audit M5): the four former `private var` sections are now their
// own View structs (DrtMethodCard / DrtEncodingGroup / DrtLimitingGroup /
// DrtPresetGroup — each holds the model class reference and reads narrowly),
// and the former `State(initialValue:)` init became the house onAppear
// lazy-build form (the FilmPanelView shape — the ancestor body no longer
// allocates a throwaway model per evaluation; m11). The `encodingExpanded`
// disclosure @State moved with its group into DrtEncodingGroup. Behavior
// preserving: every binding is a line-for-line translation (the D-H1 peak
// trio's live tick → setDrtLive / drag end → commitDrtEdit untouched).
// ─────────────────────────────────────────────────────────────────────────────

internal struct DrtPanelView: View {

    private let workspace: WorkspaceModel
    private let editorState: EditorState
    private let pipeCoordinator: PipeCoordinator

    @State private var model: DrtPanelModel?

    init(
        workspace: WorkspaceModel, editorState: EditorState,
        pipeCoordinator: PipeCoordinator
    ) {
        self.workspace = workspace
        self.editorState = editorState
        self.pipeCoordinator = pipeCoordinator
    }

    var body: some View {
        Group {
            if let model {
                panelBody(model: model)
            } else {
                EmptyView()
            }
        }
        .accessibilityIdentifier("editor.stack.drt.panel")
        // The house lazy-build form (the FilmPanelView onAppear shape): the
        // ancestor body no longer allocates a throwaway model per evaluation
        // (m11); the build is one async execution after appear.
        .onAppear { model = DrtPanelModel(
            workspace: workspace, editorState: editorState,
            pipeCoordinator: pipeCoordinator) }
    }

    private func panelBody(model: DrtPanelModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.sections.enumerated()), id: \.element.kind) { _, section in
                switch section.kind {
                case .method:
                    DrtMethodCard(model: model)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                case .colorEncoding:
                    DrtEncodingGroup(model: model)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                case .acesLimiting:
                    DrtLimitingGroup(model: model)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                case .opendrtPresets:
                    DrtPresetGroup(model: model)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Display names (technical proper nouns: zh = the English form)

    static func spaceName(_ space: DrtEncodingSpace) -> String {
        switch space {
        case .rec709: String(localized: "drt_space_rec709", defaultValue: "Rec.709")
        case .p3d65: String(localized: "drt_space_p3d65", defaultValue: "P3-D65")
        case .p3d60: String(localized: "drt_space_p3d60", defaultValue: "P3-D60")
        case .p3dci: String(localized: "drt_space_p3dci", defaultValue: "P3-DCI")
        case .xyz: String(localized: "drt_space_xyz", defaultValue: "XYZ")
        case .rec2020: String(localized: "drt_space_rec2020", defaultValue: "Rec.2020")
        }
    }

    static func eotfName(_ eotf: DrtEotf) -> String {
        switch eotf {
        case .linear: String(localized: "drt_eotf_linear", defaultValue: "Linear")
        case .st2084: String(localized: "drt_eotf_st2084", defaultValue: "ST 2084 (PQ)")
        case .hlg: String(localized: "drt_eotf_hlg", defaultValue: "HLG")
        case .gamma26: String(localized: "drt_eotf_gamma26", defaultValue: "Gamma 2.6")
        case .bt1886: String(localized: "drt_eotf_bt1886", defaultValue: "BT.1886")
        case .gamma22: String(localized: "drt_eotf_gamma22", defaultValue: "Gamma 2.2")
        case .gamma18: String(localized: "drt_eotf_gamma18", defaultValue: "Gamma 1.8")
        case .srgbPiecewise: String(localized: "drt_eotf_srgb_piecewise", defaultValue: "sRGB")
        }
    }

    static func limitingName(_ space: DrtLimitingSpace) -> String {
        switch space {
        case .rec709: String(localized: "drt_space_rec709", defaultValue: "Rec.709")
        case .rec2020: String(localized: "drt_space_rec2020", defaultValue: "Rec.2020")
        case .p3d65: String(localized: "drt_space_p3d65", defaultValue: "P3-D65")
        case .p3d60: String(localized: "drt_space_p3d60", defaultValue: "P3-D60")
        case .p3dci: String(localized: "drt_space_p3dci", defaultValue: "P3-DCI")
        case .proPhoto: String(localized: "drt_space_prophoto", defaultValue: "ProPhoto RGB")
        case .adobeRGB: String(localized: "drt_space_adobe", defaultValue: "Adobe RGB")
        }
    }

    /// Preset display names — the dctl spellings are the technical proper
    /// nouns (use_look_preset → "Use Look Preset" is the one human phrase).
    static func presetName(_ raw: String) -> String {
        switch raw {
        case "use_look_preset":
            String(localized: "drt_preset_use_look", defaultValue: "Use Look Preset")
        case "low_contrast":
            String(localized: "drt_preset_low_contrast", defaultValue: "Low Contrast")
        case "medium_contrast":
            String(localized: "drt_preset_medium_contrast", defaultValue: "Medium Contrast")
        case "high_contrast":
            String(localized: "drt_preset_high_contrast", defaultValue: "High Contrast")
        case "aces_1_x":
            String(localized: "drt_preset_aces1x", defaultValue: "ACES 1.x")
        case "aces_2_0":
            String(localized: "drt_preset_aces20", defaultValue: "ACES 2.0")
        case "marvelous_tonscape":
            String(localized: "drt_preset_marvelous", defaultValue: "Marvelous Tonscape")
        case "dagrinchi_tonegroan":
            String(localized: "drt_preset_dagrinchi", defaultValue: "Dagrinchi Tonegroan")
        case "d93", "d75", "d65", "d60", "d55", "d50":
            raw.uppercased()
        default:
            raw.capitalized
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The four section structs (AR-01 T3 / audit M5) — the FEATURE-MAP §5 rows as
// independent invalidation boundaries, plus the shared row shell.
// ─────────────────────────────────────────────────────────────────────────────

/// The Method segmented card (the always-expanded section).
private struct DrtMethodCard: View {

    let model: DrtPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "drt_section_method", defaultValue: "Method"))
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
            Picker(
                String(localized: "drt_section_method", defaultValue: "Method"),
                selection: Binding(
                    get: { model.record.method },
                    set: { model.setMethod($0) }
                )
            ) {
                Text(String(localized: "drt_method_ac", defaultValue: "ACES 2.0"))
                    .tag(DrtMethod.aces20)
                Text(String(localized: "drt_method_opendrt", defaultValue: "OpenDRT"))
                    .tag(DrtMethod.opendrt)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("drt.method.picker")
        }
    }
}

/// Color & Encoding (the disclosure section, expanded by default KD-2):
/// the six-space menu, the EOTF picker (the Core legal subset) and the Peak
/// slider (the D-H1 trio). The disclosure @State lives HERE, with its group.
private struct DrtEncodingGroup: View {

    let model: DrtPanelModel
    /// The Color & Encoding disclosure state (expanded by default, KD-2).
    @State private var encodingExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $encodingExpanded) {
            row(String(localized: "drt_label_encoding_space", defaultValue: "Encoding Space")) {
                Picker(
                    String(localized: "drt_label_encoding_space", defaultValue: "Encoding Space"),
                    selection: Binding(
                        get: { model.record.encodingSpace },
                        set: { model.setEncodingSpace($0) }
                    )
                ) {
                    ForEach(DrtEncodingSpace.allCases, id: \.self) { space in
                        Text(DrtPanelView.spaceName(space)).tag(space)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("drt.encoding.space")
            }
            row(String(localized: "drt_label_encoding_eotf", defaultValue: "Encoding EOTF")) {
                Picker(
                    String(localized: "drt_label_encoding_eotf", defaultValue: "Encoding EOTF"),
                    selection: Binding(
                        get: { model.record.encodingEotf },
                        set: { model.setEncodingEotf($0) }
                    )
                ) {
                    // The picker's data source IS the Core legal set — an
                    // illegal combination is unconstructible from the UI
                    // (OQ-5-B; the snap faces live in the model, KD-3).
                    ForEach(model.legalEotfs, id: \.self) { eotf in
                        Text(DrtPanelView.eotfName(eotf)).tag(eotf)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("drt.encoding.eotf")
            }
            peakRow
        } label: {
            Text(String(
                localized: "drt_section_color_encoding",
                defaultValue: "Color & Encoding"))
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
        }
        .accessibilityIdentifier("drt.section.encoding")
    }

    /// Peak Luminance 100–1000, default 100 (FEATURE-MAP §5): the D-H1
    /// trio — live ticks re-render without items, the drag end commits ONCE.
    private var peakRow: some View {
        row(
            String(localized: "drt_label_peak", defaultValue: "Peak Luminance")
        ) {
            HStack {
                Slider(
                    value: Binding(
                        get: { model.record.peakLuminance },
                        set: { model.setPeakLive($0) }
                    ),
                    in: DrtPanelModel.peakRange
                ) { editing in
                    if editing {
                        model.beginPeakDrag()
                    } else {
                        model.commitPeak()
                    }
                }
                .accessibilityIdentifier("drt.peak.slider")
                Text(verbatim: "\(Int(model.record.peakLuminance)) nits")
                    .font(.caption2)
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }

    private func row(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
                .frame(width: 110, alignment: .leading)
            content()
        }
        .padding(.vertical, 2)
    }
}

/// The ACES 2.0 limiting group (method == aces20 only).
private struct DrtLimitingGroup: View {

    let model: DrtPanelModel

    var body: some View {
        row(String(localized: "drt_label_limiting_space", defaultValue: "Limiting Space")) {
            Picker(
                String(localized: "drt_label_limiting_space", defaultValue: "Limiting Space"),
                selection: Binding(
                    get: { model.record.limitingSpace },
                    set: { model.setLimiting($0) }
                )
            ) {
                ForEach(DrtLimitingSpace.allCases, id: \.self) { space in
                    Text(DrtPanelView.limitingName(space)).tag(space)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("drt.aces.limiting")
        }
    }

    private func row(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
                .frame(width: 110, alignment: .leading)
            content()
        }
        .padding(.vertical, 2)
    }
}

/// The OpenDRT preset trio (method == opendrt only).
private struct DrtPresetGroup: View {

    let model: DrtPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(String(localized: "drt_label_look", defaultValue: "Look")) {
                Picker(
                    String(localized: "drt_label_look", defaultValue: "Look"),
                    selection: Binding(
                        get: { DrtLookPreset(rawValue: model.record.lookPreset) ?? .standard },
                        set: { model.applyLook($0) }
                    )
                ) {
                    ForEach(DrtLookPreset.allCases, id: \.self) { look in
                        Text(DrtPanelView.presetName(look.rawValue)).tag(look)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("drt.preset.look")
            }
            if model.isCustomLook {
                Text(String(localized: "drt_look_custom", defaultValue: "Custom"))
                    .font(.caption2)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .padding(.horizontal, 10)
                    .accessibilityIdentifier("drt.preset.custom")
            }
            row(String(localized: "drt_label_tonescale", defaultValue: "Tonescale")) {
                Picker(
                    String(localized: "drt_label_tonescale", defaultValue: "Tonescale"),
                    selection: Binding(
                        get: {
                            DrtTonescalePreset(rawValue: model.record.tonescalePreset)
                                ?? .useLookPreset
                        },
                        set: { model.applyTonescale($0) }
                    )
                ) {
                    ForEach(DrtTonescalePreset.allCases, id: \.self) { ts in
                        Text(DrtPanelView.presetName(ts.rawValue)).tag(ts)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("drt.preset.tonescale")
            }
            row(String(localized: "drt_label_creative_white", defaultValue: "Creative White")) {
                Picker(
                    String(localized: "drt_label_creative_white", defaultValue: "Creative White"),
                    selection: Binding(
                        get: {
                            DrtCreativeWhite(rawValue: model.record.creativeWhite)
                                ?? .useLookPreset
                        },
                        set: { model.applyCreativeWhite($0) }
                    )
                ) {
                    ForEach(DrtCreativeWhite.allCases, id: \.self) { white in
                        Text(DrtPanelView.presetName(white.rawValue)).tag(white)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("drt.preset.white")
            }
        }
    }

    private func row(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(ThemeTokens.textSecondary)
                .frame(width: 110, alignment: .leading)
            content()
        }
        .padding(.vertical, 2)
    }
}
