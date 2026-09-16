import SwiftUI

/// Editor center column: empty state ↔ loaded placeholder (D-11).
///
/// D-03b: injects ONLY `EditorState`. Plan 03 replaces the loaded branch's
/// placeholder with the real `EditorMTKView` (D-13 display-only viewport).
internal struct EditorAreaView: View {

    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if editorState.loadedImageURL == nil {
                    EmptyStateView(onOpen: { editorState.load(url: $0) })
                        .transition(.opacity)
                } else {
                    Text("editor_loaded_placeholder")
                        .font(.body)
                        .foregroundStyle(LightamerColors.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(LightamerColors.canvas)
                        .transition(.opacity)
                        .accessibilityLabel(Text("editor_loaded_placeholder"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: editorState.loadedImageURL)

            StatusBar(isDecoding: editorState.isDecoding)
        }
        .background(LightamerColors.canvas)
    }
}
