import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// GradeScalarPanels (Plan M2-5-2 T3) — the six thin slider panels for the
// M2-5-1 catalog ops: CAT02 creative white balance / Contrast / White /
// Black / Tint / Saturation.
//
// SHAPE CONTRACT (the Vignette panel family): every panel is a thin
// LightamerSlider face over `PanelEditing` — drags live-tick (zero history
// items), land exactly ONE commit at drag end, double-click resets to the
// module identity. ZERO hand-copied ranges/defaults: each slider cites the
// module's own range constants and Params() defaults (the P1 single
// source; a module-side range change re-flows the panel at compile time).
//
// LightamerSlider carries no step (the shared component's face — the
// DECISIONS entry records it); granularity rides the readout precision.
// ─────────────────────────────────────────────────────────────────────────

/// CAT02 creative white balance (the Look/Color seat — D5): CCT + tint on
/// the RAW Custom WB tint scale, applied in the ACEScc grade domain. The
/// page note carries the Alcedo copy semantics: camera WB stays on the RAW
/// Decode / CIRAW layer (M2GRADE-04) — this op never writes back to decode.
internal struct Cat02WBPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private let params: Cat02WBModule.Params

    init(instance: ModuleInstance, edit: InspectorEditSession) {
        self.instance = instance
        self.edit = edit
        self.params = PanelEditing.params(of: instance, as: Cat02WBModule.self) ?? Cat02WBModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_cat02_temperature"),
                    value: Double(params.temperature),
                    range: Double(Cat02WBModule.temperatureRange.lowerBound)
                        ... Double(Cat02WBModule.temperatureRange.upperBound),
                    defaultValue: Double(Cat02WBModule.identityTemperature),
                    readoutFormat: "%.0f",
                    unit: " K",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.temperature, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_cat02")) },
                    onReset: {
                        reset(
                            \.temperature, Cat02WBModule.identityTemperature)
                    },
                    accessibilityID: "inspector.slider.cat02.temperature"
                )
                LightamerSlider(
                    label: String(localized: "panel_cat02_tint"),
                    value: Double(params.tint),
                    range: Double(Cat02WBModule.tintRange.lowerBound)
                        ... Double(Cat02WBModule.tintRange.upperBound),
                    defaultValue: Double(Cat02WBModule.identityTint),
                    readoutFormat: "%.1f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.tint, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_cat02")) },
                    onReset: { reset(\.tint, Cat02WBModule.identityTint) },
                    accessibilityID: "inspector.slider.cat02.tint"
                )
            } header: {
                Text("panel_cat02_section")
            } footer: {
                Text("panel_cat02_note")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.cat02")
    }

    private func set(_ keyPath: WritableKeyPath<Cat02WBModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: Cat02WBModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<Cat02WBModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: Cat02WBModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_cat02"))
        }
    }
}

/// Contrast (the Tone main seat): the OkLab lightness S-curve op — 0 is
/// the flag-early-exit identity.
internal struct ContrastPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private let params: ContrastModule.Params

    init(instance: ModuleInstance, edit: InspectorEditSession) {
        self.instance = instance
        self.edit = edit
        self.params = PanelEditing.params(of: instance, as: ContrastModule.self) ?? ContrastModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_contrast_contrast"),
                    value: Double(params.contrast),
                    range: Double(ContrastModule.contrastRange.lowerBound)
                        ... Double(ContrastModule.contrastRange.upperBound),
                    defaultValue: Double(ContrastModule.Params().contrast),
                    readoutFormat: "%.0f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.contrast, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_contrast")) },
                    onReset: { reset(\.contrast, ContrastModule.Params().contrast) },
                    accessibilityID: "inspector.slider.contrast.contrast"
                )
            } header: {
                Text("panel_contrast_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.contrast")
    }

    private func set(_ keyPath: WritableKeyPath<ContrastModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: ContrastModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<ContrastModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: ContrastModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_contrast"))
        }
    }
}

/// White (the Tone main seat): the +0.005/channel gain endpoint op.
internal struct WhitePanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private let params: WhiteModule.Params

    init(instance: ModuleInstance, edit: InspectorEditSession) {
        self.instance = instance
        self.edit = edit
        self.params = PanelEditing.params(of: instance, as: WhiteModule.self) ?? WhiteModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_white_white"),
                    value: Double(params.white),
                    range: Double(WhiteModule.whiteRange.lowerBound)
                        ... Double(WhiteModule.whiteRange.upperBound),
                    defaultValue: Double(WhiteModule.Params().white),
                    readoutFormat: "%.0f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.white, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_white")) },
                    onReset: { reset(\.white, WhiteModule.Params().white) },
                    accessibilityID: "inspector.slider.white.white"
                )
            } header: {
                Text("panel_white_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.white")
    }

    private func set(_ keyPath: WritableKeyPath<WhiteModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: WhiteModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<WhiteModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: WhiteModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_white"))
        }
    }
}

/// Black (the Tone main seat): the +0.001/channel offset endpoint op.
internal struct BlackPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private let params: BlackModule.Params

    init(instance: ModuleInstance, edit: InspectorEditSession) {
        self.instance = instance
        self.edit = edit
        self.params = PanelEditing.params(of: instance, as: BlackModule.self) ?? BlackModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_black_black"),
                    value: Double(params.black),
                    range: Double(BlackModule.blackRange.lowerBound)
                        ... Double(BlackModule.blackRange.upperBound),
                    defaultValue: Double(BlackModule.Params().black),
                    readoutFormat: "%.0f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.black, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_black")) },
                    onReset: { reset(\.black, BlackModule.Params().black) },
                    accessibilityID: "inspector.slider.black.black"
                )
            } header: {
                Text("panel_black_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.black")
    }

    private func set(_ keyPath: WritableKeyPath<BlackModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: BlackModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<BlackModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: BlackModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_black"))
        }
    }
}

/// Tint (the Look/Color seat): the standalone ±100 green-magenta scalar
/// (distinct from the CAT02 panel's inner tint — the directory keeps both).
internal struct TintPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private let params: TintModule.Params

    init(instance: ModuleInstance, edit: InspectorEditSession) {
        self.instance = instance
        self.edit = edit
        self.params = PanelEditing.params(of: instance, as: TintModule.self) ?? TintModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_tint_tint"),
                    value: Double(params.tint),
                    range: Double(TintModule.tintRange.lowerBound)
                        ... Double(TintModule.tintRange.upperBound),
                    defaultValue: Double(TintModule.Params().tint),
                    readoutFormat: "%.0f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.tint, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_tint")) },
                    onReset: { reset(\.tint, TintModule.Params().tint) },
                    accessibilityID: "inspector.slider.tint.tint"
                )
            } header: {
                Text("panel_tint_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.tint")
    }

    private func set(_ keyPath: WritableKeyPath<TintModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: TintModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<TintModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: TintModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_tint"))
        }
    }
}

/// Saturation (the Look/Master seat): the 0–4 multiplicative luma-pivot
/// op — 1.0 is the flag-early-exit identity.
internal struct SaturationPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private let params: SaturationModule.Params

    init(instance: ModuleInstance, edit: InspectorEditSession) {
        self.instance = instance
        self.edit = edit
        self.params = PanelEditing.params(of: instance, as: SaturationModule.self) ?? SaturationModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_saturation_saturation"),
                    value: Double(params.saturation),
                    range: Double(SaturationModule.saturationRange.lowerBound)
                        ... Double(SaturationModule.saturationRange.upperBound),
                    defaultValue: Double(SaturationModule.Params().saturation),
                    readoutFormat: "%.2f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.saturation, Float($0)) },
                    onDragEnd: {
                        edit.endEditing(label: String(localized: "history_saturation"))
                    },
                    onReset: {
                        reset(\.saturation, SaturationModule.Params().saturation)
                    },
                    accessibilityID: "inspector.slider.saturation.saturation"
                )
            } header: {
                Text("panel_saturation_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.saturation")
    }

    private func set(_ keyPath: WritableKeyPath<SaturationModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: SaturationModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<SaturationModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: SaturationModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_saturation"))
        }
    }
}

// MARK: - Providers (the IOPPanelProvider face — one per op)

internal struct Cat02WBPanelProvider: IOPPanelProvider {
    var opName: String { Cat02WBModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(Cat02WBPanelView(instance: instance, edit: edit))
    }
}

internal struct ContrastPanelProvider: IOPPanelProvider {
    var opName: String { ContrastModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(ContrastPanelView(instance: instance, edit: edit))
    }
}

internal struct WhitePanelProvider: IOPPanelProvider {
    var opName: String { WhiteModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(WhitePanelView(instance: instance, edit: edit))
    }
}

internal struct BlackPanelProvider: IOPPanelProvider {
    var opName: String { BlackModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(BlackPanelView(instance: instance, edit: edit))
    }
}

internal struct TintPanelProvider: IOPPanelProvider {
    var opName: String { TintModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(TintPanelView(instance: instance, edit: edit))
    }
}

internal struct SaturationPanelProvider: IOPPanelProvider {
    var opName: String { SaturationModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(SaturationPanelView(instance: instance, edit: edit))
    }
}
