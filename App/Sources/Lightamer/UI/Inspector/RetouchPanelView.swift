import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// RetouchPanelView (Plan 06-07 T4, IOP-GEO-06, D-06-CONTEXT-4) — the
// Inspector surface for the SELECTED RETOUCH layer: the algorithm Picker
// (dt's module-level `algorithm` default = heal), the per-algorithm
// parameters (blur sigma / fill color), the stroke radius / feather /
// opacity tools, and the stroke list with per-stroke delete.
//
// The stroke EDIT itself lives on the viewport (RetouchOverlayHost — dt's
// on-canvas painting); the panel is the tool + list surface. NO_MASKS
// (dt retouch.c:221): there is no mask section — the stroke shapes ARE
// the mask (the doc comment pins the v1 contract).
//
// 面板四件套 (the hard checklist): L010 accessibilityIdentifiers
// (inspector.retouch.*) + zh/en String Catalog (every label below) +
// 280pt Inspector constraint (Form in the existing column; never grows
// the viewport) + D-H1 (radius/feather/opacity drags render live via
// `applyLiveRetouch` and commit EXACTLY ONE structure item at release;
// Picker/button/discrete edits commit once).
// ─────────────────────────────────────────────────────────────────────────

internal struct RetouchPanelView: View {

    /// The LIVE retouch layer (re-read from EditorState each render —
    /// strokes are value records swapped wholesale).
    let layer: RetouchLayer

    @Environment(EditorState.self) private var editorState
    @Environment(LayerEditingState.self) private var editingState

    /// The stroke the per-stroke controls edit (panel-local selection;
    /// mirrors the LiquifyPanelView node-selection pattern, D-06-06-T4-1).
    @State private var selectedStrokeID: UUID?

    private var strokes: [RetouchStroke] { layer.strokes }

    private var selectedStroke: RetouchStroke? {
        if let id = selectedStrokeID, strokes.contains(where: { $0.id == id }) {
            return strokes.first { $0.id == id }
        }
        return strokes.last
    }

    var body: some View {
        Form {
            Section {
                algorithmPicker
                toolSliders
                if editingState.retouchAlgorithm == .blur {
                    blurSlider
                }
                if editingState.retouchAlgorithm == .fill {
                    fillSlider
                }
                sourcePickToggle
                overlayHint
            } header: {
                Text("panel_retouch_section")
            }

            Section {
                if strokes.isEmpty {
                    Text("panel_retouch_no_strokes")
                        .font(.caption)
                        .foregroundStyle(LightamerColors.textTertiary)
                } else {
                    strokeList
                    if let stroke = selectedStroke {
                        strokeOpacitySlider(stroke)
                        Button("panel_retouch_delete_stroke", role: .destructive) {
                            deleteStroke(stroke)
                        }
                        .accessibilityIdentifier("inspector.retouch.deleteStroke")
                    }
                }
            } header: {
                Text("panel_retouch_strokes_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.retouch")
    }

    // MARK: tools

    private var algorithmPicker: some View {
        Picker("panel_retouch_algorithm", selection: Binding(
            get: { editingState.retouchAlgorithm },
            set: { editingState.retouchAlgorithm = $0 }
        )) {
            Text("panel_retouch_clone").tag(RetouchAlgorithm.clone)
            Text("panel_retouch_heal").tag(RetouchAlgorithm.heal)
            Text("panel_retouch_blur").tag(RetouchAlgorithm.blur)
            Text("panel_retouch_fill").tag(RetouchAlgorithm.fill)
        }
        .accessibilityIdentifier("inspector.retouch.algorithm")
    }

    private var toolSliders: some View {
        VStack(spacing: 0) {
            LightamerSlider(
                label: String(localized: "panel_retouch_radius"),
                value: Double(editingState.retouchRadius) * 100,
                range: 1...30,
                defaultValue: 6,
                readoutFormat: "%.1f",
                unit: "",
                onDragBegin: {},
                onChange: { value in editingState.retouchRadius = Float(value) / 100 },
                onDragEnd: {},
                onReset: { editingState.retouchRadius = 0.06 },
                accessibilityID: "inspector.retouch.radius"
            )
            LightamerSlider(
                label: String(localized: "panel_retouch_feather"),
                value: Double(editingState.retouchFeather) * 100,
                range: 0...60,
                defaultValue: 15,
                readoutFormat: "%.1f",
                unit: "",
                onDragBegin: {},
                onChange: { value in editingState.retouchFeather = Float(value) / 100 },
                onDragEnd: {},
                onReset: { editingState.retouchFeather = 0.15 },
                accessibilityID: "inspector.retouch.feather"
            )
        }
    }

    private var blurSlider: some View {
        LightamerSlider(
            label: String(localized: "panel_retouch_blur_radius"),
            value: Double(editingState.retouchBlurRadius),
            range: 1...50,
            defaultValue: 10,
            readoutFormat: "%.1f",
            unit: "",
            onDragBegin: {},
            onChange: { value in editingState.retouchBlurRadius = Float(value) },
            onDragEnd: {},
            onReset: { editingState.retouchBlurRadius = 10 },
            accessibilityID: "inspector.retouch.blurRadius"
        )
    }

    private var fillSlider: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("panel_retouch_fill_color")
                .font(.caption)
            ColorPicker(
                String(localized: "panel_retouch_fill_color"),
                selection: Binding(
                    get: {
                        let c = editingState.retouchFillColor
                        // sRGB display-space pick folded to linear Rec2020
                        // is the export leg's business; the panel edits the
                        // RAW linear value through an sRGB approximation —
                        // the Manual-Only register covers the perceived
                        // accuracy (D-06-07-T4-1).
                        return Color(
                            red: Double(c.x), green: Double(c.y), blue: Double(c.z))
                    },
                    set: { color in
                        #if canImport(AppKit)
                        let ns = NSColor(color)
                        let converted = ns.usingColorSpace(.sRGB) ?? ns
                        editingState.retouchFillColor = SIMD3(
                            Float(converted.redComponent),
                            Float(converted.greenComponent),
                            Float(converted.blueComponent))
                        #endif
                    }),
                supportsOpacity: false)
                .labelsHidden()
                .accessibilityIdentifier("inspector.retouch.fillColor")
        }
    }

    private var sourcePickToggle: some View {
        Toggle(isOn: Binding(
            get: { editingState.retouchSourcePickArmed },
            set: { editingState.retouchSourcePickArmed = $0 }
        )) {
            Text("panel_retouch_pick_source")
        }
        .accessibilityIdentifier("inspector.retouch.pickSource")
    }

    private var overlayHint: some View {
        Text("panel_retouch_overlay_hint")
            .font(.caption2)
            .foregroundStyle(LightamerColors.textTertiary)
    }

    // MARK: stroke list

    private var strokeList: some View {
        ForEach(strokes.reversed()) { stroke in
            HStack(spacing: 6) {
                Image(systemName: Self.icon(stroke.algorithm))
                    .font(.caption)
                    .foregroundStyle(LightamerColors.textSecondary)
                Text(Self.strokeLabel(stroke))
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                if selectedStroke?.id == stroke.id {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(
                selectedStroke?.id == stroke.id
                    ? LightamerColors.accent.opacity(0.2)
                    : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { selectedStrokeID = stroke.id }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("inspector.retouch.stroke.\(stroke.id.uuidString)")
        }
    }

    /// The selected stroke's opacity ceiling (D-H1: live ticks + ONE
    /// commit at release).
    private func strokeOpacitySlider(_ stroke: RetouchStroke) -> some View {
        LightamerSlider(
            label: String(localized: "panel_retouch_stroke_opacity"),
            value: Double(stroke.opacity),
            range: 0...1,
            defaultValue: 1,
            readoutFormat: "%.2f",
            unit: "",
            onDragBegin: {},
            onChange: { value in
                mutateStroke(stroke.id) { $0.opacity = Float(value) }
            },
            onDragEnd: {
                if let live = editorState.retouchLayer(id: layer.id) {
                    editorState.commitRetouchEdit(
                        live, label: String(localized: "history_retouch_stroke"))
                }
            },
            onReset: nil,
            accessibilityID: "inspector.retouch.strokeOpacity"
        )
    }

    // MARK: mutations

    /// Live-tick a stroke mutation (zero history — the caller commits once).
    private func mutateStroke(_ id: UUID, _ mutate: (inout RetouchStroke) -> Void) {
        let copy = layer
        var strokes = copy.strokes
        guard let index = strokes.firstIndex(where: { $0.id == id }) else { return }
        mutate(&strokes[index])
        let updated = RetouchLayer(
            id: copy.id, name: copy.name, isVisible: copy.isVisible,
            opacity: copy.opacity, blendMode: copy.blendMode,
            blendOptions: copy.blendOptions, enabled: copy.enabled,
            strokes: strokes)
        editorState.applyLiveRetouch(updated)
    }

    private func deleteStroke(_ stroke: RetouchStroke) {
        var strokes = layer.strokes
        strokes.removeAll { $0.id == stroke.id }
        let updated = RetouchLayer(
            id: layer.id, name: layer.name, isVisible: layer.isVisible,
            opacity: layer.opacity, blendMode: layer.blendMode,
            blendOptions: layer.blendOptions, enabled: layer.enabled,
            strokes: strokes)
        editorState.commitRetouchEdit(
            updated, label: String(localized: "history_retouch_stroke"))
        selectedStrokeID = nil
    }

    // MARK: labels

    static func icon(_ algorithm: RetouchAlgorithm) -> String {
        switch algorithm {
        case .clone: return "rectangle.on.rectangle"
        case .heal: return "cross.vial" // GUI-14 family: verified-present glyphs only
        case .blur: return "drop.halffull"
        case .fill: return "square.fill" // GUI-14 family: "paintbucket" is MISSING on this OS
        }
    }

    static func strokeLabel(_ stroke: RetouchStroke) -> String {
        let algorithm: String = switch stroke.algorithm {
        case .clone: String(localized: "panel_retouch_clone")
        case .heal: String(localized: "panel_retouch_heal")
        case .blur: String(localized: "panel_retouch_blur")
        case .fill: String(localized: "panel_retouch_fill")
        }
        return "\(algorithm) \(stroke.centerString)"
    }
}

extension RetouchStroke {
    /// The list-row coordinate readout (percentages, 1 decimal).
    var centerString: String {
        let c = formAnchorPoint
        return String(format: "%.0f,%.0f%%", c.x * 100, c.y * 100)
    }

    /// The stroke's anchor in normalized coords (the ellipse center or the
    /// path node centroid — the same anchor the engine clones relative to).
    var formAnchorPoint: SIMD2<Float> {
        switch form.kind {
        case let .ellipse(e): return SIMD2(e.center.x, e.center.y)
        case let .path(p):
            guard !p.nodes.isEmpty else { return .zero }
            let sum = p.nodes.reduce(SIMD2<Float>.zero) {
                $0 + SIMD2($1.corner.x, $1.corner.y)
            }
            return sum / Float(p.nodes.count)
        case .brush, .gradient: return .zero
        }
    }
}
