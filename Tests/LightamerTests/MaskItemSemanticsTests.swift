@testable import Lightamer
@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// MaskItemSemanticsTests (Plan M2-4-2 T1, AC1/AC2) — the v5 mask-item fields
// become BEHAVIOR:
//
//   disabled = 恒等元过滤  — the enabled gate filters items CPU-side BEFORE
//                            the combine assembly (5 op × first/middle/last
//                            disabled per-pixel vs the Double reference over
//                            the enabled subset <1e-6; the closed-form area
//                            anchors for the two-circle subset; kernels and
//                            the five formulas untouched).
//   空 enabled 集 = 恒 1   — all-disabled (or a single disabled item) group
//                            resolves NO plane → the dt no-form fill-1 leg:
//                            the assembly is byte-exact the constant-1
//                            plane × opacity (NOT constant 0 — disabling a
//                            mask LIFTS the constraint, it does not disable
//                            the grade; D-M2-4-CONTEXT-6 owns that).
//   deletionProtected 双腿 — clear AND fill both refuse (checker E3: two
//                            content-clearing legs), toast + ZERO history
//                            item; unprotected behavior byte-for-byte the
//                            pre-M2-4 shape.
//   accessor round-trip    — maskItems read view + the two setters, silent
//                            no-op on unknown ids, nil name stays stored nil
//                            (the M2-7 derivation consumes the Core single
//                            source LayerStack.nextLayerName(base:)).
//
// App-level suite (checker E2 → LightamerTestsApp): the lock legs instantiate
// EditorState/LayerEditingState; the combiner legs reuse the 06-04 Metal
// harness pattern (that class stays nonisolated — Swift 6 region isolation
// lets locally-created textures cross into the async assembly there).
// ─────────────────────────────────────────────────────────────────────────────

/// The three overlapping circles (the 06-04 geometry): A r=.20 @.38, B
/// r=.16 @.62, C r=.07 @.5 (C sits inside A, lensing B).
private func makeCircleForms() -> [MaskForm] {
    func circle(_ cx: Float, _ r: Float) -> MaskForm {
        MaskForm(kind: .ellipse(EllipseForm(
            center: MaskPoint(x: cx, y: 0.5), radiusX: r, radiusY: r,
            rotationDegrees: 0, border: 0)))
    }
    return [circle(0.38, 0.20), circle(0.62, 0.16), circle(0.5, 0.07)]
}

// MARK: - The combiner face (KD-1; nonisolated — the Metal harness)

final class MaskItemCombinerSemanticsTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func makeR32(
        _ w: Int, _ h: Int, metal: MetalContext, value: (Int, Int) -> Float
    ) throws -> any MTLTexture {
        var pixels = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { pixels[y * w + x] = value(x, y) } }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: d))
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: w * 4)
        }
        return texture
    }

    private func readMask(_ t: any MTLTexture, metal: MetalContext) -> [Float] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        var out = [Float](repeating: 0, count: t.width * t.height)
        out.withUnsafeMutableBytes {
            t.getBytes(
                $0.baseAddress!, bytesPerRow: t.width * 4,
                from: MTLRegionMake2D(0, 0, t.width, t.height), mipmapLevel: 0)
        }
        return out
    }

    private func makeRGBA(
        _ w: Int, _ h: Int, metal: MetalContext, value: Float
    ) throws -> any MTLTexture {
        var pixels = [Float](repeating: value, count: w * h * 4)
        for i in stride(from: 3, to: pixels.count, by: 4) { pixels[i] = 1 }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: d))
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: w * 16)
        }
        return texture
    }

    /// The three-item group: A installs, B/C apply `op` (B at opacity
    /// .85, C inverted — the fold mix rides through the filter). The
    /// `disabled` indices carry enabled = false.
    private func makeGroup(
        forms: [MaskForm], op: MaskCombineOp, disabled: Set<Int>
    ) -> MaskGroupSpec {
        var items = [
            MaskGroupItem(formID: forms[0].id, op: .union, inverted: false, opacity: 1),
            MaskGroupItem(formID: forms[1].id, op: op, inverted: false, opacity: 0.85),
            MaskGroupItem(formID: forms[2].id, op: op, inverted: true, opacity: 1),
        ]
        for index in disabled { items[index].enabled = false }
        return MaskGroupSpec(items: items)
    }

    // MARK: float64 reference (the 06-04 group.c formulas)

    private static func combineRef(
        _ dest: Double, _ src: Double, op: MaskCombineOp,
        inverted: Bool, opacity: Double
    ) -> Double {
        let m = opacity * (inverted ? 1.0 - src : src)
        switch op {
        case .union:
            return max(dest, m)
        case .intersect:
            return min(max(dest, 0), max(m, 0))
        case .difference:
            return (dest > 0 && m > 0) ? dest * (1.0 - m) : dest
        case .sum:
            return min(1.0, dest + m)
        case .exclusion:
            let pos = (dest > 0 && m > 0) ? 1.0 : 0.0
            return pos * max((1.0 - dest) * m, dest * (1.0 - m))
                + (1.0 - pos) * max(dest, m)
        }
    }

    /// The filtered-list reference: the ENABLED items only; index 0 of the
    /// filtered list installs onto the zero seed (the reduce's first-item
    /// semantics ride the FILTERED order).
    private static func reduceRef(
        _ items: [(v: Double, op: MaskCombineOp, inverted: Bool, opacity: Double)]
    ) -> Double {
        var dest = 0.0
        for (index, item) in items.enumerated() {
            dest = combineRef(
                dest, item.v,
                op: index == 0 ? .union : item.op,
                inverted: item.inverted, opacity: item.opacity)
        }
        return dest
    }

    // MARK: 1: the disabled-position matrix (5 op × first/middle/last)

    /// Every disabled position must equal the reference over the ENABLED
    /// subset, per pixel <1e-6 (the filter is exact term-dropping, not an
    /// approximation — the n-ary fold's "does not participate" per op).
    /// The reference folds the ACTUAL per-pixel plane values, so edge
    /// pixels are covered too.
    func testDisabledItemMatrixMatchesTheEnabledOnlyReference() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 64, h = 48
        let mapper = GeometryPointMapper.compose(
            boxes: [], frameSize: SIMD2(Double(w), Double(h)))
        let window = ROI(x: 0, y: 0, width: w, height: h)
        let forms = makeCircleForms()
        var planes: [any MTLTexture] = []
        for form in forms {
            planes.append(try await DrawnMaskRasterizer.singleFormPlane(
                form: form, window: window, mapper: mapper, metal: metal))
        }
        let planeRefs = planes.map { readMask($0, metal: metal) }

        var compared = 0
        for op in [MaskCombineOp.union, .intersect, .difference, .sum, .exclusion] {
            // The item fold face: A installs (union), B/C apply `op`
            // (B at opacity .85, C inverted — the fold mix rides through).
            let fold: [(plane: Int, op: MaskCombineOp, inverted: Bool, opacity: Double)] = [
                (0, .union, false, 1.0), (1, op, false, 0.85), (2, op, true, 1.0),
            ]
            for disabledPosition in [0, 1, 2] {
                let group = makeGroup(forms: forms, op: op, disabled: [disabledPosition])
                let combined = try await MaskCombiner.drawnGroupPlane(
                    group: group, forms: forms, window: window,
                    mapper: mapper, metal: metal)
                let got = readMask(try XCTUnwrap(combined), metal: metal)
                let enabledFold = fold.filter { $0.plane != disabledPosition }
                var violations = 0
                var maxAbs: Float = 0
                for i in 0..<got.count {
                    let refItems = enabledFold.map { item in
                        (v: Double(planeRefs[item.plane][i]), op: item.op,
                         inverted: item.inverted, opacity: item.opacity)
                    }
                    let diff = abs(got[i] - Float(Self.reduceRef(refItems)))
                    if diff >= 1e-6 { violations += 1 }
                    maxAbs = max(maxAbs, diff)
                    compared += 1
                }
                XCTAssertEqual(
                    violations, 0,
                    "op \(op) disabled[\(disabledPosition)]: \(violations) violations " +
                        "(maxAbs \(maxAbs))")
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")
    }

    // MARK: 2: the analytic-area anchors (two circles, closed form)

    /// Closed-form area of the lens-shaped intersection of two circles
    /// (the 06-04 anchor's formula).
    private static func circleIntersectionArea(
        _ a: (c: Double, r: Double), _ b: (c: Double, r: Double)
    ) -> Double {
        let d = hypot(b.c - a.c, 0)
        if d >= a.r + b.r { return 0 }
        if d <= abs(a.r - b.r) { return .pi * pow(min(a.r, b.r), 2) }
        let a1 = pow(a.r, 2) * acos((d * d + pow(a.r, 2) - pow(b.r, 2)) / (2 * d * a.r))
        let a2 = pow(b.r, 2) * acos((d * d + pow(b.r, 2) - pow(a.r, 2)) / (2 * d * b.r))
        let a3 = 0.5 * sqrt(max(
            (-d + a.r + b.r) * (d + a.r - b.r) * (d - a.r + b.r) * (d + a.r + b.r), 0))
        return a1 + a2 - a3
    }

    /// The three-circle subset with plain items (opacity 1, normal): the
    /// thresholded pixel count must match the analytic area of the ENABLED
    /// subset within the discretization bound — a WRONG filter position
    /// deviates by half a circle, two orders beyond the bound. (A
    /// three-item group keeps a REAL op in play after each single
    /// disable: first-disabled leaves B-installs-C-ops, last-disabled
    /// leaves A-installs-B-ops.)
    func testDisabledPositionAnalyticAreaAnchors() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 96, h = 96
        let mapper = GeometryPointMapper.compose(
            boxes: [], frameSize: SIMD2(Double(w), Double(h)))
        let window = ROI(x: 0, y: 0, width: w, height: h)
        let forms = makeCircleForms()
        let rA = 0.20 * Double(w), rB = 0.16 * Double(w), rC = 0.07 * Double(w)
        let areaA = Double.pi * rA * rA
        let areaB = Double.pi * rB * rB, areaC = Double.pi * rC * rC
        // B–C lens (d = 0.12w): the op-bearing pair after A is disabled.
        let lensBC = Self.circleIntersectionArea((0.62 * Double(w), rB), (0.5 * Double(w), rC))
        // A–B lens (the 06-04 geometry): the op-bearing pair after C is disabled.
        let lensAB = Self.circleIntersectionArea((0.38 * Double(w), rA), (0.62 * Double(w), rB))

        func plainGroup(op: MaskCombineOp, disabled: Set<Int>) -> MaskGroupSpec {
            var items = [
                MaskGroupItem(formID: forms[0].id, op: .union, inverted: false, opacity: 1),
                MaskGroupItem(formID: forms[1].id, op: op, inverted: false, opacity: 1),
                MaskGroupItem(formID: forms[2].id, op: op, inverted: false, opacity: 1),
            ]
            for index in disabled { items[index].enabled = false }
            return MaskGroupSpec(items: items)
        }

        for op in [MaskCombineOp.union, .intersect, .difference, .sum, .exclusion] {
            func expectedArea(_ a: Double, _ b: Double, _ lens: Double) -> Double {
                switch op {
                case .union, .sum: return a + b - lens
                case .intersect: return lens
                case .difference: return a - lens
                case .exclusion: return a + b - 2 * lens
                }
            }
            let expectations: [(disabled: Set<Int>, area: Double, bound: Double)] = [
                // First disabled → B installs, C applies the op.
                ([0], expectedArea(areaB, areaC, lensBC), 2.0 * Double.pi * (rB + rC)),
                // Last disabled → A installs, B applies the op.
                ([2], expectedArea(areaA, areaB, lensAB), 2.0 * Double.pi * (rA + rB)),
            ]
            for expected in expectations {
                let plane = try await MaskCombiner.drawnGroupPlane(
                    group: plainGroup(op: op, disabled: expected.disabled),
                    forms: forms, window: window, mapper: mapper, metal: metal)
                let got = readMask(try XCTUnwrap(plane), metal: metal)
                let counted = got.filter { $0 >= 0.5 }.count
                XCTAssertGreaterThan(counted, 0, "\(op) \(expected.disabled): empty — 防空转")
                XCTAssertLessThan(
                    abs(Double(counted) - expected.area), expected.bound,
                    "\(op) disabled\(expected.disabled): counted \(counted) vs analytic " +
                        "\(String(format: "%.1f", expected.area)), bound \(String(format: "%.1f", expected.bound))")
            }
        }
    }

    // MARK: 3: the empty enabled set = the constant-1 passthrough

    /// All items disabled (or a single-item group disabled) resolves NO
    /// plane: drawnGroupPlane returns nil and the full assembly is
    /// BYTE-EXACT the constant-1 plane × layer opacity (the 06-01
    /// degenerate triple's no-form fill-1 channel — every pixel 0.7).
    func testAllDisabledGroupIsTheConstantOnePassthrough() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 32, h = 24
        let mapper = GeometryPointMapper.compose(
            boxes: [], frameSize: SIMD2(Double(w), Double(h)))
        let window = ROI(x: 0, y: 0, width: w, height: h)
        let forms = makeCircleForms()
        let below = try makeRGBA(w, h, metal: metal, value: 0.3)
        let top = try makeRGBA(w, h, metal: metal, value: 0.4)

        func spec(group: MaskGroupSpec) -> MaskSpec {
            MaskSpec(drawn: DrawnMaskSpec(forms: forms, group: group))
        }

        // (a) the whole group disabled → nil plane at the combiner face.
        let allDisabled = makeGroup(forms: forms, op: .difference, disabled: [0, 1, 2])
        let groupPlane = try await MaskCombiner.drawnGroupPlane(
            group: allDisabled, forms: forms, window: window,
            mapper: mapper, metal: metal)
        XCTAssertNil(groupPlane, "an empty enabled set resolves no plane")

        // (b) the full assembly degrades to constant-1 × opacity, byte-exact.
        for group in [allDisabled, makeGroup(forms: forms, op: .union, disabled: [0, 1, 2])] {
            let (plane, reason) = try await MaskCombiner.assembleUnmasked(
                spec: spec(group: group), layerOpacity: 0.7, window: window,
                below: below, top: top, mapper: mapper, metal: metal,
                maskDirectory: nil, rasterStore: RasterMaskStore.self)
            XCTAssertNil(reason)
            let got = readMask(plane, metal: metal)
            XCTAssertEqual(got.count, w * h)
            for value in got {
                XCTAssertEqual(value, 0.7, "constant-1 passthrough must be exact 0.7")
            }
        }

        // (c) a single-item disabled group — same 恒 1 channel.
        let single = MaskGroupSpec(items: [
            MaskGroupItem(formID: forms[0].id, op: .union, inverted: false, opacity: 1,
                          enabled: false),
        ])
        let singlePlane = try await MaskCombiner.drawnGroupPlane(
            group: single, forms: forms, window: window, mapper: mapper, metal: metal)
        XCTAssertNil(singlePlane, "a single disabled item = the empty enabled set")
    }

    // MARK: 4: the group-less drawn path ignores item semantics

    /// A group-less drawn spec (the 06-3 single-form path) has NO items —
    /// maskItems reads [] and the form still renders (no enabled face to
    /// filter; the item semantics never touch this path).
    func testGrouplessDrawnIgnoresItemSemantics() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 48, h = 48
        let mapper = GeometryPointMapper.compose(
            boxes: [], frameSize: SIMD2(Double(w), Double(h)))
        let window = ROI(x: 0, y: 0, width: w, height: h)
        let forms = makeCircleForms()
        let groupless = MaskSpec(drawn: DrawnMaskSpec(forms: forms))
        XCTAssertTrue(groupless.maskItems.isEmpty, "nil group → no items")

        let below = try makeRGBA(w, h, metal: metal, value: 0.3)
        let top = try makeRGBA(w, h, metal: metal, value: 0.4)
        let (plane, reason) = try await MaskCombiner.assembleUnmasked(
            spec: groupless, layerOpacity: 1, window: window,
            below: below, top: top, mapper: mapper, metal: metal,
            maskDirectory: nil, rasterStore: RasterMaskStore.self)
        XCTAssertNil(reason)
        let got = readMask(plane, metal: metal)
        XCTAssertTrue(got.contains { $0 > 0.99 }, "the form still renders")
        XCTAssertTrue(got.contains { $0 < 0.01 }, "…and it is a shaped mask, not fill-1")
    }
}

// MARK: - The record/state face (KD-2 accessors + KD-4 lock; App types)

@MainActor
final class MaskItemSemanticsTests: XCTestCase {

    // MARK: 5: the accessor round-trip (KD-2)

    func testMaskItemsAccessorRoundTrip() {
        let forms = makeCircleForms()
        var spec = MaskSpec(drawn: DrawnMaskSpec(
            forms: forms,
            group: MaskGroupSpec(items: [
                MaskGroupItem(formID: forms[0].id, op: .union, inverted: false, opacity: 1),
                MaskGroupItem(formID: forms[1].id, op: .intersect, inverted: true, opacity: 0.6),
            ])))

        // The read view folds the v5 optionals (nil enabled = true, nil
        // name = derived-at-display) and keeps group order.
        var items = spec.maskItems
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].id, forms[0].id)
        XCTAssertEqual(items[0].enabled, true)
        XCTAssertNil(items[0].name)
        XCTAssertEqual(items[1].opacity, 0.6)
        XCTAssertEqual(items[1].inverted, true)

        // Enabled round-trip + the hash moves with it (the mask-domain
        // fold — D-M2-4-1-2).
        let hashBefore = spec.stableHash()
        spec.setItemEnabled(forms[0].id, false)
        items = spec.maskItems
        XCTAssertEqual(items[0].enabled, false)
        XCTAssertEqual(items[1].enabled, true, "only the addressed item moves")
        XCTAssertNotEqual(spec.stableHash(), hashBefore)

        // Display-name round-trip, including the nil reset.
        spec.setItemDisplayName(forms[1].id, "Sky")
        XCTAssertEqual(spec.maskItems[1].name, "Sky")
        XCTAssertNil(spec.maskItems[0].name, "the untouched item keeps nil")
        spec.setItemDisplayName(forms[1].id, nil)
        XCTAssertNil(spec.maskItems[1].name)

        // Unknown id / group-less spec = the documented silent no-op.
        let untouched = spec
        spec.setItemEnabled(UUID(), false)
        spec.setItemDisplayName(UUID(), "ghost")
        XCTAssertEqual(spec, untouched)

        var bare = MaskSpec()
        bare.setItemEnabled(forms[0].id, false)
        XCTAssertTrue(bare.maskItems.isEmpty)
        XCTAssertFalse(bare.hasAnyPayload)
    }

    // MARK: 6: the display-name derivation consumes the Core single source

    /// The stored name stays nil (the derivation is a DISPLAY fact, never
    /// persisted); the M2-7 panel derives through
    /// `LayerStack.nextLayerName(base:)` — the ONE ordinal/collision
    /// algorithm (M2-4-1 M4; no second copy may appear).
    func testDisplayNameDerivationConsumesCoreSingleSource() {
        let forms = makeCircleForms()
        let spec = MaskSpec(drawn: DrawnMaskSpec(
            forms: forms,
            group: MaskGroupSpec(items: [
                MaskGroupItem(formID: forms[0].id, op: .union, inverted: false, opacity: 1),
            ])))
        XCTAssertTrue(spec.maskItems.allSatisfy { $0.name == nil })

        // The single-source primitive: ordinal = count + 1, swept past
        // collisions.
        var empty = LayerStack(baseLayer: BackgroundLayer())
        XCTAssertEqual(empty.nextLayerName(base: "Mask"), "Mask 1")

        func namedLayer(_ name: String) -> AdjustmentLayer {
            AdjustmentLayer(name: name)
        }
        empty.addAdjustment(namedLayer("Mask 1"))
        empty.addAdjustment(namedLayer("Mask 2"))
        XCTAssertEqual(empty.nextLayerName(base: "Mask"), "Mask 3")
        // The collision sweep: "Mask 2" exists → ordinal 2 skips to 3.
        var sparse = LayerStack(baseLayer: BackgroundLayer())
        sparse.addAdjustment(namedLayer("Mask 2"))
        XCTAssertEqual(sparse.nextLayerName(base: "Mask"), "Mask 3")
    }

    // MARK: 7-9: the deletionProtected lock (clear + fill legs, checker E3)

    private func makeEditorState() -> EditorState {
        let state = EditorState()
        // The structure-commit placeholder needs a NON-EMPTY base/instance
        // set (the MaskCommandTests pattern — without it the commit is a
        // documented silent no-op).
        state.resetHistoryForNewImage(defaultInstances: [
            ModuleInstance(
                module: TestGainModule.self, multiName: "seed",
                params: .init(gain: 1.0))
        ])
        return state
    }

    /// A drawn mask with a group of two items; `protected` stamps the
    /// spec-level lock. Installed through the standard ONE-item commit.
    private func installMask(
        _ editorState: EditorState, on layerID: UUID, protected: Bool
    ) {
        let forms = makeCircleForms()
        var mask = MaskSpec(drawn: DrawnMaskSpec(
            forms: forms,
            group: MaskGroupSpec(items: [
                MaskGroupItem(formID: forms[0].id, op: .union, inverted: false, opacity: 1),
                MaskGroupItem(formID: forms[1].id, op: .intersect, inverted: false, opacity: 1),
            ])))
        mask.deletionProtected = protected
        let live = editorState.adjustmentLayer(id: layerID)!
        live.mask = mask
        editorState.commitLayerEdit(live, label: "test install mask")
    }

    func testDeletionProtectedRejectsClear() throws {
        let editorState = makeEditorState()
        let editingState = LayerEditingState()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        editingState.select(layer.id)
        installMask(editorState, on: layer.id, protected: true)
        let maskBefore = try XCTUnwrap(
            editorState.adjustmentLayer(id: layer.id)).mask
        let items = editorState.history.items.count
        XCTAssertNil(editorState.toast, "clean witness")

        // The clear leg: refused — mask kept, ZERO history item, toast up.
        editingState.performMaskCommand(.clear, editorState: editorState)
        XCTAssertEqual(
            editorState.adjustmentLayer(id: layer.id)?.mask, maskBefore,
            "clear must not touch a locked mask")
        XCTAssertEqual(editorState.history.items.count, items, "zero history item")
        XCTAssertNotNil(editorState.toast, "the refusal surfaces")
    }

    func testDeletionProtectedRejectsFill() throws {
        let editorState = makeEditorState()
        let editingState = LayerEditingState()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        editingState.select(layer.id)
        installMask(editorState, on: layer.id, protected: true)
        let maskBefore = try XCTUnwrap(
            editorState.adjustmentLayer(id: layer.id)).mask
        let items = editorState.history.items.count

        // The fill leg (checker E3's second clearing write — the empty
        // spec is the constant-1 passthrough, content gone all the same):
        // SAME refusal.
        editingState.performMaskCommand(.fill, editorState: editorState)
        XCTAssertEqual(
            editorState.adjustmentLayer(id: layer.id)?.mask, maskBefore,
            "fill must not touch a locked mask")
        XCTAssertEqual(editorState.history.items.count, items, "zero history item")
        XCTAssertNotNil(editorState.toast, "the refusal surfaces")
    }

    func testUnprotectedClearAndFillBehaviorUnchanged() throws {
        let editorState = makeEditorState()
        let editingState = LayerEditingState()
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        editingState.select(layer.id)
        installMask(editorState, on: layer.id, protected: false)
        let items = editorState.history.items.count

        // fill: the empty-spec record lands with exactly ONE history item.
        editingState.performMaskCommand(.fill, editorState: editorState)
        let filled = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id)).mask
        XCTAssertNotNil(filled, "fill keeps a mask record")
        XCTAssertFalse(try XCTUnwrap(filled).hasAnyPayload)
        XCTAssertEqual(editorState.history.items.count, items + 1)
        XCTAssertNil(editorState.toast, "no refusal")

        // clear: the record disappears with exactly ONE history item.
        XCTAssertTrue(editorState.performUndo()) // back to the drawn mask
        editingState.performMaskCommand(.clear, editorState: editorState)
        XCTAssertNil(
            editorState.adjustmentLayer(id: layer.id)?.mask,
            "clear removes the record")
        XCTAssertEqual(editorState.history.items.count, items + 1)
        XCTAssertNil(editorState.toast)
    }
}
