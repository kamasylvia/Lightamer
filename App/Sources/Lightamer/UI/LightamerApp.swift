import CoreImage
import ImageIO
import LightamerCore
import LightamerIOP
import SwiftUI
import os

// ─────────────────────────────────────────────────────────────────────────────
// Focused-value plumbing: the split-view column visibility lives in
// ContentView (it owns the NavigationSplitView), but the View menu commands
// run in the App scene. `focusedSceneValue` + `@FocusedBinding` bridge the
// two without shared mutable globals.
// ─────────────────────────────────────────────────────────────────────────────

/// Plan 11-04: the export-sheet request binding, seen from the App scene's
/// File menu (⌘⇧E mirrors the toolbar's export button).
internal struct ExportPanelRequestKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

internal extension FocusedValues {
    // F0P-03 T1 (omp M2 (a)): the RETIRED publish faces (the column
    // visibility, the metadata focus, the workspace model and the two
    // ContentView export-request legs) no longer write focused values; the
    // shell face's @FocusedBinding(\.exportPanelRequest) below is the last
    // live dependency, so the key + this accessor survive it. With nothing
    // publishing, the binding reads nil and the shell's export action takes
    // the honest-degrade page route (zero behavior face).
    var exportPanelRequest: Binding<Bool>? {
        get { self[ExportPanelRequestKey.self] }
        set { self[ExportPanelRequestKey.self] = newValue }
    }
}

/// Plan 14-4: the lock-guarded latest (writer, provider) pair the MCP
/// culling face reads. The GUI publishes the SHARED segment-3 writer and
/// thumbnail provider here at the per-session rebuild, and clears them at
/// the teardown — the MCP write face is the SAME single source the GUI
/// rides (D-14-CONTEXT-5①), never a private queue.
final class McpWriteFaceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _writer: BatchSidecarWriter?
    private var _provider: SessionThumbnailProvider?

    var writer: BatchSidecarWriter? {
        lock.lock(); defer { lock.unlock() }
        return _writer
    }

    var provider: SessionThumbnailProvider? {
        lock.lock(); defer { lock.unlock() }
        return _provider
    }

    func set(writer: BatchSidecarWriter?, provider: SessionThumbnailProvider?) {
        lock.lock()
        _writer = writer
        _provider = provider
        lock.unlock()
    }
}

/// Plan M5-3-03 (KD-3): the typed pano failure vocabulary's display-layer
/// mapping — the P1 canonical prefixes (pinned in Core,
/// `PanoMatch.FailurePrefix`) map onto the three zh keys at the merge
/// failureHook's consumption face. The Core error vocabulary stays
/// untouched; a message without a pano prefix passes through
/// byte-identically (the existing error face's zero-change invariant).
enum PanoFailureCopy {

    /// The prefix table (canonical Core prefix → catalog key). Pure and
    /// machine-checked (three prefixes, both directions).
    static func failureKey(for message: String) -> String? {
        let table: [(prefix: String, key: String)] = [
            (PanoMatch.FailurePrefix.alignment, "pano_error_alignment"),
            (PanoMatch.FailurePrefix.disconnected, "pano_error_disconnected"),
            (PanoMatch.FailurePrefix.canvas, "pano_error_canvas"),
        ]
        for entry in table where message.contains(entry.prefix) {
            return entry.key
        }
        return nil
    }

    /// The failureHook consumption face: a matched message renders as
    /// "<localized copy>: <typed detail>" (the AppError boilerplate head
    /// is dropped with the substitution); a non-pano message returns the
    /// input unchanged.
    static func failureMessage(for raw: String) -> String {
        guard let key = failureKey(for: raw) else { return raw }
        let localized: String
        // V14 discipline: dynamic key positions resolve through an
        // explicit switch returning STATIC keys (no runtime-key
        // LocalizationValue lookup).
        switch key {
        case "pano_error_alignment":
            localized = String(localized: "pano_error_alignment")
        case "pano_error_disconnected":
            localized = String(localized: "pano_error_disconnected")
        case "pano_error_canvas":
            localized = String(localized: "pano_error_canvas")
        default:
            return raw
        }
        // The canonical prefixes carry their own ": " tail — the typed
        // detail (when present) follows them in the raw message.
        var detail = ""
        for prefix in [PanoMatch.FailurePrefix.alignment,
                       PanoMatch.FailurePrefix.disconnected,
                       PanoMatch.FailurePrefix.canvas] {
            if let range = raw.range(of: prefix) {
                detail = String(raw[range.upperBound...])
                break
            }
        }
        let trimmed = detail.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? localized : localized + ": " + trimmed
    }
}/// Plan 14-1 T1 (D-14-CONTEXT-2⑤): the process entry fork. A headless MCP
/// launch (`--mcp-stdio` / `--mcp-http`) NEVER constructs the SwiftUI App
/// struct below — `@NSApplicationDelegateAdaptor` and the whole `@State`
/// graph are instance properties that only initialize inside
/// `App.main()`'s instance creation — and never enters `NSApplication.run`
/// (the research §RQ-14-1④ shape; the fork itself is the R3 risk probe).
/// Every other launch runs the normal GUI flow unchanged.
@main
enum LightamerEntryPoint {
    @MainActor
    static func main() {
        #if DEBUG
        // The two-process flock fixture (McpHostTests): must short-circuit
        // BEFORE the GUI decision — it never constructs any App state.
        if McpServerController.holdLockFixtureIfRequested() {
            return // parks inside; never returns
        }
        // M6-1-01: the PROJECT-lock fixture (the arbitration tests) — same
        // short-circuit shape, parks inside.
        if McpServerController.holdProjectLockFixtureIfRequested() {
            return // parks inside; never returns
        }
        #endif
        if let mode = McpServerController.headlessModeIfRequested() {
            McpServerController.runHeadless(mode: mode) // parks forever
            return
        }
        // UQ-S3: the one-shot CLI gate (`Lightamer mcp call/list`) — same
        // fork shape as the headless arms above: never constructs the
        // SwiftUI App, runs one call and exits with the typed code.
        if let tail = McpOneShot.tailIfRequested() {
            Task {
                let code = await McpOneShot.run(tail)
                exit(code)
            }
            dispatchMain() // the Task above exits; this parks meanwhile
        }
        // Plan M2-10-05 (OQ-5-A): the AI worker fork — the same-binary
        // child process the editor spawns for local inference (a native
        // inference crash must never take the editor down). Like the MCP
        // arm above: parks in its frame loop and NEVER constructs the
        // SwiftUI App.
        if AIWorkerMain.runIfRequested() {
            return // unreachable: runIfRequested parks forever on this arm
        }
        // F0-prime shell handover (F0P-01 T6): the GUI arm runs under the
        // manual NSApplication lifecycle — the SwiftUI face is demoted to
        // NSHostingView sub-content (F0PRIME: menu authority + churn 96%→0%
        // + face survival). The fork sequence above is byte-untouched.
        // The production entry below stays for reference but is unreachable
        // in this build (the dead-line shape retires with P3).
        LightamerShellMain.run()
    }
}

/// Handles the open-document Apple Event (Finder double-click, `open` CLI,
/// drag onto the Dock icon) so declared CFBundleDocumentTypes actually route
/// into `EditorState.load`. Opens that arrive before the scene is ready are
/// buffered and flushed on first appearance. Also bridges
/// `applicationWillTerminate` into the coordinator's sidecar flush (02-06,
/// D-S3) — the AppKit callback is synchronous and chosen over
/// `scenePhase`/notification observers because it is the ONLY termination
/// signal delivered deterministically on the main thread before exit.
internal final class AppDelegate: NSObject, NSApplicationDelegate {
    var openHandler: (([URL]) -> Void)?
    private var buffered: [URL] = []

    /// 02-06: the synchronous flush bridge, installed by the app root once
    /// the state graph is wired. NSApplicationDelegate callbacks arrive on
    /// the main thread; `@MainActor @Sendable` is the sanctioned closure
    /// shape for main-thread state capture, and the call site proves the
    /// thread via `MainActor.assumeIsolated`.
    var terminateHandler: (@MainActor @Sendable () -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        if let openHandler {
            openHandler(urls)
        } else {
            buffered.append(contentsOf: urls)
        }
    }

    /// D-S3: force the pending sidecar write before the process exits
    /// (bounded wait inside the handler; a hung volume must not block
    /// termination forever).
    /// The parameter type is LOAD-BEARING: the protocol's optional is
    /// `applicationWillTerminate(_ notification: Notification)` — an
    /// `NSApplication`-typed parameter "nearly matches" (the compiler
    /// warning) and the ObjC selector dispatch NEVER fires it (found by
    /// the M2-8-2 T4 kill-walkthrough: the flush/sentinel legs were dead
    /// on every quit since 02-06; the 2s debounce masked the flush gap).
    func applicationWillTerminate(_ notification: Notification) {
        guard let handler = terminateHandler else { return }
        MainActor.assumeIsolated {
            handler()
        }
    }

    /// Drains opens that arrived before the handler was installed.
    func flushBuffered() -> [URL] {
        let pending = buffered
        buffered = []
        return pending
    }
}

/// D-COL2 window capture (Plan 02-04-05): an invisible accessory view that
/// reports its hosting `NSWindow` the moment SwiftUI places it
/// (`viewDidMoveToWindow` also fires on window changes). The least-invasive
/// window source — no invasive scene introspection, no AppKit window
/// subclassing; the app root forwards the window to
/// `PipeCoordinator.configure(window:)`. F0P-01 T6 (review m4): visibility
/// widened internal (exactly this one change) — the transplanted
/// LightamerShellFace reuses it.
struct WindowCapture: NSViewRepresentable {

    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> CaptureView {
        CaptureView(onWindow: onWindow)
    }

    func updateNSView(_ view: CaptureView, context: Context) {}

    final class CaptureView: NSView {
        let onWindow: (NSWindow) -> Void

        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow(window) }
        }
    }
}
