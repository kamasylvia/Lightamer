import CoreGraphics
import Foundation
import LightamerCore
import LightamerIOP
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
    /// spektra-module P1 T6' (D-SM-15): the QL process assembles
    /// INDEPENDENTLY — the full populate (spektraFilm included) + its own
    /// material store + the seam install. Mechanism (r4-m2): the async
    /// assembly runs ONCE inside a Task at first use (the `shared`
    /// actor serializes it); static lets never block on async work (no
    /// unbounded wait inside a static initializer — the r4-m2 ban).
    private enum Env {
        static let metal: MetalContext? = try? MetalContext()
        static let registry = ModuleRegistry.makeDefault()

        /// The one-shot async assembly (populate + store + seam).
        static func ensureAssembled() async {
            await QLAssembly.shared.ensure(
                registry: registry, metal: metal)
        }
    }

    /// The QL assembly serializer (the r4-m2 mechanism: an actor-owned
    /// once-flag — concurrent first-use Tasks coalesce, late Tasks
    /// no-op; a failed store build retries next call).
    private actor QLAssembly {
        static let shared = QLAssembly()
        private var populated = false
        private var storeInstalled = false

        func ensure(registry: ModuleRegistry, metal: MetalContext?) async {
            if !populated {
                await LightamerIOPRegistry.populate(registry)
                populated = true
            }
            if !storeInstalled {
                storeInstalled = installStore()
            }
            _ = metal
        }

        /// Build the QL-process store (the host bundle's Resources —
        /// the appex bundle carries no FilmProfiles; the folder
        /// references ride the host) and install the seam resolver.
        private func installStore() -> Bool {
            let hostResources: URL? = {
                // The appex bundle sits at Host.app/Contents/PlugIns/*.appex:
                // walk up to Contents, then down into Resources.
                var url = Bundle.main.bundleURL
                for _ in 0..<2 { url.deleteLastPathComponent() }
                url.appendPathComponent("Resources")
                return url
            }()
            guard let hostResources else {
                FilmMaterialSeam.resolver = { _ in nil }
                return true
            }
            let ccURL = hostResources.appendingPathComponent("FilmProfiles/profiles")
            let bwURL = hostResources.appendingPathComponent("FilmProfilesBW/profiles")
            let directories = [ccURL] + (
                FileManager.default.fileExists(atPath: bwURL.path) ? [bwURL] : [])
            guard let store = try? FilmMaterialStore(profilesDirectories: directories) else {
                FilmMaterialSeam.resolver = { _ in nil }
                return true
            }
            FilmMaterialSeam.resolver = { record in
                guard let film = store.profile(id: record.filmStock),
                    let paper = store.profile(id: record.paperStock)
                else { return nil }
                return FilmMaterialSeam.ResolvedMaterials(
                    film: film, paper: paper,
                    materialPairHash: FilmMaterialStore.materialPairHash(
                        film: film, paper: paper))
            }
            return true
        }
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
        await Env.ensureAssembled()
        guard let metal = Env.metal else { return nil }
        return await QuickLookRenderer.thumbnail(
            imageURL: url, requestedLongEdge: longEdge,
            metal: metal, registry: Env.registry)
    }

    private static func previewImage(url: URL) async -> CGImage? {
        await Env.ensureAssembled()
        guard let metal = Env.metal else { return nil }
        // D-SM-15③ (the TaskLocal-direct arm — the appex cannot import
        // the App's pure resolver): resolve the disk record's tags here
        // and scope them around the render (the render body zero-diff).
        let tags = Self.requestTags(imageURL: url)
        return await SpectralPrintBake.$requestTags.withValue(tags) {
            try? await QuickLookRenderer.preview(
                imageURL: url, targetLongEdge: previewLongEdge,
                metal: metal, registry: Env.registry)
        }
    }

    /// The QL-run tags resolution (the D-SM-14 pure shape, appex-local:
    /// read the disk sidecar's spektraFilm record, resolve grade/filter/
    /// mode through the QL-process store; the RMS memo is App-side so QL
    /// leaves it absent — the dispatch degrades per-channel).
    private static func requestTags(
        imageURL: URL
    ) -> SpectralPrintBake.FilmLegRequestTags? {
        guard let document = ExportRenderer.readDocument(imageURL: imageURL),
            case let record? = spektraRecord(of: document),
            let store = qlStore()
        else { return nil }
        var tags = SpectralPrintBake.FilmLegRequestTags()
        var any = false
        if let grade = record.paperGrade, !grade.isEmpty,
            let paper = store.profile(id: record.paperStock),
            let preset = PaperGradeTable.cachedTable(paper: paper)[grade] {
            tags.paperGrade = SpectralPrintBake.PaperGradeTag(
                key: grade, magentaCC: preset.magentaCC,
                yellowCC: preset.yellowCC, exposureEv: preset.exposureEv)
            any = true
        }
        if let filterName = record.cameraFilter, !filterName.isEmpty,
            let filter = store.filters[filterName] {
            tags.cameraFilter = SpectralPrintBake.CameraFilterTag(
                name: filterName,
                transmission: CameraFilterTable.alignedTransmission(
                    filter, wavelengths: SpectralConstantsData.wavelengthsNm,
                    tableWavelengths: SpectralConstantsData.wavelengthsNm))
            any = true
        }
        if let mode = record.resolvedReversalPrintMode {
            tags.reversalPrintMode = mode
            any = true
        }
        return any ? tags : nil
    }

    /// The disk sidecar's spektraFilm record (global ∪ layer chains).
    private static func spektraRecord(of document: LightamerSidecar) -> FilmRecord? {
        let stacks: [[ModuleInstance]] =
            [document.history.effectiveInstances()] + (
                document.layerStack.map {
                    $0.snapshot.makeLayers().compactMap { $0 as? AdjustmentLayer }
                        .map(\.chain)
                } ?? [])
        for chain in stacks {
            for record in HistoryStack.effectiveChain(chain)
            where record.opName == "spektraFilm" {
                if let params = try? JSONDecoder().decode(
                    SpektraFilmModule.Params.self, from: record.paramsData) {
                    return params.record
                }
            }
        }
        return nil
    }

    /// The QL-process store (rebuilt per render — the install path owns
    /// the cached install; this read face rebuilds cheaply for tags).
    private static func qlStore() -> FilmMaterialStore? {
        var url = Bundle.main.bundleURL
        for _ in 0..<2 { url.deleteLastPathComponent() }
        url.appendPathComponent("Resources")
        let ccURL = url.appendingPathComponent("FilmProfiles/profiles")
        let bwURL = url.appendingPathComponent("FilmProfilesBW/profiles")
        let directories = [ccURL] + (
            FileManager.default.fileExists(atPath: bwURL.path) ? [bwURL] : [])
        return try? FilmMaterialStore(profilesDirectories: directories)
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
