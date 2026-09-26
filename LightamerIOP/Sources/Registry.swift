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
        // Plan 05-02-T2: colorbalancergb (scene-referred RGB grading,
        // 4-way + saturation legs), v50 slot 41.5 — after colorbalance
        // (41.0), before rgbcurve (42.0).
        await registry.register(opName: ColorBalanceRGBModule.opName) { id in
            ModuleBox(module: ColorBalanceRGBModule(), instanceID: id)
        }
        // Plan 05-03-T2: channelmixerrgb ("color calibration",
        // scene-linear RGB WB + 3x3 mix), v50 slot 28.5 — immediately after
        // colorin (28.0). Seed DISABLED (dt default_enabled FALSE,
        // channelmixerrgb.c:3886; default D-illuminant adaptation is not
        // pixel-identity — colorbalancergb D1 same disposition).
        await registry.register(opName: ChannelMixerRGBModule.opName) { id in
            ModuleBox(module: ChannelMixerRGBModule(), instanceID: id)
        }
        // Plan 05-03-T3: channelmixer legacy (3x3 gain + HSL modes), v50
        // slot 39.0. Seed ENABLED-neutral (identity RGB + v2 ⇒
        // OPERATION_MODE_RGB identity — exposure-0EV style). dt DEPRECATED
        // (channelmixer.c:126) — delivered per IOP-COLOR-04, head note.
        await registry.register(opName: ChannelMixerModule.opName) { id in
            ModuleBox(module: ChannelMixerModule(), instanceID: id)
        }
        // Plan 05-03-T3: colorcontrast (Lab a/b slope + offset), v50 slot
        // 56.0. Seed ENABLED-neutral (steepness 1/offset 0 ⇒ identity).
        await registry.register(opName: ColorContrastModule.opName) { id in
            ModuleBox(module: ColorContrastModule(), instanceID: id)
        }
        // Plan 05-04-T1: velvia (RGB linear saturation boost), v50 slot
        // 57.0 — before vibrance (58.0). Seed ENABLED-neutral (strength 0
        // ⇒ saturation 0 ⇒ in == out). The trailing clamp is dt's formula
        // (head note).
        await registry.register(opName: VelviaModule.opName) { id in
            ModuleBox(module: VelviaModule(), instanceID: id)
        }
        // Plan 05-04-T1: vibrance (Lab single-parameter), v50 slot 58.0.
        // Seed ENABLED-neutral (amount 0 ⇒ ls=ss=1). dt DEPRECATED in favor
        // of colorbalancergb's Ych-family slider — delivered independently
        // per D-05-CONTEXT-8 (different formula family, head note).
        await registry.register(opName: VibranceModule.opName) { id in
            ModuleBox(module: VibranceModule(), instanceID: id)
        }
        // Plan 05-04-T2: colorzones (Lab 3-curve L/C/h + 0x10000 LUTs),
        // v50 slot 60.0. Seed ENABLED-neutral (default curves flat-0.5 ⇒
        // Lm/hm = 0, Cm = 1 ⇒ in == out). SMOOTH/v3 path only (strong
        // legacy out of scope — DECISIONS D-05-04-T2-2).
        await registry.register(opName: ColorZonesModule.opName) { id in
            ModuleBox(module: ColorZonesModule(), instanceID: id)
        }
        // Plan 05-05-T1: monochrome (B&W + color filter, Lab filter leg),
        // v50 slot 64.0 — after lowlight (63.0), before grain (65.0).
        // Seed DISABLED (default size=2 red filter is not pixel-identity —
        // identity holds only via the disabled piece; colorbalancergb D1
        // same disposition; DECISIONS D2).
        await registry.register(opName: MonochromeModule.opName) { id in
            ModuleBox(module: MonochromeModule(), instanceID: id)
        }
        // Plan 05-06-T2: nlmeans ("astrophoto denoise", Goossens sliding
        // window NLMeans), v50 slot 29.0 — immediately after colorin (28.0;
        // Lab needs calibrated color, iop_order.c note). Seed DISABLED
        // (dt ships nlmeans without a default_enabled override; no zero-
        // param identity exists — sharpness=3000 at strength 0 still
        // smooths similar patches and the commit clamp floors
        // luma/chroma at 0.0001 so the finish blend never reaches zero
        // weight; colorbalancergb D1 disposition, DECISIONS D-05-06-T2-1).
        await registry.register(opName: NLMeansModule.opName) { id in
            ModuleBox(module: NLMeansModule(), instanceID: id)
        }
        // Plan 05-07-T2: denoiseprofile ("denoise (profiled)", VST + eaw
        // wavelets + NLMeans leg + NoiseProfileStore consumption), v50 slot
        // 9.0 — immediately after temperature (3.0-era WB semantics), the
        // FIRST post-demosaic RGB slot. Seed DISABLED (D-05-07-T2-2: dt
        // auto-profiles RAWs at defaults, but no zero-param identity
        // exists — force 0.5 keeps thrs>0 so noisy pixels move, and the
        // auto profile makes defaults image-dependent; identity holds only
        // via the disabled piece, colorbalancergb D1 disposition).
        await registry.register(opName: DenoiseProfileModule.opName) { id in
            ModuleBox(module: DenoiseProfileModule(), instanceID: id)
        }
        // Plan 05-08-T1: bilateral ("surface blur", direct stamp ≤ rad 6 +
        // 5D grid leg with the OQ7 budget), v50 slot 10.0 — immediately
        // after denoiseprofile (9.0), before demosaic-adjacent colorin-era
        // slots. Seed DISABLED (D-05-08-T1-3: no zero-param identity —
        // radius $MIN 1.0 still smooths, so identity holds only via the
        // disabled piece; colorbalancergb D1 disposition).
        await registry.register(opName: BilateralModule.opName) { id in
            ModuleBox(module: BilateralModule(), instanceID: id)
        }
        // Plan 04-05-T3: soften (Orton effect, RGB linear domain), v50 slot
        // 66.0 (creative) — after grain (65.0), before splittoning (67.0).
        await registry.register(opName: SoftenModule.opName) { id in
            ModuleBox(module: SoftenModule(), instanceID: id)
        }
        // Plan 07-2: skinSmooth (frequency-separation skin smoothing),
        // v50 slot 66.5 — the FIRST Lightamer-native row in the otherwise
        // dt-verbatim V50Order table (D-07-CONTEXT-2): after soften (66.0),
        // before splittoning (67.0) — the blur/creative neighborhood. Seed
        // ENABLED-neutral (strength 0 ⇒ blit identity ⇒ cache-neutral —
        // the liquify empty-path disposition; the 07-3 panel drives it).
        await registry.register(opName: SkinSmoothModule.opName) { id in
            ModuleBox(module: SkinSmoothModule(), instanceID: id)
        }
        // Plan 06-06-T2: liquify (portrait liquify warp), v50 slot 18.0 —
        // after clipping (17.0), before spots (19.0); the base chain's last
        // DISTORT|GEOMETRY warp before the tone stages. Seed ENABLED-neutral
        // (empty paths = blit identity, cache-neutral — the plan's
        // 空路径恒等 seed; exposure-0EV style).
        await registry.register(opName: LiquifyModule.opName) { id in
            ModuleBox(module: LiquifyModule(), instanceID: id)
        }
        // Plan 08-01-T1: borders (yiyin 印框 canvas module), v50 slot 76.0 —
        // ALREADY in the V50Order table (zero rows inserted); the first
        // resident of the widened iopOrder ≥ 70.0 terminal tail window.
        await registry.register(opName: BordersModule.opName) { id in
            ModuleBox(module: BordersModule(), instanceID: id)
        }
        // Plan 08-2-T3: watermark (yiyin 终局水印 module), v50 slot 77.0 —
        // ALREADY in the V50Order table (zero rows inserted); the terminal
        // tail window's second resident. Seed ENABLED-neutral (the system
        // template catalog present but ALL rows OFF → rowless →
        // byte-identical blit — D-08-CONTEXT-4's explicit-add semantics;
        // the 08-2 panel drives this instance).
        await registry.register(opName: WatermarkModule.opName) { id in
            ModuleBox(module: WatermarkModule(), instanceID: id)
        }
        // Plan 12-5 T2: lut3d (.cube application), v50 slot 36.0 — ALREADY
        // in the V50Order table (zero rows inserted). Neutral (lutName nil)
        // = blit identity ⇒ cache-neutral (exposure-0EV style); the T5
        // LUT panel drives this instance. Resolution rides the shared
        // library store (T5) — missing entries degrade to the blit.
        await registry.register(opName: Lut3dModule.opName) { id in
            ModuleBox(module: Lut3dModule(resolver: LutLibraryStore.shared), instanceID: id)
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
            // Plan 04-05-T4: equalizer prep + pyramid recombine.
            EqualizerKernel.prepFunction,
            EqualizerKernel.recombineFunction,
            // Plan 05-02-T2: colorbalancergb single-pass grading.
            ColorBalanceRGBKernel.functionName,
            // Plan 05-04-T2: colorzones LUT triple.
            ColorZonesKernel.functionName,
            // Plan 05-05-T1/T2: monochrome filter + apply + the 3D grid
            // quadruple it consumes (splat/blur_line/blur_line_z/slice —
            // BilateralGrid3D prewarms on first monochrome render otherwise).
            MonochromeKernel.filterFunction,
            MonochromeKernel.applyFunction,
            BilateralGrid3D.splatFunction,
            BilateralGrid3D.blurLineFunction,
            BilateralGrid3D.blurLineZFunction,
            BilateralGrid3D.sliceFunction,
            ChannelMixerKernel.functionName,
            ColorContrastKernel.functionName,
            // Plan 05-06: nlmeans kernel group (the denoiseprofile NLMeans
            // leg consumes the same five kernels — 05-07 rides this warm-up).
            NLMeansKernel.labForwardFunction,
            NLMeansKernel.distFunction,
            NLMeansKernel.horizFunction,
            NLMeansKernel.vertFunction,
            NLMeansKernel.accuFunction,
            NLMeansKernel.finishFunction,
            // Plan 05-07-T2: denoiseprofile kernel group (the NLMeans leg
            // additionally reuses the nlmeans dist/horiz/accu above).
            DenoiseProfileKernel.precondition,
            DenoiseProfileKernel.preconditionV2,
            DenoiseProfileKernel.preconditionY0U0V0,
            DenoiseProfileKernel.backtransform,
            DenoiseProfileKernel.backtransformV2,
            DenoiseProfileKernel.backtransformY0U0V0,
            DenoiseProfileKernel.decompose,
            DenoiseProfileKernel.synthesizeAccum,
            DenoiseProfileKernel.reduceFirst,
            DenoiseProfileKernel.reduceSecond,
            DenoiseProfileKernel.addResidue,
            DenoiseProfileKernel.vert,
            DenoiseProfileKernel.finish,
            DenoiseProfileKernel.finishV2,
            // Plan 05-08-T1: bilateral kernel pair (direct stamp + the 5D
            // grid trio — splat/blur/slice; the blur runs ×5 dims).
            BilateralKernel.directFunction,
            BilateralKernel.splatFunction,
            BilateralKernel.blurLineFunction,
            BilateralKernel.sliceFunction,
            // Plan 05-04-T1: velvia + vibrance.
            VelviaKernel.functionName,
            VibranceKernel.functionName,
            SoftenKernel.overFunction,
            SoftenKernel.mixFunction,
            // Plan 06-06-T2: the liquify displacement warp (lanczos3/
            // bicubic tables ride in a buffer — one PSO for all).
            LiquifyKernel.functionName,
            // Plan 07-2: the skinSmooth threshold-attenuation mix (the low
            // leg reuses the gaussian_pass_* kernels — warmed above).
            SkinSmoothKernel.mixFunction,
            // Plan 08-01: the yiyin borders composite canvas pass (the SDF/
            // downsample kernels warm on first use — T4/T5 legs).
            BordersModule.kernelComposite,
            BordersModule.kernelShadowSDF,
            BordersModule.kernelBoxDownsample,
            // Plan 08-2 T4: the watermark row composite (one PSO per
            // functionName — the 16×16 threadgroup is static).
            WatermarkModule.kernelRow,
            // Plan 12-5 T2: the lut3d interpolation pair (both states —
            // the picker flips between them without a first-use stall) +
            // the 1D ramp kernel (T3).
            Lut3dModule.Kernel.tetrahedral,
            Lut3dModule.Kernel.trilinear,
            Lut3dModule.Kernel.ramp1D,
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
            // Plan 05-02-T2: colorbalancergb joins the seed DISABLED
            // (05-02-DECISIONS D1: default params are NOT pixel-identity —
            // the gamut legs move wide-gamut colors even at neutral, so no
            // zero-param identity exists; identity holds only via the
            // disabled piece — highpass/soften D11 same disposition).
            ModuleInstance(module: ColorBalanceRGBModule.self, params: ColorBalanceRGBModule.Params(), enabled: false),
            // Plan 04-05-T3: highpass + soften join the seed DISABLED
            // (creative modules — DECISIONS D11: no zero-param identity, so
            // identity holds only via the disabled piece).
            ModuleInstance(module: HighpassModule.self, params: HighpassModule.Params(), enabled: false),
            ModuleInstance(module: SoftenModule.self, params: SoftenModule.Params(), enabled: false),
            // Plan 05-03-T2: channelmixerrgb joins the seed DISABLED
            // (dt default_enabled FALSE, channelmixerrgb.c:3886; the default
            // D-illuminant adaptation is not pixel-identity —
            // colorbalancergb D1 same disposition).
            ModuleInstance(module: ChannelMixerRGBModule.self, params: ChannelMixerRGBModule.Params(), enabled: false),
            // Plan 05-03-T3: channelmixer legacy + colorcontrast join the
            // seed ENABLED-neutral (identity matrices ⇒ cache-neutral,
            // exposure-0EV style, so their panels have instances to drive).
            ModuleInstance(module: ChannelMixerModule.self, params: ChannelMixerModule.Params()),
            ModuleInstance(module: ColorContrastModule.self, params: ColorContrastModule.Params()),
            // Plan 05-04-T1: velvia + vibrance join the seed ENABLED-neutral
            // (strength/amount 0 ⇒ identity, cache-neutral, exposure-0EV
            // style, so their panels have instances to drive).
            ModuleInstance(module: VelviaModule.self, params: VelviaModule.Params()),
            ModuleInstance(module: VibranceModule.self, params: VibranceModule.Params()),
            // Plan 05-04-T2: colorzones joins the seed ENABLED-neutral
            // (flat-0.5 default curves ⇒ identity, cache-neutral).
            ModuleInstance(module: ColorZonesModule.self, params: ColorZonesModule.Params()),
            // Plan 05-05-T1: monochrome joins the seed DISABLED (D2: default
            // size=2 red filter is not pixel-identity — identity holds only
            // via the disabled piece; colorbalancergb D1 same disposition).
            ModuleInstance(module: MonochromeModule.self, params: MonochromeModule.Params(), enabled: false),
            // Plan 05-06-T2: nlmeans joins the seed DISABLED (DECISIONS
            // D-05-06-T2-1: dt ships it disabled — no default_enabled
            // override — and no zero-param identity exists: strength 0
            // keeps sharpness 3000 which still smooths similar patches,
            // and the commit clamp floors luma/chroma at 0.0001 so the
            // finish blend never reaches zero weight; identity holds only
            // via the disabled piece, colorbalancergb D1 disposition).
            ModuleInstance(module: NLMeansModule.self, params: NLMeansModule.Params(), enabled: false),
            // Plan 05-07-T2: denoiseprofile joins the seed DISABLED
            // (D-05-07-T2-2 — see the registration note above).
            ModuleInstance(module: DenoiseProfileModule.self, params: DenoiseProfileModule.Params(), enabled: false),
            // Plan 05-08-T1: bilateral joins the seed DISABLED (D-05-08-T1-3
            // — see the registration note above).
            ModuleInstance(module: BilateralModule.self, params: BilateralModule.Params(), enabled: false),
            // Plan 06-06-T2: liquify joins the seed ENABLED-neutral (empty
            // paths = the blit identity — the NORMAL liquify state, cache-
            // neutral, exposure-0EV style; the liquify panel + overlay have
            // an instance to drive).
            ModuleInstance(module: LiquifyModule.self, params: LiquifyModule.Params()),
            // Plan 07-2: skinSmooth joins the seed ENABLED-neutral (strength
            // 0 ⇒ the D9 blit identity — cache-neutral, exposure-0EV style;
            // the 07-3 panel has an instance to drive).
            ModuleInstance(module: SkinSmoothModule.self, params: SkinSmoothModule.Params()),
            // Plan 08-01-T1: borders joins the seed ENABLED-neutral
            // (rate 100 / margin 0 / radius nil / shadow nil ⇒ canvas ==
            // main image ⇒ byte-identical blit — the PARAM-based identity,
            // never the yiyin formula whose ceil-quirk can grow the canvas;
            // D-08-CONTEXT-4: 新图不自动挂默认印框 is about AUTO-ATTACH
            // semantics, this seed instance is the neutral carrier the
            // 08-2 panel drives, exposure-0EV style).
            ModuleInstance(module: BordersModule.self, params: BordersModule.Params.neutralSeed),
            // Plan 08-2-T3: watermark joins the seed ENABLED-neutral (the
            // rowless seed — all system templates OFF → no resolved rows →
            // byte-identical blit, cache-neutral, exposure-0EV style; the
            // 08-2 watermark panel has an instance to drive).
            ModuleInstance(module: WatermarkModule.self, params: WatermarkModule.Params.neutralSeed),
            // Plan 12-5 T5: lut3d joins the seed ENABLED-neutral (lutName
            // nil = the routed blit identity — cache-neutral, exposure-0EV
            // style; the LUT panel has an instance to drive).
            ModuleInstance(module: Lut3dModule.self, params: Lut3dModule.Params()),
        ]
        .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
}
}
