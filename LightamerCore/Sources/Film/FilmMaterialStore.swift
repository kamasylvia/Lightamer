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

    /// M9-2 T3: the taking-filter table — loaded from any
    /// `camera_filters.json` sitting beside the profile DIRECTORIES (the
    /// BW set's root); a missing file is legal (empty table — the filter
    /// picker hides). Immutable after init.
    private let cameraFilters: [String: CameraFilterTable.Filter]

    /// The loaded filter table (the picker's data source; the coordinator
    /// resolves the record's `cameraFilter` name through it).
    public var filters: [String: CameraFilterTable.Filter] {
        cameraFilters
    }

    /// Read the directory, decode + validate every *.json (sorted by file
    /// name for deterministic first-seen order), index by stock id.
    public convenience init(profilesDirectory: URL) throws {
        try self.init(profilesDirectories: [profilesDirectory])
    }

    /// M9-2 T2: the MULTI-directory face — the CC set and the self-digitized
    /// BW set live in physically separate directories (the licensing
    /// boundary the two NOTICEs document) and index into ONE store.
    /// Directories are visited in array order (sorted per directory); the
    /// duplicate-id guard spans the union — a BW id colliding with a CC id
    /// fails closed at construction.
    public init(profilesDirectories: [URL]) throws {
        var index: [String: FilmProfile] = [:]
        var filters: [String: CameraFilterTable.Filter] = [:]
        for profilesDirectory in profilesDirectories {
            let names: [String]
            do {
                names = try FileManager.default
                    .contentsOfDirectory(atPath: profilesDirectory.path)
                    .filter { $0.hasSuffix(".json") }
                    .sorted()
            } catch {
                throw FilmMaterialStoreError.directoryUnreadable
            }
            index.reserveCapacity(index.count + names.count)
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
            // M9-2 T3: the sibling filter table (first-seen wins across
            // directories — the BW root is the only expected seat).
            let filterURL = profilesDirectory.deletingLastPathComponent()
                .appendingPathComponent("camera_filters.json")
            if FileManager.default.fileExists(atPath: filterURL.path),
                filters.isEmpty {
                filters = try CameraFilterTable.load(url: filterURL)
            }
        }
        profiles = index
        cameraFilters = filters
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
    /// Swift `Hasher`). The folded fields: log_exposure + density_curves
    /// (the dye-approximation payload), base_density + wavelengths (the
    /// E2 projection + its axis), and — M9-2 T3 (D-M92-5's alignment) —
    /// log_sensitivity + channel_density + viewing_illuminant (the
    /// spectral build's three CONSUMED spectral keys, grep-verified) and
    /// midscale_neutral_density (a PRE-FOLD: the engine consumes nothing
    /// from it today, but a future consumption widening must not silently
    /// share stale cache slots — the two reasons are registered
    /// separately in M9-2-DECISIONS). Unconsumed metadata/info prose
    /// never enters the identity.
    ///
    /// This hash keys the runtime solve cache (M3-3-02:
    /// `fnv(pairHash ⊕ statisticHash ⊕ modeTag)` composition) — the same
    /// materials must hash identically across launches and machines. The
    /// M9-2 fold widening moves EVERY existing pair key ONCE (the
    /// registered cold-miss window — the hash is a cache key, not a
    /// persisted identity, so old builds simply rebuild).
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
        // M9-2 T3 (D-M92-5): the spectral consumption keys —
        // log_sensitivity (row-major [λ][c] as decoded) and
        // channel_density (nil-vs-value tagged, the base_density form).
        if let logSensitivity = profile.logSensitivity {
            combined = chain(combined, 1)
            for row in logSensitivity {
                for value in row {
                    combined = chain(combined, UInt64(value.bitPattern))
                }
            }
        } else {
            combined = chain(combined, 0)
        }
        if let channelDensity = profile.channelDensity {
            combined = chain(combined, 1)
            for row in channelDensity {
                for sample in row {
                    switch sample {
                    case .some(let value):
                        combined = chain(combined, 1)
                        combined = chain(combined, UInt64(value.bitPattern))
                    case .none:
                        combined = chain(combined, 0)
                    }
                }
            }
        } else {
            combined = chain(combined, 0)
        }
        if let viewing = profile.info.viewingIlluminant {
            combined = chain(combined, 1)
            for byte in viewing.utf8 {
                combined = withUnsafeBytes(of: byte) {
                    StableHash.combine(combined, $0)
                }
            }
        } else {
            combined = chain(combined, 0)
        }
        // The PRE-FOLD (registered separately): midscale_neutral_density
        // — zero engine consumption today, folded so a future widening
        // cannot share stale slots.
        if let midscale = profile.midscaleNeutralDensity {
            combined = chain(combined, 1)
            for sample in midscale {
                switch sample {
                case .some(let value):
                    combined = chain(combined, 1)
                    combined = chain(combined, UInt64(value.bitPattern))
                case .none:
                    combined = chain(combined, 0)
                }
            }
        } else {
            combined = chain(combined, 0)
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
