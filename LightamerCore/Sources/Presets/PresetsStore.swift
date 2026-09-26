import Foundation
import Observation
import os

// ─────────────────────────────────────────────────────────────────────────────
// PresetsStore (Plan 12-4 T1; PRES-01/02; D-12-CONTEXT-5) — the app-level
// preset directory: ONE preset = ONE file under
// `~/Library/Application Support/Lightamer/Presets/<uuid>.lightamer-preset`.
//
// The YiyinFontStore 三拆 pattern (YIYIN-05; the 12-2 SmartAlbumStore twin):
//   ① session registration — the init rescans the directory into the
//     in-memory registry (the app root owns ONE store for the app lifetime);
//   ② TYPED errors — every failure mode is a `PresetError`, never a silent
//     fallback;
//   ③ startup self-heal — a corrupt / future-schema / mutual-exclusion-
//     violating file is SKIPPED into `skippedFiles` (标坏不崩) and never
//     deleted; the rest of the library stays usable.
//
// PRES-02 import/export = FILE COPY with ZERO format conversion: the bytes
// on disk are the interchange format (the exported file re-imports as-is).
// An import always lands on a FRESH uuid stem — a foreign file can never
// clobber a local one.
//
// Write discipline: `.prettyPrinted + .sortedKeys` (the container golden) +
// a SAME-DIRECTORY tmp file promoted via moveItem (L009 — never a
// cross-volume /tmp rename).
// ─────────────────────────────────────────────────────────────────────────────

public enum PresetError: Error, Equatable, Sendable {
    /// A blank/whitespace-only name (the UI trims; the store re-checks).
    case emptyName
    /// No preset with this id (the file-stem identity).
    case notFound(id: String)
    /// The file's bytes do not decode as a `.lightamer-preset` document.
    case corruptPreset(name: String)
    /// The file decodes but violates the format contract (the container's
    /// mutual-exclusion face).
    case invalidPreset(LightamerPreset.ValidationError)
    /// An export preset's recipe fails `ExportVariant.validate()` (an
    /// out-of-domain quality/percent/sizing — the T4 load-time gate).
    case invalidExportRecipe(name: String)
    /// An import source could not be read at all.
    case unreadableFile(name: String)
    /// An export-kind preset was created with no recipe (meaningless).
    case emptyExportRecipe(name: String)
    /// A 「从当前图创建预设」 composition produced NO instances (the copy
    /// skip set filtered everything — the chain is all identity defaults;
    /// an empty develop preset would apply nothing).
    case emptyComposition
}

/// One registered preset (the registry row; `id` = the file stem — a stable
/// identity that survives renames).
public struct StoredPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public var document: LightamerPreset

    public init(id: String, document: LightamerPreset) {
        self.id = id
        self.document = document
    }
}

/// `@Observable` (the App observes the registry through the environment) +
/// the NSLock (the store may be touched from multiple actors — the
/// `SmartAlbumStore` / `YiyinFontStore` posture).
@Observable
public final class PresetsStore: @unchecked Sendable {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "presets-store")

    public static let fileExtension = "lightamer-preset"

    public let directory: URL

    private let lock = NSLock()
    private var registry: [StoredPreset] = []
    /// Files the rescan skipped (corrupt JSON / future schema the reader
    /// cannot project / mutual-exclusion violation / invalid export recipe
    /// — the typed forward-compat degradation). Never deleted; surfaced for
    /// the manager's 「标坏」 display and diagnostics.
    public private(set) var skippedFiles: [String] = []

    /// Default directory:
    /// `~/Library/Application Support/Lightamer/Presets`.
    public convenience init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lightamer/Presets", isDirectory: true)
        self.init(directory: base)
    }

    /// Injected-directory init (tests + the app root's explicit layout).
    /// The startup rescan IS the self-heal: files decode or are skipped,
    /// the in-memory registry reflects exactly the readable set.
    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        rescan()
    }

    // MARK: - The rescan (the self-heal leg)

    /// Re-read every `*.lightamer-preset` in the directory (sorted for a
    /// stable registry order; failures land in `skippedFiles` — never a
    /// crash, never a deletion).
    public func rescan() {
        lock.lock()
        defer { lock.unlock() }
        registry = []
        skippedFiles = []
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where file.pathExtension.lowercased() == Self.fileExtension {
            do {
                let document = try Self.readAndValidate(fileURL: file)
                registry.append(StoredPreset(
                    id: file.deletingPathExtension().lastPathComponent,
                    document: document))
            } catch {
                // The typed degrade: the file lands on the skipped list
                // with its REASON (corrupt / future schema / mutual
                // exclusion / invalid recipe) — never a crash, never a
                // deletion.
                skippedFiles.append(file.lastPathComponent)
                Self.logger.warning(
                    "preset skipped (typed degrade, never deleted): \(file.lastPathComponent, privacy: .public) — \(String(describing: error), privacy: .public)")
            }
        }
        registry.sort {
            $0.document.name.localizedCaseInsensitiveCompare($1.document.name)
                == .orderedAscending
        }
    }

    /// Decode + validate ONE file (the shared read leg of the scan and the
    /// `loadDocument` face). TYPED throw on every failure mode.
    static func readAndValidate(fileURL: URL) throws -> LightamerPreset {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw PresetError.unreadableFile(name: fileURL.lastPathComponent)
        }
        let preset: LightamerPreset
        do {
            preset = try JSONDecoder().decode(LightamerPreset.self, from: data)
        } catch {
            throw PresetError.corruptPreset(name: fileURL.lastPathComponent)
        }
        do {
            try preset.validate()
        } catch let violation as LightamerPreset.ValidationError {
            throw PresetError.invalidPreset(violation)
        }
        // The T4 load-time export gate: every variant must pass its own
        // domain validation (quality/percent/sizing bounds) — a bad recipe
        // is a BAD PRESET, degraded at load exactly like a corrupt file.
        if preset.kind == .export {
            for variant in preset.exportRecipe ?? [] {
                do {
                    try variant.validate()
                } catch {
                    throw PresetError.invalidExportRecipe(
                        name: fileURL.lastPathComponent)
                }
            }
        }
        return preset
    }

    // MARK: - Read face

    /// The registry (sorted by name — the manager's stable order).
    public func presets() -> [StoredPreset] {
        lock.lock()
        defer { lock.unlock() }
        return registry
    }

    public func presets(kind: LightamerPreset.Kind) -> [StoredPreset] {
        lock.lock()
        defer { lock.unlock() }
        return registry.filter { $0.document.kind == kind }
    }

    public func preset(id: String) -> StoredPreset? {
        lock.lock()
        defer { lock.unlock() }
        return registry.first { $0.id == id }
    }

    /// Load ONE preset FRESH FROM DISK (the apply leg's truth read — the
    /// registry row may lag a concurrent external edit; apply must not).
    /// TYPED errors on every failure mode (the caller surfaces; never a
    /// silent fallback).
    public func loadDocument(id: String) throws -> LightamerPreset {
        let fileURL = directory.appendingPathComponent(
            id + "." + Self.fileExtension)
        return try Self.readAndValidate(fileURL: fileURL)
    }

    // MARK: - Write face (typed errors; every write re-validates)

    /// Create a preset (the manager's 「从当前图创建…」 and the export
    /// panel's 「存为预设」 land here): validates name + format, writes the
    /// file atomically, registers the row.
    @discardableResult
    public func create(
        name rawName: String,
        kind: LightamerPreset.Kind,
        category: String? = nil,
        instances: [ModuleInstance] = [],
        exportRecipe: ExportRecipe? = nil
    ) throws -> StoredPreset {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PresetError.emptyName }
        if kind == .export, (exportRecipe ?? []).isEmpty {
            throw PresetError.emptyExportRecipe(name: name)
        }
        let document = LightamerPreset(
            kind: kind, name: name, category: category,
            instances: instances, exportRecipe: exportRecipe)
        do {
            try document.validate()
        } catch let violation as LightamerPreset.ValidationError {
            throw PresetError.invalidPreset(violation)
        }

        let id = UUID().uuidString
        try write(document, id: id)
        lock.lock()
        let stored = StoredPreset(id: id, document: document)
        registry.append(stored)
        registry.sort {
            $0.document.name.localizedCaseInsensitiveCompare($1.document.name)
                == .orderedAscending
        }
        lock.unlock()
        return stored
    }

    /// Rename (the file keeps its id — only the document's name changes).
    public func rename(id: String, to rawName: String) throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PresetError.emptyName }
        try mutate(id: id) { document in
            document.name = name
        }
    }

    /// The category edit (the manager's grouping-key face; nil =
    /// uncategorized).
    public func setCategory(id: String, category: String?) throws {
        let trimmed = category.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        try mutate(id: id) { document in
            document.category = value
        }
    }

    /// Remove: the file goes FIRST (disk truth leads), then the registry
    /// row. A failed removal leaves the row (the state never lies; the
    /// next rescan reconciles).
    public func remove(id: String) throws {
        lock.lock()
        guard let index = registry.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            throw PresetError.notFound(id: id)
        }
        let stored = registry[index]
        lock.unlock()
        let file = directory.appendingPathComponent(
            stored.id + "." + Self.fileExtension)
        try FileManager.default.removeItem(at: file)
        lock.lock()
        registry.removeAll { $0.id == id }
        lock.unlock()
    }

    // MARK: - PRES-02: import / export (file copy, ZERO format conversion)

    /// Import a `.lightamer-preset` file: read → decode → validate → copy
    /// into the library under a FRESH uuid stem (a foreign file never
    /// clobbers a local one). TYPED errors on every failure mode.
    @discardableResult
    public func importPreset(from sourceURL: URL) throws -> StoredPreset {
        let document = try Self.readAndValidate(fileURL: sourceURL)
        let id = UUID().uuidString
        try write(document, id: id)
        lock.lock()
        let stored = StoredPreset(id: id, document: document)
        registry.append(stored)
        registry.sort {
            $0.document.name.localizedCaseInsensitiveCompare($1.document.name)
                == .orderedAscending
        }
        lock.unlock()
        return stored
    }

    /// Export ONE preset: copy the file's bytes VERBATIM to the
    /// destination (the on-disk format IS the interchange format). The
    /// destination is overwritten when present (the SavePanel's replace
    /// semantics).
    public func exportFile(id: String, to destination: URL) throws {
        lock.lock()
        guard registry.contains(where: { $0.id == id }) else {
            lock.unlock()
            throw PresetError.notFound(id: id)
        }
        lock.unlock()
        let source = directory.appendingPathComponent(id + "." + Self.fileExtension)
        let data: Data
        do {
            data = try Data(contentsOf: source)
        } catch {
            throw PresetError.unreadableFile(name: source.lastPathComponent)
        }
        try data.write(to: destination, options: .atomic)
    }

    // MARK: - Internals

    /// Mutate one registered document through `body`, re-validate, persist,
    /// and refresh the registry row (the rename/category edit shape).
    private func mutate(
        id: String, _ body: (inout LightamerPreset) -> Void
    ) throws {
        lock.lock()
        guard let index = registry.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            throw PresetError.notFound(id: id)
        }
        var document = registry[index].document
        lock.unlock()
        body(&document)
        do {
            try document.validate()
        } catch let violation as LightamerPreset.ValidationError {
            throw PresetError.invalidPreset(violation)
        }
        try write(document, id: id)
        lock.lock()
        registry[index].document = document
        registry.sort {
            $0.document.name.localizedCaseInsensitiveCompare($1.document.name)
                == .orderedAscending
        }
        lock.unlock()
    }

    /// The atomic write: sortedKeys encode → SAME-DIRECTORY tmp sibling →
    /// moveItem promotion (L009 — the rename is same-VOLUME atomic).
    private func write(_ document: LightamerPreset, id: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        let target = directory.appendingPathComponent(id + "." + Self.fileExtension)
        let tmp = directory.appendingPathComponent(
            ".tmp-" + UUID().uuidString + "." + Self.fileExtension)
        try data.write(to: tmp, options: .atomic)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: tmp, to: target)
    }
}
