import CoreImage
import XCTest
import LightamerCore
import LightamerIOP


@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// McpEditingToolsetTests (Plan 14-2 T2/T3/T4) — the write-face + catalog +
// export tool suite:
//
//   T2 apply_params (module-level upsert, planner ruling D5 stateless):
//     • the FOUR upsert legs against the DISK truth (golden round-trip at
//       the byte level): replace params / create instance / enable flip /
//       remove instance;
//     • IDEMPOTENCE: the same apply twice leaves the sidecar BYTES unchanged
//       (the projection no-op, §RQ-14-5② — agent retry safety);
//     • GUI-live HARD rejection (imageLiveInEditor, bilingual guidance) with
//       the disk untouched — the single-image semantics that D8 pins against
//       14-3's batch soft-skip;
//     • the typed error table, one case per code (unknownOp / invalidParams
//       / notSessionMember / serverReadOnly);
//   T2 load_image: the stateless read view (no server-side handle) + the
//     honest "saved edit state" note.
//   T3 list_iops + IopCatalog reflection guard (see the catalog section).
//   T4 export_image (see the export section).
//
// Fixtures: synthetic sessions under NSTemporaryDirectory (L009). The apply
// path is pixel-free by construction (the lazy red line) — no GPU needed for
// the write legs.
// ─────────────────────────────────────────────────────────────────────────────

final class McpEditingToolsetTests: XCTestCase {

    private var tempDirectory: URL!


    override func setUpWithError() throws {
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-editing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Fixtures

    /// Registers the IOP modules (exposure etc. — the upsert decode path).
    private func populatedModules() async -> ModuleRegistry {
        let registry = ModuleRegistry()
        await LightamerIOPRegistry.populate(registry)
        return registry
    }

    /// Synthetic session: root/Capture/<name> + an open+synced lindex row.
    private func makeSession(
        imageName: String = "DSC00012.ARW"
    ) async throws -> (root: URL, imageURL: URL, store: SessionIndexStore) {
        let root = tempDirectory.appendingPathComponent(
            "session-\(UUID().uuidString)", isDirectory: true)
        let capture = root.appendingPathComponent("Capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        let imageURL = capture.appendingPathComponent(imageName)
        try Data(repeating: 0xCD, count: 64).write(to: imageURL)

        let store = SessionIndexStore(sessionRoot: root)
        let entry = SessionScanEntry(
            relPath: "Capture/\(imageName)",
            mtime: (try? imageURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate)?.timeIntervalSince1970 ?? 0,
            size: 64)
        _ = try await store.openSession(
            root: root,
            scan: AsyncStream { continuation in
                continuation.yield(SessionScanPage(entries: [entry]))
                continuation.finish()
            })
        return (root, imageURL, store)
    }

    private func makeSeams(
        session: (store: SessionIndexStore, root: URL),
        metal metalContext: MetalContext? = nil,
        liveImageURL: @escaping @Sendable () async -> URL? = { nil }
    ) async -> EditingToolset.Seams {
        let populated = await populatedModules()
        var seams = EditingToolset.Seams(
            session: { session },
            metal: { metalContext },
            modules: { populated },
            gate: McpRenderGate(),
            liveImageURL: liveImageURL)
        seams.writeGate = McpRenderGate()
        return seams
    }

    private func makeRegistry(
        seams: EditingToolset.Seams, writerCheck: (@Sendable () async -> Bool)? = nil
    ) async -> McpToolRegistry {
        let registry = McpToolRegistry()
        await EditingToolset.register(into: registry, seams: seams)
        await registry.setWriterCheck(writerCheck)
        return registry
    }

    /// Calls apply_params with a one-op shape.
    private static func applyOp(
        _ registry: McpToolRegistry, relPath: String, opName: String,
        multiPriority: Int? = nil, params: [String: McpJSON]? = nil,
        enabled: Bool? = nil, remove: Bool = false
    ) async throws -> String {
        var op: [String: McpJSON] = ["opName": .string(opName)]
        if let multiPriority { op["multiPriority"] = .int(multiPriority) }
        if let params { op["params"] = .object(params) }
        if let enabled { op["enabled"] = .bool(enabled) }
        if remove { op["remove"] = .bool(true) }
        let output = try await registry.call(
            name: "apply_params",
            arguments: [
                "relPath": .string(relPath),
                "ops": .array([.object(op)]),
            ])
        guard case .text(let text) = output.content.first else {
            throw McpToolError.internalError("test harness: expected text content")
        }
        return text
    }

    private static func sidecarDoc(
        _ imageURL: URL
    ) throws -> LightamerSidecar {
        let sidecarURL = imageURL.appendingPathExtension("lra")
        let data = try Data(contentsOf: sidecarURL)
        return try JSONDecoder().decode(LightamerSidecar.self, from: data)
    }

    // MARK: - T2: the four upsert legs (golden round-trip, byte-level)

    /// Leg 1 — REPLACE: a partial params overlay lands on the existing
    /// instance and the disk sidecar carries it (the golden round-trip).
    func testApplyParamsReplacesParamsOnDisk() async throws {
        let (root, imageURL, store) = try await makeSession()
        let registry = await makeRegistry(
            seams: await makeSeams(session: (store, root)))

        _ = try await Self.applyOp(
            registry, relPath: "Capture/DSC00012.ARW", opName: "exposure",
            params: ["exposure": .double(0.3)])

        // The disk truth: the exposure instance carries 0.3 stops.
        let document = try Self.sidecarDoc(imageURL)
        let record = try XCTUnwrap(
            document.instances.first { $0.opName == "exposure" },
            "the exposure instance must exist in the sidecar")
        let params = try record.params(of: ExposureModule.self)
        XCTAssertEqual(params.exposure, 0.3, accuracy: 1e-9)

        // One undoable commit on top (the overwrite epoch).
        XCTAssertEqual(document.history.items.count, 1)
        XCTAssertEqual(document.history.position, 0)
    }

    /// IDEMPOTENCE: the same apply again writes NOTHING — the sidecar bytes
    /// stay identical (the projection no-op).
    func testApplyParamsIsByteIdempotent() async throws {
        let (root, imageURL, store) = try await makeSession()
        let registry = await makeRegistry(
            seams: await makeSeams(session: (store, root)))

        _ = try await Self.applyOp(
            registry, relPath: "Capture/DSC00012.ARW", opName: "exposure",
            params: ["exposure": .double(0.3)])
        let first = try Data(contentsOf: imageURL.appendingPathExtension("lra"))
        let answer = try await Self.applyOp(
            registry, relPath: "Capture/DSC00012.ARW", opName: "exposure",
            params: ["exposure": .double(0.3)])
        let second = try Data(contentsOf: imageURL.appendingPathExtension("lra"))

        XCTAssertEqual(first, second, "a byte-identical retry must not rewrite")
        XCTAssertTrue(answer.contains("applied=nothing"))
    }

    /// Leg 2 — CREATE: an ABSENT key (exposure at multiPriority 1 — a
    /// second instance) appends a NEW instance with the module defaults
    /// overlaid by the request params.
    func testApplyParamsCreatesMissingInstance() async throws {
        let (root, imageURL, store) = try await makeSession()
        let registry = await makeRegistry(
            seams: await makeSeams(session: (store, root)))

        _ = try await Self.applyOp(
            registry, relPath: "Capture/DSC00012.ARW", opName: "colisa",
            multiPriority: 1, params: ["contrast": .double(0.25)])

        let document = try Self.sidecarDoc(imageURL)
        let record = try XCTUnwrap(
            document.instances.first {
                $0.opName == "colisa" && $0.multiPriority == 1
            },
            "the absent (colisa, 1) key must be created")
        let params = try record.params(of: ColisaModule.self)
        XCTAssertEqual(params.contrast, 0.25, accuracy: 1e-9)
        // The untouched seed keys survive (the FULL desired set rides).
        XCTAssertNotNil(document.instances.first { $0.opName == "exposure" })
    }

    /// Leg 3 — ENABLE FLIP: the instance stays, its enabled flag flips.
    func testApplyParamsFlipsEnabled() async throws {
        let (root, imageURL, store) = try await makeSession()
        let registry = await makeRegistry(
            seams: await makeSeams(session: (store, root)))

        _ = try await Self.applyOp(
            registry, relPath: "Capture/DSC00012.ARW", opName: "exposure",
            params: ["exposure": .double(0.5)])
        _ = try await Self.applyOp(
            registry, relPath: "Capture/DSC00012.ARW", opName: "exposure",
            enabled: false)

        let document = try Self.sidecarDoc(imageURL)
        let record = try XCTUnwrap(
            document.instances.first { $0.opName == "exposure" })
        XCTAssertFalse(record.enabled, "the flip must land on disk")
        let params = try record.params(of: ExposureModule.self)
        XCTAssertEqual(params.exposure, 0.5, accuracy: 1e-9, "params ride unchanged")
    }

    /// Leg 4 — REMOVE: `"remove": true` drops the instance from the disk
    /// document.
    func testApplyParamsRemovesInstance() async throws {
        let (root, imageURL, store) = try await makeSession()
        let registry = await makeRegistry(
            seams: await makeSeams(session: (store, root)))

        _ = try await Self.applyOp(
            registry, relPath: "Capture/DSC00012.ARW", opName: "exposure",
            params: ["exposure": .double(0.5)])
        XCTAssertNotNil(try Self.sidecarDoc(imageURL).instances.first { $0.opName == "exposure" })

        _ = try await Self.applyOp(
            registry, relPath: "Capture/DSC00012.ARW", opName: "exposure", remove: true)

        let document = try Self.sidecarDoc(imageURL)
        XCTAssertNil(
            document.instances.first { $0.opName == "exposure" },
            "the removed instance must leave the disk document")
    }

    // MARK: - T2: GUI-live HARD rejection (D8 single-image semantics)

    func testApplyParamsGUIliveIsHardRejectedAndDiskUntouched() async throws {
        let (root, imageURL, store) = try await makeSession()
        let seams = await makeSeams(
            session: (store, root),
            liveImageURL: { imageURL })
        let registry = await makeRegistry(seams: seams)

        do {
            _ = try await Self.applyOp(
                registry, relPath: "Capture/DSC00012.ARW", opName: "exposure",
                params: ["exposure": .double(0.3)])
            XCTFail("a GUI-live image must be hard-rejected")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "imageLiveInEditor")
            // The bilingual disposal guidance rides the message (L025 face).
            XCTAssertTrue(error.message.contains("图像在 Lightamer 编辑器中打开"))
            XCTAssertTrue(error.message.contains("Lightamer editor"))
        }
        // The disk truth is untouched (the rejection precedes any write).
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: imageURL.appendingPathExtension("lra").path),
            "the hard rejection must leave no sidecar write")

        // After the editor releases the image, the SAME call succeeds.
        let released = await makeSeams(session: (store, root))
        let registry2 = await makeRegistry(seams: released)
        _ = try await Self.applyOp(
            registry2, relPath: "Capture/DSC00012.ARW", opName: "exposure",
            params: ["exposure": .double(0.3)])
        XCTAssertNotNil(try? Self.sidecarDoc(imageURL))
    }

    // MARK: - T2: the typed error table (one case per code)

    func testApplyParamsUnknownOpIsTyped() async throws {
        let (root, _, store) = try await makeSession()
        let registry = await makeRegistry(
            seams: await makeSeams(session: (store, root)))
        do {
            _ = try await Self.applyOp(
                registry, relPath: "Capture/DSC00012.ARW", opName: "definitely_not_an_iop",
                params: [:])
            XCTFail("an unregistered op must be unknownOp")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "unknownOp")
        }
    }

    func testApplyParamsMistypedValueIsInvalidParamsWithOpNamed() async throws {
        let (root, _, store) = try await makeSession()
        let registry = await makeRegistry(
            seams: await makeSeams(session: (store, root)))
        do {
            _ = try await Self.applyOp(
                registry, relPath: "Capture/DSC00012.ARW", opName: "exposure",
                params: ["exposure": .string("bright")])
            XCTFail("a mistyped param value must be invalidParams")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
            XCTAssertTrue(error.message.contains("exposure"), "the op must be named")
        }
    }

    func testApplyParamsForeignRelPathIsNotSessionMember() async throws {
        let (root, _, store) = try await makeSession()
        let registry = await makeRegistry(
            seams: await makeSeams(session: (store, root)))
        do {
            _ = try await Self.applyOp(
                registry, relPath: "Capture/foreign.ARW", opName: "exposure",
                params: ["exposure": .double(0.1)])
            XCTFail("a foreign relPath must be notSessionMember")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "notSessionMember")
        }
    }

    func testApplyParamsOnReadOnlyHostIsServerReadOnly() async throws {
        let (root, _, store) = try await makeSession()
        let registry = await makeRegistry(
            seams: await makeSeams(session: (store, root)),
            writerCheck: { false })
        do {
            _ = try await Self.applyOp(
                registry, relPath: "Capture/DSC00012.ARW", opName: "exposure",
                params: ["exposure": .double(0.1)])
            XCTFail("a read-only host must refuse writes")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "serverReadOnly")
        }
    }

    /// The apply body races `McpTimeouts.apply` (D-14-2-T6-1): a compose leg
    /// stalled past the budget surfaces the typed internalError face within
    /// a bounded time. The loser-finishes posture applies (the cancelled leg
    /// may still complete into the disk) — the idempotent retry is the
    /// recovery contract, §RQ-14-5②.
    func testApplyParamsTimeoutIsTypedInternalError() async throws {
        let (root, _, store) = try await makeSession()
        let populated = await populatedModules()
        var seams = EditingToolset.Seams(
            session: { (store, root) },
            metal: { nil },
            modules: {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return populated
            },
            gate: McpRenderGate(),
            liveImageURL: { nil })
        seams.writeGate = McpRenderGate()
        seams.applyTimeoutOverride = 0.15
        let registry = await makeRegistry(seams: seams)

        let start = DispatchTime.now()
        do {
            _ = try await Self.applyOp(
                registry, relPath: "Capture/DSC00012.ARW", opName: "exposure",
                params: ["exposure": .double(0.3)])
            XCTFail("a stalled apply must surface internalError")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "internalError")
            XCTAssertTrue(error.message.contains("timed out"))
        }
        let elapsed = Double(
            DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
        XCTAssertLessThan(elapsed, 5.0, "the timeout must be bounded")
    }

    // MARK: - T2: load_image (the stateless read view)

    func testLoadImageViewReflectsTheSavedState() async throws {
        let (root, imageURL, store) = try await makeSession()
        let registry = await makeRegistry(
            seams: await makeSeams(session: (store, root)))

        // Pristine: an empty instance list and the honest note.
        let pristine = try await registry.call(
            name: "load_image", arguments: ["relPath": .string("Capture/DSC00012.ARW")])
        guard case .text(let pristineView) = pristine.content.first else {
            return XCTFail("expected text")
        }
        XCTAssertTrue(pristineView.contains("\"instances\""))
        XCTAssertFalse(pristineView.contains("opName"), "pristine = an empty instance list")
        XCTAssertTrue(pristineView.contains("render_preview reflects the SAVED edit state"))

        // After an apply, the view shows the saved instance.
        _ = try await Self.applyOp(
            registry, relPath: "Capture/DSC00012.ARW", opName: "exposure",
            params: ["exposure": .double(0.3)])
        let after = try await registry.call(
            name: "load_image", arguments: ["relPath": .string("Capture/DSC00012.ARW")])
        guard case .text(let view) = after.content.first else {
            return XCTFail("expected text")
        }
        XCTAssertTrue(view.contains("exposure"))
        // The saved instance shows up enabled (JSONSerialization booleans).
        let viewObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(view.utf8), options: [])
                as? [String: Any])
        let viewInstances = try XCTUnwrap(viewObject["instances"] as? [[String: Any]])
        let viewExposure = try XCTUnwrap(
            viewInstances.first { ($0["opName"] as? String) == "exposure" })
        XCTAssertEqual(viewExposure["enabled"] as? Bool, true)

        // Statelessness: TWO interleaved viewers see the same view — there
        // is no server-side handle to stomp (the D5 dissolution).
        let first = try await registry.call(
            name: "load_image", arguments: ["relPath": .string("Capture/DSC00012.ARW")])
        let second = try await registry.call(
            name: "load_image", arguments: ["relPath": .string("Capture/DSC00012.ARW")])
        XCTAssertEqual(
            first.content[0],
            second.content[0])
        _ = imageURL  // the fixture holds the file
    }

    func testLoadImageForeignRelPathIsNotSessionMember() async throws {
        let (root, _, store) = try await makeSession()
        let registry = await makeRegistry(
            seams: await makeSeams(session: (store, root)))
        do {
            _ = try await registry.call(
                name: "load_image", arguments: ["relPath": .string("../escape.ARW")])
            XCTFail("a foreign relPath must be notSessionMember")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "notSessionMember")
        }
    }


    // MARK: - T3: the IopCatalog reflection guard (keys + version pin)

    /// Per cataloged op: the handwritten key set must equal the module's
    /// canonical default-ENCODED key set (the wire truth — stronger than the
    /// CodingKeys declaration), and the version/iopOrder pins must hold. A
    /// params-shape migration flips the version pin red and forces a
    /// conscious catalog refresh (the agent cache-invalidation contract).
    func testIopCatalogKeySetsMatchEncodedDefaultsAndVersionPins() async throws {
        let populated = await populatedModules()
        let defaults = await populated.makeDefaultInstances()
            + LightamerIOPRegistry.editingDefaultInstances()
        var checked = 0
        for op in IopCatalog.ops {
            let registered = await populated.makeBox(opName: op.opName) != nil
            XCTAssertTrue(registered, "\(op.opName) must be a registered module")
            let record = try XCTUnwrap(
                defaults.first { $0.opName == op.opName && $0.multiPriority == 0 },
                "\(op.opName): no default seed record to guard against")
            let object = try? JSONSerialization.jsonObject(
                with: record.paramsData, options: []) as? [String: Any]
            let encodedKeys = Set((object ?? [:]).keys)
            let catalogKeys = Set(op.params.map(\.name))
            XCTAssertEqual(
                catalogKeys, encodedKeys,
                "\(op.opName): handwritten keys must equal the encoded default keys")
            XCTAssertEqual(op.version, record.version,
                           "\(op.opName): version pin drifted — refresh the catalog")
            XCTAssertEqual(op.iopOrder, record.iopOrder,
                           "\(op.opName): iopOrder drifted from the module record")
            checked += 1
        }
        XCTAssertEqual(checked, 18, "the catalog coverage is pinned at 18 ops")
    }

    func testListIopsReturnsTheCatalogShape() async throws {
        let (root, _, store) = try await makeSession()
        let registry = await makeRegistry(seams: await makeSeams(session: (store, root)))
        let output = try await registry.call(name: "list_iops", arguments: [:])
        guard case .text(let text) = output.content.first else {
            return XCTFail("expected text")
        }
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8), options: [])
                as? [String: Any])
        let ops = try XCTUnwrap(object["ops"] as? [[String: Any]])
        XCTAssertEqual(ops.count, 18)
        let exposure = try XCTUnwrap(
            ops.first { ($0["opName"] as? String) == "exposure" })
        XCTAssertEqual(exposure["version"] as? Int, 1)
        XCTAssertEqual(exposure["domain"] as? String, "both")
        let params = try XCTUnwrap(exposure["params"] as? [String: Any])
        XCTAssertTrue(params.keys.contains("exposure"), "the params key reference rides")
    }

    // MARK: - T4: export_image (Output pinned, naming, yiyin seam)

    /// A synthetic gradient decode (the export tests render the REAL chain
    /// over millisecond-cheap pixels).
    private static func syntheticDecoded(width: Int, height: Int) -> DecodedImage {
        let gradient = CIImage(color: CIColor(red: 0.55, green: 0.45, blue: 0.35))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        return DecodedImage(
            ciImage: gradient, rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil,
            decoderVersionUsed: .v8)
    }

    /// A fixture session whose image carries a WRITTEN sidecar (terminal
    /// trio + exposure + rating) so the export renders the saved state and
    /// the XMP mount has content. The decode leg is synthetic — the render
    /// chain is REAL (the pixel-free fixtures keep the export legs fast).
    private func makeExportFixture(
        metal metalContext: MetalContext? = nil
    ) async throws
        -> (root: URL, imageURL: URL, store: SessionIndexStore, seams: EditingToolset.Seams)
    {
        let (root, imageURL, store) = try await makeSession()
        let populated = await populatedModules()
        // The pipe dispatches the IOP kernels through the framework's
        // default.metallib — the app registers it at launch; tests mirror
        // that here (the exposure box would otherwise functionNotFound).
        if let metalContext = metalContext {
            try await metalContext.registerDefaultLibrary(
                in: ExposureKernel.metalBundle)
        }
        let trio = await populated.makeDefaultInstances()
        var exposureParams = ExposureModule.Params()
        exposureParams.exposure = 0.25
        let exposureRecord = ModuleInstance(
            module: ExposureModule.self, params: exposureParams)
        let document = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8", decodeParamsHash: 0,
            instances: trio + [exposureRecord],
            history: HistoryStack(), historyHash: 0, rating: 4)
        let data = try JSONEncoder().encode(document)
        try data.write(to: imageURL.appendingPathExtension("lra"))
        let decoded = Self.syntheticDecoded(width: 800, height: 600)
        var seams = await makeSeams(session: (store, root), metal: metalContext)
        seams.decodeLeg = { _ in decoded }
        return (root, imageURL, store, seams)
    }

    private static func exportCall(
        _ registry: McpToolRegistry, relPath: String,
        extra arguments: [String: McpJSON] = [:]
    ) async throws -> String {
        var arguments = arguments
        arguments["relPath"] = .string(relPath)
        let output = try await registry.call(
            name: "export_image", arguments: arguments)
        guard case .text(let text) = output.content.first else {
            throw McpToolError.internalError("test harness: expected text content")
        }
        return text
    }

    func testExportImageLandsInOutputWithXMPAndPathNote() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal GPU") }
        let (root, imageURL, store, seams) = try await makeExportFixture(
            metal: try MetalContext())
        let registry = await makeRegistry(seams: seams)

        let text = try await Self.exportCall(
            registry, relPath: "Capture/DSC00012.ARW",
            extra: ["format": .string("jpeg"), "quality": .int(90)])

        // The landing zone is the session's Output/ — SERVER-PINNED.
        let outputDirectory = root.appendingPathComponent("Output", isDirectory: true)
        let files = try XCTUnwrap(
            try? FileManager.default.contentsOfDirectory(atPath: outputDirectory.path))
        XCTAssertEqual(files.count, 1, "exactly one export artifact")
        let destination = outputDirectory.appendingPathComponent(files[0])
        let bytes = try Data(contentsOf: destination)
        XCTAssertEqual(bytes.prefix(2), Data([0xFF, 0xD8]), "JPEG magic")
        // The XMP mount rides encodeStage automatically (rating 4 = content).
        XCTAssertTrue(
            bytes.range(of: Data("ns.adobe.com/xap/1.0/".utf8)) != nil,
            "the exported product carries the sidecar's XMP")
        // The path + note return face.
        XCTAssertTrue(text.contains("exported=\(outputDirectory.path)"))
        XCTAssertTrue(text.contains("800x600"))
        XCTAssertTrue(text.contains("render_preview"))
        _ = imageURL
    }

    func testExportImageCollisionIncrements() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal GPU") }
        let (root, _, store, seams) = try await makeExportFixture(
            metal: try MetalContext())
        let registry = await makeRegistry(seams: seams)

        _ = try await Self.exportCall(registry, relPath: "Capture/DSC00012.ARW")
        _ = try await Self.exportCall(registry, relPath: "Capture/DSC00012.ARW")
        let outputDirectory = root.appendingPathComponent("Output", isDirectory: true)
        var files = try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path)
        files.sort()
        XCTAssertEqual(files.count, 2, "the collision must NOT overwrite")
        XCTAssertTrue(files.contains { $0.hasSuffix("-1.jpg") },
                      "the second export increments -1 (ExportNamer), got \(files)")
    }

    func testExportImageYiyinToggleGatesTheProductionSeam() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal GPU") }
        var (root, _, store, seams) = try await makeExportFixture(
            metal: try MetalContext())
        // The injection counter: the seam fires ONLY on yiyin=true.
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var value = 0
            func bump() { lock.lock(); value += 1; lock.unlock() }
        }
        let counter = Counter()
        seams.yiyinInjector = {
            ExportYiyinInjector { _, _, _, _ in counter.bump() }
        }
        let registry = await makeRegistry(seams: seams)

        // Default FALSE: the plain render, injector untouched.
        _ = try await Self.exportCall(registry, relPath: "Capture/DSC00012.ARW")
        XCTAssertEqual(counter.value, 0, "yiyin=false must not run the injector")

        // TRUE: the production seam runs (the ONE semantic it transmits).
        _ = try await Self.exportCall(
            registry, relPath: "Capture/DSC00012.ARW", extra: ["yiyin": .bool(true)])
        XCTAssertEqual(counter.value, 1, "yiyin=true runs the injector exactly once")
    }

    func testExportImageYiyinWithoutSeamIsTypedExportFailed() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal GPU") }
        // NO yiyinInjector — the headless shape.
        let (root, _, store, seams) = try await makeExportFixture(
            metal: try MetalContext())
        let registry = await makeRegistry(seams: seams)
        do {
            _ = try await Self.exportCall(
                registry, relPath: "Capture/DSC00012.ARW", extra: ["yiyin": .bool(true)])
            XCTFail("yiyin=true without the production seam must be exportFailed")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "exportFailed")
        }
    }

    func testExportImagePinnedOutputIsSelfProvenAndBadArgsAreTyped() async throws {
        let (root, _, store, seams) = try await makeExportFixture()
        let registry = await makeRegistry(seams: seams)
        let descriptors = await registry.descriptors()
        let export = try XCTUnwrap(descriptors.first { $0.name == "export_image" })
        // The schema self-proof: NO path/destination property exists.
        let schema = try JSONSerialization.jsonObject(
            with: Data(export.inputSchemaJSON.utf8), options: []) as? [String: Any]
        let properties = try XCTUnwrap(schema?["properties"] as? [String: Any])
        XCTAssertNil(properties["path"])
        XCTAssertNil(properties["destination"])
        XCTAssertNil(properties["directory"])

        // A smuggled "destination" argument changes nothing (Output stays
        // the server decision); a bad format is typed.
        do {
            _ = try await Self.exportCall(
                registry, relPath: "Capture/DSC00012.ARW",
                extra: [
                    "format": .string("bmp"),
                    "destination": .string("/tmp/evil"),
                ])
            XCTFail("bmp must be invalidParams")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
        }
        do {
            _ = try await Self.exportCall(
                registry, relPath: "Capture/DSC00012.ARW",
                extra: ["colorSpace": .string("wizard")])
            XCTFail("an unknown colorSpace must be invalidParams")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
        }
    }
}
