import LightamerCore
import LightamerIOP
import simd
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// Liquify panel (Plan 06-06-T4, IOP-GEO-05) — the Inspector surface for the
// liquify warp: node list (dt MAX_NODES=100 cap surfaced as UI state), the
// selected node's warp type / strength / radius controls, and the overlay
// hint. dt reference: liquify.c CONF_RADIUS/ANGLE/STRENGTH defaults + the
// warp-type enum (:218-223); Lightamer presents them per selected node
// (dt's on-canvas handles map 1:1 to the overlay's drag handles — T4).
//
// D-H1 wiring: sliders map the continuous trio (drag = live ticks, release =
// exactly ONE commit); the warp-type Picker / add / delete are discrete
// one-commit edits. Values READ from the instance record
// (PanelEditing pattern); geometry lives in NORMALIZED entry-frame
// fractions (D-06-06-T1-1), so the sliders are resolution-independent.
// ─────────────────────────────────────────────────────────────────────────

internal struct LiquifyPanelView: View {

    let instance: ModuleInstance
    let edit: InspectorEditSession

    /// The node the type/strength/radius controls edit (panel-local
    /// selection; the overlay's drag does not move it — v1 simplification,
    /// DECISIONS D-06-06-T4-1).
    @State private var selectedNode: Int = 0

    private var params: LiquifyModule.Params {
        PanelEditing.params(of: instance, as: LiquifyModule.self) ?? .init()
    }

    private var clampedSelection: Int {
        min(max(selectedNode, 0), max(0, params.paths.count - 1))
    }

    var body: some View {
        Form {
            Section {
                if params.paths.isEmpty {
                    Text("panel_liquify_no_nodes")
                        .font(.caption)
                        .foregroundStyle(LightamerColors.textTertiary)
                } else {
                    Picker("panel_liquify_nodes", selection: nodeSelection) {
                        ForEach(params.paths.indices, id: \.self) { index in
                            Text("panel_liquify_node_n \(index + 1)")
                                .tag(index)
                        }
                    }
                    .accessibilityIdentifier("inspector.liquify.nodePicker")

                    warpTypePicker
                    strengthSlider
                    radiusSlider

                    Button("panel_liquify_delete_node", role: .destructive) {
                        deleteSelectedNode()
                    }
                    .accessibilityIdentifier("inspector.liquify.deleteNode")
                }

                Button("panel_liquify_add_node") {
                    addNode()
                }
                .disabled(params.paths.count >= LiquifyPathData.maxNodes)
                .accessibilityIdentifier("inspector.liquify.addNode")

                if params.paths.count >= LiquifyPathData.maxNodes {
                    Text("panel_liquify_node_cap")
                        .font(.caption2)
                        .foregroundStyle(LightamerColors.textTertiary)
                }

                Text("panel_liquify_overlay_hint")
                    .font(.caption2)
                    .foregroundStyle(LightamerColors.textTertiary)
            } header: {
                Text("panel_liquify_section")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LightamerColors.surface)
        .accessibilityIdentifier("inspector.panel.liquify")
    }

    // MARK: controls

    private var nodeSelection: Binding<Int> {
        Binding(
            get: { clampedSelection },
            set: { selectedNode = $0 }
        )
    }

    @ViewBuilder
    private var warpTypePicker: some View {
        let index = clampedSelection
        if params.paths.indices.contains(index) {
            Picker("panel_liquify_warp_type", selection: Binding(
                get: { params.paths[index].warpType },
                set: { newType in
                    applyDiscrete { $0.paths[index].warpType = newType }
                }
            )) {
                Text("panel_liquify_linear").tag(LiquifyWarpType.linear)
                Text("panel_liquify_radial_grow").tag(LiquifyWarpType.radialGrow)
                Text("panel_liquify_radial_shrink").tag(LiquifyWarpType.radialShrink)
            }
            .accessibilityIdentifier("inspector.liquify.warpType")
        }
    }

    /// The selected node's strength magnitude (|strength − point|, frame
    /// fractions ×100 for a 0…20 slider readout).
    @ViewBuilder
    private var strengthSlider: some View {
        let index = clampedSelection
        if params.paths.indices.contains(index) {
            let node = params.paths[index]
            LightamerSlider(
                label: String(localized: "panel_liquify_strength"),
                value: Double((node.strengthVector.x * node.strengthVector.x
                    + node.strengthVector.y * node.strengthVector.y).squareRoot()) * 100,
                range: 0...20,
                defaultValue: 0,
                readoutFormat: "%.2f",
                unit: "",
                onDragBegin: { edit.beginEditing() },
                onChange: { value in
                    applyLive { $0.setStrengthMagnitude(Double(value) / 100, node: index) }
                },
                onDragEnd: { edit.endEditing(label: String(localized: "history_liquify")) },
                onReset: {
                    applyDiscrete { $0.setStrengthMagnitude(0, node: index) }
                },
                accessibilityID: "inspector.liquify.strength"
            )
        }
    }

    /// The selected node's radius scalar (frame fraction ×100).
    @ViewBuilder
    private var radiusSlider: some View {
        let index = clampedSelection
        if params.paths.indices.contains(index) {
            let node = params.paths[index]
            LightamerSlider(
                label: String(localized: "panel_liquify_radius"),
                value: Double(node.radiusScalar) * 100,
                range: 1...40,
                defaultValue: 8,
                readoutFormat: "%.1f",
                unit: "",
                onDragBegin: { edit.beginEditing() },
                onChange: { value in
                    applyLive { $0.setRadius(Double(value) / 100, node: index) }
                },
                onDragEnd: { edit.endEditing(label: String(localized: "history_liquify")) },
                onReset: nil,
                accessibilityID: "inspector.liquify.radius"
            )
        }
    }

    // MARK: mutation helpers (the D-H1 record flow)

    private func applyLive(_ mutate: (inout LiquifyModule.Params) -> Void) {
        var params = params
        mutate(&params)
        if let record = PanelEditing.updated(instance, params: params, as: LiquifyModule.self) {
            edit.update(record)
        }
    }

    private func applyDiscrete(_ mutate: (inout LiquifyModule.Params) -> Void) {
        var params = params
        mutate(&params)
        if let record = PanelEditing.updated(instance, params: params, as: LiquifyModule.self) {
            edit.applyDiscrete(record, label: String(localized: "history_liquify"))
        }
    }

    private func addNode() {
        applyDiscrete { params in
            // A fresh node lands at the frame center with a usable radius
            // (dt's CONF_RADIUS default ≈ 100 px of a ~1000 px canvas →
            // 0.1 of the frame) and a no-op strength (init_warp semantics).
            params.paths.append(.moveTo(
                SIMD2(0.5, 0.5), warpType: .radialGrow))
            params.paths[params.paths.count - 1].radius = SIMD2(0.6, 0.5)
            selectedNode = params.paths.count - 1
        }
    }

    private func deleteSelectedNode() {
        let index = clampedSelection
        guard params.paths.indices.contains(index) else { return }
        applyDiscrete { params in
            params.paths.remove(at: index)
        }
        selectedNode = max(0, selectedNode - 1)
    }
}

extension LiquifyModule.Params {
    /// Rescale the strength handle to `magnitude` along its current
    /// direction (a zero vector grows along +x).
    mutating func setStrengthMagnitude(_ magnitude: Double, node index: Int) {
        guard paths.indices.contains(index) else { return }
        let vector = paths[index].strengthVector
        let current = (vector.x * vector.x + vector.y * vector.y).squareRoot()
        let scale = current > 1e-9 ? Float(magnitude) / current : Float(magnitude)
        paths[index].strength = paths[index].point + SIMD2<Float>(vector.x, vector.y) * scale
    }

    /// Rescale the radius handle to `radius` (fractions of the frame).
    mutating func setRadius(_ radius: Double, node index: Int) {
        guard paths.indices.contains(index) else { return }
        paths[index].radius = paths[index].point + SIMD2<Float>(Float(radius), 0)
    }
}

internal struct LiquifyPanelProvider: IOPPanelProvider {
    var opName: String { LiquifyModule.opName }
    func panel(for instance: ModuleInstance, edit: InspectorEditSession) -> AnyView {
        AnyView(LiquifyPanelView(instance: instance, edit: edit))
    }
}
