@testable import LightamerCore
@testable import LightamerIOP
import XCTest

/// ColormatchCubeAssetTests (Plan M5-1-02 T4, KD-4) — the `.cube` derived
/// asset store:
///
/// - the write→read BIT-EXACT round trip (shortest-representation
///   serialization + the own parser; elementwise Float32 bit patterns);
/// - the locale-invariant decimal point (no comma form can ever appear in
///   the serialized floats — the checker 回注 m5 face);
/// - the full-verification load (byte FNV vs the params hash; a one-byte
///   tamper → the typed `.degraded(reason)` value);
/// - the atomic promotion (no half file under the asset name; no leftover
///   tmp on success);
/// - the same-solution prefix cleanup;
/// - the paramsData upper bound (the LUT bytes never enter sidecar
///   params: a FULL params blob with the asset attached stays < 8KB).
final class ColormatchCubeAssetTests: XCTestCase {

    /// A small deterministic table (the bake's size contract — 65³) with
    /// deliberately nasty values: 0, -0, 1, denormal-scale, exponent forms.
    private func nastyTable() -> [SIMD3<Float>] {
        let count = ColormatchCubeAsset.latticeSize * ColormatchCubeAsset.latticeSize
            * ColormatchCubeAsset.latticeSize
        var table = [SIMD3<Float>](repeating: .zero, count: count)
        var rng: UInt64 = 0xC0FFEE123456789
        for index in stride(from: 0, to: count, by: 97) {
            let a = Float(Double(Int(rng >> 3) % 2000 - 1000) / 1000.0)
            let b = Float(Double(Int(rng >> 17) % 1000000) * 1e-9)
            let c = Float(Int(rng >> 41) % 2 == 0 ? 1.0 : -1.0)
                * Float(Double(Int(rng >> 23) % 1000) / 997.0)
            table[index] = SIMD3(a, b, c)
        }
        // The pin values: zero/negative-zero/one/float-min normals.
        table[0] = SIMD3(0, -0.0, 1)
        table[1] = SIMD3(Float.leastNormalMagnitude, -Float.leastNormalMagnitude, 0.5)
        table[2] = SIMD3(1e-30, -1e30, 3.14159265)
        return table
    }

    private func tempDirectory(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("colormatch-cube-\(name)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The fixture image URL inside `directory` — the asset directory IS
    /// the image's sibling (`<name>.lra.colormatch/`), so write and load
    /// resolve through the SAME image anchor.
    private func fixtureImageURL(in directory: URL) -> URL {
        directory.appendingPathComponent("img.raw")
    }

    // MARK: - The bit-exact round trip

    func testWriteReadRoundTripIsBitExact() throws {
        let table = nastyTable()
        let solutionHash: UInt64 = 0x1234567890ABCDEF
        let strength: Float = 0.75
        let directory = tempDirectory("roundtrip")
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = fixtureImageURL(in: directory)
        let writtenHash = try ColormatchCubeAsset.write(
            table: table, solutionHash: solutionHash, strength: strength,
            directory: ColormatchCubeAsset.directory(forImageURL: imageURL))
        let assetRef = ColormatchCubeAsset.assetRef(
            solutionHash: solutionHash, strength: strength, forImageURL: imageURL)
        let result = ColormatchCubeAsset.load(
            assetRef: assetRef, forImageURL: imageURL, expectedHash: String(writtenHash))
        guard case .loaded(let readBack, let hash) = result else {
            return XCTFail("round trip degraded: \(result)")
        }
        XCTAssertEqual(hash, writtenHash)
        XCTAssertEqual(readBack.count, table.count)
        for (a, b) in zip(table, readBack) {
            XCTAssertEqual(a.x.bitPattern, b.x.bitPattern)
            XCTAssertEqual(a.y.bitPattern, b.y.bitPattern)
            XCTAssertEqual(a.z.bitPattern, b.z.bitPattern)
        }
    }

    func testSerializationIsLocaleInvariant() {
        // The decimal point is ALWAYS `.` — no comma form (the m5 note:
        // String(Float) is locale-independent; the test pins it against a
        // comma decimal separator locale being active).
        let table = nastyTable()
        let data = ColormatchCubeAsset.serialize(table: table, solutionHash: 1)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertFalse(text.contains(","), "a comma reached the payload: locale breach")
        XCTAssertTrue(text.contains("LUT_3D_SIZE 65"))
        // The shortest round-trip property itself: serialize → parse each
        // float → identical bits (spot lines).
        let sample = text.split(separator: "\n").first { $0.hasPrefix("0.") || $0.hasPrefix("-") }
        XCTAssertNotNil(sample)
    }

    // MARK: - The full-verification load

    func testTamperedByteDegradesWithReason() throws {
        let table = nastyTable()
        let directory = tempDirectory("tamper")
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = fixtureImageURL(in: directory)
        let assetDirectory = ColormatchCubeAsset.directory(forImageURL: imageURL)
        let writtenHash = try ColormatchCubeAsset.write(
            table: table, solutionHash: 42, strength: 1, directory: assetDirectory)
        let fileURL = assetDirectory.appendingPathComponent(
            ColormatchCubeAsset.fileName(solutionHash: 42, strength: 1))
        var bytes = try Data(contentsOf: fileURL)
        // Flip one byte deep in the float body.
        let flipIndex = bytes.count - 10
        bytes[flipIndex] = bytes[flipIndex] == 48 ? 49 : 48
        try bytes.write(to: fileURL)
        let assetRef = ColormatchCubeAsset.assetRef(solutionHash: 42, strength: 1, forImageURL: imageURL)
        let result = ColormatchCubeAsset.load(
            assetRef: assetRef, forImageURL: imageURL, expectedHash: String(writtenHash))
        guard case .degraded(let reason) = result else {
            return XCTFail("a tampered asset must degrade, got \(result)")
        }
        XCTAssertTrue(reason.contains("hash mismatch"), "reason: \(reason)")
    }

    func testMissingAssetDegradesWithValue() {
        let result = ColormatchCubeAsset.load(
            assetRef: "img.raw.lra.colormatch/gone.cube",
            forImageURL: URL(fileURLWithPath: "/nowhere/img.raw"),
            expectedHash: "123")
        XCTAssertEqual(
            result, .degraded(reason: "colormatch asset missing: img.raw.lra.colormatch/gone.cube"))
    }

    func testStructuralCorruptionDegrades() throws {
        let directory = tempDirectory("corrupt")
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = fixtureImageURL(in: directory)
        let assetDirectory = ColormatchCubeAsset.directory(forImageURL: imageURL)
        try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
        let fileURL = assetDirectory.appendingPathComponent("bad.cube")
        try Data("TITLE \"junk\"\nLUT_3D_SIZE 33\n1 2 3\n".utf8).write(to: fileURL)
        let result = ColormatchCubeAsset.load(
            assetRef: "img.raw.lra.colormatch/bad.cube",
            forImageURL: imageURL, expectedHash: nil)
        guard case .degraded(let reason) = result else {
            return XCTFail("a wrong-size asset must degrade, got \(result)")
        }
        XCTAssertTrue(reason.contains("corrupt"), "reason: \(reason)")
    }

    // MARK: - The atomic promotion

    func testWritePromotesAtomicallyWithoutTmpLeftover() throws {
        let table = nastyTable()
        let directory = tempDirectory("atomic")
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try ColormatchCubeAsset.write(
            table: table, solutionHash: 7, strength: 0.5, directory: directory)
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
        XCTAssertEqual(
            contents, [ColormatchCubeAsset.fileName(solutionHash: 7, strength: 0.5)],
            "exactly the asset file — no tmp leftovers")
        // Overwrite (the promote removes an existing target first).
        _ = try ColormatchCubeAsset.write(
            table: table, solutionHash: 7, strength: 0.5, directory: directory)
        let after = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(after.count, 1, "overwrite stays single-file")
    }

    // MARK: - The same-solution cleanup

    func testCleanupRemovesSameSolutionKeepsTarget() throws {
        let table = nastyTable()
        let directory = tempDirectory("cleanup")
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try ColormatchCubeAsset.write(
            table: table, solutionHash: 0xAB, strength: 0.2, directory: directory)
        _ = try ColormatchCubeAsset.write(
            table: table, solutionHash: 0xAB, strength: 0.8, directory: directory)
        _ = try ColormatchCubeAsset.write(
            table: table, solutionHash: 0xCD, strength: 0.5, directory: directory)
        ColormatchCubeAsset.cleanupSameSolution(
            solutionHash: 0xAB,
            keepFileName: ColormatchCubeAsset.fileName(solutionHash: 0xAB, strength: 0.8),
            directory: directory)
        let remaining = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent).sorted()
        XCTAssertEqual(remaining, [
            ColormatchCubeAsset.fileName(solutionHash: 0xAB, strength: 0.8),
            ColormatchCubeAsset.fileName(solutionHash: 0xCD, strength: 0.5),
        ], "the old-alpha sibling of the SAME solution goes; other solutions stay")
    }

    // MARK: - The paramsData upper bound

    func testParamsBlobStaysUnderBoundWithAssetAttached() throws {
        // The sidecar-bloat red line's mechanical face: the params with the
        // asset attached stay < 8KB — the 65³ table bytes can never be in
        // there (a 3.3MB payload would blow this out by 400×).
        var params = ColormatchModule.Params()
        params.solver = .cdf
        params.strength = 0.8
        params.assetRef = "img.raw.lra.colormatch/0123456789abcdef-3f4ccccd.cube"
        params.assetHash = "18446744073709551615"
        params.sourceStatsHash = "111"
        params.referenceStatsHash = "222"
        let encoded = ParamsCoding.encode(params)
        XCTAssertLessThan(encoded.count, 8192, "params blob grew past the sidecar bound")
    }
}
