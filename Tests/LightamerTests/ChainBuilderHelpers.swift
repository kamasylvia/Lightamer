@testable import LightamerCore
import CoreGraphics
import CoreImage
import LightamerIOP
import Metal
import XCTest

// M2-4-0 E1 exemption (checker 2026-09-30) — zero-test SHARED chain-builder
// helpers. The two cross-domain builders below were extracted VERBATIM from
// TerminalTrioTests.makeCommittedDefaultChain (static) and
// GeometryGoldenTests.makeChainWithCropFlip (internal instance method, no
// self dependencies) so that the six domain test bundles can all link them
// without dragging the whole test classes into multiple targets (which would
// re-execute their test methods per bundle and break the 2165-test
// reconciliation). Test-method count is unchanged by construction: only
// non-test-method lines moved (1 definition + 49 qualified call sites
// mechanically rewritten). Compiled into IOP/Layers/Library/Export/App
// (SESS has no callers — minimal listing, ParityGate precedent).
// Precedents: Fixtures.swift / ParityGate.swift (zero-test shared helpers).

/// The default chain committed for an EXPLICIT displayP3 target
/// (deterministic across hosts — the screen-dependent `.display`
/// resolution is the coordinator's business, not the harness's).
func makeCommittedDefaultChain(
    registry: ModuleRegistry, outputProfile: ColorOutModule.OutputProfile
) async -> [any ModuleBoxing] {
    let chain = await registry.makeDefaultChain()
    if let colorout = chain.first(where: { $0.opName == ColorOutModule.opName })
        as? ModuleBox<ColorOutModule> {
        colorout.setParams(.init(outputProfile: outputProfile))
    }
    for box in chain where box.opName == ColorInModule.opName {
        if let colorin = box as? ModuleBox<ColorInModule> {
            colorin.setParams(.init())
        }
    }
    for box in chain where box.opName == GammaModule.opName {
        if let gamma = box as? ModuleBox<GammaModule> {
            gamma.setParams(.init())
        }
    }
    return chain
}

/// The default chain with crop (FULL-frame = identity window) + flip
/// (NONE identity) + lens (neutral OFF) + the five detail neutrals
/// (sharpen/bilat/equalizer enabled-neutral blit, highpass/soften
/// DISABLED — plan 04-05-T5 track B) inserted at their v50 slots.
/// Full-frame crop = whole-plane blit; neutral lens/detail = blit
/// identity (cache-neutral shapes, exercise the blit legs through the
/// real chain without moving patches into the letterbox).
/// (Internal — not private — since 06-01 T7: the layer zero-increment
/// gate reuses the exact track-B chain as its baseline. M2-4-0 E1:
/// extracted verbatim from GeometryGoldenTests.)
func makeChainWithCropFlip(
    registry: ModuleRegistry, outputProfile: ColorOutModule.OutputProfile
) async throws -> [any ModuleBoxing] {
    await LightamerIOPRegistry.populate(registry)
    var chain = await makeCommittedDefaultChain(
        registry: registry, outputProfile: outputProfile
    )
    let flip = await registry.makeBox(opName: FlipModule.opName)
    let flipBox = try XCTUnwrap(flip as? ModuleBox<FlipModule>)
    flipBox.setParams(FlipModule.Params(orientation: .none))
    chain.append(flipBox)
    let lens = await registry.makeBox(opName: LensModule.opName)
    let lensBox = try XCTUnwrap(lens as? ModuleBox<LensModule>)
    lensBox.setParams(LensModule.Params())
    chain.append(lensBox)
    let crop = await registry.makeBox(opName: CropModule.opName)
    let cropBox = try XCTUnwrap(crop as? ModuleBox<CropModule>)
    cropBox.setParams(CropModule.Params())
    chain.append(cropBox)
    // Plan 04-05-T5 track B: the five detail neutrals (blit-identity
    // legs through the real chain — enabled-neutral ×3, disabled ×2).
    let sharpenMade = await registry.makeBox(opName: SharpenModule.opName)
    let sharpenBox = try XCTUnwrap(sharpenMade as? ModuleBox<SharpenModule>)
    sharpenBox.setParams(SharpenModule.Params())
    chain.append(sharpenBox)
    let bilatMade = await registry.makeBox(opName: LocalContrastModule.opName)
    let bilatBox = try XCTUnwrap(bilatMade as? ModuleBox<LocalContrastModule>)
    bilatBox.setParams(LocalContrastModule.Params())
    chain.append(bilatBox)
    let eqMade = await registry.makeBox(opName: EqualizerModule.opName)
    let eqBox = try XCTUnwrap(eqMade as? ModuleBox<EqualizerModule>)
    eqBox.setParams(EqualizerModule.Params())
    chain.append(eqBox)
    let highMade = await registry.makeBox(opName: HighpassModule.opName)
    let highBox = try XCTUnwrap(highMade as? ModuleBox<HighpassModule>)
    highBox.setParams(HighpassModule.Params())
    highBox.enabled = false
    chain.append(highBox)
    let softMade = await registry.makeBox(opName: SoftenModule.opName)
    let softBox = try XCTUnwrap(softMade as? ModuleBox<SoftenModule>)
    softBox.setParams(SoftenModule.Params())
    softBox.enabled = false
    chain.append(softBox)
    // Plan 05-04-T5 track B: vibrance + velvia + colorzones neutrals
    // (enabled-neutral ×3 — amount/strength 0 + flat-0.5 curves ⇒
    // identity through the real chain).
    let vibMade = await registry.makeBox(opName: VibranceModule.opName)
    let vibBox = try XCTUnwrap(vibMade as? ModuleBox<VibranceModule>)
    vibBox.setParams(VibranceModule.Params())
    chain.append(vibBox)
    let velMade = await registry.makeBox(opName: VelviaModule.opName)
    let velBox = try XCTUnwrap(velMade as? ModuleBox<VelviaModule>)
    velBox.setParams(VelviaModule.Params())
    chain.append(velBox)
    let czMade = await registry.makeBox(opName: ColorZonesModule.opName)
    let czBox = try XCTUnwrap(czMade as? ModuleBox<ColorZonesModule>)
    czBox.setParams(ColorZonesModule.Params())
    chain.append(czBox)
    // Plan 05-05-T4 track B: monochrome DISABLED seed (default size=2
    // filter is not neutral — disabled ⇒ pipe skips ⇒ zero chain delta;
    // 05-02 colorbalancergb T5 zero-increment precedent).
    let monoMade = await registry.makeBox(opName: MonochromeModule.opName)
    let monoBox = try XCTUnwrap(monoMade as? ModuleBox<MonochromeModule>)
    monoBox.setParams(MonochromeModule.Params())
    monoBox.enabled = false
    chain.append(monoBox)
    // Plan 05-07-T6 track B: denoiseprofile DISABLED (no zero-param
    // identity — force 0.5 keeps thrs > 0 — disabled ⇒ pipe skips ⇒
    // zero chain delta; the LIVE insertion coverage rides the parity
    // suite; 05-06's nlmeans keeps its own enabled-neutral test).
    let dpMade = await registry.makeBox(opName: DenoiseProfileModule.opName)
    let dpBox = try XCTUnwrap(dpMade as? ModuleBox<DenoiseProfileModule>)
    dpBox.setParams(DenoiseProfileModule.Params())
    dpBox.enabled = false
    chain.append(dpBox)
    // Plan 05-08-T5 track B: nlmeans + bilateral DISABLED (no zero-param
    // identity for either — D-05-06-T2-1 / D-05-08-T1-3; disabled ⇒ pipe
    // skips ⇒ zero chain delta). With these two the track-B chain now
    // carries EVERY Phase 3+4+5 module — the Phase 6 baseline.
    let nlMade = await registry.makeBox(opName: NLMeansModule.opName)
    let nlBox = try XCTUnwrap(nlMade as? ModuleBox<NLMeansModule>)
    nlBox.setParams(NLMeansModule.Params())
    nlBox.enabled = false
    chain.append(nlBox)
    let blMade = await registry.makeBox(opName: BilateralModule.opName)
    let blBox = try XCTUnwrap(blMade as? ModuleBox<BilateralModule>)
    blBox.setParams(BilateralModule.Params())
    blBox.enabled = false
    chain.append(blBox)
    return chain.sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
}
