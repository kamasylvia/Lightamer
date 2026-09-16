import Foundation
import XCTest

/// Fixture access for the decode tests (Plan 06).
///
/// Two tiers, by design (recorded deviation from the plan's
/// "bundle everything into the test target" reading):
///
/// 1. **Raster fixtures** (`sample-gradient.{jpg,heic,png,tiff}`) are small
///    and tracked — they ride in the LightamerTests bundle via the
///    `Resources/TestFixtures/**` resource glob in `Project.swift` and are
///    loaded with `Bundle(for:)`.
///
/// 2. **Real camera RAW fixtures** (Plan 05's CC0 downloads,
///    ~1.2 GB / 13 samples from raw.pixls.us) are NOT tracked in git and
///    NOT bundled — bundling would bloat the repo and every CI checkout.
///    They live untracked at `<repo>/.work/01-05/samples/` (the same copies
///    Spike A/B measured). Tests resolve them per the search order below and
///    `XCTSkip` with a documented reason when a machine has not run the
///    Plan 05 download. On this machine the RAW tests run for real
///    (quality gate: real camera RAW decodes in tests).
///
/// RAW sample search order (first hit wins, per file):
/// 1. `LIGHTAMER_RAW_SAMPLES_DIR` env override (CI / custom checkouts).
/// 2. `~/Library/Application Support/Lightamer/TestRAW/` — the internal-disk
///    mirror. This exists because the repo checkout typically sits on an
///    external/USB volume, which is a TCC *Removable Volumes* protected
///    location: an xctest agent whose responsible process lacks the grant
///    blocks forever inside `open()` when the screen is LOCKED (the consent
///    prompt cannot be presented). Copying the samples to the internal disk
///    keeps the suite runnable headless/locked (recorded Plan 06 finding).
/// 3. `<repo>/.work/01-05/samples/` — the canonical Plan 05 location.
final class Fixtures {

    /// Candidate RAW sample directories, in resolution order.
    private static let candidateDirectories: [URL] = {
        var dirs: [URL] = []
        if let override = ProcessInfo.processInfo.environment["LIGHTAMER_RAW_SAMPLES_DIR"] {
            dirs.append(URL(fileURLWithPath: override, isDirectory: true))
        }
        if let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first {
            dirs.append(appSupport.appendingPathComponent("Lightamer/TestRAW", isDirectory: true))
        }
        let testsDir = (#filePath as NSString).deletingLastPathComponent // Tests/LightamerTests
        let repoRoot = ((testsDir as NSString).deletingLastPathComponent as NSString)
            .deletingLastPathComponent // repo root
        dirs.append(URL(fileURLWithPath: repoRoot, isDirectory: true)
            .appendingPathComponent(".work/01-05/samples", isDirectory: true))
        return dirs
    }()

    /// Resolve a sample against the first candidate directory that has it.
    private static func sample(_ fileName: String) -> URL {
        candidateDirectories.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent(fileName).path)
        }.map { $0.appendingPathComponent(fileName) }
            ?? candidateDirectories[0].appendingPathComponent(fileName)
    }

    // ── RAW camera samples (file names as downloaded by Plan 05) ──

    /// Canon CR3 (~31 MB) — RAW-01.
    static var cr3: URL { sample("IMG_4276.CR3") }
    /// Nikon Z8 NEF lossless (~61 MB) — RAW-01; RAW 9 NOT supported at GM
    /// (Spike A) → the D-22 silent-fallback fixture (version-pinned).
    static var nef: URL { sample("Nikon_Z8_raw_14_bit_lossless_compression.NEF") }
    /// Sony A7R V ARW lossless-c (~86 MB) — RAW-01; RAW 9 capable at GM
    /// (Spike B measured v9 ≈ 766 ms on this exact file) → the D-22
    /// opt-in fixture.
    static var arw: URL { sample("7RM5-LosslessCompressedLarge.ARW") }
    /// Fujifilm RAF (~43 MB, X-Trans) — RAW-01; fast lossless decode.
    static var raf: URL { sample("DSCF0021.RAF") }
    /// Adobe DNG (~23 MB) — RAW-02.
    static var dng: URL { sample("5G4A9394-compressed-lossless.DNG") }

    /// Skip unless the RAW sample exists (machines without the Plan 05
    /// download skip with this documented reason; never fails them).
    static func require(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip(
                "RAW fixture missing: \(url.lastPathComponent). "
                    + "Run the Plan 05 sample download (untracked .work/01-05/samples)."
            )
        }
    }

    // ── Raster fixtures (tracked, bundled with the test target) ──

    static func raster(_ name: String, _ ext: String) throws -> URL {
        guard let url = Bundle(for: Fixtures.self)
            .url(forResource: name, withExtension: ext)
        else {
            throw XCTSkip("Bundled raster fixture missing: \(name).\(ext)")
        }
        return url
    }
}
