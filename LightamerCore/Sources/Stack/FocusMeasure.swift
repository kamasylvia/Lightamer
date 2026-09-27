import Foundation
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// FocusMeasure (Plan 08-3 T1; RESEARCH §5.1/§5.4) — the SML focus-measure
// leg: one decoded float32 RGBA plane → its per-pixel quality map (half).
//
//   ML(x,y)  = |2f − f(x−1) − f(x+1)| + |2f − f(y−1) − f(y+1)|   (f = luma)
//   SML(x,y) = Σ over the 3×3 window of ML²
//
// The P5 probe separated true defocus proxies by 59× (sharp/blurred SML)
// at 1.5 ns/px → ≈0.15 s/source @100MP; the kernel form is `focus_sml`
// (StackKernels.metal — formula mirrored by the tests' float64 reference).
//
// SUBMISSION + READBACK DISCIPLINE (the plan's L031/L014 red lines):
//   • L031 posture — the kernel rides the STACK MERGE SERVICE's own
//     dedicated MTLCommandQueue (the self-contained domain 08-1 built;
//     `queue` is a parameter and production passes ONLY `mergeQueue`).
//     Routing through a MetalContext would submit onto the editor/export
//     queues — exactly the cross-queue race the unique-routing red line
//     forbids — so this file is the domain's ONE submission point instead
//     (D-08-3-T1-2).
//   • L014 drain — the producing command buffer is committed and WAITED
//     (`waitUntilCompleted`) before the CPU touches the output buffer.
//     An async `completed()` callback or an unwaited read races the GPU
//     (the quality-map readback is this plan's high-frequency read path).
//     FocusStackTests pins correctness under a loaded queue AND, via the
//     test-only `spinIterations` knob, the stale-read race itself.
// ─────────────────────────────────────────────────────────────────────────────

public enum FocusMeasure {

    /// The focus-measure operator (D-08-CONTEXT-2 Reversibility — the
    /// operator is swappable; v1 implements ONLY the SML math, the second
    /// case is the additive dispatch slot).
    public enum Operator: String, Sendable, CaseIterable {
        /// Modified-Laplacian magnitude sum (the implemented operator).
        case modifiedLaplacian
        /// Sobel-magnitude energy — the ADDITIVE SLOT ONLY (v2; requesting
        /// it throws `notImplemented`, no second-operator math exists).
        case tenengrad
    }

    /// Must mirror `FocusSMLParams` in StackKernels.metal (the buffer(2)
    /// layout: four packed uint32 scalars).
    private struct KernelParams {
        var width: UInt32
        var height: UInt32
        var spin: UInt32
        var pad: UInt32 = 0
    }

    // MARK: - PSO (per-device cache — the service domain mints its own)

    private static let psoLock = NSLock()
    /// Guarded by `psoLock` (the `nonisolated(unsafe)` escape is the locked
    /// global-state posture — every access below pairs with the lock).
    private nonisolated(unsafe) static var psoCache:
        [ObjectIdentifier: any MTLComputePipelineState] = [:]

    private static func pso(for device: any MTLDevice) throws -> any MTLComputePipelineState {
        let key = ObjectIdentifier(device)
        psoLock.lock()
        if let cached = psoCache[key] {
            psoLock.unlock()
            return cached
        }
        psoLock.unlock()
        guard let library = try? device.makeDefaultLibrary(
            bundle: Bundle(for: MetalContextMarker.self)),
            let function = library.makeFunction(name: "focus_sml"),
            let state = try? device.makeComputePipelineState(function: function)
        else {
            AppError.logger.error("focus_sml PSO creation failed")
            throw AppError.metalDeviceUnavailable
        }
        psoLock.lock()
        psoCache[key] = state
        psoLock.unlock()
        return state
    }

    // MARK: - The quality map

    /// Compute the SML quality map of one full-frame RGBA float32 plane.
    ///
    /// - Parameters:
    ///   - plane: the decoded plane (row-major RGBA float32, tight or
    ///     strided rows — `bytesPerRow` in BYTES).
    ///   - device/queue: the CALLER'S domain (production = the
    ///     StackMergeService's dedicated device+queue; the self-contained
    ///     GPU domain — see the L031 header note).
    ///   - op: the measure operator (v1 = `.modifiedLaplacian` only).
    ///   - spinIterations: TEST-ONLY stall per thread (the no-drain race
    ///     demonstrator; always 0 in production).
    /// - Returns: the W×H map as raw half bits (`UInt16`), row-major —
    ///   the staged quality-file format (band-streamed consumption never
    ///   widens it; research §5.4 half-storage verdict).
    public static func qualityMap(
        plane: UnsafeRawBufferPointer, width: Int, height: Int,
        bytesPerRow: Int, device: any MTLDevice, queue: any MTLCommandQueue,
        op: Operator = .modifiedLaplacian,
        spinIterations: UInt32 = 0,
        waitsCompletion: Bool = true
    ) throws -> [UInt16] {
        guard op == .modifiedLaplacian else {
            // The additive dispatch slot — NO second-operator math exists.
            throw AppError.notImplemented(
                "tenengrad focus operator (additive slot, not implemented in v1)")
        }
        guard width >= 1, height >= 1, plane.count >= height * bytesPerRow else {
            throw AppError.invalidParameter(
                "focus measure: bad plane \(width)×\(height) row \(bytesPerRow)B")
        }
        guard let output = device.makeBuffer(
            length: width * height * MemoryLayout<UInt16>.size,
            options: .storageModeShared)
        else { throw AppError.metalDeviceUnavailable }
        try dispatch(
            into: output, plane: plane, width: width, height: height,
            bytesPerRow: bytesPerRow, device: device, queue: queue,
            spinIterations: spinIterations, waitsCompletion: waitsCompletion)
        let bits = output.contents().bindMemory(to: UInt16.self, capacity: width * height)
        return Array(UnsafeBufferPointer(start: bits, count: width * height))
    }

    /// The dispatch leg shared by both faces (INTERNAL — the no-drain race
    /// demonstrator reuses ONE caller-provided output buffer so the stale
    /// read observes the PREVIOUS dispatch's map; production never passes
    /// `waitsCompletion: false`).
    static func dispatch(
        into output: any MTLBuffer, plane: UnsafeRawBufferPointer,
        width: Int, height: Int, bytesPerRow: Int,
        device: any MTLDevice, queue: any MTLCommandQueue,
        spinIterations: UInt32, waitsCompletion: Bool
    ) throws {
        guard width >= 1, height >= 1, plane.count >= height * bytesPerRow else {
            throw AppError.invalidParameter(
                "focus measure: bad plane \(width)×\(height) row \(bytesPerRow)B")
        }
        guard let input = device.makeBuffer(
            length: height * bytesPerRow, options: .storageModeShared)
        else { throw AppError.metalDeviceUnavailable }
        // The plane rows → the kernel's TIGHT-row layout (row-by-row copy;
        // the source stride may differ from width*16).
        let sourceRowBytes = width * 16
        if bytesPerRow == sourceRowBytes {
            input.contents().copyMemory(
                from: plane.baseAddress!, byteCount: height * bytesPerRow)
        } else {
            for row in 0..<height {
                input.contents()
                    .advanced(by: row * sourceRowBytes)
                    .copyMemory(
                        from: plane.baseAddress!.advanced(by: row * bytesPerRow),
                        byteCount: sourceRowBytes)
            }
        }

        let state = try pso(for: device)
        var params = KernelParams(
            width: UInt32(width), height: UInt32(height), spin: spinIterations)
        guard let paramBuffer = device.makeBuffer(
            length: MemoryLayout<KernelParams>.stride, options: .storageModeShared)
        else { throw AppError.metalDeviceUnavailable }
        withUnsafeBytes(of: &params) { raw in
            paramBuffer.contents().copyMemory(
                from: raw.baseAddress!, byteCount: raw.count)
        }

        // THE L031/L014 shape: ONE command buffer on the caller's dedicated
        // queue → encode → commit → WAIT (the drain) → only then read.
        guard let commandBuffer = queue.makeCommandBuffer() else {
            throw AppError.metalDeviceUnavailable
        }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw AppError.metalDeviceUnavailable
        }
        encoder.setComputePipelineState(state)
        encoder.setBuffer(input, offset: 0, index: 0)
        encoder.setBuffer(output, offset: 0, index: 1)
        encoder.setBuffer(paramBuffer, offset: 0, index: 2)
        let groupWidth = min(state.threadExecutionWidth, max(width, 1))
        let groupHeight = min(
            state.maxTotalThreadsPerThreadgroup / state.threadExecutionWidth,
            max(height, 1))
        let groups = MTLSize(
            width: (width + groupWidth - 1) / groupWidth,
            height: (height + groupHeight - 1) / groupHeight,
            depth: 1)
        encoder.dispatchThreadgroups(
            groups, threadsPerThreadgroup: MTLSize(
                width: groupWidth, height: groupHeight, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        // THE L014 DRAIN — the read below is legal only after this returns
        // (the tests demonstrate the stale race this wait eliminates).
        // `waitsCompletion == false` is the TEST-ONLY negative-control arm
        // (the race demonstrator; production never passes it).
        if waitsCompletion {
            commandBuffer.waitUntilCompleted()
        }
    }

    // MARK: - The CPU reference (the tests' float64 twin + the degenerate
    // fallback when Metal is unavailable)

    /// Float32 CPU mirror of `focus_sml` (the test golden's reference form;
    /// the kernel's clamp-to-edge and window are reproduced exactly).
    public static func qualityMapCPU(
        _ plane: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int
    ) -> [Float] {
        let floatsPerRow = bytesPerRow / 4
        func luma(_ x: Int, _ y: Int) -> Float {
            let cx = max(0, min(x, width - 1))
            let cy = max(0, min(y, height - 1))
            let base = (cy * floatsPerRow + cx * 4)
            let row = plane.bindMemory(to: Float.self)
            return 0.2126 * row[base] + 0.7152 * row[base + 1] + 0.0722 * row[base + 2]
        }
        func ml(_ x: Int, _ y: Int) -> Float {
            let c = luma(x, y)
            let horizontal = abs(2 * c - luma(x - 1, y) - luma(x + 1, y))
            let vertical = abs(2 * c - luma(x, y - 1) - luma(x, y + 1))
            return horizontal + vertical
        }
        var result = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        // Clamp the WINDOW position first (the kernel's
                        // exact walk — the phantom edge position does NOT
                        // evaluate its own vanished-gradient ML).
                        let sx = max(0, min(x + dx, width - 1))
                        let sy = max(0, min(y + dy, height - 1))
                        let value = ml(sx, sy)
                        sum += value * value
                    }
                }
                result[y * width + x] = sum
            }
        }
        return result
    }
}
