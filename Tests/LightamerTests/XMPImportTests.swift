import LightamerCore
@testable import LightamerCore
import XCTest

/// Plan 12-3 T5 — the third-party `.xmp` READ face: lr:hierarchicalSubject
/// verbatim, the dc:subject-only honest degradation, the reject/rating and
/// label reverse mappings, file round-trips against the writer, and the
/// typed error vectors. READ-ONLY is structural: every face takes Data or
/// opens the file read-only.
final class XMPImportTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("xmp-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Harness

    /// A hand-written third-party packet (NOT produced by XMPWriter — the
    /// import face must accept the ECOSYSTEM's bytes, not just our own).
    private func foreignPacket(
        rating: String? = nil, label: String? = nil,
        hierarchical: [String] = [], leaves: [String] = []
    ) -> Data {
        var items = ""
        for h in hierarchical {
            items += "       <rdf:li>\(h)</rdf:li>\n"
        }
        let hierSection = hierarchical.isEmpty ? "" : """
           <lr:hierarchicalSubject>
            <rdf:Bag>
        \(items)   </rdf:Bag>
           </lr:hierarchicalSubject>\n
        """
        var leafItems = ""
        for l in leaves {
            leafItems += "       <rdf:li>\(l)</rdf:li>\n"
        }
        let dcSection = leaves.isEmpty ? "" : """
           <dc:subject>
            <rdf:Bag>
        \(leafItems)   </rdf:Bag>
           </dc:subject>\n
        """
        let ratingLine = rating.map { "   <xmp:Rating>\($0)</xmp:Rating>\n" } ?? ""
        let labelLine = label.map { "   <xmp:Label>\($0)</xmp:Label>\n" } ?? ""
        let xml = """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Third Party 1.0">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
                xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                xmlns:lr="http://ns.adobe.com/lightroom/1.0/"
                xmlns:dc="http://purl.org/dc/elements/1.1/">
        \(ratingLine)\(labelLine)\(hierSection)\(dcSection)  </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
        return Data(xml.utf8)
    }

    private func read(_ data: Data) throws -> XMPImport.Fields {
        try XMPImport.read(data: data)
    }

    // MARK: - lr:hierarchicalSubject (full paths verbatim)

    func testHierarchicalSubjectReadsVerbatim() throws {
        let fields = try read(foreignPacket(
            hierarchical: ["Nature|Flower|Rose", "Garden|Rose"]))
        XCTAssertEqual(
            fields.keywords, ["Nature|Flower|Rose", "Garden|Rose"],
            "lr paths store verbatim — no flattening, no ancestor invention")
        XCTAssertNil(fields.rating)
        XCTAssertNil(fields.flag)
        XCTAssertNil(fields.colorLabel)
    }

    // MARK: - dc:subject-only (the honest single-level degradation)

    func testDCSubjectOnlyDegradesToSingleLevelPaths() throws {
        let fields = try read(foreignPacket(leaves: ["Rose", "Flower"]))
        XCTAssertEqual(
            fields.keywords, ["Rose", "Flower"],
            "no ancestor information exists — the leaves ARE the paths")
    }

    /// lr present + dc present → lr wins (dc is derivable from lr).
    func testHierarchicalWinsOverDCSubject() throws {
        let fields = try read(foreignPacket(
            hierarchical: ["Nature|Flower"], leaves: ["Flower"]))
        XCTAssertEqual(fields.keywords, ["Nature|Flower"])
    }

    // MARK: - Rating / reject / label mappings

    func testRatingAndRejectMapping() throws {
        XCTAssertEqual(try read(foreignPacket(rating: "4")).rating, 4)
        XCTAssertNil(try read(foreignPacket(rating: "4")).flag)
        // The reject convention: -1 → flag reject, no star rating.
        let reject = try read(foreignPacket(rating: "-1"))
        XCTAssertEqual(reject.flag, 2)
        XCTAssertNil(reject.rating)
        // XMP 0 = unrated and out-of-convention values never invent a
        // rating: the import face
        // THROWS .noFields (nothing importable) instead of returning an
        // empty Fields — the user-visible "nothing found" contract (D-2).
        XCTAssertThrowsError(try read(foreignPacket(rating: "0"))) { error in
            XCTAssertEqual(error as? XMPImport.ImportError, .noFields)
        }
        XCTAssertThrowsError(try read(foreignPacket(rating: "9"))) { error in
            XCTAssertEqual(error as? XMPImport.ImportError, .noFields)
        }
    }

    func testLabelReverseMapping() throws {
        XCTAssertEqual(try read(foreignPacket(label: "Green")).colorLabel, 3)
        XCTAssertEqual(try read(foreignPacket(label: "blue")).colorLabel, 4)
        // Unknown color names never invent a color: the whole import is
        // nothing-mappable → the .noFields contract (same as rating 0/9).
        XCTAssertThrowsError(try read(foreignPacket(label: "Magenta"))) { error in
            XCTAssertEqual(error as? XMPImport.ImportError, .noFields)
        }
    }

    // MARK: - Round-trip against the writer (the coexistence contract)

    func testRoundTripAgainstWriter() throws {
        let fields = XMPFields(
            rating: 2, label: "Purple",
            hierarchicalSubject: ["Nature|Flower|Rose"],
            subject: ["Rose", "Flower"])
        let packet = try XCTUnwrap(XMPWriter.write(fields: fields))
        let imported = try read(packet)
        XCTAssertEqual(imported.rating, 2)
        XCTAssertEqual(imported.colorLabel, 5)
        XCTAssertEqual(imported.keywords, ["Nature|Flower|Rose"])
        XCTAssertNil(imported.flag)
        // And the reject direction: writer's -1 imports back as reject.
        let rejectPacket = try XCTUnwrap(XMPWriter.write(fields: XMPFields(rating: -1)))
        let reject = try read(rejectPacket)
        XCTAssertEqual(reject.flag, 2)
        XCTAssertNil(reject.rating)
    }

    // MARK: - Typed error vectors

    func testTypedErrors() throws {
        XCTAssertThrowsError(try read(Data("not xml at all".utf8))) { error in
            XCTAssertEqual(error as? XMPImport.ImportError, .unparsableXMP)
        }
        // Host fact (2026-09-26 probe): a property-less XMP packet makes
        // CGImageMetadataCreateFromXMPData return nil → the honest error is
        // unparsableXMP, not noFields (test aligned to host behavior).
        XCTAssertThrowsError(try read(foreignPacket())) { error in
            XCTAssertEqual(error as? XMPImport.ImportError, .unparsableXMP)
        }
        XCTAssertThrowsError(
            try XMPImport.read(fileURL: tempDirectory.appendingPathComponent("missing.xmp"))
        ) { error in
            guard case XMPImport.ImportError.unreadableFile(let name) = error else {
                return XCTFail("expected unreadableFile, got \(error)")
            }
            XCTAssertEqual(name, "missing.xmp")
        }
    }

    // MARK: - The file face (READ-ONLY)

    func testFileReadLeavesSourceUnchanged() throws {
        let url = tempDirectory.appendingPathComponent("third-party.xmp")
        let original = foreignPacket(rating: "4", hierarchical: ["A|B"])
        try original.write(to: url)
        let before = try Data(contentsOf: url)

        let fields = try XMPImport.read(fileURL: url)
        XCTAssertEqual(fields.rating, 4)
        XCTAssertEqual(fields.keywords, ["A|B"])

        // The source file is byte-identical after the import (the red
        // line's read-only face — the imported file is never written).
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(FileManager.default.fileExists(atPath: url.path), true)
    }
}
