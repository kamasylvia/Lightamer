import CoreImage
import Metal
import os

/// The Metal dispatch framework (D-14..D-19 — public cross-module contract;
/// iops in LightamerIOP call `dispatch2D`, the app reads `device`).
///
/// Design locks:
/// - **D-14** device = `MTLCreateSystemDefaultDevice()` (Apple Silicon UMA GPU).
/// - **D-15** single `MTLCommandQueue`. Declared `nonisolated let` — immutable
///   by construction, which is the `private(set)` seam shape: Phase 11 adds a
///   second low-priority export queue as a NEW property, never by reassigning
///   this one.
/// - **D-16** lazy + memory PSO cache keyed on `PSOKey`, LRU-bounded at 256
///   entries (RESEARCH Open Question #3).
/// - **D-17** function-constants via `makeFunction(name:constantValues:)`;
///   `makeConstants`/`setConstant` mirror the `[[function_constant(N)]]`
///   indices (RESEARCH §3 gotcha: ALL declared constants must be set).
/// - **D-18** typed `throws` — `MetalError` (bridged to `AppError` at the
///   `AppError`-facing facade `renderToTexture`).
/// - **D-19** two-layer dispatch: high-level `dispatch2D`/`dispatch2DTexture`
///   for simple iops; low-level `makeEncoder` for fine control (tiling, Phase 2).
///
/// Isolation model (D-33): the ACTOR protects the only mutable state — the
/// PSO cache and the registered libraries. The dispatch methods themselves
/// are `nonisolated`: Metal buffers/textures/command buffers stay in the
/// caller's isolation region (Metal objects are thread-safe for read-only
/// cross-thread use; encoding is single-threaded by contract), and the only
/// actor hop is the PSO-cache lookup. This is what lets iops reuse their
/// working buffers across sequential `dispatch2D` calls without ownership
/// transfers.
///
/// Ownership (RESEARCH Open Question #2): owned by `LightamerApp` via `@State`
/// and injected into the render path — NOT a singleton.
///
/// Metallib resolution (RESEARCH §1 gotcha #1 — the #1 cross-module Metal
/// bug): a framework target's `default.metallib` lives in the FRAMEWORK
/// bundle, not `Bundle.main`. Core's own library is resolved via
/// `Bundle(for: MetalContextMarker.self)`. Kernel-owning modules register
/// their metallibs through `registerDefaultLibrary(in:)`; function lookup
/// walks Core's library first, then registered ones in registration order.
public actor MetalContext {

    // D-14: the default GPU. `nonisolated let` — immutable and thread-safe,
    // readable synchronously from any isolation (e.g. SwiftUI view bodies).
    public nonisolated let device: any MTLDevice

    // D-15: single queue; Phase 11 export queue is an additional property.
    public nonisolated let commandQueue: any MTLCommandQueue

    /// Core's default library (first) + libraries registered by kernel-owning
    /// modules (LightamerIOP now, later targets). Empty list is valid: Core
    /// ships no kernels in Phase 1, so its metallib is absent by design.
    private var libraries: [any MTLLibrary] = []

    /// Bundle URLs already registered (idempotent `registerDefaultLibrary`).
    private var registeredBundleURLs: Set<URL> = []

    /// D-16: lazy + memory PSO cache + LRU order bookkeeping.
    private var psoCache: [PSOKey: any MTLComputePipelineState] = [:]
    private var lruKeys: [PSOKey] = []

    /// LRU bound (RESEARCH Open Question #3). Phase 1 has ~1 kernel so the
    /// bound is trivial; it matters from Phase 3+ (~91 modules x variants).
    private static let psoCacheLimit = 256

    /// Lazily created CIImage→MTLTexture bridge (internal to Core; the app
    /// only sees the `renderToTexture` facade below).
    private var ciContextPool: CIContextPool?

    /// D-31: GPU-path signposts (visible in Instruments Metal System Trace).
    private static let signposter = OSSignposter(subsystem: "com.kamasylvia.lightamer", category: "metal")

    // MARK: - Lifecycle

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalError.deviceUnavailable
        }
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            AppError.logger.error("MTLCommandQueue allocation failed on \(device.name, privacy: .public)")
            throw MetalError.deviceUnavailable
        }
        self.commandQueue = queue

        // CRITICAL (RESEARCH §1 #1): resolve the framework bundle, never
        // Bundle.main. Tolerant load: Core has no kernels in Phase 1, so its
        // bundle carries no default.metallib yet — kernel-owning modules
        // register theirs via registerDefaultLibrary(in:).
        if let coreLibrary = try? device.makeDefaultLibrary(bundle: Bundle(for: MetalContextMarker.self)) {
            libraries.append(coreLibrary)
        } else {
            AppError.logger.info("LightamerCore ships no default.metallib (no Core kernels in Phase 1); kernel modules register their own libraries.")
        }
        AppError.logger.info("MetalContext ready: \(device.name, privacy: .public)")
    }

    /// Register another module's `default.metallib` (e.g. LightamerIOP's,
    /// whose bundle is exposed by `PassthroughKernel.metalBundle`). Idempotent
    /// per bundle. Lookup order: Core's library (when present) first, then
    /// registration order.
    public func registerDefaultLibrary(in bundle: Bundle) throws {
        let url = bundle.bundleURL
        guard !registeredBundleURLs.contains(url) else { return }
        do {
            let library = try device.makeDefaultLibrary(bundle: bundle)
            libraries.append(library)
            registeredBundleURLs.insert(url)
            AppError.logger.info("registered default.metallib from \(url.lastPathComponent, privacy: .public)")
        } catch {
            throw MetalError.functionNotFound("default.metallib in \(url.lastPathComponent)")
        }
    }

    // MARK: - High-level dispatch (D-19)

    /// Dispatch a 2D compute kernel over buffer-bound data (the simple-iop
    /// path, D-19 high layer). Binds `input` at buffer index 0 and `output`
    /// at index 1, runs `configure` for extra bindings/uniforms, enqueues and
    /// commits. Same-queue command buffers serialize, so chained iops are
    /// correctly ordered without waiting.
    ///
    /// `nonisolated`: the buffers are encoded in the CALLER's isolation
    /// region — they never cross an actor boundary, so an iop can reuse its
    /// working buffers across sequential dispatches. The only hop is the
    /// PSO-cache lookup.
    public nonisolated func dispatch2D(
        functionName: String,
        input: any MTLBuffer,
        output: any MTLBuffer,
        width: Int,
        height: Int,
        threadgroupSize: MTLSize = MTLSize(width: 16, height: 16, depth: 1),
        constants: MTLFunctionConstantValues? = nil,
        configure: (any MTLComputeCommandEncoder) -> Void = { _ in }
    ) async throws {
        let state = try await pipelineState(for: functionName, constants: constants)
        let commandBuffer = try makeCommandBuffer()
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalError.psoCreationFailed(functionName, nil)
        }
        encoder.setComputePipelineState(state)
        encoder.setBuffer(input, offset: 0, index: 0)
        encoder.setBuffer(output, offset: 0, index: 1)
        configure(encoder)
        encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: Self.clampedThreadgroup(threadgroupSize, for: state)
        )
        encoder.endEncoding()
        commandBuffer.commit()
    }

    /// Texture variant of `dispatch2D` (D-19 high layer): binds `input` at
    /// texture index 0 and `output` at index 1; the grid spans the output
    /// texture's dimensions. `nonisolated` for the same reason as `dispatch2D`.
    public nonisolated func dispatch2DTexture(
        functionName: String,
        input: any MTLTexture,
        output: any MTLTexture,
        threadgroupSize: MTLSize = MTLSize(width: 8, height: 8, depth: 1),
        constants: MTLFunctionConstantValues? = nil,
        configure: (any MTLComputeCommandEncoder) -> Void = { _ in }
    ) async throws {
        let state = try await pipelineState(for: functionName, constants: constants)
        let commandBuffer = try makeCommandBuffer()
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalError.psoCreationFailed(functionName, nil)
        }
        encoder.setComputePipelineState(state)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)
        configure(encoder)
        encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: Self.clampedThreadgroup(threadgroupSize, for: state)
        )
        encoder.endEncoding()
        commandBuffer.commit()
    }

    // MARK: - Low-level encoder exposure (D-19)

    /// Escape hatch for fine control (tiling Phase 2, multi-bind kernels):
    /// returns a live compute-encoder session with the PSO already bound.
    /// The caller configures the encoder, dispatches, `endEncoding()`s and
    /// `commit()`s the command buffer. Thread-safety contract: use the
    /// session from a single thread/actor (Metal command buffers are not
    /// concurrently encodable) — hence `@unchecked Sendable` carries an
    /// ownership-transfer contract, not free-for-all sharing.
    public struct ComputeEncoderSession: @unchecked Sendable {
        public let commandBuffer: any MTLCommandBuffer
        public let encoder: any MTLComputeCommandEncoder
        public let pipelineState: any MTLComputePipelineState
    }

    public nonisolated func makeEncoder(
        functionName: String,
        constants: MTLFunctionConstantValues? = nil
    ) async throws -> ComputeEncoderSession {
        let state = try await pipelineState(for: functionName, constants: constants)
        let commandBuffer = try makeCommandBuffer()
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalError.psoCreationFailed(functionName, nil)
        }
        encoder.setComputePipelineState(state)
        return ComputeEncoderSession(commandBuffer: commandBuffer, encoder: encoder, pipelineState: state)
    }

    // MARK: - PSO lazy cache (D-16) — internal, actor-isolated

    /// Cache-or-build a compute PSO for `(functionName, constants)`. Builds
    /// asynchronously via the completion-handler PSO API — NEVER a
    /// synchronous build on the MainActor (RESEARCH §3 gotcha).
    internal func pipelineState(
        for functionName: String,
        constants: MTLFunctionConstantValues?
    ) async throws -> any MTLComputePipelineState {
        let key = PSOKey(name: functionName, constantsFingerprint: Self.fingerprint(constants))
        if let cached = psoCache[key] {
            touch(key)
            return cached
        }
        let function = try await functionNamed(functionName, constants: constants)
        let descriptor = MTLComputePipelineDescriptor()
        descriptor.computeFunction = function
        do {
            // Async PSO build. The reflection out-parameter variant defeats
            // Swift's completion-handler → async bridge in the macOS 27 SDK,
            // so bridge the completion-handler variant explicitly.
            let state: any MTLComputePipelineState = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<any MTLComputePipelineState, Error>) in
                device.makeComputePipelineState(descriptor: descriptor, options: []) { state, _, error in
                    if let state {
                        continuation.resume(returning: state)
                    } else {
                        continuation.resume(throwing: error ?? MetalError.psoCreationFailed(functionName, nil))
                    }
                }
            }
            insert(key, state)
            AppError.logger.debug("PSO built: \(functionName, privacy: .public)")
            return state
        } catch {
            throw MetalError.psoCreationFailed(functionName, error)
        }
    }

    /// Resolve a (possibly constant-specialized) function across Core's
    /// library and all registered libraries.
    ///
    /// Gotcha (RESEARCH §3): `makeFunction(name:constantValues:)` requires
    /// ALL constants the function declares to be set — partial specialization
    /// throws at PSO creation. Mirror `[[function_constant(N)]]` indices via
    /// `makeConstants`/`setConstant`.
    internal func functionNamed(
        _ name: String,
        constants: MTLFunctionConstantValues?
    ) async throws -> any MTLFunction {
        if let constants {
            var lastError: Error?
            for library in libraries {
                do {
                    return try await library.makeFunction(name: name, constantValues: constants)
                } catch {
                    lastError = error
                }
            }
            throw MetalError.psoCreationFailed(name, lastError)
        }
        for library in libraries where library.makeFunction(name: name) != nil {
            return library.makeFunction(name: name)!
        }
        throw MetalError.functionNotFound(name)
    }

    // MARK: - Function-constants helper (D-17)

    /// Build a fresh `MTLFunctionConstantValues` with one value set at the
    /// `[[function_constant(index)]]` slot. For functions with MULTIPLE
    /// constants, chain with `setConstant(_:at:type:into:)` — a
    /// partially-filled set throws at PSO creation (all constants required).
    ///
    /// ```swift
    /// let c = metal.makeConstants(false, at: 0, type: .bool)
    /// metal.setConstant(Float(0.0), at: 1, type: .float, into: c)
    /// ```
    public nonisolated func makeConstants<T>(
        _ value: T, at index: Int, type: MTLDataType
    ) -> MTLFunctionConstantValues {
        let constants = MTLFunctionConstantValues()
        setConstant(value, at: index, type: type, into: constants)
        return constants
    }

    /// Set one additional constant on an existing set (see `makeConstants`).
    public nonisolated func setConstant<T>(
        _ value: T, at index: Int, type: MTLDataType, into constants: MTLFunctionConstantValues
    ) {
        var value = value
        withUnsafeBytes(of: &value) { bytes in
            constants.setConstantValue(bytes.baseAddress!, type: type, index: index)
        }
    }

    // MARK: - Session cache management (Plan 02-06-05, D-C1 layer 2)

    /// Clear the CI/RawCamera internal caches (the spike-b cross-decode
    /// accumulator). Actor-isolated async (the pool is lazily created
    /// here): callers `await` it. The PSO cache is deliberately NOT
    /// cleared (MB-scale; clearing costs PSO rebuild stalls for zero
    /// memory win — research §6 layer-3 decision).
    /// PSO startup pre-warm (Plan 03-06-T7, Open#7): build the named
    /// functions' compute pipeline states off the interactive path so the
    /// first drag doesn't pay the cold PSO compile (METAL-5). Failures are
    /// logged, not thrown — the lazy cache remains the source of truth and
    /// the interactive path would build on demand anyway.
    public func prewarmPipelineStates(functionNames: [String]) async {
        for name in functionNames {
            do {
                _ = try await pipelineState(for: name, constants: nil)
            } catch {
                AppError.logger.debug(
                    "PSO prewarm skipped \(name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    public func clearCICaches() async {
        await getOrCreatePool().clearCaches()
    }

    // MARK: - CIImage bridge facade

    /// Colorout's ColorSync leg (Plan 02-04-03, internal — the module lives
    /// in Core): converts a float32 linear-Rec2020 texture into a fresh
    /// float32 texture of LINEAR values in the `target` (linear) space via
    /// the pool's bitmap+replace path (host finding: direct CI render-to-
    /// texture is a no-op — see `CIContextPool`). The TRC encode stays with
    /// the gamma module (D-COL4).
    func convertToLinearSpace(
        _ input: sending any MTLTexture,
        target: CGColorSpace
    ) async throws -> sending any MTLTexture {
        let pool = await getOrCreatePool()
        do {
            let rendered = try await pool.convertTexture(input, toLinearSpace: target)
            return rendered.texture
        } catch let error as MetalError {
            throw error.asAppError
        }
    }

    /// Render a `CIImage` into a freshly allocated float32 linear-Rec2020
    /// `MTLTexture` (FOUND-02 pixelpipe format). Public facade over the
    /// internal `CIContextPool` — the app hands this the decoded `ciImage`;
    /// the pool never leaks cross-module (RESEARCH §9 internal surface).
    ///
    /// `nonisolated` + `sending` result: the texture is transferred OUT of
    /// the pool actor into the caller's region (owner: the caller from here
    /// on); the pool retains nothing.
    public nonisolated func renderToTexture(_ image: CIImage) async throws -> sending any MTLTexture {
        let pool = await getOrCreatePool()
        do {
            let rendered = try await pool.renderToTexture(image)
            return rendered.texture
        } catch let error as MetalError {
            throw error.asAppError
        }
    }

    /// Scale-at-entry variant (Plan 02-03-02): renders `image` transformed
    /// to `longEdge` pixels on its long dimension (downscale-only) in ONE
    /// pass — the PREVIEW/THUMBNAIL input-plane builder (D-C3; Darktable
    /// entry resampling mirror, `pixelpipe_hb.c:1930-1999`). Same float32
    /// linear-Rec2020 contract and ownership handoff as the full-extent
    /// facade above; signposted `"render-scaled"` (the 02-01 spike Test C
    /// decode-at-scale numbers are cited at `CIContextPool.renderToTexture
    /// (_:longEdge:)` — the win is plane MEMORY, not decode time).
    public nonisolated func renderToTexture(
        _ image: CIImage, longEdge: Int
    ) async throws -> sending any MTLTexture {
        let pool = await getOrCreatePool()
        do {
            let rendered = try await pool.renderToTexture(image, longEdge: longEdge)
            return rendered.texture
        } catch let error as MetalError {
            throw error.asAppError
        }
    }

    // MARK: - Private helpers

    /// Actor-isolated get-or-create; returns the actor REFERENCE (actor
    /// references are Sendable), never the rendered texture.
    private func getOrCreatePool() -> CIContextPool {
        if let ciContextPool {
            return ciContextPool
        }
        let pool = CIContextPool(device: device, commandQueue: commandQueue)
        ciContextPool = pool
        return pool
    }

    private nonisolated func makeCommandBuffer() throws -> any MTLCommandBuffer {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            AppError.logger.error("MTLCommandBuffer allocation failed")
            throw MetalError.deviceUnavailable
        }
        return commandBuffer
    }

    /// LRU move-to-end on cache hit.
    private func touch(_ key: PSOKey) {
        if let index = lruKeys.firstIndex(of: key) {
            lruKeys.remove(at: index)
            lruKeys.append(key)
        }
    }

    /// Insert + evict beyond the LRU bound (Open Question #3: 256 entries).
    private func insert(_ key: PSOKey, _ state: any MTLComputePipelineState) {
        psoCache[key] = state
        lruKeys.append(key)
        while lruKeys.count > Self.psoCacheLimit {
            let evicted = lruKeys.removeFirst()
            psoCache.removeValue(forKey: evicted)
        }
    }

    /// `MTLFunctionConstantValues` has no value introspection; fingerprint by
    /// instance identity (see `PSOKey`). Distinct constant combinations →
    /// distinct identities → distinct PSO entries (D-17); reusing one set
    /// instance is a cache hit (the intended iop hot-path pattern).
    private static func fingerprint(_ constants: MTLFunctionConstantValues?) -> String {
        constants.map { String(describing: ObjectIdentifier($0)) } ?? "none"
    }

    /// Clamp a requested threadgroup shape to the PSO's per-threadgroup
    /// thread budget (METAL-7 gotcha via `maxTotalThreadsPerThreadgroup`).
    private nonisolated static func clampedThreadgroup(
        _ requested: MTLSize, for state: any MTLComputePipelineState
    ) -> MTLSize {
        let maxTotal = state.maxTotalThreadsPerThreadgroup
        var group = MTLSize(
            width: max(requested.width, 1),
            height: max(requested.height, 1),
            depth: max(requested.depth, 1)
        )
        while group.width * group.height * group.depth > maxTotal {
            if group.width >= group.height, group.width > 1 {
                group.width = max(1, group.width / 2)
            } else if group.height > 1 {
                group.height = max(1, group.height / 2)
            } else {
                group.depth = max(1, group.depth / 2)
                break
            }
        }
        return group
    }
}
