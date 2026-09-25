import LightamerCore
import Metal
@testable import LightamerIOP
import XCTest

/// Plan 08-3 T4 — the yiyin END-TO-END suite: open image → configure the
/// border frame → configure the watermark → ⌘Z step-by-step → sidecar
/// round-trip, all through the REAL pipe with the FULL editing seed and
/// the coordinator's joint-context wiring (D-08-3-T3-2 mirrored), all
/// byte-exact comparisons (the 06-05 E2E precedent: three passes + a
/// cross-restart liveness proof), plus the four-state instance-switch
/// matrix (双关 == 无实例基线 逐字节).
final class YiyinE2ETests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("yiyin-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - the E2E flow

    func testOpenConfigureUndoSidecarRoundTripByteExact() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let image = gradientImage(width: 96, height: 64)
        let imageID = UUID(uuidString: "DEADBEEF-1234-5678-9ABC-DEF012345678")!

        // ── 开图: the pristine seed (trio + editing defaults incl. the
        // yiyin neutral carriers) renders the baseline. ──
        let trioRecords = await registry.makeDefaultInstances()
        let seedRecords = (trioRecords + LightamerIOPRegistry.editingDefaultInstances())
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        let seedBoxes = try await materialize(seedRecords, registry: registry)
        let baseline = try await renderAndRead(seedBoxes, image: image, imageID: imageID, metal: metal)

        // ── 配印框: borders (canvas growth + radius + shadow + dark band)
        // through the SAME record→box path the coordinator drives. ──
        var bordersConfigured = try seedRecords.first { $0.opName == BordersModule.opName }!
            .params(of: BordersModule.self)
        bordersConfigured.mode = .solid(color: "#101010")
        bordersConfigured.mainImageWidthRate = 85
        bordersConfigured.cornerRadius = 3.0
        bordersConfigured.shadow = 5.0
        var bordersRecord = seedRecords.first { $0.opName == BordersModule.opName }!
        try bordersRecord.setParams(bordersConfigured, as: BordersModule.self)
        var configuredRecords = seedRecords
        let bordersIndex = configuredRecords.firstIndex { $0.id == bordersRecord.id }!
        configuredRecords[bordersIndex] = bordersRecord
        var boxes = try await materialize(configuredRecords, registry: registry)
        wireYiyinContext(boxes: boxes, records: configuredRecords, image: image)
        let bordersOnly = try await renderAndRead(boxes, image: image, imageID: imageID, metal: metal)
        XCTAssertNotEqual(bordersOnly, baseline, "the border frame changed the render")

        // ── 配水印: a literal row (4% font, white) + center anchor. ──
        var watermarkConfigured = WatermarkModule.Params.neutralSeed
        watermarkConfigured.templates = [YiyinTemplate(
            key: "row", name: "n", pattern: "LIGHTAMER E2E", use: true,
            font: YiyinFont(sizePercent: 4, color: "#ffffff"))]
        watermarkConfigured.fields = []
        watermarkConfigured.anchor = .center
        var watermarkRecord = seedRecords.first { $0.opName == WatermarkModule.opName }!
        try watermarkRecord.setParams(watermarkConfigured, as: WatermarkModule.self)
        let watermarkIndex = configuredRecords.firstIndex { $0.id == watermarkRecord.id }!
        configuredRecords[watermarkIndex] = watermarkRecord
        boxes = try await materialize(configuredRecords, registry: registry)
        wireYiyinContext(boxes: boxes, records: configuredRecords, image: image)
        let bothConfigured = try await renderAndRead(boxes, image: image, imageID: imageID, metal: metal)
        XCTAssertNotEqual(bothConfigured, bordersOnly, "the watermark row changed the render")

        // ── ⌘Z 逐级还原 (the interleaved undo, byte-exact at each step):
        // #1 reverts the LAST commit (the watermark) → the borders-only
        // state; #2 reverts the borders → the pristine seed. ──
        var stepRecords = configuredRecords
        let stepIndex = stepRecords.firstIndex { $0.id == watermarkRecord.id }!
        stepRecords[stepIndex] = seedRecords.first { $0.opName == WatermarkModule.opName }!
        boxes = try await materialize(stepRecords, registry: registry)
        wireYiyinContext(boxes: boxes, records: stepRecords, image: image)
        let undoOne = try await renderAndRead(boxes, image: image, imageID: imageID, metal: metal)
        XCTAssertEqual(undoOne, bordersOnly, "⌘Z #1 lands byte-exactly on the borders-only state")

        let pristineRecords = seedRecords
        boxes = try await materialize(pristineRecords, registry: registry)
        wireYiyinContext(boxes: boxes, records: pristineRecords, image: image)
        let undoTwo = try await renderAndRead(boxes, image: image, imageID: imageID, metal: metal)
        XCTAssertEqual(undoTwo, baseline, "⌘Z #2 lands byte-exactly on the pristine seed")

        // ── persist: the configured session into a sidecar (the history
        // carries the two commits; the live records = the configured set).
        var history = HistoryStack()
        history.commit(bordersRecord, label: "印框")
        history.commit(watermarkRecord, label: "水印")
        let decodeSeed: UInt64 = 0x1234_5678_9ABC_DEF0
        let document = LightamerSidecar(
            imageID: imageID,
            decoderVersionUsed: "v8",
            decodeParamsHash: decodeSeed,
            instances: configuredRecords,
            history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: decodeSeed),
            appVersion: "0.3.0-e2e")
        let destination = tempDirectory.appendingPathComponent("E2E_0001.ARW.lra")
        let store = SidecarStore(destination: destination)
        await store.scheduleWrite(document)
        try await store.flushNow() // 切图/退出强制落盘语义 (D-S3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

        // ── 跨重启活体复证: EVERYTHING dropped — fresh registry, cache,
        // metal context, boxes. The sidecar restores the session; the
        // restore projection (EditorState.restoreFromSidecar's rule)
        // re-derives the live records; THREE render passes must all be
        // byte-exact vs the pre-persist configured render. ──
        let registry2 = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry2)
        let store2 = SidecarStore(destination: destination)
        let loadedRaw = await store2.load()
        let loaded = try XCTUnwrap(loadedRaw, "the sidecar restores")
        XCTAssertFalse(loaded.driftDetected, "no history drift across the round-trip")
        let (degraded, unknown) = await loaded.degradedForUnknownOps(registry: registry2)
        XCTAssertTrue(unknown.isEmpty, "no unknown ops — borders/watermark persisted cleanly")
        let effective = degraded.effectiveInstances()
        let base = loaded.instances.filter { record in
            !effective.contains {
                $0.opName == record.opName && $0.multiPriority == record.multiPriority
            }
        }
        var merged = base
        for record in effective {
            if let index = merged.firstIndex(where: {
                $0.opName == record.opName && $0.multiPriority == record.multiPriority
            }) {
                merged[index] = record
            } else {
                merged.append(record)
            }
        }
        merged.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        XCTAssertEqual(merged, configuredRecords, "the restore projection == the live set")

        let metal2 = try MetalContext()
        try await metal2.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        for pass in 1...3 {
            let boxes2 = try await materialize(merged, registry: registry2)
            wireYiyinContext(boxes: boxes2, records: merged, image: image)
            let restored = try await renderAndRead(boxes2, image: image, imageID: loaded.imageID, metal: metal2)
            XCTAssertEqual(restored, bothConfigured,
                           "cross-restart pass \(pass): byte-exact vs the pre-persist render")
        }
    }

    /// The four-state instance-switch matrix: 仅 borders / 仅 watermark /
    /// 双开 / 双关 — the 双关 state must equal the NO-instance baseline
    /// byte-exactly (the 禁用 == 无实例 red line at E2E level), and each
    /// active combination must differ from the baseline and from each
    /// other (真内容差异, not vacuous bookkeeping).
    func testFourStateCombinationMatrix() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let image = gradientImage(width: 96, height: 64)
        let imageID = UUID()

        let trioRecords = await registry.makeDefaultInstances()
        let seedRecords = (trioRecords + LightamerIOPRegistry.editingDefaultInstances())
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }

        var bordersParams = BordersModule.Params.neutralSeed
        bordersParams.mode = .solid(color: "#202020")
        bordersParams.mainImageWidthRate = 80
        var watermarkParams = WatermarkModule.Params.neutralSeed
        watermarkParams.templates = [YiyinTemplate(
            key: "row", name: "n", pattern: "MATRIX", use: true,
            font: YiyinFont(sizePercent: 4, color: "#ffffff"))]
        watermarkParams.fields = []

        let bordersRecord = ModuleInstance(module: BordersModule.self, params: bordersParams)
        let watermarkRecord = ModuleInstance(module: WatermarkModule.self, params: watermarkParams)

        func records(_ borders: Bool, _ watermark: Bool, disableBorders: Bool = false,
                     disableWatermark: Bool = false) -> [ModuleInstance] {
            var records = seedRecords.filter {
                $0.opName != BordersModule.opName && $0.opName != WatermarkModule.opName
            }
            if borders {
                var r = bordersRecord
                r.enabled = !disableBorders
                records.append(r)
            }
            if watermark {
                var r = watermarkRecord
                r.enabled = !disableWatermark
                records.append(r)
            }
            return records.sorted {
                ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
            }
        }

        func render(_ records: [ModuleInstance]) async throws -> [UInt8] {
            let boxes = try await materialize(records, registry: registry)
            wireYiyinContext(boxes: boxes, records: records, image: image)
            return try await renderAndRead(boxes, image: image, imageID: imageID, metal: metal)
        }

        let base = try await render(records(false, false))
        let onlyBorders = try await render(records(true, false))
        let onlyWatermark = try await render(records(false, true))
        let both = try await render(records(true, true))
        let bothDisabled = try await render(records(true, true, disableBorders: true, disableWatermark: true))

        // The red line: 双关 == 无实例基线 逐字节.
        XCTAssertEqual(bothDisabled, base, "both disabled == no-instance baseline, byte-exact")
        // Every active state differs from the baseline (content-level).
        XCTAssertNotEqual(onlyBorders, base, "borders-only changed the render")
        XCTAssertNotEqual(onlyWatermark, base, "watermark-only changed the render")
        XCTAssertNotEqual(both, base, "both changed the render")
        // The active states differ from EACH OTHER (真比较 — no vacuous pass).
        XCTAssertNotEqual(onlyBorders, onlyWatermark)
        XCTAssertNotEqual(both, onlyBorders, "adding the watermark to borders changes bytes")
        XCTAssertNotEqual(both, onlyWatermark, "adding the borders to watermark changes bytes")
    }

    // MARK: - harness

    /// Materialize the records through the registry (the coordinator's
    /// identity-preserving path) and apply each record.
    private func materialize(
        _ records: [ModuleInstance], registry: ModuleRegistry
    ) async throws -> [any ModuleBoxing] {
        var boxes: [any ModuleBoxing] = []
        for record in records {
            guard let box = await registry.makeBox(opName: record.opName, instanceID: record.id) else {
                continue // unknown op degrade — none expected for the seed
            }
            try box.apply(record)
            boxes.append(box)
        }
        return boxes
    }

    /// The coordinator's per-run yiyin wiring (D-08-3-T3-2 mirrored at
    /// FULL extent — longEdge nil ⇒ the entry plane IS the image extent).
    private func wireYiyinContext(
        boxes: [any ModuleBoxing], records: [ModuleInstance], image: DecodedImage
    ) {
        guard let watermarkBox = boxes.first(where: { $0.opName == WatermarkModule.opName })
            as? ModuleBox<WatermarkModule>
        else { return }
        let bordersParams = try? records
            .first { $0.opName == BordersModule.opName }?
            .params(of: BordersModule.self)
        let mainSize = SIMD2(Int(image.ciImage.extent.width), Int(image.ciImage.extent.height))
        let watermark = watermarkBox.module
        watermark.captureExif = image.capture
        watermark.jointContext = WatermarkModule.JointContext(
            mainImageSize: mainSize, bordersParams: bordersParams)
        guard let bordersBox = boxes.first(where: { $0.opName == BordersModule.opName })
            as? ModuleBox<BordersModule>
        else { return }
        bordersBox.module.jointLayoutOverride = watermark.makeJointLayoutRecord(
            mainImageSize: mainSize, bordersParams: bordersParams)
    }

    /// Full chain render (gamma included — the real display path, the
    /// bgra8 tail) + fence (L014) + raw byte read.
    private func renderAndRead(
        _ boxes: [any ModuleBoxing], image: DecodedImage, imageID: UUID, metal: MetalContext
    ) async throws -> [UInt8] {
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: boxes, imageID: imageID,
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
        drain(metal)
        let bytesPerPixel = 4 // the gamma tail: .bgra8Unorm
        let rowBytes = texture.width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: rowBytes * texture.height)
        bytes.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: rowBytes,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        return bytes
    }

    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    private func gradientImage(width: Int, height: Int) -> DecodedImage {
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                rgba[i + 0] = Float(x) / Float(max(width - 1, 1))
                rgba[i + 1] = Float(y) / Float(max(height - 1, 1))
                rgba[i + 2] = 0.25
                rgba[i + 3] = 1.0
            }
        }
        var data = Data(capacity: rgba.count * 4)
        for value in rgba {
            var le = value.bitPattern.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
        }
        let provider = CGDataProvider(data: data as CFData)!
        let cg = CGImage(
            width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
            bytesPerRow: width * 16, space: WorkingSpace.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return DecodedImage(
            ciImage: CIImage(cgImage: cg),
            rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8)
    }
}
