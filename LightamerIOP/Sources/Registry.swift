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
        // Plan 04-04-T1: lens (manual warp + Lensfun XML resolve), v50
        // slot 13.0 — AFTER scalepixels (12.0), BEFORE cacorrectrgb (13.5,
        // whose source comment orders CA-after-lens).
        await registry.register(opName: LensModule.opName) { id in
            ModuleBox(module: LensModule(), instanceID: id)
        }
        // Plan 04-03-T2: ashift (rotate/perspective single-homography warp),
        // v50 slot 15.0 — BEFORE flip (16.0) per iop_order.c:319-320.
        await registry.register(opName: AshiftModule.opName) { id in
            ModuleBox(module: AshiftModule(), instanceID: id)
        }
        // Plan 04-02-T2: flip (orientation index remap), v50 slot 16.0 —
        // AFTER ashift (15.0), BEFORE crop (24.5) per iop_order.c:810-812.
        await registry.register(opName: FlipModule.opName) { id in
            ModuleBox(module: FlipModule(), instanceID: id)
        }
        // Plan 04-02-T1: crop (framing window, blit copy — no kernel),
        // v50 slot 24.5 — after toneequal (24.0, last roi_in widener).
        await registry.register(opName: CropModule.opName) { id in
            ModuleBox(module: CropModule(), instanceID: id)
        }
        // Plan 04-05-T4: equalizer (gaussian half-octave pyramid +
        // per-band gains), v50 slot 27.0 — after profile_gamma (26.0),
        // before colorin (28.0).
        await registry.register(opName: EqualizerModule.opName) { id in
            ModuleBox(module: EqualizerModule(), instanceID: id)
        }
        // Plan 04-05-T3: highpass (Lab inverted highpass), v50 slot 34.0 —
        // after lowpass (33.0), before sharpen (35.0).
        await registry.register(opName: HighpassModule.opName) { id in
            ModuleBox(module: HighpassModule(), instanceID: id)
        }
        // Plan 04-05-T1: sharpen (USM: IIR + soft-threshold mix), v50 slot
        // 35.0 — after highpass (34.0), before colortransfer (37.0). D-G5
        // backward-expansion prover (replaces the ROINegotiationTests stub).
        await registry.register(opName: SharpenModule.opName) { id in
            ModuleBox(module: SharpenModule(), instanceID: id)
        }
        // Plan 04-05-T2: local contrast (clarity, EIGF base + detail mix),
        // v50 slot 54.0 (dt op "bilat") — after relight (53.0), before
        // colorcorrection (55.0). TilingPlan FULL second consumer.
        await registry.register(opName: LocalContrastModule.opName) { id in
            ModuleBox(module: LocalContrastModule(), instanceID: id)
        }
        // Plan 04-05-T3: soften (Orton effect, RGB linear domain), v50 slot
        // 66.0 (creative) — after grain (65.0), before splittoning (67.0).
        await registry.register(opName: SoftenModule.opName) { id in
            ModuleBox(module: SoftenModule(), instanceID: id)
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
            // Plan 04-02-T2: the flip remap (crop needs no kernel — blit).
            FlipKernel.functionName,
            // Plan 04-03-T2: the single-homography warp (rotation +
            // perspective share one kernel).
            AshiftKernel.functionName,
            // Plan 04-04-T1: the lens manual warp (distortion + TCA +
            // devignette fusion).
            LensKernel.functionName,
            // Plan 04-05-T1: sharpen prep + soft-threshold mix.
            SharpenKernel.prepFunction,
            SharpenKernel.mixFunction,
            // Plan 04-05-T2: local-contrast prep + clarity apply (the EIGF
            // leg reuses toneequal's kernels — already warmed above).
            LocalContrastKernel.prepFunction,
            LocalContrastKernel.applyFunction,
            // Plan 04-05-T3: highpass prep + CL mix; soften overexposed + mix.
            HighpassKernel.prepFunction,
            HighpassKernel.mixFunction,
            SoftenKernel.overFunction,
            SoftenKernel.mixFunction,
            // Plan 04-05-T4: equalizer prep + pyramid recombine.
            EqualizerKernel.prepFunction,
            EqualizerKernel.recombineFunction,
        ]
    }

    /// The pristine EDITING seed beyond the terminal trio (Plan 03-02-T4):
    /// the tone iops that ship permanent Inspector panels join a freshly
    /// loaded image at IDENTITY params, so their panels have instances to
    /// drive (D-T6's "ModuleRegistry-driven panel generation"). Identity
    /// params keep the default chain cache-neutral (byte-identical hashes).
    public static func editingDefaultInstances() -> [ModuleInstance] {
        [
            ModuleInstance(module: TemperatureModule.self, params: TemperatureModule.Params()),
            // Plan 04-04-T1: lens (neutral OFF) joins the seed — neutral
            // ⇒ blit identity ⇒ cache-neutral (exposure-0EV style), so
            // the lens panel has an instance to drive. Sorted by
            // (iopOrder, multiPriority) at return.
            ModuleInstance(module: LensModule.self, params: LensModule.Params()),
            ModuleInstance(module: AshiftModule.self, params: AshiftModule.Params()),
            // Plan 04-02: flip (NONE identity) + crop (full-frame neutral)
            // join the seed — both cache-neutral (flip NONE = identity
            // process; crop full-frame = whole-plane blit), so their
            // Inspector panels (T5) have instances to drive, exposure-0EV
            // style. Sorted by (iopOrder, multiPriority) at return.
            ModuleInstance(module: FlipModule.self, params: FlipModule.Params(orientation: .none)),
            ModuleInstance(module: ExposureModule.self, params: ExposureModule.Params()),
            ModuleInstance(module: ToneEqualModule.self, params: ToneEqualModule.Params()),
            ModuleInstance(module: CropModule.self, params: CropModule.Params()),
            ModuleInstance(module: SigmoidModule.self, params: SigmoidModule.Params()),
            ModuleInstance(module: AgXModule.self, params: AgXModule.Params()),
            ModuleInstance(module: FilmicRGBModule.self, params: FilmicRGBModule.Params()),
            ModuleInstance(module: ColisaModule.self, params: ColisaModule.Params()),
            ModuleInstance(module: ToneCurveModule.self, params: ToneCurveModule.Params()),
            ModuleInstance(module: LevelsModule.self, params: LevelsModule.Params()),
            ModuleInstance(module: ShadhiModule.self, params: ShadhiModule.Params()),
            // Plan 04-05-T1/T2: sharpen (amount 0) + local contrast (detail 0)
            // join the seed ENABLED-neutral — blit identity ⇒ cache-neutral
            // (exposure-0EV style), so their panels have instances to drive.
            ModuleInstance(module: SharpenModule.self, params: SharpenModule.Params()),
            ModuleInstance(module: LocalContrastModule.self, params: LocalContrastModule.Params()),
            // Plan 04-05-T4: equalizer (all-zero deltas = neutral) joins the
            // seed — blit identity ⇒ cache-neutral (exposure-0EV style), so
            // the equalizer panel has an instance to drive.
            ModuleInstance(module: EqualizerModule.self, params: EqualizerModule.Params()),
            // Plan 04-05-T3: highpass + soften join the seed DISABLED
            // (creative modules — DECISIONS D11: no zero-param identity, so
            // identity holds only via the disabled piece).
            ModuleInstance(module: HighpassModule.self, params: HighpassModule.Params(), enabled: false),
            ModuleInstance(module: SoftenModule.self, params: SoftenModule.Params(), enabled: false),
        ]
        .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }
}
