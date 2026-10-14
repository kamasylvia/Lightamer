import Foundation
import LightamerCore
import LightamerIOP
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ExportGainMapPanelTests (Plan M6-3-01 T3, KD-6 — APP bundle) — the M2 page's
// gain map face, asserted on the MODEL state layer (the KD-6 机检缝 — the
// panel tests never drive SwiftUI):
//
//   1. the five-dimension availability gate (jpeg / readout / peak ≥ 203 /
//      SDR encoding / embedICC — the UI mirror of the Core validate gates);
//   2. the linkage reset: embedICC off (and format off-jpeg) clears the flag
//      — the C-3 enable-under-broken-gate entry closed;
//   3. the assembly carry: makeVariant lands the flag on RunAssembly.variant
//      (the S4 落点) + the run-face re-check auto-resets a broken flag (C-2);
//   4. the enqueue linkage: enqueueExportM2 assembles the flag through with
//      the forced DRT record (the OQ-7 mirror) — captured on the REAL queue
//      with injected legs (the ExportAssemblyTests shape);
//   5. the default-off zero diff: a fresh model assembles gainMapHDR=false.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class ExportGainMapPanelTests: XCTestCase {

    private var tempDirectory: URL!
    private var outputDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("m63-panel-\(UUID().uuidString)", isDirectory: true)
        outputDirectory = tempDirectory.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try? FileManager.default.removeItem(
            at: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("m63-panel-raw-\(UUID().uuidString)"))
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private func record(
        peak: Float = 1000, eotf: DrtEotf = .gamma22
    ) -> DrtRecord {
        var record = DrtRecord()
        record.peakLuminance = peak
        record.encodingEotf = eotf
        if isHdrEncoding(eotf) { record.encodingSpace = .rec2020 }
        return record
    }

    private func armedModel() -> ExportM2PanelModel {
        let model = ExportM2PanelModel()
        model.gainMapHDR = true
        return model
    }

    // MARK: - 1: the five-dimension gate (KD-6)

    func testGateBlocksNonJPEGFormat() {
        let model = armedModel()
        model.formatKind = .png
        XCTAssertEqual(
            model.gainMapGate(effectiveRecord: record()),
            .blocked(.format))
        model.formatKind = .heic
        XCTAssertEqual(model.gainMapGate(effectiveRecord: record()), .blocked(.format))
    }

    func testGateBlocksPeakBelowTheReferenceWhite() {
        let model = ExportM2PanelModel()  // default record peak = 100
        XCTAssertEqual(
            model.gainMapGate(effectiveRecord: DrtRecord()),
            .blocked(.peak), "the DEFAULT record (peak 100) is the gray face")
        XCTAssertEqual(
            model.gainMapGate(effectiveRecord: record(peak: 202)),
            .blocked(.peak))
        // the boundary: exactly 203 = available (headroom 1.0).
        XCTAssertEqual(
            model.gainMapGate(effectiveRecord: record(peak: 203)),
            .available)
        // the toast copy reuses THIS dimension's unavailable key.
        XCTAssertEqual(
            ExportInspectorView.gainMapResetToastKey(for: .peak),
            "export_gainmap_unavailable_peak")
    }

    func testGateBlocksHDREncoding() {
        let model = armedModel()
        XCTAssertEqual(
            model.gainMapGate(effectiveRecord: record(eotf: .st2084)),
            .blocked(.encoding))
        XCTAssertEqual(
            model.gainMapGate(effectiveRecord: record(eotf: .hlg)),
            .blocked(.encoding))
        XCTAssertEqual(
            ExportInspectorView.gainMapResetToastKey(for: .encoding),
            "export_gainmap_unavailable_encoding")
    }

    func testGateBlocksEmbedICCOff() {
        let model = armedModel()
        model.embedICC = false
        XCTAssertEqual(
            model.gainMapGate(effectiveRecord: record()),
            .blocked(.embedICC), "C-3: the fifth dimension closes the broken-arm entry")
    }

    func testGateAvailableForJPEGSDREmbeddedICCAndNoRecordFace() {
        let model = armedModel()
        XCTAssertEqual(model.gainMapGate(effectiveRecord: record()), .available)
        // no image → .noRecord (the silent disabled face).
        XCTAssertEqual(model.gainMapGate(effectiveRecord: nil), .blocked(.noRecord))
    }

    // MARK: - 2: the linkage reset (KD-6/M2 + C-3)

    func testEmbedICCOffResetsTheFlag() {
        let model = armedModel()
        model.resetGainMapIfGateBroken(effectiveRecord: record())
        XCTAssertTrue(model.gainMapHDR, "the armed-and-legal face survives")
        model.embedICC = false
        model.resetGainMapIfGateBroken(effectiveRecord: record())
        XCTAssertFalse(model.gainMapHDR, "the embedICC break resets the flag")
        // the format dimension resets the same way.
        model.gainMapHDR = true
        model.formatKind = .tiff
        model.resetGainMapIfGateBroken(effectiveRecord: record())
        XCTAssertFalse(model.gainMapHDR)
    }

    // MARK: - 3: the assembly carry + the run-face re-check (C-2)

    func testRunAssemblyCarriesTheFlagAndAutoResetsBrokenGate() {
        let model = armedModel()
        let assembly = model.makeRunAssembly(
            targets: [URL(fileURLWithPath: "/tmp/a.jpg")],
            loadedImageURL: nil,
            instances: [],
            effectiveDrtRecord: record(),
            destination: outputDirectory)
        XCTAssertNotNil(assembly)
        XCTAssertTrue(assembly!.variant.gainMapHDR, "the flag rides the variant (S4)")
        XCTAssertNil(assembly!.gainMapAutoReset)
        XCTAssertNil(assembly!.variant.drtOutput, "the record lands at enqueue (OQ-7)")

        // the run-face re-check: the gate broke on the DRT panel (peak drop)
        // — the assembly auto-resets AND reports the dimension.
        model.gainMapHDR = true
        let broken = model.makeRunAssembly(
            targets: [URL(fileURLWithPath: "/tmp/a.jpg")],
            loadedImageURL: nil,
            instances: [],
            effectiveDrtRecord: DrtRecord(),  // peak 100 — broke off-page
            destination: outputDirectory)
        XCTAssertNotNil(broken)
        XCTAssertEqual(broken!.gainMapAutoReset, .peak)
        XCTAssertFalse(broken!.variant.gainMapHDR, "the reset face is what enqueues")
        XCTAssertFalse(model.gainMapHDR, "the model flag itself reset")
    }

    // MARK: - 4: the enqueue linkage (the ExportAssemblyTests capture shape)

    private final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var variants: [ExportVariant] = []
        func append(_ v: ExportVariant) {
            lock.lock()
            defer { lock.unlock() }
            variants.append(v)
        }
        var all: [ExportVariant] {
            lock.lock()
            defer { lock.unlock() }
            return variants
        }
    }

    func testEnqueueM2LinksTheFlagThroughWithTheDRTRecord() async throws {
        let capture = Capture()
        let state = ExportState()
        let renderLeg: ExportRenderLeg = { snapshot, _ in
            if let variant = snapshot.variants.first {
                capture.append(variant)
            }
            return ExportRenderArtifact(token: snapshot.seq, width: 4, height: 4)
        }
        let encodeLeg: ExportEncodeLeg = { _, _ in
            URL(fileURLWithPath: "/tmp/synthetic-gainmap.jpg")
        }
        state.installQueueForTesting(ExportQueue(
            metal: nil, registry: ModuleRegistry.makeDefault(),
            renderLeg: renderLeg, encodeLeg: encodeLeg))

        let model = armedModel()
        let assembly = model.makeRunAssembly(
            targets: [URL(fileURLWithPath: "/tmp/enqueue-src.jpg")],
            loadedImageURL: nil,
            instances: [],
            effectiveDrtRecord: record(),
            destination: outputDirectory)
        let unwrapped = try XCTUnwrap(assembly)
        try await state.enqueueExportM2(
            images: unwrapped.batch,
            instancesOverrides: unwrapped.overrides,
            drtRecord: unwrapped.drtRecord,
            variant: unwrapped.variant,
            destination: unwrapped.destination,
            subfolder: unwrapped.subfolder,
            namingPattern: unwrapped.pattern,
            collisionPolicy: unwrapped.collisionPolicy)
        // the enqueue poll waits for the capture; assert after settle.
        for _ in 0..<500 where capture.all.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let captured = try XCTUnwrap(capture.all.first)
        XCTAssertTrue(captured.gainMapHDR, "the flag rides the assembled variant")
        XCTAssertNotNil(
            captured.drtOutput, "the OQ-7 forced linkage landed the record")
        XCTAssertEqual(captured.drtOutput?.peakLuminance, 1000)
    }

    // MARK: - 5: the default-off zero diff

    func testDefaultModelAssemblesGainMapOff() {
        let model = ExportM2PanelModel()
        XCTAssertFalse(model.gainMapHDR)
        let variant = model.makeVariant()
        XCTAssertFalse(variant.gainMapHDR, "the default assembly is the zero path")
    }
}
