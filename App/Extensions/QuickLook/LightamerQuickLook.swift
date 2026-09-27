import CoreGraphics
import Foundation
import QuickLookThumbnailing
import QuickLookUI

// ─────────────────────────────────────────────────────────────────────────────
// LightamerQuickLook — the Quick Look app extension SHELL (Plan 13-1 T4).
//
// Single appex, BOTH QL abilities (D-13-CONTEXT-1): thumbnail + full preview
// share one target — the two requests are the same question ("what does the
// CURRENT EDIT look like") at two sizes.
//
// SDK shape (macOS 27, execution decision): the thumbnail API LEFT the
// QLPreviewingController protocol — it now lives on the `QLThumbnailProvider`
// base class (QuickLookThumbnailing). One class carries both abilities by
// subclassing QLThumbnailProvider AND conforming QLPreviewingController (the
// protocol's NSObject requirement is satisfied through the same base).
//
// ⚠︎ Main-app coexistence semantics (09-CONTEXT:82): this process ALWAYS reads
// the DISK-COMMITTED state — the sidecar's last 2s-debounced committed
// version, the thumbs cache, the lindex — never the main app's in-memory
// editing state. The two processes are naturally decoupled through disk.
//
// The shell carries ZERO business logic (the appex red line): file
// location, sidecar parsing and rendering all live in LightamerCore
// (`QuickLookRenderer`); this file is protocol glue only.
// ─────────────────────────────────────────────────────────────────────────────

final class PreviewProvider: QLThumbnailProvider, QLPreviewingController {

    // Thumbnail ability (the QuickLookThumbnailing leg): the three-probe
    // fallback chain — fresh thumbs direct read → headless render @ the
    // requested size → tier-A embedded preview.
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        // Wired to QuickLookRenderer.thumbnail in Plan 13-1 T4.
        handler(nil, nil)
    }

    // Preview ability (the QuickLookUI leg): the EDITED STATE rendered at
    // the QL-requested fit size — never the 100 MP native full frame
    // (D-13-CONTEXT-2 ③). NOT an export preview: no yiyin framing, no
    // export sizing/quantize/encode.
    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        // Wired to QuickLookRenderer.preview in Plan 13-1 T4.
        handler(nil)
    }
}
