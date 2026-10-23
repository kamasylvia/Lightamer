import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// CullViewLoader (Plan LUMEN-B T4, X7/D-LU-1/6) — the cull face's image
// supply: the camera-rendered DISPLAY tier read straight off the embedded
// preview (ZERO RAW decode — the Lumen ViewLoader discipline), a small LRU
// of decoded views, a 2-deep FULL-SIZE memory LRU for the 100% face, the
// ±3 read-ahead (low-priority tail insert), and a production cap of 2
// (the ThumbnailProductionGate shape, reused).
//
// Tiers (两档两用途 — D-LU-10's separation, X7):
//   • display (2560) — `CGImageSourceCreateThumbnailAtIndex` max pixel
//     2560 over the EMBEDDED preview. Not the Session thumbnail tier and
//     never the analysis tier (three edges, three consumers, zero sharing).
//   • full — the 100% face: the largest embedded preview when it clears the
//     `full_size` judgment (embedded ≥ 50% of the sensor's pixels — Lumen
//     previews.py embedded_view 直译: the verdict rides the extraction);
//     otherwise the RAW fallback DECODE leg (the T3 cache route — a hit
//     serves from the smart-preview cache).
//
// The loader never decodes on a view-body path (the body-purity red line):
// every leg is an actor-isolated async production behind the gate.
// ─────────────────────────────────────────────────────────────────────────────

actor CullViewLoader {

    /// The display tier long edge (Lumen VIEW_EDGE 直译 — D-LU-10: this is
    /// the LU3 display档, never the analysis档 nor the Session thumbnail档).
    static let displayLongEdge = 2560

    /// Decoded display views kept (Lumen VIEWS = 14).
    static let viewCapacity = 14

    /// Full-size planes kept for the 100%/compare face (D-LU-6 cap 2).
    static let fullCapacity = 2

    /// The read-ahead window on each side (Lumen AHEAD = 3).
    static let aheadWindow = 3

    /// The full-size judgment threshold (embedded ≥ 50% sensor pixels).
    static let fullSizeRatio = 0.5

    /// The RAW fallback decode leg (the T3 cache route): source URL →
    /// full-quality CGImage. Production = SmartPreviewStore.shared.load +
    /// SmartPreviewRender; tests inject counters.
    typealias FullDecodeLeg = @Sendable (URL) async throws -> CGImage

    /// The source-properties seam (the full_size judgment's denominator;
    /// tests inject synthetic properties — CGImageSourceCopyPropertiesAtIndex
    /// is untestable against real RAW files in CI).
    typealias PropertiesProvider = @Sendable (URL) -> (pixelWidth: Int, pixelHeight: Int)?

    /// One full-tier production: the plane plus whether the EMBEDDED
    /// preview served it (false = the RAW fallback decode did).
    struct FullProduction: Sendable {
        let image: CGImage
        let isEmbedded: Bool
    }

    private let decodeLeg: FullDecodeLeg?
    private let properties: PropertiesProvider
    private let gate: ThumbnailProductionGate

    /// The display LRU + the full-size LRU (D-LU-6) + the pending table
    /// (the in-flight dedup, one (url, tier) at a time).
    private var views: [URL: CGImage] = [:]
    private var viewOrder: [URL] = []
    private var fulls: [URL: CGImage] = [:]
    private var fullOrder: [URL] = []
    private var pending: [Key: Task<CGImage?, Never>] = [:]
    private var pendingFull: [URL: Task<FullProduction?, Never>] = [:]
    /// The cached full_size verdicts (the header's faces-box face reads it).
    private(set) var fullSizeVerdicts: [URL: Bool] = [:]

    /// Completed productions counter (the test observability face — LRU
    /// hits and merged requests never bump it).
    private(set) var productionCount = 0
    /// The RAW fallback decode invocations (the test observability face —
    /// a full_size source never bumps it).
    private(set) var fallbackDecodeCount = 0

    struct Key: Hashable {
        let url: URL
    }

    init(
        decodeLeg: FullDecodeLeg? = nil,
        properties: @escaping PropertiesProvider = { url in
            CullViewLoader.sourcePixels(url: url)
        }
    ) {
        self.decodeLeg = decodeLeg ?? CullViewLoader.defaultDecodeLeg()
        self.properties = properties
        self.gate = ThumbnailProductionGate(limit: Self.fullCapacity)
    }

    // MARK: - Request face

    /// The display view for `url`: memory → in-flight merge → produce
    /// (embedded direct read). `front` = the user-facing request (gate
    /// queue head); the ±3 read-ahead inserts at the TAIL (front=false —
    /// the prioritize 反向同形).
    func displayImage(for url: URL, front: Bool = true) async -> CGImage? {
        if let cached = accessView(url) { return cached }
        let key = Key(url: url)
        if let running = pending[key] {
            return await running.value
        }
        let gate = self.gate
        let task = Task.detached(priority: .userInitiated) { () -> CGImage? in
            await gate.acquire(id: Int64(key.hashValue))
            defer { Task { await gate.release() } }
            return Self.embeddedDisplay(url: url)
        }
        pending[key] = task
        let image = await task.value
        pending[key] = nil
        if let image {
            productionCount += 1
            insertView(url, image)
        }
        return image
    }

    /// The full-size image for `url` plus whether the embedded preview
    /// served it (false = the RAW fallback decode leg did).
    func fullImage(for url: URL) async -> (image: CGImage, isEmbedded: Bool)? {
        if let cached = accessFull(url) {
            return (cached, fullSizeVerdicts[url] ?? false)
        }
        if let running = pendingFull[url] {
            guard let produced = await running.value else { return nil }
            return (produced.image, produced.isEmbedded)
        }
        let gate = self.gate
        let leg = self.decodeLeg
        let properties = self.properties
        let task = Task.detached(priority: .userInitiated) { () -> FullProduction? in
            await gate.acquire(id: Int64(url.hashValue))
            defer { Task { await gate.release() } }
            // The embedded arm: the largest embedded preview, verdict riding
            // the extraction (Lumen embedded_view 同形).
            if let embedded = Self.embeddedFullSize(url: url) {
                let sourcePixels = properties(url).map { $0.pixelWidth * $0.pixelHeight } ?? 0
                let verdict = sourcePixels > 0
                    && Double(embedded.width * embedded.height)
                        >= Double(sourcePixels) * Self.fullSizeRatio
                if verdict {
                    return FullProduction(image: embedded, isEmbedded: true)
                }
            }
            // The fallback arm: the RAW decode through the T3 cache.
            guard let leg else { return nil }
            guard let image = try? await leg(url) else { return nil }
            return FullProduction(image: image, isEmbedded: false)
        }
        pendingFull[url] = task
        let produced = await task.value
        pendingFull[url] = nil
        guard let produced else { return nil }
        productionCount += 1
        if !produced.isEmbedded { fallbackDecodeCount += 1 }
        fullSizeVerdicts[url] = produced.isEmbedded
        insertFull(url, produced.image)
        return (produced.image, produced.isEmbedded)
    }

    /// The read-ahead: the neighbour URLs at low priority (the caller
    /// computes the ±3 window; the requests take the gate-queue TAIL).
    func readAhead(_ urls: [URL]) {
        for url in urls {
            Task { _ = await self.displayImage(for: url, front: false) }
        }
    }

    // MARK: - LRU faces (the MemoryLRU order discipline)

    private func accessView(_ url: URL) -> CGImage? {
        guard views[url] != nil else { return nil }
        viewOrder.removeAll { $0 == url }
        viewOrder.append(url)
        return views[url]
    }

    private func insertView(_ url: URL, _ image: CGImage) {
        views[url] = image
        viewOrder.removeAll { $0 == url }
        viewOrder.append(url)
        while viewOrder.count > Self.viewCapacity {
            let evicted = viewOrder.removeFirst()
            views[evicted] = nil
        }
    }

    private func accessFull(_ url: URL) -> CGImage? {
        guard fulls[url] != nil else { return nil }
        fullOrder.removeAll { $0 == url }
        fullOrder.append(url)
        return fulls[url]
    }

    private func insertFull(_ url: URL, _ image: CGImage) {
        fulls[url] = image
        fullOrder.removeAll { $0 == url }
        fullOrder.append(url)
        while fullOrder.count > Self.fullCapacity {
            let evicted = fullOrder.removeFirst()
            fulls[evicted] = nil
        }
    }

    /// The queued production count (the test observability face — the gate
    /// window tests read it through the loader).
    func queuedCountForTesting() async -> Int {
        await gate.pendingCount
    }

    /// The LRU order face (front = least recently used).
    func orderForTesting() -> (views: [URL], fulls: [URL]) {
        (viewOrder, fullOrder)
    }

    // MARK: - ImageIO legs (nonisolated statics)

    /// The source's declared pixel dims (the sensor face for RAWs — the
    /// full_size judgment's denominator).
    nonisolated static func sourcePixels(url: URL) -> (pixelWidth: Int, pixelHeight: Int)? {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        else { return nil }
        guard let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }

    /// The DISPLAY tier: the embedded preview straight through the
    /// thumbnail API at max 2560 (zero RAW decode).
    nonisolated static func embeddedDisplay(url: URL) -> CGImage? {
        embeddedThumbnail(url: url, maxPixel: Self.displayLongEdge)
    }

    /// The FULL tier's embedded arm: the largest embedded preview WITHOUT
    /// a RAW decode (the thumbnail API with an unbounded max pixel size —
    /// ImageIO serves the embedded preview data, never the RAW demosaic).
    nonisolated static func embeddedFullSize(url: URL) -> CGImage? {
        embeddedThumbnail(url: url, maxPixel: Int.max)
    }

    private nonisolated static func embeddedThumbnail(url: URL, maxPixel: Int) -> CGImage? {
        let options = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else { return nil }
        return image
    }

    /// The production decode leg (gate ③): the T3 cache route — the store's
    /// shared load (hit = the cached plane; miss = the shared decode leg +
    /// quantize + backfill) rendered to the display currency.
    nonisolated private static func defaultDecodeLeg() -> FullDecodeLeg {
        let context = CIContext()
        return { url in
            let plane = try await SmartPreviewStore.shared.load(
                url: url,
                processVersion: RenderProcessVersion.current.rawValue,
                decode: { try await SmartPreviewRender.decodePlane(url: $0) })
            guard let image = SmartPreviewRender.cgImage(plane, context: context) else {
                throw AppError.decodeFailed(
                    "smart preview render failed for \(url.lastPathComponent)")
            }
            return image
        }
    }
}
