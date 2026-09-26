import ImageIO
@testable import LightamerCore
import XCTest

/// Plan 12-3 T1 — the XMPWriter goldens: byte-golden packet structure
/// (x:xmpmeta/rdf:RDF/Bag shapes + field SET ORDER), round-trip value
/// assertions over every field, the all-empty → nil face, the projection
/// mapping (reject → -1, pick → no seat, leaves dedup), and the Bag-vs-Seq
/// counterexample that pins the F2 array discipline.
final class XMPWriterTests: XCTestCase {

    // MARK: - Helpers

    /// The packet's `x:xmptk="XMP Core N.N.N"` stamp is the HOST XMP
    /// library's version — a live host face (the same class of face the
    /// 11-02 reverse anchors guard). The golden normalizes it to a sentinel
    /// before the byte comparison; a separate assertion proves the
    /// attribute exists (an absent stamp is its own drift signal).
    private func normalizedPacket(_ data: Data) throws -> String {
        let raw = try XCTUnwrap(String(data: data, encoding: .utf8))
        let normalized = raw.replacingOccurrences(
            of: "x:xmptk=\"[^\"]*\"",
            with: "x:xmptk=\"STAMP\"",
            options: .regularExpression)
        return normalized
    }

    /// Round-trip parse + scalar read.
    private func parse(_ data: Data) throws -> CGImageMetadata {
        try XCTUnwrap(
            CGImageMetadataCreateFromXMPData(data as CFData),
            "the packet must reparse (the importer's only entry face)")
    }

    private func stringValue(
        _ metadata: CGImageMetadata, _ path: String
    ) -> String? {
        CGImageMetadataCopyStringValueWithPath(
            metadata, nil, path as CFString) as String?
    }

    /// Array read: on REPARSE the Bag's elements come back as nested
    /// `CGImageMetadataTag` objects (probe-pinned), each wrapping a string
    /// value — not a plain [String].
    private func arrayValue(
        _ metadata: CGImageMetadata, _ path: String
    ) throws -> [String] {
        let tag = try XCTUnwrap(
            CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString),
            "\(path) must parse back as a tag")
        let value = try XCTUnwrap(CGImageMetadataTagCopyValue(tag))
        let elements = try XCTUnwrap(value as? [Any], "\(path) value must be an array")
        return try elements.map { element in
            if let string = element as? String { return string }
            // The element is a nested CGImageMetadataTag (CFTypeRef) — a
            // plain String branch above handles the defensive alternative.
            let nested = element as! CGImageMetadataTag
            return try XCTUnwrap(
                CGImageMetadataTagCopyValue(nested) as? String,
                "\(path) nested tag must wrap a string")
        }
    }

    // MARK: - All-empty → nil (the probe-pinned "no fields, no packet")

    func testEmptyFieldsYieldNilPacket() {
        XCTAssertNil(XMPWriter.write(fields: XMPFields()))
        // A sidecar with ONLY a pick flag projects to nothing — pick has no
        // XMP seat, so a pick-only export writes no packet at all.
        let pickOnly = XMPWriter.project(rating: nil, flag: 1, colorLabel: nil, keywords: nil)
        XCTAssertTrue(pickOnly.isEmpty)
        XCTAssertNil(XMPWriter.write(fields: pickOnly))
    }

    // MARK: - Byte golden (structure + field order; stamp-normalized)

    func testGoldenPacketStructureAndFieldOrder() throws {
        let fields = XMPWriter.project(
            rating: 3, flag: nil, colorLabel: 3,  // 3 = Green
            keywords: ["Nature|Flower|Rose", "Nature"])
        let data = try XCTUnwrap(XMPWriter.write(fields: fields))
        let packet = try normalizedPacket(data)

        // The stamp exists but is host-owned (excluded from the golden).
        let raw = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(raw.contains("x:xmptk=\"XMP Core "), "the host toolkit stamp must be present")

        // The golden packet — indentation and element order are ImageIO's
        // own (the live host pretty-prints Bags multi-line; the RESEARCH
        // §1.2 excerpt was a compressed transcription). Any host-side shape
        // change or field-order regression flips this red.
        let golden = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="STAMP">
           <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
              <rdf:Description rdf:about=""
                    xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                    xmlns:lr="http://ns.adobe.com/lightroom/1.0/"
                    xmlns:dc="http://purl.org/dc/elements/1.1/">
                 <xmp:Rating>3</xmp:Rating>
                 <xmp:Label>Green</xmp:Label>
                 <lr:hierarchicalSubject>
                    <rdf:Bag>
                       <rdf:li>Nature|Flower|Rose</rdf:li>
                       <rdf:li>Nature</rdf:li>
                    </rdf:Bag>
                 </lr:hierarchicalSubject>
                 <dc:subject>
                    <rdf:Bag>
                       <rdf:li>Rose</rdf:li>
                       <rdf:li>Nature</rdf:li>
                    </rdf:Bag>
                 </dc:subject>
              </rdf:Description>
           </rdf:RDF>
        </x:xmpmeta>\n
        """
        XCTAssertEqual(packet, golden,
            "packet bytes drifted — a host serialization change or a field-order regression")

        // The BAG shape is load-bearing: both arrays serialize rdf:Bag and
        // the wrong shape (rdf:Seq) appears NOWHERE in our packets.
        XCTAssertTrue(packet.contains("<rdf:Bag>"), "lr/dc arrays must be Bags")
        XCTAssertFalse(packet.contains("rdf:Seq"), "the Seq shape is the F2 violation")
    }

    // MARK: - Round-trip (every field, both directions)

    func testRoundTripAllFields() throws {
        let fields = XMPFields(
            rating: 4, label: "Blue",
            hierarchicalSubject: ["Nature|Flower|Rose", "Nature"],
            subject: ["Rose", "Flower", "Nature"])
        let data = try XCTUnwrap(XMPWriter.write(fields: fields))
        let metadata = try parse(data)

        XCTAssertEqual(stringValue(metadata, "xmp:Rating"), "4")
        XCTAssertEqual(stringValue(metadata, "xmp:Label"), "Blue")
        XCTAssertEqual(
            try arrayValue(metadata, "lr:hierarchicalSubject"),
            ["Nature|Flower|Rose", "Nature"])
        XCTAssertEqual(
            try arrayValue(metadata, "dc:subject"), ["Rose", "Flower", "Nature"])
    }

    /// The reject convention: Rating -1 serializes and round-trips verbatim.
    func testRejectRatingMinusOneRoundTrips() throws {
        let fields = XMPWriter.project(rating: 5, flag: 2, colorLabel: nil, keywords: nil)
        XCTAssertEqual(fields.rating, -1, "reject wins over any star rating")
        let data = try XCTUnwrap(XMPWriter.write(fields: fields))
        let metadata = try parse(data)
        XCTAssertEqual(stringValue(metadata, "xmp:Rating"), "-1")
    }

    // MARK: - Projection mapping (the sidecar five-field face)

    func testProjectMapsSidecarFace() {
        // Reject precedence over the star rating.
        XCTAssertEqual(
            XMPWriter.project(rating: 2, flag: 2, colorLabel: nil, keywords: nil).rating,
            -1)
        // Pick: no XMP seat — the rating rides, the flag maps to nothing.
        let pick = XMPWriter.project(rating: 4, flag: 1, colorLabel: nil, keywords: nil)
        XCTAssertEqual(pick.rating, 4)
        // Out-of-range color label → dropped (no invented names).
        XCTAssertNil(
            XMPWriter.project(rating: nil, flag: nil, colorLabel: 9, keywords: nil).label)
        // The full seven-color name table (the golden-locked spelling).
        XCTAssertEqual(
            XMPWriter.labelNames.sorted { $0.key < $1.key }.map(\.value),
            ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"])
    }

    func testProjectLeafExtractionDeduplicates() {
        let fields = XMPWriter.project(
            rating: nil, flag: nil, colorLabel: nil,
            keywords: ["Nature|Flower|Rose", "Garden|Rose", "Nature"])
        XCTAssertEqual(
            fields.subject, ["Rose", "Nature"],
            "dc:subject = the leaf (LAST path component) of each path, order-preserving dedup")
        XCTAssertEqual(
            fields.hierarchicalSubject, ["Nature|Flower|Rose", "Garden|Rose", "Nature"],
            "lr:hierarchicalSubject = the full paths verbatim")
    }

    /// The importer's reverse label lookup (case-insensitive; unknown → nil).
    func testLabelReverseLookup() {
        XCTAssertEqual(XMPWriter.colorLabel(forName: "Green"), 3)
        XCTAssertEqual(XMPWriter.colorLabel(forName: "purple"), 5)
        XCTAssertNil(XMPWriter.colorLabel(forName: "Magenta"), "non-C1 names never map")
        XCTAssertNil(XMPWriter.colorLabel(forName: ""))
    }

    // MARK: - The Bag-vs-Seq counterexample (F2 discipline #1, pinned wrong)

    /// The WRONG shape, kept as a tripwire: a raw CFArray through
    /// SetValueWithPath serializes rdf:Seq. If a future refactor "simplifies"
    /// the writer back to this form, this test's mirror assertions (golden
    /// Bag + no-Seq) fail and the discipline breach is caught.
    func testRawCFArraySerializesSeqNotBag() throws {
        let metadata = CGImageMetadataCreateMutable()
        let rawArray: [CFString] = ["Rose" as CFString, "Flower" as CFString]
        XCTAssertTrue(CGImageMetadataSetValueWithPath(
            metadata, nil, "dc:subject" as CFString, rawArray as CFArray))
        let data = try XCTUnwrap(CGImageMetadataCreateXMPData(metadata, nil) as Data?)
        let packet = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(packet.contains("rdf:Seq"), "the wrong shape still exists on this host (the tripwire's premise)")
        XCTAssertFalse(packet.contains("rdf:Bag"), "SetValueWithPath cannot produce a Bag — this is why TagCreate is mandatory")
    }
}
