import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// LibraryAutoStackDialog (Plan M6-4-01 T7, KD-8) — the auto-stack CONFIRM
// dialog: the gap stepper (seconds, initial 60 = StackClustering's default),
// the preview cluster count (queried on entry — preview NEVER writes), and
// the start/cancel pair.
//
// PRESENTATION DISCIPLINE (L057): this dialog rides the SwiftUI `.sheet`
// seam ONLY — `runModal`-family panels are banned from the production face
// (the L055/L057 crash family); the presenting closure hops through `Task`
// per the L057 call-site rule.
//
// STATE DISCIPLINE (the D-9 sheet shape): the dialog owns NOTHING — the
// model does the store work through the `autoStack(gap:preview:)` face and
// the caller closes the sheet via the binding.
// ─────────────────────────────────────────────────────────────────────────────

struct LibraryAutoStackDialog: View {

    /// The collection model (the autoStack face lives there — the pool
    /// selection, the preview, the commit + reload).
    let model: LibraryGridModel
    /// The presenting binding (Start and Cancel both close).
    @Binding var isPresented: Bool

    /// The gap (seconds) — the LightCraft UI default.
    @State private var gapSeconds: Double = StackClustering.defaultGapSeconds
    /// The previewed cluster count (nil = the preview query in flight).
    @State private var previewCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(
                localized: "library_stack_auto_title",
                defaultValue: "Auto-Stack by Capture Time"))
                .font(.headline)
            Stepper(value: $gapSeconds, in: 2...600, step: 2) {
                HStack {
                    Text(String(
                        localized: "library_stack_auto_gap_label",
                        defaultValue: "Gap (seconds)"))
                    Spacer()
                    Text("\(Int(gapSeconds)) s")
                        .foregroundStyle(ThemeTokens.textSecondary)
                        .monospacedDigit()
                }
            }
            .accessibilityIdentifier("library.autostack.gap")
            // The preview: re-run on entry and on every gap change (the
            // count is the ONLY decision input — preview never writes).
            Group {
                if let previewCount {
                    // The format-key spelling rides the focus_stack_dialog
                    // precedent (interpolated key = the argument; the
                    // catalog entry carries the string — defaultValue is a
                    // StaticString face and cannot ride interpolation).
                    Text(String(
                        localized: "library_stack_auto_preview \(previewCount)"))
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .font(.callout)
            .foregroundStyle(ThemeTokens.textSecondary)
            .accessibilityIdentifier("library.autostack.preview")
            HStack {
                Spacer()
                Button(String(
                    localized: "library_stack_auto_cancel",
                    defaultValue: "Cancel"), role: .cancel) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                Button(String(
                    localized: "library_stack_auto_start",
                    defaultValue: "Create Stacks")) {
                    let gap = gapSeconds
                    isPresented = false
                    Task {
                        _ = try? await model.autoStack(gap: gap, preview: false)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(previewCount == nil || previewCount == 0)
                .accessibilityIdentifier("library.autostack.start")
            }
        }
        .padding(20)
        .frame(width: 340)
        .task(id: gapSeconds) {
            previewCount = try? await model.autoStack(
                gap: gapSeconds, preview: true)
        }
    }
}
