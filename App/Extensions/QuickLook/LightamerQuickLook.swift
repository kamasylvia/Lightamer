import CoreGraphics
import Foundation
import LightamerCore
import QuickLookThumbnailing
import QuickLookUI
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────────
// LightamerQuickLook — the Quick Look app extension SHELL (Plan 13-1 T4).
//
// Single appex, BOTH QL abilities (D-13-CONTEXT-1) through the macOS 27 SDK
// shape: the thumbnail API left QLPreviewingController (it now lives on the
// `QLThumbnailProvider` base class), so one principal class carries both by
// subclassing QLThumbnailProvider AND conforming QLPreviewingController —
// thumbnail via `provideThumbnail(for:_:)`, preview via the DATA-BASED
// `providePreview(for:completionHandler:)` (an image QLPreviewReply — no
// view controller, no state; the preparePreviewOfFile view-based leg stays
// unused, an execution decision recorded in 13-1-DECISIONS).
//
// ⚠︎ Main-app coexistence semantics (09-CONTEXT:82): this process ALWAYS reads
// the DISK-COMMITTED state — the sidecar's last 2s-debounced committed
// version, the thumbs cache, the lindex — never the main app's in-memory
// editing state. The two processes are naturally decoupled through disk.
//
// ZERO business logic (the appex red line): everything below is glue onto
// `QuickLookRenderer` (LightamerCore) — QL always gets an answer or an
// error, never a hang (the bounded-render contract lives in Core).
// ─────────────────────────────────────────────────────────────────────────────

final class PreviewProvider: QLThumbnailProvider, QLPreviewingController {

    /// Process-wide render context (the QL process spawns one principal
    /// object; a Metal context + registry are per-process, not per-request).
    private enum Env {
        static let metal: MetalContext? = try? MetalContext()
        static let registry = ModuleRegistry.makeDefault()
    }

    /// The full-preview fit long edge (the T2 probe's 2560 fit tier — the
    /// QL window never needs the 100 MP native frame).
    private static let previewLongEdge = 2560

    /// The QL completion-handler bridge: the framework's handlers are plain
    /// @escaping closures (not Sendable); the async render work runs in a
    /// detached task and hands the ANSWER back through this wrapper.
    private struct Reply: @unchecked Sendable {
        let handler: (QLThumbnailReply?, Error?) -> Void
    }
    private struct PreviewReply: @unchecked Sendable {
        let handler: (QLPreviewReply?, Error?) -> Void
    }

    // ── Thumbnail ability: the three-probe chain ──────────────────────────

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let url = request.fileURL
        let size = request.maximumSize
        let longEdge = Int(max(size.width, size.height).rounded(.up))
        let reply = Reply(handler: handler)
        Task {
            guard let outcome = await Self.thumbnailOutcome(url: url, longEdge: longEdge)
            else {
                reply.handler(nil, nil) // every probe missed — the system probe takes over
                return
            }
            let image = outcome.image
            let drawn = QLThumbnailReply(contextSize: size, drawing: { context in
                Self.draw(image, in: context, fitting: size)
                return true
            })
            reply.handler(drawn, nil)
        }
    }

    // ── Preview ability: the edited state at the fit size, as image data ──

    func providePreview(
        for request: QLFilePreviewRequest,
        completionHandler handler: @escaping (QLPreviewReply?, Error?) -> Void
    ) {
        let url = request.fileURL
        let reply = PreviewReply(handler: handler)
        Task {
            guard let image = await Self.previewImage(url: url) else {
                reply.handler(nil, nil)
                return
            }
            guard let data = try? ThumbnailDiskStore.jpegData(from: image) else {
                reply.handler(nil, nil)
                return
            }
            let answer = QLPreviewReply(
                __dataOfContentType: .jpeg,
                contentSize: CGSize(width: image.width, height: image.height),
                dataCreationBlock: { _, _ in data })
            reply.handler(answer, nil)
        }
    }

    // MARK: - Core seams (glue only)

    private static func thumbnailOutcome(url: URL, longEdge: Int)
        async -> QuickLookRenderer.ThumbnailOutcome?
    {
        guard let metal = Env.metal else { return nil }
        return await QuickLookRenderer.thumbnail(
            imageURL: url, requestedLongEdge: longEdge,
            metal: metal, registry: Env.registry)
    }

    private static func previewImage(url: URL) async -> CGImage? {
        guard let metal = Env.metal else { return nil }
        return try? await QuickLookRenderer.preview(
            imageURL: url, targetLongEdge: previewLongEdge,
            metal: metal, registry: Env.registry)
    }

    /// Aspect-fit the rendered image into the reply's context (CG origin —
    /// bottom-left — irrelevant for a centered fit).
    private static func draw(_ image: CGImage, in context: CGContext, fitting size: CGSize) {
        let scale = min(
            size.width / CGFloat(image.width),
            size.height / CGFloat(image.height),
            1)
        let drawSize = CGSize(
            width: CGFloat(image.width) * scale,
            height: CGFloat(image.height) * scale)
        let origin = CGPoint(
            x: (size.width - drawSize.width) / 2,
            y: (size.height - drawSize.height) / 2)
        context.draw(image, in: CGRect(origin: origin, size: drawSize))
    }
}
