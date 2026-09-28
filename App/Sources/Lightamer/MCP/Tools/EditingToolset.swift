import CoreGraphics
import Foundation
import ImageIO
import LightamerCore
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────────
// EditingToolset (Plan 14-2) — the MCP editing face, five tools:
//
//   render_preview  (T1)  renderedPlane → inline JPEG base64 (§RQ-14-4/8)
//   load_image      (T2)  stateless read view (planner ruling D5)
//   apply_params    (T2)  module-level upsert, three segments, GUI-live hard
//                         rejection
//   list_iops       (T3)  the handwritten per-op catalog (IopCatalog.swift)
//   export_image    (T4)  direct render → Session/Output (§RQ-14-11)
//
// PURE SWIFT CONSUMPTION FACE — zero new render code, zero new write paths,
// zero new queues (the plan's 接线 phase discipline):
//   • renders consume `QuickLookRenderer.renderedPlane` / `ExportRenderer
//     .render` verbatim (the L031 routed-queue + L014 fence discipline is
//     FIXED IN THE SOURCE; this file cannot even build a command queue);
//   • writes consume the `SessionBatchApplier` three segments (PresetApplier
//     :105-117 同构) — the sidecar bytes are never touched here;
//   • concurrency 1 for every render-class call rides the SHARED
//     `McpRenderGate` (14-1 base).
//
// Statelessness (D5, planner ruling): every tool carries its own `relPath`
// argument — the server holds NO session-level active handle, which dissolves
// the two-client load_image context-stomping problem wholesale (§RQ-14-14).
// ─────────────────────────────────────────────────────────────────────────────

enum EditingToolset {

    // MARK: - Constants (§RQ-14-8 budget table + D7; one place each)

    /// render_preview defaults (the budget table row: 1024px/q85 ≈ 1.5MB
    /// base64 — the token-efficiency line).
    static let previewDefaultLongEdge = 1024
    static let previewDefaultQuality = 85
    /// D7 (planner, 2026-09-28): the 4096 cap is CUT to 2048 — 4096/q90 =
    /// 5.5MB base64 / ~22K visual tokens per call; anything larger belongs
    /// to export_image (落盘), which the tool description says verbatim.
    static let previewMaxLongEdge = 2048
    static let previewMaxQuality = 90

    // MARK: - Seams (the App-layer reality, injected for tests)

    /// Everything the editing face consumes from the host process. The
    /// headless host, the GUI-embedded host and the tests assemble the SAME
    /// struct (the single-kernel × multi-host red line).
    struct Seams: Sendable {

        /// The open session (index store + ROOT URL). `nil` = no session —
        /// every tool answers `notSessionMember` (nothing is a member of a
        /// session that is not open).
        let session: @Sendable () async -> (store: SessionIndexStore, root: URL)?

        /// The GPU context (lazy — render-class tools only). `nil` answer =
        /// `renderFailed` ("renderer unavailable"), never a crash.
        let metal: @Sendable () async -> MetalContext?

        /// The POPULATED module registry (terminal trio + LightamerIOP —
        /// `LightamerIOPRegistry.populate` ran before this seam is built).
        let modules: @Sendable () async -> ModuleRegistry

        /// The render serial gate (concurrency 1, shared with 14-3's render
        /// class — ONE gate instance per server kernel).
        let gate: McpRenderGate

        /// The GUI-live judge (§RQ-14-3①): the editor's current image URL
        /// (MainActor hop inside the closure; nil headless). apply_params
        /// HARD-REJECTS a matching target (`imageLiveInEditor`).
        let liveImageURL: @Sendable () async -> URL?

        /// Test seam: the shared decode leg (parity legs share ONE CIRAW
        /// decode — the speckle discipline). nil = `RAWDecoder`.
        var decodeLeg: QuickLookRenderer.DecodeLeg?

        /// Test seam: render-class timeout override (seconds). nil = the
        /// `McpTimeouts` production constants.
        var renderTimeoutOverride: Double?

        init(
            session: @escaping @Sendable () async -> (store: SessionIndexStore, root: URL)?,
            metal: @escaping @Sendable () async -> MetalContext?,
            modules: @escaping @Sendable () async -> ModuleRegistry,
            gate: McpRenderGate = McpRenderGate(),
            liveImageURL: @escaping @Sendable () async -> URL? = { nil }
        ) {
            self.session = session
            self.metal = metal
            self.modules = modules
            self.gate = gate
            self.liveImageURL = liveImageURL
        }
    }

    // MARK: - Registration

    /// Registers the editing tools into `registry`. Each plan task extends
    /// this body; the snapshot tests pin every addition (the tool face IS a
    /// security face).
    static func register(into registry: McpToolRegistry, seams: Seams) async {
        await registerRenderPreview(into: registry, seams: seams)
    }

    // MARK: - Shared argument faces

    /// The required `relPath` argument (D5: every tool carries it).
    static func requiredRelPath(
        _ arguments: [String: McpJSON]
    ) throws -> String {
        guard let relPath = arguments["relPath"]?.stringValue, !relPath.isEmpty else {
            throw McpToolError.invalidParams(
                "relPath (string) is required — the editing tools are stateless "
                    + "(D5): every call names its image relative to the session root")
        }
        return relPath
    }

    /// Resolves the session + membership for `relPath` and returns the ABSOLUTE
    /// image URL. Not open → `notSessionMember`; not an indexed row →
    /// `notSessionMember` (the load_image scope is open-session members only,
    /// D-14-CONTEXT-6③).
    static func resolveMember(
        relPath: String, seams: Seams
    ) async throws -> (imageURL: URL, root: URL, store: SessionIndexStore) {
        guard let session = await seams.session() else {
            throw McpToolError.notSessionMember(
                "no Lightamer session is open on the server host")
        }
        let row = try await session.store.fetchRow(relPath: relPath)
        guard row != nil else {
            throw McpToolError.notSessionMember(
                "'\(relPath)' is not a member of the open session — load_image and "
                    + "every editing tool address open-session members by relPath only")
        }
        return (session.root.appendingPathComponent(relPath), session.root, session.store)
    }

    // MARK: - render_preview (T1)

    private static func registerRenderPreview(
        into registry: McpToolRegistry, seams: Seams
    ) async {
        await registry.register(
            McpToolDescriptor(
                name: "render_preview",
                description:
                    "Render an open-session image's SAVED edit state (the disk sidecar) "
                        + "and return it as an inline JPEG image (base64). The preview is "
                        + "the sRGB-encoded EDIT state — no yiyin frame/watermark, and NOT "
                        + "the GUI's EDR display domain. It reflects the last SAVED edit: "
                        + "edits saved by the GUI carry a ~2s debounce. Bounds: longEdge "
                        + "1...2048 (default 1024), quality 1...90 (default 85); for "
                        + "anything larger or for files on disk use export_image. Fails "
                        + "typed: renderFailed, renderTimeout (30s), notSessionMember, "
                        + "invalidParams. Errors for read-only hosts: serverReadOnly.",
                inputSchemaJSON:
                    #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"},"longEdge":{"type":"integer","minimum":1,"maximum":2048,"default":1024,"description":"Output long edge in px (rendered in-pipe at this size)"},"quality":{"type":"integer","minimum":1,"maximum":90,"default":85,"description":"JPEG quality (percent)"}},"required":["relPath"]}"#,
                readOnlyHint: true
            ),
            handler: { arguments in
                let relPath = try requiredRelPath(arguments)
                let longEdge = try intArgument(
                    arguments["longEdge"], name: "longEdge",
                    default: previewDefaultLongEdge,
                    range: 1...previewMaxLongEdge,
                    overMessage:
                        "longEdge > \(previewMaxLongEdge) would inline a multi-megabyte "
                        + "base64 payload (D7); use export_image to land a larger file "
                        + "in Session/Output/")
                let quality = try intArgument(
                    arguments["quality"], name: "quality",
                    default: previewDefaultQuality,
                    range: 1...previewMaxQuality,
                    overMessage:
                        "quality > \(previewMaxQuality) — the inline preview cap is 90 "
                        + "(D7); use export_image for quality-critical output")
                let member = try await resolveMember(relPath: relPath, seams: seams)

                return try await seams.gate.withRenderGate {
                    try await renderPreviewBody(
                        imageURL: member.imageURL, longEdge: longEdge,
                        quality: quality, seams: seams)
                }
            })
    }

    /// The render body (INSIDE the gate): bounded wait → renderedPlane →
    /// CGImage → JPEG → base64. Typed failures, never the QL embedded-
    /// preview fallback (the MCP face has no preview to lie with).
    private static func renderPreviewBody(
        imageURL: URL, longEdge: Int, quality: Int, seams: Seams
    ) async throws -> McpToolOutput {
        let seconds = seams.renderTimeoutOverride
            ?? durationSeconds(McpTimeouts.renderAndCrop)
        do {
            let base64 = try await QuickLookRenderer.boundedWait(seconds: seconds) {
                guard let metal = await seams.metal() else {
                    throw McpToolError.renderFailed("renderer unavailable on this host")
                }
                let registry = await seams.modules()
                let rendered = try await QuickLookRenderer.renderedPlane(
                    imageURL: imageURL, targetLongEdge: longEdge,
                    metal: metal, registry: registry, decodeLeg: seams.decodeLeg)
                let image = try QuickLookRenderer.image(from: rendered)
                guard let jpeg = Self.encodeJPEG(image, quality: Double(quality) / 100.0),
                    !jpeg.isEmpty
                else {
                    throw McpToolError.renderFailed(
                        "JPEG encode failed for '\(imageURL.lastPathComponent)'")
                }
                return jpeg.base64EncodedString()
            }
            return McpToolOutput([.imageBase64(base64, mimeType: "image/jpeg")])
        } catch let timeout as QuickLookRenderer.RenderTimeout {
            throw McpToolError.renderTimeout(
                "render exceeded the \(timeout.seconds)s bounded wait for "
                    + "'\(imageURL.lastPathComponent)' — the GPU work is not cancelled "
                    + "mid-flight; retry once before giving up")
        } catch let error as McpToolError {
            throw error
        } catch {
            throw McpToolError.renderFailed(
                "render failed for '\(imageURL.lastPathComponent)': \(error)")
        }
    }

    // MARK: - Argument helpers

    /// `Duration` → seconds (the `boundedWait` TimeInterval face).
    static func durationSeconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    /// An optional integer argument with a default and an inclusive range.
    /// Out-of-range → `invalidParams` with the tool-facing guidance.
    static func intArgument(
        _ value: McpJSON?, name: String, default defaultValue: Int,
        range: ClosedRange<Int>, overMessage: String
    ) throws -> Int {
        guard let value, value != .null else { return defaultValue }
        guard let int = value.intValue else {
            throw McpToolError.invalidParams("\(name) must be an integer")
        }
        guard range.contains(int) else {
            throw McpToolError.invalidParams(
                "\(name)=\(int) outside \(range.lowerBound)...\(range.upperBound): "
                    + overMessage)
        }
        return int
    }

    // MARK: - JPEG encode (the inline leg's only new bytes)

    /// CGImage → JPEG Data via ImageIO (the same encoder family the thumbs
    /// cache uses). nil = the encode failed (caller → `renderFailed`).
    static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
