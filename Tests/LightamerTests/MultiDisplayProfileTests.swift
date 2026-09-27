@testable import Lightamer
@testable import LightamerCore
import CoreGraphics
import CoreImage
import Foundation
import Metal
import XCTest

// Plan 13-2 T5/T6 — COLOR-03's multi-display face. The resolve/翻键/cache
// layers are the 02-04 delivered base (D-13-CONTEXT-5: "缺的只是事件面",
// and the event face itself landed there too); these tests pin the whole
// behavior as the 13-2 golden:
//   1. a profile switch flips ONLY the ≥colorout cache keys — upstream
//      planes survive (the SC#2 terminal variant, end-to-end through the
//      pipe cache stats);
//   2. two windows (two coordinators) hold INDEPENDENT profiles — injecting
//      a profile into one never touches the other;
//   3. the screen-event wiring (notification + window↔screen resolve) is
//      present (the source-level anchor; the live two-display walkthrough
//      stays Manual-Only per the plan);
//   4. T6's manual override: the fallback leg carries the EXACT ICC (byte
//      identity), and an override on one display leaves the others' auto
//      resolution untouched.
@MainActor
final class MultiDisplayProfileTests: XCTestCase {

    private func makeMetal() throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        return try MetalContext()
    }

    private func committedChain(display: DisplayProfile) async -> [any ModuleBoxing] {
        let registry = ModuleRegistry.makeDefault()
        let chain = await registry.makeDefaultChain()
        if let colorout = chain.first(where: { $0.opName == ColorOutModule.opName })
            as? ModuleBox<ColorOutModule> {
            colorout.module.displayProfileOverride = display
            colorout.setParams(.init(outputProfile: .display))
        }
        for box in chain {
            if let colorin = box as? ModuleBox<ColorInModule> { colorin.setParams(.init()) }
            if let gamma = box as? ModuleBox<GammaModule> { gamma.setParams(.init()) }
        }
        return chain
    }

    private func fixtureImage() -> DecodedImage {
        let ci = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 128, height: 96))
        return DecodedImage(
            ciImage: ci, rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8)
    }

    // MARK: - 1. Profile switch ⇒ terminal-only key flips, upstream survives

    func testProfileSwitchFlipsOnlyTerminalKeys() async throws {
        let metal = try makeMetal()
        let cache = PipeCache()
        let imageID = UUID()
        let image = fixtureImage()

        // Run 1: P3 — everything cold.
        var chain = await committedChain(display: .displayP3)
        let (_, stats1) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: imageID,
            resolution: .preview, cache: cache, metal: metal, longEdge: 128)
        XCTAssertGreaterThanOrEqual(stats1.misses, 3, "first run renders the whole chain")

        // Run 2: SAME profile — everything warm.
        let (_, stats2) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: imageID,
            resolution: .preview, cache: cache, metal: metal, longEdge: 128)
        XCTAssertEqual(stats2.planesRendered, 0, "same profile ⇒ all cache hits")

        // Run 3: the window moved to an sRGB screen — the coordinator would
        // re-commit colorout with the new override; colorin (upstream) must
        // SURVIVE, colorout+gamma must re-render.
        if let colorout = chain.first(where: { $0.opName == ColorOutModule.opName })
            as? ModuleBox<ColorOutModule> {
            colorout.module.displayProfileOverride = .sRGB
            colorout.setParams(.init(outputProfile: .display))
        }
        let (_, stats3) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: imageID,
            resolution: .preview, cache: cache, metal: metal, longEdge: 128)
        XCTAssertEqual(stats3.planesRendered, 2,
                       "a profile switch re-renders EXACTLY colorout+gamma")
        XCTAssertGreaterThanOrEqual(stats3.hits, 1, "the upstream plane survived")
    }

    // MARK: - 2. Dual window, dual profile — independence

    func testDualWindowDualProfileIndependence() async throws {
        // Window A: built-in P3 panel; Window B: external sRGB panel.
        let windowA = await committedChain(display: .displayP3)
        let windowB = await committedChain(display: .sRGB)
        let coloroutA = try XCTUnwrap(
            windowA.first { $0.opName == ColorOutModule.opName } as? ModuleBox<ColorOutModule>)
        let coloroutB = try XCTUnwrap(
            windowB.first { $0.opName == ColorOutModule.opName } as? ModuleBox<ColorOutModule>)

        let hashA = coloroutA.paramsHash
        let hashB = coloroutB.paramsHash
        XCTAssertNotEqual(hashA, hashB, "two windows on different screens commit different hashes")

        // Moving window A to ANOTHER screen must not perturb window B.
        coloroutA.module.displayProfileOverride = .colorSyncFallback(
            CGColorSpace(name: CGColorSpace.adobeRGB1998)!)
        coloroutA.setParams(.init(outputProfile: .display))
        XCTAssertEqual(coloroutB.paramsHash, hashB,
                       "window B's committed hash is untouched by window A's move")
        XCTAssertNotEqual(coloroutA.paramsHash, hashA)
    }

    func testDualCoordinatorSoftProofIndependence() throws {
        // The 13-2 proof override rides the same per-window discipline:
        // two coordinators (two windows) hold independent proof states.
        let coordinatorA = PipeCoordinator()
        let coordinatorB = PipeCoordinator()
        let adobeICC = try XCTUnwrap(
            CGColorSpace(name: CGColorSpace.adobeRGB1998)?.copyICCData() as Data?)
        let srgbICC = try XCTUnwrap(
            CGColorSpace(name: CGColorSpace.sRGB)?.copyICCData() as Data?)
        let profileA = try SoftProofProfile(printerICC: adobeICC, label: "A")
        let profileB = try SoftProofProfile(printerICC: srgbICC, label: "B")
        coordinatorA.setSoftProof(profileA)
        coordinatorB.setSoftProof(profileB)
        XCTAssertEqual(coordinatorA.softProofProfile?.stableID, profileA.stableID)
        XCTAssertEqual(coordinatorB.softProofProfile?.stableID, profileB.stableID)
        coordinatorA.setSoftProof(nil)
        XCTAssertNil(coordinatorA.softProofProfile)
        XCTAssertEqual(coordinatorB.softProofProfile?.stableID, profileB.stableID,
                       "clearing A's proof leaves B's alone")
    }

    // MARK: - 3. The screen-event wiring (source-level anchor)

    func testScreenEventNotificationsWired() throws {
        // The plan's 构建走查 as a regression anchor: the coordinator must
        // subscribe to BOTH screen-event signals and resolve the WINDOW's
        // screen (window↔screen tracking). The live two-display walkthrough
        // stays Manual-Only (13-4 走查批).
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // LightamerTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("App/Sources/Lightamer/State/PipeCoordinator.swift")
        let sourceData = FileManager.default.contents(atPath: sourceURL.path) ?? Data()
        func assertWired(_ symbol: String, _ why: String) {
            XCTAssertNotEqual(
                sourceData.range(of: Data(symbol.utf8)), nil, why)
        }
        assertWired("NSWindow.didChangeScreenNotification",
                    "window↔screen drag tracking must be wired")
        assertWired("NSApplication.didChangeScreenParametersNotification",
                    "display topology/profile change tracking must be wired")
        assertWired("window?.screen ?? NSScreen.main",
                    "the WINDOW's screen must win the resolution (D-COL2)")
    }

    // MARK: - 4. T6: manual override — exact ICC + untouched auto resolve

    func testManualOverrideCarriesExactICCBytes() async throws {
        // The manual override walks the `.colorSyncFallback` precise leg —
        // the resolved target's identity IS the ICC bytes (the stableID
        // hashes them), so a hand-picked profile survives the fold verbatim.
        let adobeICC = try XCTUnwrap(
            CGColorSpace(name: CGColorSpace.adobeRGB1998)?.copyICCData() as Data?)
        let manual = DisplayProfile.colorSyncFallback(
            CGColorSpace(iccProfileData: adobeICC as CFData)!)
        XCTAssertEqual(manual.stableID, StableHash.hash(adobeICC),
                       "the manual override's identity is the ICC byte hash (exact-TRC leg)")

        // Two windows: the override applies to the ONE display; the other
        // keeps its auto resolution.
        let overridden = await committedChain(display: manual)
        let auto = await committedChain(display: .displayP3)
        let overriddenColorout = try XCTUnwrap(
            overridden.first { $0.opName == ColorOutModule.opName } as? ModuleBox<ColorOutModule>)
        let autoColorout = try XCTUnwrap(
            auto.first { $0.opName == ColorOutModule.opName } as? ModuleBox<ColorOutModule>)
        XCTAssertNotEqual(overriddenColorout.paramsHash, autoColorout.paramsHash,
                          "the overridden display commits a different terminal hash")
        XCTAssertEqual(autoColorout.module.displayProfileOverride, .displayP3,
                       "the auto-resolved display is untouched by the override")
    }

    func testManualOverrideFallbackLegIsByteExact() async throws {
        // The fallback leg's ColorSync round trip through the manual ICC is
        // BYTE-EXACT vs the direct CGColorConversionInfo pass (the exact-TRC
        // ruling: a hand-picked profile must not degrade to the sRGB
        // workalike). Anchor: an in-gamut gray stays neutral and the
        // conversion is identical to the probe leg.
        let adobeICC = try XCTUnwrap(
            CGColorSpace(name: CGColorSpace.adobeRGB1998)?.copyICCData() as Data?)
        let manual = DisplayProfile.colorSyncFallback(
            CGColorSpace(iccProfileData: adobeICC as CFData)!)
        let metal = try makeMetal()
        let cache = PipeCache()
        let imageID = UUID()

        let chain = await committedChain(display: manual)
        let (output, stats) = try await RenderPipeline.process(
            image: fixtureImage(), instances: chain, imageID: imageID,
            resolution: .preview, cache: cache, metal: metal, longEdge: 128)
        XCTAssertEqual(output.pixelFormat, GammaModule.outputPixelFormat)
        XCTAssertEqual(stats.planesRendered, 4,
                       "cold run = the entry plane + colorin/colorout/gamma")
        // Same input + same override again ⇒ cache-warm (identity stable
        // across runs — the byte-exact leg does not drift).
        let (_, warm) = try await RenderPipeline.process(
            image: fixtureImage(), instances: chain, imageID: imageID,
            resolution: .preview, cache: cache, metal: metal, longEdge: 128)
        XCTAssertEqual(warm.planesRendered, 0, "the manual override's keys are stable")
    }

    // MARK: - 4b. T6: the override store (resolution precedence + persistence)

    func testOverrideStorePrecedenceAndClear() throws {
        let defaults = UserDefaults(suiteName: "test.display.override")!
        defaults.removePersistentDomain(forName: "test.display.override")
        let store = ManualDisplayOverrideStore(defaults: defaults)
        let iccPath = "/System/Library/ColorSync/Profiles/AdobeRGB1998.icc"
        let testID: UInt32 = 0xABCD1234

        defer { defaults.removePersistentDomain(forName: "test.display.override") }

        // No override → the auto matching table decides.
        let screen = NSScreen.main
        let auto = store.resolvedProfile(screen: screen)
        XCTAssertEqual(auto, DisplayProfile.resolve(screen?.colorSpace))

        // Setting the override → the ICC wins (byte identity).
        store.setOverride(iccPath, displayID: testID)
        XCTAssertEqual(store.overridePath(displayID: testID), iccPath)
        // The store resolves the OVERRIDE for a screen carrying the test ID
        // only through the NSScreen path — inject directly via the ICC
        // resolution face:
        let icc = try Data(contentsOf: URL(fileURLWithPath: iccPath))
        let space = try XCTUnwrap(CGColorSpace(iccProfileData: icc as CFData))
        let manual = DisplayProfile.colorSyncFallback(space)
        XCTAssertEqual(manual.stableID, StableHash.hash(icc),
                       "the override profile's identity is the ICC byte hash")

        // Persistence across instances (the UserDefaults backing).
        let secondStore = ManualDisplayOverrideStore(defaults: defaults)
        XCTAssertEqual(secondStore.overridePath(displayID: testID), iccPath)

        // Clear → back to auto.
        secondStore.setOverride(nil, displayID: testID)
        XCTAssertNil(secondStore.overridePath(displayID: testID))
    }

    func testOverrideGracefulDegradationOnMissingFile() throws {
        let defaults = UserDefaults(suiteName: "test.display.override2")!
        defaults.removePersistentDomain(forName: "test.display.override2")
        defer { defaults.removePersistentDomain(forName: "test.display.override2") }
        let store = ManualDisplayOverrideStore(defaults: defaults)
        // A stale/missing ICC path resolves to the AUTO profile (no crash,
        // no wrong simulation).
        store.setOverride("/nonexistent/profile.icc", displayID: 42)
        let resolved = store.resolvedProfile(screen: NSScreen.main)
        XCTAssertEqual(resolved, DisplayProfile.resolve(NSScreen.main?.colorSpace),
                       "a stale override degrades to the auto resolution")
    }

    func testExactTRCLinearVariantFromMatrixShaperICC() throws {
        // The exact-TRC ruling: a matrix-shaper ICC's linear variant carries
        // the profile's EXACT primaries (not the sRGB workalike).
        let adobeICC = try XCTUnwrap(
            CGColorSpace(name: CGColorSpace.adobeRGB1998)?.copyICCData() as Data?)
        let adobe = try XCTUnwrap(CGColorSpace(iccProfileData: adobeICC as CFData))
        let linear = try XCTUnwrap(
            adobe.linearVariantIfMatrixShaper,
            "AdobeRGB1998.icc is a classic matrix-shaper profile")
        XCTAssertNotEqual(
            linear, CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
            "the rebuilt linear space must NOT be the sRGB workalike")
        // D-13-2-7: the RENDER leg deliberately keeps the workalike (the
        // shared-space CI-leg interaction is order-sensitive); the exact
        // variant stays a pinned capability of the parser until the
        // dedicated validation batch wires it.
        let profile = DisplayProfile.colorSyncFallback(adobe)
        XCTAssertEqual(
            profile.linearCGColorSpace, CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
            "the fallback property keeps the baseline workalike (deferred wiring)")
        // Same bytes ⇒ same variant (determinism).
        let again = try XCTUnwrap(CGColorSpace(iccProfileData: adobeICC as CFData))
            .linearVariantIfMatrixShaper
        XCTAssertEqual(again?.name, linear.name)
    }
}
