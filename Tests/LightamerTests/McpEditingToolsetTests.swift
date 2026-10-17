import CoreImage
import ImageIO
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
            // Seed-absent ops (the grade catalog rows that join the editing
            // seed with their panels — the filmPlacement precedent, now
            // colormatch) have no seed record; their encoded default IS the
            // GradeCatalog identityJSON (the same ParamsCoding bytes — the
            // row's single source).
            let encodedData: Data
            let versionPin: Int
            let orderPin: Float
            if let record = defaults.first(
                where: { $0.opName == op.opName && $0.multiPriority == 0 }) {
                encodedData = record.paramsData
                versionPin = record.version
                orderPin = record.iopOrder
            } else if let row = GradeCatalog.item(opName: op.opName) {
                encodedData = Data(row.identityJSON.utf8)
                versionPin = 1  // the fresh-module shape version
                orderPin = V50Order.order(for: op.opName) ?? -1
            } else {
                return XCTFail("\(op.opName): no seed record or catalog row to guard against")
            }
            let object = try? JSONSerialization.jsonObject(
                with: encodedData, options: []) as? [String: Any]
            let encodedKeys = Set((object ?? [:]).keys)
            let catalogKeys = Set(op.params.map(\.name))
            XCTAssertEqual(
                catalogKeys, encodedKeys,
                "\(op.opName): handwritten keys must equal the encoded default keys")
            XCTAssertEqual(op.version, versionPin,
                           "\(op.opName): version pin drifted — refresh the catalog")
            XCTAssertEqual(op.iopOrder, orderPin,
                           "\(op.opName): iopOrder drifted from the module record")
            checked += 1
        }
        XCTAssertEqual(checked, 19, "the catalog coverage is pinned at 19 ops (M5-1-01 colormatch joined)")
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
        XCTAssertEqual(ops.count, 19)
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

    // MARK: - M7-3 T5: the region/compare/list_luts goldens (ROADMAP §M7-3
    // acceptance ①)

    /// A render fixture: an indexed session with N members; the FIRST member
    /// carries a WRITTEN sidecar (exposure 0.25); the decode leg is the
    /// shared synthetic gradient; the render chain is REAL (a MetalContext).
    private func makeRenderFixture(memberNames: [String]) async throws
        -> (root: URL, store: SessionIndexStore, seams: EditingToolset.Seams)
    {
        let root = tempDirectory.appendingPathComponent(
            "render-\(UUID().uuidString)", isDirectory: true)
        let capture = root.appendingPathComponent("Capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        var entries: [SessionScanEntry] = []
        for name in memberNames {
            let url = capture.appendingPathComponent(name)
            try Data(repeating: 0xCD, count: 64).write(to: url)
            entries.append(SessionScanEntry(
                relPath: "Capture/\(name)",
                mtime: 0, size: 64))
        }
        let store = SessionIndexStore(sessionRoot: root)
        _ = try await store.openSession(
            root: root,
            scan: AsyncStream { continuation in
                continuation.yield(SessionScanPage(entries: entries))
                continuation.finish()
            })

        let metalContext = try MetalContext()
        try await metalContext.registerDefaultLibrary(in: ExposureKernel.metalBundle)
        let populated = await populatedModules()
        let trio = await populated.makeDefaultInstances()
        var exposureParams = ExposureModule.Params()
        exposureParams.exposure = 0.25
        let exposureRecord = ModuleInstance(
            module: ExposureModule.self, params: exposureParams)
        let document = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8", decodeParamsHash: 0,
            instances: trio + [exposureRecord],
            history: HistoryStack(), historyHash: 0)
        try JSONEncoder().encode(document).write(
            to: capture
                .appendingPathComponent(memberNames[0])
                .appendingPathExtension("lra"))
        let decoded = Self.syntheticDecoded(width: 800, height: 600)
        var seams = await makeSeams(session: (store, root), metal: metalContext)
        seams.decodeLeg = { _ in decoded }
        return (root, store, seams)
    }

    /// Calls render_preview and returns the CONTENT array (the dual-arm
    /// faces need the order).
    private static func renderPreview(
        _ registry: McpToolRegistry, relPath: String,
        extra arguments: [String: McpJSON] = [:]
    ) async throws -> [McpToolOutput.Content] {
        var arguments = arguments
        arguments["relPath"] = .string(relPath)
        let output = try await registry.call(
            name: "render_preview", arguments: arguments)
        return output.content
    }

    /// Decodes an inline JPEG content face to its CGImage (dimensions
    /// assertions) — and keeps the bytes for byte-equal judgments.
    private static func jpegFace(
        _ content: McpToolOutput.Content, file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (bytes: Data, image: CGImage) {
        guard case .imageBase64(let base64, let mime) = content, mime == "image/jpeg"
        else {
            XCTFail("expected an inline JPEG face", file: file, line: line)
            throw McpToolError.internalError("test harness: expected image")
        }
        let bytes = try XCTUnwrap(Data(base64Encoded: base64), file: file, line: line)
        let source = try XCTUnwrap(
            CGImageSourceCreateWithData(bytes as CFData, nil),
            file: file, line: line)
        let image = try XCTUnwrap(
            CGImageSourceCreateImageAtIndex(source, 0, nil),
            file: file, line: line)
        return (bytes, image)
    }

    /// The region golden (M2): the normalized rect × the rendered pixel
    /// size, ROUNDED — the crop's pixel frame ≡ the hand computation. The
    /// 800×600 decode renders 1:1 at longEdge 800.
    func testRenderPreviewRegionGoldenPixelFrame() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal GPU") }
        let (_, _, seams) = try await makeRenderFixture(
            memberNames: ["DSC00012.ARW"])
        let registry = await makeRegistry(seams: seams)

        let contents = try await Self.renderPreview(registry, relPath: "Capture/DSC00012.ARW", extra: [
            "longEdge": .int(800),
            "region": .object([
                "x": .double(0.25), "y": .double(0.5),
                "w": .double(0.5), "h": .double(0.25),
            ]),
            "compare": .string("none"),
        ])
        XCTAssertEqual(contents.count, 1)
        let face = try Self.jpegFace(contents[0])
        // Hand math: px = 0.25×800 = 200, py = 300, pw = 400, ph = 150.
        XCTAssertEqual(face.image.width, 400)
        XCTAssertEqual(face.image.height, 150)

        // The exact x+w==1.0 leg: the FULL-frame rect stays exact (no
        // round-drift past the bounds → no clamp shrink).
        let full = try await Self.renderPreview(registry, relPath: "Capture/DSC00012.ARW", extra: [
            "longEdge": .int(800),
            "region": .object([
                "x": .double(0.0), "y": .double(0.0),
                "w": .double(1.0), "h": .double(1.0),
            ]),
            "compare": .string("none"),
        ])
        let fullFace = try Self.jpegFace(full[0])
        XCTAssertEqual(fullFace.image.width, 800)
        XCTAssertEqual(fullFace.image.height, 600)
    }

    /// The region rejections (typed, no new codes): zero/negative extent →
    /// invalidParams; out-of-domain → roiOutOfBounds; a legal normalized
    /// rect that rounds to a zero-area frame → invalidParams CARRYING the
    /// normalized values (never the silent renderFailed bail-out).
    func testRenderPreviewRegionRejections() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal GPU") }
        let (_, _, seams) = try await makeRenderFixture(
            memberNames: ["DSC00012.ARW"])
        let registry = await makeRegistry(seams: seams)

        do {
            _ = try await Self.renderPreview(registry, relPath: "Capture/DSC00012.ARW", extra: [
                "region": .object([
                    "x": .double(0.1), "y": .double(0.1),
                    "w": .double(0.0), "h": .double(0.5),
                ]),
            ])
            XCTFail("w=0 must be invalidParams")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
        }
        do {
            _ = try await Self.renderPreview(registry, relPath: "Capture/DSC00012.ARW", extra: [
                "region": .object([
                    "x": .double(0.8), "y": .double(0.1),
                    "w": .double(0.5), "h": .double(0.5),
                ]),
            ])
            XCTFail("x+w>1 must be roiOutOfBounds")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "roiOutOfBounds")
        }
        do {
            _ = try await Self.renderPreview(registry, relPath: "Capture/DSC00012.ARW", extra: [
                "region": .object([
                    "x": .double(-0.1), "y": .double(0.1),
                    "w": .double(0.5), "h": .double(0.5),
                ]),
            ])
            XCTFail("a negative coordinate must be roiOutOfBounds")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "roiOutOfBounds")
        }
        // The sub-pixel leg (M2): 0.0005×800 = 0.4 → rounds to 0 → the
        // typed invalidParams carrying the NORMALIZED values.
        do {
            _ = try await Self.renderPreview(registry, relPath: "Capture/DSC00012.ARW", extra: [
                "region": .object([
                    "x": .double(0.0), "y": .double(0.0),
                    "w": .double(0.0005), "h": .double(0.0005),
                ]),
            ])
            XCTFail("a zero-area frame must be invalidParams")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
            XCTAssertTrue(error.message.contains("0.0005"),
                          "the normalized values ride the message: \(error.message)")
        }
    }

    /// The compare:root golden (D-M7-3-3): the DEFAULT call (no compare
    /// argument) is the DUAL arm — content [current, root, text] with the
    /// summary JSON; both planes share the dimensions; the pristine arm is
    /// byte-equal to the no-sidecar copy's render (the empty-chain-branch
    /// self-certification through the TOOL face).
    func testRenderPreviewCompareRootDualArm() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal GPU") }
        let (_, _, seams) = try await makeRenderFixture(
            memberNames: ["edited.ARW", "pristine.ARW"])
        let registry = await makeRegistry(seams: seams)

        // The bare call: DEFAULT root → the dual arm.
        let bare = try await Self.renderPreview(registry, relPath: "Capture/edited.ARW", extra: [
            "longEdge": .int(256),
        ])
        XCTAssertEqual(bare.count, 3, "[current, root, text]")
        let current = try Self.jpegFace(bare[0])
        let root = try Self.jpegFace(bare[1])
        XCTAssertEqual(current.image.width, root.image.width, "both arms share the frame")
        XCTAssertEqual(current.image.height, root.image.height)
        guard case .text(let summary) = bare[2] else {
            return XCTFail("expected the summary text face")
        }
        let summaryObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(summary.utf8)) as? [String: Any])
        XCTAssertEqual(summaryObject["compare"] as? String, "root")
        let currentFace = try XCTUnwrap(summaryObject["current"] as? [String: Any])
        XCTAssertEqual(currentFace["width"] as? Int, current.image.width)
        let rootFace = try XCTUnwrap(summaryObject["root"] as? [String: Any])
        XCTAssertEqual(rootFace["width"] as? Int, root.image.width)

        // The root arm ≡ the no-sidecar copy's single render (the SAME
        // empty-chain branch through the tool face — byte-equal JPEGs).
        let pristineCall = try await Self.renderPreview(
            registry, relPath: "Capture/pristine.ARW",
            extra: ["longEdge": .int(256), "compare": .string("none")])
        XCTAssertEqual(pristineCall.count, 1, "compare:none = the single-image face")
        let pristineFace = try Self.jpegFace(pristineCall[0])
        XCTAssertEqual(root.bytes, pristineFace.bytes,
                       "the root arm ≡ the no-sidecar render (byte-equal)")

        // The default-value identity: explicit compare:root ≡ the bare call.
        let explicit = try await Self.renderPreview(registry, relPath: "Capture/edited.ARW", extra: [
            "longEdge": .int(256), "compare": .string("root"),
        ])
        XCTAssertEqual(explicit.count, 3)
        let explicitRoot = try Self.jpegFace(explicit[1])
        XCTAssertEqual(explicitRoot.bytes, root.bytes, "explicit root ≡ default arm")
    }

    /// The region rect rides BOTH arms (Alcedo 同构): same rect → both
    /// frames the same hand-computed crop.
    func testRenderPreviewRegionAppliesToBothArms() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal GPU") }
        let (_, _, seams) = try await makeRenderFixture(
            memberNames: ["DSC00012.ARW"])
        let registry = await makeRegistry(seams: seams)
        let contents = try await Self.renderPreview(registry, relPath: "Capture/DSC00012.ARW", extra: [
            "longEdge": .int(800),
            "region": .object([
                "x": .double(0.5), "y": .double(0.0),
                "w": .double(0.5), "h": .double(0.5),
            ]),
        ])
        XCTAssertEqual(contents.count, 3)
        let current = try Self.jpegFace(contents[0])
        let root = try Self.jpegFace(contents[1])
        XCTAssertEqual(current.image.width, 400, "hand math: 0.5×800")
        XCTAssertEqual(current.image.height, 300)
        XCTAssertEqual(root.image.width, 400, "the SAME rect on the root arm")
        XCTAssertEqual(root.image.height, 300)
    }

    /// The list_luts golden (L4): the seeded temp library → the projection
    /// ≡ installedNames/entry direct (the single-source identity) PLUS the
    /// seeded content POSITIVE assertion (known key/name/is1D/size — the
    /// tool read the store, not a tautology) + the key-form (root-relative
    /// POSIX) + the libraryRoot echo.
    func testListLutsGoldenSeededProjection() async throws {
        let libraryRoot = tempDirectory.appendingPathComponent("LUTs", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        let cube = """
            TITLE "Golden Cube"
            LUT_3D_SIZE 2
            0.0 0.0 0.0
            1.0 0.0 0.0
            0.0 1.0 0.0
            1.0 1.0 0.0
            0.0 0.0 1.0
            1.0 1.0 1.0
            0.0 1.0 1.0
            1.0 0.0 1.0
            """
        try cube.write(
            to: libraryRoot.appendingPathComponent("golden.cube"), atomically: true,
            encoding: .utf8)
        let seeded = LutLibraryStore(directory: libraryRoot)
        let original = LutLibraryStore.shared
        LutLibraryStore.replaceShared(seeded)
        defer { LutLibraryStore.replaceShared(original) }

        let registry = McpToolRegistry()
        await EditingToolset.register(
            into: registry,
            seams: EditingToolset.Seams(
                session: { nil }, metal: { nil }, modules: { ModuleRegistry() },
                gate: McpRenderGate(), liveImageURL: { nil }))
        let output = try await registry.call(name: "list_luts", arguments: [:])
        guard case .text(let text) = output.content.first else {
            return XCTFail("expected a text payload")
        }
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(payload["libraryRoot"] as? String, libraryRoot.path)
        XCTAssertEqual(payload["total"] as? Int, 1)
        let luts = try XCTUnwrap(payload["luts"] as? [[String: Any]])
        XCTAssertEqual(luts.count, 1)
        let row = try XCTUnwrap(luts.first)
        // The POSITIVE content assertion (the seeded row's known facts).
        XCTAssertEqual(row["key"] as? String, "golden.cube", "root-relative POSIX key")
        XCTAssertEqual(row["name"] as? String, "golden.cube")
        XCTAssertEqual(row["is1D"] as? Bool, false)
        XCTAssertEqual(row["size"] as? Int, 2)
        // The identity leg: the projection ≡ the store's own faces.
        XCTAssertEqual(row["hash"] as? String, seeded.entry(named: "golden.cube")?.hash)
        let projectedKeys = Set(luts.map { $0["key"] as? String ?? "" })
        XCTAssertEqual(projectedKeys, Set(seeded.installedNames),
                       "the projection ≡ installedNames")
        XCTAssertFalse(
            row.keys.contains("subdirectory"), "root rows carry no subdirectory")
    }

    // MARK: - O4 (M7-4-01, MCP2-08): the copy/paste pair goldens

    /// The transfer fixture: a session with TWO members; the source
    /// carries a layer-structured sidecar (one Grade layer: an exposure +
    /// a temperature + the terminal-trio gamma + a masked
    /// contentRevision 7) + a DRT record. Returns the pieces the legs
    /// address.
    private func makeTransferFixture() async throws -> (
        root: URL, store: SessionIndexStore,
        sourceRel: String, sourceURL: URL,
        targetRel: String, targetURL: URL,
        sourceExposureID: UUID, layerID: UUID
    ) {
        // The two-member session (the makeSession shape, both entries in
        // the ONE scan — the open-time sync face).
        let root = tempDirectory.appendingPathComponent(
            "session-\(UUID().uuidString)", isDirectory: true)
        let capture = root.appendingPathComponent("Capture", isDirectory: true)
        try FileManager.default.createDirectory(
            at: capture, withIntermediateDirectories: true)
        let sourceURL = capture.appendingPathComponent("SRC_0001.ARW")
        try Data(repeating: 0xCD, count: 64).write(to: sourceURL)
        let targetURL = capture.appendingPathComponent("TGT_0001.ARW")
        try Data(repeating: 0xEF, count: 32).write(to: targetURL)
        let store = SessionIndexStore(sessionRoot: root)
        func entry(_ url: URL, relPath: String, size: Int64) -> SessionScanEntry {
            SessionScanEntry(
                relPath: relPath,
                mtime: (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate)?.timeIntervalSince1970 ?? 0,
                size: size)
        }
        _ = try await store.openSession(root: root, scan: AsyncStream { continuation in
            continuation.yield(SessionScanPage(entries: [
                entry(sourceURL, relPath: "Capture/SRC_0001.ARW", size: 64),
                entry(targetURL, relPath: "Capture/TGT_0001.ARW", size: 32),
            ]))
            continuation.finish()
        })
        let session = (root: root, imageURL: sourceURL, store: store)

        // The source sidecar: the M2-8 sourceChain shape (one Grade layer
        // with a transferable pair + a non-transferable terminal row).
        let layerID = UUID()
        var layer = AdjustmentLayer(id: layerID, name: "Warm")
        let exposure = ModuleInstance(
            module: ExposureModule.self,
            params: ExposureModule.Params(exposure: 0.5))
        layer.chain = [
            exposure,
            ModuleInstance(
                module: TemperatureModule.self,
                params: TemperatureModule.Params()),
            ModuleInstance(
                module: GammaModule.self, params: GammaModule.Params()),
        ]
        layer.mask = MaskSpec(
            drawn: DrawnMaskSpec(forms: [], group: nil), contentRevision: 7)
        let snapshot = LayerStackSnapshot(layers: [.init(layer)])
        var history = HistoryStack()
        let seed = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params())
        history.commit(
            seed, label: "structure", layerScope: EditorStructureScope.marker,
            stackSnapshot: snapshot)
        history.commitDrt(
            record: DrtRecord(), placeholder: seed, label: "drt")
        let document = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8", decodeParamsHash: 0,
            instances: [], history: history, historyHash: 0)
        let encoder = JSONEncoder()
        try encoder.encode(document).write(
            to: LightamerSidecar.sidecarURL(for: session.imageURL))
        return (
            session.root, session.store,
            "Capture/SRC_0001.ARW", session.imageURL,
            "Capture/TGT_0001.ARW", targetURL,
            exposure.id, layerID
        )
    }

    private static func jsonOutput(_ output: McpToolOutput) throws -> [String: Any] {
        guard case .text(let text) = output.content.first else {
            throw McpToolError.internalError("expected a text payload")
        }
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
            text)
    }

    /// The COPY face: the enumeration preview answers the source's Grade
    /// layer with its three items (the terminal trio greyed, VISIBLE) and
    /// the DRT presence — no state lands anywhere.
    func testCopyAdjustmentsEnumeratesTheSourceChain() async throws {
        let fixture = try await makeTransferFixture()
        let seams = await makeSeams(session: (fixture.store, fixture.root))
        let registry = await makeRegistry(seams: seams)
        let payload = try await Self.jsonOutput(try await registry.call(
            name: "copy_adjustments",
            arguments: ["source": .string(fixture.sourceRel)]))
        XCTAssertEqual(payload["source"] as? String, fixture.sourceRel)
        let grades = try XCTUnwrap(payload["grades"] as? [[String: Any]])
        XCTAssertEqual(grades.count, 1)
        let grade = try XCTUnwrap(grades.first)
        XCTAssertEqual(grade["name"] as? String, "Warm")
        XCTAssertEqual(grade["chainCount"] as? Int, 3)
        XCTAssertEqual(grade["transferableCount"] as? Int, 1,
                       "exposure only (temperature is RAW-decode-owned)")
        let items = try XCTUnwrap(grade["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 3)
        let byOp = Dictionary(uniqueKeysWithValues: items.map {
            ($0["opName"] as? String ?? "", $0)
        })
        XCTAssertEqual(byOp[ExposureModule.opName]?["transferable"] as? Bool, true)
        XCTAssertEqual(byOp[ExposureModule.opName]?["instanceId"] as? String,
                       fixture.sourceExposureID.uuidString)
        // The greyed face (VISIBLE, never swallowed): temperature rides
        // the RAW-decode ownership, gamma the terminal trio.
        XCTAssertEqual(byOp[TemperatureModule.opName]?["transferable"] as? Bool, false)
        XCTAssertEqual(byOp[GammaModule.opName]?["transferable"] as? Bool, false)
        let drt = try XCTUnwrap(payload["drt"] as? [String: Any])
        XCTAssertEqual(drt["present"] as? Bool, true)
        XCTAssertEqual(drt["eligible"] as? Bool, true)
        // The library-id form resolves through the same face (the O4
        // addressing dual form — the provider fixture rides an absolute
        // row; the kind0 anchor face is T5's leg).
        let packageURL = tempDirectory.appendingPathComponent("CopyLib.lalb")
        let fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "CopyLib")
        let libImage = tempDirectory.appendingPathComponent("lib-src.tif")
        try Data(repeating: 0xCD, count: 16).write(to: libImage)
        // A sidecar NEXT TO the library row (copy reads the sidecar).
        let libDocument = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8", decodeParamsHash: 0,
            instances: [], history: HistoryStack(), historyHash: 0)
        try JSONEncoder().encode(libDocument).write(
            to: LightamerSidecar.sidecarURL(for: libImage))
        let libID = try await LibraryStore(store: fileStore).insertImage(
            record: LibraryImageRecord(
                imagePath: libImage.path, pathKind: .absolute))
        MatchColorToolset.installLibraryProvider {
            (LibraryStore(store: fileStore),
             packageURL.deletingLastPathComponent())
        }
        let byID = try await Self.jsonOutput(try await registry.call(
            name: "copy_adjustments",
            arguments: ["source": .string(String(libID))]))
        XCTAssertEqual(byID["source"] as? String, String(libID))
        let libGrades = try XCTUnwrap(byID["grades"] as? [[String: Any]])
        XCTAssertEqual(libGrades.count, 0, "the empty source answers honestly")
        MatchColorToolset.installLibraryProvider { nil }
    }

    /// The PASTE face (happy path): per-target applied ledger, the epoch
    /// commit carries the label + the note/author stamp, the mask epoch
    /// resets, and the state reads back from DISK immediately after the
    /// call (the write-lands-before-return contract).
    func testPasteAdjustmentsLedgerAppliedWithStampAndEpoch() async throws {
        let fixture = try await makeTransferFixture()
        let seams = await makeSeams(session: (fixture.store, fixture.root))
        let registry = await makeRegistry(seams: seams)
        let payload = try await Self.jsonOutput(try await registry.call(
            name: "paste_adjustments",
            arguments: [
                "source": .string(fixture.sourceRel),
                "targets": .array([.string(fixture.targetRel)]),
                "note": .string("pasted by the agent"),
            ]))
        XCTAssertEqual(payload["appliedCount"] as? Int, 1)
        XCTAssertEqual(payload["author"] as? String, "mcp")
        XCTAssertEqual(payload["note"] as? String, "pasted by the agent")
        let rows = try XCTUnwrap(payload["targets"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["relPath"] as? String, fixture.targetRel)
        XCTAssertEqual(rows[0]["status"] as? String, "applied")
        XCTAssertNil(rows[0]["reason"])

        // The DISK truth, read immediately (no drain race): the epoch
        // item + the stamp + the mask reset.
        let target = try Self.sidecarDoc(fixture.targetURL)
        let top = try XCTUnwrap(target.history.items.last)
        XCTAssertEqual(top.label, "MCP paste_adjustments")
        XCTAssertEqual(top.layerScope, HistoryStack.pasteEpochScope)
        XCTAssertEqual(top.author, "mcp")
        XCTAssertEqual(top.note, "pasted by the agent")
        let pasted = try XCTUnwrap(top.pasteSet)
        XCTAssertTrue(pasted.contains { $0.opName == ExposureModule.opName })
        let layers = try XCTUnwrap(top.stackSnapshot?.layers)
        XCTAssertEqual(layers.count, 1)
        XCTAssertNil(layers[0].mask?.contentRevision,
                     "the mask epoch resets on paste (KD-3)")
    }

    /// The live target is a PER-TARGET rejected row (never a skip — the
    /// MCP face has no interactive layer to hand the image to).
    func testPasteAdjustmentsLiveTargetIsPerTargetRejected() async throws {
        let fixture = try await makeTransferFixture()
        let liveURL = fixture.targetURL
        let seams = await makeSeams(
            session: (fixture.store, fixture.root),
            liveImageURL: { liveURL })
        let registry = await makeRegistry(seams: seams)
        let payload = try await Self.jsonOutput(try await registry.call(
            name: "paste_adjustments",
            arguments: [
                "source": .string(fixture.sourceRel),
                "targets": .array([.string(fixture.targetRel)]),
            ]))
        XCTAssertEqual(payload["appliedCount"] as? Int, 0)
        let rows = try XCTUnwrap(payload["targets"] as? [[String: Any]])
        XCTAssertEqual(rows[0]["status"] as? String, "rejected")
        XCTAssertEqual(rows[0]["reason"] as? String, "imageLiveInEditor")
        // The disk truth untouched.
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: LightamerSidecar.sidecarURL(for: fixture.targetURL).path),
            "the rejected target keeps its pristine state")
    }

    /// A non-member target = the per-target notSessionMember row; the
    /// held project probe = the WHOLE call typed projectReadOnly.
    func testPasteAdjustmentsMembershipAndProbeArms() async throws {
        let fixture = try await makeTransferFixture()
        let seams = await makeSeams(session: (fixture.store, fixture.root))
        let registry = await makeRegistry(seams: seams)
        let payload = try await Self.jsonOutput(try await registry.call(
            name: "paste_adjustments",
            arguments: [
                "source": .string(fixture.sourceRel),
                "targets": .array([.string("Capture/GONE.ARW")]),
            ]))
        XCTAssertEqual(payload["appliedCount"] as? Int, 0)
        let rows = try XCTUnwrap(payload["targets"] as? [[String: Any]])
        XCTAssertEqual(rows[0]["reason"] as? String, "notSessionMember")

        // The probe arm (whole call).
        var heldSeams = await makeSeams(session: (fixture.store, fixture.root))
        heldSeams.projectWriteProbe = { .held(holderSummary: "pid 42", guidance: "g") }
        let heldRegistry = await makeRegistry(seams: heldSeams)
        do {
            _ = try await heldRegistry.call(
                name: "paste_adjustments",
                arguments: [
                    "source": .string(fixture.sourceRel),
                    "targets": .array([.string(fixture.targetRel)]),
                ])
            XCTFail("the held probe must refuse the whole call")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "projectReadOnly")
        }
    }

    /// Duplicate targets = typed invalidParams (F10: silent dedup would
    /// mask a caller bug); the unreadable source = the all-rejected
    /// ledger with the unreadableSidecar token (F7's fixed set).
    func testPasteAdjustmentsDuplicateAndUnreadableSourceArms() async throws {
        let fixture = try await makeTransferFixture()
        let seams = await makeSeams(session: (fixture.store, fixture.root))
        let registry = await makeRegistry(seams: seams)
        do {
            _ = try await registry.call(
                name: "paste_adjustments",
                arguments: [
                    "source": .string(fixture.sourceRel),
                    "targets": .array([
                        .string(fixture.targetRel), .string(fixture.targetRel),
                    ]),
                ])
            XCTFail("duplicate targets must be typed")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
        }
        // The pristine session member (no sidecar) = the honest rejected
        // ledger, never a throw.
        // The bare member rides a FRESH session (the two-entry scan face
        // cannot carry a sidecar-less member twice; a second store with
        // only the bare row keeps the source fixture untouched).
        let bareSession = try await makeSession(imageName: "BARE.ARW")
        let goneRel = "Capture/BARE.ARW"
        let bareSeams = await makeSeams(session: (bareSession.store, bareSession.root))
        let bareRegistry = await makeRegistry(seams: bareSeams)
        let payload = try await Self.jsonOutput(try await bareRegistry.call(
            name: "paste_adjustments",
            arguments: [
                "source": .string(goneRel),
                "targets": .array([.string(goneRel)]),
            ]))
        XCTAssertEqual(payload["appliedCount"] as? Int, 0)
        let rows = try XCTUnwrap(payload["targets"] as? [[String: Any]])
        XCTAssertEqual(rows[0]["reason"] as? String, "unreadableSidecar")
    }

    /// The include subset + the includeDrt opt-out ride the payload build
    /// (only the whitelisted instance lands; the DRT row drops).
    func testPasteAdjustmentsIncludeSubsetAndDrtOptOut() async throws {
        let fixture = try await makeTransferFixture()
        let seams = await makeSeams(session: (fixture.store, fixture.root))
        let registry = await makeRegistry(seams: seams)
        let copy = try await Self.jsonOutput(try await registry.call(
            name: "copy_adjustments",
            arguments: ["source": .string(fixture.sourceRel)]))
        let grades = try XCTUnwrap(copy["grades"] as? [[String: Any]])
        let items = try XCTUnwrap(grades[0]["items"] as? [[String: Any]])
        let exposureRow = try XCTUnwrap(
            items.first { ($0["opName"] as? String) == ExposureModule.opName })
        let exposureID = try XCTUnwrap(exposureRow["instanceId"] as? String)
        let payload = try await Self.jsonOutput(try await registry.call(
            name: "paste_adjustments",
            arguments: [
                "source": .string(fixture.sourceRel),
                "targets": .array([.string(fixture.targetRel)]),
                "include": .array([.string(exposureID)]),
                "includeDrt": .bool(false),
            ]))
        XCTAssertEqual(payload["appliedCount"] as? Int, 1)
        let target = try Self.sidecarDoc(fixture.targetURL)
        let top = try XCTUnwrap(target.history.items.last)
        let pasted = try XCTUnwrap(top.pasteSet)
        XCTAssertEqual(pasted.count, 1, "only the whitelisted instance lands")
        XCTAssertEqual(pasted[0].opName, ExposureModule.opName)
        // includeDrt=false → the target history carries NO drt item.
        XCTAssertFalse(
            target.history.items.contains { $0.drtRecord != nil },
            "the DRT row must not ride an includeDrt=false paste")
        // UUID recast: the pasted ids differ from the source instance id.
        XCTAssertNotEqual(pasted[0].id, fixture.sourceExposureID)
    }
}
