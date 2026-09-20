import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Ashift panel (Plan 04-03-T5) — the IOP-GEO-02 Inspector surface: rotation
// block (angle slider ±45 + auto-level button) + perspective block
// (lens-shift/shear sliders + auto-detect button) + inner-crop shortcut.
//
// D-H1 wiring: sliders are the drag-begin/tick/end trio (zero history
// during the drag, exactly ONE commit at the end); the auto buttons are
// discrete one-commit edits (detection runs synchronously on a small
// probe — Vision requests are fast on 512px; failure toasts and leaves
// params untouched). Values READ from the instance record.
//
// EXIF division of labor (04-03-T0 decision (3)): 90° steps live in flip;
// this panel handles fine rotation + perspective only.
// ─────────────────────────────────────────────────────────────────────────

internal struct AshiftPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    @State private var notice: String?

    private var params: AshiftModule.Params {
        PanelEditing.params(of: instance, as: AshiftModule.self)
            ?? AshiftModule.Params()
    }

    var body: some View {
        Form {
            Section {
                LightamerSlider(
                    label: String(localized: "panel_ashift_rotation"),
                    value: Double(params.rotation),
                    range: -45...45,
                    defaultValue: 0,
                    readoutFormat: "%+.2f",
                    unit: "°",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.rotation, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_ashift")) },
                    onReset: { reset(\.rotation, 0) },
                    accessibilityID: "inspector.slider.ashift.rotation"
                )
                Button(String(localized: "panel_ashift_auto_level")) {
                    autoLevel()
                }
                .accessibilityIdentifier("inspector.ashift.autoLevel")
                if let notice {
                    Text(notice)
                        .font(.caption2)
                        .foregroundStyle(LightamerColors.textTertiary)
                        .accessibilityIdentifier("inspector.ashift.notice")
                }
            } header: {
                Text("panel_ashift_rotation_section")
            }

            Section {
                LightamerSlider(
                    label: String(localized: "panel_ashift_lens_shift_v"),
                    value: Double(params.lensShiftV),
                    range: -1...1,
                    defaultValue: 0,
                    readoutFormat: "%+.3f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.lensShiftV, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_ashift")) },
                    onReset: { reset(\.lensShiftV, 0) },
                    accessibilityID: "inspector.slider.ashift.lensShiftV"
                )
                LightamerSlider(
                    label: String(localized: "panel_ashift_lens_shift_h"),
                    value: Double(params.lensShiftH),
                    range: -1...1,
                    defaultValue: 0,
                    readoutFormat: "%+.3f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.lensShiftH, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_ashift")) },
                    onReset: { reset(\.lensShiftH, 0) },
                    accessibilityID: "inspector.slider.ashift.lensShiftH"
                )
                LightamerSlider(
                    label: String(localized: "panel_ashift_shear"),
                    value: Double(params.shear),
                    range: -0.5...0.5,
                    defaultValue: 0,
                    readoutFormat: "%+.3f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.shear, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_ashift")) },
                    onReset: { reset(\.shear, 0) },
                    accessibilityID: "inspector.slider.ashift.shear"
                )
                Button(String(localized: "panel_ashift_auto_detect")) {
                    autoPerspective()
                }
                .accessibilityIdentifier("inspector.ashift.autoDetect")
            } header: {
                Text("panel_ashift_perspective_section")
            }

            Section {
                LightamerSlider(
                    label: String(localized: "panel_ashift_crop_left"),
                    value: Double(params.cl),
                    range: 0...0.99,
                    defaultValue: 0,
                    readoutFormat: "%.3f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.cl, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_ashift")) },
                    onReset: { reset(\.cl, 0) },
                    accessibilityID: "inspector.slider.ashift.cl"
                )
                LightamerSlider(
                    label: String(localized: "panel_ashift_crop_right"),
                    value: Double(params.cr),
                    range: 0.01...1,
                    defaultValue: 1,
                    readoutFormat: "%.3f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.cr, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_ashift")) },
                    onReset: { reset(\.cr, 1) },
                    accessibilityID: "inspector.slider.ashift.cr"
                )
                LightamerSlider(
                    label: String(localized: "panel_ashift_crop_top"),
                    value: Double(params.ct),
                    range: 0...0.99,
                    defaultValue: 0,
                    readoutFormat: "%.3f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.ct, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_ashift")) },
                    onReset: { reset(\.ct, 0) },
                    accessibilityID: "inspector.slider.ashift.ct"
                )
                LightamerSlider(
                    label: String(localized: "panel_ashift_crop_bottom"),
                    value: Double(params.cb),
                    range: 0.01...1,
                    defaultValue: 1,
                    readoutFormat: "%.3f",
                    onDragBegin: { edit.beginEditing() },
                    onChange: { set(\.cb, Float($0)) },
                    onDragEnd: { edit.endEditing(label: String(localized: "history_ashift")) },
                    onReset: { reset(\.cb, 1) },
                    accessibilityID: "inspector.slider.ashift.cb"
                )
                Button(String(localized: "panel_ashift_reset")) {
                    applyDiscrete(AshiftModule.Params())
                }
                .accessibilityIdentifier("inspector.ashift.reset")
            } header: {
                Text("panel_ashift_crop_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.ashift")
    }

    // MARK: - D-H1 helpers (CropPanelView pattern)

    private func set(_ keyPath: WritableKeyPath<AshiftModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        if let record = PanelEditing.updated(instance, params: p, as: AshiftModule.self) {
            edit.update(record)
        }
    }

    private func reset(_ keyPath: WritableKeyPath<AshiftModule.Params, Float>, _ v: Float) {
        var p = params
        p[keyPath: keyPath] = v
        applyDiscrete(p)
    }

    private func applyDiscrete(_ p: AshiftModule.Params) {
        if let record = PanelEditing.updated(instance, params: p, as: AshiftModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_ashift"))
        }
    }

    // MARK: - Auto-detect (Vision façade, discrete one-commit each)

    /// Horizon → rotation correction (exactly ONE commit; nil = toast, no params change).
    private func autoLevel() {
        guard let source = edit.detectionSourceImage() else {
            notice = String(localized: "panel_ashift_no_image")
            return
        }
        guard let angle = AshiftAutoDetect.horizonAngleDegrees(ciImage: source.ciImage) else {
            notice = String(localized: "panel_ashift_no_horizon")
            return
        }
        var p = params
        p.rotation = Float(AshiftAutoDetect.rotationCorrection(forHorizonAngleDegrees: angle))
        notice = nil
        applyDiscrete(p)
    }

    /// Dominant rectangle → DLT + param fit (exactly ONE commit; nil = toast).
    private func autoPerspective() {
        guard let source = edit.detectionSourceImage() else {
            notice = String(localized: "panel_ashift_no_image")
            return
        }
        guard let quad = AshiftAutoDetect.rectangleCorners(ciImage: source.ciImage) else {
            notice = String(localized: "panel_ashift_no_rectangle")
            return
        }
        let extent = source.ciImage.extent
        let w = Double(extent.width), h = Double(extent.height)
        // CG normalized (y-down) → pixel coords (y-down): the fit runs in
        // the same y-down frame on both sides (VisionDetect header), so no
        // flip is applied — source corners are the full-frame rect.
        let src = [(0.0, 0.0), (w, 0.0), (w, h), (0.0, h)]
        let dst = [
            (Double(quad.topLeft.x) * w, Double(quad.topLeft.y) * h),
            (Double(quad.topRight.x) * w, Double(quad.topRight.y) * h),
            (Double(quad.bottomRight.x) * w, Double(quad.bottomRight.y) * h),
            (Double(quad.bottomLeft.x) * w, Double(quad.bottomLeft.y) * h),
        ]
        let fit = Homography.fitParams(
            src: src, dst: dst, fLengthKB: 28, width: w, height: h)
        var p = params
        p.rotation = Float(fit.rotation)
        p.lensShiftV = Float(fit.shiftV)
        p.lensShiftH = Float(fit.shiftH)
        p.shear = Float(fit.shear)
        notice = nil
        applyDiscrete(p)
    }
}

internal struct AshiftPanelProvider: IOPPanelProvider {
    var opName: String { AshiftModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(AshiftPanelView(instance: instance, edit: edit))
    }
}
