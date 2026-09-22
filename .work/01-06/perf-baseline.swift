// Plan 01-06 perf baseline probe — the REAL app pipeline (public surface):
//   RAWDecoder.decode (signposted "decode", D-31) →
//   RenderPipeline.render (signposted "pixelpipe", the public face of the
//   internal PixelPipe) → display texture (float32 linear-Rec2020).
// Consolidates the app-architecture leg of 01-PERF-BASELINE.md; the raw
// decode/blit/frame matrix comes from Spike B (.planning/spikes/spike-b-*).
// Not part of any build target (per the .work process-files convention).
//
// Usage: perf-baseline <fixture1> <fixture2> ...   (n runs each, median)

import CoreImage
import Foundation
import LightamerCore
import Metal

let runs = 3
nonisolated(unsafe) var failures = 0

func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride
    )
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
}

func median(_ values: [Double]) -> Double {
    values.sorted()[values.count / 2]
}

/// Duration → milliseconds.
func ms(_ d: Duration) -> Double {
    Double(d.components.seconds) * 1_000 + Double(d.components.attoseconds) / 1e15
}

let semaphore = DispatchSemaphore(value: 0)
Task.detached {
    defer { semaphore.signal() }
    do {
        let decoder = RAWDecoder()
        let metal = try MetalContext()
        print("device: \(metal.device.name)  recommendedWorkingSet: \(Double(metal.device.recommendedMaxWorkingSetSize) / 1_048_576) MB")

        for arg in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: arg)
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("SKIP \(url.lastPathComponent) (missing)")
                continue
            }

            // Warm-up (page cache + probe cache).
            var decoded = try await decoder.decode(url)
            _ = try await RenderPipeline.render(image: decoded, layerStack: nil, metal: metal)

            var decodeMs: [Double] = []
            var pipeMs: [Double] = []
            var totalMs: [Double] = []
            var peakAboveStart: [Double] = []
            for _ in 0..<runs {
                let startFootprint = footprintMB()
                let clock = ContinuousClock()
                let t0 = clock.now
                decoded = try await decoder.decode(url) // signposted "decode"
                let t1 = clock.now
                let texture = try await RenderPipeline.render(
                    image: decoded, layerStack: nil, metal: metal
                ) // signposted "pixelpipe"
                let t2 = clock.now
                decodeMs.append(ms(t1 - t0))
                pipeMs.append(ms(t2 - t1))
                totalMs.append(ms(t2 - t0))
                peakAboveStart.append(footprintMB() - startFootprint)
                _ = texture
            }

            let mp = Double(decoded.ciImage.extent.width * decoded.ciImage.extent.height) / 1_000_000
            print(String(
                format: "%@  %.1fMP  v%@  decode med %.0f ms  pipe med %.1f ms  total med %.0f ms  footprintΔ med %.0f MB  end %.0f MB",
                url.lastPathComponent, mp, decoded.decoderVersionUsed.rawValue,
                median(decodeMs), median(pipeMs), median(totalMs),
                median(peakAboveStart), footprintMB()
            ))
        }
    } catch {
        print("FAIL \(error)")
        failures += 1
    }
}
semaphore.wait()
exit(failures == 0 ? 0 : 1)
