import CoreGraphics
import Foundation
import ImageIO

// ─────────────────────────────────────────────────────────────────────────────
// XMPWriter (Plan 12-3 T1) — the sidecar metadata face → XMP packet, as a
// THIN ImageIO serialization wrapper (F1: `CGImageMetadataCreateXMPData` is
// alive on this host — the 12-RESEARCH §1 probe serialized an 831-byte
// packet with all four fields and round-tripped it clean; the "handwritten
// XML template" fallback branch is DEAD. What died in 11-02 D3 was the
// ImageIO WRITE side — properties dict → file bytes; the SERIALIZATION side
// never stopped working).
//
// TWO probe-pinned API disciplines (F2 — 12-RESEARCH §1.3; both are
// counterexample-tested in XMPWriterTests):
// 1. A BAG is only reachable through `CGImageMetadataTagCreate` with
//    `.arrayUnordered`. A raw CFArray handed to `SetValueWithPath`
//    serializes as rdf:Seq — the WRONG shape for dc:subject /
//    lr:hierarchicalSubject (the whole XMP ecosystem's convention).
// 2. The custom Lightroom namespace (`lr`) MUST be registered via
//    `CGImageMetadataRegisterNamespaceForPrefix` before SetTagWithPath —
//    unregistered, the set silently returns false.
//
// The non-existent-API list (12-RESEARCH §1.3, header-verified) — do NOT
// "fix" this file back to the old docs' names: `CGImageMetadataCreateTag`,
// `CGImageMetadataCreateArray`, `CGImageMetadataCopyValueWithPath` do not
// exist in CGImageMetadata.h.
//
// RED LINE (D-12-CONTEXT-2, zero exceptions): this writer feeds ONLY the
// EXPORT-product injection seam and it never touches a `.xmp` file beside
// an original — originals' `.xmp` attachments are never read, written, or
// deleted (Phase 9 boundary). The READ side (third-party import) lives in
// Session/XMPImport.swift.
// ─────────────────────────────────────────────────────────────────────────────

/// The XMP field projection (RESEARCH §1.4 verbatim field face).
public struct XMPFields: Sendable, Equatable {

    /// `xmp:Rating`. 0...5 stars, or **-1 = reject** (the dt/Lr convention —
    /// the caller-side projection maps `flag == 2` here; XMP has no flag
    /// position and pick has NO XMP seat at all — documented, D-12-CONTEXT-2).
    public var rating: Int?

    /// `xmp:Label` — the color-label NAME (the C1 seven-color set spelled
    /// out; see `labelNames` — execution decision, golden-locked).
    public var label: String?

    /// `lr:hierarchicalSubject` — FULL `|`-separated path strings, verbatim.
    public var hierarchicalSubject: [String]

    /// `dc:subject` — the LEAF of each path, order-preserving deduplicated.
    public var subject: [String]

    public init(
        rating: Int? = nil, label: String? = nil,
        hierarchicalSubject: [String] = [], subject: [String] = []
    ) {
        self.rating = rating
        self.label = label
        self.hierarchicalSubject = hierarchicalSubject
        self.subject = subject
    }

    /// All-nil → no packet at all (the probe-pinned host behavior: an empty
    /// metadata object serializes to nil; the injection seam skips).
    public var isEmpty: Bool {
        rating == nil && label == nil
            && hierarchicalSubject.isEmpty && subject.isEmpty
    }
}

public enum XMPWriter {

    /// The XMP namespace URIs (one place; the packet + the importer agree).
    public enum Namespaces {
        public static let lightroom = "http://ns.adobe.com/lightroom/1.0/"
        public static let lightroomPrefix = "lr"
    }

    /// colorLabel Int → `xmp:Label` name — the C1 SEVEN-COLOR set in the
    /// 12-1 execution-decision order (SessionBrowserView.colorLabelColor is
    /// the tint half: 0 red / 1 orange / 2 yellow / 3 green / 4 blue /
    /// 5 purple / 6 gray). The NAMES are this plan's execution decision
    /// (RESEARCH left the spelling open; the golden locks it).
    public static let labelNames: [Int: String] = [
        0: "Red", 1: "Orange", 2: "Yellow",
        3: "Green", 4: "Blue", 5: "Purple", 6: "Gray",
    ]

    public static func colorLabelName(_ value: Int) -> String? {
        labelNames[value]
    }

    /// Case-insensitive reverse lookup (the importer's label → colorLabel).
    public static func colorLabel(forName name: String) -> Int? {
        let lowered = name.lowercased()
        for (value, label) in labelNames where label.lowercased() == lowered {
            return value
        }
        return nil
    }

    /// The sidecar five-field face → `XMPFields` (the export mount's only
    /// sanctioned projection — D-12-CONTEXT-2):
    /// - `flag == 2` (reject) → **rating = -1** (XMP's reject convention;
    ///   reject WINS over any star rating — the XMP face has no flag seat).
    /// - `flag == 1` (pick) has NO XMP position — nothing mapped (documented;
    ///   pick stays a sidecar/DB-local dimension).
    /// - `rating` (0...5) → verbatim.
    /// - `colorLabel` → the label-name table (out-of-range → dropped).
    /// - `keywords` → hierarchicalSubject verbatim + dc:subject leaves
    ///   (each path's LAST `|` component), order-preserving deduplicated.
    public static func project(
        rating: Int?, flag: Int?, colorLabel: Int?, keywords: [String]?
    ) -> XMPFields {
        var fields = XMPFields()
        if flag == 2 {
            fields.rating = -1
        } else if let rating {
            fields.rating = rating
        }
        if let colorLabel {
            fields.label = labelNames[colorLabel]
        }
        if let keywords, !keywords.isEmpty {
            fields.hierarchicalSubject = keywords
            var leaves: [String] = []
            leaves.reserveCapacity(keywords.count)
            for path in keywords {
                let leaf = path.split(separator: "|", omittingEmptySubsequences: true)
                    .last.map(String.init) ?? path
                if !leaves.contains(leaf) { leaves.append(leaf) }
            }
            fields.subject = leaves
        }
        return fields
    }

    /// Serialize `fields` → an XMP packet (`<x:xmpmeta>` bytes).
    /// ALL-EMPTY fields → **nil** (legal: no fields, no packet — the probe's
    /// observed host behavior; the injection mount skips on nil).
    /// Field SET ORDER (golden-locked): Rating → Label → hierarchicalSubject
    /// → subject (the probe §1.2's rdf:Description child order).
    public static func write(fields: XMPFields) -> Data? {
        guard !fields.isEmpty else { return nil }

        let metadata = CGImageMetadataCreateMutable()
        // xmp:* scalars ride the standard xap namespace — the probe pinned
        // the "xmp" prefix resolving WITHOUT an explicit registration.
        if let rating = fields.rating {
            guard CGImageMetadataSetValueWithPath(
                metadata, nil, "xmp:Rating" as CFString, rating as CFNumber)
            else { return nil }
        }
        if let label = fields.label {
            guard CGImageMetadataSetValueWithPath(
                metadata, nil, "xmp:Label" as CFString, label as CFString)
            else { return nil }
        }

        if !fields.hierarchicalSubject.isEmpty {
            // Discipline #2: register the custom `lr` namespace FIRST —
            // unregistered, SetTagWithPath silently returns false.
            var registrationError: Unmanaged<CFError>?
            guard CGImageMetadataRegisterNamespaceForPrefix(
                metadata,
                Namespaces.lightroom as CFString,
                Namespaces.lightroomPrefix as CFString,
                &registrationError)
            else { return nil }
            guard setBag(
                metadata, path: "lr:hierarchicalSubject",
                xmlns: Namespaces.lightroom, prefix: Namespaces.lightroomPrefix,
                name: "hierarchicalSubject", values: fields.hierarchicalSubject)
            else { return nil }
        }

        if !fields.subject.isEmpty {
            guard setBag(
                metadata, path: "dc:subject",
                xmlns: kCGImageMetadataNamespaceDublinCore as String, prefix: nil,
                name: "subject", values: fields.subject)
            else { return nil }
        }

        return CGImageMetadataCreateXMPData(metadata, nil) as Data?
    }

    // MARK: - The Bag construction discipline (F2 #1)

    /// `CGImageMetadataTagCreate` + `.arrayUnordered` → rdf:Bag. A raw
    /// CFArray through `SetValueWithPath` would land rdf:Seq (the
    /// counterexample test pins the wrong shape so the discipline cannot
    /// silently regress).
    private static func setBag(
        _ metadata: CGMutableImageMetadata, path: String, xmlns: String,
        prefix: String?, name: String, values: [String]
    ) -> Bool {
        guard let tag = CGImageMetadataTagCreate(
            xmlns as CFString, prefix as CFString?, name as CFString,
            .arrayUnordered, values as CFArray)
        else { return false }
        return CGImageMetadataSetTagWithPath(metadata, nil, path as CFString, tag)
    }
}
