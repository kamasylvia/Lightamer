import Foundation
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// SpectralScratchAllocator (Plan M8-3+ T5) — the run-scoped serial-reuse
// slot (OQ-M83-9's single source — the ONLY new memory-discipline piece
// this batch: the three operators' intermediate planes time-share ONE
// slot — the pre-leg face → release → the grain face → release → the B2
// face; a second borrow by a DIFFERENT leg while one is out is a TYPED
// refusal, never a second allocation).
//
// The fix-round face (E-acc1): the Slot graduated from a borrow TOKEN to a
// RESOURCE pool — the four production dispatch sites
// (dispatchTakingDiffusion's acc/tmp/comp, blurPlaneWide's five staging
// buffers, dispatchGrainGroup's raw/acc/grain + blurTmp/usmOrig +
// separable-blur r32 staging, dispatchStageB's B1 CMY plane) borrow through
// the run's Slot and return faces to the pool on release. Same-geometry
// re-borrows hit the pool instead of allocating (the borrow/release/water
// counters are the accounting face — the reuse regression consumes them,
// not the MTL heap).
//
// The run owns ONE Slot: the chain entry (dispatchFilmChain) creates it
// (or the test injects one) and threads it down the leg dispatches
// (default-nil params — call sites without a run slot allocate
// independently, the legacy face). The borrow discipline:
//   • the holder is the top-level SEGMENT (.spatialPre for the whole
//     pre-leg span, .stageB2 for the whole B1→grain→B2 span);
//   • nested borrows WITHIN the segment (the wide staging inside the
//     diffusion loop, the grain working set inside stage B) pass the
//     SAME leg — a same-holder top-up, explicitly allowed;
//   • a DIFFERENT leg while faces are out is the typed refusal
//     (BorrowError.alreadyBorrowed);
//   • the holder clears when the segment's LAST live face returns
//     (partial returns keep it — releasePlanes/Buffers count down).
// The token borrow/release pair is the TEST face (it predates the pool);
// production borrows faces, never tokens.
//
// The peak face: `capacityPlan(width:height:legs:)` (the pure function —
// the peak-budget proof face: acc+comp rgba32F + the grain CMY face +
// the streaming-component ceiling; the 100MP full-open probe pins the
// ≤3.5GB gate, DECISIONS-logged). The fix round MEASURED the wired peak
// (the byte watermarks on real armed renders) — DECISIONS carries the
// measured numbers; capacityPlan stays the frozen two-face model.
// ─────────────────────────────────────────────────────────────────────────────

public enum SpectralScratchAllocator {

    /// The legs that draw from the slot (the borrow face's vocabulary).
    public enum Leg: Sendable, Equatable {
        case spatialPre
        case grain
        case stageB2
    }

    /// The typed borrow errors (fail-closed).
    public enum BorrowError: Error, Equatable, Sendable {
        /// A borrow is already out (the holder + the requester).
        case alreadyBorrowed(holder: Leg, requester: Leg)
    }

    /// One run-scoped slot (a class — the borrow state mutates; the
    /// run owns it, the legs borrow through it).
    ///
    /// The pool face: released faces park here keyed by exact geometry
    /// (width×height×pixelFormat for textures, byte length for buffers);
    /// a later same-geometry borrow returns the parked face. Geometry
    /// mismatch = a fresh allocation (no split/merge — the run's frame
    /// geometry is fixed, so same-leg re-borrows hit).
    public final class Slot: @unchecked Sendable {
        private let lock = NSLock()
        private var holder: Leg?
        private var texturePool: [String: [any MTLTexture]] = [:]
        private var bufferPool: [Int: [any MTLBuffer]] = [:]
        private var textureBorrows = 0
        private var textureHits = 0
        private var bufferBorrows = 0
        private var bufferHits = 0
        private var waterTextures = 0
        private var waterBuffers = 0
        private var waterTextureBytes = 0
        private var waterBufferBytes = 0
        private var liveTextures = 0
        private var liveBuffers = 0
        private var liveTextureBytes = 0
        private var liveBufferBytes = 0

        public init() {}

        /// Borrow the slot for one leg (typed refusal while held).
        /// The TEST face — production borrows faces, never tokens.
        public func borrow(_ leg: Leg) throws {
            lock.lock()
            defer { lock.unlock() }
            if let holder {
                throw BorrowError.alreadyBorrowed(
                    holder: holder, requester: leg)
            }
            holder = leg
        }

        /// Release the slot (idempotent — a double release is a no-op,
        /// never an error: the legs release defensively).
        /// The TEST face (see borrow).
        public func release() {
            lock.lock()
            defer { lock.unlock() }
            holder = nil
        }

        /// The test face: the current holder (nil = free).
        public var holderForTesting: Leg? {
            lock.lock()
            defer { lock.unlock() }
            return holder
        }

        private func textureKey(
            width: Int, height: Int, pixelFormat: MTLPixelFormat
        ) -> String {
            "\(width)×\(height)×\(pixelFormat.rawValue)"
        }

        /// The pool's two pixel formats (the production faces — rgba32F
        /// planes + the separable-blur r32 staging; anything else is a
        /// fail-closed nil, never a guessed stride).
        private func bytesPerPixel(_ format: MTLPixelFormat) -> Int? {
            switch format {
            case .rgba32Float: return 16
            case .r32Float: return 4
            default: return nil
            }
        }

        private func makePlane(
            device: any MTLDevice, width: Int, height: Int,
            pixelFormat: MTLPixelFormat
        ) -> (any MTLTexture)? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: pixelFormat,
                width: max(width, 1), height: max(height, 1),
                mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .shared
            return device.makeTexture(descriptor: descriptor)
        }

        /// Claim the holder for one leg (nil = free → claim; same leg →
        /// the top-up re-entry; a different leg → the typed refusal).
        private func claim(_ leg: Leg) throws {
            lock.lock()
            defer { lock.unlock() }
            if let holder, holder != leg {
                throw BorrowError.alreadyBorrowed(
                    holder: holder, requester: leg)
            }
            holder = leg
        }

        /// Borrow N read/write planes for one leg (the leg's live set in
        /// ONE call preferred — nested top-ups pass the same leg).
        /// Returns nil only when the device refuses or the format is
        /// outside the pool's two faces (fail-closed, the caller throws
        /// its own allocation error; already-borrowed faces in the same
        /// call park back before the nil).
        public func borrowPlanes(
            _ leg: Leg, device: any MTLDevice, count: Int,
            width: Int, height: Int,
            pixelFormat: MTLPixelFormat = .rgba32Float
        ) throws -> [any MTLTexture]? {
            try claim(leg)
            guard let bpp = bytesPerPixel(pixelFormat) else {
                maybeClear()
                return nil
            }
            let faceBytes = width * height * bpp
            var out: [any MTLTexture] = []
            for _ in 0..<count {
                let hit: (any MTLTexture)?
                lock.lock()
                let key = textureKey(
                    width: width, height: height, pixelFormat: pixelFormat)
                textureBorrows += 1
                if var parked = texturePool[key], !parked.isEmpty {
                    hit = parked.removeLast()
                    texturePool[key] = parked
                    textureHits += 1
                } else {
                    hit = nil
                }
                lock.unlock()
                guard let face = hit ?? makePlane(
                    device: device, width: width, height: height,
                    pixelFormat: pixelFormat)
                else {
                    releasePlanes(out)
                    return nil
                }
                lock.lock()
                liveTextures += 1
                liveTextureBytes += faceBytes
                waterTextures = max(waterTextures, liveTextures)
                waterTextureBytes = max(waterTextureBytes, liveTextureBytes)
                lock.unlock()
                out.append(face)
            }
            return out
        }

        /// Borrow N shared buffers for one leg (one call per leg — the
        /// byte lengths ride the layouts array, in order; nested top-ups
        /// pass the same leg).
        public func borrowBuffers(
            _ leg: Leg, device: any MTLDevice, byteLengths: [Int]
        ) throws -> [any MTLBuffer]? {
            try claim(leg)
            var out: [any MTLBuffer] = []
            for length in byteLengths {
                let hit: (any MTLBuffer)?
                lock.lock()
                bufferBorrows += 1
                if var parked = bufferPool[length], !parked.isEmpty {
                    hit = parked.removeLast()
                    bufferPool[length] = parked
                    bufferHits += 1
                } else {
                    hit = nil
                }
                lock.unlock()
                guard let face = hit ?? device.makeBuffer(
                    length: length, options: .storageModeShared)
                else {
                    releaseBuffers(out)
                    return nil
                }
                lock.lock()
                liveBuffers += 1
                liveBufferBytes += length
                waterBuffers = max(waterBuffers, liveBuffers)
                waterBufferBytes = max(waterBufferBytes, liveBufferBytes)
                lock.unlock()
                out.append(face)
            }
            return out
        }

        /// Clear the holder when nothing is live (the segment's last
        /// return — partial returns keep the holder for the top-up).
        private func maybeClear() {
            lock.lock()
            defer { lock.unlock() }
            if liveTextures == 0 && liveBuffers == 0 {
                holder = nil
            }
        }

        /// Return texture faces to the pool (the holder clears when the
        /// segment's last face returns).
        public func releasePlanes(_ faces: [any MTLTexture]) {
            lock.lock()
            for face in faces {
                let key = textureKey(
                    width: face.width, height: face.height,
                    pixelFormat: face.pixelFormat)
                texturePool[key, default: []].append(face)
                liveTextures = max(liveTextures - 1, 0)
                if let bpp = bytesPerPixel(face.pixelFormat) {
                    liveTextureBytes = max(
                        liveTextureBytes - face.width * face.height * bpp, 0)
                }
            }
            if liveTextures == 0 && liveBuffers == 0 {
                holder = nil
            }
            lock.unlock()
        }

        /// Return buffer faces to the pool (same holder rule).
        public func releaseBuffers(_ faces: [any MTLBuffer]) {
            lock.lock()
            for face in faces {
                bufferPool[face.length, default: []].append(face)
                liveBuffers = max(liveBuffers - 1, 0)
                liveBufferBytes = max(liveBufferBytes - face.length, 0)
            }
            if liveTextures == 0 && liveBuffers == 0 {
                holder = nil
            }
            lock.unlock()
        }

        /// The accounting face (the reuse regression's counters — lock
        /// snapshot, single source).
        public struct Accounting: Sendable, Equatable {
            /// Total texture-face borrows served (hits + fresh).
            public let textureBorrows: Int
            /// Borrows served from the pool (no device allocation).
            public let textureHits: Int
            /// Total buffer-face borrows served.
            public let bufferBorrows: Int
            /// Buffer borrows served from the pool.
            public let bufferHits: Int
            /// Peak simultaneously-live texture faces.
            public let textureWatermark: Int
            /// Peak simultaneously-live buffer faces.
            public let bufferWatermark: Int
            /// Peak simultaneously-live texture bytes.
            public let textureByteWatermark: Int
            /// Peak simultaneously-live buffer bytes.
            public let bufferByteWatermark: Int
            /// The wired peak (textures + buffers — the measured-peak
            /// face the DECISIONS numbers come from).
            public var peakBytes: Int {
                textureByteWatermark + bufferByteWatermark
            }
        }

        /// The accounting snapshot (the test face).
        public var accountingForTesting: Accounting {
            lock.lock()
            defer { lock.unlock() }
            return Accounting(
                textureBorrows: textureBorrows, textureHits: textureHits,
                bufferBorrows: bufferBorrows, bufferHits: bufferHits,
                textureWatermark: waterTextures,
                bufferWatermark: waterBuffers,
                textureByteWatermark: waterTextureBytes,
                bufferByteWatermark: waterBufferBytes)
        }
    }

    /// The peak-byte plan (the pure function — rgba32F faces):
    ///
    ///   spatialPre = acc + comp (2 rgba32F planes @ full frame)
    ///   grain      = the CMY density plane (1 rgba32F @ full frame)
    ///   stageB2    = the B1 CMY plane is ALREADY the input (0 new)
    ///
    /// The slot reuses ONE peak: peak = max(face bytes) — the serial
    /// discipline's whole point (independent allocation would SUM them).
    /// The streaming ceiling: bank components accumulate one at a time
    /// (the acc plane is the only bank-wide face — ≤ 11 components ×
    /// per-component scratch never coexists).
    public static func capacityPlan(
        width: Int, height: Int, legs: [Leg]
    ) -> Int {
        let plane = width * height * 4 * MemoryLayout<Float>.size
        var peak = 0
        for leg in legs {
            switch leg {
            case .spatialPre:
                peak = max(peak, 2 * plane)
            case .grain:
                peak = max(peak, plane)
            case .stageB2:
                peak = max(peak, 0)
            }
        }
        return peak
    }

    /// The 100MP full-open probe face (the ≤3.5GB gate's measurement
    /// leg — 100MP = 100M pixels; rgba32F = 16 B/px).
    public static func fullOpen100MP() -> Int {
        capacityPlan(
            width: 10_000, height: 10_000,
            legs: [.spatialPre, .grain, .stageB2])
    }
}
