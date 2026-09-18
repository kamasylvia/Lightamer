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
        #if DEBUG
        await registry.register(opName: TestGainModule.opName) { id in
            ModuleBox(module: TestGainModule(), instanceID: id)
        }
        #endif
        // Phase 3+: exposure, WB, filmic, … register here.
        // `passthrough_spike` stays test-only (Phase 1 spike module — it
        // never enters app chains, so it is deliberately unregistered).
    }
}
