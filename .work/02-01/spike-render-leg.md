# Spike — CIContext render-to-MTLTexture warm-up + decode-at-scale (Plan 02-01 Task 02-01-02)

- **Date:** 2026-09-19 (headless, Apple M4, macOS 27.0, Xcode 27.0 SDK)
- **Harness:** `.work/02-01/spike-render-leg.swift` (compiled against Debug frameworks with `swiftc -F <DerivedData products>`; no app target involvement)
- **Fixtures:** `input/RAW/DSC09991.ARW` (6336×9504, 60.2MP Sony), `input/RAW/DSC00012.jpg` (9504×6336, 60.2MP)
- **Context config under test (unless noted):** identical to `CIContextPool.init` — working/output colorSpace = linear Rec2020, workingFormat = RGBAh, cacheIntermediates = false.
- **Empty detection:** after render, blit texture → `MTLBuffer` (own command buffer, completed-wait) and count non-zero elements. A render that writes anything scores OK.

## Test A — warm-up hypothesis (N=6 fresh CIContexts)

Direct `render(_:to:commandBuffer:bounds:colorSpace:)` with an app-OWNED command buffer, explicit `commit()` + `completed()` wait before readback (the honest, race-free app-viable pattern). Per round: cold render (#1) → throwaway warm-up render (#2) → post-warm-up render (#3).

| round | cold (#1) | warm-up (#2) elapsed | post-warm-up (#3) |
|---|---|---|---|
| 1 | EMPTY (0.1ms) | 0.0ms | EMPTY |
| 2 | EMPTY (0.0ms) | 0.0ms | EMPTY |
| 3 | EMPTY (0.0ms) | 0.0ms | EMPTY |
| 4 | EMPTY (0.0ms) | 0.0ms | EMPTY |
| 5 | EMPTY (0.0ms) | 0.0ms | EMPTY |
| 6 | EMPTY (0.0ms) | 0.0ms | EMPTY |

- **first-render-empty WITHOUT warm-up: 6/6. WITH warm-up: 6/6.** Warm-up does NOT rehabilitate the direct path.
- Elapsed 0.0ms even through `commit()` + `completed()`: the command buffer contains no work — Core Image **enqueues nothing at all**. This is not a write-empty race; the call is a silent no-op.

### A0 — commandBuffer:nil variant (race documentation)

3/3 fresh contexts: render returns in 0.0ms, readback EMPTY. With a nil buffer CI works on its internal queue and returns immediately; even ignoring the race the result is still empty — consistent with A.

### A2 — real CIRAW-backed CIImage (fresh context)

Cold EMPTY, post-warm-up EMPTY. Not a synthetic-image artifact.

### A3 — control: DEFAULT CIContext (no options), `.rgba8Unorm`, deviceRGB

EMPTY. The no-op reproduces with a plain default context and 8-bit output — **our option set (linear Rec2020 / RGBAh / cacheIntermediates:false) is ruled out as the trigger**; the direct texture path is non-functional on this host/OS build across every variant Phase 1 swept (formats × storage × context ownership × command-buffer ownership) and every variant re-swept here.

## Test B — bitmap+replace baseline (CIContextPool's current path, n=3)

| extent | runs | median |
|---|---|---|
| preview 2560×1706 (from 60.2MP JPEG) | 25.2 / 19.3 / 18.0 ms | **19.3 ms** |
| full 60.2MP (9504×6336) | 449.9 / 291.1 / 172.5 ms | **291.1 ms** |

Consistent with Phase 1 (2560px ≈ 15.6ms; 100MP replace ≈ 0.3–0.5s). The preview-size CPU round-trip is ~16-20ms — acceptable ONLY off the drag hot path (research §5: hot path is all-Metal regardless of this spike).

## Test C — decode-at-scale (Open Question #3)

`RAWDecoder.decode(DSC09991.ARW)` (60.2MP) → render FULL extent vs `transformed(by:)`-scaled 2560px long edge, via `MetalContext.renderToTexture` (bitmap leg; pool pre-warmed with a throwaway render). decode() itself (metadata + CIRAWFilter construction, lazy pixels): 410–459ms n=1.

| run | FULL 60.2MP | scaled 2560px |
|---|---|---|
| 1 | 11223.4 ms (CIRAW kernel compile, cold) | 108.0 ms |
| 2 | 285.2 ms | 2019.6 ms |
| 3 | 303.6 ms | 922.5 ms |
| median | 303.6 ms | 922.5 ms |

- **First CIRAW render at any scale can cost seconds** (11.2s cold compile this run; 9.5s / 4.5s in earlier runs) — the decode→first-display leg is multi-second worst case → **Phase 3 PREVIEW first-render UX needs a progress affordance** (decision for Open Question #3: yes).
- **Scaled rendering gives NO reliable decode win**: medians are inverted (scaled 922ms vs full 304ms) and run-to-run variance swings 10–20× depending on which scale rendered before — with `cacheIntermediates:false` CIRAW re-executes per render and its internal per-configuration state thrashes when alternating scales. The win of rendering the input plane at target resolution is **memory** (70MB plane vs 1.55GB), not decode time.
- Steady-state full 60MP render ≈ 0.3s is the realistic PREVIEW-refresh upper bound (matches Test B + CIRAW re-execution).

## Decision

`Decision: bitmap — CIContext.render(_:toMTLTexture:) is a silent no-op on this host (macOS 27.0 / Apple M4): 0/6 non-empty cold AND 0/6 post-warm-up with an owned command buffer (0.0ms = CI enqueues no work), EMPTY with a real CIRAW-backed image, and EMPTY even on a DEFAULT CIContext + rgba8Unorm + deviceRGB; warm-up does not make the direct path reliable, so the decode leg keeps bitmap+replace (CIContextPool, Phase 1 workaround) for PREVIEW and FULL. The drag hot path is all-Metal regardless of this outcome (research §5 — the spike only decides the decode leg and the FULL path).`

Bitmap+replace remains the documented fallback AND the primary; `CIContextPool` carries this citation. Direct render-to-texture should be re-tested only on a future OS point release (the 0.0ms no-op smells like an Apple bug, not a design constraint).

## Consequences for downstream plans

- **02-03:** input plane for PREVIEW = CIImage → `transformed(by:)` → `CIContextPool.renderToTexture` (bitmap leg). Do NOT add a progress bar per-render; the progress affordance is a Phase 3 UX task (first-render seconds).
- **02-03:** render target resolution decides memory, not decode time — quantization ladder (D-C3) still worth it for cache footprint.
- Phase 1's "first-render-empty, second works" theory is **revised**: there is no working second render via the direct path; earlier "second render OK" observations came from the bitmap path or readback races, not from the direct path recovering.
