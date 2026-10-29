//  Lightamer — FinderReveal seam (M9-4 T4 / acceptance-2ND M-1 repair)
//  SPDX-License-Identifier: GPL-3.0-only
//  Additional permission under GPLv3 section 7 applies; see the LICENSE file.

import AppKit
import Foundation

/// The Show-in-Finder seam (acceptance-2ND M-1 repair): the reveal
/// precedent (PostExportActions shape) — existence-checked, non-modal,
/// L057-clear — lifted into ONE production face the three doors consume
/// (the library grid row, the filmstrip row, and the editor Image menu).
///
/// The three accessibility identifiers are PRODUCTION CONSTANTS (single
/// source): the mounts register them and `SmallPoolUITests` pins the
/// spellings against these symbols, so a mount can no longer silently
/// drift from the walkthrough-registered AX tree (the AX-tree reachability
/// walk itself stays the gui-acceptance recipe face — M9-4 MANIFEST,
/// DECISIONS §11).
enum FinderReveal {

    /// The library grid row's context-menu door.
    static let gridActionID = "library.grid.action.finder"
    /// The filmstrip row's context-menu door.
    static let filmstripActionID = "filmstrip.action.finder"
    /// The editor Image menu door (NSMenuBridge).
    static let menuActionID = "menu.image.finder"

    /// Reveals `path` in Finder (selected, parent folder opened) when it
    /// exists; returns `false` and reveals nothing when it does not (the
    /// typed degrade — the guard rides BEFORE every reveal on all three
    /// doors). The `reveal` and `exists` parameters are the test seam:
    /// production callers take the defaults (NSWorkspace.shared +
    /// FileManager.default); the unit test injects a recording closure and
    /// exercises the REAL guard/reveal decision path.
    @discardableResult
    static func revealIfPresent(
        _ path: String,
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        reveal: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    ) -> Bool {
        guard exists(path) else { return false }
        reveal(URL(fileURLWithPath: path))
        return true
    }
}
