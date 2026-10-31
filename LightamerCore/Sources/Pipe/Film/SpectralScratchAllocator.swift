import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// SpectralScratchAllocator (Plan M8-3+ T5) — the run-scoped serial-reuse
// slot (OQ-M83-9's single source — the ONLY new memory-discipline piece
// this batch: the three operators' intermediate planes time-share ONE
// slot — the pre-leg face → release → the grain face → release → the B2
// face; a second borrow while one is out is a TYPED refusal, never a
// second allocation).
//
// The peak face: `capacityPlan(width:height:legs:)` (the pure function —
// the peak-budget proof face: acc+comp rgba32F + the grain CMY face +
// the streaming-component ceiling; the 100MP full-open probe pins the
// ≤3.5GB gate, DECISIONS-logged).
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
    public final class Slot: @unchecked Sendable {
        private let lock = NSLock()
        private var holder: Leg?

        public init() {}

        /// Borrow the slot for one leg (typed refusal while held).
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
