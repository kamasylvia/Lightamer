import Foundation

/// Stable 64-bit FNV-1a — the ONLY hash allowed in cache keys, history
/// hashes, and sidecar drift detection. Swift `Hasher` is seeded per
/// process and must never cross a persistence boundary (02-RESEARCH §4.2,
/// Risks #2). Mirrors Darktable dt_hash's role (pixelpipe_cache.c:120).
///
/// Consumers (the "stable" contract is load-bearing for all three):
/// - `PipeCacheKey.upstreamHash` (Plan 02-02) — pixelpipe per-module
///   per-ROI cache keys, must match across launches
/// - `ModuleInstance.paramsHash` / `HistoryHash` (Plan 02-05) — history
///   identity tuple hashing
/// - sidecar `historyHash` drift detection (Plan 02-06) — recomputed on
///   reload and compared against the archived value, MUST be identical to
///   the value written by a previous process or every reload false-positives
///
/// Contract: identical bytes → identical hash across processes, app
/// launches, and machines (FNV-1a 64, public-domain spec — offset basis
/// `0xcbf29ce484222325`, prime `0x00000100000001b3`).
public enum StableHash {

    /// FNV-1a 64 offset basis (public-domain spec) — also the hash of the
    /// empty byte sequence.
    public static let fnvOffsetBasis: UInt64 = 0xcbf29ce484222325

    /// FNV-1a 64 prime (public-domain spec).
    private static let fnvPrime: UInt64 = 0x00000100000001b3

    /// Fold `bytes` into `seed` (FNV-1a 64). Start a fresh hash with
    /// `StableHash.fnvOffsetBasis`; combine sequences by feeding a previous
    /// result as the seed (Darktable `dt_hash`'s incremental role).
    public static func combine(
        _ seed: UInt64 = fnvOffsetBasis,
        _ bytes: UnsafeRawBufferPointer
    ) -> UInt64 {
        var hash = seed
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* fnvPrime
        }
        return hash
    }

    /// Hash a byte sequence (FNV-1a 64). Folds each contiguous region in
    /// order, so discontiguous `DataProtocol` conformance is handled
    /// correctly (regions are contiguous slices).
    public static func hash(_ data: some DataProtocol) -> UInt64 {
        var hash = fnvOffsetBasis
        for region in data.regions {
            hash = region.withUnsafeBytes { combine(hash, $0) }
        }
        return hash
    }

    /// Hash a string's UTF-8 bytes (FNV-1a 64).
    public static func hash(_ string: some StringProtocol) -> UInt64 {
        var hash = fnvOffsetBasis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* fnvPrime
        }
        return hash
    }
}
