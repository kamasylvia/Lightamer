import Foundation

/// The CANONICAL params coder (Plan 02-04; the D-H4 encode side).
///
/// **`.sortedKeys` is MANDATORY.** Foundation's keyed-container JSON
/// emission order is NOT deterministic — not just across processes, but
/// ACROSS CALLS WITHIN ONE PROCESS (host-proven 2026-09-19,
/// `.work/plans/02-04/probe-json.swift`: a 2-field struct encoded 5× produced
/// BOTH key orders; the unsorted hashes split 3/2). Every `paramsHash`
/// (the D-H4 atom: pipe-cache identity + 02-05 history identity + 02-06
/// sidecar drift detection) hashes THESE bytes, so unsorted encoding
/// would make cache keys flip per commit and false-positive every drift
/// check. (Same finding family as the `PixelPipe.run` decode-hash
/// field-explicit comment.)
///
/// Decoding is order-agnostic — plain `JSONDecoder` at the call sites.
public enum ParamsCoding {

    /// Encode `params` canonically (sorted keys, compact). Fresh encoder
    /// per call — `JSONEncoder` is not documented thread-safe and the
    /// cost is negligible at params-change frequency.
    public static func encode(_ params: some Encodable) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(params)) ?? Data()
    }
}
