@testable import LightamerCore
@testable import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// PanelParamsDecodeProbeTests (Plan AR-02 T2) — the env-gated decode-cost
// probe for the panel params path (the M2-5 env-gate convention: the
// default suite SKIPS this file; an approved directed round sets
// LIGHTAMER_PERF_PROBE=1 explicitly and the numbers land in
// AR-02-DECISIONS).
//
// THE PATH UNDER PROBE = `ModuleInstance.params(of:)` — the base64+JSON
// decode every panel read re-ran before the AR-02 stored-params codemod
// (once per body tick × ~20 reads), and once per init after it. The probe
// records the per-decode µs baseline for representative Params structs so
// later panel-performance archaeology can compare against a documented
// number.
//
// NO GATE (RESEARCH §5): the stored-params lift is a mechanical N→1
// construction — this probe is a documentation face, never a budget
// assertion. Pure CPU wall clock (no GPU segment, L014 has no object).
// ─────────────────────────────────────────────────────────────────────────────

final class PanelParamsDecodeProbeTests: XCTestCase {

    /// The skip leg IS the test: without the env gate this method skips,
    /// proving the probe stays out of the default suite (the ΔN +0..1
    /// accounting treats this skip as the +0 side; the PERF round below
    /// is the +1).
    func testDecodeProbeDefaultGated() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LIGHTAMER_PERF_PROBE"] == "1",
            "panel params decode probe runs only under LIGHTAMER_PERF_PROBE=1")
        // Smoke face: one round-trip decode per representative Params so
        // the PERF leg's decode path is proven reachable, not just timed.
        let record = ModuleInstance(module: ChannelMixerRGBModule.self, params: ChannelMixerRGBModule.Params())
        let decoded = try record.params(of: ChannelMixerRGBModule.self)
        XCTAssertEqual(decoded, ChannelMixerRGBModule.Params())
    }

    /// The PERF leg: representative Params (largest panel family + scalar
    /// small + curve-family large) decoded through the production path,
    /// median/min/p95 µs to stderr unbuffered.
    func testParamsDecodeMicrosecondBaseline() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LIGHTAMER_PERF_PROBE"] == "1",
            "panel params decode probe runs only under LIGHTAMER_PERF_PROBE=1")

        let iters = 2_000
        let cases: [(String, ModuleInstance, Any)] = [
            ("ChannelMixerRGB.Params",
             ModuleInstance(module: ChannelMixerRGBModule.self, params: ChannelMixerRGBModule.Params()),
             ChannelMixerRGBModule.self),
            ("Exposure.Params",
             ModuleInstance(module: ExposureModule.self, params: ExposureModule.Params()),
             ExposureModule.self),
            ("FilmicRGB.Params",
             ModuleInstance(module: FilmicRGBModule.self, params: FilmicRGBModule.Params()),
             FilmicRGBModule.self),
        ]

        func decodeOnce<M: IOPModule>(_ instance: ModuleInstance, as type: M.Type) throws -> M.Params {
            try instance.params(of: type)
        }

        for (name, record, typeAny) in cases {
            // warmup
            switch typeAny {
            case let t as ChannelMixerRGBModule.Type: _ = try decodeOnce(record, as: t)
            case let t as ExposureModule.Type: _ = try decodeOnce(record, as: t)
            case let t as FilmicRGBModule.Type: _ = try decodeOnce(record, as: t)
            default: XCTFail("unhandled params family")
            }
            var samples: [Double] = []
            samples.reserveCapacity(iters)
            for _ in 0..<iters {
                let t0 = Date()
                switch typeAny {
                case let t as ChannelMixerRGBModule.Type: _ = try decodeOnce(record, as: t)
                case let t as ExposureModule.Type: _ = try decodeOnce(record, as: t)
                case let t as FilmicRGBModule.Type: _ = try decodeOnce(record, as: t)
                default: XCTFail("unhandled params family")
                }
                samples.append(Date().timeIntervalSince(t0) * 1_000_000)
            }
            samples.sort()
            let median = samples[iters / 2]
            let min = samples[0]
            let p95 = samples[(iters * 95) / 100]
            Self.perf(
                "params-decode|\(name)|iters=\(iters)|median_us=\(String(format: "%.2f", median))"
                + "|min_us=\(String(format: "%.2f", min))|p95_us=\(String(format: "%.2f", p95))")
        }
    }

    /// The PERF line face — stderr (UNBUFFERED: a buffered stdout loses
    /// its lines on abnormal exit; the M2-5 convention).
    private static func perf(_ line: String) {
        FileHandle.standardError.write(Data("PERF|\(line)\n".utf8))
    }
}
