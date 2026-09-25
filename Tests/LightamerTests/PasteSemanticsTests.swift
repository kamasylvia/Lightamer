import Foundation
import LightamerCore
import LightamerIOP
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 09-04 T1/T2 — PastePayload (copy + skip set, D-09-CONTEXT-5) and
// PasteSemantics (overwrite / merge / partial + live protection + per-image
// undo) suites.
//
// T1 (copy 段): the skip-set truth table (decode domain < 28.0 excluded /
// identity defaults excluded / creative domain kept / multi-instances kept),
// the payload Codable byte round-trip, and the partial-selection filter.
// T2 (paste 段): the three paste modes against composed HistoryStacks, the
// reverse assertions (overwrite == payload EXACTLY; merge latest-wins),
// the UUID recast, and the single-⌘Z restore.
//
// Pure-value tests — no Metal, no decode, no I/O (the lazy-render red line
// starts at the data layer).
// ─────────────────────────────────────────────────────────────────────────────

final class PasteSemanticsTests: XCTestCase {

    // MARK: - Fixtures

    /// The identity-default seed (terminal trio + the editing defaults) —
    /// exactly what the coordinator hands `PastePayload.compose`.
    private func makeSeed() async -> [ModuleInstance] {
        (
            await ModuleRegistry.makeDefault().makeDefaultInstances()
                + LightamerIOPRegistry.editingDefaultInstances()
        )
        .sorted {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }
    }

    private func sourceID() -> UUID { UUID(uuidString: "09040904-0904-0904-0904-090409040904")! }

    // MARK: - T1: the skip-set truth table

    func testCopySkipsDecodeDomainInstances() async throws {
        let seed = await makeSeed()
        // temperature (3.0) + lens (13.0) live strictly below the ashift
        // 15.0 boundary — EVEN modified they never cross images (废片 risk,
        // D-09-CONTEXT-5; boundary resolution in 09-04-DECISIONS).
        let hotTemperature = ModuleInstance(
            module: TemperatureModule.self,
            params: TemperatureModule.Params(gains: SIMD3<Float>(1.2, 1.0, 0.8)))
        let warpedLens = ModuleInstance(
            module: LensModule.self, params: LensModule.Params(distortionK1: 0.05))
        let payload = PastePayload.compose(
            sourceImageID: sourceID(), sourceURL: nil,
            sourceInstances: [hotTemperature, warpedLens],
            sourceEffective: [hotTemperature, warpedLens],
            seed: seed, layerStack: nil)
        XCTAssertTrue(
            payload.instances.isEmpty,
            "decode-domain instances are excluded even when modified")
    }

    func testCopyKeepsTheSceneReferredCreativeBand() async throws {
        let seed = await makeSeed()
        // The 15.0..28.0 band (ashift/exposure/toneequal/crop) is CREATIVE
        // territory in the verbatim v50 table — the copy-paste payload core.
        // A literal "< colorin 28.0" would forbid these (see DECISIONS).
        let pushedExposure = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params(exposure: 1.5))
        let payload = PastePayload.compose(
            sourceImageID: sourceID(), sourceURL: nil,
            sourceInstances: [pushedExposure],
            sourceEffective: [pushedExposure],
            seed: seed, layerStack: nil)
        XCTAssertEqual(
            payload.instances.map(\.opName), [ExposureModule.opName],
            "exposure (21.0) copies — the scene-referred creative band stays copyable")
    }

    func testCopyKeepsAshiftAtTheBoundaryWhenModified() async throws {
        let seed = await makeSeed()
        // ashift sits AT 15.0 — not below the boundary. A record the seed
        // table does not own ((ashift, 1)) is not identity either → kept.
        let straightened = ModuleInstance(
            module: AshiftModule.self, multiPriority: 1, multiName: "pinned",
            params: AshiftModule.Params())
        let payload = PastePayload.compose(
            sourceImageID: sourceID(), sourceURL: nil,
            sourceInstances: [straightened], sourceEffective: [straightened],
            seed: seed, layerStack: nil)
        XCTAssertEqual(
            payload.instances.map(\.opName), [AshiftModule.opName],
            "the boundary is strict `< 15.0`: ashift itself is copyable when the tuple is not a seed twin")
    }

    func testCopyExcludesIdentityDefaultsButKeepsModified() async throws {
        let seed = await makeSeed()
        // exposure at DEFAULT params = identity → excluded.
        let defaultExposure = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params())
        // exposure at +1.5EV = a real edit → kept.
        let pushedExposure = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params(exposure: 1.5))
        // A DISABLED seed twin (colorbalancergb ships disabled) at defaults → excluded.
        let defaultCBRGB = ModuleInstance(
            module: ColorBalanceRGBModule.self, params: ColorBalanceRGBModule.Params(),
            enabled: false)
        // A renamed-but-unmodified instance stays excluded (dt compares
        // params, not multi_name).
        var renamed = defaultExposure
        renamed.multiName = "relabeled"
        let payload = PastePayload.compose(
            sourceImageID: sourceID(), sourceURL: nil,
            sourceInstances: [defaultExposure, pushedExposure, defaultCBRGB, renamed],
            sourceEffective: [defaultExposure, pushedExposure, defaultCBRGB, renamed],
            seed: seed, layerStack: nil)
        XCTAssertEqual(
            payload.instances.map(\.opName), [ExposureModule.opName],
            "identity defaults are excluded; the modified instance survives")
        XCTAssertEqual(
            payload.instances.first?.paramsHash, pushedExposure.paramsHash,
            "the kept record is the +1.5EV edit, byte-identical params")
    }

    func testCopyKeepsCreativeDomainAndTerminalTail() async throws {
        let seed = await makeSeed()
        // borders (≥70.0 terminal tail) + sharpen (35.0, creative domain) are
        // copyable; that is the D-09-CONTEXT-5 ④ rule (yiyin 印框/水印随队).
        let sharpen = ModuleInstance(
            module: SharpenModule.self, params: SharpenModule.Params(amount: 0.8))
        let borders = ModuleInstance(
            module: BordersModule.self, multiName: "frame", params: BordersModule.Params())
        let payload = PastePayload.compose(
            sourceImageID: sourceID(), sourceURL: nil,
            sourceInstances: [sharpen, borders],
            sourceEffective: [sharpen, borders],
            seed: seed, layerStack: nil)
        XCTAssertEqual(
            Set(payload.instances.map(\.opName)),
            [SharpenModule.opName, BordersModule.opName],
            "creative + terminal-tail instances copy")
    }

    func testCopyKeepsEveryMultiInstance() async throws {
        let seed = await makeSeed()
        // Two exposure instances (multiPriority 0 + 1) — both modified, both
        // survive (the tuple identity is (opName, multiPriority, multiName)).
        let first = ModuleInstance(
            module: ExposureModule.self, multiPriority: 0,
            params: ExposureModule.Params(exposure: 0.5))
        let second = ModuleInstance(
            module: ExposureModule.self, multiPriority: 1, multiName: "push",
            params: ExposureModule.Params(exposure: 2.0))
        let payload = PastePayload.compose(
            sourceImageID: sourceID(), sourceURL: nil,
            sourceInstances: [first, second],
            sourceEffective: [first, second],
            seed: seed, layerStack: nil)
        XCTAssertEqual(payload.instances.count, 2, "every modified multi-instance copies")
        XCTAssertEqual(
            Set(payload.instances.map(\.multiPriority)), [0, 1],
            "the multi-priority ordinals ride along")
    }

    func testCopyProjectsOnlyTheEffectiveChain() async throws {
        let seed = await makeSeed()
        // The source's live set carries base records the history does not own
        // (the pristine seed) — the copy must project ONLY the effective chain.
        let pushedExposure = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params(exposure: 1.0))
        let liveSet = seed + [pushedExposure]
        let payload = PastePayload.compose(
            sourceImageID: sourceID(), sourceURL: nil,
            sourceInstances: liveSet,
            sourceEffective: [pushedExposure],
            seed: seed, layerStack: nil)
        XCTAssertEqual(
            payload.instances.map(\.opName), [ExposureModule.opName],
            "the payload freezes the effective set, never the raw base+effective union")
    }

    // MARK: - T1: Codable byte round-trip

    func testPayloadCodableRoundTripIsByteIdentical() async throws {
        let pushedExposure = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params(exposure: 1.5))
        let borders = ModuleInstance(
            module: BordersModule.self, multiName: "frame", params: BordersModule.Params())
        let payload = PastePayload(
            sourceImageID: sourceID(),
            sourceURL: URL(fileURLWithPath: "/tmp/src.ARW"),
            instances: [pushedExposure, borders],
            layerStack: nil,
            copiedAt: Date(timeIntervalSince1970: 1_770_000_000),
            appVersion: "0.9.4")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let first = try encoder.encode(payload)
        let decoded = try JSONDecoder().decode(PastePayload.self, from: first)
        let second = try encoder.encode(decoded)
        XCTAssertEqual(first, second, "encode→decode→encode is byte-identical (sortedKeys determinism)")
        XCTAssertEqual(decoded, payload, "value equality survives the round trip")
        // The instance records round-trip byte-exactly (paramsData is the
        // authoritative payload — the D-H4 atoms must not drift).
        XCTAssertEqual(
            decoded.instances.map(\.paramsData), payload.instances.map(\.paramsData))
        XCTAssertEqual(
            decoded.instances.map(\.paramsHash), payload.instances.map(\.paramsHash))
    }

    // MARK: - T1: partial-selection filter

    func testPartialSelectionFiltersToCheckedKeys() async throws {
        let first = ModuleInstance(
            module: ExposureModule.self, multiPriority: 0,
            params: ExposureModule.Params(exposure: 0.5))
        let second = ModuleInstance(
            module: ExposureModule.self, multiPriority: 1, multiName: "push",
            params: ExposureModule.Params(exposure: 2.0))
        let sharpen = ModuleInstance(
            module: SharpenModule.self, params: SharpenModule.Params(amount: 0.8))
        let payload = PastePayload(
            sourceImageID: sourceID(), sourceURL: nil,
            instances: [first, second, sharpen], layerStack: nil)

        let selection: Set<PastePayload.InstanceKey> = [
            PastePayload.InstanceKey(second), PastePayload.InstanceKey(sharpen),
        ]
        let filtered = payload.filtered(by: selection)
        XCTAssertEqual(
            filtered.instances.map(\.id), [second.id, sharpen.id],
            "the checked subset lands exactly (order + records preserved)")
        XCTAssertEqual(filtered.instances.count, 2, "unchecked instances are dropped")
        XCTAssertTrue(payload.filtered(by: []).instances.isEmpty, "an empty selection yields an empty payload")
    }
}

// MARK: - T2: the paste modes (pure Core semantics)

extension PasteSemanticsTests {

    /// A target with a REAL edit history: exposure +1EV + testgain 2.0
    /// (two commits) over the seed.
    private func makeEditedTarget() async -> (history: HistoryStack, instances: [ModuleInstance], seed: [ModuleInstance], oldExposure: ModuleInstance, oldGain: ModuleInstance) {
        let seed = await makeSeed()
        var history = HistoryStack()
        let exposure = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params(exposure: 1.0))
        let gain = ModuleInstance(
            module: TestGainModule.self, params: TestGainModule.Params(gain: 2.0))
        history.commit(exposure, label: "exposure +1")
        history.commit(gain, label: "testgain 2x")
        let live = PasteSemanticsTests.liveSet(seed: seed, history: history)
        return (history, live, seed, exposure, gain)
    }

    /// base ∪ effective (the EditorState.rebuildInstances / sidecar doc rule).
    private static func liveSet(seed: [ModuleInstance], history: HistoryStack) -> [ModuleInstance] {
        let effective = history.effectiveInstances()
        var merged = seed
        for record in effective
        where !merged.contains(where: {
            $0.opName == record.opName && $0.multiPriority == record.multiPriority
        }) {
            merged.append(record)
        }
        return merged.sorted {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }
    }

    /// A payload frozen from a "source" whose edits are exposure +2EV and
    /// borders (the creative pair; the skip set cut the rest).
    private func makePayload() -> PastePayload {
        let exposure = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params(exposure: 2.0))
        let borders = ModuleInstance(
            module: BordersModule.self, multiName: "frame", params: BordersModule.Params())
        return PastePayload(
            sourceImageID: sourceID(), sourceURL: nil,
            instances: [exposure, borders], layerStack: nil)
    }

    func testOverwriteReplacesEffectiveSetExactlyWithPayload() async throws {
        let target = await makeEditedTarget()
        let payload = makePayload()
        let composed = try XCTUnwrap(PasteSemantics.paste(
            targetHistory: target.history, targetInstances: target.instances,
            payload: payload, mode: .overwrite, seed: target.seed))
        // REVERSE ASSERTION (防空转): the effective set == the payload
        // EXACTLY — the target's old edits (testgain) are GONE (a non-
        // superset is the whole point of overwrite, dt DELETE+INSERT).
        let effective = composed.history.effectiveInstances()
        func key(_ r: ModuleInstance) -> String {
            "\(r.opName)|\(r.multiPriority)|\(r.paramsHash)"
        }
        XCTAssertEqual(
            Set(effective.map(key)),
            Set(payload.instances.map(key)),
            "overwrite: the effective set is the payload EXACTLY, never a superset")
        // ONE NEW commit (the undo contract) — an epoch item; the older
        // items stay in the stack as dead state for the ⌘Z restore.
        XCTAssertEqual(composed.history.items.count, target.history.items.count + 1)
        XCTAssertEqual(composed.history.position, target.history.position + 1)
        // instances = 默认种子 + 载荷实例: every seed record present
        // (payload twins shadow), no target edits left in the live set.
        let live = composed.instances
        for seedRecord in target.seed {
            XCTAssertTrue(
                live.contains(where: {
                    $0.opName == seedRecord.opName && $0.multiPriority == seedRecord.multiPriority
                }),
                "the seed record \(seedRecord.opName) survives overwrite in the base/live set")
        }
        XCTAssertFalse(
            live.contains(where: { $0.opName == TestGainModule.opName }),
            "the target's own edit is gone from the live set")
    }

    func testOverwriteSingleUndoRestoresByteExactly() async throws {
        let target = await makeEditedTarget()
        let payload = makePayload()
        let composed = try XCTUnwrap(PasteSemantics.paste(
            targetHistory: target.history, targetInstances: target.instances,
            payload: payload, mode: .overwrite, seed: target.seed))

        // ONE ⌘Z: position drops below the epoch item → the OLD projection.
        var undoStack = composed.history
        undoStack.undo()
        let undone = undoStack.effectiveInstances()
        let oldEffective = target.history.effectiveInstances()
        XCTAssertEqual(
            undone.map { "\($0.opName)|\($0.multiPriority)|\($0.paramsData.count)|\($0.paramsHash)" },
            oldEffective.map { "\($0.opName)|\($0.multiPriority)|\($0.paramsData.count)|\($0.paramsHash)" },
            "one ⌘Z restores the pre-paste effective set BYTE-EXACTLY")
        // Redo forward: the payload projection returns.
        undoStack.redo()
        XCTAssertEqual(
            undoStack.effectiveInstances().map(\.paramsHash),
            payload.instances.map(\.paramsHash))
    }

    func testMergeKeepsTargetInstancesAndPayloadWinsSameTuple() async throws {
        let target = await makeEditedTarget()
        let payload = makePayload()
        let composed = try XCTUnwrap(PasteSemantics.paste(
            targetHistory: target.history, targetInstances: target.instances,
            payload: payload, mode: .merge, seed: target.seed))

        let effective = composed.history.effectiveInstances()
        // Same-tuple (exposure, 0): the PAYLOAD's +2EV wins (latest-wins).
        let exposure = effective.first { $0.opName == ExposureModule.opName }
        XCTAssertEqual(
            exposure?.paramsHash,
            payload.instances.first { $0.opName == ExposureModule.opName }?.paramsHash,
            "merge: the pasted (newest) record wins the shared tuple")
        // 异名共存: the target's OWN testgain survives; borders lands too.
        XCTAssertEqual(
            effective.first { $0.opName == TestGainModule.opName }?.paramsHash,
            target.oldGain.paramsHash,
            "merge: the target's own edit coexists")
        XCTAssertNotNil(effective.first { $0.opName == BordersModule.opName })
        // ONE paste commit on top of the untouched stack.
        XCTAssertEqual(
            composed.history.items.count, target.history.items.count + 1)
        XCTAssertEqual(composed.history.position, target.history.position + 1)
        // ONE ⌘Z → byte-exact pre-paste projection.
        var mergeUndo = composed.history
        mergeUndo.undo()
        XCTAssertEqual(
            mergeUndo.effectiveInstances().map { "\($0.opName)|\($0.multiPriority)|\($0.paramsHash)" },
            target.history.effectiveInstances().map { "\($0.opName)|\($0.multiPriority)|\($0.paramsHash)" },
            "merge: one ⌘Z restores the pre-paste set byte-exactly")
    }

    func testPartialPasteLandsOnlyTheCheckedSubset() async throws {
        let target = await makeEditedTarget()
        let payload = makePayload()
        let selection: Set<PastePayload.InstanceKey> = [
            PastePayload.InstanceKey(payload.instances[0]) // exposure only
        ]
        let composed = try XCTUnwrap(PasteSemantics.paste(
            targetHistory: target.history, targetInstances: target.instances,
            payload: payload, mode: .merge, seed: target.seed, selection: selection))
        let effective = composed.history.effectiveInstances()
        XCTAssertNotNil(effective.first { $0.opName == ExposureModule.opName })
        XCTAssertNil(
            effective.first { $0.opName == BordersModule.opName },
            "partial: the unchecked instance never lands")
    }

    func testPasteRecastsUUIDsButKeepsSemantics() async throws {
        let target = await makeEditedTarget()
        let payload = makePayload()
        let first = try XCTUnwrap(PasteSemantics.paste(
            targetHistory: target.history, targetInstances: target.instances,
            payload: payload, mode: .overwrite, seed: target.seed))
        let second = try XCTUnwrap(PasteSemantics.paste(
            targetHistory: target.history, targetInstances: target.instances,
            payload: payload, mode: .overwrite, seed: target.seed))
        // Different UUIDs per paste (cross-image namespaces stay separate).
        XCTAssertNotEqual(
            Set(first.pastedRecords.map(\.id)),
            Set(second.pastedRecords.map(\.id)),
            "each paste RECASTS the payload UUIDs")
        // Identical semantics (tuple + params bytes).
        XCTAssertEqual(
            first.pastedRecords.map { "\($0.opName)|\($0.multiPriority)|\($0.multiName)|\($0.paramsHash)" },
            second.pastedRecords.map { "\($0.opName)|\($0.multiPriority)|\($0.multiName)|\($0.paramsHash)" })
    }

    func testPasteCommitRoundTripsThroughTheSidecarSpelling() async throws {
        let target = await makeEditedTarget()
        let payload = makePayload()
        let composed = try XCTUnwrap(PasteSemantics.paste(
            targetHistory: target.history, targetInstances: target.instances,
            payload: payload, mode: .merge, seed: target.seed))

        // The sidecar spelling (decimal-String hashes) round-trips the
        // paste item — the additive pasteSet field survives both ways.
        let decoderVersion = "v8"
        let decodeHash = UInt64(12345678901234567)
        let hash = HistoryHash.hash(
            stack: composed.history, decodeParamsHash: decodeHash,
            layerSnapshot: composed.layerStack?.snapshot)
        let document = LightamerSidecar(
            imageID: sourceID(), decoderVersionUsed: decoderVersion,
            decodeParamsHash: decodeHash, instances: composed.instances,
            history: composed.history, historyHash: hash)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(document)
        let restored = try JSONDecoder().decode(LightamerSidecar.self, from: bytes)
        XCTAssertFalse(restored.driftDetected, "the pasted doc is self-consistent (no drift)")
        XCTAssertEqual(restored.history.items.count, composed.history.items.count)
        XCTAssertEqual(
            restored.history.effectiveInstances().map { "\($0.opName)|\($0.multiPriority)|\($0.paramsHash)" },
            composed.history.effectiveInstances().map { "\($0.opName)|\($0.multiPriority)|\($0.paramsHash)" },
            "the effective set survives the sidecar round-trip byte-exactly")
        let pasteItem = restored.history.items.last
        XCTAssertEqual(pasteItem?.pasteSet?.count, payload.instances.count,
                       "the pasteSet rides the additive sidecar field")
    }

    @MainActor
    func testEditorStructureMarkerMirrorMatches() {
        // The Core-side mirror must equal EditorState's canonical marker
        // (the layer restore path matches BOTH markers).
        XCTAssertEqual(
            EditorStructureScope.marker, EditorState.layerStructureScope,
            "the Core mirror of the layer-structure marker drifted from the App canonical")
    }
}
