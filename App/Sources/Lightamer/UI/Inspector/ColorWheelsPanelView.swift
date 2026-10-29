import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// ColorWheelsPanelView (Plan M2-5-2 T4, KD-2) — the LGG three-trackball
// panel ("Color Wheels"): lift / gamma / gain wheels, each a SwiftUI Canvas
// disc + DragGesture writing the disc through the ColorWheelsModule pure
// conversions (the UI only forwards coordinates — the math is the IOP
// testable face). NO Metal self-drawing (the D-OQ-2 A argument: a handful
// of nodes, Canvas frame cost negligible).
//
// The drag derives the wheel's colorOffset with the Alcedo trackball
// mapping (DiscToCdlDelta + UpdateDerived: lift rides base 0, gamma/gain
// base 1 with gamma inverted) — disc/strength are carried UI state, the
// derived colorOffset is the pixel truth (the P1 D1 packing verbatim).
// Per-wheel double-click resets that wheel to the payload identity; the
// Reset wheels button decodes the GradeCatalog identityJSON (the P1 single
// source) and replaces all three.
// ─────────────────────────────────────────────────────────────────────────

internal struct ColorWheelsPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    private let params: ColorWheelsModule.Params

    /// M9-4 T2 (X4): the panel fork — the document's RESOLVED arm read
    /// ONCE at panel build (body-evaluation discipline). nil (no image /
    /// legacy) and `.v1/.v2` render the EXISTING three-wheel view
    /// BYTE-IDENTICAL (the frozen view over the frozen render); `.v3`
    /// renders the four-wheel stops view with the edit projection
    /// (effective params — the first edit materializes the offset).
    private let processArm: RenderProcess?

    /// The migration row's decision (read once at build; the same pure
    /// gate the film row consumes — D-M9SP-7④'s single-row mount).
    private let migrationAction: FilmMigrationAction?

    init(instance: ModuleInstance, edit: InspectorEditSession) {
        self.instance = instance
        self.edit = edit
        self.params = PanelEditing.params(of: instance, as: ColorWheelsModule.self) ?? ColorWheelsModule.Params()
        self.processArm = edit.documentProcessVersion.map { RenderProcess.resolving($0) }
        self.migrationAction = edit.migrationAction
    }

    var body: some View {
        if processArm == .v3 {
            v3Body
        } else {
            legacyBody
        }
    }

    // MARK: - The v1/v2 (frozen) three-wheel view — BYTE-IDENTICAL to the
    // pre-M9-4 body (the frozen view over the frozen render, D-M9SP-1).

    @ViewBuilder
    private var legacyBody: some View {
        Form {
            Section {
                wheelBlock(.lift, control: params.lift)
            } header: {
                Text("panel_wheels_lift")
            }
            Section {
                wheelBlock(.gamma, control: params.gamma)
            } header: {
                Text("panel_wheels_gamma")
            }
            Section {
                wheelBlock(.gain, control: params.gain)
            } header: {
                Text("panel_wheels_gain")
            }
            Section {
                Button(String(localized: "panel_wheels_reset")) {
                    resetAllWheels()
                }
                .accessibilityIdentifier("inspector.button.colorwheels.reset")
            }
            if let migrationAction {
                ProcessMigrationRow(inputs: ProcessMigrationInputs(
                    action: migrationAction,
                    onMigrate: { edit.runProcessMigration() }))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.colorwheels")
    }

    // MARK: - The v3 four-wheel stops view (X4)

    /// The v3 wheel slots (panel-local — the v1 `WheelKind` enum and its
    /// base±delta derivation stay untouched; the v3 semantics are the
    /// stops-domain disc mapping).
    private enum V3Wheel: String, CaseIterable {
        case shadows, midtones, highlights, offset

        var titleKey: String {
            switch self {
            case .shadows: return "panel_wheels_shadows"
            case .midtones: return "panel_wheels_midtones"
            case .highlights: return "panel_wheels_highlights"
            case .offset: return "panel_wheels_offset"
            }
        }

        var tooltipKey: String {
            switch self {
            case .shadows: return "panel_wheels_shadows_tooltip"
            case .midtones: return "panel_wheels_midtones_tooltip"
            case .highlights: return "panel_wheels_highlights_tooltip"
            case .offset: return "panel_wheels_offset_tooltip"
            }
        }
    }

    /// The v3 edit projection (D-M9SP-2 补强①): the editing base is
    /// `effective(params)` — an offset-absent shape converts ONCE at the
    /// first tick, so the committed quad ALWAYS carries the offset
    /// (the v2 discriminator materializes at the first edit). Undo back
    /// past the first edit restores the absent shape and the render-time
    /// conversion.
    private var v3Params: ColorWheelsModule.Params {
        ColorWheelsModule.effectiveToneWheelParams(params)
    }

    @ViewBuilder
    private var v3Body: some View {
        Form {
            ForEach(V3Wheel.allCases, id: \.rawValue) { wheel in
                Section {
                    v3WheelBlock(wheel, control: v3Control(of: wheel))
                } header: {
                    Text(String(localized: String.LocalizationValue(wheel.titleKey)))
                }
            }
            Section {
                Button(String(localized: "panel_wheels_reset")) {
                    resetAllWheelsV3()
                }
                .accessibilityIdentifier("inspector.button.colorwheels.reset")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.colorwheels")
    }

    private func v3Control(of wheel: V3Wheel) -> ColorWheelControl {
        let p = v3Params
        switch wheel {
        case .shadows: return p.lift
        case .midtones: return p.gamma
        case .highlights: return p.gain
        case .offset: return p.offset ?? ColorWheelControl()
        }
    }

    private func v3Set(
        _ wheel: V3Wheel, _ value: ColorWheelControl,
        in params: inout ColorWheelsModule.Params
    ) {
        switch wheel {
        case .shadows: params.lift = value
        case .midtones: params.gamma = value
        case .highlights: params.gain = value
        case .offset: params.offset = value
        }
    }

    @ViewBuilder
    private func v3WheelBlock(
        _ wheel: V3Wheel, control: ColorWheelControl
    ) -> some View {
        TrackballView(
            disc: control.disc,
            onTick: { disc in
                v3Write(wheel) { c in
                    c.disc = disc
                    // The stops-domain mapping (X1): the disc IS the
                    // zero-mean per-channel stops at strength × radius —
                    // no v1 base/delta derivation, no clamp.
                    c.colorOffset = ColorWheelsModule.discToChannelStops(
                        x: disc.x, y: disc.y, strength: max(c.strength, 0))
                }
            },
            onDragEnd: { edit.endEditing(label: historyLabel) },
            onReset: {
                v3WriteDiscrete(wheel) { $0 = ColorWheelControl() }
            },
            accessibilityID: "inspector.trackball.colorwheels.\(wheel.rawValue)")
        Text(String(localized: String.LocalizationValue(wheel.tooltipKey)))
            .font(.caption2)
            .foregroundStyle(ThemeTokens.textSecondary)
        LightamerSlider(
            label: String(localized: "panel_wheels_strength"),
            value: Double(control.strength),
            range: 0.0...Double(ColorWheelsModule.discMaxStops),
            defaultValue: Double(ColorWheelsModule.discMaxStops),
            readoutFormat: "%.2f",
            onDragBegin: { edit.beginEditing() },
            onChange: { value in
                v3Write(wheel) { c in
                    c.strength = Float(value)
                    c.colorOffset = ColorWheelsModule.discToChannelStops(
                        x: c.disc.x, y: c.disc.y, strength: max(c.strength, 0))
                }
            },
            onDragEnd: { edit.endEditing(label: historyLabel) },
            onReset: {
                v3WriteDiscrete(wheel) { $0.strength = ColorWheelsModule.discMaxStops }
            },
            accessibilityID: "inspector.slider.colorwheels.\(wheel.rawValue).strength"
        )
        LightamerSlider(
            label: String(localized: "panel_wheels_luminance"),
            value: Double(control.luminanceOffset),
            range: Double(-ColorWheelsModule.masterMaxStops)
                ... Double(ColorWheelsModule.masterMaxStops),
            defaultValue: 0,
            readoutFormat: "%.2f",
            onDragBegin: { edit.beginEditing() },
            onChange: { value in
                v3Write(wheel) { $0.luminanceOffset = Float(value) }
            },
            onDragEnd: { edit.endEditing(label: historyLabel) },
            onReset: {
                v3WriteDiscrete(wheel) { $0.luminanceOffset = 0 }
            },
            accessibilityID: "inspector.slider.colorwheels.\(wheel.rawValue).luminance"
        )
    }

    /// A v3 live tick (the editing projection base — see `v3Params`).
    private func v3Write(
        _ wheel: V3Wheel, _ mutate: (inout ColorWheelControl) -> Void
    ) {
        var p = v3Params
        var control = v3Control(of: wheel)
        mutate(&control)
        v3Set(wheel, control, in: &p)
        if let record = PanelEditing.updated(
            instance, params: p, as: ColorWheelsModule.self) {
            edit.update(record)
        }
    }

    /// A v3 discrete write (double-click reset): ONE commit.
    private func v3WriteDiscrete(
        _ wheel: V3Wheel, _ mutate: (inout ColorWheelControl) -> Void
    ) {
        var p = v3Params
        var control = v3Control(of: wheel)
        mutate(&control)
        v3Set(wheel, control, in: &p)
        if let record = PanelEditing.updated(
            instance, params: p, as: ColorWheelsModule.self) {
            edit.applyDiscrete(record, label: historyLabel)
        }
    }

    /// The v3 payload-identity reset (the zero quad, offset present —
    /// the materialized v2 shape's neutral).
    private func resetAllWheelsV3() {
        var p = v3Params
        p.lift = ColorWheelControl()
        p.gamma = ColorWheelControl()
        p.gain = ColorWheelControl()
        p.offset = ColorWheelControl()
        if let record = PanelEditing.updated(
            instance, params: p, as: ColorWheelsModule.self) {
            edit.applyDiscrete(record, label: historyLabel)
        }
    }

    // MARK: - One wheel block (trackball + strength + luminance)

    @ViewBuilder
    private func wheelBlock(
        _ wheel: ColorWheelsModule.WheelKind, control: ColorWheelControl
    ) -> some View {
        TrackballView(
            disc: control.disc,
            onTick: { disc in write(wheel) { $0.disc = disc } },
            onDragEnd: { edit.endEditing(label: historyLabel) },
            onReset: {
                var p = params
                p = ColorWheelsModule.resetting(p, wheel: wheel)
                if let record = PanelEditing.updated(
                    instance, params: p, as: ColorWheelsModule.self) {
                    edit.applyDiscrete(record, label: historyLabel)
                }
            },
            accessibilityID: "inspector.trackball.colorwheels.\(wheel.rawValue)")
        LightamerSlider(
            label: String(localized: "panel_wheels_strength"),
            value: Double(control.strength),
            range: Double(ColorWheelsModule.strengthRange.lowerBound)
                ... Double(ColorWheelsModule.strengthRange.upperBound),
            defaultValue: Double(ColorWheelControl().strength),
            readoutFormat: "%.3f",
            onDragBegin: { edit.beginEditing() },
            onChange: { value in write(wheel) { $0.strength = Float(value) } },
            onDragEnd: { edit.endEditing(label: historyLabel) },
            onReset: {
                writeDiscrete(wheel) { $0.strength = ColorWheelControl().strength }
            },
            accessibilityID: "inspector.slider.colorwheels.\(wheel.rawValue).strength"
        )
        LightamerSlider(
            label: String(localized: "panel_wheels_luminance"),
            value: Double(control.luminanceOffset),
            range: Double(ColorWheelsModule.luminanceRange.lowerBound)
                ... Double(ColorWheelsModule.luminanceRange.upperBound),
            defaultValue: Double(ColorWheelControl().luminanceOffset),
            readoutFormat: "%.2f",
            onDragBegin: { edit.beginEditing() },
            onChange: { value in write(wheel) { $0.luminanceOffset = Float(value) } },
            onDragEnd: { edit.endEditing(label: historyLabel) },
            onReset: {
                writeDiscrete(wheel) {
                    $0.luminanceOffset = ColorWheelControl().luminanceOffset
                }
            },
            accessibilityID: "inspector.slider.colorwheels.\(wheel.rawValue).luminance"
        )
    }

    private var historyLabel: String {
        String(localized: "history_colorwheels")
    }

    /// The Reset wheels button (KD-2): the GradeCatalog colorWheel row's
    /// identityJSON (the P1 single source) decoded back to Params, ONE
    /// discrete commit.
    private func resetAllWheels() {
        guard let item = GradeCatalog.item(opName: ColorWheelsModule.opName),
            let identity = try? JSONDecoder().decode(
                ColorWheelsModule.Params.self, from: Data(item.identityJSON.utf8)),
            let record = PanelEditing.updated(
                instance, params: identity, as: ColorWheelsModule.self)
        else { return }
        edit.applyDiscrete(record, label: historyLabel)
    }

    /// A live tick: mutate one wheel's control, re-derive its colorOffset
    /// from the (disc, strength) pair, upsert WITHOUT history.
    private func write(
        _ wheel: ColorWheelsModule.WheelKind,
        _ mutate: (inout ColorWheelControl) -> Void
    ) {
        var p = params
        var control = self.control(of: wheel, in: &p)
        mutate(&control)
        setControl(wheel, control, in: &p)
        deriveColorOffset(of: &p, wheel: wheel)
        if let record = PanelEditing.updated(instance, params: p, as: ColorWheelsModule.self) {
            edit.update(record)
        }
    }

    /// A discrete write (slider double-click reset): ONE commit.
    private func writeDiscrete(
        _ wheel: ColorWheelsModule.WheelKind,
        _ mutate: (inout ColorWheelControl) -> Void
    ) {
        var p = params
        var control = self.control(of: wheel, in: &p)
        mutate(&control)
        setControl(wheel, control, in: &p)
        deriveColorOffset(of: &p, wheel: wheel)
        if let record = PanelEditing.updated(instance, params: p, as: ColorWheelsModule.self) {
            edit.applyDiscrete(record, label: historyLabel)
        }
    }

    private func control(
        of wheel: ColorWheelsModule.WheelKind, in params: inout ColorWheelsModule.Params
    ) -> ColorWheelControl {
        switch wheel {
        case .lift: return params.lift
        case .gamma: return params.gamma
        case .gain: return params.gain
        }
    }

    private func setControl(
        _ wheel: ColorWheelsModule.WheelKind, _ value: ColorWheelControl,
        in params: inout ColorWheelsModule.Params
    ) {
        switch wheel {
        case .lift: params.lift = value
        case .gamma: params.gamma = value
        case .gain: params.gain = value
        }
    }

    /// The pixel-state derivation (Alcedo UpdateDerived): the wheel's
    /// colorOffset = base(lift 0 / gamma·gain 1) ± DiscToCdlDelta(disc,
    /// strength) — the drag is the ABSOLUTE position, never a delta.
    private func deriveColorOffset(
        of params: inout ColorWheelsModule.Params, wheel: ColorWheelsModule.WheelKind
    ) {
        var control = self.control(of: wheel, in: &params)
        control.colorOffset = ColorWheelsModule.colorOffset(
            from: control.disc, strength: control.strength, wheel: wheel)
        setControl(wheel, control, in: &params)
    }
}

// MARK: - The trackball control (Canvas + DragGesture, KD-2)

private struct TrackballView: View {

    let disc: SIMD2<Float>
    let onTick: (SIMD2<Float>) -> Void
    let onDragEnd: () -> Void
    let onReset: () -> Void
    let accessibilityID: String

    /// The live drag disc (the prop catches up at the commit boundary).
    @State private var liveDisc: SIMD2<Float>?

    var body: some View {
        GeometryReader { geo in
            let center = SIMD2<Float>(
                Float(geo.size.width / 2), Float(geo.size.height / 2))
            let radius = Float(min(geo.size.width, geo.size.height) / 2) - 6
            Canvas { context, _ in
                let rect = CGRect(
                    x: CGFloat(center.x - radius),
                    y: CGFloat(center.y - radius),
                    width: CGFloat(radius * 2), height: CGFloat(radius * 2))
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(LightamerColors.textSecondary.opacity(0.6)),
                    lineWidth: 1)
                var cross = Path()
                cross.move(to: CGPoint(x: CGFloat(center.x - radius), y: CGFloat(center.y)))
                cross.addLine(
                    to: CGPoint(x: CGFloat(center.x + radius), y: CGFloat(center.y)))
                cross.move(to: CGPoint(x: CGFloat(center.x), y: CGFloat(center.y - radius)))
                cross.addLine(
                    to: CGPoint(x: CGFloat(center.x), y: CGFloat(center.y + radius)))
                context.stroke(
                    cross, with: .color(LightamerColors.textSecondary.opacity(0.25)),
                    lineWidth: 1)
                let offset = ColorWheelsModule.pointFrom(
                    disc: displayedDisc, radius: radius)
                let dotRect = CGRect(
                    x: CGFloat(center.x + offset.x) - 5,
                    y: CGFloat(center.y + offset.y) - 5, width: 10, height: 10)
                context.fill(
                    Path(ellipseIn: dotRect), with: .color(LightamerColors.accent))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = SIMD2(
                            Float(value.location.x), Float(value.location.y))
                        let disc = ColorWheelsModule.discFrom(
                            point: point, relativeTo: center, radius: radius)
                        liveDisc = disc
                        onTick(disc)
                    }
                    .onEnded { _ in
                        liveDisc = nil
                        onDragEnd()
                    })
            .onTapGesture(count: 2) { onReset() }
        }
        .frame(height: 116)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityID)
    }

    private var displayedDisc: SIMD2<Float> { liveDisc ?? disc }
}

// MARK: - Provider

internal struct ColorWheelsPanelProvider: IOPPanelProvider {
    var opName: String { ColorWheelsModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(ColorWheelsPanelView(instance: instance, edit: edit))
    }
}
