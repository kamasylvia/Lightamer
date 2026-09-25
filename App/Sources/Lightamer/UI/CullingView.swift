import AppKit
import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// CullingView (Plan 09-03 T5 shape / T6 pipeline) — the COMPARE mode: TWO
// images side-by-side, EACH pane an independent PREVIEW sub-pipeline
// (D-09-CONTEXT-6: own RAWDecoder decode + the halved PreviewBucket ladder
// — the planes are SELF-OWNED, never the shared session cache).
//
// cap 2 is a CONSTANT (the 4-image extension slot is a comment, not a
// magic number — D-09-CONTEXT-6). The panes decode STAGGERED (pane B only
// after pane A's plane lands — the anti-storm gate against two concurrent
// 100 MP decodes hitching the UI, PERF-04's lesson) behind a progress
// placeholder.
//
// Closing the mode / switching sessions drops the self-owned planes (the
// T6 memory assertion pins the release).
// ─────────────────────────────────────────────────────────────────────────────

internal struct CullingView: View {

    /// The compare cap (D-09-CONTEXT-6; 4-image = a later constant bump +
    /// a memory-budget re-check, NOT a view-layout change).
    static let paneCap = 2

    /// The collection model (the FIRST TWO selected rows compare; a single
    /// selection compares it against the next collection row — the C1
    /// pick-two gesture, data face).
    let model: SessionBrowserModel
    let decoder: RAWDecoder
    let metalContext: MetalContext?

    var body: some View {
        Group {
            if let pair = comparePair {
                HStack(alignment: .center, spacing: 2) {
                    pane(for: pair.0, identifier: "browser.culling.paneA")
                    pane(for: pair.1, identifier: "browser.culling.paneB")
                }
            } else {
                ContentUnavailableView(
                    String(localized: "browser_culling_pick_two"),
                    systemImage: "rectangle.on.rectangle"
                )
                .accessibilityIdentifier("browser.culling.empty")
            }
        }
        .accessibilityIdentifier("browser.culling")
    }

    // MARK: - Panes (T6 wires the sub-pipelines; the shape ships now)

    @ViewBuilder
    private func pane(for relPath: String, identifier: String) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.15))
                .overlay(
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                )
                .aspectRatio(3.0 / 2.0, contentMode: .fit)
            Text(relPath)
                .font(.caption2)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - The pick-two data face

    /// The compare pair: the selection's first two rows (collection order);
    /// a ONE-row selection pairs it with the NEXT collection row.
    private var comparePair: (String, String)? {
        let selected = model.selectedOrderedPaths
        if selected.count >= Self.paneCap {
            return (selected[0], selected[1])
        }
        if selected.count == 1, let index = model.rows.firstIndex(where: { $0.relPath == selected[0] }) {
            let next = model.rows[(index + 1)...].first { !$0.orphanSidecar }
            return next.map { (selected[0], $0.relPath) }
        }
        // No selection: the first two browsable rows (an instant default).
        let browsable = model.rows.filter { !$0.orphanSidecar }.map(\.relPath)
        guard browsable.count >= Self.paneCap else { return nil }
        return (browsable[0], browsable[1])
    }
}
