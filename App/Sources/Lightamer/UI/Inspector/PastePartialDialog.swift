import LightamerCore
import LightamerIOP
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// ModuleTitles (Plan 09-04 T2) — the SINGLE localized display-name mapping
// for module ops (extracted from InspectorView's private switch so the
// partial-paste dialog and the Inspector rows can never drift).
// ─────────────────────────────────────────────────────────────────────────────

enum ModuleTitles {

    /// The localized display name for an op (fallback = the raw opName —
    /// a new op must land with its zh key the same round, the 05-06-T5
    /// precedent).
    static func label(for opName: String) -> String {
        switch opName {
        case ExposureModule.opName: return String(localized: "module_exposure")
        case TemperatureModule.opName: return String(localized: "module_temperature")
        case CropModule.opName: return String(localized: "module_crop")
        case FlipModule.opName: return String(localized: "module_flip")
        case ColorBalanceRGBModule.opName: return String(localized: "history_colorbalancergb")
        case ChannelMixerRGBModule.opName: return String(localized: "history_channelmixerrgb")
        case ChannelMixerModule.opName: return String(localized: "history_channelmixer")
        case LiquifyModule.opName: return String(localized: "module_liquify")
        case ColorContrastModule.opName: return String(localized: "history_colorcontrast")
        case VibranceModule.opName: return String(localized: "history_vibrance")
        case VelviaModule.opName: return String(localized: "history_velvia")
        case ColorZonesModule.opName: return String(localized: "history_colorzones")
        case MonochromeModule.opName: return String(localized: "history_monochrome")
        case NLMeansModule.opName: return String(localized: "history_nlmeans")
        case DenoiseProfileModule.opName: return String(localized: "history_denoiseprofile")
        case BilateralModule.opName: return String(localized: "history_bilateral")
        case BordersModule.opName: return String(localized: "module_borders")
        case WatermarkModule.opName: return String(localized: "module_watermark")
        case SigmoidModule.opName: return String(localized: "history_sigmoid")
        case FilmicRGBModule.opName: return String(localized: "history_filmicrgb")
        case SharpenModule.opName: return String(localized: "history_sharpen")
        case LocalContrastModule.opName: return String(localized: "history_localcontrast")
        case EqualizerModule.opName: return String(localized: "history_equalizer")
        case LensModule.opName: return String(localized: "history_lens")
        case AshiftModule.opName: return String(localized: "history_ashift")
        case HighpassModule.opName: return String(localized: "history_highpass")
        case SoftenModule.opName: return String(localized: "history_soften")
        case ToneCurveModule.opName: return String(localized: "history_tonecurve")
        case LevelsModule.opName: return String(localized: "history_levels")
        case ShadhiModule.opName: return String(localized: "history_shadhi")
        case SkinSmoothModule.opName: return String(localized: "history_skinsmooth")
        case AgXModule.opName: return String(localized: "history_agx")
        case ColisaModule.opName: return String(localized: "history_colisa")
        case ToneEqualModule.opName: return String(localized: "history_toneequal")
        default: return opName
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// PastePartialDialog (Plan 09-04 T2; HIST-05 部分复制粘贴) — the checked
// subset picker over a frozen PastePayload (dt `dt_gui_hist_dialog_new` /
// `dt_history_copy_parts` twin, history.c:1906-1922).
//
// One row per payload INSTANCE (逐模块 × 每模块多实例 — the (opName,
// multiPriority, multiName) tuple is the row identity). A mode picker
// rides the dialog (dt's dialog has the same overwrite/append radios):
// merge = append (default — batch-safe); overwrite = exact duplicate.
//
// 面板四件套: L010 identifiers (`paste.partial.*`), zh/en catalog (L025),
// the sheet width honors the 280pt Inspector-constraint family (a modal
// sheet — fixed 320pt so the tree stays readable), D-H1 N/A (no drags —
// the dialog commits nothing itself; it only RETURNS a selection).
// ─────────────────────────────────────────────────────────────────────────────

internal struct PastePartialDialog: View {

    let payload: PastePayload
    let initialSelection: Set<PastePayload.InstanceKey>?
    let onPaste: (_ selection: Set<PastePayload.InstanceKey>, _ mode: PasteMode) -> Void
    let onCancel: () -> Void

    @State private var checked: Set<PastePayload.InstanceKey> = []
    @State private var mode: PasteMode = .merge

    var body: some View {
        VStack(spacing: 12) {
            Text("paste_partial_title")
                .font(.headline)
                .accessibilityIdentifier("paste.partial.title")

            modePicker

            List(payload.instances, id: \.id) { instance in
                let key = PastePayload.InstanceKey(instance)
                Toggle(isOn: binding(for: key)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ModuleTitles.label(for: instance.opName))
                        if !instance.multiName.isEmpty {
                            Text(instance.multiName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier(
                    "paste.partial.row.\(instance.opName).\(instance.multiPriority)")
            }
            .frame(minHeight: 220)

            HStack {
                Button(String(localized: "paste_partial_check_all")) {
                    checked = Set(payload.instanceKeys)
                }
                .accessibilityIdentifier("paste.partial.checkall")
                Button(String(localized: "paste_partial_check_none")) {
                    checked = []
                }
                .accessibilityIdentifier("paste.partial.checknone")
                Spacer()
                Button(String(localized: "alert_ok")) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "paste_partial_paste_button")) {
                    onPaste(checked, mode)
                }
                .disabled(checked.isEmpty)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("paste.partial.confirm")
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            checked = initialSelection ?? Set(payload.instanceKeys)
        }
    }

    private var modePicker: some View {
        Picker(String(localized: "paste_partial_mode_label"), selection: $mode) {
            Text("paste_partial_mode_merge").tag(PasteMode.merge)
            Text("paste_partial_mode_overwrite").tag(PasteMode.overwrite)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("paste.partial.mode")
    }

    private func binding(for key: PastePayload.InstanceKey) -> Binding<Bool> {
        Binding(
            get: { checked.contains(key) },
            set: { isOn in
                if isOn {
                    checked.insert(key)
                } else {
                    checked.remove(key)
                }
            })
    }
}
