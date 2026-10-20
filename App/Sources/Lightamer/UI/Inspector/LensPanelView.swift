import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Lens panel (Plan 04-04-T3; LENS-01 T5 upgrades §1) — the IOP-GEO-03
// Inspector surface, three sections mirroring the D-G1 three layers:
//
//  ① Embedded status ((a) layer): the mutex judgment readout
//     (params.embeddedGeometry — detected/unknown/notApplicable/nil
//     undetermined) + the REAL match preview (LensfunStore.matchOutcome
//     through the hardened memoized face — no more key-echo stub).
//  ② Manual sliders ((b) layer): distortion k1/k2, TCA R/B, devignette
//     k1/k2/k3 — D-H1 drag trio, exactly ONE commit per gesture.
//  ③ Lensfun match ((c) layer): match actions (Apply/Clear) + first-run
//     download (the profile browser replaces Apply/Clear in LENS-02 T4).
//
// D-H1 wiring: sliders are the drag-begin/tick/end trio (zero history
// during the drag, exactly ONE commit at the end); Apply/Clear/download
// are discrete one-commit edits. Values READ from the instance record.
// ─────────────────────────────────────────────────────────────────────────

/// The §1 readout pure model (LENS-01 T5): maps the params' mutex judgment
/// + the hardened match outcome onto display states + STATIC copy keys.
/// View-only consumption; testable without a store (the outcome is
/// injected). All copy keys are static literals — the interpolated-key
/// localization trap (M2-9 F-2) is banned here.
enum LensPanelReadout: Equatable {
    // The embedded-geometry mutex face.
    case embeddedDetected
    case embeddedUnknown
    case embeddedNotApplicable
    /// nil judgment (pre-batch synthetic constructions) — the neutral
    /// face, never a conclusion.
    case embeddedUndetermined

    // The match-state-machine face.
    case matched(name: String, score: Int)
    case ambiguous
    case noLens
    case noDatabase
    /// No lens EXIF string at all (the panel_no_exif notice face).
    case idle

    /// The static copy key for the state (zh/en via Localizable.xcstrings;
    /// matched renders its name+score beside the label).
    var copyKey: String {
        switch self {
        case .embeddedDetected: return "panel_lens_embedded_detected"
        case .embeddedUnknown: return "panel_lens_embedded_unknown"
        case .embeddedNotApplicable: return "panel_lens_embedded_notapplicable"
        case .embeddedUndetermined: return "panel_lens_embedded_note"
        case .matched: return "panel_lens_match_matched"
        case .ambiguous: return "panel_lens_match_ambiguous"
        case .noLens: return "panel_lens_match_nolens"
        case .noDatabase: return "panel_lens_match_nodatabase"
        case .idle: return "panel_lens_no_exif"
        }
    }

    /// The mutex judgment mapping (X1: the panel reads the params field,
    /// no second seam).
    static func embedded(_ state: EmbeddedGeometryState?) -> LensPanelReadout {
        switch state {
        case .detected: return .embeddedDetected
        case .unknown: return .embeddedUnknown
        case .notApplicable: return .embeddedNotApplicable
        case nil: return .embeddedUndetermined
        }
    }

    /// The match-state mapping (hasData=false → noDatabase BEFORE any
    /// matching; missing lens EXIF → idle; otherwise the hardened
    /// outcome verbatim).
    static func match(
        params: LensModule.Params, hasData: Bool, outcome: LensMatchOutcome?
    ) -> LensPanelReadout {
        guard hasData else { return .noDatabase }
        guard params.lensKey != nil && !(params.lensKey ?? "").isEmpty else { return .idle }
        guard let outcome else { return .noDatabase }
        switch outcome {
        case .matched(let profile, let score):
            let name = profile.maker.isEmpty
                ? profile.model
                : profile.maker + " " + profile.model
            return .matched(name: name, score: score)
        case .ambiguous: return .ambiguous
        case .noLens: return .noLens
        case .missingFocal: return .idle
        }
    }

    /// The full frozen key set (the localization ledger face — the panel
    /// tests pin exactly these; panel_lens_embedded_note and
    /// panel_lens_no_exif are the PRE-EXISTING keys reused for the
    /// undetermined/idle faces, zero historical-key touching).
    static let allCopyKeys: Set<String> = [
        "panel_lens_embedded_detected",
        "panel_lens_embedded_unknown",
        "panel_lens_embedded_notapplicable",
        "panel_lens_embedded_note",
        "panel_lens_match_matched",
        "panel_lens_match_ambiguous",
        "panel_lens_match_nolens",
        "panel_lens_match_nodatabase",
        "panel_lens_no_exif",
    ]
}

internal struct LensPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    @State private var notice: String?
    @State private var embeddedReadout: LensPanelReadout = .embeddedUndetermined
    @State private var matchReadout: LensPanelReadout = .idle
    @State private var hasData: Bool = LensfunStore.isInstalled
    @State private var downloading: Bool = false
    /// LENS-02 T2: the auto-apply toggle state (read ONCE at init through
    /// the injected setting face — body never touches UserDefaults).
    @State private var autoApply: Bool

    private let params: LensModule.Params

    init(instance: ModuleInstance, edit: InspectorEditSession) {
        self.instance = instance
        self.edit = edit
        self.params = PanelEditing.params(of: instance, as: LensModule.self) ?? LensModule.Params()
        _autoApply = State(initialValue: LensAutoApplySetting.read())
    }

    var body: some View {
        Form {
            // ── §1 embedded status + match state machine (LENS-01 T5) ──
            Section {
                HStack {
                    Image(systemName: "circlebadge")
                        .font(.caption2)
                    Text(String(localized: String.LocalizationValue(embeddedReadout.copyKey)))
                        .font(.caption2)
                }
                .foregroundStyle(LightamerColors.textTertiary)
                .accessibilityIdentifier("inspector.lens.embeddedReadout")
                HStack {
                    Text(String(localized: String.LocalizationValue(matchReadout.copyKey)))
                        .font(.caption)
                    if case .matched(let name, let score) = matchReadout {
                        Text(verbatim: "\(name) · \(score)")
                            .font(.caption)
                            .foregroundStyle(LightamerColors.textPrimary)
                    }
                }
                .foregroundStyle(matchReadout == .noDatabase
                    ? LightamerColors.textTertiary : LightamerColors.textPrimary)
                .accessibilityIdentifier("inspector.lens.matchReadout")
            } header: {
                Text("panel_lens_embedded_section")
            }

            // ── §2 manual sliders ──
            Section {
                LightamerSlider(
                    label: String(localized: "panel_lens_distortion_k1"),
                    value: Double(params.distortionK1),
                    range: -0.2...0.2,
                    defaultValue: 0,
                    readoutFormat: "%+.4f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.distortionK1, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_lens")) },
                    onReset: { reset(\.distortionK1, 0) },
                    accessibilityID: "inspector.slider.lens.distortionK1"
                )
                LightamerSlider(
                    label: String(localized: "panel_lens_distortion_k2"),
                    value: Double(params.distortionK2),
                    range: -0.2...0.2,
                    defaultValue: 0,
                    readoutFormat: "%+.4f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.distortionK2, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_lens")) },
                    onReset: { reset(\.distortionK2, 0) },
                    accessibilityID: "inspector.slider.lens.distortionK2"
                )
                LightamerSlider(
                    label: String(localized: "panel_lens_tca_r"),
                    value: Double(params.tcaR),
                    range: -0.01...0.01,
                    defaultValue: 0,
                    readoutFormat: "%+.5f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.tcaR, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_lens")) },
                    onReset: { reset(\.tcaR, 0) },
                    accessibilityID: "inspector.slider.lens.tcaR"
                )
                LightamerSlider(
                    label: String(localized: "panel_lens_tca_b"),
                    value: Double(params.tcaB),
                    range: -0.01...0.01,
                    defaultValue: 0,
                    readoutFormat: "%+.5f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.tcaB, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_lens")) },
                    onReset: { reset(\.tcaB, 0) },
                    accessibilityID: "inspector.slider.lens.tcaB"
                )
                LightamerSlider(
                    label: String(localized: "panel_lens_vignette_k1"),
                    value: Double(params.vignetteK1),
                    range: -2...2,
                    defaultValue: 0,
                    readoutFormat: "%+.4f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.vignetteK1, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_lens")) },
                    onReset: { reset(\.vignetteK1, 0) },
                    accessibilityID: "inspector.slider.lens.vignetteK1"
                )
                LightamerSlider(
                    label: String(localized: "panel_lens_vignette_k2"),
                    value: Double(params.vignetteK2),
                    range: -2...2,
                    defaultValue: 0,
                    readoutFormat: "%+.4f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.vignetteK2, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_lens")) },
                    onReset: { reset(\.vignetteK2, 0) },
                    accessibilityID: "inspector.slider.lens.vignetteK2"
                )
                LightamerSlider(
                    label: String(localized: "panel_lens_vignette_k3"),
                    value: Double(params.vignetteK3),
                    range: -2...2,
                    defaultValue: 0,
                    readoutFormat: "%+.4f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.vignetteK3, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_lens")) },
                    onReset: { reset(\.vignetteK3, 0) },
                    accessibilityID: "inspector.slider.lens.vignetteK3"
                )
                Button(String(localized: "panel_lens_reset")) {
                    applyDiscrete(LensModule.Params(
                        focalLength: params.focalLength,
                        aperture: params.aperture,
                        lensKey: params.lensKey))
                }
                .accessibilityIdentifier("inspector.lens.reset")

                // LENS-02 T1 (D-LENS-7): the enable + per-correction family
                // switches (Alcedo apply_* alignment) — each flip is ONE
                // discrete commit; the manual slider storage above is never
                // touched (the gate rides the resolved coefficients).
                Toggle(String(localized: "panel_lens_enabled"),
                       isOn: boolBinding(\.enabled))
                    .accessibilityIdentifier("inspector.toggle.lens.enabled")
                Toggle(String(localized: "panel_lens_apply_distortion"),
                       isOn: boolBinding(\.applyDistortion))
                    .accessibilityIdentifier("inspector.toggle.lens.applyDistortion")
                Toggle(String(localized: "panel_lens_apply_tca"),
                       isOn: boolBinding(\.applyTCA))
                    .accessibilityIdentifier("inspector.toggle.lens.applyTCA")
                Toggle(String(localized: "panel_lens_apply_vignette"),
                       isOn: boolBinding(\.applyVignette))
                    .accessibilityIdentifier("inspector.toggle.lens.applyVignette")

                // LENS-02 T2 (D-LENS-1): the opt-in auto-apply (default
                // FALSE; effective domain = raster chain only — the hard
                // guard lives in reloadDefaults). Persists via the setting
                // face; affects NEW images only (per-image params rule).
                Toggle(String(localized: "panel_lens_auto_apply"),
                       isOn: $autoApply)
                    .onChange(of: autoApply) { _, v in
                        LensAutoApplySetting.write(v)
                    }
                    .accessibilityIdentifier("inspector.toggle.lens.autoApply")
            } header: {
                Text("panel_lens_manual_section")
            }

            // ── §3 Lensfun match (actions + first-run download) ──
            Section {
                if hasData {
                    HStack {
                        Button(String(localized: "panel_lens_apply_match")) {
                            applyMatch()
                        }
                        .accessibilityIdentifier("inspector.lens.applyMatch")
                        Button(String(localized: "panel_lens_clear")) {
                            clearToManual()
                        }
                        .accessibilityIdentifier("inspector.lens.clear")
                    }
                } else {
                    Text(String(localized: "panel_lens_no_data"))
                        .font(.caption2)
                        .foregroundStyle(LightamerColors.textTertiary)
                        .accessibilityIdentifier("inspector.lens.noData")
                    Button(downloading
                        ? String(localized: "panel_lens_downloading")
                        : String(localized: "panel_lens_download")) {
                        downloadData()
                    }
                    .disabled(downloading)
                    .accessibilityIdentifier("inspector.lens.download")
                }
                if let notice {
                    Text(notice)
                        .font(.caption2)
                        .foregroundStyle(LightamerColors.textTertiary)
                        .accessibilityIdentifier("inspector.lens.notice")
                }
            } header: {
                Text("panel_lens_lensfun_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.lens")
        .task {
            refreshMatchState()
        }
    }

    // MARK: - D-H1 helpers (AshiftPanelView pattern)

    private func set(_ keyPath: WritableKeyPath<LensModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if p.source == .off { p.source = .manual }
        if let record = PanelEditing.updated(instance, params: p, as: LensModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<LensModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        applyDiscrete(p)
    }

    private func applyDiscrete(_ p: LensModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: LensModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_lens"))
        }
    }

    /// LENS-02 T1: the nil-defaulting Bool binding (nil renders as ON —
    /// the additive default face); each flip is ONE discrete commit.
    private func boolBinding(_ keyPath: WritableKeyPath<LensModule.Params, Bool?>) -> Binding<Bool> {
        Binding(
            get: { params[keyPath: keyPath] ?? true },
            set: { v in
                var p = params
                p[keyPath: keyPath] = v
                if let record = PanelEditing.updated(instance, params: p, as: LensModule.self) {
                    edit.applyDiscrete(record, label: String(localized: "history_lens"))
                }
            })
    }

    // MARK: - Lensfun match (discrete one-commit each)

    /// Refresh the §1 readouts (read-only; NOT a body-evaluation path —
    /// the values cache into @State and refresh only on panel appear /
    /// image switch / post-download). LENS-01 T5: the REAL match preview
    /// through the hardened memoized face (the pre-T5 stub echoed the raw
    /// EXIF key — `matchName = key` — retired).
    private func refreshMatchState() {
        hasData = LensfunStore.isInstalled
        embeddedReadout = .embedded(params.embeddedGeometry)
        let outcome = hasData ? LensfunStore.matchOutcome(params) : nil
        matchReadout = .match(params: params, hasData: hasData, outcome: outcome)
        if case .idle = matchReadout {
            notice = String(localized: "panel_lens_no_exif")
        } else {
            notice = nil
        }
    }

    /// Apply the match: flip `source` to lensfun (the resolve happens in
    /// the pipe's process — the SAME kernel as manual, D-G1 unified exit).
    /// Exactly ONE commit; unresolvable at render → identity + log (D5).
    private func applyMatch() {
        guard hasData else { return }
        var p = params
        p.source = .lensfun
        notice = nil
        applyDiscrete(p)
    }

    /// Clear back to manual (keeps slider values, drops the lensfun source).
    private func clearToManual() {
        var p = params
        p.source = .manual
        notice = nil
        applyDiscrete(p)
    }

    /// First-run download (background; failure toasts, editing unblocked).
    private func downloadData() {
        downloading = true
        Task {
            let loc = await LensfunDownloadService.download()
            await MainActor.run {
                downloading = false
                switch loc {
                case .downloaded, .custom:
                    hasData = true
                    notice = nil
                    refreshMatchState()
                case .absent:
                    notice = String(localized: "panel_lens_download_failed")
                }
            }
        }
    }
}

internal struct LensPanelProvider: IOPPanelProvider {
    var opName: String { LensModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(LensPanelView(instance: instance, edit: edit))
    }
}
