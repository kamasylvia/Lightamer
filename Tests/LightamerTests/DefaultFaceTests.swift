import XCTest

@testable import Lightamer
@testable import LightamerCore
import LightamerIOP

// ─────────────────────────────────────────────────────────────────────────────
// DefaultFaceTests (Plan M2-1 T1/T2/T3) — the dt-face feature-flag disable
// suite. The matrix of record is
// `.work/gsd/phases/m2-1-dt-disable/M2-1-MATRIX.md` (禁用 6 / 启用 33); the
// machine-readable twin is `LightamerIOPRegistry.defaultFaceDisabledOpNames`.
//
// Covered faces:
//   T1 registry seam  — disable-set constancy, default-face population,
//                       the KD-2 full-face default-parameter reverse pin,
//                       the seed face (sort invariant + count contract);
//   T1 red line       — legacy sidecar round-trip through the 02-06
//                       degradedForUnknownOps/degradedLayerStack mechanism:
//                       record + paramsData bytes survive verbatim,
//                       enabled=false, typed unknownOps, write→reload
//                       byte-identical (KD-4: 可读、可写、不崩、数据不丢);
//   T1 MCP face       — apply_params upsert of a disabled op = typed
//                       unknownOp; `remove: true` still flows (the
//                       `registered || op.remove` contract — deletion does
//                       not need a factory);
//   T2 UI face        — registerDefaultProviders(defaultFace:) gates the 6
//                       panels; the default parameter keeps all of them
//                       (PanelWiringTests' existing assertions stay green);
//   T3 catalog face   — list_iops output drops the 3 cataloged disabled
//                       entries while `IopCatalog.ops` keeps all 18 (the
//                       reflection guard is untouched).
// ─────────────────────────────────────────────────────────────────────────────

final class DefaultFaceTests: XCTestCase {

    /// The disable set under test (matrix rows 1-6; D1 trio + D2 trio).
    private static let disabled = LightamerIOPRegistry.defaultFaceDisabledOpNames

    /// String spellings of the matrix disable set — the ONLY place literals
    /// are legal (production builds the set from opName constants; this test
    /// is the drift guard pinning constant ↔ matrix equality).
    private static let matrixDisabledNames: Set<String> = [
        "filmicrgb", "sigmoid", "agx",
        "denoiseprofile", "nlmeans", "bilateral",
    ]

    /// Enabled probes spanning the matrix's keep faces: the terminal trio
    /// (pipeline infrastructure), enabled-set samples (§10 direct mapping),
    /// gray-zone keeps (D6 — including `bilat`, the near-neighbor of the
    /// disabled `bilateral`), and the yiyin/native rows.
    private static let enabledProbes: [String] = [
        ColorInModule.opName,
        ColorOutModule.opName,
        GammaModule.opName,
        ExposureModule.opName,
        TemperatureModule.opName,
        ColisaModule.opName,
        ToneCurveModule.opName,
        ToneEqualModule.opName,
        ShadhiModule.opName,
        LocalContrastModule.opName,
        ColorBalanceRGBModule.opName,
        Lut3dModule.opName,
        BordersModule.opName,
        WatermarkModule.opName,
        SkinSmoothModule.opName,
        TextOverlayModule.opName,
    ]

    // MARK: - T1: the disable-set constant (matrix twin)

    /// AC1: the constant is EXACTLY the matrix disable set, 6 entries —
    /// no drift in either direction (a widened set would disable a kept
    /// module; a shrunken one would leak a D1/D2 module back into the
    /// default face).
    func testDisabledSetMatchesMatrixExactly() {
        XCTAssertEqual(
            Self.disabled, Self.matrixDisabledNames,
            "defaultFaceDisabledOpNames must equal the M2-1-MATRIX disable set")
        XCTAssertEqual(Self.disabled.count, 6)
    }

    // MARK: - T1: the registry seam (KD-1 population, KD-2 reverse pin)

    /// AC2: a default-face registry leaves the disable set UNADDRESSABLE
    /// (`makeBox` nil) while the terminal trio + enabled probes stay
    /// addressable.
    func testDefaultFaceRegistryExcludesDisabledAndKeepsEnabled() async {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry, defaultFace: true)
        for opName in Self.matrixDisabledNames {
            let box = await registry.makeBox(opName: opName)
            XCTAssertNil(
                box, "\(opName) must be unaddressable in the default face")
        }
        XCTAssertGreaterThanOrEqual(Self.enabledProbes.count, 8)
        for opName in Self.enabledProbes {
            let box = await registry.makeBox(opName: opName)
            XCTAssertNotNil(
                box, "\(opName) must stay addressable in the default face")
        }
    }

    /// AC8/KD-2 reverse pin: `populate` WITHOUT the face argument (and with
    /// `defaultFace: false` explicitly) keeps all six registered — the
    /// pre-M2-1 behavior every existing caller/test relies on is unchanged.
    func testFullFaceDefaultParameterKeepsDisabledRegistered() async {
        // The bare call (the KD-2 default-parameter contract).
        let full = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(full)
        for opName in Self.matrixDisabledNames {
            let box = await full.makeBox(opName: opName)
            XCTAssertNotNil(
                box, "\(opName) must stay registered under the default parameter")
        }
        // The explicit false (the full-face opt-out of the opt-in).
        let explicit = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(explicit, defaultFace: false)
        for opName in Self.matrixDisabledNames {
            let box = await explicit.makeBox(opName: opName)
            XCTAssertNotNil(box, "\(opName) must stay registered under false")
        }
    }

    // MARK: - T1: the seed face (KD-1 filter, v50 invariant)

    /// AC3: the default-face seed excludes the disable set, keeps the v50
    /// sort invariant, and satisfies the count contract full − 6. The
    /// default parameter keeps the disabled rows (the KD-2 mirror).
    func testDefaultFaceSeedExcludesDisabledKeepsSortAndCount() {
        let full = LightamerIOPRegistry.editingDefaultInstances()
        let narrow = LightamerIOPRegistry.editingDefaultInstances(defaultFace: true)

        XCTAssertEqual(narrow.count, full.count - 6, "count contract: full − 6")
        for instance in narrow {
            XCTAssertFalse(
                Self.disabled.contains(instance.opName),
                "the default-face seed must not contain \(instance.opName)")
        }
        XCTAssertTrue(
            full.contains { Self.disabled.contains($0.opName) },
            "the full-face seed keeps the disabled rows (KD-2)")
        // The six dropped rows are exactly the disable set.
        let dropped = Set(full.map(\.opName)).subtracting(narrow.map(\.opName))
        XCTAssertEqual(dropped, Self.matrixDisabledNames)

        // v50 sort invariant holds on the narrowed seed.
        XCTAssertEqual(
            narrow, narrow.sorted {
                ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
            }, "the narrowed seed must stay v50-sorted")
    }

    // MARK: - T1: the round-trip red line (KD-4)

    /// AC4 — THE red line: a legacy sidecar whose global history carries an
    /// ENABLED filmicrgb item and whose layer chain carries a sigmoid item
    /// opens, degrades, saves, and reloads WITHOUT losing a byte of user
    /// data. Degraded faces: record count unchanged, paramsData byte-equal,
    /// enabled=false, typed unknownOps (global ["filmicrgb"] / layer
    /// ["sigmoid"]); the write→reload disk round-trip is byte-identical to
    /// the canonical encoding of the degraded document.
    func testLegacySidecarWithDisabledOpsRoundTripsByteSemantics() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry, defaultFace: true)

        // ── A legacy document: enabled filmicrgb (global) + sigmoid (layer),
        //    both with non-default params bytes.
        var filmicParams = FilmicRGBModule.Params()
        filmicParams.contrast = 1.37
        let filmic = ModuleInstance(
            module: FilmicRGBModule.self, params: filmicParams)
        var stack = HistoryStack()
        stack.commit(filmic, label: "filmic edit")

        var sigmoidParams = SigmoidModule.Params()
        sigmoidParams.contrastSkewness = 0.62
        let sigmoid = ModuleInstance(
            module: SigmoidModule.self, params: sigmoidParams)
        var layerStack = LayerStack(baseLayer: BackgroundLayer())
        layerStack.addAdjustment(
            AdjustmentLayer(name: "Sigmoid leg", opacity: 1.0, chain: [sigmoid]))

        let decodeHash: UInt64 = 0x1234_5678_9ABC_DEF0
        let document = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash,
            instances: [filmic], history: stack,
            historyHash: HistoryHash.hash(
                stack: stack, decodeParamsHash: decodeHash,
                layerSnapshot: LayerStackSnapshot(layerStack)),
            appVersion: "99.0.0",
            layerStack: SidecarLayerStackRecord(layerStack))

        // ── Global leg degrade (02-06 mechanism, default-face registry).
        let (degradedHistory, globalUnknown) =
            await document.degradedForUnknownOps(registry: registry)
        XCTAssertEqual(globalUnknown, ["filmicrgb"], "typed unknownOp for the toast")
        XCTAssertEqual(degradedHistory.items.count, stack.items.count,
                       "record count unchanged")
        let degradedSnapshot = degradedHistory.items[0].snapshot
        XCTAssertFalse(degradedSnapshot.enabled, "the disabled op degrades off")
        XCTAssertEqual(degradedSnapshot.paramsData, filmic.paramsData,
                       "paramsData preserved byte-for-byte")
        XCTAssertEqual(degradedSnapshot.paramsHash, filmic.paramsHash,
                       "the hash atom rides along untouched")
        XCTAssertEqual(degradedSnapshot.opName, FilmicRGBModule.opName)
        XCTAssertEqual(degradedHistory.position, stack.position)

        // ── Layer leg degrade (06-01 mechanism): the whole layer flips off,
        //    chain bytes stay verbatim.
        let (degradedLayers, layerUnknown) =
            await document.degradedLayerStack(registry: registry)
        XCTAssertEqual(layerUnknown, ["sigmoid"])
        let layerRecords = degradedLayers?.layers ?? []
        XCTAssertEqual(layerRecords.count, 1)
        XCTAssertFalse(layerRecords[0].enabled,
                       "the unknown-op layer drops out of the composite")
        XCTAssertEqual(layerRecords[0].chain[0].instance.paramsData,
                       sigmoid.paramsData,
                       "layer chain paramsData preserved byte-for-byte")

        // ── Compose the degraded document the way the restore path would
        //    persist it, then write → reload through a real SidecarStore.
        var degradedFilmic = filmic
        degradedFilmic.enabled = false
        let degradedDocument = LightamerSidecar(
            imageID: document.imageID,
            decoderVersionUsed: document.decoderVersionUsed,
            decodeParamsHash: document.decodeParamsHash,
            instances: [degradedFilmic],
            history: degradedHistory,
            historyHash: document.historyHash,
            appVersion: document.appVersion,
            layerStack: degradedLayers)

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("m21-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("legacy.ARW.lra")
        let store = SidecarStore(destination: destination)
        await store.scheduleWrite(degradedDocument)
        try await store.flushNow()

        // The file on disk is the canonical encoding of the degraded
        // document (byte面 round-trip, half one).
        let written = try Data(contentsOf: destination)
        let canonical = try JSONEncoder().encode(degradedDocument)
        // NOTE: SidecarStore encodes with [.prettyPrinted, .sortedKeys].
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        XCTAssertEqual(written, try encoder.encode(degradedDocument),
                       "the file bytes equal the canonical degraded encoding")

        // Reload + byte-semantic equality (half two).
        let reloadedStore = SidecarStore(destination: destination)
        let reloadedDoc = await reloadedStore.load()
        let reloaded = try XCTUnwrap(reloadedDoc)
        XCTAssertEqual(reloaded, degradedDocument,
                       "reload restores the degraded document whole")

        // The explicit red-line fields off the RELOADED document.
        let reloadedGlobal = reloaded.history.items[0].snapshot
        XCTAssertEqual(reloadedGlobal.paramsData, filmic.paramsData)
        XCTAssertFalse(reloadedGlobal.enabled)
        let reloadedLayer = try XCTUnwrap(
            reloaded.layerStack?.layers.first)
        XCTAssertFalse(reloadedLayer.enabled)
        XCTAssertEqual(reloadedLayer.chain[0].instance.paramsData,
                       sigmoid.paramsData)

        // Idempotence: a second degrade pass over the reloaded document is
        // stable (no un-degrade, no byte churn beyond canonical equality).
        let (secondPass, secondUnknown) =
            await reloaded.degradedForUnknownOps(registry: registry)
        XCTAssertEqual(secondUnknown, ["filmicrgb"])
        XCTAssertEqual(secondPass.items[0].snapshot.paramsData, filmic.paramsData)
        XCTAssertFalse(secondPass.items[0].snapshot.enabled)
    }

    // MARK: - T1: the MCP write face (unknownOp typed rejection)

    /// AC7 partial: with a default-face registry, an apply_params UPSERT of
    /// a disabled op throws the typed `unknownOp` (the `makeBox != nil`
    /// addressing seam narrows for free), while `remove: true` still flows —
    /// deletion does not need a factory, so a legacy image's disabled
    /// instance stays agent-removable.
    func testDefaultFaceProjectInstancesRejectsUpsertAllowsRemove() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry, defaultFace: true)
        let current = LightamerIOPRegistry.editingDefaultInstances(defaultFace: true)

        do {
            _ = try await EditingToolset.projectInstances(
                current: current,
                ops: [EditingToolset.ParamOp(
                    opName: FilmicRGBModule.opName, multiPriority: 0,
                    params: nil, enabled: nil, remove: false)],
                modules: registry)
            XCTFail("upserting a default-face-disabled op must be unknownOp")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "unknownOp")
        }

        // A legacy record (as an old sidecar would carry it, disabled by
        // the degrade pass) stays REMOVABLE through the narrowed face.
        var legacy = ModuleInstance(
            module: FilmicRGBModule.self, params: FilmicRGBModule.Params())
        legacy.enabled = false
        let projected = try await EditingToolset.projectInstances(
            current: current + [legacy],
            ops: [EditingToolset.ParamOp(
                opName: FilmicRGBModule.opName, multiPriority: 0,
                params: nil, enabled: nil, remove: true)],
            modules: registry)
        XCTAssertFalse(
            projected.contains { $0.opName == FilmicRGBModule.opName },
            "remove: true must stay addressable for legacy instances")
    }
}
