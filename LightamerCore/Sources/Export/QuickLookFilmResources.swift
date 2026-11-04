import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// QuickLookFilmResources (spektra-module P1 T6', r4-m3) — the appex→host
// resource helper in its TESTABLE shape: the bundle root rides a
// parameter (the appex passes its host bundle's Resources; tests pass a
// fixture root). The appex's Env inlines the same two-path join today;
// this helper is the shared spelling both faces pin.
// ─────────────────────────────────────────────────────────────────────────────

public struct QuickLookFilmResources: Sendable {
    public let bundleRoot: URL

    public init(bundleRoot: URL) {
        self.bundleRoot = bundleRoot
    }

    /// The CC + BW store directories (the BW leg drops when absent —
    /// the host-assembly degrade twin).
    public func storeDirectories() -> [URL] {
        let cc = bundleRoot.appendingPathComponent("Resources/FilmProfiles/profiles")
        let bw = bundleRoot.appendingPathComponent("Resources/FilmProfilesBW/profiles")
        if FileManager.default.fileExists(atPath: bw.path) {
            return [cc, bw]
        }
        return [cc]
    }
}
