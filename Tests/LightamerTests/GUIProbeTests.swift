@testable import LightamerCore
@testable import Lightamer
@testable import LightamerIOP
import CoreImage
import Foundation
import Metal
import XCTest

// GUIProbeTests (Plan 04-06-T1) — GUI-1 判别探针，只诊断不修复。
//
// 背景：真实 GUI 验收（Debug 产物 + input/RAW/DSC00012.ARW）视口近全黑，
// 而管线单测全绿。管线 Core 层只被 trio-only 链证明过；app 真实 seed 链
// （terminal trio + 全部 tone/geometory/detail 默认实例 ENABLED，其中
// sigmoid/filmic/agx 三个 filmic-style 曲线同时启用）从未端到端验证过。
//
// 方法（plan T1 的 in-process 实现——不污染 app 源码，零常驻探针）：
// coordinator.load 走 app 真实路径（pristine seed → rematerialize →
// recommitColoroutForDisplay → renderPreview → displayTexture），再用
// RenderPipeline 直接跑消融链（trio-only / trio+单个 tone 模块），同
// imageID + 同 cache（input 平面共享）。L014：每次读回前 fence。
//
// 判别表：
// - displayTexture.pixelFormat == .bgra8Unorm ⟹ gamma tail 到达显示腿
//   （tail policy：top-enabled 是 gamma 才分配 bgra8；float32 = gamma
//   缺失/disabled → 候选 a/b）。
// - trio-only 亮 vs 全 seed 黑 ⟹ tone 栈叠加压黑（候选 d，app 层 seed
//   使能问题，Core 零改动）。
// - 单模块消融列 pinpoint 压黑贡献者。
// - 去 gamma 线性链中心/均值 ⟹ CIRAW 输出域合理性（候选 c）。
final class GUIProbeTests: XCTestCase {

    private static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Tests/LightamerTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root

    private var metal: MetalContext!

    override func setUp() async throws {
        try await super.setUp()
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal GPU") }
        metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
    }

    private func drain() {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    /// bgra8 平面统计：均值/中心/四角/<16 占比/≥128 占比。
    private func statsBGRA8(_ texture: any MTLTexture) -> String {
        let w = texture.width, h = texture.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: w * 4,
                from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0
            )
        }
        func px(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
            let i = (y * w + x) * 4
            return (bytes[i + 2], bytes[i + 1], bytes[i]) // BGRA → RGB
        }
        var sumR = 0, sumG = 0, sumB = 0
        var dark = 0, bright = 0
        let n = w * h
        for i in 0..<n {
            let r = Int(bytes[i * 4 + 2]), g = Int(bytes[i * 4 + 1]), b = Int(bytes[i * 4])
            sumR += r; sumG += g; sumB += b
            let lum = (r + g + b) / 3
            if lum < 16 { dark += 1 }
            if lum >= 128 { bright += 1 }
        }
        let c = px(w / 2, h / 2)
        let tl = px(0, 0), tr = px(w - 1, 0), bl = px(0, h - 1), br = px(w - 1, h - 1)
        return String(format:
            "mean=(%d,%d,%d) center=(%d,%d,%d) TL=(%d,%d,%d) TR=(%d,%d,%d) BL=(%d,%d,%d) BR=(%d,%d,%d) <16=%.1f%% >=128=%.1f%%",
            sumR / n, sumG / n, sumB / n,
            c.0, c.1, c.2, tl.0, tl.1, tl.2, tr.0, tr.1, tr.2,
            bl.0, bl.1, bl.2, br.0, br.1, br.2,
            100.0 * Double(dark) / Double(n), 100.0 * Double(bright) / Double(n))
    }

    /// float32 线性平面统计：均值/中心（候选 c 域证据）。
    private func statsFloat(_ texture: any MTLTexture) -> String {
        let w = texture.width, h = texture.height
        var floats = [Float](repeating: 0, count: w * h * 4)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: w * 16,
                from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0
            )
        }
        var sum = SIMD3<Double>.zero
        let n = w * h
        for i in 0..<n {
            sum += SIMD3<Double>(Double(floats[i * 4]), Double(floats[i * 4 + 1]), Double(floats[i * 4 + 2]))
        }
        let mean = sum / Double(n)
        let ci = ((h / 2) * w + w / 2) * 4
        return String(format: "mean=(%.4f,%.4f,%.4f) center=(%.4f,%.4f,%.4f)",
            mean.x, mean.y, mean.z, floats[ci], floats[ci + 1], floats[ci + 2])
    }

    @MainActor
    func testGUI1Discriminate() async throws {
        let arw = Self.repoRoot.appendingPathComponent("input/RAW/DSC00012.ARW")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: arw.path), "DSC00012.ARW missing")
        var lines: [String] = []
        func log(_ s: String) { lines.append(s); print("GUI1PROBE " + s) }

        // ── 真实 CIRAW 解码 ──
        let decoder = RAWDecoder()
        let decoded = try await decoder.decode(arw)
        let ex = decoded.ciImage.extent
        log("decode: extent=\(Int(ex.width))x\(Int(ex.height)) decoder=\(decoded.decoderVersionUsed)")

        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let imageID = UUID()
        let cache = PipeCache()
        let longEdge = 760 // 速度 ladder 档；域结论与 scale 无关

        // ── A. app 真实路径：coordinator.load（pristine seed 全链）──
        let editorState = EditorState()
        let coordinator = PipeCoordinator()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        coordinator.attach(registry: registry)
        let probeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gui1probe-\(UUID().uuidString).exr")
        await coordinator.load(url: probeURL, decoded: decoded, instances: [], metal: metal)
        guard let display = editorState.displayTexture else {
            log("A full-seed displayTexture=NIL (render failed — see log)")
            XCTFail("displayTexture nil")
            return
        }
        drain()
        let fmtName = display.pixelFormat == .bgra8Unorm ? "bgra8Unorm" : "FORMAT=\(display.pixelFormat.rawValue)"
        log("A full-seed displayTexture: \(display.width)x\(display.height) \(fmtName)")
        if display.pixelFormat == .bgra8Unorm {
            log("A full-seed pixels: " + statsBGRA8(display))
        } else {
            log("A full-seed pixels(f32): " + statsFloat(display))
        }
        let seedOps = editorState.instances.map { "\($0.opName):\($0.enabled ? "on" : "OFF")" }.joined(separator: " ")
        log("A seed instances (\(editorState.instances.count)): " + seedOps)
        log("host DisplayProfile.current=\(DisplayProfile.current().label)")

        // ── 消融链：同 imageID + 同 cache（input 平面共享）──
        func runChain(_ boxes: [any ModuleBoxing], tag: String) async throws {
            let (tex, _) = try await RenderPipeline.process(
                image: decoded, instances: boxes, imageID: imageID,
                resolution: .preview, cache: cache, metal: metal, longEdge: longEdge)
            drain()
            let f = tex.pixelFormat == .bgra8Unorm ? "bgra8" : "f32(\(tex.pixelFormat.rawValue))"
            if tex.pixelFormat == .bgra8Unorm {
                log("\(tag) \(tex.width)x\(tex.height) \(f): " + statsBGRA8(tex))
            } else {
                log("\(tag) \(tex.width)x\(tex.height) \(f): " + statsFloat(tex))
            }
        }

        // B. trio-only（Core 已证正确的基准）
        let trio = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .displayP3)
        try await runChain(trio, tag: "B trio-only")

        // C. 去 gamma 线性链（候选 c：CIRAW 输出域证据）
        let linearChain = trio.filter { $0.opName != GammaModule.opName }
        try await runChain(linearChain, tag: "C trio-no-gamma")

        // D–G. 单模块消融：trio + 单个 tone 默认实例（concrete 逐模块展开；
        // 泛型 local func 的 M.Params 无 Sendable 已知性，region-isolation
        // 报错——concrete Params 均为 Sendable struct，直传合法）
        do {
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            let made = await registry.makeBox(opName: SigmoidModule.opName)
            let box = try XCTUnwrap(made as? ModuleBox<SigmoidModule>)
            await box.setParams(SigmoidModule.Params())
            chain.append(box)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "D trio+sigmoid")
        }
        do {
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            let made = await registry.makeBox(opName: FilmicRGBModule.opName)
            let box = try XCTUnwrap(made as? ModuleBox<FilmicRGBModule>)
            await box.setParams(FilmicRGBModule.Params())
            chain.append(box)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "E trio+filmic")
        }
        do {
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            let made = await registry.makeBox(opName: AgXModule.opName)
            let box = try XCTUnwrap(made as? ModuleBox<AgXModule>)
            await box.setParams(AgXModule.Params())
            chain.append(box)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "F trio+agx")
        }
        do {
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            let made = await registry.makeBox(opName: ShadhiModule.opName)
            let box = try XCTUnwrap(made as? ModuleBox<ShadhiModule>)
            await box.setParams(ShadhiModule.Params())
            chain.append(box)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "G trio+shadhi")
        }
        // I–K. 双组合：sigmoid/filmic/agx 两两叠加是否互压黑（concrete 展开）
        do {
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            let m1 = await registry.makeBox(opName: SigmoidModule.opName)
            let b1 = try XCTUnwrap(m1 as? ModuleBox<SigmoidModule>)
            await b1.setParams(SigmoidModule.Params())
            chain.append(b1)
            let m2 = await registry.makeBox(opName: FilmicRGBModule.opName)
            let b2 = try XCTUnwrap(m2 as? ModuleBox<FilmicRGBModule>)
            await b2.setParams(FilmicRGBModule.Params())
            chain.append(b2)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "I trio+sigmoid+filmic")
        }
        do {
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            let m1 = await registry.makeBox(opName: SigmoidModule.opName)
            let b1 = try XCTUnwrap(m1 as? ModuleBox<SigmoidModule>)
            await b1.setParams(SigmoidModule.Params())
            chain.append(b1)
            let m2 = await registry.makeBox(opName: AgXModule.opName)
            let b2 = try XCTUnwrap(m2 as? ModuleBox<AgXModule>)
            await b2.setParams(AgXModule.Params())
            chain.append(b2)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "J trio+sigmoid+agx")
        }
        do {
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            let m1 = await registry.makeBox(opName: FilmicRGBModule.opName)
            let b1 = try XCTUnwrap(m1 as? ModuleBox<FilmicRGBModule>)
            await b1.setParams(FilmicRGBModule.Params())
            chain.append(b1)
            let m2 = await registry.makeBox(opName: AgXModule.opName)
            let b2 = try XCTUnwrap(m2 as? ModuleBox<AgXModule>)
            await b2.setParams(AgXModule.Params())
            chain.append(b2)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "K trio+filmic+agx")
        }
        do {
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            let m1 = await registry.makeBox(opName: SigmoidModule.opName)
            let b1 = try XCTUnwrap(m1 as? ModuleBox<SigmoidModule>)
            await b1.setParams(SigmoidModule.Params())
            chain.append(b1)
            let m2 = await registry.makeBox(opName: FilmicRGBModule.opName)
            let b2 = try XCTUnwrap(m2 as? ModuleBox<FilmicRGBModule>)
            await b2.setParams(FilmicRGBModule.Params())
            chain.append(b2)
            let m3 = await registry.makeBox(opName: AgXModule.opName)
            let b3 = try XCTUnwrap(m3 as? ModuleBox<AgXModule>)
            await b3.setParams(AgXModule.Params())
            chain.append(b3)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "L trio+3filmic-stack")
        }
        // H. 全 seed 链经 RenderPipeline（与 A 同链，验证路径一致性）
        var fullChain: [any ModuleBoxing] = []
        for record in editorState.instances {
            let made = await registry.makeBox(opName: record.opName, instanceID: record.id)
            let box = try XCTUnwrap(made, "no box for \(record.opName)")
            try await box.apply(record)
            fullChain.append(box)
        }
        try await runChain(fullChain, tag: "H full-seed-via-pipe")
        // M–R. bisect：每次 +2 个模块逼近压黑 contributors
        do { // M: trio + toneequal/shadhi/colisa 默认
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            let m1 = await registry.makeBox(opName: ToneEqualModule.opName)
            let b1 = try XCTUnwrap(m1 as? ModuleBox<ToneEqualModule>)
            await b1.setParams(ToneEqualModule.Params())
            chain.append(b1)
            let m2 = await registry.makeBox(opName: ShadhiModule.opName)
            let b2 = try XCTUnwrap(m2 as? ModuleBox<ShadhiModule>)
            await b2.setParams(ShadhiModule.Params())
            chain.append(b2)
            let m3 = await registry.makeBox(opName: ColisaModule.opName)
            let b3 = try XCTUnwrap(m3 as? ModuleBox<ColisaModule>)
            await b3.setParams(ColisaModule.Params())
            chain.append(b3)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "M trio+toneeq+shadhi+colisa")
        }
        do { // N: trio + 温度/曝光/tonecurve/levels 默认
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            let m1 = await registry.makeBox(opName: TemperatureModule.opName)
            let b1 = try XCTUnwrap(m1 as? ModuleBox<TemperatureModule>)
            await b1.setParams(TemperatureModule.Params())
            chain.append(b1)
            let m2 = await registry.makeBox(opName: ExposureModule.opName)
            let b2 = try XCTUnwrap(m2 as? ModuleBox<ExposureModule>)
            await b2.setParams(ExposureModule.Params())
            chain.append(b2)
            let m3 = await registry.makeBox(opName: ToneCurveModule.opName)
            let b3 = try XCTUnwrap(m3 as? ModuleBox<ToneCurveModule>)
            await b3.setParams(ToneCurveModule.Params())
            chain.append(b3)
            let m4 = await registry.makeBox(opName: LevelsModule.opName)
            let b4 = try XCTUnwrap(m4 as? ModuleBox<LevelsModule>)
            await b4.setParams(LevelsModule.Params())
            chain.append(b4)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "N trio+temp+expo+tcurve+levels")
        }
        do { // O: trio + 三 filmic 栈 + shadhi（验证叠加是否坍缩）
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            let m1 = await registry.makeBox(opName: SigmoidModule.opName)
            let b1 = try XCTUnwrap(m1 as? ModuleBox<SigmoidModule>)
            await b1.setParams(SigmoidModule.Params())
            chain.append(b1)
            let m2 = await registry.makeBox(opName: FilmicRGBModule.opName)
            let b2 = try XCTUnwrap(m2 as? ModuleBox<FilmicRGBModule>)
            await b2.setParams(FilmicRGBModule.Params())
            chain.append(b2)
            let m3 = await registry.makeBox(opName: AgXModule.opName)
            let b3 = try XCTUnwrap(m3 as? ModuleBox<AgXModule>)
            await b3.setParams(AgXModule.Params())
            chain.append(b3)
            let m4 = await registry.makeBox(opName: ShadhiModule.opName)
            let b4 = try XCTUnwrap(m4 as? ModuleBox<ShadhiModule>)
            await b4.setParams(ShadhiModule.Params())
            chain.append(b4)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "O trio+3stack+shadhi")
        }
        do { // P: trio + 全 seed 除三 filmic（反证：去掉三栈是否回亮）
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            for record in editorState.instances where record.enabled
                && record.opName != SigmoidModule.opName
                && record.opName != FilmicRGBModule.opName
                && record.opName != AgXModule.opName
                && record.opName != ColorInModule.opName
                && record.opName != ColorOutModule.opName
                && record.opName != GammaModule.opName {
                let made = await registry.makeBox(opName: record.opName, instanceID: record.id)
                let box = try XCTUnwrap(made, "no box for \(record.opName)")
                try await box.apply(record)
                chain.append(box)
            }
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "P full-minus-3stack")
        }
        do { // Q1: trio + 几何栈 lens/ashift/flip/crop
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            let m1 = await registry.makeBox(opName: LensModule.opName)
            let b1 = try XCTUnwrap(m1 as? ModuleBox<LensModule>)
            await b1.setParams(LensModule.Params())
            let m2 = await registry.makeBox(opName: AshiftModule.opName)
            let b2 = try XCTUnwrap(m2 as? ModuleBox<AshiftModule>)
            await b2.setParams(AshiftModule.Params())
            chain.append(b2)
            let m3 = await registry.makeBox(opName: FlipModule.opName)
            let b3 = try XCTUnwrap(m3 as? ModuleBox<FlipModule>)
            await b3.setParams(FlipModule.Params(orientation: .none))
            chain.append(b3)
            let m4 = await registry.makeBox(opName: CropModule.opName)
            let b4 = try XCTUnwrap(m4 as? ModuleBox<CropModule>)
            await b4.setParams(CropModule.Params())
            chain.append(b4)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "Q1 trio+lens+ashift+flip+crop")
        }
        do { // Q2: trio + detail 栈 equalizer/sharpen/bilat
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            let m1 = await registry.makeBox(opName: EqualizerModule.opName)
            let b1 = try XCTUnwrap(m1 as? ModuleBox<EqualizerModule>)
            await b1.setParams(EqualizerModule.Params())
            chain.append(b1)
            let m2 = await registry.makeBox(opName: SharpenModule.opName)
            let b2 = try XCTUnwrap(m2 as? ModuleBox<SharpenModule>)
            await b2.setParams(SharpenModule.Params())
            chain.append(b2)
            let m3 = await registry.makeBox(opName: LocalContrastModule.opName)
            let b3 = try XCTUnwrap(m3 as? ModuleBox<LocalContrastModule>)
            await b3.setParams(LocalContrastModule.Params())
            chain.append(b3)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "Q2 trio+equalizer+sharpen+bilat")
        }
        do { // Q3: trio + lens ONLY（几何栈二分 1/4）
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            let m1 = await registry.makeBox(opName: LensModule.opName)
            let b1 = try XCTUnwrap(m1 as? ModuleBox<LensModule>)
            await b1.setParams(LensModule.Params())
            chain.append(b1)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "Q3 trio+lens-only")
        }
        do { // Q4: trio + ashift ONLY
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            let m1 = await registry.makeBox(opName: AshiftModule.opName)
            let b1 = try XCTUnwrap(m1 as? ModuleBox<AshiftModule>)
            await b1.setParams(AshiftModule.Params())
            chain.append(b1)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "Q4 trio+ashift-only")
        }
        do { // Q5: trio + flip/crop ONLY
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            let m1 = await registry.makeBox(opName: FlipModule.opName)
            let b1 = try XCTUnwrap(m1 as? ModuleBox<FlipModule>)
            await b1.setParams(FlipModule.Params(orientation: .none))
            chain.append(b1)
            let m2 = await registry.makeBox(opName: CropModule.opName)
            let b2 = try XCTUnwrap(m2 as? ModuleBox<CropModule>)
            await b2.setParams(CropModule.Params())
            chain.append(b2)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "Q5 trio+flip+crop")
        }
        do { // Q6: trio + crop ONLY（几何栈二分：crop 单独）
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            let m1 = await registry.makeBox(opName: CropModule.opName)
            let b1 = try XCTUnwrap(m1 as? ModuleBox<CropModule>)
            await b1.setParams(CropModule.Params())
            chain.append(b1)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "Q6 trio+crop-only")
        }
        do { // Q7: trio + flip ONLY
            var chain = await TerminalTrioTests.makeCommittedDefaultChain(
                registry: registry, outputProfile: .displayP3)
            let m1 = await registry.makeBox(opName: FlipModule.opName)
            let b1 = try XCTUnwrap(m1 as? ModuleBox<FlipModule>)
            await b1.setParams(FlipModule.Params(orientation: .none))
            chain.append(b1)
            chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            try await runChain(chain, tag: "Q7 trio+flip-only")
        }

        // ── 落盘证据 ──
        let dir = Self.repoRoot.appendingPathComponent(".work/04-06", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let md = "# GUI-1 判别探针（\(Date()))\n\nDSC00012.ARW，经 coordinator.load 真实路径 + RenderPipeline 消融。\n\n```\n"
            + lines.joined(separator: "\n") + "\n```\n"
        try? md.write(to: dir.appendingPathComponent("probe-gui1.md"), atomically: true, encoding: .utf8)

        // ── 弱门：探针只诊断不断言因果 ──
        XCTAssertEqual(display.pixelFormat, GammaModule.outputPixelFormat,
            "tail policy：top-enabled gamma ⇒ displayTexture 必须是 bgra8（否则候选 a/b 成立）")
        XCTAssertGreaterThan(display.width, 0)
    }
}
