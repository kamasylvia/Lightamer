import Foundation
import LightamerCore
import Observation
import os

// ─────────────────────────────────────────────────────────────────────────────
// MetadataController (Plan 12-1 T6) — the App-side metadata WRITE face.
//
// The D-03b isolated state object bridging the UI (commands, inspector
// rows, grid menus) to the Core `MetadataService` (the single write
// implementation — GUI and the Phase 14 MCP-06 tools share it). The
// controller holds NO back-references to other states: the app root
// configures it per session open (root/store/writer/seed — the same
// store/writer pair the batch paste uses) and wires `onWrite` to the
// browser model's reload (the grid overlay's refresh seam).
//
// All failures are SC#2 soft: logged, surfaced as a `false` return where
// the caller can react (e.g. the `|` keyword rejection), never a crash.
// ─────────────────────────────────────────────────────────────────────────────

@Observable
@MainActor
final class MetadataController {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "metadata-ctl")

    /// The per-session write inputs (nil = no open session).
    private(set) var root: URL?
    private var store: SessionIndexStore?
    private var writer: BatchSidecarWriter?
    private var seed: [ModuleInstance] = []

    /// The post-write refresh seam — the app root wires it to the browser
    /// model's reload so grid/culling overlays re-render after edits.
    var onWrite: (() async -> Void)?

    func configure(
        root: URL, store: SessionIndexStore,
        writer: BatchSidecarWriter?, seed: [ModuleInstance]
    ) {
        self.root = root
        self.store = store
        self.writer = writer
        self.seed = seed
    }

    /// Session teardown (before the index closes).
    func invalidate() {
        root = nil
        store = nil
        writer = nil
        seed = []
    }

    // MARK: - Read face

    /// The metadata projection of ONE row (the inspector rows' initial
    /// value + the X/P toggle's current-value read).
    struct Snapshot: Sendable, Equatable {
        public var rating: Int64?
        public var flag: Int64?
        public var colorLabel: Int64?
        public var keywords: String?
        public var note: String?
    }

    func snapshot(relPath: String) async -> Snapshot? {
        guard let store else { return nil }
        guard let row = try? await store.fetchRow(relPath: relPath) else { return nil }
        return Snapshot(
            rating: row.rating, flag: row.flag, colorLabel: row.colorLabel,
            keywords: row.keywords, note: row.note)
    }

    // MARK: - Write face (all route through MetadataService — the single
    // implementation)

    @discardableResult
    func setRating(_ value: Int?, relPaths: [String]) async -> Bool {
        await write { try await $0.setRating(value, relPaths: relPaths) }
    }

    @discardableResult
    func setFlag(_ value: Int?, relPaths: [String]) async -> Bool {
        await write { try await $0.setFlag(value, relPaths: relPaths) }
    }

    @discardableResult
    func setColorLabel(_ value: Int?, relPaths: [String]) async -> Bool {
        await write { try await $0.setColorLabel(value, relPaths: relPaths) }
    }

    /// Whole-group keyword replacement. `false` = typed rejection (the
    /// `|` separator ban — the caller keeps the field's old value).
    @discardableResult
    func setKeywords(_ keywords: [String], relPath: String) async -> Bool {
        await write { try await $0.setKeywords(keywords, relPaths: [relPath]) }
    }

    /// The XMP-import face (Plan 12-3 T5): whole-group replacement over a
    /// target SET with the hierarchical gate OPEN — third-party
    /// `lr:hierarchicalSubject` paths legitimately carry `|`.
    @discardableResult
    func setImportedKeywords(_ keywords: [String], relPaths: [String]) async -> Bool {
        await write {
            try await $0.setKeywords(
                keywords, relPaths: relPaths, allowHierarchical: true)
        }
    }

    @discardableResult
    func appendKeywords(_ keywords: [String], relPaths: [String]) async -> Bool {
        await write { try await $0.appendKeywords(keywords, relPaths: relPaths) }
    }

    @discardableResult
    func appendNote(_ addition: String, relPaths: [String]) async -> Bool {
        await write { try await $0.appendNote(addition, relPaths: relPaths) }
    }

    private func write(
        _ body: (MetadataService) async throws -> MetadataEditOutcome
    ) async -> Bool {
        guard let root, let store else { return false }
        let service = MetadataService(
            root: root, store: store, writer: writer, seed: seed)
        do {
            let outcome = try await body(service)
            if !outcome.skippedRelPaths.isEmpty {
                Self.logger.warning(
                    "metadata edit skipped \(outcome.skippedRelPaths.count) unreadable target(s)")
            }
            await onWrite?()
            return true
        } catch {
            Self.logger.error(
                "metadata write rejected: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
