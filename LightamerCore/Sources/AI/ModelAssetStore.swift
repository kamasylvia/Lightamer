import CryptoKit
import Foundation

/// Status of one model asset profile (KD-3).
public enum ModelAssetStatus: Sendable, Equatable {
    /// Present in the app bundle folder reference (zero download/install).
    case bundled
    /// Installed under Application Support and hash-verified.
    case installed
    /// Downloadable right now (digest published, nothing installed).
    case notInstalled
    /// Release-tier profile whose digest was never published — download is
    /// refused (fail-closed; the UI face shows "待发布").
    case digestUnpublished
    /// A download is in flight with the given fraction (0…1).
    case downloading(Double)
    /// Installed artifact's hash no longer matches (next successful
    /// `download` self-heals by re-fetching over it).
    case corrupt
}

/// Typed download/store failures (checker E4: failures surface as typed
/// errors, never silent state).
public enum ModelAssetStoreError: Error, Equatable, Sendable {
    case unknownProfile(String)
    case bundledNotDownloadable(String)
    case digestUnpublished(String)
    case checksumMismatch(expected: String, actual: String)
    case unexpectedHTTPStatus(Int)
    case allSourcesFailed
    case alreadyDownloading(String)
}

/// Resolve / download / verify / activate model assets (KD-3).
///
/// Download order is fixed for China-direct friendliness:
/// GitHub Release (version-locked URL) → hf-mirror → huggingface.co.
/// Bytes stream into `<modelsRoot>/<profile_id>.tmp/<assetFileName>` (a
/// SAME-PARENT sibling dir — L009, never /tmp across volumes), are hashed
/// incrementally (CryptoKit SHA-256, streaming: the 834 MB Jina archive is
/// never fully resident), and are promoted by same-volume rename only after
/// the digest matches. Failure/cancellation removes the tmp directory.
public actor ModelAssetStore {

    private let manifestProvider: @Sendable (String) -> ModelAssetManifest?
    private let digestProvider: @Sendable (String) -> ModelAssetDigestEntry?
    private let locator: ModelLocator
    private let session: URLSession
    private let onProgress: (@Sendable (String, Double) -> Void)?

    private var inFlight: [String: Double] = [:]

    /// Memo of verified installed artifacts: profileID → (path, size, mtime)
    /// fingerprint. Avoids re-hashing an 834 MB archive on every `status`.
    private struct VerificationKey: Equatable {
        let path: String
        let size: Int
        let mtime: Double
    }
    private var verificationMemo: [String: (key: VerificationKey, verified: Bool)] = [:]

    public init(
        manifestProvider: @escaping @Sendable (String) -> ModelAssetManifest? = {
            ModelAssetCatalog.manifest(for: $0)
        },
        digestProvider: @escaping @Sendable (String) -> ModelAssetDigestEntry? = {
            ModelAssetDigests.digest(for: $0)
        },
        locator: ModelLocator = ModelLocator(),
        session: URLSession = .shared,
        onProgress: (@Sendable (String, Double) -> Void)? = nil
    ) {
        self.manifestProvider = manifestProvider
        self.digestProvider = digestProvider
        self.locator = locator
        self.session = session
        self.onProgress = onProgress
    }

    // MARK: Status

    public func status(for profileID: String) async -> ModelAssetStatus {
        guard let manifest = manifestProvider(profileID) else {
            return .notInstalled
        }
        if inFlight[profileID] != nil {
            return .downloading(inFlight[profileID] ?? 0)
        }
        // Bundled wins (KD-3): the folder reference short-circuits.
        if locator.bundledProfileURL(profileID) != nil {
            return .bundled
        }
        if let installed = installedArtifactURL(profileID, manifest: manifest) {
            let verified = await verifyInstalledArtifact(
                profileID, manifest: manifest, url: installed
            )
            return verified ? .installed : .corrupt
        }
        if manifest.tier == .gitHubRelease, digestProvider(profileID) == nil {
            return .digestUnpublished
        }
        return .notInstalled
    }

    /// Bundled profile directory (CLIP family) or verified installed
    /// artifact URL; nil when absent/corrupt. Bundled > installed (KD-3).
    public func modelURL(for profileID: String) async -> URL? {
        guard let manifest = manifestProvider(profileID) else { return nil }
        if let bundled = locator.bundledProfileURL(profileID) {
            return bundled
        }
        guard let installed = installedArtifactURL(profileID, manifest: manifest) else {
            return nil
        }
        let verified = await verifyInstalledArtifact(profileID, manifest: manifest, url: installed)
        return verified ? installed : nil
    }

    // MARK: Download

    /// Download → verify → promote (KD-3). Throws typed errors; cancellation
    /// (Task cancellation) removes the tmp directory before rethrowing.
    public func download(_ profileID: String) async throws {
        guard let manifest = manifestProvider(profileID) else {
            throw ModelAssetStoreError.unknownProfile(profileID)
        }
        guard manifest.tier == .gitHubRelease else {
            throw ModelAssetStoreError.bundledNotDownloadable(profileID)
        }
        guard inFlight[profileID] == nil else {
            throw ModelAssetStoreError.alreadyDownloading(profileID)
        }
        guard let digest = digestProvider(profileID) else {
            // Fail-closed: an unpublished digest refuses the download
            // (AC #2; the Alcedo broken-link anti-pattern inverted).
            throw ModelAssetStoreError.digestUnpublished(profileID)
        }

        let tmpDir = try locator.installedProfileTmpURL(profileID)
        let finalDir = try locator.installedProfileURL(profileID)
        let tmpFile = tmpDir.appendingPathComponent(manifest.assetFileName)

        inFlight[profileID] = 0
        defer {
            inFlight[profileID] = nil
            try? FileManager.default.removeItem(at: tmpDir)
            verificationMemo[profileID] = nil
        }

        do {
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: tmpFile.path, contents: nil)

            let sources = Self.downloadSources(for: manifest)
            var fetched = false
            for source in sources {
                do {
                    try await fetch(from: source, to: tmpFile, digest: digest, profileID: profileID)
                    fetched = true
                    break
                } catch let error as ModelAssetStoreError {
                    // A 404 from one source falls through to the next
                    // (source-order test asserts this sequence); anything
                    // else (checksum, cancel) propagates immediately.
                    if case .unexpectedHTTPStatus = error { continue }
                    throw error
                }
            }
            // Exhausted every source without a fetch: aggregate typed error
            // (the per-source 404s are already visible in request telemetry).
            guard fetched else {
                throw ModelAssetStoreError.allSourcesFailed
            }

            // Promote: same-volume rename into the final profile directory.
            try FileManager.default.createDirectory(at: finalDir, withIntermediateDirectories: true)
            let finalFile = finalDir.appendingPathComponent(manifest.assetFileName)
            if FileManager.default.fileExists(atPath: finalFile.path) {
                try FileManager.default.removeItem(at: finalFile)
            }
            try FileManager.default.moveItem(at: tmpFile, to: finalFile)
        } catch is CancellationError {
            throw CancellationError()
        }
    }    /// Remove the installed copy (tmp scratch included). No-op when the
    /// profile has nothing installed (bundled assets are untouched).
    public func remove(_ profileID: String) async throws {
        verificationMemo[profileID] = nil
        let root = try locator.installationRoot()
        for dir in [
            root.appendingPathComponent(profileID, isDirectory: true),
            root.appendingPathComponent("\(profileID).tmp", isDirectory: true),
        ] {
            if FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.removeItem(at: dir)
            }
        }
    }

    // MARK: Internals

    /// Fixed source order: Release (version-locked) → hf-mirror → HF.
    static func downloadSources(for manifest: ModelAssetManifest) -> [URL] {
        var urls: [URL] = []
        if let tag = manifest.releaseTag {
            urls.append(URL(string: "https://github.com/kamasylvia/Lightamer/releases/download/\(tag)/\(manifest.assetFileName)")!)
        }
        let encodedFile = manifest.hfFallback.file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? manifest.hfFallback.file
        urls.append(URL(string: "https://hf-mirror.com/\(manifest.hfFallback.repo)/resolve/\(manifest.revision)/\(encodedFile)")!)
        urls.append(URL(string: "https://huggingface.co/\(manifest.hfFallback.repo)/resolve/\(manifest.revision)/\(encodedFile)")!)
        return urls
    }

    private func fetch(
        from source: URL,
        to destination: URL,
        digest: ModelAssetDigestEntry,
        profileID: String
    ) async throws {
        let (bytes, response) = try await session.bytes(for: URLRequest(url: source))
        guard let http = response as? HTTPURLResponse else {
            throw ModelAssetStoreError.unexpectedHTTPStatus(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ModelAssetStoreError.unexpectedHTTPStatus(http.statusCode)
        }

        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var hasher = SHA256()
        var received = 0
        let expected = max(digest.byteCount, 1)
        var lastReported = -1.0
        // AsyncBytes yields UInt8 — buffer into 64KB blocks before hashing
        // and writing (block granularity is also the progress cadence).
        var buffer = Data()
        buffer.reserveCapacity(1 << 16)

        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                buffer.append(byte)
                if buffer.count >= 1 << 16 {
                    hasher.update(data: buffer)
                    received += buffer.count
                    try handle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                    let fraction = min(Double(received) / Double(expected), 1.0)
                    if fraction - lastReported >= 0.01 || fraction >= 1.0 {
                        lastReported = fraction
                        reportProgress(profileID, fraction)
                    }
                }
            }
            if !buffer.isEmpty {
                hasher.update(data: buffer)
                received += buffer.count
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
            reportProgress(profileID, min(Double(received) / Double(expected), 1.0))
        } catch let error as URLError where error.code == .cancelled {
            // Task cancellation surfaces from the session as URLError.cancelled
            // (the bytes iterator) — normalize to CancellationError.
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        }

        let actualHex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actualHex == digest.sha256Hex else {
            throw ModelAssetStoreError.checksumMismatch(
                expected: digest.sha256Hex, actual: actualHex
            )
        }
        guard received == digest.byteCount else {
            throw ModelAssetStoreError.checksumMismatch(
                expected: "\(digest.byteCount) bytes", actual: "\(received) bytes"
            )
        }
    }

    /// Actor-isolated progress bookkeeping + consumer callback (64KB-block
    /// granularity; the consumer maps fraction to its task snapshot —
    /// M2-10-03 registry, no UI in this plan).
    private func reportProgress(_ profileID: String, _ fraction: Double) {
        inFlight[profileID] = fraction
        onProgress?(profileID, fraction)
    }

    /// The installed distribution artifact (file), or nil.
    private func installedArtifactURL(
        _ profileID: String, manifest: ModelAssetManifest
    ) -> URL? {
        guard let root = try? locator.installationRoot() else { return nil }
        let file = root
            .appendingPathComponent(profileID, isDirectory: true)
            .appendingPathComponent(manifest.assetFileName)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }
        return file
    }

    /// Hash-verify the installed artifact against the published digest.
    /// Memoized per (path, size, mtime); nil digest counts as unverifiable
    /// (caller decides what that means for the status face).
    private func verifyInstalledArtifact(
        _ profileID: String, manifest: ModelAssetManifest, url: URL
    ) async -> Bool {
        guard let digest = digestProvider(profileID) else { return false }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? Int) ?? -1
        let mtime = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = VerificationKey(path: url.path, size: size, mtime: mtime)
        if let memo = verificationMemo[profileID], memo.key == key {
            return memo.verified
        }
        // Primary artifact hash + byte count.
        guard size == digest.byteCount else {
            verificationMemo[profileID] = (key, false)
            return false
        }
        let actual = (try? Self.sha256Hex(ofFileAt: url)) ?? ""
        let verified = actual == digest.sha256Hex
        // Auxiliaries only exist for bundled multi-file profiles; a release
        // archive is self-contained.
        if verified {
            for auxiliary in digest.auxiliaryFiles {
                let auxURL = url.deletingLastPathComponent().appendingPathComponent(auxiliary.fileName)
                guard FileManager.default.fileExists(atPath: auxURL.path),
                      (try? Self.sha256Hex(ofFileAt: auxURL)) == auxiliary.sha256Hex else {
                    verificationMemo[profileID] = (key, false)
                    return false
                }
            }
        }
        verificationMemo[profileID] = (key, verified)
        return verified
    }

    /// Streaming SHA-256 (large archives are never fully resident).
    static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 16) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Digest of a distribution ARTIFACT — file or directory.
    ///
    /// File: plain SHA-256. Directory (.mlpackage trees): canonical tree
    /// hash — sort files by relative posix path, one UTF-8 line per file
    /// `<relpath> <size> <sha256>\n`, SHA-256 over the concatenation. This
    /// mirrors Scripts/ai-models/build_default_bundle.sh's Python
    /// implementation EXACTLY (byte-identical algorithm; the two sides
    /// cross-verify the bundled assets).
    public static func artifactDigestHex(of url: URL) throws -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard isDirectory.boolValue else {
            return try sha256Hex(ofFileAt: url)
        }
        var hasher = SHA256()
        for (relPath, size, fileHash) in try artifactTreeEntries(of: url) {
            hasher.update(data: Data("\(relPath) \(size) \(fileHash)\n".utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Total byte count of an artifact (file size, or the recursive file
    /// byte total for a directory tree).
    public static func artifactByteCount(of url: URL) throws -> Int {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard isDirectory.boolValue else {
            return (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        }
        return try artifactTreeEntries(of: url).reduce(0) { $0 + $1.1 }
    }

    /// (relPath, size, fileSHA256) for every file under a directory, sorted
    /// by relPath — the single source of the tree-hash ordering contract.
    private static func artifactTreeEntries(
        of directory: URL
    ) throws -> [(String, Int, String)] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else {
            throw CocoaError(.fileReadUnknown)
        }
        var rows: [(String, Int, String)] = []
        // L039: enumerator physicalizes the root spelling (/var →
        // /private/var under the firmlink) — strip BOTH spellings.
        let prefix = directory.path + "/"
        let physicalPrefix = "/private" + prefix
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let path = fileURL.path
            let relPath: String
            if path.hasPrefix(prefix) {
                relPath = String(path.dropFirst(prefix.count))
            } else if path.hasPrefix(physicalPrefix) {
                relPath = String(path.dropFirst(physicalPrefix.count))
            } else {
                relPath = fileURL.lastPathComponent
            }
            let size = values.fileSize ?? 0
            rows.append((relPath, size, try sha256Hex(ofFileAt: fileURL)))
        }
        return rows.sorted { $0.0 < $1.0 }
    }
}
