import AppKit

/// The L057-safe panel presentation seam (fix(l057), 2026-10-08).
///
/// ROOT CAUSE (L057 family; .ips 2026-10-08-085205 + 2026-10-07-0937):
/// `NSOpenPanel`/`NSSavePanel` runModal called inside a SwiftUI action
/// callout (menu command, button action, context-menu item, sheet
/// content) starts a NESTED modal session while the caller frame is
/// still on the stack. The nested session re-enters the SwiftUI graph
/// (hover hit-test, AX menu inspection, menuNeedsUpdate populate); the
/// re-entrant update pass tears down Button/menu-item action closures
/// whose contexts the suspended outer frames still reference — the
/// dangling contexts are over-released at the NEXT arbitrary update.
/// Observed crash sites (stack tops, no panel code on either):
/// `PlatformItemList.update / destroy for Button` under
/// `menuNeedsUpdate`, and `ButtonResponder.updateValue /
/// assignWithTake for AppKitButtonConfiguration` under hover hit-test.
///
/// DISCRIMINANT (full text: .work/gsd/phases/l057-panel-family/L057-DECISIONS.md D2):
/// a `Task {}` hop only removes the action frame. The main-actor queue
/// drains through the CFRunLoop common modes (which include the
/// event-tracking mode), so the panel can still start while menu
/// tracking / AX simulated-open is being torn down — the nesting
/// survives (the 085205 crash came from a Task-wrapped menu command).
/// The sufficient pattern removes the nesting itself: present with
/// `begin(withCompletionHandler:)` — documented non-blocking; AppKit
/// schedules the panel's modal loop at a safe point after the current
/// event is fully processed, so the modal loop is never nested inside a
/// SwiftUI callout. Call sites additionally hop through `Task { }` so
/// the begin call itself leaves the action frame.
@MainActor
enum PanelPresentation {

    /// Presents the panel application-modally (runModal's behavior,
    /// non-sheet) via the non-blocking `begin` API. Resolves with the
    /// picked URL on OK, nil on cancel. The completion handler fires on
    /// a clean stack after dismissal — never inside a SwiftUI action or
    /// menu transaction.
    static func present(_ panel: NSSavePanel) async -> URL? {
        await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}
