@testable import Lightamer
@testable import LightamerCore
import Foundation
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// McpRefineMasksToolTests (Plan LUMEN-C T3) — the refine_masks tool face:
// ① the snapshot leg (the tool joins the editing domain — the name set +
// the VERBATIM schema, the security-face pin), ② the typed UNAVAILABLE face
// (nil seam — the headless default), ③ the live-image requirement (a
// non-live relPath fails typed and the seam is never called), ④ the unknown
// id typed error surfaces (the shell's typed mapping), ⑤ the render-gate
// serialization (two concurrent calls never overlap — the render-class
// discipline). The seam is injected in every leg — no GUI coordinator here.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class McpRefineMasksToolTests: XCTestCase {

    private var tempDirectory: URL!

    /// A tiny @Sendable counter box (the closure-capture discipline).
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        var value = 0
        func bump() { lock.lock(); value += 1; lock.unlock() }
    }

    override func setUpWithError() throws {
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-refine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    /// Synthetic session (the McpEditingToolsetTests shape): one member
    /// image; `liveRel` names it when the live seam should match.
    private func makeSession(liveRel: String?) async throws -> (
        root: URL, imageURL: URL, store: SessionIndexStore
    ) {
        let root = tempDirectory.appendingPathComponent(
            "session-\(UUID().uuidString)", isDirectory: true)
        let capture = root.appendingPathComponent("Capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        let imageURL = capture.appendingPathComponent("DSC00012.ARW")
        try Data(repeating: 0xCD, count: 64).write(to: imageURL)
        let store = SessionIndexStore(sessionRoot: root)
        let entry = SessionScanEntry(
            relPath: "Capture/DSC00012.ARW",
            mtime: (try? imageURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate)?.timeIntervalSince1970 ?? 0,
            size: 64)
        _ = try await store.openSession(
            root: root,
            scan: AsyncStream { continuation in
                continuation.yield(SessionScanPage(entries: [entry]))
                continuation.finish()
            })
        return (root, imageURL, store)
    }

    private func makeSeams(
        session: (root: URL, imageURL: URL, store: SessionIndexStore)?,
        liveURL: URL?,
        refineMasks: (@Sendable ([String]) async throws -> Void)?
    ) -> EditingToolset.Seams {
        var seams = EditingToolset.Seams(
            session: { [session] in
                guard let session else { return nil }
                return (session.store, session.root)
            },
            metal: { nil },
            modules: { ModuleRegistry() },
            gate: McpRenderGate(),
            liveImageURL: { liveURL })
        seams.refineMasks = refineMasks
        return seams
    }

    private static let schemaJSON =
        #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root — MUST be the editor's current image"},"maskIds":{"type":"array","items":{"type":"string","description":"The owning layer's UUID"},"minItems":1,"maxItems":30,"description":"Layer UUIDs whose AI raster masks to refine"}},"required":["relPath","maskIds"]}"#

    // MARK: ① the snapshot leg

    func testRefineMasksJoinsTheEditingDomainSnapshot() async throws {
        let registry = McpToolRegistry()
        await EditingToolset.register(into: registry, seams: makeSeams(
            session: nil, liveURL: nil, refineMasks: nil))
        let descriptors = await registry.descriptors()
        let tool = try XCTUnwrap(
            descriptors.first(where: { $0.name == "refine_masks" }),
            "refine_masks joins the editing domain")
        XCTAssertEqual(tool.inputSchemaJSON, Self.schemaJSON)
        XCTAssertEqual(tool.readOnlyHint, false)
        XCTAssertFalse(tool.description.isEmpty)
        // The whole editing set: the ten names (nine pre-LUMEN-C + this).
        let names = Set(descriptors.map(\.name))
        for expected in ["load_image", "apply_params", "render_preview", "list_iops",
            "export_image", "list_luts", "copy_adjustments", "paste_adjustments",
            "match_color", "refine_masks"] {
            XCTAssertTrue(names.contains(expected), "missing \(expected)")
        }
        XCTAssertEqual(descriptors.count, 10, "the editing domain grew to ten")
    }

    // MARK: ② the typed unavailable face (nil seam)

    func testNilSeamAnswersTypedUnavailable() async throws {
        let session = try await makeSession(liveRel: "Capture/DSC00012.ARW")
        let registry = McpToolRegistry()
        await EditingToolset.register(into: registry, seams: makeSeams(
            session: session, liveURL: session.imageURL, refineMasks: nil))
        do {
            _ = try await registry.call(
                name: "refine_masks",
                arguments: [
                    "relPath": .string("Capture/DSC00012.ARW"),
                    "maskIds": .array([.string(UUID().uuidString)]),
                ])
            XCTFail("the nil seam must type out")
        } catch let error as McpToolError {
            guard case .renderFailed(let message) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertTrue(message.contains("unavailable"), message)
        }
    }

    // MARK: ③ the live-image requirement

    func testNonLiveRelPathFailsTypedWithoutCallingTheSeam() async throws {
        let session = try await makeSession(liveRel: nil)
        let registry = McpToolRegistry()
        let seamCalls = Counter()
        await EditingToolset.register(into: registry, seams: makeSeams(
            session: session, liveURL: nil,
            refineMasks: { _ in seamCalls.bump() }))
        do {
            _ = try await registry.call(
                name: "refine_masks",
                arguments: [
                    "relPath": .string("Capture/DSC00012.ARW"),
                    "maskIds": .array([.string(UUID().uuidString)]),
                ])
            XCTFail("a non-live relPath must type out")
        } catch let error as McpToolError {
            guard case .invalidParams(let message) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertTrue(message.contains("EDITOR's current image"), message)
        }
        XCTAssertEqual(seamCalls.value, 0, "the seam is never reached off-live")
    }

    // MARK: ④ the unknown-id typed error surfaces

    func testUnknownIDTypedErrorSurfaces() async throws {
        let session = try await makeSession(liveRel: "Capture/DSC00012.ARW")
        let registry = McpToolRegistry()
        await EditingToolset.register(into: registry, seams: makeSeams(
            session: session, liveURL: session.imageURL,
            refineMasks: { ids in
                // The shell's mapping: the coordinator's typed unknown face
                // lands as invalidParams with the reason.
                throw McpToolError.invalidParams(
                    "refine_masks: unknown or non-AI mask id: \(ids.first ?? "?")")
            }))
        let bad = UUID().uuidString
        do {
            _ = try await registry.call(
                name: "refine_masks",
                arguments: [
                    "relPath": .string("Capture/DSC00012.ARW"),
                    "maskIds": .array([.string(bad)]),
                ])
            XCTFail("an unknown id must type out")
        } catch let error as McpToolError {
            guard case .invalidParams(let message) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertTrue(message.contains(bad), message)
        }
        // The happy leg: the seam runs, the queued summary returns.
        final class Box: @unchecked Sendable {
            var ids: [String] = []
        }
        let received = Box()
        let seams = makeSeams(session: session, liveURL: session.imageURL,
            refineMasks: { ids in received.ids = ids })
        let registry2 = McpToolRegistry()
        await EditingToolset.register(into: registry2, seams: seams)
        let output = try await registry2.call(
            name: "refine_masks",
            arguments: [
                "relPath": .string("Capture/DSC00012.ARW"),
                "maskIds": .array([.string("id-1"), .string("id-2")]),
            ])
        guard case .text(let text) = output.content.first else {
            return XCTFail("expected a text payload")
        }
        XCTAssertEqual(received.ids, ["id-1", "id-2"])
        XCTAssertTrue(text.contains("\"queued\" : 2") || text.contains("queued"), text)
    }

    // MARK: ⑤ the render-gate serialization

    func testRenderGateSerializesConcurrentRefines() async throws {
        let session = try await makeSession(liveRel: "Capture/DSC00012.ARW")
        let registry = McpToolRegistry()
        final class Overlap: @unchecked Sendable {
            private let lock = NSLock()
            var inside = 0
            var maxInside = 0
            func enter() {
                lock.lock()
                inside += 1
                maxInside = max(maxInside, inside)
                lock.unlock()
            }
            func leave() {
                lock.lock()
                inside -= 1
                lock.unlock()
            }
        }
        let overlap = Overlap()
        await EditingToolset.register(into: registry, seams: makeSeams(
            session: session, liveURL: session.imageURL,
            refineMasks: { _ in
                overlap.enter()
                try? await Task.sleep(for: .milliseconds(60))
                overlap.leave()
            }))
        func callRefine(_ id: String) -> Task<McpToolOutput?, Never> {
            Task {
                (try? await registry.call(
                    name: "refine_masks",
                    arguments: [
                        "relPath": McpJSON.string("Capture/DSC00012.ARW"),
                        "maskIds": McpJSON.array([.string(id)]),
                    ]))
            }
        }
        let first = callRefine("a")
        let second = callRefine("b")
        _ = await (first.value, second.value)
        XCTAssertEqual(overlap.maxInside, 1, "the render gate serializes the calls")
    }
}
