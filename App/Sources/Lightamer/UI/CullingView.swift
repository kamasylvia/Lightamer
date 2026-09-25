import AppKit
import CoreGraphics
import CoreImage
import LightamerCore
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// CullingView (Plan 09-03 T6) — the COMPARE mode: TWO images side-by-side,
// EACH pane an independent PREVIEW sub-pipeline (D-09-CONTEXT-6: its own
// decode + its own throwaway plane cache @ the halved ladder bucket — the
// planes are SELF-OWNED; the shared session cache is never consulted).
//
// cap 2 is a CONSTANT (D-09-CONTEXT-6; the 4-image extension is a constant
// bump + a memory-budget re-check, never a layout change).
//
// STAGGERED DECODE (the anti-storm gate): pane B starts only AFTER pane A's
// plane has landed — two concurrent 100 MP decodes would hitch the UI
// (PERF-04's lesson). Pane B's slot shows a progress placeholder meanwhile.
//
// RELEASE: leaving the mode / a pair change drops the self-owned planes —
// `CullingPaneModel.release()` zeroes the memory ledger (the T6/T8 tests
// pin the release and the ~23 MB/plane budget face).
//
// v1 pane semantics: the pane renders the image's PRISTINE chain (the
// compare gesture is "pick two, eyeball the originals side-by-side"); the
// edited-render compare arrives with 9-4's before/after planes, which ride
// the same self-owned-pane shape.
// ─────────────────────────────────────────────────────────────────────────────

internal struct CullingView: View {

    /// The compare cap (D-09-CONTEXT-6).
    static let paneCap = 2

    /// The halved-ladder PREVIEW bucket for a culling pane (RESEARCH §5.4:
    /// 1480px ≈ 23 MB float32/plane — a rung of `PreviewBucket.ladder`).
    static let cullingLongEdge = 1480

    /// The collection model (the pick-two data face below).
    let model: SessionBrowserModel
    let decoder: RAWDecoder
    let metalContext: MetalContext?
    /// The session root (pane URL assembly) — the environment's current
    /// session.
    let sessionRoot: URL?

    /// The two panes (nil = not yet spawned). @State so a pair change
    /// releases the OLD panes before the new ones spawn.
    @State private var panes: (CullingPaneModel, CullingPaneModel)?

    var body: some View {
        Group {
            if let metal = metalContext, let pair = comparePair {
                panesContent(metal, pair)
            } else {
                ContentUnavailableView(
                    String(localized: "browser_culling_pick_two"),
                    systemImage: "rectangle.on.rectangle"
                )
                .accessibilityIdentifier("browser.culling.empty")
            }
        }
        .accessibilityIdentifier("browser.culling")
        .onDisappear {
            // RELEASE: leaving the mode drops both self-owned planes.
            panes?.0.release()
            panes?.1.release()
            panes = nil
        }
    }

    /// The two-pane layout with the STAGGERED spawn: pane A loads first;
    /// pane B's task only starts after A's plane landed (the anti-storm
    /// gate) behind its progress placeholder. A pair change releases the
    /// OLD planes before the new panes spawn (the ledger zeroes first).
    @ViewBuilder
    private func panesContent(
        _ metal: MetalContext, _ pair: (String, String)
    ) -> some View {
        let paneA = CullingPaneModel(
            relPath: pair.0, decoder: decoder, metal: metal,
            sessionRoot: sessionRoot
        )
        let paneB = CullingPaneModel(
            relPath: pair.1, decoder: decoder, metal: metal,
            sessionRoot: sessionRoot
        )
        HStack(alignment: .center, spacing: 2) {
            CullingPaneView(pane: paneA, identifier: "browser.culling.paneA")
            CullingPaneView(pane: paneB, identifier: "browser.culling.paneB")
        }
        .task {
            panes?.0.release()
            panes?.1.release()
            panes = (paneA, paneB)
            await paneA.load()
            await paneB.load() // STAGGERED — A's plane is on the page first
        }
    }

    // MARK: - The pick-two data face (internal + static for the tests)

    /// The compare pair: the selection's first two rows (collection order);
    /// a ONE-row selection pairs it with the NEXT browsable row; no
    /// selection pairs the first two. Orphan rows NEVER pair (no original).
    static func resolvePair(
        rows: [SessionBrowserModel.Row], selected: [String]
    ) -> (String, String)? {
        let browsable = rows.filter { !$0.orphanSidecar }.map(\.relPath)
        if selected.count >= paneCap {
            let picks = browsable.filter { selected.contains($0) }
            if picks.count >= paneCap { return (picks[0], picks[1]) }
        }
        if selected.count == 1,
           let anchor = browsable.first(where: { selected.contains($0) }),
           let index = browsable.firstIndex(of: anchor) {
            let rest = browsable[(index + 1)...]
            if let next = rest.first { return (anchor, next) }
            if let previous = browsable.first(where: { !selected.contains($0) }) {
                return (previous, anchor)
            }
        }
        guard browsable.count >= paneCap else { return nil }
        return (browsable[0], browsable[1])
    }

    private var comparePair: (String, String)? {
        Self.resolvePair(rows: model.rows, selected: model.selectedOrderedPaths)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The pane MODEL — the independent sub-pipeline with its memory ledger.
// ─────────────────────────────────────────────────────────────────────────────

@Observable
@MainActor
final class CullingPaneModel: Identifiable {

    enum State: Equatable, Sendable {
        case idle
        case decoding
        case rendering
        case ready
        case failed
    }

    let id: String
    private(set) var state: State = .idle
    /// The display plane (8-bit sRGB downsample of the render).
    private(set) var image: CGImage?
    /// The GPU-plane ledger: the float32 plane the run produced
    /// (width × height × 16 B — the ~23 MB/plane budget face; T8). The
    /// throwaway cache dies with the run; the ledger keeps the honest
    /// footprint statement for the budget assertions.
    private(set) var planeBytes = 0

    private let relPath: String
    private let decoder: RAWDecoder
    private let metal: MetalContext
    /// The decode seam (tests inject synthetic DecodedImages; the app wires
    /// the real RAWDecoder).
    private let decodeLeg: ThumbnailDecodeLeg?
    private let sessionRoot: URL?
    /// The registry for the display chain (the pane renders the PRISTINE
    /// DISPLAY chain — the gamma tail's bgra8Unorm output — not a raw
    /// linear passthrough).
    private let registry: ModuleRegistry

    init(
        relPath: String, decoder: RAWDecoder, metal: MetalContext,
        registry: ModuleRegistry = ModuleRegistry.makeDefault(),
        decodeLeg: ThumbnailDecodeLeg? = nil, sessionRoot: URL? = nil
    ) {
        self.id = relPath
        self.relPath = relPath
        self.decoder = decoder
        self.metal = metal
        self.registry = registry
        self.decodeLeg = decodeLeg
        self.sessionRoot = sessionRoot
    }

    /// The sub-pipeline run: decode → process @ the halved bucket → sRGB
    /// CGImage. SELF-OWNED throwaway plane cache — the shared session cache
    /// is never visible here.
    func load() async {
        guard state == .idle || state == .failed, let root = sessionRoot else { return }
        let url = root.appendingPathComponent(relPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            state = .failed
            return
        }
        state = .decoding
        do {
            let decoded: DecodedImage
            if let decodeLeg {
                decoded = try await decodeLeg(url)
            } else {
                decoded = try await decoder.decode(url)
            }
            state = .rendering
            // The halved bucket: PREVIEW at the fixed culling rung; the
            // PRISTINE DISPLAY chain (the default trio — the gamma tail's
            // bgra8Unorm output, not a raw linear passthrough).
            let (texture, _) = try await RenderPipeline.process(
                image: decoded,
                instances: await registry.makeDefaultChain(),
                imageID: UUID(),
                resolution: .preview,
                cache: PipeCache(), // SELF-OWNED throwaway — dies with the run
                metal: metal,
                longEdge: CullingView.cullingLongEdge
            )
            // The ledger: float32 planes cost 16 B/px; the gamma tail's
            // bgra8Unorm costs 4 B/px (the honest footprint either way).
            planeBytes = texture.width * texture.height
                * (texture.pixelFormat == .bgra8Unorm ? 4 : 16)
            image = try SessionThumbnailRenderer.cgImage(from: texture, metal: metal)
            state = .ready
        } catch {
            state = .failed
        }
    }

    /// The release leg: planes dropped, ledger zeroed (the T6 memory
    /// assertion's face).
    func release() {
        image = nil
        planeBytes = 0
        state = .idle
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The pane VIEW — the progress placeholder (B's staggered slot shows it).
// ─────────────────────────────────────────────────────────────────────────────

private struct CullingPaneView: View {
    let pane: CullingPaneModel
    /// The stable A/B slot identifier (L010 — set by the layout, never an
    /// array index baked into the model).
    let identifier: String

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                if let image = pane.image {
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .transition(.opacity)
                } else {
                    VStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.large)
                        Text(pane.state == .decoding
                            ? String(localized: "browser_culling_decoding")
                            : String(localized: "browser_culling_rendering"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .aspectRatio(3.0 / 2.0, contentMode: .fit)
            Text(pane.id)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(identifier)
    }
}
