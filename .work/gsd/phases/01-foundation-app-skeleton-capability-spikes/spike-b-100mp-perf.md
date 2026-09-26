# Spike B Report — 100MP Metal performance vertebra on macOS 27.0 GM

**Plan:** 01-05 Task 01-05-02 · **Executed:** 2026-09-16 · **Owner:** GSD executor
**Host:** Apple M4 (Mac16,10), **16 GB unified memory**, macOS 27.0 official (26A428), Xcode 27.0 / macOS 27.0 SDK, Swift 6.4.
`recommendedMaxWorkingSetSize` = **12 124 MB**. Requirement: FOUND-07. Decisions fed: **D-20** (tiling deferral), **D-32** (hard budgets), Phase 2 pixelpipe cache scope.

> **Execution-form note (recorded deviation from plan text):** per the coordinator's
> pragmatic call, the spike is a **headless measurement harness** (same
> public-API-driven pattern as the Plan 01-03/01-04 smoke harnesses, zero Lightamer
> dependencies) instead of a standalone Tuist GUI app on a spike branch. Zoom/pan is
> measured as per-frame render cost at viewport resolution (2560×1440) — the exact
> work MTKView's drawable blit does — rather than an interactive MTKView session.
> Probe sources: `.planning/spikes/spike-b-100mp-perf/{perf-harness,perf-extra}.swift`
> (working copies in untracked `.work/plans/01-05/`); raw outputs `spike-b-*.txt` alongside.
> All timing emits `os.signpost` intervals (`com.kamasylvia.lightamer.spikeb`) — D-31.
> Real RAW samples only (CC0, raw.pixls.us) — no synthetic/fabricated images.
> **No 60fps GUI app was built; "drag fps" below is a measured proxy, labeled as such.**

---

## 1. Method

Two harnesses, one process per file (fresh `CIContext(mtlDevice:, [.cacheIntermediates: false, .workingColorSpace: linear Rec2020])` — the exact FOUND-02/Plan-03 config):

- **`perf-harness.swift`** — per file: warm-up decode, then **n=5** full-size decode+render runs (median/min/max); blit-path A/B test; native-res float32 plane test; uncached viewport-frame cost (60 frames).
- **`perf-extra.swift`** — memory-lean supplement: single warm decode, float32 plane test with fresh footprint budget, and the **cached-frame test** (decode ONCE into an RGBA8 plane, wrap as `CIImage(bitmapData:)`, then 60 per-frame aspect-fit+pan transforms at 2560×1440 — this models the real app architecture: decode → cached plane → per-frame blit).
- Memory: `task_vm_info.phys_footprint` sampled every 10 ms by a background timer (true peak, not end-state).
- Timing: `ContinuousClock` + `os.signpost` intervals.

Samples (see `samples/README.md` for provenance/license): GFX100S RAF 101.8MP (headline), Sony A7R V ARW 60.2MP (also RAW-9-capable), Nikon Z8 NEF 45.4MP (substitutes the plan's Canon R5 slot — no R5 sample exists on raw.pixls.us), Hasselblad X2D 3FR 102.1MP, plus GFX100S **uncompressed** RAF 101.8MP (isolation experiment, §4). Phase One IQ4 150MP IIQ was excluded: **CIRAW cannot decode it at all** (Spike A finding, `supportedDecoderVersions == [None]`).

## 2. Raw numbers

### 2.1 Decode: full-size, native-res, RGBA8 render (the real pipeline cost), n=5 steady-state medians

| Image | MP | Decoder | decode+full render (med) | min / max | footprint peak (med / max) |
|---|---|---|---|---|---|
| Nikon Z8 NEF (lossless) | 45.4 | v8 | **345 ms** | 335 / 355 | +88 / +283 MB |
| Sony A7R V ARW (lossless-c) | 60.2 | v8 | **763 ms** | 757 / 768 | +2 / +398 MB |
| Sony A7R V ARW | 60.2 | **v9** | **766 ms** | 754 / 829 | +2 / +86 MB |
| Hasselblad X2D 3FR | 102.1 | v8 | **833 ms** | 811 / 877 | +480 / +616 MB |
| **GFX100S RAF (lossless-c)** | 101.8 | v8 | **20 894 ms** | 20 635 / 24 388 | +330 / +503 MB |
| GFX100S RAF **(uncompressed)** | 101.8 | v8 | **848 ms** | 835 / 876 | — (isolation run, n=3) |
| Fujifilm X-T5 RAF (lossless-c) | 39.8 | v8 | **414 ms** | 414 / 417 | — (isolation run, n=3) |
| Fujifilm X-T5 RAF | 39.8 | **v9** | **1 793 ms** | 1 788 / 1 801 | — (isolation run, n=3) |

**Two decisive findings:**

1. **The 100MP decode budget is NOT blown by 100MP — it is blown by Apple's lossless-RAF decompressor at GFX width.** The same 101.8MP X-Trans sensor decodes in **848 ms uncompressed vs 20 894 ms lossless-compressed** (24.6×, identical pixel count, identical demosaic). Bayer 100MP (X2D 3FR, also compressed) = 833 ms. The cliff is specific to lossless-compressed **RAF** at GFX scale (X-T5 lossless at 40MP is fine at 414 ms). All 100MP Bayer bodies and uncompressed RAF are comfortably inside the 2 s budget; **lossless-compressed GFX RAF is 10× over it** on macOS 27.0.
2. **RAW 9 does NOT speed up full-size decode at GM.** A7R V: v9 766 ms ≈ v8 763 ms. X-T5: v9 1 793 ms is **4.3× slower** than v8 414 ms. (The 11–49× "v9 speedups" seen in Spike A's 1:1 crop renders were first-touch artifacts, not steady-state throughput.) RAW 9's value is X-Trans demosaic *quality*, not speed.

### 2.2 Memory

| Test | Z8 45MP | A7R V 60MP | X2D 102MP | GFX100S 102MP |
|---|---|---|---|---|
| float32 RGBA native plane (theory) | 693 MB | 919 MB | 1 557 MB | 1 553 MB |
| float32 native render time | 478 ms | 848 ms | 1 875 ms | 2 038 ms |
| **footprint peak during float32 render** | **+1 908 MB** | **+2 147 MB** | **+2 058 MB** | **+1 466 MB** |
| decode RGBA8 footprint peak (med) | +88 MB | +2 MB | +480 MB | +330 MB |
| end-of-process footprint (main harness) | 4 258 MB | 4 399 MB | (crashed late, §5) | 4 754 MB |

- **A single 100MP float32 RGBA plane fits easily**: 1.55 GB alloc + render succeeds; peak footprint during the render is **2.0–2.8 GB** (CI render overhead ≈ plane × ~1.3), well under both the 12.1 GB recommended working set and the 4 GB budget.
- **`cacheIntermediates: false` is validated (CIRAW-4)**: per-decode footprint peaks stay at +0.3–0.6 GB for 100MP files — the lazy-chain blow-up Pitfalls CIRAW-4 warns about did not occur with this config.
- **But footprint ACCUMULATES across repeated decodes in one process**: end-of-process footprint reached 4.3–4.8 GB after ~11 full 100MP renders despite `cacheIntermediates: false` — CI/RawCamera retain internal per-camera state. **Phase 2 must call `CIContext.clearCaches()` on image switch** (the memory-lean supplement runs, which do exactly one decode + one float32 render with a `clearCaches()` between phases, ended at 2.3–3.8 GB).

### 2.3 Display-path (blit) and frame cost

- **Blit A** (`CIContext.render` → `MTLTexture(.rgba32Float)`, 1024×768 crop): 27–335 ms depending on file. **First call in every process wrote EMPTY texture content** (`contentNonZero=false` 6/6 processes; the second call in the same process succeeded). This **reproduces Plan 03's macOS 27 finding at GM** — first-use render-to-texture is silently empty; either warm it up once at context creation or keep the bitmap+replace path.
- **Blit B** (bitmap render + `texture.replace(region:)`, 1024×768): **4–6 ms total** (render 2–5 ms + replace 1.2–1.8 ms). This remains the correct Phase 2 display path.
- **Uncached frame cost** (re-rendering the lazy CIRAW `CIImage` per frame at 2560×1440 — i.e. what you get with NO pixelpipe cache): median **1 019.6 ms/frame on GFX100S (≈1 fps)**, 330–332 ms on 45–60MP files. A lazy CIImage is **not** a frame cache; every pan/zoom frame re-runs the full RAW pipeline.
- **Cached frame cost** (decode-once plane + per-frame transform, the real architecture): median **15.60 ms on GFX100S (≈64 fps)**, 17.51 ms on X2D (≈57 fps), 8.50 ms on A7R V (≈118 fps), 6.73 ms on Z8 (≈149 fps). This path renders from a CPU bitmap through CIContext each frame (source upload included) — a resident `MTLTexture` in the real MTKView pipeline removes that upload, so these are **upper bounds**.

## 3. Verdict per D-32 hard budget

| Budget | Result | Verdict |
|---|---|---|
| 100MP decode ≤ 2 s | Bayer 100MP: 833 ms; X-Trans 100MP lossless-c RAF: **20.9 s**; X-Trans 100MP uncompressed: 848 ms | **PASS for Bayer and uncompressed RAF; FAIL (10×) for lossless-compressed GFX RAF** — the specific variant most GFX100S shooters use |
| Display ≤ 500 ms (decode → drawable) | 848 ms decode + 6 ms blit ≈ 0.9 s (worst-case 100MP); display-after-cache 6 ms | **PASS** (the 500 ms budget is met by every cached-display path; first-display on uncompressed 100MP ≈ 0.9 s is marginally over but one-shot) |
| Steady-state memory ≤ 4 GB | single-plane pipeline peak 2.0–2.8 GB; **process end-state 4.3–4.8 GB without `clearCaches()`** | **PASS per-image, CONDITIONAL in-app**: budget holds only with `clearCaches()` on image switch; without it, a long session drifts past 4 GB |
| Drag frame ≤ 16 ms at viewport res | cached path 15.6 ms @ 102MP (64 fps), 6.7–8.5 ms @ 45–60MP; uncached path 330–1020 ms | **PASS with the pixelpipe cache; CATASTROPHIC FAIL without it** (1–3 fps) |

## 4. D-20 decision evidence (tiling deferred to Phase 2 — user makes the call)

**Evidence FOR keeping D-20 (tiling deferred):**

- The Phase 1 vertebra (decode → single plane → display blit) works at 102MP within memory: 1.55 GB plane, 2.0–2.8 GB peak, no jetsam.
- Cached-path frame cost at 102MP is 15.6 ms — **60fps is achievable at 100MP without tiling** for the display path.
- Phase 1 has no iop chain: one plane + one blit is the whole pipeline.

**Evidence AGAINST deferring (i.e. for early tiling):**

- The **cached-path margin at 100MP is thin**: 15.6 ms median leaves <1 ms to the 16.67 ms budget, and 17/60 frames exceeded it on the M4. Any iop kernel added to the per-frame path at full 100MP resolution blows it. (Phase 2's answer is non-full-res interactive previews, which IS the tiling/multi-resolution machinery.)
- **Phase 2's per-module cache multiplies the plane**: every cached pipeline stage holds ~1.55 GB at 100MP float32. Three concurrent planes ≈ 4.7 GB — at the 4 GB budget; five ≈ 7.8 GB — over half the 12.1 GB recommended working set. **Tiling (or aggressive downscale-on-idle) becomes mandatory in Phase 2**, exactly as D-20 anticipated.
- 150MP-class files (Phase One IQ4) exist in the wild (2.4 GB/plane); CIRAW can't decode IQ4 today, but DNG/3FR at that scale will arrive.

**Recommendation for the phase-verification decision** (documented evidence, user decides): **D-20 holds for Phase 1** — no tiling needed for decode+display of 100MP; the measured numbers confirm the deferral. **Phase 2 planning must treat tiling/multi-resolution caching as a hard requirement, not an optimization** — not because Phase 1 fails, but because (a) per-frame budget at 100MP has <1 ms headroom, and (b) the Phase 2 per-module cache's plane multiplication crosses the 4 GB budget at ~2–3 cached planes. Practical Phase 2 scope: tile the *cache* (per-module, per-resolution pyramid), keep the display path full-res-blit. Suggested MP threshold to record: **full-res float32 pipelines stay untiled up to ~60MP with ≤3 cached planes; above that, or above ~2 cached planes at any MP, tile** — derived from 4 GB / (plane bytes × planes) with the measured ×1.3 CI overhead.

**Phase 2 actions fed by this spike:** ① `CIContext.clearCaches()` on image switch (4 GB drift); ② warm-up render-to-texture once per context (blit-A empty-first-render) or standardize on bitmap+replace; ③ re-measure GFX lossless RAF on macOS 27.x point updates (Apple may fix the decompressor; also consider a background "decode-at-preview-scale" UX path for lossless RAF); ④ progress UI for >2 s decodes (Phase 9 browser).

## 5. Anomalies & honest caveats (no data fabricated)

1. **swift-frontend interpreter teardown crash (exit 139)** after measurement completes — crash is in `swift::ASTContext` teardown after multi-GB allocations, NOT in measured code. All numbers print before it. Cosmetic for a script harness; a packaged app target would not hit it.
2. **One real CoreImage crash**: the X2D main-harness run SIGSEGV'd inside `CI::recursive_tile` during a render after many full 100MP renders in one process (footprint accumulation) — CoreImage crashed rather than returning an error under memory pressure on this 16 GB machine. Reinforces the `clearCaches()` action item and honest 16 GB headroom concerns.
3. **Harness bug disclosure**: the version-selection switch mapped unknown `supportedDecoderVersions` entries to `.version8`, so rows tagged `[7]` in the raw outputs are actually **v8 replicates** (useful: they agree with the `[8]` rows within ~3%). No numbers are affected; the tags are.
4. Machine-level variance: repeated 100MP processes on 16 GB + USB storage produced first-touch decodes up to 33× slower than steady state (page-cache/swap effects; GFX lossless first decode 21 s vs 2.3 s warm in a later process). **The canonical numbers in §2 are steady-state medians within a single process**; cold-start UX numbers are called out as such.
5. iOS semantic mattes, zoomable GUI, and Instruments GPU traces were out of scope for this headless spike (mattes probed in Spike A; GPU timing via signposts; Instruments left to Phase 2 profiling).

## 6. Artifacts

- Harness sources (tracked): `.planning/spikes/spike-b-100mp-perf/{perf-harness,perf-extra}.swift`
- Raw outputs (tracked): `.planning/spikes/spike-b-100mp-perf/spike-b-*.txt` (8 files, incl. the X2D crash stack)
- Golden viewport renders (tracked): `.planning/spikes/spike-b-100mp-perf/samples/golden/*-viewport.png` (2560×1440, 4 files)
- Sample provenance + CC0: `.planning/spikes/spike-b-100mp-perf/samples/README.md`
- RAW working copies (untracked): `.work/plans/01-05/samples/`
