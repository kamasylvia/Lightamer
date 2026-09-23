import Foundation
import os

/// `opName → module factory` — the module registry (Plan 02-04-01; the
/// COLOR-04/Phase-3 extension point). TWO consumers:
/// 1. **Default-chain assembly** — `makeDefaultChain()` returns the
///    terminal trio `[colorin, colorout, gamma]` in v50 order; the app
///    builds one registry at launch and hands its chain to the pipe
///    coordinator.
/// 2. **Sidecar params decode** (Plan 02-06) — `makeBox(opName:)` returns
///    nil for an UNKNOWN op; the sidecar's degrade policy consumes that
///    (keep `paramsData` verbatim, disable the instance, toast — never
///    drop user data).
///
/// LightamerCore hosts the terminal trio (pipeline infrastructure — the
/// pipe + golden harness run with ZERO LightamerIOP dependency, research
/// Open Question #2 resolution); LightamerIOP registers its modules via
/// `LightamerIOPRegistry.populate(_:)` at app launch, and Phase 3+ joins
/// the same hook.
///
/// **Actor (D-33 unified isolation, checker fix):** the registry's only
/// mutable state is the factory dictionary; actor isolation matches every
/// other registry/cache object in Core (`PipeCache`, `MetalContext`,
/// `RAWDecoder`). Factories are `@Sendable` closures over metatypes only —
/// module INSTANCES are owned per box/pipe run, never shared.
public actor ModuleRegistry {

    /// `@Sendable (UUID) -> any ModuleBoxing`: builds a FRESH box wrapping
    /// a fresh module instance under the given (persisted) instance UUID.
    private var factories: [String: @Sendable (UUID) -> any ModuleBoxing] = [:]

    /// Signpost/log channel (registry churn is a launch-time + sidecar-time
    /// event; debug-level).
    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "registry"
    )

    // MARK: - Lifecycle

    /// Self-registers the terminal trio (colorin 28.0 / colorout 70.0 /
    /// gamma 78.0 — the v50 default chain). `passthrough_spike`/`testgain`
    /// are NOT part of the default chain (dev-only modules register
    /// explicitly — tests / `LightamerIOPRegistry.populate`).
    ///
    /// Direct dictionary mutation (NOT `register(_:)`): an actor init can
    /// touch its own storage but cannot hop into isolated methods.
    public init() {
        factories[ColorInModule.opName] = { id in
            ModuleBox(module: ColorInModule(), instanceID: id)
        }
        factories[ColorOutModule.opName] = { id in
            ModuleBox(module: ColorOutModule(), instanceID: id)
        }
        factories[GammaModule.opName] = { id in
            ModuleBox(module: GammaModule(), instanceID: id)
        }
    }

    /// Convenience: a registry with just the terminal trio registered.
    public static func makeDefault() -> ModuleRegistry {
        ModuleRegistry()
    }

    // MARK: - Registration + manufacture

    /// Register a module factory under `opName`. IDEMPOTENT per opName —
    /// last-wins with a debug log (re-registration is the Phase 3
    /// populate-hook pattern; a silent overwrite would hide a typo'd op).
    public func register(
        opName: String,
        factory: @escaping @Sendable (UUID) -> any ModuleBoxing
    ) {
        if factories[opName] != nil {
            Self.logger.debug(
                "ModuleRegistry: re-registering op '\(opName, privacy: .public)' (last-wins)"
            )
        }
        factories[opName] = factory
    }

    /// Manufacture a box for `opName` under `instanceID` — nil for an
    /// UNREGISTERED op (02-06's unknown-op degrade path consumes this:
    /// params kept verbatim, instance disabled, toast).
    public func makeBox(
        opName: String,
        instanceID: UUID = UUID()
    ) -> (any ModuleBoxing)? {
        factories[opName]?(instanceID)
    }

    /// The v50 default chain — the terminal trio `[colorin, colorout,
    /// gamma]` sorted by `iopOrder` (28.0 < 70.0 < 78.0). Fresh instances
    /// per call (boxes are single-owner). Params are UNCOMMITTED
    /// (paramsHash 0); the coordinator/tests commit defaults via
    /// `ModuleBox.setParams` when they adopt the chain.
    public func makeDefaultChain() -> [any ModuleBoxing] {
        [
            makeBox(opName: ColorInModule.opName),
            makeBox(opName: ColorOutModule.opName),
            makeBox(opName: GammaModule.opName),
        ]
        .compactMap { $0 }
        .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }

    /// The pristine instance RECORDS for the default chain (Plan 02-05-05)
    /// — the same terminal trio as `makeDefaultChain()` as `ModuleInstance`
    /// values with DEFAULT params canonically committed through the typed
    /// initializer (real `paramsData` + `paramsHash`, fresh UUIDs).
    ///
    /// EditorState seeds its live instance set with these on a fresh image
    /// load; the coordinator then MATERIALIZES boxes FROM the records
    /// (`makeBox(opName:instanceID:)` preserves the record UUIDs), so the
    /// records — not the boxes — are the identity anchor from day one.
    /// MUST stay in parity with the trio registered in `init()`.
    public func makeDefaultInstances() -> [ModuleInstance] {
        [
            ModuleInstance(module: ColorInModule.self, params: ColorInModule.Params()),
            ModuleInstance(module: ColorOutModule.self, params: ColorOutModule.Params()),
            ModuleInstance(module: GammaModule.self, params: GammaModule.Params()),
        ]
        .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }

    // MARK: - Layer chains (Plan 06-01 T2)

    /// The effective instance set for an adjustment layer's chain (Plan
    /// 06-01 T2): the same `(opName, multiPriority)` dedup + v50 sort the
    /// global history projection applies — layer-internal semantics stay
    /// identical to the global chain (mixed model (c): a layer chain IS a
    /// pipe run's piece array).
    public func effectiveInstances(layer: AdjustmentLayer) -> [ModuleInstance] {
        HistoryStack.effectiveChain(layer.chain)
    }

    /// Materialize boxes for a record chain — the sub-run lifecycle seam
    /// the `LayerCompositeDriver` consumes (records → boxes per run).
    /// Unknown ops yield NOTHING (02-06 degrade shape: the record survives
    /// in the layer, the box simply doesn't exist — the driver skips it);
    /// a params decode failure likewise drops the box, never the record.
    /// Boxes are applied from their records (`apply` preserves identity +
    /// commits params) so the sub-run's hash chain keys on the record
    /// bytes.
    public func materializeBoxes(
        for records: [ModuleInstance]
    ) async -> (boxes: [any ModuleBoxing], skippedUnknownOps: [String]) {
        var boxes: [any ModuleBoxing] = []
        boxes.reserveCapacity(records.count)
        var unknown: [String] = []
        var seenUnknown = Set<String>()
        for record in HistoryStack.effectiveChain(records) {
            guard let box = makeBox(opName: record.opName, instanceID: record.id) else {
                if seenUnknown.insert(record.opName).inserted {
                    unknown.append(record.opName)
                }
                continue
            }
            do {
                try box.apply(record)
                boxes.append(box)
            } catch {
                // Params decode failure = same degrade as unknown op.
                if seenUnknown.insert(record.opName).inserted {
                    unknown.append(record.opName)
                }
            }
        }
        return (boxes, unknown)
    }
}
