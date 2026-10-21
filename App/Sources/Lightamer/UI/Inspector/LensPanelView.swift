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

    // MARK: LENS-02 T3 — the relay-crop conversion

    /// The suggested crop window for a resolved scale (the center 1/s
    /// window, normalized) — the RELAY semantics (D-LENS-5): the framing
    /// truth stays in the Crop module; this only computes the suggestion.
    /// scale ≤ 1 → the full frame (no relay needed).
    static func relayCropRect(scale: Float) -> (left: Float, top: Float, right: Float, bottom: Float) {
        guard scale > 1 else { return (0, 0, 1, 1) }
        let inset = (1 - 1 / scale) / 2
        return (inset, inset, 1 - inset, 1 - inset)
    }
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
    /// LENS-02 T3: the resolved-scale readout cache (OFF the body path).
    @State private var resolvedScaleValue: Float = 1
    @State private var scaleUnsupported: Bool = false
    /// LENS-02 T4: the pending selection for the detected-confirmation
    /// alert (D-LENS-2 v1 face — a selection on a detected document lands
    /// ONLY after the user confirms).
    @State private var pendingSelection: LensProfileCandidate?

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

            // ── §2.5 scale (LENS-02 T3, D-LENS-5): auto bisection + user
            // slider + resolved readout + the relay-crop button. The
            // resolved scale value caches into @State (refreshed OFF the
            // body path with the other readouts).
            Section {
                Toggle(String(localized: "panel_lens_auto_scale"),
                       isOn: boolBinding(\.autoScale))
                    .accessibilityIdentifier("inspector.toggle.lens.autoScale")
                LightamerSlider(
                    label: String(localized: "panel_lens_user_scale"),
                    value: Double(params.userScale ?? 1),
                    range: 1...4,
                    defaultValue: 1,
                    readoutFormat: "%.3f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: {
                        var p = params
                        p.userScale = Float($0)
                        if let record = PanelEditing.updated(instance, params: p, as: LensModule.self) {
                            edit.update(record)
                        }
                    },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_lens")) },
                    onReset: {
                        var p = params
                        p.userScale = nil
                        applyDiscrete(p)
                    },
                    accessibilityID: "inspector.slider.lens.userScale"
                )
                .disabled(params.autoScale ?? false)
                if scaleUnsupported {
                    Text(String(localized: "panel_lens_scale_unsupported"))
                        .font(.caption2)
                        .foregroundStyle(LightamerColors.textTertiary)
                        .accessibilityIdentifier("inspector.lens.scaleUnsupported")
                }
                HStack {
                    Text(String(localized: "panel_lens_scale_readout"))
                        .font(.caption)
                        .foregroundStyle(LightamerColors.textTertiary)
                    Text(verbatim: String(format: "%.4f", resolvedScaleValue))
                        .font(.caption)
                        .foregroundStyle(LightamerColors.textPrimary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("inspector.lens.scaleReadout")
                Button(String(localized: "panel_lens_relay_crop")) {
                    relayCropToCropPanel()
                }
                .disabled(resolvedScaleValue <= 1.0001)
                .accessibilityIdentifier("inspector.lens.relayCrop")

                // LENS-03 T1 (D-LENS-8): the TARGET projection picker —
                // rectilinear identity base + the four ACTIVE types; the
                // reserved slots are hidden (unreachable until activated).
                Picker(String(localized: "panel_lens_target_projection"),
                       selection: projectionBinding)
                {
                    Text(String(localized: "panel_lens_projection_rectilinear"))
                        .tag("rectilinear")
                    ForEach(LensProjection.active, id: \.rawValue) { p in
                        Text(String(localized: String.LocalizationValue(projectionCopyKey(p))))
                            .tag(p.rawValue)
                    }
                }
                .accessibilityIdentifier("inspector.picker.lens.targetProjection")
            } header: {
                Text("panel_lens_scale_section")
            }

            // ── §3 Lensfun profile browser + actions (LENS-02 T4): the
            // Apply/Clear buttons are RETIRED — Apply's semantics are
            // absorbed by the browser selection; Clear survives as the
            // return-to-manual arm shown ONLY while the lensfun source is
            // active. The detected-confirmation alert (D-LENS-2 v1 face)
            // gates every selection on a detected document.
            Section {
                if hasData {
                    LensProfileBrowserView(params: params, edit: edit) { candidate in
                        requestSelection(candidate)
                    }
                    if params.source == .lensfun {
                        HStack {
                            Button(String(localized: "panel_lens_rematch")) {
                                rematchAgainstCurrentDatabase()
                            }
                            .accessibilityIdentifier("inspector.lens.rematch")
                            Button(String(localized: "panel_lens_clear")) {
                                clearToManual()
                            }
                            .accessibilityIdentifier("inspector.lens.clear")
                        }
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
        .task(id: params) {
            refreshMatchState()
        }
        .alert(
            String(localized: "panel_lens_detected_confirm_title"),
            isPresented: Binding(
                get: { pendingSelection != nil },
                set: { if !$0 { pendingSelection = nil } }),
            presenting: pendingSelection
        ) { candidate in
            Button(String(localized: "panel_lens_detected_confirm_apply")) {
                commitSelection(candidate)
            }
            Button(String(localized: "panel_lens_detected_confirm_cancel"), role: .cancel) {
                pendingSelection = nil
            }
        } message: { _ in
            Text(String(localized: "panel_lens_detected_confirm_body"))
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
    /// LENS-03 T1: the target-projection picker binding (nil ≡
    /// rectilinear; each pick is ONE discrete commit).
    private var projectionBinding: Binding<String> {
        Binding(
            get: { params.targetProjection ?? "rectilinear" },
            set: { v in
                var p = params
                p.targetProjection = (v == "rectilinear") ? nil : v
                if let record = PanelEditing.updated(instance, params: p, as: LensModule.self) {
                    edit.applyDiscrete(record, label: String(localized: "history_lens"))
                }
            })
    }

    /// The static per-type copy key (the V14 explicit-switch discipline).
    private func projectionCopyKey(_ p: LensProjection) -> String {
        switch p {
        case .fisheye: return "panel_lens_projection_fisheye"
        case .equisolid: return "panel_lens_projection_equisolid"
        case .stereographic: return "panel_lens_projection_stereographic"
        case .orthographic: return "panel_lens_projection_orthographic"
        case .rectilinear: return "panel_lens_projection_rectilinear"
        case .panoramic, .equirectangular, .thoby: return "panel_lens_projection_rectilinear"
        }
    }

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
        refreshScaleReadout()
    }

    /// LENS-02 T3: the resolved-scale readout (the full-frame face —
    /// OFF the body evaluation path, same cache discipline as the match
    /// readout). Frame size from the decoded capture (nil = skip — the
    /// readout stays at the 1.0 default).
    private func refreshScaleReadout() {
        guard let image = edit.detectionSourceImage(),
              let w = image.capture.width, let h = image.capture.height, w > 1, h > 1
        else { return }
        let result = LensModule.resolvedScalePreview(
            params: params, bufW: w, bufH: h)
        resolvedScaleValue = result.scale
        scaleUnsupported = result.unsupported
    }

    /// LENS-02 T3: the relay-crop action (D-LENS-5) — write the suggested
    /// center window into the CROP module record (the sibling-instance
    /// seam, D-08-CONTEXT-3) as ONE discrete commit. The framing truth
    /// stays in Crop; the lens panel only suggests.
    private func relayCropToCropPanel() {
        guard let cropInstance = edit.siblingInstance(opName: "crop"),
              var cropParams = PanelEditing.params(of: cropInstance, as: CropModule.self)
        else {
            edit.presentToast(String(localized: "panel_lens_relay_no_crop"))
            return
        }
        let rect = LensPanelReadout.relayCropRect(scale: resolvedScaleValue)
        cropParams.left = rect.left
        cropParams.top = rect.top
        cropParams.right = rect.right
        cropParams.bottom = rect.bottom
        if let record = PanelEditing.updated(cropInstance, params: cropParams, as: CropModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_crop"))
        }
    }

    /// LENS-02 T4: the browser selection entry — a DETECTED document
    /// routes through the confirmation alert (unconfirmed = params never
    /// touched); every other judgment commits directly.
    private func requestSelection(_ candidate: LensProfileCandidate) {
        guard hasData else { return }
        notice = nil
        if LensProfileBrowserModel.needsConfirmation(embedded: params.embeddedGeometry) {
            pendingSelection = candidate
        } else {
            commitSelection(candidate)
        }
    }

    /// The selection commit: ONE discrete edit (source = .lensfun + the
    /// picked model; LENS-04 T1 — the snapshot bakes in the same commit
    /// via bakeCommitted; a match/resolve miss keeps the snapshot-free
    /// params and the live memo path renders).
    /// B-2 (LENS-01 acceptance 2nd) seam ②: the commit runs through the
    /// REAL reloadDefaults seam (`LensDefaultsWiring.committedSelection`)
    /// — the EXIF resolve inputs fold in first (pre-wiring, every commit
    /// matched against EXIF-less params: missingFocal → identity), and
    /// the bake is the rematch face (fresh snapshot per selection; a miss
    /// clears any stale prior snapshot instead of silently keeping it).
    private func commitSelection(_ candidate: LensProfileCandidate) {
        pendingSelection = nil
        Task {
            let committed = await LensDefaultsWiring.committedSelection(
                base: params, candidate: candidate,
                image: edit.detectionSourceImage())
            applyDiscrete(committed)
        }
    }

    /// LENS-04 T1: the Re-match action — invalidate the snapshot, re-run
    /// the match against the CURRENT database, and commit the fresh
    /// snapshot in ONE discrete edit; a miss CLEARS the snapshot (the
    /// readout shows the miss face; the live memo path renders identity).
    private func rematchAgainstCurrentDatabase() {
        if let rematched = LensfunStore.rematch(params) {
            applyDiscrete(rematched)
        } else {
            applyDiscrete(LensfunStore.clearSnapshot(params))
            notice = String(localized: "panel_lens_rematch_miss")
        }
    }

    /// Clear back to manual (keeps every stored value, drops the lensfun
    /// source — the retired Clear button's surviving arm, model-owned).
    private func clearToManual() {
        notice = nil
        applyDiscrete(LensProfileBrowserModel.clearedParams(base: params))
    }

    /// First-run data acquisition (background; failure toasts, editing
    /// unblocked). LENS-03 T3: the bundled seed first (local, instant);
    /// the legacy download stays as the no-seed fallback; the manual
    /// SHA-verified update lives in the Settings face.
    private func downloadData() {
        downloading = true
        Task {
            let loc = LensfunDataDistribution.resolveAndInstall()
            if case .absent = loc {
                let fallback = await LensfunDownloadService.download()
                await MainActor.run {
                    downloading = false
                    switch fallback {
                    case .absent:
                        notice = String(localized: "panel_lens_download_failed")
                    default:
                        hasData = true
                        notice = nil
                        refreshMatchState()
                    }
                }
            } else {
                await MainActor.run {
                    downloading = false
                    hasData = true
                    notice = nil
                    refreshMatchState()
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
