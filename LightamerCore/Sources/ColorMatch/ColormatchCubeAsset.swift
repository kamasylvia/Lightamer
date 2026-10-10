import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ColormatchCubeAsset (Plan M5-1-02 T4, KD-4; OQ-3) — the `.cube` derived
// asset store for the colormatch LUT arm: the baked 65³ table persists as
// `<original full name>.lra.colormatch/<bakeKeyHex>.cube` beside the
// original (the `.lra.masks/` sibling-directory convention, RasterMaskStore
// 孪生), and the module params carry ONLY `{assetRef, assetHash}` — the
// table bytes NEVER enter paramsData (the 65³ ≈ 3.3MB sidecar-bloat red
// line; the paramsData upper-bound assertion is T5's).
//
// FORMAT (self-authored, write/read SELF-CONSISTENT — the checker 回注 m5
// ruling: no promise of byte-compatibility with the external .cube
// ecosystem; `CubeLutParser` is ZERO-TOUCHED and the colormatch arm reads
// through THIS parser only): a header block
//
//     TITLE "Lightamer colormatch <solutionHashHex>"
//     LUT_3D_SIZE 65
//     DOMAIN_MIN 0.0 0.0 0.0
//     DOMAIN_MAX 1.0 1.0 1.0
//
// followed by 65³ lines of `<r> <g> <b>`, lattice order x fastest. Each
// float serializes through Swift `String(Float)` — the SHORTEST
// round-trip representation, LOCALE-INVARIANT (the decimal point is
// always `.`; a dedicated test asserts no comma form can ever appear).
// `Float(String)` parses the shortest form back to the EXACT Float32 bits,
// so write→read is bit-exact (the G1 byte-round-trip face).
//
// VALIDATION (the full-verify load): size == 65, the float count ==
// 3·65³, and the byte FNV over the FILE bytes == params.assetHash — any
// failure degrades to the VALUE `.degraded(reason)` (never a silent
// default; the module blits and the panel discloses).
//
// WRITE (L009): the payload goes to a same-directory `.tmp-<name>` file
// and promotes with the atomic rename — a crash mid-write never leaves a
// half file under the asset name.
//
// CLEANUP: same-solution old-alpha assets delete best-effort at commit
// (the `<bakeKeyHex>.cube` names share the solution prefix through the
// TITLE/kebab form `<solutionHex>-<alphaHex>.cube`); orphans are an
// observation item, not a gate.
// ─────────────────────────────────────────────────────────────────────────────

public enum ColormatchCubeAsset {

    /// The lattice level (the bake's 65).
    public static let latticeSize = 65

    /// The load outcome — the degrade leg is a VALUE with its reason (the
    /// RasterMaskStore.LoadResult 体例, minus the GPU plane: the module
    /// consumes the table).
    public enum LoadResult: Sendable, Equatable {
        case loaded(table: [SIMD3<Float>], bytesHash: UInt64)
        case degraded(reason: String)
    }

    /// `<original full name>.lra.colormatch/` beside the original.
    public static func directory(forImageURL imageURL: URL) -> URL {
        imageURL.deletingLastPathComponent().appendingPathComponent(
            imageURL.lastPathComponent + ".lra.colormatch", isDirectory: true)
    }

    /// The asset file name for one bake: `<solutionHex>-<alphaHex>.cube` —
    /// the solution prefix makes the same-solution cleanup a prefix scan.
    public static func fileName(solutionHash: UInt64, strength: Float) -> String {
        String(format: "%016llx-%08x.cube", solutionHash, strength.bitPattern)
    }

    /// The project(-image)-relative ref spelling: `<dirName>/<fileName>`.
    public static func assetRef(solutionHash: UInt64, strength: Float, forImageURL imageURL: URL) -> String {
        directory(forImageURL: imageURL).lastPathComponent + "/"
            + fileName(solutionHash: solutionHash, strength: strength)
    }

    /// Resolve an assetRef against the image URL (the resolver's only path
    /// arithmetic — the module never touches paths).
    public static func fileURL(assetRef: String, forImageURL imageURL: URL) -> URL {
        directory(forImageURL: imageURL).appendingPathComponent(
            assetRef.split(separator: "/", maxSplits: 1).last.map(String.init) ?? assetRef)
    }

    // MARK: - Serialization

    /// Serialize the table (the bake output, lattice order x fastest) into
    /// the self-authored .cube text. Every float through `String(Float)` —
    /// shortest round-trip, locale-invariant.
    public static func serialize(table: [SIMD3<Float>], solutionHash: UInt64) -> Data {
        precondition(table.count == latticeSize * latticeSize * latticeSize)
        var text = "TITLE \"Lightamer colormatch \(String(solutionHash, radix: 16))\"\n"
        text += "LUT_3D_SIZE \(latticeSize)\n"
        text += "DOMAIN_MIN 0.0 0.0 0.0\n"
        text += "DOMAIN_MAX 1.0 1.0 1.0\n"
        for voxel in table {
            // String(Float): the shortest round-trip decimal — Swift's
            // description is locale-independent (always `.`).
            text += "\(String(voxel.x)) \(String(voxel.y)) \(String(voxel.z))\n"
        }
        return Data(text.utf8)
    }

    /// The colormatch OWN reader (CubeLutParser zero-touch): header keys +
    /// strict float-triple body. Returns nil on any structural mismatch
    /// (the caller wraps it into `.degraded`).
    public static func parse(_ data: Data) -> [SIMD3<Float>]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let expected = latticeSize * latticeSize * latticeSize
        var table = [SIMD3<Float>]()
        table.reserveCapacity(expected)
        var sawSize = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let upper = line.uppercased()
            if upper.hasPrefix("TITLE") || upper.hasPrefix("DOMAIN_MIN")
                || upper.hasPrefix("DOMAIN_MAX") || upper.hasPrefix("LUT_1D_SIZE") {
                continue
            }
            if upper.hasPrefix("LUT_3D_SIZE") {
                let value = line.split(separator: " ").last.flatMap { Int($0) }
                guard value == latticeSize else { return nil }
                sawSize = true
                continue
            }
            // A float triple.
            let parts = line.split(separator: " ")
            guard parts.count == 3, sawSize,
                let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2])
            else { return nil }
            if table.count == expected { return nil }  // overlong body
            table.append(SIMD3(r, g, b))
        }
        guard sawSize, table.count == expected else { return nil }
        return table
    }

    // MARK: - Write / load

    /// Write the asset (same-directory tmp + atomic promote, L009): the
    /// exact file name comes from the (solutionHash, strength) pair — the
    /// same-solution cleanup keys on the prefix. Returns the byte FNV over
    /// the WRITTEN bytes (the params' assetHash — the decimal String face
    /// at the params layer).
    public static func write(
        table: [SIMD3<Float>], solutionHash: UInt64, strength: Float, directory: URL
    ) throws -> UInt64 {
        let data = serialize(table: table, solutionHash: solutionHash)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(fileName(solutionHash: solutionHash, strength: strength))
        return try writeAtomic(data: data, to: target)
    }

    /// L009: the tmp file lives in the TARGET's directory (same volume) and
    /// promotes with `rename(2)` — atomic, no cross-volume rename.
    private static func writeAtomic(data: Data, to target: URL) throws -> UInt64 {
        let tmp = target.deletingLastPathComponent()
            .appendingPathComponent(".tmp-" + target.lastPathComponent)
        try data.write(to: tmp, options: .atomic)
        try FileManager.default.removeItemIfExistsTransitional(at: target)
        try FileManager.default.moveItem(at: tmp, to: target)
        return StableHash.hash(try Data(contentsOf: target))
    }

    /// Load + full verification: existence, size, structure, and the byte
    /// FNV against the params' expected hash (decimal String — L013). Any
    /// failure is the VALUE `.degraded(reason)`.
    public static func load(
        assetRef: String, forImageURL imageURL: URL, expectedHash: String?
    ) -> LoadResult {
        let fileURL = fileURL(assetRef: assetRef, forImageURL: imageURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .degraded(reason: "colormatch asset missing: \(assetRef)")
        }
        guard let bytes = try? Data(contentsOf: fileURL) else {
            return .degraded(reason: "colormatch asset unreadable: \(assetRef)")
        }
        let hash = StableHash.hash(bytes)
        if let expectedHash, let expected = UInt64(expectedHash), hash != expected {
            return .degraded(
                reason: "colormatch asset hash mismatch: \(assetRef) "
                    + "(file \(hash) != ref \(expected))")
        }
        guard let table = parse(bytes) else {
            return .degraded(reason: "colormatch asset corrupt: \(assetRef)")
        }
        return .loaded(table: table, bytesHash: hash)
    }

    /// Best-effort same-solution cleanup: delete every `<solutionHex>-*.cube`
    /// in the directory EXCEPT the keep file. Orphans are an observation
    /// item — failures here never throw into the commit path.
    public static func cleanupSameSolution(
        solutionHash: UInt64, keepFileName: String, directory: URL
    ) {
        let prefix = String(format: "%016llx-", solutionHash)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        for item in contents where item.lastPathComponent.hasPrefix(prefix) {
            guard item.lastPathComponent != keepFileName,
                item.lastPathComponent.hasSuffix(".cube")
            else { continue }
            try? FileManager.default.removeItem(at: item)
        }
    }
}

// A tiny FileManager helper local to this store (removing a nonexistent
// target before promote is the NORMAL first-write case, not an error).
extension FileManager {
    fileprivate func removeItemIfExistsTransitional(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
}
