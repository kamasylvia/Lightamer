import Foundation
import LightamerIOP

// ─────────────────────────────────────────────────────────────────────────
// LensfunDataDistribution (Plan LENS-03 T3, D-LENS-6 / X7) — the pinned
// snapshot's seeder + the database-location priority + the manual
// SHA-verified update channel.
//
// PRIORITY (X7): customPath (user-supplied, the pre-existing
// `lensfun.customPath` key — LENS-03 zero-change) > BUNDLED SEED (the
// app bundle's Lensfun/version_1, copied into the support directory on
// first run) > DOWNLOADED copy (the manual update channel's install
// target) > absent.
//
// SEEDER (the LutLibraryStore precedent): the sentinel = "exists AND
// byte-equal" skips; any drift re-copies that file; missing files
// copy. Per-FILE comparison (a future snapshot upgrade triggers a
// partial copy, not a whole-directory blowaway).
//
// UPDATE CHANNEL: manual only (no automatic fetch). The official
// tar.bz2 is downloaded, its SHA-256 verified against the REGISTERED
// value (LensfunPinnedSnapshot.archiveSHA256 — the README's registered
// value), and a mismatch REFUSES the install (never a silent unknown
// database). The legacy master.zip download path survives in
// LensfunDownloadService as the no-seed fallback.
//
// dbTag: the ACTIVE database's identity = SHA-256 of the sorted
// per-file (name, hash) manifest, first 16 hex — the LENS-04 snapshot
// audit face (NOT a render face; it never folds into paramsHash).
// ─────────────────────────────────────────────────────────────────────────

/// The pinned snapshot's registered identity (the README's values, in
/// code for the SHA-verified update gate).
enum LensfunPinnedSnapshot {
    static let sourceURL = URL(string: "https://lensfun.github.io/db/version_1.tar.bz2")!
    /// The official archive's SHA-256 (Resources/Lensfun/README.md).
    static let archiveSHA256 = "97c9f8059accae0128a413bc610a04a4548e8da2764a6d3d60d82bf917639457"
    /// The检取 date (the README's).
    static let checkoutDate = "2026-10-21"
}

enum LensfunDataDistribution {

    /// The SHA-256 of a file's bytes (hex, lowercase).
    static func fileSHA256(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256Hex.of(data)
    }

    /// The ACTIVE database's dbTag: the sorted per-file (name, hash)
    /// manifest's SHA-256, first 16 hex. nil = the directory has no XML.
    static func dbTag(directory: URL) -> String? {
        let fm = FileManager.default
        guard let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter({ $0.pathExtension == "xml" })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }),
            !files.isEmpty
        else { return nil }
        var manifest = ""
        for file in files {
            let hash = fileSHA256(at: file) ?? "unreadable"
            manifest += file.lastPathComponent + ":" + hash + "\n"
        }
        return String(SHA256Hex.of(Data(manifest.utf8)).prefix(16))
    }

    /// The bundled seed directory (the folder reference keeps the
    /// Lensfun/version_1 hierarchy inside the app bundle).
    static func bundledSeed() -> URL? {
        let url = Bundle.main.resourceURL?.appendingPathComponent("Lensfun/version_1", isDirectory: true)
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Seed the bundled snapshot into the support directory (per-file
    /// sentinel: exists AND byte-equal skips; drift re-copies; missing
    /// copies). Returns the seeded directory when any XML is present.
    @discardableResult
    static func seedIfNeeded(bundleID: String = Bundle.main.bundleIdentifier ?? "com.kamasylvia.lightamer") -> URL? {
        guard let seed = bundledSeed() else { return nil }
        let root = LensfunDownloadService.supportDirectory(bundleID: bundleID)
        let dest = root.appendingPathComponent("version_1-seeded", isDirectory: true)
        let fm = FileManager.default
        guard let files = (try? fm.contentsOfDirectory(at: seed, includingPropertiesForKeys: nil))?
            .filter({ $0.pathExtension == "xml" }), !files.isEmpty
        else { return nil }
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        for file in files {
            let target = dest.appendingPathComponent(file.lastPathComponent)
            let same = (try? fileSHA256(at: target)) == fileSHA256(at: file)
                && fm.fileExists(atPath: target.path)
            guard !same else { continue }
            if fm.fileExists(atPath: target.path) {
                try? fm.removeItem(at: target)
            }
            try? fm.copyItem(at: file, to: target)
        }
        return dest
    }

    /// The FULL location resolution (X7 priority), seeding on the way and
    /// installing the store as the side effect. Replaces the panel-era
    /// `resolveAndInstall` as the launch face (LightamerShell).
    @discardableResult
    static func resolveAndInstall(bundleID: String = Bundle.main.bundleIdentifier ?? "com.kamasylvia.lightamer") -> LensfunDataLocation {
        // 1. custom path (the pre-existing key; zero-change semantics).
        if let custom = UserDefaults.standard.string(forKey: LensfunDownloadService.customPathKey),
           !custom.isEmpty {
            let url = URL(fileURLWithPath: custom, isDirectory: true)
            if LensfunStore.install(directory: url) {
                return .custom(url)
            }
        }
        // 2. the bundled seed (copied into the support dir on first run).
        if let seeded = seedIfNeeded(bundleID: bundleID),
           LensfunStore.install(directory: seeded) {
            return .seeded(seeded)
        }
        // 3. the downloaded copy (the update channel's install target or
        //    the legacy first-run download).
        let dir = LensfunDownloadService.supportDirectory(bundleID: bundleID)
            .appendingPathComponent("version_1", isDirectory: true)
        if LensfunStore.install(directory: dir) {
            return .downloaded(dir)
        }
        return .absent
    }

    // MARK: - The manual SHA-verified update channel

    enum UpdateOutcome: Sendable, Equatable {
        case installed(URL)
        case shaMismatch(expected: String, actual: String)
        case downloadFailed
    }

    /// Download the official archive → verify the SHA-256 against the
    /// registered value → install as the DOWNLOADED copy. Any mismatch
    /// refuses the install (never a silent unknown database). Manual
    /// only — nothing here runs on a timer.
    static func checkForUpdates() async -> UpdateOutcome {
        let staging = LensfunDownloadService.supportDirectory()
            .appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            let archive = staging.appendingPathComponent("version_1.tar.bz2")
            let (tmpURL, _) = try await URLSession.shared.download(from: LensfunPinnedSnapshot.sourceURL)
            try FileManager.default.moveItem(at: tmpURL, to: archive)
            let archiveData = try Data(contentsOf: archive)
            let actual = SHA256Hex.of(archiveData)
            guard actual == LensfunPinnedSnapshot.archiveSHA256 else {
                return .shaMismatch(expected: LensfunPinnedSnapshot.archiveSHA256, actual: actual)
            }
            // Unpack (the archive nests version_1/*.xml).
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            proc.arguments = ["-xjf", archive.path, "-C", staging.path]
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return .downloadFailed }
            let unpacked = staging.appendingPathComponent("version_1", isDirectory: true)
            let xmls = (try? FileManager.default.contentsOfDirectory(
                at: unpacked, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "xml" } ?? []
            guard !xmls.isEmpty else { return .downloadFailed }
            let root = LensfunDownloadService.supportDirectory()
            let dest = root.appendingPathComponent("version_1", isDirectory: true)
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            for xml in xmls {
                let target = dest.appendingPathComponent(xml.lastPathComponent)
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.moveItem(at: xml, to: target)
            }
            if LensfunStore.install(directory: dest) {
                return .installed(dest)
            }
            return .downloadFailed
        } catch {
            return .downloadFailed
        }
    }
}

/// The raw SHA-256 hex helper (CryptoKit-free — a compact implementation
/// keeps the App target's dependency surface unchanged).
enum SHA256Hex {
    static func of(_ data: Data) -> String {
        // #if canImport(CryptoKit) is always true on macOS 27 — the
        // import sits at the top of the file's conditional block.
        SHA256HexImpl.digest(data)
    }
}

import CryptoKit

enum SHA256HexImpl {
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
