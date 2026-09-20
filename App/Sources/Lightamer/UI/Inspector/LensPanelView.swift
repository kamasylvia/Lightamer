import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Lens panel (Plan 04-04-T3) — the IOP-GEO-03 Inspector surface, three
// sections mirroring the D-G1 three layers:
//
//  ① Embedded status ((a) layer): CIRAW already applied the embedded
//     correction for supported lenses — manual defaults OFF to avoid
//     double-correction (the known tradeoff, 04-04-DECISIONS D-04-04-T0-1).
//  ② Manual sliders ((b) layer): distortion k1/k2, TCA R/B, devignette
//     k1/k2/k3 — D-H1 drag trio, exactly ONE commit per gesture.
//  ③ Lensfun match ((c) layer): match status (hit name / miss / no data)
//     + Apply/Clear discrete buttons + first-run download.
//
// D-H1 wiring: sliders are the drag-begin/tick/end trio (zero history
// during the drag, exactly ONE commit at the end); Apply/Clear/download
// are discrete one-commit edits. Values READ from the instance record.
// ─────────────────────────────────────────────────────────────────────────

internal struct LensPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    @State private var notice: String?
    @State private var matchName: String?
    @State private var hasData: Bool = LensfunStore.isInstalled
    @State private var downloading: Bool = false

    private var params: LensModule.Params {
        PanelEditing.params(of: instance, as: LensModule.self)
            ?? LensModule.Params()
    }

    var body: some View {
        Form {
            // ── §1 embedded status ──
            Section {
                Text(String(localized: "panel_lens_embedded_note"))
                    .font(.caption2)
                    .foregroundStyle(LightamerColors.textTertiary)
                    .accessibilityIdentifier("inspector.lens.embeddedNote")
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
            } header: {
                Text("panel_lens_manual_section")
            }

            // ── §3 Lensfun match ──
            Section {
                if hasData {
                    if let matchName {
                        Text(matchName)
                            .font(.caption)
                            .foregroundStyle(LightamerColors.textPrimary)
                            .accessibilityIdentifier("inspector.lens.matchName")
                    }
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

    // MARK: - Lensfun match (discrete one-commit each)

    /// Refresh the §3 status line from the store + EXIF snapshot (read-only).
    private func refreshMatchState() {
        hasData = LensfunStore.isInstalled
        guard hasData else { matchName = nil; return }
        guard let key = params.lensKey, !key.isEmpty else {
            matchName = nil
            notice = String(localized: "panel_lens_no_exif")
            return
        }
        // Match probe is synchronous (snapshot read, no pipe involvement).
        matchName = key
        notice = nil
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
