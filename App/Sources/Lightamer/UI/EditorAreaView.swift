import AppKit
import LightamerCore
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

    @Environment(EditorState.self) private var editorState

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
                    } else {
                        Color.clear
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // UI-SPEC Accessibility: stable identifier for
                // VoiceOver/XCUITest. NO accessibilityLabel here — a
                // container label absorbs the child elements (the
                // empty-state card would vanish from the AX tree); the
                // MTKView carries its own label in the loaded state.
                .accessibilityIdentifier("Image viewport")
                .animation(.easeInOut(duration: 0.2), value: editorState.loadedImageURL)
                // Geometry → the coordinator's bucket re-evaluation (D-C3).
                // Fire-and-forget Task: the view NEVER awaits or renders.
                // Scale: main-screen backing factor (Retina 2×); per-window
                // screen tracking refines this with 02-04's display-profile
                // work.
                .onChange(of: geo.size) { _, newSize in
                    let scale = NSScreen.main?.backingScaleFactor ?? 2
                    let longEdge = Int(max(newSize.width, newSize.height) * scale)
                    Task { await pipeCoordinator.drawableDidChange(drawableLongEdge: longEdge) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            StatusBar(isDecoding: editorState.isDecoding)
        }
        .background(LightamerColors.canvas)
    }
}
