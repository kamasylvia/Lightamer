import SwiftUI

/// Inspector column — Phase 1 stub (UI-SPEC "Inspector Panel").
///
/// D-03b: injects ONLY `InspectorState`. Phase 3+ replaces the placeholder
/// with the real iop panel stack (`Form` + `Section`s).
internal struct InspectorView: View {

    @Environment(InspectorState.self) private var inspectorState

    var body: some View {
        ContentUnavailableView {
            Label("no_image_selected", systemImage: "sliders")
        } description: {
            Text("no_image_selected_body")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LightamerColors.surface)
        .accessibilityLabel(Text("a11y_inspector_label"))
        .accessibilityIdentifier("Inspector")
        .accessibilityHint(Text("a11y_inspector_hint"))
    }
}
