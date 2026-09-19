@testable import LightamerCore
import CoreImage
import LightamerIOP
import Metal
import XCTest

/// History stack + identity + hash semantics (Plan 02-05-07; HIST-01/02/04,
/// D-H1, D-H2). Covers: commit/undo/redo/jump pointer transitions (HIST-02),
/// redo-tail truncation, `(opName, multiPriority)` dedup with v50 sort
/// (the `history.c:1600-1607` translation), the D-H1 drag-end trio's item
/// economy (0 items live / exactly 1 on commit — the mutation-sequence twin
/// of `PipeCoordinator`, which lives app-internally and is not
/// test-importable; the coordinator wiring itself is verified by build +
/// inspection, recorded in the plan summary), the FNV-1a history-hash
/// golden vector + determinism (HIST-04/D-H4), Codable round-trips (the
/// schema 02-06 persists), and the SC#2 undo leg end-to-end through
/// history-driven re-materialization (record → box via `ModuleRegistry`
/// + `ModuleBoxing.apply` — the exact path `PipeCoordinator
/// .rematerializeInstances` runs).
final class HistoryStackTests: XCTestCase {

    /// Distinctive fixed decode seed so golden vectors are independent of
    /// the FNV offset basis.
    private static let decodeSeed: UInt64 = 0xDEAD_BEEF_CAFE_BABE

    // ── The golden vector (HIST-04) ──────────────────────────────────────
    //
    // RECIPE (how the constant was generated — deterministic, recompute
    // anywhere with the same LightamerCore):
    //   decodeParamsHash          = 0xDEADBEEFCAFEBABE
    //   effective instance set (v50-ascending, (iopOrder, multiPriority,
    //   opName) tiebreak), each folded as
    //   opName-UTF8 ‖ multiPriority-LE(8) ‖ version-LE(8) ‖ paramsData:
    //     1. colorin  mp0  v1  params = ColorInModule.Params()  (nil
    //        inputProfile → canonical JSON `{}`)
    //     2. testgain mp0  v1  params = {"gain":1.5}
    //     3. testgain mp1  v1  params = {"gain":2}
    //   (paramsData via ParamsCoding.encode — .sortedKeys canonical, L013)
    private static let goldenThreeInstanceStackHash: UInt64 = 0x684A_EC37_2467_B526

    // ── Fixtures ──────────────────────────────────────────────────────────

    private func makeGain(
        _ gain: Float,
        priority: Int = 0,
        id: UUID = UUID(),
        enabled: Bool = true
    ) -> ModuleInstance {
        ModuleInstance(
            id: id, module: TestGainModule.self, multiPriority: priority,
            multiName: "gain\(priority)", params: .init(gain: gain),
            enabled: enabled
        )
    }

    private func makeColorin(id: UUID = UUID()) -> ModuleInstance {
        ModuleInstance(id: id, module: ColorInModule.self, params: .init())
    }

    private func makeColorout(id: UUID = UUID()) -> ModuleInstance {
        ModuleInstance(id: id, module: ColorOutModule.self, params: .init())
    }

    private func makeGamma(id: UUID = UUID()) -> ModuleInstance {
        ModuleInstance(id: id, module: GammaModule.self, params: .init())
    }

    private func commitAll(
        _ stack: inout HistoryStack,
        _ records: [(ModuleInstance, String)]
    ) {
        for (record, label) in records {
            stack.commit(record, label: label)
        }
    }

    // ── 1. HIST-01: commit appends; the stack is the only surface ────────

    func testCommitAppendsAndMovesPosition() throws {
        var stack = HistoryStack()
        XCTAssertTrue(stack.items.isEmpty)
        XCTAssertEqual(stack.position, -1)
        XCTAssertNil(stack.currentValue)

        let gain = makeGain(1.5)
        let colorin = makeColorin()
        stack.commit(gain, label: "gain 1.5")
        stack.commit(colorin, label: "colorin")

        XCTAssertEqual(stack.items.count, 2)
        XCTAssertEqual(stack.position, 1)
        XCTAssertEqual(stack.currentValue?.id, colorin.id)
        XCTAssertEqual(stack.items[0].snapshot.id, gain.id)
        XCTAssertEqual(stack.items[0].label, "gain 1.5")

        // HIST-01's "original file untouched" is structural (no I/O in the
        // stack) — the meaningful assertion is VALUE isolation: snapshots
        // held by the caller never change when the stack mutates.
        var probe = gain
        stack.commit(makeGain(2.0), label: "gain 2.0")
        XCTAssertEqual(probe.paramsHash, gain.paramsHash)
        try probe.setParams(TestGainModule.Params(gain: 9.0), as: TestGainModule.self)
        XCTAssertNotEqual(probe.paramsHash, stack.items[0].snapshot.paramsHash)
    }

    // ── 2. HIST-02: undo/redo pointer transitions ────────────────────────

    func testUndoRedoPointerTransitions() {
        var stack = HistoryStack()
        let records = [makeGain(1.0), makeGain(1.5), makeGain(2.0)]
        commitAll(&stack, Array(records.enumerated().map { ($0.element, "s\($0.offset)") }))

        XCTAssertEqual(stack.position, 2)

        let undone = stack.undo()
        XCTAssertEqual(undone?.snapshot.id, records[2].id, "undo returns the entry stepped OFF")
        XCTAssertEqual(stack.position, 1)

        _ = stack.undo()
        _ = stack.undo()
        XCTAssertEqual(stack.position, -1, "pristine floor")
        XCTAssertNil(stack.undo(), "undo at pristine is a no-op")

        let redone = stack.redo()
        XCTAssertEqual(redone?.snapshot.id, records[0].id, "redo returns the entry stepped ONTO")
        XCTAssertEqual(stack.position, 0)
        _ = stack.redo()
        _ = stack.redo()
        XCTAssertEqual(stack.position, 2)
        XCTAssertNil(stack.redo(), "redo at the top is a no-op")
    }

    /// commit-after-undo kills the redo tail.
    func testCommitAfterUndoTruncatesRedoTail() {
        var stack = HistoryStack()
        let a = makeGain(1.0), b = makeGain(1.5), c = makeGain(2.0), d = makeGain(2.5)
        commitAll(&stack, [(a, "a"), (b, "b"), (c, "c")])
        _ = stack.undo()
        _ = stack.undo()
        XCTAssertEqual(stack.position, 0)

        stack.commit(d, label: "d")
        XCTAssertEqual(stack.items.map(\.snapshot.id), [a.id, d.id], "b/c truncated")
        XCTAssertEqual(stack.position, 1)
        XCTAssertNil(stack.redo(), "redo tail is gone")
    }

    /// jump(to:) clamps; a mid-stack jump + commit truncates forward.
    func testJumpClampsAndMidStackCommitTruncates() {
        var stack = HistoryStack()
        let a = makeGain(1.0), b = makeGain(1.5), c = makeGain(2.0), d = makeGain(2.5)
        commitAll(&stack, [(a, "a"), (b, "b"), (c, "c")])

        stack.jump(to: 999)
        XCTAssertEqual(stack.position, 2, "high clamp → top")
        stack.jump(to: -999)
        XCTAssertEqual(stack.position, -1, "low clamp → pristine")
        XCTAssertNil(stack.currentValue)

        stack.jump(to: 0)
        XCTAssertEqual(stack.currentValue?.id, a.id)
        stack.commit(d, label: "d")
        XCTAssertEqual(stack.items.map(\.snapshot.id), [a.id, d.id])
    }

    /// D-H2 uncapped sanity: 100 entries, all retained.
    func testHundredItemStackIsUncapped() {
        var stack = HistoryStack()
        for step in 0..<100 {
            stack.commit(makeGain(Float(step) * 0.01), label: "step \(step)")
        }
        XCTAssertEqual(stack.items.count, 100)
        XCTAssertEqual(stack.position, 99)
        // Same identity throughout → the effective set is ONE instance.
        XCTAssertEqual(stack.effectiveInstances().count, 1)
        XCTAssertEqual(stack.effectiveInstances().first?.paramsHash, stack.items[99].snapshot.paramsHash)
    }

    // ── 3. Dedup rule (history.c:1600-1607 translation) ──────────────────

    /// Same `(opName, multiPriority)` with DIFFERENT UUIDs → only the
    /// latest entry at-or-before position survives.
    func testDedupKeepsLatestPerIdentity() {
        var stack = HistoryStack()
        let first = makeGain(1.0) // fresh UUID
        let second = makeGain(2.0) // different UUID, SAME identity tuple
        let colorin = makeColorin()
        commitAll(&stack, [(first, "g1"), (second, "g2"), (colorin, "colorin")])

        let effective = stack.effectiveInstances()
        XCTAssertEqual(effective.count, 2, "the earlier gain entry is dead state")
        let gainRecord = effective.first { $0.opName == TestGainModule.opName }
        XCTAssertEqual(gainRecord?.id, second.id, "LATEST wins")
        XCTAssertEqual(gainRecord?.paramsHash, second.paramsHash)

        // v50 sort: colorin 28.0 before testgain 50.5.
        XCTAssertEqual(effective.first?.opName, ColorInModule.opName)

        // Jumping back BEFORE the second gain commit resurrects the FIRST
        // gain entry — the snapshot-in-item design restores params as they
        // were. (One undo is not enough: position 1 still contains BOTH
        // gain entries, and the latest-at-or-before-position rule keeps
        // the second — Darktable's GROUP BY … MAX(num) semantics.)
        stack.jump(to: 0)
        let rewound = stack.effectiveInstances().first { $0.opName == TestGainModule.opName }
        XCTAssertEqual(rewound?.id, first.id)
        XCTAssertEqual(rewound?.paramsHash, first.paramsHash)
    }

    /// Different `multiPriority` on the same op → BOTH kept (multi-instance
    /// legality), v50-sorted with the (iopOrder, multiPriority, opName)
    /// stable tiebreak.
    func testMultiInstanceSameOpBothKeptAndSorted() {
        var stack = HistoryStack()
        let low = makeGain(1.0, priority: 0)
        let high = makeGain(2.0, priority: 1)
        let colorout = makeColorout()
        commitAll(&stack, [(high, "hi"), (low, "lo"), (colorout, "colorout")])

        let effective = stack.effectiveInstances()
        XCTAssertEqual(effective.count, 3)
        XCTAssertEqual(effective.map(\.opName), ["testgain", "testgain", "colorout"])
        XCTAssertEqual(effective[0].multiPriority, 0)
        XCTAssertEqual(effective[1].multiPriority, 1)
    }

    /// Disabled instances stay in the effective set (they EXIST with those
    /// params) but fold nothing into the hash.
    func testDisabledInstanceIncludedInEffectiveSkippedByHash() {
        let live = makeGain(1.0)                       // testgain mp0
        let dead = makeGain(2.0, priority: 1, enabled: false) // testgain mp1
        let colorin = makeColorin()

        var stack = HistoryStack()
        commitAll(&stack, [(live, "live"), (dead, "dead"), (colorin, "colorin")])
        XCTAssertTrue(
            stack.effectiveInstances().contains { $0.id == dead.id },
            "disabled instances remain in the effective set"
        )

        // Hash parity: a disabled instance contributes nothing. Both sides
        // fold the SAME v50-ordered enabled chain ([colorin, live]).
        let withDead = HistoryHash.hash(
            instances: stack.effectiveInstances(), decodeParamsHash: Self.decodeSeed
        )
        let withoutDead = HistoryHash.hash(
            instances: [colorin, live], decodeParamsHash: Self.decodeSeed
        )
        XCTAssertEqual(withDead, withoutDead)

        // …and flipping enabled on the SAME params flips the hash.
        let revived = makeGain(2.0, priority: 1, enabled: true)
        let revivedHash = HistoryHash.hash(
            instances: [colorin, live, revived], decodeParamsHash: Self.decodeSeed
        )
        XCTAssertNotEqual(withDead, revivedHash)
    }

    // ── 4. HIST-04: history hash vectors + determinism ───────────────────

    /// Empty/pristine stack → the hash is exactly the decode seed
    /// (`StableHash.combine(seed, [])` folds zero bytes).
    func testPristineStackHashIsTheDecodeSeed() {
        let pristine = HistoryStack()
        XCTAssertEqual(
            HistoryHash.hash(stack: pristine, decodeParamsHash: Self.decodeSeed),
            Self.decodeSeed
        )
        var emptied = HistoryStack()
        commitAll(&emptied, [(makeGain(1.0), "x")])
        emptied.jump(to: -1)
        XCTAssertEqual(
            HistoryHash.hash(stack: emptied, decodeParamsHash: Self.decodeSeed),
            Self.decodeSeed,
            "jumped back to pristine → seed only"
        )
    }

    /// THE golden vector (recipe at the constant). Computed once, pinned.
    func testGoldenThreeInstanceStackVector() {
        var stack = HistoryStack()
        commitAll(
            &stack,
            [
                (makeGain(1.5, priority: 0), "gain 1.5"),
                (makeColorin(), "colorin"),
                (makeGain(2.0, priority: 1), "gain 2.0 (multi)"),
            ]
        )
        XCTAssertEqual(
            HistoryHash.hash(stack: stack, decodeParamsHash: Self.decodeSeed),
            Self.goldenThreeInstanceStackHash,
            "golden vector drift — HistoryHash composition changed (a ONE-WAY schema event)"
        )
    }

    /// Cross-run stability: the SAME recipe computed in a separate test
    /// method (fresh locals, nothing shared but the pinned constant)
    /// matches. Swift `Hasher` is banned from History/ — enforced by
    /// `grep -n "Hasher(" LightamerCore/Sources/Pipe/History/` in review;
    /// these two methods would disagree on ANY per-process state.
    func testGoldenVectorStableAcrossFreshComputation() {
        var stack = HistoryStack()
        stack.commit(makeGain(1.5, priority: 0), label: "gain 1.5")
        stack.commit(makeColorin(), label: "colorin")
        stack.commit(makeGain(2.0, priority: 1), label: "gain 2.0 (multi)")
        XCTAssertEqual(
            HistoryHash.hash(stack: stack, decodeParamsHash: Self.decodeSeed),
            Self.goldenThreeInstanceStackHash
        )
    }

    /// Reordering two DIFFERENT-order instances changes the hash (the v50
    /// order is part of the identity); an order-collision cluster
    /// (equal iopOrder) is deterministic via the stable tiebreak.
    func testReorderSensitivityAndCollisionDeterminism() {
        let colorin = makeColorin()   // 28.0
        let gain = makeGain(1.0)      // 50.5
        let forward = HistoryHash.hash(
            instances: [colorin, gain], decodeParamsHash: Self.decodeSeed
        )
        let backward = HistoryHash.hash(
            instances: [gain, colorin], decodeParamsHash: Self.decodeSeed
        )
        XCTAssertNotEqual(forward, backward, "module order is hashed identity")

        // 50.5 collision cluster (passthrough 50.5 + testgain 50.5 — legal,
        // disambiguated by the tiebreak): the tiebreak-sorted recomputation
        // is deterministic regardless of caller-side input order.
        let pass = ModuleInstance(module: PassthroughModule.self, params: .init())
        func tiebreakSorted(_ records: [ModuleInstance]) -> [ModuleInstance] {
            records.sorted {
                ($0.iopOrder, $0.multiPriority, $0.opName)
                    < ($1.iopOrder, $1.multiPriority, $1.opName)
            }
        }
        let clusterFromGainFirst = HistoryHash.hash(
            instances: tiebreakSorted([gain, pass]), decodeParamsHash: Self.decodeSeed
        )
        let clusterFromPassFirst = HistoryHash.hash(
            instances: tiebreakSorted([pass, gain]), decodeParamsHash: Self.decodeSeed
        )
        XCTAssertEqual(
            clusterFromGainFirst, clusterFromPassFirst,
            "the (iopOrder, multiPriority, opName) tiebreak makes collision clusters deterministic"
        )
    }

    // ── 5. ModuleInstance params/hash + Codable (02-06 schema guard) ─────

    /// paramsHash changes when and only when paramsData changes.
    func testParamsHashTracksParamsData() throws {
        var record = makeGain(1.0)
        let originalData = record.paramsData
        let originalHash = record.paramsHash

        try record.setParams(TestGainModule.Params(gain: 1.0), as: TestGainModule.self)
        XCTAssertEqual(record.paramsData, originalData, "same params → same canonical bytes")
        XCTAssertEqual(record.paramsHash, originalHash)

        try record.setParams(TestGainModule.Params(gain: 3.0), as: TestGainModule.self)
        XCTAssertNotEqual(record.paramsData, originalData)
        XCTAssertNotEqual(record.paramsHash, originalHash)

        // Typed readback decodes the authoritative payload.
        let decoded = try record.params(of: TestGainModule.self)
        XCTAssertEqual(decoded.gain, 3.0)

        // Wrong-type decode is a typed error, not a crash (ColorOut.Params
        // has REQUIRED keys — a testgain payload cannot satisfy it;
        // optional-only Params structs would decode permissively).
        XCTAssertThrowsError(try record.params(of: ColorOutModule.self))
    }

    /// ModuleInstance round-trip: JSON → equal instance, paramsHash intact.
    func testModuleInstanceCodableRoundTrip() throws {
        let record = makeGain(1.5, priority: 2, enabled: false)
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ModuleInstance.self, from: data)
        XCTAssertEqual(decoded, record, "Codable round-trip preserves the FULL record")
        XCTAssertEqual(decoded.paramsHash, record.paramsHash)

        // nil layerScope / optional-free records: distinct enabled flag
        // survives too.
        let enabled = try JSONDecoder().decode(
            ModuleInstance.self, from: try JSONEncoder().encode(makeGain(2.0))
        )
        XCTAssertEqual(enabled.enabled, true)
    }

    /// HistoryStack round-trip — THE schema 02-06 persists; a failure here
    /// is a schema regression. Mid-undo position and per-item fields
    /// (label/timestamp/layerScope) must survive verbatim.
    func testHistoryStackCodableRoundTrip() throws {
        var stack = HistoryStack()
        let a = makeGain(1.0), b = makeColorin(), c = makeColorout()
        stack.commit(a, label: "gain", layerScope: nil)
        stack.commit(b, label: "colorin")
        stack.commit(c, label: "colorout", layerScope: "layer-1")
        _ = stack.undo()
        let before = stack

        let data = try JSONEncoder().encode(stack)
        let decoded = try JSONDecoder().decode(HistoryStack.self, from: data)

        XCTAssertEqual(decoded, before, "items + position round-trip exactly")
        XCTAssertEqual(decoded.position, before.position)
        XCTAssertEqual(decoded.items.count, 3, "the REDO TAIL persists too (D-H2 full log)")
        XCTAssertEqual(decoded.items[2].layerScope, "layer-1")
        XCTAssertEqual(decoded.items[0].snapshot.paramsHash, a.paramsHash)
        XCTAssertEqual(
            decoded.items.map(\.id), stack.items.map(\.id),
            "item UUIDs survive (undo/redo references stay valid)"
        )
    }

    // ── 6. D-H1: the drag-end trio's item economy ────────────────────────

    /// The mutation-sequence twin of `PipeCoordinator`'s trio (app-internal,
    /// not test-importable — the coordinator code executes exactly this):
    /// begin → N × live upsert (stack untouched) → ONE commit.
    func testContinuousEditEmitsZeroItemsThenExactlyOneCommit() {
        var stack = HistoryStack()
        var live: [UUID: ModuleInstance] = [ // the live instance-set mirror
            makeColorin().id: makeColorin()
        ]
        let gainID = makeGain(1.0).id
        live[gainID] = makeGain(1.0)

        // beginContinuousEdit() — state only, no stack effect.
        // setLiveParams per drag tick: upsert into live, NEVER the stack.
        for tick in [1.25, 1.5, 1.75, 2.0] {
            live[gainID] = makeGain(Float(tick), id: gainID)
        }

        XCTAssertTrue(stack.items.isEmpty, "live ticks commit NOTHING (D-H1)")
        XCTAssertEqual(stack.position, -1)

        // commitContinuousEdit: exactly ONE item for the touched instance.
        let final = live[gainID]!
        stack.commit(final, label: "testgain")
        XCTAssertEqual(stack.items.count, 1)
        XCTAssertEqual(stack.position, 0)
        XCTAssertEqual(stack.currentValue?.paramsHash, final.paramsHash)
        XCTAssertEqual(stack.effectiveInstances().count, 1, "only the committed gain is effective — the untouched colorin lives in the live-instance mirror, not the stack")
    }

    // ── 7. SC#2 undo leg end-to-end (history → materialization → pipe) ───

    private func makeSyntheticImage(width: Int, height: Int) -> DecodedImage {
        let ci = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        return DecodedImage(
            ciImage: ci,
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )
    }

    /// The `PipeCoordinator.rematerializeInstances` path, Core-side:
    /// records → boxes via `ModuleRegistry.makeBox(opName:instanceID:)` +
    /// `ModuleBoxing.apply` — identity (UUID) preserved, existing boxes
    /// REUSED in place when the id is unchanged.
    private func materialize(
        _ records: [ModuleInstance],
        registry: ModuleRegistry,
        knownBoxes: inout [UUID: any ModuleBoxing]
    ) async throws -> [any ModuleBoxing] {
        var boxes: [any ModuleBoxing] = []
        for record in records {
            let box: any ModuleBoxing
            if let existing = knownBoxes[record.id] {
                box = existing // IN-PLACE reuse (uniforms/cache survive)
            } else {
                guard let fresh = await registry.makeBox(
                    opName: record.opName, instanceID: record.id
                ) else {
                    continue
                }
                box = fresh
            }
            try await box.apply(record)
            knownBoxes[record.id] = box
            boxes.append(box)
        }
        return boxes
    }

    /// A Core-only registry with `testgain` registered (the default
    /// registry carries ONLY the terminal trio — mirrors
    /// `LightamerIOPRegistry.populate`).
    private func makeRegistry() async -> ModuleRegistry {
        let registry = ModuleRegistry()
        await registry.register(opName: TestGainModule.opName) { id in
            ModuleBox(module: TestGainModule(), instanceID: id)
        }
        return registry
    }

    func testUndoReRenderHitsUpstreamAndRevertedPlanes() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let registry = await makeRegistry()
        let cache = PipeCache()
        let image = makeSyntheticImage(width: 640, height: 480)
        let imageID = UUID()

        // History: [colorin, gain1.0, colorout, gamma] + the "drag" to
        // gain2.0. undo() rewinds the stack — effectiveInstances() returns
        // the PRE-EDIT gain record (inline snapshot restore).
        var stack = HistoryStack()
        let colorin = makeColorin()
        let gainBefore = makeGain(1.0)
        let colorout = makeColorout()
        let gamma = makeGamma()
        commitAll(
            &stack,
            [(colorin, "colorin"), (gainBefore, "gain 1.0"), (colorout, "colorout"), (gamma, "gamma")]
        )
        let gainAfter = makeGain(2.0, id: gainBefore.id) // SAME identity, new params
        stack.commit(gainAfter, label: "gain 2.0 (drag-end)")
        _ = stack.undo() // ← HIST-02 navigation under test

        var knownBoxes: [UUID: any ModuleBoxing] = [:]

        func run(_ records: [ModuleInstance]) async throws -> RenderPipeline.PipeRunStats {
            let boxes = try await materialize(
                records, registry: registry, knownBoxes: &knownBoxes
            )
            return try await RenderPipeline.process(
                image: image, instances: boxes, imageID: imageID,
                resolution: .preview, cache: cache, metal: metal, longEdge: 256
            ).1
        }

        // Run 1 — the PRE-EDIT state: everything misses (5 lines: input +
        // 4 modules). Also proves the materialization + pipe path.
        let run1 = try await run(stack.effectiveInstances())
        XCTAssertEqual(run1.hits, 0)
        XCTAssertEqual(run1.misses, 5)

        // Redo — the edit lands: the gain identity flips its hash. The
        // walk probes TOP-DOWN and short-circuits on the FIRST hit, so a
        // run records at most ONE hit: colorout+gamma MISS, the gain line
        // MISSES, and colorin's line HITs (its key is untouched) — the
        // recursion stops there and the input plane is never even probed
        // (SC#2 upstream survival).
        stack.redo()
        let run2 = try await run(stack.effectiveInstances())
        XCTAssertEqual(run2.hits, 1, "colorin's line keys are untouched by the edit")
        XCTAssertEqual(run2.misses, 3, "gain onward re-renders")

        // Undo again (the acceptance case): the reverted chain's TOP line
        // (gamma) still carries its run-1 key → immediate hit, zero work
        // anywhere above it (the whole pre-edit chain is intact).
        _ = stack.undo()
        let run3 = try await run(stack.effectiveInstances())
        XCTAssertEqual(run3.hits, 1, "the reverted top-of-chain line is still cached")
        XCTAssertEqual(run3.misses, 0)

        // Identity discipline: the gain box was reused IN PLACE across all
        // three materializations (same object, not re-manufactured).
        XCTAssertEqual(knownBoxes.count, 4, "one box per instance UUID")
        XCTAssertEqual(knownBoxes[gainBefore.id]!.instanceID, gainBefore.id)
    }

    /// The box's apply fast-path: byte-identical params keep the committed
    /// piece untouched (paramsHash stable → cache keys stable).
    func testApplyWithIdenticalBytesIsAStableNoOp() async throws {
        let registry = await makeRegistry()
        let record = makeGain(1.5)
        guard let box = await registry.makeBox(opName: record.opName, instanceID: record.id) else {
            return XCTFail("testgain must be registered")
        }
        try await box.apply(record)
        let hashAfterFirst = box.paramsHash
        XCTAssertEqual(hashAfterFirst, record.paramsHash)
        XCTAssertEqual(box.enabled, true)

        // Identical bytes → no-op; enabled sync still flows through.
        try await box.apply(record)
        XCTAssertEqual(box.paramsHash, hashAfterFirst)

        var disabled = record
        disabled.enabled = false
        try await box.apply(disabled)
        XCTAssertEqual(box.enabled, false, "enabled syncs even on the fast path")
        XCTAssertEqual(box.paramsHash, hashAfterFirst, "params untouched")
    }
}
