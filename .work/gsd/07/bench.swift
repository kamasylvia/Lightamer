// bench.swift — Plan 07-1 T1 Vision benchmark (re-runnable, standalone).
//
// Compile:
//   xcrun -sdk macosx swiftc -O -o bench bench.swift
// Run (from .work/07):
//   ./bench <image1> <image2> ...
//
// Measures: layer A (GenerateForegroundInstanceMaskRequest), layer B
// (GenerateIterativeSegmentationRequest, model-ready state), personSeg,
// faceLandmarks × qualityLevel (where applicable) × {default(ANE-preferred),
// CPU pin}. Reports cold (run 1) + median of runs 2..4 wall time + the
// produced mask resolution. Layer B model download is timed when needed.

import CoreImage
import CoreML
import Foundation
import Vision

let clock = ContinuousClock()

func ms(_ d: Duration) -> Double {
    Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000.0
}

/// All MLComputeDevice cases, printed once.
func enumerateDevices() {
    print("## MLComputeDevice.allComputeDevices")
    for d in MLComputeDevice.allComputeDevices {
        let kind: String
        switch d {
        case .cpu: kind = "cpu"
        case .gpu: kind = "gpu"
        case .neuralEngine: kind = "neuralEngine"
        }
        print("- \(kind): \(d.description)")
    }
}

func cpuDevice() -> MLComputeDevice? {
    // The PIN device for the gpu-pin legs: the GPU (CPU pins trap — probes).
    for d in MLComputeDevice.allComputeDevices {
        if case .gpu = d { return d }
    }
    return nil
}

// The new-Swift requests each expose setComputeDevice differently (struct
// mutating vs class). Wrap per-request-type config in the builders below.

func decodeCI(_ url: URL) throws -> (CIImage, Double) {
    let t0 = clock.now
    guard let raw = CIRAWFilter(imageURL: url) else {
        throw NSError(domain: "bench", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "CIRAWFilter failed for \(url.lastPathComponent)"])
    }
    // The RAWDecoder.decodeRAW shape: request v9 when the file reports it.
    if #available(macOS 27, *),
       raw.supportedDecoderVersions.contains(.version9) {
        raw.decoderVersion = .version9
    }
    guard let image = raw.outputImage else {
        throw NSError(domain: "bench", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "no outputImage"])
    }
    let dt = ms(clock.now - t0)
    return (image, dt)
}

enum DeviceMode: String {
    case ane = "default(ANE-pref)"
    case cpu = "gpu-pin"
}

struct Row {
    var image: String
    var request: String
    var quality: String
    var device: String
    var coldMs: Double
    var warmMedianMs: Double
    var maskRes: String
}

var rows: [Row] = []

func record(_ r: Row) {
    rows.append(r)
    print(String(
        format: "| %@ | %@ | %@ | %@ | %.1f | %.1f | %@ |",
        r.image, r.request, r.quality, r.device, r.coldMs, r.warmMedianMs, r.maskRes))
}

// ───────────────────────── Layer B asset download ─────────────────────────

func ensureLayerBAssets() {
    print("## Layer B model assets (GenerateIterativeSegmentationRequest)")
    final class StatusBox: @unchecked Sendable {
        var initial: String = "?"
        var after: String = "?"
        var downloadMs: Double = -1
        var failed: String?
    }
    let box = StatusBox()
    let sem = DispatchSemaphore(value: 0)
    Task {
        let probe = GenerateIterativeSegmentationRequest(seedPoint: NormalizedPoint(x: 0.5, y: 0.5))
        let status0 = await probe.assetStatus
        box.initial = "\(status0)"
        if case DownloadableAssetsRequestStatus.ready = status0 {
            box.after = "already ready (no download needed)"
        } else {
            let t0 = clock.now
            do {
                try await probe.downloadAssets()
                box.downloadMs = ms(clock.now - t0)
                box.after = "\(await probe.assetStatus)"
            } catch {
                box.failed = "\(error)"
            }
        }
        sem.signal()
    }
    sem.wait()
    print("- initial assetStatus: \(box.initial)")
    if let f = box.failed {
        print("- downloadAssets FAILED: \(f)")
    } else if box.downloadMs >= 0 {
        print(String(format: "- downloadAssets(): %.1f ms -> %@", box.downloadMs, box.after))
    } else {
        print("- \(box.after)")
    }
}

// ───────────────────────── Request builders ─────────────────────────

func benchLayerA(_ name: String, handler: ImageRequestHandler, mode: DeviceMode, cpu: MLComputeDevice?) {
    var request = GenerateForegroundInstanceMaskRequest()
    if mode == .cpu, let cpu {
        // GPU pin (the validated safe pin on this OS — see header note).
        request.setComputeDevice(cpu, for: .main)
        request.setComputeDevice(cpu, for: .postProcessing)
    } else {
        // default: no pin — Vision/CoreML picks (ANE preferred)
    }
    var times: [Double] = []
    var res = ""
    for i in 0..<4 {
        let t0 = clock.now
        var err: String?
        let result = await_err(&err) { try await handler.perform(request) }
        times.append(ms(clock.now - t0))
        if i == 3 {
            if let e = err {
                res = "ERROR: \(e)"
            } else if let obs = result {
                // Scaled mask = the full-resolution leg the pipeline consumes.
                if let scaled = try? obs.generateScaledMask(for: obs.allInstances, scaledToImageFrom: handler) {
                    res = "\(CVPixelBufferGetWidth(scaled))×\(CVPixelBufferGetHeight(scaled)) (allInstances \(obs.allInstances.count))"
                } else {
                    res = "scaled-mask failed; instances \(obs.allInstances.count)"
                }
            } else {
                res = "nil (no subject)"
            }
        }
    }
    record(Row(image: name, request: "layerA foregroundInstMask", quality: "-",
               device: mode.rawValue, coldMs: times[0],
               warmMedianMs: median(Array(times.dropFirst())), maskRes: res))
}

func benchLayerB(_ name: String, image: CIImage, handler: ImageRequestHandler,
                 quality: GenerateIterativeSegmentationRequest.QualityLevel,
                 mode: DeviceMode, cpu: MLComputeDevice?) {
    let request = GenerateIterativeSegmentationRequest(seedPoint: NormalizedPoint(x: 0.5, y: 0.5))
    request.qualityLevel = quality
    // Pin finding (07-1 T1 probe): layer B supported=[gpu] but a GPU pin
    // SIGKILLs on macOS 27.0b (recursive os_unfair_lock) — pin is IMPOSSIBLE
    // for layer B on this OS; the pin leg is skipped, noted in the row.
    if mode == .cpu {
        request.qualityLevel = quality // keep default device path
    }
    var times: [Double] = []
    var res = ""
    for i in 0..<4 {
        let t0 = clock.now
        var err: String?
        let result = await_err(&err) { try await handler.perform(request) }
        times.append(ms(clock.now - t0))
        if i == 3 {
            if let e = err {
                res = "ERROR: \(e)"
            } else if let obs = result {
                let dims = obs.pixelBuffer.withUnsafeBuffer {
                    "\(CVPixelBufferGetWidth($0))×\(CVPixelBufferGetHeight($0))"
                }
                res = dims
            } else {
                res = "nil (no subject at seed)"
            }
        }
    }
    record(Row(image: name, request: "layerB iterativeSeg", quality: "\(quality)",
               device: mode.rawValue, coldMs: times[0],
               warmMedianMs: median(Array(times.dropFirst())), maskRes: res))
}

func benchPersonSeg(_ name: String, handler: ImageRequestHandler,
                    quality: GeneratePersonSegmentationRequest.QualityLevel,
                    mode: DeviceMode, cpu: MLComputeDevice?) {
    let request = GeneratePersonSegmentationRequest()
    request.qualityLevel = quality
    if mode == .cpu, let cpu {
        request.setComputeDevice(cpu, for: .main)
        request.setComputeDevice(cpu, for: .postProcessing)
    }
    var times: [Double] = []
    var res = ""
    for i in 0..<4 {
        let t0 = clock.now
        let result = try? await_sync { try await handler.perform(request) }
        times.append(ms(clock.now - t0))
        if i == 3, let obs = result {
            res = obs.pixelBuffer.withUnsafeBuffer {
                "\(CVPixelBufferGetWidth($0))×\(CVPixelBufferGetHeight($0))"
            }
        }
    }
    record(Row(image: name, request: "personSeg", quality: "\(quality)",
               device: mode.rawValue, coldMs: times[0],
               warmMedianMs: median(Array(times.dropFirst())), maskRes: res))
}

func benchFaceLandmarks(_ name: String, handler: ImageRequestHandler,
                        mode: DeviceMode, cpu: MLComputeDevice?) {
    var request = DetectFaceLandmarksRequest()
    if mode == .cpu, let cpu {
        request.setComputeDevice(cpu, for: .main)
        request.setComputeDevice(cpu, for: .postProcessing)
    }
    var times: [Double] = []
    var res = ""
    for i in 0..<4 {
        let t0 = clock.now
        let result = try? await_sync { try await handler.perform(request) }
        times.append(ms(clock.now - t0))
        if i == 3, let faces = result {
            res = "\(faces.count) face(s)"
        }
    }
    record(Row(image: name, request: "faceLandmarks", quality: "-",
               device: mode.rawValue, coldMs: times[0],
               warmMedianMs: median(Array(times.dropFirst())), maskRes: res))
}

func median(_ v: [Double]) -> Double {
    let s = v.sorted()
    return s[s.count / 2]
}

/// Tiny synchronous driver for the async benchmark legs (script context —
/// no structured-concurrency elegance needed; each call gets a fresh
/// top-level task awaited via semaphore).
private final class ResultBox<T>: @unchecked Sendable { var result: T? }

func await_sync<T>(_ body: @escaping @Sendable () async throws -> T) -> T? {
    let box = ResultBox<T>()
    let sem = DispatchSemaphore(value: 0)
    Task {
        box.result = try? await body()
        sem.signal()
    }
    sem.wait()
    return box.result
}

/// Error-capturing flattened await (layer A/B optional results).
private final class ErrBox: @unchecked Sendable { var message: String? }

func await_err<T>(_ errorOut: inout String?, _ body: @escaping @Sendable () async throws -> T?) -> T? {
    let eb = ErrBox()
    let r = await_sync_opt({
        do { return try await body() }
        catch { eb.message = String(describing: error); return nil }
    }) as T??
    errorOut = eb.message
    return (r ?? nil)
}

/// Optional-flattening variant for requests whose Result is itself optional
/// (layer A / layer B: `InstanceMaskObservation?` / `PixelBufferObservation?`).
func await_sync_opt<T>(_ body: @escaping @Sendable () async throws -> T?) -> T? {
    let box = ResultBox<T>()
    let sem = DispatchSemaphore(value: 0)
    Task {
        box.result = (try? await body()) ?? nil
        sem.signal()
    }
    sem.wait()
    return box.result
}

// ───────────────────────── Main ─────────────────────────

let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else {
    print("usage: bench <image...>")
    exit(2)
}

enumerateDevices()
ensureLayerBAssets()

// Print supportedComputeStageDevices once per request type (CPU-residency
// evidence for the test pin).
print("## supportedComputeStageDevices")
let pa = GenerateForegroundInstanceMaskRequest()
print("- layerA: \(mapDevices(pa.supportedComputeStageDevices))")
let pb = GenerateIterativeSegmentationRequest(seedPoint: NormalizedPoint(x: 0.5, y: 0.5))
print("- layerB: \(mapDevices(pb.supportedComputeStageDevices))")
print("- personSeg: (exposes setComputeDevice only — no supportedComputeStageDevices member)")

func mapDevices(_ m: [ComputeStage: [MLComputeDevice]]) -> String {
    m.map { stage, devs in
        "\(stage): [" + devs.map { d in
            switch d {
            case .cpu: return "cpu"
            case .gpu: return "gpu"
            case .neuralEngine: return "ane"
            }
        }.joined(separator: ",") + "]"
    }.sorted().joined(separator: " ")
}

print()
print("| image | request | quality | device | cold ms | warm median ms | mask res / result |")
print("|---|---|---|---|---|---|---|")

let cpu = cpuDevice()

for path in args {
    let url = URL(fileURLWithPath: path)
    let name = url.lastPathComponent
    guard let (image, decodeMs) = try? decodeCI(url) else {
        print("| \(name) | DECODE FAILED | | | | | |")
        continue
    }
    let extent = image.extent
    print(String(format: "<!-- %@ decode: %.1f ms, extent %.0f×%.0f -->",
                 name, decodeMs, extent.width, extent.height))
    let handler = ImageRequestHandler(image)

    // Pin modes: GPU only (CPU is not in either request's supported set —
    // a CPU pin SIGTRAPs; probes 07-1 T1). Layer B: ANY pin crashes the
    // process on this OS build — layer B runs default-only, one pass.
    benchLayerA(name, handler: handler, mode: .ane, cpu: cpu)
    for q in [GenerateIterativeSegmentationRequest.QualityLevel.fast,
              .balanced, .accurate] {
        benchLayerB(name, image: image, handler: handler, quality: q, mode: .ane, cpu: cpu)
    }
    for q in [GeneratePersonSegmentationRequest.QualityLevel.fast,
              .balanced, .accurate] {
        benchPersonSeg(name, handler: handler, quality: q, mode: .ane, cpu: cpu)
    }
    benchFaceLandmarks(name, handler: handler, mode: .ane, cpu: cpu)
    // PIN LEGS REMOVED for real images (07-1 probe findings: CPU pins trap
    // on every request; the layer-A GPU pin traps at 100MP scale although it
    // works at 512 synthetic — beta instability documented in perf.md; the
    // determinism gates run on 512 synthetic images in the test suite).
}

print()
print("Done. \(rows.count) rows.")
