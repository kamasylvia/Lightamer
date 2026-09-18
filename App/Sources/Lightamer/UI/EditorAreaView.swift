import LightamerCore
import SwiftUI

/// Editor center column: empty state ↔ Metal viewport (D-11/D-13).
///
/// D-03b: injects ONLY `EditorState` (plus the app-owned `decoder` and
/// `metalContext` passed down from the app root). The loaded branch renders
/// `EditorMTKView` (Plan 03) over `EditorState.displayTexture`; the render
/// trigger lives here as a URL-keyed `.task` — one render per loaded image.
internal struct EditorAreaView: View {

    /// The app-owned decode actor (D-21), passed through to `EditorState.load`
    /// for the empty-state open path.
    let decoder: RAWDecoder

    /// The app-owned Metal context (D-14/15); nil = no GPU (fatal alert is
    /// hosted by `ContentView` per UI-SPEC Error Messages).
    let metalContext: MetalContext?

    @Environment(EditorState.self) private var editorState

    var body: some View {
        @Bindable var editorState = editorState
        VStack(spacing: 0) {
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
                    // One display render per loaded image (not per frame).
                    .task(id: editorState.loadedImageURL) {
                        await editorState.renderDisplayTexture(using: metalContext)
                    }
                    .transition(.opacity)
                    .accessibilityLabel(Text("editor_viewport"))
                } else {
                    Color.clear
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // UI-SPEC Accessibility: stable identifier for VoiceOver/XCUITest.
            // NO accessibilityLabel here — a container label absorbs the
            // child elements (the empty-state card would vanish from the AX
            // tree); the MTKView carries its own label in the loaded state.
            .accessibilityIdentifier("Image viewport")
            .animation(.easeInOut(duration: 0.2), value: editorState.loadedImageURL)

            StatusBar(isDecoding: editorState.isDecoding)
        }
        .background(LightamerColors.canvas)
    }
}
