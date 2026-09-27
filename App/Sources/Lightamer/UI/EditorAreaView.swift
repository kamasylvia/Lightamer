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

    /// 13-3 T1/T3: the zoom/pan/rotation state — the eyedropper samples
    /// through its inverse map and the overlay mutex rides its lock.
    @Environment(ViewportState.self) private var viewportState

    /// 13-3 T4: the empty-state drop routes a FOLDER to the session-open
    /// flow (the 「文件夹→会话」 path) and FILES to the single-image edit.
    @Environment(SessionCoordinator.self) private var sessionCoordinator

    /// 09-04 T7 (HIST-06): the before/after presentation state (split /
    /// peek / hold) + the fetched compare plane (a resident cache line —
    /// fetched ONCE per activation, never re-rendered by the hold edge).
    @Environment(BeforeAfterState.self) private var beforeAfterState
    @State private var comparePlane: (any MTLTexture)?

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
                        }, onDropURLs: { urls in
                            routeDroppedURLs(urls)
                        })
                            .transition(.opacity)
                    } else if let metalContext {
                        EditorMTKView(
                            device: metalContext.device,
                            commandQueue: metalContext.commandQueue,
                            sourceTexture: $editorState.displayTexture,
                            secondaryTexture: beforeAfterState.isCompareActive ? comparePlane : nil,
                            splitFraction: beforeAfterState.isCompareActive
                                ? beforeAfterState.effectiveSplitFraction : nil
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
                                case .segment:
                                    // 07-3 T2: the tap-to-segment editor
                                    // (the 4th route — layer B refine
                                    // points + confirm re-bake).
                                    SegmentEditingOverlayHost(
                                        viewportSize: overlayGeo.size,
                                        displaySize: displayPixelSize,
                                        metalContext: metalContext)
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
                                MaskToolbarView(metalContext: metalContext)
                            }
                        }
                        // 09-04 T7 (HIST-06): the compare HUD — a floating
                        // strip at the viewport's TOP EDGE while a
                        // before/after form is active (compare point + peek
                        // stepper + the split-line drag handle).
                        .overlay(alignment: .top) {
                            if beforeAfterState.splitEnabled {
                                BeforeAfterHUD()
                            }
                        }
                        // 13-3 T2 (SYS-03): the zoom HUD — a floating
                        // capsule at the viewport's TOP-LEADING corner
                        // (the state's value + the fit/100% switches; the
                        // percentage label's double-click resets rotation).
                        .overlay(alignment: .topLeading) {
                            if editorState.loadedImageURL != nil {
                                ZoomHUD(
                                    viewportSize: geo.size,
                                    textureSize: displayPixelSize)
                                    .padding(.top, 8)
                                    .padding(.leading, 12)
                            }
                        }
                        // 13-2 T4 (COLOR-02): the soft-proof capsule — a
                        // floating top-trailing control (toggle + printer
                        // picker + gamut check; the same SoftProofState the
                        // View menu drives).
                        .overlay(alignment: .topTrailing) {
                            SoftProofControlView()
                                .padding(.top, 8)
                                .padding(.trailing, 12)
                        }
                        // The compare plane lifecycle: fetched through the
                        // coordinator's OVERRIDE render on activation /
                        // peek change ONLY (the hold edges never re-fetch —
                        // the plane is resident; zero-render fast path).
                        .task(id: beforeAfterTaskKey) {
                            guard beforeAfterState.isCompareActive else { return }
                            if beforeAfterState.peekIndex == nil {
                                comparePlane = try? await pipeCoordinator.renderPristinePlane()
                            } else {
                                comparePlane = try? await pipeCoordinator.renderHistoryPeekPlane(
                                    at: beforeAfterState.peekIndex!)
                            }
                        }
                        // 13-3 T4: the EDITOR-AREA drop = single-image
                        // direct edit (the existing `EditorState.load`
                        // path; the sidecar lands beside the ORIGINAL —
                        // no import, no index row, D-13-CONTEXT-7①).
                        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                            SessionBrowserView.loadDropURLs(providers: providers) { urls in
                                guard let first = urls.first else { return }
                                editorState.load(
                                    url: first,
                                    decoder: decoder,
                                    metal: metalContext,
                                    logger: EditorState.decodeLogger
                                )
                            }
                            return true
                        }
                        // The hold key (`\`, the C1 habit): key-down flips
                        // the blit to the resident before plane, key-up
                        // flips back — a CONSTANT blit switch (no render,
                        // no history item).
                        .onAppear { installHoldMonitor() }
                        .onDisappear { removeHoldMonitor() }
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
                            // 13-3 T3: the click inverse-maps through the
                            // zoom/pan/rotation state (the same ViewportFit
                            // math; nil transform = the untouched fit path).
                            let xf = viewportState.transform(
                                viewportSize: geo.size,
                                textureSize: displayPixelSize)
                            Task {
                                if let picked = await pipeCoordinator.pickColor(
                                    at: point, viewportSize: geo.size,
                                    transform: xf
                                ) {
                                    inspectorState.completeEyedropper(with: picked)
                                }
                            }
                        }
                )
                // 13-3 T3 (D-13-CONTEXT-6③): the overlay MUTEX — when a
                // viewport-exclusive overlay owns the route (crop /
                // liquify / retouch), the zoom state LOCKS to the fit
                // identity (entering the lock snaps back; gestures are
                // swallowed while set). The mask/segment routes stay free
                // — they inverse-map through the transform.
                .onChange(of: viewportRoute) { _, route in
                    viewportState.setZoomLocked(Self.routeLocksZoom(route))
                }
                .onAppear {
                    viewportState.setZoomLocked(Self.routeLocksZoom(viewportRoute))
                }
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

    // MARK: - 13-3 T4 drop routing (empty state)

    /// The empty-state drop router: a FOLDER opens the 「文件夹→会话」
    /// flow (the existing openSession orchestration); files edit the
    /// FIRST directly (the single-image path — the rest are ignored,
    /// execution decision 13-3-DECISIONS).
    private func routeDroppedURLs(_ urls: [URL]) {
        guard let first = urls.first else { return }
        let isDirectory = (try? first.resourceValues(forKeys: [.isDirectoryKey]))?
            .isDirectory ?? false
        if isDirectory {
            Task { await sessionCoordinator.openSession(url: first) }
        } else {
            editorState.load(
                url: first,
                decoder: decoder,
                metal: metalContext,
                logger: EditorState.decodeLogger
            )
        }
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

    /// 13-3 T3: the routes whose overlay geometry assumes the FIT layout
    /// lock the zoom state (D-13-CONTEXT-6③, v1 从简 — crop-while-zoomed
    /// is the recorded v2順位). Mask editing and the segment taps are NOT
    /// here: they inverse-map through `ViewportFit`.
    static func routeLocksZoom(_ route: LayerEditingState.ViewportRoute) -> Bool {
        switch route {
        case .crop, .liquify, .retouch: return true
        case .maskEditing, .segment: return false
        }
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

    // MARK: - 09-04 T7 before/after legs

    /// The fetch-trigger key (the .task(id:) identity): re-fetches the
    /// compare plane only on activation/peek/point/image changes.
    private var beforeAfterTaskKey: String {
        let split = beforeAfterState.splitEnabled
        let peek = beforeAfterState.peekIndex ?? -1
        let url = editorState.loadedImageURL?.absoluteString ?? "none"
        return "\(split)|\(peek)|\(url)"
    }

    @State private var holdMonitor: Any?

    private func installHoldMonitor() {
        guard holdMonitor == nil else { return }
        holdMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            guard event.charactersIgnoringModifiers == "\\",
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            else { return event }
            switch event.type {
            case .keyDown:
                if !beforeAfterState.isHoldingOriginal {
                    beforeAfterState.isHoldingOriginal = true
                }
                return nil // consumed — the hold is viewport-local
            case .keyUp:
                if beforeAfterState.isHoldingOriginal {
                    beforeAfterState.isHoldingOriginal = false
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeHoldMonitor() {
        if let monitor = holdMonitor {
            NSEvent.removeMonitor(monitor)
        }
        holdMonitor = nil
        beforeAfterState.isHoldingOriginal = false
    }
}

/// The zoom HUD (13-3 T2): the current zoom state/value + the fit/100%
/// switches. Form (execution decision, 13-3-DECISIONS): a compact capsule
/// — [−] [label] [+] | [fit] [1:1]; the label reads "Fit" in the fit mode,
/// "100%" pinned at the hundred-percent state, and the free percentage
/// otherwise; double-clicking the label resets the rotation (anchored at
/// the viewport center). Locked (a viewport-exclusive overlay) the whole
/// HUD disables — the mutex is the state machine's decision.
internal struct ZoomHUD: View {

    let viewportSize: CGSize
    let textureSize: CGSize

    @Environment(ViewportState.self) private var viewportState

    var body: some View {
        HStack(spacing: 8) {
            Button {
                viewportState.stepZoom(
                    factor: 1 / 1.25,
                    viewportSize: viewportSize, textureSize: textureSize)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("zoom_hud_zoom_out"))
            .accessibilityIdentifier("zoom.hud.decrease")

            Text(label)
                .monospacedDigit()
                .frame(minWidth: 44)
                .onTapGesture(count: 2) {
                    viewportState.resetRotation(
                        viewportSize: viewportSize, textureSize: textureSize)
                }
                .accessibilityLabel(Text("zoom_hud_level"))
                .accessibilityValue(label)
                .accessibilityIdentifier("zoom.hud.label")

            Button {
                viewportState.stepZoom(
                    factor: 1.25,
                    viewportSize: viewportSize, textureSize: textureSize)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("zoom_hud_zoom_in"))
            .accessibilityIdentifier("zoom.hud.increase")

            Divider().frame(height: 16)

            Button {
                viewportState.fit()
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("zoom_hud_fit"))
            .accessibilityIdentifier("zoom.hud.fit")

            Button {
                viewportState.actualSize(
                    viewportSize: viewportSize, textureSize: textureSize)
            } label: {
                Text("zoom_hud_100")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("zoom_hud_actual_size"))
            .accessibilityIdentifier("zoom.hud.actual")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .disabled(viewportState.zoomLocked)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("zoom.hud")
    }

    private var label: String {
        if viewportState.mode == .fit {
            return String(localized: "zoom_hud_fit_label")
        }
        return "\(viewportState.displayPercent)%"
    }
}

/// The compare HUD (split form): the compare-point label + the peek
/// stepper + a draggable split handle. The drag lands in Manual-Only
/// (feel/手感), the data face is the state's fraction.
internal struct BeforeAfterHUD: View {

    @Environment(BeforeAfterState.self) private var beforeAfterState
    @Environment(EditorState.self) private var editorState

    var body: some View {
        @Bindable var state = beforeAfterState
        HStack(spacing: 10) {
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityIdentifier("beforeafter.peek.prev")

            Text(state.comparePointLabel)
                .monospacedDigit()
                .accessibilityIdentifier("beforeafter.compare.label")

            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(beforeAfterState.peekIndex.map { $0 + 1 >= editorState.history.items.count } ?? false)
            .accessibilityIdentifier("beforeafter.peek.next")

            Divider().frame(height: 16)

            Slider(
                value: Binding(
                    get: { beforeAfterState.splitFraction },
                    set: { beforeAfterState.splitFraction = $0 }),
                in: 0.05...0.95
            )
            .frame(width: 140)
            .accessibilityIdentifier("beforeafter.split.handle")

            Button {
                beforeAfterState.splitEnabled = false
                beforeAfterState.peekIndex = nil
            } label: {
                Image(systemName: "xmark.circle")
            }
            .accessibilityIdentifier("beforeafter.close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("beforeafter.hud")
    }

    /// Peek stepping: nil (pristine) → 0 → 1 → … clamped to the stack;
    /// backward steps end at nil. Pure state — the render rides the
    /// view's .task(id:) (never inline).
    private func step(_ delta: Int) {
        let count = editorState.history.items.count
        let current = beforeAfterState.peekIndex
        let next: Int?
        if delta > 0 {
            next = (current ?? -1) + 1 < count ? (current ?? -1) + 1 : current
        } else {
            next = (current ?? 0) - 1 >= 0 ? (current ?? 0) - 1 : nil
        }
        beforeAfterState.peekIndex = next
    }
}
