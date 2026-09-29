import LightamerCore
import LightamerIOP
import Metal
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// ScopePanelView (Plan M2-3-3 T3, D6/M2UIW-04) — the right-pane scope panel
// (the Alcedo `EditorScopePanel` form): Show histogram / Show waveform.
//
// DATA: the PipeCoordinator samples the PREVIEW output plane through
// ScopeReduce (the GPU two-pass family) after each render completion, gated
// by THIS panel's visibility (invisible = zero tap) and the throttle.
//
// THROTTLE (the pure MainActor state machine below, unit-tested): ≤15 Hz
// while renders stream in; the deferred request settles once the frame goes
// idle (≥250 ms without a newer render) — the last frame always gets its
// scopes. The coordinator drives the machine; the panel hosts the toggle +
// the presentation.
//
// PRESENT NOTE (DECISIONS D6): the waveform shows as a Canvas column scatter
// drawn from the small r16Uint texture read (fenced in ScopeReduce, ≤553 KB
// at ≤15 Hz) — the MTKView direct-display leg would need a vertex/fragment
// present pipeline outside this plan's declared kernel surface; the P4
// observation item ③ receives the real-machine feel check.
// ─────────────────────────────────────────────────────────────────────────────

/// The scope-sample throttle (pure state, synthetic-clock testable).
/// Renders stream in at drag rate; the machine lets a sample through at
/// most every `minInterval`, defers the rest, and settles the newest
/// pending request once the frame has been idle for `settleInterval`.
struct ScopeThrottle: Equatable, Sendable {

    enum Action: Equatable, Sendable {
        /// Sample now.
        case run
        /// Too soon — hold the request for the idle settle.
        case deferForSettle
        /// No-op (disabled / nothing pending / not yet settled).
        case skip
    }

    /// The minimum spacing between samples while renders stream (1/15 s).
    let minInterval: Double
    /// The idle window after which a deferred request settles (0.25 s).
    let settleInterval: Double

    private(set) var lastRun: Double = 0
    private(set) var hasPending = false

    init(minInterval: Double = 1.0 / 15.0, settleInterval: Double = 0.25) {
        self.minInterval = minInterval
        self.settleInterval = settleInterval
    }

    /// A render completed → maybe sample. Disabled = zero tap (and any
    /// pending request drops).
    mutating func request(isEnabled: Bool, now: Double) -> Action {
        guard isEnabled else {
            hasPending = false
            return .skip
        }
        if now - lastRun >= minInterval {
            lastRun = now
            hasPending = false
            return .run
        }
        hasPending = true
        return .deferForSettle
    }

    /// The idle tick (fired after the settle window): the newest pending
    /// request runs now.
    mutating func settleTick(now: Double) -> Action {
        guard hasPending else { return .skip }
        guard now - lastRun >= max(settleInterval, minInterval) else {
            return .skip
        }
        hasPending = false
        lastRun = now
        return .run
    }
}

struct ScopePanelView: View {

    enum Mode: String, CaseIterable, Identifiable {
        case histogram
        case waveform
        var id: String { rawValue }
    }

    @Environment(PipeCoordinator.self) private var pipeCoordinator

    @State private var mode: Mode = .histogram
    /// The waveform texture read (column × band counts, CPU-side copy for
    /// the Canvas — the presentation note above).
    @State private var waveformCounts: [[UInt16]] = []
    @State private var waveformSize: (width: Int, height: Int) = (0, 0)

    var body: some View {
        VStack(spacing: 0) {
            Picker(
                String(localized: "editor_scopes_mode", defaultValue: "Scope mode"),
                selection: $mode
            ) {
                Text(String(
                    localized: "editor_scopes_show_histogram",
                    defaultValue: "Show histogram"))
                    .tag(Mode.histogram)
                Text(String(
                    localized: "editor_scopes_show_waveform",
                    defaultValue: "Show waveform"))
                    .tag(Mode.waveform)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .accessibilityIdentifier("editor.scopes.mode")

            Divider()

            Group {
                if mode == .histogram {
                    histogramCanvas
                        .accessibilityIdentifier("editor.scopes.histogram")
                } else {
                    waveformCanvas
                        .accessibilityIdentifier("editor.scopes.waveform")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ThemeTokens.cardSurface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.scopes.panel")
        // The visibility gate: visible = the tap is ON (the P1 View-menu
        // toggle mounts/unmounts this view); gone = zero tap.
        .onAppear { pipeCoordinator.setScopeTapEnabled(true) }
        .onDisappear { pipeCoordinator.setScopeTapEnabled(false) }
        // Re-read the waveform present texture per sample (the coordinator
        // bumps the generation each completed sample).
        .task(id: pipeCoordinator.scopeSampleGeneration) {
            guard mode == .waveform else { return }
            readWaveform()
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .waveform { readWaveform() }
        }
    }

    // MARK: - Histogram (4 overlaid channel curves)

    private var histogramCanvas: some View {
        Canvas { context, size in
            guard let histogram = pipeCoordinator.scopeHistogram,
                histogram.perChannel.count == 4 else { return }
            let maxCount = histogram.perChannel.map { $0.max() ?? 0 }.max() ?? 0
            guard maxCount > 0 else { return }
            let colors: [Color] = [.red, .green, .blue, .gray]
            for (channel, counts) in histogram.perChannel.enumerated() {
                var path = Path()
                for (bin, count) in counts.enumerated() {
                    let x = size.width * CGFloat(bin) / CGFloat(counts.count - 1)
                    let y = size.height
                        * (1 - CGFloat(count) / CGFloat(maxCount))
                    let point = CGPoint(x: x, y: y)
                    if bin == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                context.stroke(
                    path,
                    with: .color(colors[channel].opacity(0.75)),
                    lineWidth: 1)
            }
        }
    }

    // MARK: - Waveform (column × band scatter)

    private var waveformCanvas: some View {
        Canvas { context, size in
            guard waveformSize.height > 0, waveformSize.width > 0 else { return }
            let cellW = size.width / CGFloat(waveformSize.width)
            let cellH = size.height / CGFloat(waveformSize.height)
            var maxCount: UInt16 = 0
            for column in waveformCounts where !column.isEmpty {
                maxCount = max(maxCount, column.max() ?? 0)
            }
            guard maxCount > 0 else { return }
            for (x, column) in waveformCounts.enumerated() {
                for (band, count) in column.enumerated() where count > 0 {
                    let alpha = 0.25 + 0.75 * Double(count) / Double(maxCount)
                    let rect = CGRect(
                        x: CGFloat(x) * cellW,
                        y: (1 - CGFloat(band + 1) / CGFloat(waveformSize.height))
                            * size.height,
                        width: max(cellW, 0.5),
                        height: max(cellH, 0.5))
                    context.fill(
                        Path(rect),
                        with: .color(.green.opacity(alpha)))
                }
            }
        }
    }

    /// The fenced small-texture read (the presentation copy — DECISIONS D6).
    /// getBytes demands 256-byte row alignment — read padded, de-stride.
    private func readWaveform() {
        guard let texture = pipeCoordinator.scopeWaveform else {
            waveformCounts = []
            waveformSize = (0, 0)
            return
        }
        let width = texture.width
        let height = texture.height
        let rowBytes = (width * 2 + 255) / 256 * 256
        var padded = [UInt8](repeating: 0, count: rowBytes * height)
        padded.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: rowBytes,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        var columns = [[UInt16]](repeating: [], count: width)
        padded.withUnsafeBytes { raw in
            let base = raw.baseAddress!
            for x in 0..<width {
                var column = [UInt16](repeating: 0, count: height)
                for y in 0..<height {
                    column[y] = base.advanced(by: y * rowBytes)
                        .assumingMemoryBound(to: UInt16.self)[x]
                }
                columns[x] = column
            }
        }
        waveformCounts = columns
        waveformSize = (width, height)
    }
}
