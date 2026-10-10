import CoreImage
import ImageIO
import LightamerCore
import Observation
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────────
// DepthMaskService (M4-3-01 KD-5/T4) — the App-side depth mask orchestration:
// the entry gate (pure), the release-zip resolver (ditto), the preview JPEG
// writer, the float readback, and the single commit seam hand-off.
//
// ZERO-CONSUMPTION-FACE-NEW-MECHANISM: the product lands through
// `AIMaskEditing.commitRasterMask` (the ONE seam — upsample → bake →
// MaskSpec.raster → exactly one history item), with `source: .depth`
// naming the sidecar PNG. `expectedRevision` stays nil (the Subject
// first-generation form: this CREATES the edit, it is not a refine rebake).
//
// RESOLVER ERRATUM (DECISIONS §4): the release tier's "zip → usable
// package" hop was missing end-to-end (EnhancementSession.resolvePackage
// looks for the EXTRACTED directory while ModelAssetStore.download only
// promotes the zip — the latent gap never fired because every release
// digest was nil). This plan fills it for the DEPTH leg App-side; the
// enhancement family defers to its own digest-publish batch.
//
// RACE GUARD: `generate` captures `editorState.loadedImageURL` at
// initiation and compares before the commit — a mid-inference image
// switch discards the result typed (the Lumen document-token form,
// auto_masks.py:56,75).
// ─────────────────────────────────────────────────────────────────────────────

/// The depth entry gate — a PURE function of (asset status, package
/// presence), the `AIMaskEntryGate.layerBEntry` four-state form (KD-5).
enum DepthEntryGate {

    enum Entry: Equatable, Sendable {
        /// Installed AND the extracted package sits on disk.
        case ready
        /// Downloadable guidance; `hasDigest == false` renders the
        /// 「待发布」 note (the fail-closed face — download cannot arm).
        case needsDownload(hasDigest: Bool)
        /// A download is in flight with the fraction (0…1).
        case downloading(Double)
        /// The failed face (corrupt → the self-heal note: a re-download
        /// replaces the artifact — the store's built-in behavior).
        case failed(String)
    }

    static func entry(status: ModelAssetStatus, packagePresent: Bool) -> Entry {
        switch status {
        case .bundled:
            return packagePresent ? .ready : .needsDownload(hasDigest: false)
        case .installed:
            // Installed-but-unextracted self-heals through refresh's
            // ensurePackage; if extraction failed, the download guidance
            // is the honest remaining action (a re-download re-extracts).
            return packagePresent ? .ready : .needsDownload(hasDigest: true)
        case .notInstalled:
            return .needsDownload(hasDigest: true)
        case .digestUnpublished:
            return .needsDownload(hasDigest: false)
        case .downloading(let fraction):
            return .downloading(fraction)
        case .corrupt:
            return .failed("re-download will self-heal")
        }
    }
}

extension DepthEntryGate {

    /// The toolbar's visual fold (KD-6): the service's pure gate state +
    /// the local generation phase → the five button faces. Pure = the
    /// view logic is gate-driven and unit-testable without a view.
    enum Visual: Equatable, Sendable {
        /// The one generate button (ready).
        case generate
        /// A generation is in flight (spinner replaces the button).
        case generating
        /// The guided download entry; `armed == false` renders the
        /// disabled 「待发布」 face (the fail-closed note).
        case download(armed: Bool)
        /// The download progress (mini spinner + percentage).
        case downloading(Double)
        /// The failed face (orange retry).
        case retry
    }

    static func map(service entry: Entry, running: Bool) -> Visual {
        if running { return .generating }
        switch entry {
        case .ready:
            return .generate
        case .needsDownload(let hasDigest):
            return .download(armed: hasDigest)
        case .downloading(let fraction):
            return .downloading(fraction)
        case .failed:
            return .retry
        }
    }
}

/// The release-zip → extracted-`mlpackage` hop (the resolver erratum's
/// depth-leg fill). `/usr/bin/ditto -x -k` (the Lensfun Process precedent);
/// idempotent — the extracted directory short-circuits.
struct DepthPackageResolver {

    enum ResolverError: Error, Equatable {
        case extractionFailed(String)
    }

    let locator: ModelLocator

    /// The extracted `.mlpackage` directory (assetFileName minus `.zip`),
    /// present on disk under the installed profile root.
    func extractedPackageURL(_ manifest: ModelAssetManifest) -> URL? {
        guard let profileDir = try? locator.installedProfileURL(manifest.profileID) else {
            return nil
        }
        var name = manifest.assetFileName
        if name.hasSuffix(".zip") { name = String(name.dropLast(4)) }
        let candidate = profileDir.appendingPathComponent(name)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: candidate.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return nil }
        return candidate
    }

    func packagePresent(_ manifest: ModelAssetManifest) -> Bool {
        extractedPackageURL(manifest) != nil
    }

    /// Idempotent extraction: directory present → no-op; zip present →
    /// ditto-extract next to it; neither → silent no-op (the gate owns the
    /// absent-assets face). A failed extraction throws typed.
    func ensurePackage(_ manifest: ModelAssetManifest) throws {
        if packagePresent(manifest) { return }
        guard let profileDir = try? locator.installedProfileURL(manifest.profileID) else {
            return
        }
        let zipURL = profileDir.appendingPathComponent(manifest.assetFileName)
        guard FileManager.default.fileExists(atPath: zipURL.path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, profileDir.path]
        do {
            try process.run()
        } catch {
            throw ResolverError.extractionFailed("ditto spawn: \(error)")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, packagePresent(manifest) else {
            throw ResolverError.extractionFailed(
                "ditto exit \(process.terminationStatus) for \(zipURL.path)")
        }
    }
}

/// The @MainActor orchestration face the toolbar observes (the
/// AIDownloadModel pattern: ONE instance, app-root owned).
@MainActor
@Observable
final class DepthMaskService {

    /// Sendable-facing (the progress sink and the worker calls reference
    /// it from nonisolated contexts).
    nonisolated static let profileID = ModelAssetCatalog.depthAnythingV2SmallF16.profileID

    /// The init-time weak bridge (a sink closure cannot capture a
    /// not-yet-initialized self).
    private final class ProgressSinkBox: @unchecked Sendable {
        weak var service: DepthMaskService?
        init() {}
    }

    let store: ModelAssetStore
    let resolver: DepthPackageResolver

    /// The toolbar's gate state (refresh()/download progress driven).
    private(set) var entry: DepthEntryGate.Entry = .needsDownload(hasDigest: false)

    private let makeClient: () -> AIWorkerClient

    init(
        store: ModelAssetStore? = nil,
        locator: ModelLocator = ModelLocator(),
        makeClient: @escaping () -> AIWorkerClient
    ) {
        self.resolver = DepthPackageResolver(locator: locator)
        self.makeClient = makeClient
        // The progress sink cannot capture self during init — it reaches
        // the instance through a weak box wired after initialization.
        let box = ProgressSinkBox()
        let profileID = Self.profileID
        let progressSink: @Sendable (String, Double) -> Void = { profile, fraction in
            guard profile == profileID, let service = box.service else { return }
            Task { @MainActor in
                service.entry = .downloading(fraction)
            }
        }
        self.store = store ?? ModelAssetStore(
            locator: locator, onProgress: progressSink)
        box.service = self
    }

    /// The production assembly (app root): the real store + the real
    /// one-shot client.
    convenience init() {
        self.init(makeClient: {
            AIWorkerClient(
                record: CompatRecord(path: CompatRecord.defaultPath()))
        })
    }

    // MARK: - Gate state

    /// Status → resolver → gate. Idempotent; cheap after the store's
    /// verification memo warms.
    func refresh() async {
        let manifest = ModelAssetCatalog.depthAnythingV2SmallF16
        let status = await store.status(for: Self.profileID)
        var present = false
        if case .installed = status {
            try? resolver.ensurePackage(manifest)
            present = resolver.packagePresent(manifest)
        }
        entry = DepthEntryGate.entry(status: status, packagePresent: present)
    }

    // MARK: - Download then generate (the single-tap full journey)

    /// Download → extract → one generation. Every leg's failure surfaces
    /// as the typed toast; the gate re-reads at the end.
    func downloadThenGenerate(
        coordinator: PipeCoordinator, editorState: EditorState,
        editingState: LayerEditingState, metal: MetalContext
    ) async {
        do {
            try await store.download(Self.profileID)
            try resolver.ensurePackage(ModelAssetCatalog.depthAnythingV2SmallF16)
            await refresh()
            try await generate(
                coordinator: coordinator, editorState: editorState,
                editingState: editingState, metal: metal)
            editorState.presentToast(
                String(localized: "ai_toast_depth_download_done"))
        } catch {
            await refresh()
            editorState.presentToast(
                String(localized: "ai_toast_depth_download_failed") + " (\(error))")
        }
    }

    // MARK: - Generation (KD-5)

    /// decodeFrameInput → preview JPEG → worker runDepth → float readback →
    /// four-stage pipeline → race guard → commitRasterMask (one item).
    func generate(
        coordinator: PipeCoordinator, editorState: EditorState,
        editingState: LayerEditingState, metal: MetalContext
    ) async throws {
        guard let (input, width, height) = AIMaskEditing.decodeFrameInput(coordinator) else {
            throw AIMaskError.invalidInput("no decoded frame for inference")
        }
        // The race token: a mid-inference switch discards the result.
        let anchor = editorState.loadedImageURL

        let manifest = ModelAssetCatalog.depthAnythingV2SmallF16
        let client = makeClient()
        defer { Task { await client.stop() } }

        // The file legs hop off the main actor (the EnhanceDialogModel
        // @Sendable-crop form); the pipeline itself is Core-pure.
        let previewURL = try await Task.detached(priority: .userInitiated) {
            try Self.writePreviewJPEG(from: input)
        }.value
        defer { try? FileManager.default.removeItem(at: previewURL) }
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lightamer-depth-\(UUID().uuidString).f32")
        defer { try? FileManager.default.removeItem(at: outURL) }

        _ = try await client.runDepth(
            Self.profileID, inPath: previewURL.path, outPath: outURL.path)
        let depth = try await Task.detached(priority: .userInitiated) {
            try Self.readDepthPlane(
                from: outURL,
                expectedWidth: manifest.inputSize,
                expectedHeight: manifest.inputShortEdge ?? manifest.inputSize)
        }.value
        let alpha = try DepthMaskPipeline.nearMask(depth: depth)
        try await Self.commit(
            alpha, decodeWidth: width, decodeHeight: height, anchor: anchor,
            coordinator: coordinator, editorState: editorState,
            editingState: editingState, metal: metal)
    }

    /// The race guard + the ONE commit seam. Internal static = the testable
    /// seam (the coordinator-driven harness can drive the guard without a
    /// model). Mismatch → typed discard, zero state change.
    @MainActor
    static func commit(
        _ alpha: AIMaskPlane, decodeWidth: Int, decodeHeight: Int,
        anchor: URL?, coordinator: PipeCoordinator, editorState: EditorState,
        editingState: LayerEditingState, metal: MetalContext
    ) async throws {
        guard let anchor, editorState.loadedImageURL == anchor else {
            throw AIMaskError.invalidInput(
                "image switched during depth inference — result discarded")
        }
        _ = try await AIMaskEditing.commitRasterMask(
            plane: alpha, source: .depth,
            decodeWidth: decodeWidth, decodeHeight: decodeHeight,
            label: String(localized: "history_depth_mask"),
            activateTool: .brush,
            coordinator: coordinator, editorState: editorState,
            editingState: editingState, metal: metal)
    }

    // MARK: - Preview JPEG (KD-3: sRGB q0.92, long edge 1040 cap)

    /// The inference input: render the decode frame into an sRGB 8-bit
    /// CGImage, cap the long edge at 1040 (2× the model input — small IPC
    /// with information headroom), encode JPEG q 0.92 into a tmp file.
    nonisolated static func writePreviewJPEG(
        from input: AIMaskInput, longEdgeCap: Int = 1040, quality: Double = 0.92
    ) throws -> URL {
        let extent = input.ciImage.extent
        guard extent.width >= 1, extent.height >= 1 else {
            throw AIMaskError.invalidInput("zero-extent preview frame")
        }
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw AIMaskError.invalidInput("sRGB colorspace unavailable")
        }
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let cgImage = context.createCGImage(
            input.ciImage, from: extent, format: .RGBA8, colorSpace: sRGB)
        else {
            throw AIMaskError.invalidInput("preview render failed")
        }
        // Long-edge cap (deterministic `.medium` draw).
        let longEdge = max(cgImage.width, cgImage.height)
        let rendered: CGImage
        if longEdge > longEdgeCap {
            let scale = Double(longEdgeCap) / Double(longEdge)
            let width = max(1, Int((Double(cgImage.width) * scale).rounded()))
            let height = max(1, Int((Double(cgImage.height) * scale).rounded()))
            guard let scaled = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else {
                throw AIMaskError.invalidInput("preview scale context failed")
            }
            scaled.interpolationQuality = .medium
            scaled.draw(
                cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let drawn = scaled.makeImage() else {
                throw AIMaskError.invalidInput("preview scale failed")
            }
            rendered = drawn
        } else {
            rendered = cgImage
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lightamer-depth-preview-\(UUID().uuidString).jpg")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else {
            throw AIMaskError.invalidInput("preview destination failed")
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, rendered, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw AIMaskError.invalidInput("preview encode failed")
        }
        return url
    }

    // MARK: - Float readback (the 8-byte header form)

    /// Header check first (w/h from the manifest single source — checker
    /// m2), then the row-major F32 LE payload.
    nonisolated static func readDepthPlane(
        from url: URL, expectedWidth: Int, expectedHeight: Int
    ) throws -> AIMaskPlane {
        let data = try Data(contentsOf: url)
        guard data.count >= 8 else {
            throw AIMaskError.invalidInput("depth output truncated: \(data.count) bytes")
        }
        let width = data.withUnsafeBytes {
            UInt32(littleEndian: $0.load(fromByteOffset: 0, as: UInt32.self))
        }
        let height = data.withUnsafeBytes {
            UInt32(littleEndian: $0.load(fromByteOffset: 4, as: UInt32.self))
        }
        guard Int(width) == expectedWidth, Int(height) == expectedHeight else {
            throw AIMaskError.invalidInput(
                "depth output shape \(width)×\(height) != expected "
                    + "\(expectedWidth)×\(expectedHeight)")
        }
        let expectedBytes = 8 + expectedWidth * expectedHeight * 4
        guard data.count == expectedBytes else {
            throw AIMaskError.invalidInput(
                "depth output payload \(data.count) != \(expectedBytes) bytes")
        }
        let floats = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            (0..<(expectedWidth * expectedHeight)).map { index in
                raw.load(
                    fromByteOffset: 8 + index * 4, as: Float32.self)
            }
        }
        return AIMaskPlane(
            width: expectedWidth, height: expectedHeight, floats: floats)
    }
}
