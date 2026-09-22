// Plan 01-04 headless smoke — the no-op pixelpipe vertebra through the
// PUBLIC surface (same paths the app editor + Phase 3+ iop authors use):
//   MetalContext init → IOP metallib registration →
//   PassthroughModule full IOPModule contract (commitParams → paramsHash,
//   buffer→buffer process staging blits, bit-exact no-op) →
//   Layer skeleton structure (LayerStack/BackgroundLayer/BlendMode raw) →
//   RAWDecoder.decode(fixture) → RenderPipeline.render (the public face of
//   the internal PixelPipe; D-03a layerStack installed) → display texture.
// Not part of any build target (per the .work process-files convention).

import Foundation
import LightamerCore
import LightamerIOP
import Metal

let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
nonisolated(unsafe) var failures = 0
nonisolated func check(_ ok: Bool, _ label: String) {
    print("\(ok ? "PASS" : "FAIL")  \(label)")
    if !ok { failures += 1 }
}

let semaphore = DispatchSemaphore(value: 0)
// Top-level code is MainActor-isolated; a plain Task would inherit that
// isolation and deadlock behind the blocking semaphore wait below.
Task.detached {
    defer { semaphore.signal() }
    do {
        // 1. Context init (D-14/D-15)
        let metal = try MetalContext()
        print("device: \(metal.device.name)")
        check(!metal.device.name.isEmpty, "1. MetalContext init (device + queue)")

        // 2. IOP framework metallib registration (RESEARCH §1 #1 gotcha)
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        check(true, "2. IOP default.metallib registered (\(PassthroughKernel.metalBundle.bundleURL.lastPathComponent))")

        // 3. Decode the raster fixture first (same non-RAW entry as the
        //    app) — `reloadDefaults` needs a real DecodedImage.
        let decoder = RAWDecoder()
        let decoded = try await decoder.decode(fixture)
        check((decoded.capture.width ?? 0) > 0,
              "3. RAWDecoder.decode(\(fixture.lastPathComponent)) \(decoded.capture.width ?? -1)x\(decoded.capture.height ?? -1), decoder=\(decoded.decoderVersionUsed.rawValue)")

        // 4. PassthroughModule through the FULL IOPModule contract
        //    (FOUND-03): reloadDefaults → commitParams → paramsHash; ROI
        //    plumbing; process runs the buffer↔texture staging blits +
        //    dispatch2D (buffers bound 0/1) and implies output-buffer
        //    validity on return.
        let module = PassthroughModule()
        let w = 4, h = 2, bpp = WorkingSpace.bytesPerPixel
        var pixels: [Float] = []
        for y in 0..<h { for x in 0..<w { pixels += [Float(x + 1), Float(y + 1), 0.5, 1.0] } }
        let bytes = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        func makeBuffer(_ fill: Data) -> any MTLBuffer {
            let b = metal.device.makeBuffer(length: w * h * bpp, options: .storageModeShared)!
            fill.copyBytes(to: b.contents().assumingMemoryBound(to: UInt8.self), count: fill.count)
            return b
        }
        let inBuf = makeBuffer(bytes)
        let outBuf = makeBuffer(Data(repeating: 0xEE, count: w * h * bpp))

        var piece = IOPiece(dscIn: IOPBufferDesc(width: w, height: h), dscOut: IOPBufferDesc(width: w, height: h))
        let params = await module.reloadDefaults(image: decoded)
        await module.commitParams(params, into: &piece)
        check(piece.paramsHash == params.hashValue, "4a. reloadDefaults/commitParams → piece.paramsHash == params.hashValue")

        var roiOut = ROI(width: w, height: h)
        var roiIn = ROI()
        module.modifyROIOut(&roiOut, input: ROI(width: w, height: h), piece: piece)
        module.modifyROIIn(output: roiOut, input: &roiIn, piece: piece)
        check(roiOut.width == w && roiOut.height == h && roiIn == roiOut,
              "4b. ROI plumbing identity (modifyROIOut/modifyROIIn)")

        try await module.process(input: inBuf, output: outBuf, roiIn: roiIn, roiOut: roiOut, piece: piece, metal: metal)
        let outFloats = outBuf.contents().assumingMemoryBound(to: Float.self)
        let outPixels = [Float](UnsafeBufferPointer(start: outFloats, count: w * h * 4))
        check(outPixels.elementsEqual(pixels) { $0.bitPattern == $1.bitPattern },
              "4c. process buffer→buffer BIT-EXACT no-op (staging blits + dispatch2D)")

        // 5. Layer skeleton structure (D-03a) via the public surface
        let stack = LayerStack(baseLayer: BackgroundLayer())
        check(stack.baseLayer.kind == .background && stack.adjustmentLayers.isEmpty,
              "5a. LayerStack(baseLayer: BackgroundLayer()) — base present, zero adjustments")
        check(BlendMode.normal.rawValue == 1, "5b. BlendMode.normal raw value == 1 (sidecar-stable)")
        let bg = BackgroundLayer()
        check(bg.name == "Background" && bg.isVisible && bg.opacity == 1.0 && bg.enabled,
              "5c. BackgroundLayer LAYER-01 defaults")

        // 6. THE VERTEBRA: decode → RenderPipeline.render (internal
        //    PixelPipe, layerStack installed) → display texture.
        let texture = try await RenderPipeline.render(image: decoded, layerStack: stack, metal: metal)
        check(texture.width == decoded.capture.width && texture.height == decoded.capture.height,
              "6a. pixelpipe output size \(texture.width)x\(texture.height) == decoded extent")
        check(texture.pixelFormat == WorkingSpace.pixelFormat,
              "6b. pixelpipe output format .rgba32Float (FOUND-02)")
        let drain = metal.commandQueue.makeCommandBuffer()!
        drain.commit()
        _ = await drain.completed()
        var probe = [Float](repeating: 0, count: 4)
        texture.getBytes(&probe, bytesPerRow: texture.width * bpp,
                         from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
        check(probe.allSatisfy { $0.isFinite },
              "6c. pixelpipe output pixels finite (row0 col0: \(probe.map { String(format: "%.3f", $0) }.joined(separator: ",")))")

        // 7. nil-layerStack tolerance: the pipe installs a default
        //    BackgroundLayer stack (D-03a invariant).
        let texture2 = try await RenderPipeline.render(image: decoded, layerStack: nil, metal: metal)
        check(texture2.width == decoded.capture.width && texture2.height == decoded.capture.height,
              "7. nil layerStack → pipe installs default BackgroundLayer, still renders")

        print(failures == 0 ? "SMOKE PASS" : "SMOKE FAIL (\(failures))")
        exit(failures == 0 ? 0 : 1)
    } catch {
        print("SMOKE ERROR: \(error)")
        exit(2)
    }
}

struct SmokeError: Error { let message: String; init(_ m: String) { message = m } }
semaphore.wait()
