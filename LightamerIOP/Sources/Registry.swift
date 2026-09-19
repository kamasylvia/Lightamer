import LightamerCore

/// LightamerIOP's registration hook (Plan 02-04-01) — the ONE place the app
/// touches to make this framework's modules pipe-addressable. Phase 3+ tone
/// modules register here (each `public final class XXXModule: IOPModule`
/// gets one line, mirroring the API.md "adding a module" rule).
///
/// The app calls this at launch right after building `ModuleRegistry
/// .makeDefault()` (LightamerApp `.task`): `await LightamerIOPRegistry
/// .populate(registry)`. `populate` is async because the registry is an
/// actor (D-33 unified) — the plan's synchronous signature is realized as
/// async for the same isolation discipline (recorded plan note).
///
/// `testgain` is DEBUG-only (`#if DEBUG` — the module type itself is
/// compiled out of Release): a Release sidecar containing a `testgain` op
/// reads it back as an UNKNOWN op and degrades per 02-06 (the exact
/// scenario the dev-only module exists to exercise).
public enum LightamerIOPRegistry {

    /// Register every LightamerIOP module into `registry`.
    public static func populate(_ registry: ModuleRegistry) async {
        // Phase 3's first real iop (Plan 03-01-T5): exposure, v50 slot 21.0.
        await registry.register(opName: ExposureModule.opName) { id in
            ModuleBox(module: ExposureModule(), instanceID: id)
        }
        // Plan 03-02-T2: WB temperature, v50 slot 3.0 (post-CIRAW correction
        // layer — slot semantics divergence documented on the module).
        await registry.register(opName: TemperatureModule.opName) { id in
            ModuleBox(module: TemperatureModule(), instanceID: id)
        }
        // Plan 03-03-T2: colisa (contrast/brightness/saturation), Lab-domain,
        // v50 slot 47.0 — first LabRoundTrip consumer.
        await registry.register(opName: ColisaModule.opName) { id in
            ModuleBox(module: ColisaModule(), instanceID: id)
        }
        #if DEBUG
        await registry.register(opName: TestGainModule.opName) { id in
            ModuleBox(module: TestGainModule(), instanceID: id)
        }
        #endif
        // Phase 3+: tonecurve, filmic, … register here.
        // `passthrough_spike` stays test-only (Phase 1 spike module — it
        // never enters app chains, so it is deliberately unregistered).
    }

    /// The pristine EDITING seed beyond the terminal trio (Plan 03-02-T4):
    /// the tone iops that ship permanent Inspector panels join a freshly
    /// loaded image at IDENTITY params, so their panels have instances to
    /// drive (D-T6's "ModuleRegistry-driven panel generation"). Identity
    /// params keep the default chain cache-neutral (byte-identical hashes).
    /// Composed by `PipeCoordinator.load` after
    /// `ModuleRegistry.makeDefaultInstances()`.
    public static func editingDefaultInstances() -> [ModuleInstance] {
        [
            ModuleInstance(module: TemperatureModule.self, params: TemperatureModule.Params()),
            ModuleInstance(module: ExposureModule.self, params: ExposureModule.Params()),
            ModuleInstance(module: ColisaModule.self, params: ColisaModule.Params()),
        ]
        .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }
}
