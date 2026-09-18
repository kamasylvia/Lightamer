import Foundation

/// The history identity hashes (Plan 02-05-04; HIST-04/D-H4) — FNV-1a 64
/// ONLY, via `StableHash` (02-01). Swift `Hasher` is per-process seeded
/// and BANNED here (02-RESEARCH Risk #2): the combined hash is written
/// into sidecars as the drift anchor and recomputed on reload by a
/// DIFFERENT process — it must be byte-deterministic across launches and
/// machines (Darktable `history.c:1571-1665` role; MD5→FNV-1a64).
///
/// Composition (research §4.2):
/// - seed = `decodeParamsHash` (the §1.3 decode-side atom — a Phase 3
///   WB/re-decode change must shift the whole identity, not just the
///   input plane);
/// - fold EVERY ENABLED instance in the GIVEN order (callers pass
///   `effectiveInstances()` output: v50-sorted, deduped by
///   `(opName, multiPriority)` — the `GROUP BY … MAX(num)` translation);
/// - per instance the field order is FIXED:
///   `opName` UTF-8 ‖ `multiPriority` LE ‖ `version` LE ‖ `paramsData`.
///   Disabled instances fold NOTHING (Darktable's `if (enabled)` guard)
///   — toggling enabled flips the hash even with identical params.
///
/// Consumers: (a) the per-module `paramsHash` atoms already key the pipe
/// cache (`PipeCacheKey.upstreamHash`); (b) `hash(stack:decodeParamsHash:)`
/// is the value Plan 02-06 stores as the sidecar `historyHash` — on
/// reload it is recomputed and compared; mismatch = DRIFT → log + toast,
/// never an auto-rewrite (user data safety).
///
/// All folds go through the public `StableHash` surface only (`combine`
/// over raw bytes; `Data`/UTF-8/`littleEndian` encodings applied here) —
/// no hash state is duplicated outside `StableHash`.
public enum HistoryHash {

    /// FNV-1a 64 over the enabled instances' identity+params chain,
    /// seeded with `decodeParamsHash`. Order-sensitive: the caller owns
    /// the ordering contract (pass `effectiveInstances()` output — v50
    /// ascending with the `(iopOrder, multiPriority, opName)` tiebreak).
    public static func hash(
        instances: [ModuleInstance],
        decodeParamsHash: UInt64
    ) -> UInt64 {
        var combined = decodeParamsHash
        for instance in instances where instance.enabled {
            // opName — UTF-8 bytes (length-unambiguous vs binary fields:
            // UTF-8 never emits 0x00, so the byte stream stays parseable).
            combined = Data(instance.opName.utf8).withUnsafeBytes {
                StableHash.combine(combined, $0)
            }
            // multiPriority — little-endian (fixed-width, fixed order).
            var priority = Int64(instance.multiPriority).littleEndian
            combined = withUnsafeBytes(of: &priority) {
                StableHash.combine(combined, $0)
            }
            // version — little-endian.
            var version = Int64(instance.version).littleEndian
            combined = withUnsafeBytes(of: &version) {
                StableHash.combine(combined, $0)
            }
            // paramsData — the canonical bytes (ParamsCoding, sorted
            // keys; L013). Regions-folded so discontiguous Data backing
            // is handled by the same rule as StableHash.hash.
            for region in instance.paramsData.regions {
                combined = region.withUnsafeBytes {
                    StableHash.combine(combined, $0)
                }
            }
        }
        return combined
    }

    /// Convenience over a whole stack: `effectiveInstances()` at the
    /// CURRENT position, v50-ordered, then the chain above. THE sidecar
    /// drift anchor (02-06).
    public static func hash(
        stack: HistoryStack,
        decodeParamsHash: UInt64
    ) -> UInt64 {
        hash(
            instances: stack.effectiveInstances(),
            decodeParamsHash: decodeParamsHash
        )
    }

    // MARK: - The shared D-H4 decode atom (PixelPipe TODO(02-05) extraction)

    /// `decodeParamsHash` — the position-0 seed shared by the pipe-cache
    /// chain (`PixelPipe.run`) and the sidecar drift check (02-06 stores
    /// it; recomputing MUST produce the identical value).
    ///
    /// FIELD-EXPLICIT by design (LESSONS L013): Foundation's keyed JSON
    /// emission order is NOT contractually stable, so hashing
    /// `RAWTechnicalParams` encoder bytes would make cache keys and drift
    /// anchors unstable. Adding a `RAWTechnicalParams` field MUST extend
    /// this list.
    public static func decodeParamsHash(for image: DecodedImage) -> UInt64 {
        var seed = StableHash.hash(image.decoderVersionUsed.rawValue)
        seed = Self.chain(seed, image.rawTech.blackLevel.bitPattern)
        seed = Self.chain(seed, image.rawTech.whiteLevel.bitPattern)
        seed = Self.chain(seed, image.rawTech.baselineExposure.bitPattern)
        seed = Self.chain(seed, UInt64(image.rawTech.neutralChromaticity.x.bitPattern))
        seed = Self.chain(seed, UInt64(image.rawTech.neutralChromaticity.y.bitPattern))
        seed = Self.chain(seed, image.rawTech.noiseReductionAmount.bitPattern)
        if let value = image.rawTech.luminanceNoiseReduction {
            seed = Self.chain(seed, value.bitPattern)
        }
        if let value = image.rawTech.colorNoiseReduction {
            seed = Self.chain(seed, value.bitPattern)
        }
        return seed
    }

    /// One fold of a raw UInt64 (platform byte order — the SAME encoding
    /// `PixelPipe.chain` uses, so the extraction is bit-identical to the
    /// pre-extraction inline formula).
    private static func chain(_ seed: UInt64, _ value: UInt64) -> UInt64 {
        var v = value
        return withUnsafeBytes(of: &v) { StableHash.combine(seed, $0) }
    }
}
