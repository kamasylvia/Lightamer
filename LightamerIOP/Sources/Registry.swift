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
        // Plan 03-03-T3: tonecurve (L/a/b curves, 10001-point LUTs),
        // Lab-domain, v50 slot 48.0.
        await registry.register(opName: ToneCurveModule.opName) { id in
            ModuleBox(module: ToneCurveModule(), instanceID: id)
        }
        // Plan 03-03-T4: levels (black/gray/white points, Lab-domain),
        // v50 slot 49.0 (automatic mode wired by T5's HistogramReduce).
        await registry.register(opName: LevelsModule.opName) { id in
            ModuleBox(module: LevelsModule(), instanceID: id)
        }
        // Plan 03-04-T4: sigmoid (scene-referred log-logistic tone mapping),
        // v50 slot 45.3 — the D-T2 scene-referred baseline (filmicrgb's
        // risk buffer, plan 03-06's template).
        await registry.register(opName: SigmoidModule.opName) { id in
            ModuleBox(module: SigmoidModule(), instanceID: id)
        }
        // Plan 03-04-T2: shadhi (shadows & highlights, Lab-domain gaussian
        // leg), v50 slot 50.0 — Phase 3's first neighborhood-op module
        // (Common/GaussianBlur consumer; bilateral leg = Phase 5).
        await registry.register(opName: ShadhiModule.opName) { id in
            ModuleBox(module: ShadhiModule(), instanceID: id)
        }
        // Plan 03-05-T4: toneequal (tone equalizer, global multi-band +
        // EIGF detail leg + correction LUT), v50 slot 24.0 — Phase 3's
        // heaviest module and the TilingPlan FULL first engagement.
        await registry.register(opName: ToneEqualModule.opName) { id in
            ModuleBox(module: ToneEqualModule(), instanceID: id)
        }
        // Plan 03-06-T5: filmicrgb (scene-referred filmic view transform,
        // V5 colorscience + Yrg gamut mapping), v50 slot 46.0 — the
        // ROADMAP's hardest single port (IOP-FILM-01, F0-F4 sub-stages).
        await registry.register(opName: FilmicRGBModule.opName) { id in
            ModuleBox(module: FilmicRGBModule(), instanceID: id)
        }
        // Plan 03-06-T6: agx (the Blender AgX-inspired filmic VARIANT,
        // sigmoid-trapezoid curve + primaries adjustments), v50 slot 45.5
        // (IOP-FILM-03; hatchless = no dt counterpart, not implemented).
        await registry.register(opName: AgXModule.opName) { id in
            ModuleBox(module: AgXModule(), instanceID: id)
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

    /// The kernel function names the editing chain dispatches (Plan
    /// 03-06-T7's PSO startup pre-warm list — the terminal trio + every
    /// registered tone iop's kernels; the PSO cache dedupes).
    public static var prewarmFunctionNames: [String] {
        [
            TerminalKernels.copy,
            // NOTE: colorout_matrix carries the isP3 function constant
            // (no MSL default) — a generic nil-constants PSO build aborts
            // in Metal validation; the display-profile PSO warms on the
            // first render instead.
            TerminalKernels.gammaEncode,
            TemperatureKernel.functionName,
            ExposureKernel.functionName,
            ColisaKernel.functionName,
            ToneCurveKernel.functionName,
            LevelsKernel.functionName,
            ShadhiKernel.prepFunction,
            ShadhiKernel.mixFunction,
            ToneEqualKernel.lumaEstimateFunction,
            ToneEqualKernel.applyFunction,
            SigmoidKernel.perChannelFunction,
            SigmoidKernel.rgbRatioFunction,
            FilmicRGBKernel.v5Function,
            AgXKernel.mainFunction,
        ]
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
            ModuleInstance(module: SigmoidModule.self, params: SigmoidModule.Params()),
            ModuleInstance(module: ColisaModule.self, params: ColisaModule.Params()),
            ModuleInstance(module: ToneCurveModule.self, params: ToneCurveModule.Params()),
            ModuleInstance(module: LevelsModule.self, params: LevelsModule.Params()),
            ModuleInstance(module: ShadhiModule.self, params: ShadhiModule.Params()),
            ModuleInstance(module: ToneEqualModule.self, params: ToneEqualModule.Params()),
            ModuleInstance(module: FilmicRGBModule.self, params: FilmicRGBModule.Params()),
            ModuleInstance(module: AgXModule.self, params: AgXModule.Params()),
        ]
        .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }
}
