import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// FilmMaterialStore — the injected-directory index of the film/paper
// profiles (Plan M3-3-01 T4, KD-4; LutLibraryStore's shape: final class,
// @unchecked Sendable, immutable after load).
//
// Directory-INJECTED by contract: Core never reads the App bundle — the
// App-side assembly (M3-3-02 coordinator wiring) injects
// Bundle.main.resourceURL/FilmProfiles/profiles; tests inject the repo's
// Resources/FilmProfiles/profiles path (FilmProfileTests' #filePath walk).
//
// Load-and-index ONCE: the initializer reads the whole directory, decodes
// every profile through the fail-closed loader, and indexes by stock id.
// A bad asset, a duplicate id or a missing id is a typed error at
// construction — the store never carries a partial index. The store does
// NOT bake or cache solver results (the runtime solve cache keyed by
// materialPairHash is M3-3-02's face; this plan ships the deterministic
// identity + the solver function bodies).
//
// LICENSING: the profile data is CC BY-SA 4.0 (see Resources/FilmProfiles/
// NOTICE); this file is schema/index logic only.
// ─────────────────────────────────────────────────────────────────────────────

/// The typed store-construction errors (KD-4 — fail-closed at load).
public enum FilmMaterialStoreError: Error, Equatable, Sendable {
    /// The injected directory could not be read.
    case directoryUnreadable
    /// Two files claim the same `info.stock` id.
    case duplicateStockId(String)
    /// A profile file carries no `info.stock` id.
    case missingStockId(String)
}

public final class FilmMaterialStore: @unchecked Sendable {

    /// Every loaded profile, keyed by `info.stock` (immutable after init).
    private let profiles: [String: FilmProfile]

    /// Read the directory, decode + validate every *.json (sorted by file
    /// name for deterministic first-seen order), index by stock id.
    public init(profilesDirectory: URL) throws {
        let names: [String]
        do {
            names = try FileManager.default
                .contentsOfDirectory(atPath: profilesDirectory.path)
                .filter { $0.hasSuffix(".json") }
                .sorted()
        } catch {
            throw FilmMaterialStoreError.directoryUnreadable
        }

        var index: [String: FilmProfile] = [:]
        index.reserveCapacity(names.count)
        for name in names {
            let profile = try FilmProfile.load(
                profilesDirectory.appendingPathComponent(name))
            guard let stock = profile.info.stock, !stock.isEmpty else {
                throw FilmMaterialStoreError.missingStockId(name)
            }
            guard index[stock] == nil else {
                throw FilmMaterialStoreError.duplicateStockId(stock)
            }
            index[stock] = profile
        }
        profiles = index
    }

    /// All film-support stocks, sorted by stock id (deterministic order
    /// for menus/UI face).
    public func filmStocks() -> [FilmProfile] {
        profiles.values
            .filter { $0.info.support == "film" }
            .sorted { ($0.info.stock ?? "") < ($1.info.stock ?? "") }
    }

    /// All paper-support stocks, sorted by stock id.
    public func paperStocks() -> [FilmProfile] {
        profiles.values
            .filter { $0.info.support == "paper" }
            .sorted { ($0.info.stock ?? "") < ($1.info.stock ?? "") }
    }

    /// Look a stock up by id (the FilmRecord.filmStock/paperStock
    /// resolution; nil = unknown id — the typed degrade is the caller's
    /// domain, KD-1).
    public func profile(id: String) -> FilmProfile? {
        profiles[id]
    }

    // MARK: - The material-pair identity (KD-4 + the E2 consumer-set note)

    /// FNV-1a 64 over the two profiles' CONSUMER data domain, film first
    /// then paper (L013: field-explicit folds — never JSON bytes, never
    /// Swift `Hasher`). The folded fields are exactly the consumed ones:
    /// log_exposure + density_curves (the dye-approximation payload),
    /// base_density + wavelengths (the E2 projection + its axis — the
    /// consumer set moves WITH the registered projection; if a future
    /// ruling drops the projection these two folds move out with it, so
    /// identity and consumption can never drift apart). Unconsumed
    /// spectral payload and metadata/info prose never enter the identity.
    ///
    /// This hash keys the runtime solve cache (M3-3-02:
    /// `fnv(pairHash ⊕ statisticHash ⊕ modeTag)` composition) — the same
    /// materials must hash identically across launches and machines.
    public static func materialPairHash(
        film: FilmProfile, paper: FilmProfile
    ) -> UInt64 {
        var combined = StableHash.fnvOffsetBasis
        combined = foldProfile(film, into: combined)
        combined = foldProfile(paper, into: combined)
        return combined
    }

    private static func foldProfile(
        _ profile: FilmProfile, into seed: UInt64
    ) -> UInt64 {
        var combined = seed
        // The stock id — UTF-8 bytes (length-unambiguous, L013).
        for byte in (profile.info.stock ?? "").utf8 {
            combined = withUnsafeBytes(of: byte) {
                StableHash.combine(combined, $0)
            }
        }
        // log_exposure — Float bit patterns, zero-extended to UInt64.
        for value in profile.logExposure {
            combined = chain(combined, UInt64(value.bitPattern))
        }
        // density_curves — row-major on-disk order.
        for row in profile.densityCurves {
            for value in row {
                combined = chain(combined, UInt64(value.bitPattern))
            }
        }
        // base_density — a nil tag then the bit pattern when present
        // (nil vs 0.0 must never collide).
        for sample in profile.baseDensity {
            switch sample {
            case .some(let value):
                combined = chain(combined, 1)
                combined = chain(combined, UInt64(value.bitPattern))
            case .none:
                combined = chain(combined, 0)
            }
        }
        // wavelengths — the projection axis.
        for value in profile.wavelengths {
            combined = chain(combined, UInt64(value.bitPattern))
        }
        return combined
    }

    /// One fixed-width fold (platform byte order — HistoryHash.chain's
    /// same encoding).
    private static func chain(
        _ seed: UInt64, _ value: UInt64
    ) -> UInt64 {
        var v = value
        return withUnsafeBytes(of: &v) { StableHash.combine(seed, $0) }
    }
}
