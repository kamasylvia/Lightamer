import AppKit
import LightamerCore
import LightamerIOP
import SwiftUI

/// Editor center column: empty state ↔ Metal viewport (D-11/D-13).
///
/// D-03b: injects ONLY `EditorState` (+ the `PipeCoordinator` via the
/// environment and the app-owned `decoder`/`metalContext` passed down from
/// the app root). The loaded branch renders `EditorMTKView` (Plan 03) over
/// `EditorState.displayTexture` — a DISPLAY-ONLY view: it never initiates a
/// render. The sole producer of `displayTexture` is the PipeCoordinator's
/// `renderPreview` (D-X1; a second, view-level render producer was issue
/// #1's race — re-introducing one is the exact bug this fixes).
///
/// The ONE thing this view sends the coordinator is viewport GEOMETRY
/// (`drawableDidChange`) — an input event, not a render trigger; the
/// coordinator decides whether the D-C3 bucket crossed (and only then
/// re-renders, through its own single render path).
internal struct EditorAreaView: View {

    /// The app-owned decode actor (D-21), passed through to `EditorState.load`
    /// for the empty-state open path.
    let decoder: RAWDecoder

    /// The app-owned Metal context (D-14/15); nil = no GPU (fatal alert is
    /// hosted by `ContentView` per UI-SPEC Error Messages).
    let metalContext: MetalContext?
    /// The multi-resolution pipe owner (Plan 02-03-04) — receives the
    /// geometry input events only.
    @Environment(PipeCoordinator.self) private var pipeCoordinator

    /// T0 live state: true between overlay `onBegin` and `onCommit`
    /// (crop disabled + scrim). View-local mirror of the coordinator's
    /// `isEditingContinuous` window.
    @State private var isCropDragging = false
    @Environment(EditorState.self) private var editorState

    /// D-T4 eyedropper mode (Plan 03-02-T5): the crosshair + click routing
    /// state lives here, the sampling in the coordinator.
    @Environment(InspectorState.self) private var inspectorState

    /// 06-05: the layer-editing state machine — the viewport gesture
    /// arbitration归口 (mask tools / liquify / crop, exactly one owner).
    @Environment(LayerEditingState.self) private var editingState

    var body: some View {
        @Bindable var editorState = editorState
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack {
                    if editorState.loadedImageURL == nil {
                        EmptyStateView(onOpen: {
                            editorState.load(
                                url: $0,
                                decoder: decoder,
                                metal: metalContext,
                                logger: EditorState.decodeLogger
                            )
                        })
                            .transition(.opacity)
                    } else if let metalContext {
                        EditorMTKView(
                            device: metalContext.device,
                            commandQueue: metalContext.commandQueue,
                            sourceTexture: $editorState.displayTexture
                        )
                        .transition(.opacity)
                        .accessibilityLabel(Text("editor_viewport"))
                        // 06-05: the overlay OWNER is the editing state
                        // machine's single decision (exactly one of the
                        // three routes is active — the mutex invariant).
                        .overlay {
                            GeometryReader { overlayGeo in
                                switch viewportRoute {
                                case .maskEditing:
                                    MaskOverlayHost(
                                        viewportSize: overlayGeo.size,
                                        displaySize: displayPixelSize)
                                case .liquify:
                                    LiquifyOverlayHost(
                                        viewportSize: overlayGeo.size,
                                        displaySize: displayPixelSize,
                                        liquifyRecord: liquifyRecord,
                                        onBegin: {
                                            pipeCoordinator.beginContinuousEdit()
                                        },
                                        onLive: { snapshot in
                                            Task { await pipeCoordinator.setLiveParams(snapshot) }
                                        },
                                        onCommit: { snapshot, label in
                                            Task { await pipeCoordinator.setLiveParams(snapshot) }
                                            Task { await pipeCoordinator.commitContinuousEdit(label: label) }
                                        }
                                    )
                                case .retouch:
                                    // 06-07: the retouch stroke editor owns the
                                    // viewport while the selected layer is a
                                    // retouch kind (its edits route through
                                    // EditorState's structure commits, not the
                                    // coordinator's param paths).
                                    if let retouch = retouchLayer {
                                        RetouchOverlayHost(
                                            viewportSize: overlayGeo.size,
                                            displaySize: displayPixelSize,
                                            layer: retouch)
                                    } else {
                                        CropOverlayHost(
                                            viewportSize: overlayGeo.size,
                                            displaySize: displayPixelSize,
                                            cropRecord: cropRecord,
                                            isDragging: isCropDragging,
                                            onBegin: { isCropDragging = true },
                                            onLive: { _ in },
                                            onCommit: { _, _ in })
                                    }
                                case .crop:
                                    CropOverlayHost(
                                        viewportSize: overlayGeo.size,
                                        displaySize: displayPixelSize,
                                        cropRecord: cropRecord,
                                        isDragging: isCropDragging,
                                        onBegin: {
                                            isCropDragging = true
                                            pipeCoordinator.beginContinuousEdit()
                                        },
                                        onLive: { snapshot in
                                            Task { await pipeCoordinator.setLiveParams(snapshot) }
                                        },
                                        onCommit: { snapshot, label in
                                            isCropDragging = false
                                            Task { await pipeCoordinator.setLiveParams(snapshot) }
                                            Task { await pipeCoordinator.commitContinuousEdit(label: label) }
                                        }
                                    )
                                }
                            }
                        }
                        // 06-05 T3.1: the mask toolbar — a floating strip at
                        // the viewport's BOTTOM EDGE (never grows the
                        // Inspector; the viewport keeps its ≥50% share).
                        .overlay(alignment: .bottom) {
                            if editorState.loadedImageURL != nil {
                                MaskToolbarView()
                            }
                        }
                    } else {
                        Color.clear
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // VoiceOver/XCUITest. NO accessibilityLabel here — a
                // container label absorbs the child elements (the
                // empty-state card would vanish from the AX tree); the
                // MTKView carries its own label in the loaded state.
                .accessibilityIdentifier("Image viewport")
                .animation(.easeInOut(duration: 0.2), value: editorState.loadedImageURL)
                // Geometry → the coordinator's bucket re-evaluation (D-C3).
                // Fire-and-forget Task: the view NEVER awaits or renders.
                // POINT sizes are passed through (the bucket function owns
                // the backing-scale conversion). Also fires on APPEAR so
                // the load-time cap-bucket render reconciles to the actual
                // window bucket even without a user resize.
                .onChange(of: geo.size) { _, newSize in
                    sendDrawableGeometry(newSize)
                }
                .onAppear { sendDrawableGeometry(geo.size) }
                // D-T4 eyedropper: when armed, a click routes into the
                // coordinator's PREVIEW sampling (an INPUT event — the view
                // never renders) and the mode disarms itself in
                // `InspectorState.completeEyedropper`. Crosshair cursor via
                // AppKit (SwiftUI has no view-level cursor modifier on macOS).
                .onHover { hovering in
                    guard inspectorState.isEyedropperActive else { return }
                    if hovering {
                        NSCursor.crosshair.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            guard inspectorState.isEyedropperActive else { return }
                            let point = value.location
                            Task {
                                if let picked = await pipeCoordinator.pickColor(
                                    at: point, viewportSize: geo.size
                                ) {
                                    inspectorState.completeEyedropper(with: picked)
                                }
                            }
                        }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(LightamerColors.canvas)
    }

    /// Viewport POINT-size long edge → the coordinator's bucket
    /// re-evaluation. `PreviewBucket.longEdge(forDrawable:pixelScale:)`
    /// applies the backing scale ITSELF (contract: callers pass POINTS —
    /// doubling here would double-scale and pin every bucket at the cap).
    /// This is an INPUT event: the coordinator decides whether the D-C3
    /// bucket crossed and only then re-renders.
    private func sendDrawableGeometry(_ size: CGSize) {
        let longEdge = Int(max(size.width, size.height).rounded())
        guard longEdge > 0 else { return }
        Task { await pipeCoordinator.drawableDidChange(drawableLongEdge: longEdge) }
    }

    // MARK: - 06-05 viewport route (the state machine's decision)

    /// Exactly ONE owner for the viewport overlay (the mutex invariant):
    /// mask tools > liquify panel > retouch panel > crop. The liquify/
    /// retouch routes keep their selected-panel rules but route THROUGH
    /// the machine.
    private var viewportRoute: LayerEditingState.ViewportRoute {
        editingState.viewportRoute(
            liquifyPanelSelected: liquifyActive,
            retouchPanelSelected: retouchLayer != nil)
    }

    /// The selected RETOUCH layer (nil = the retouch route stays off).
    private var retouchLayer: RetouchLayer? {
        guard let id = editingState.selectedLayerID else { return nil }
        return editorState.retouchLayer(id: id)
    }

    // MARK: - 04-02-T4 crop overlay inputs (D-G6)

    /// The crop record (nil ⇒ no overlay). Read from the live instance
    /// set — the panel (T5) and overlay share this record (single source).
    private var cropRecord: ModuleInstance? {
        editorState.instances.first { $0.opName == CropModule.opName }
    }

    // MARK: - 06-06-T4 liquify overlay (mutual exclusion with crop)

    /// The liquify record (the seed always carries one — enabled-neutral).
    private var liquifyRecord: ModuleInstance? {
        editorState.instances.first { $0.opName == LiquifyModule.opName }
    }

    /// The liquify node editor owns the viewport while the liquify panel is
    /// the SELECTED Inspector surface (the v1 gesture-exclusion state
    /// machine, DECISIONS D-06-06-T4-3 — the crop overlay returns when any
    /// other panel is selected).
    private var liquifyActive: Bool {
        inspectorState.selectedPanel == liquifyRecord?.id.uuidString
    }

    /// The display texture's pixel size (upstream geometry for the fitted
    /// rect + the `original` preset). Nil-texture ⇒ zero size ⇒ no overlay.
    private var displayPixelSize: CGSize {
        guard let tex = editorState.displayTexture else { return .zero }
        return CGSize(width: tex.width, height: tex.height)
    }
}
