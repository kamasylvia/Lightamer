import AppKit
import Observation

// Plan 08-4 T3 (IOP-HDR-05) — the display EDR headroom monitor.
//
// The ONE query (research §7.2): `NSScreen.maximumExtendedDynamicRangeColor
// ComponentValue` of the screen the editor window currently lives on — the
// compositor-clamped SDR white is 1.0; an XDR/HDR panel reports > 1.0 (the
// extra brightness the EDR preview leg may address). The 13-2 D-COL2 face
// (PipeCoordinator.screenWatchTasks) owns the DISPLAY PROFILE follow; this
// monitor owns only the headroom NUMBER for the badge — the two faces share
// the same two notifications and never cross (the EDR toggle stales no
// colorout key; a display change never flips EDR state).
//
// Semantics on a headroom == 1.0 display (P4 实测, the SDR-only dev rig):
// the HDR toggle stays LEGAL — >1.0 values are clamped to SDR white by the
// compositor, no auto-fallback (research §7.3); the control view spells out
// 「当前显示器无 EDR 余量」.
//
// App-lifetime object (injected at the app root, the SoftProofState shape).
// `invalidationCount` is the test seam: every notification-driven re-query
// bumps it exactly once (EDRViewportTests pins the notification legs).
@Observable
@MainActor
final class EDRHeadroomMonitor {

    /// The live headroom of the window's screen (1.0 = SDR white).
    /// Legal domain is >= 1.0 (the property's documented floor); pinned by
    /// the tests against the real screen.
    private(set) var headroom: Double = 1.0

    /// Notification-driven re-query counter (the test seam — one bump per
    /// delivered screen event).
    private(set) var invalidationCount = 0

    var hasEDRHeadroom: Bool { headroom > 1.0 }

    /// The window whose screen drives the query (nil provider = NSScreen.main).
    private let windowProvider: () -> NSWindow?

    private var watchTasks: [Task<Void, Never>] = []

    init(windowProvider: @escaping () -> NSWindow? = {
        NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow
    }) {
        self.windowProvider = windowProvider
    }

    /// Initial query + the two screen-event observers (D-COL2's pair —
    /// `NSWindow.didChangeScreen` = the window dragged across displays,
    /// `NSApplication.didChangeScreenParameters` = displays connected /
    /// profile changed). Idempotent: the tasks install once. App-lifetime
    /// tasks (no deinit — the object lives for the whole session, the
    /// coordinator's `screenWatchTasks` shape).
    func start() {
        guard watchTasks.isEmpty else { return }
        recompute()
        let center = NotificationCenter.default
        watchTasks.append(Task { [weak self] in
            for await _ in center.notifications(
                named: NSWindow.didChangeScreenNotification
            ) {
                self?.recompute()
            }
        })
        watchTasks.append(Task { [weak self] in
            for await _ in center.notifications(
                named: NSApplication.didChangeScreenParametersNotification
            ) {
                self?.recompute()
            }
        })
    }

    /// Re-query the window's screen. The notification can fire for events
    /// that do not change the headroom — the recompute is idempotent and
    /// cheap (one AppKit property read).
    func recompute() {
        let screen = windowProvider()?.screen ?? NSScreen.main
        headroom = Self.headroom(of: screen)
        invalidationCount += 1
    }

    /// The raw query (the research §7.2 single source). nil screen (no
    /// display reported) falls back to 1.0 — the SDR-safe answer. The AppKit
    /// property is CGFloat; the monitor's face is Double (SwiftUI numeric).
    nonisolated static func headroom(of screen: NSScreen?) -> Double {
        (screen?.maximumExtendedDynamicRangeColorComponentValue).map(Double.init) ?? 1.0
    }
}
