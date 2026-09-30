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

    private var params: ColorWheelsModule.Params {
        PanelEditing.params(of: instance, as: ColorWheelsModule.self)
            ?? ColorWheelsModule.Params()
    }

    var body: some View {
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
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.colorwheels")
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
