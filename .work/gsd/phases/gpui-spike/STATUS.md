# gpui-kit + gpui darktable replication: status

Orchestrator's one-page status. When a report in this folder disagrees with this page, this page wins. Last updated 2026-11-25.

## The question

Can gpui + gpui-kit reproduce darktable's darkroom page, its interactions and its feel? Raised for #27, and as one input to the open cross-platform / Rust decision on #24.

## What holds

- **Page**: skeleton and control anatomy replicate. Three regions, module header anatomy, fill-bar slider with a triangle marker and inline monospace value, combobox, checkbox, collapsible section, history, filmstrip, view switch. Visible gaps: no scopes block, group icon strip missing, icons are characters, rows 10-15% taller than darktable. See `REPORT.md` §1 and `shots/compare-*.jpg`.
- **Interactions**: of the 12 items in #27, 7 match. 2 differ because darktable behaves differently from what was assumed, 1 is not achieved on either side (keyboard reach of the module header), 1 is better in the prototype (Chinese IME; darktable's own inputs do not take it), 1 unverified. See `REPORT.md` §2.
- **Feel, when the UI is not blocked**: UI layer at 60 fps for a slider drag at the top of the list, 58 fps scrolling a 30-module panel (68 changed frames in 1.17 s, interval median 16.6 ms, none over 33 ms). darktable's slider drag measured 19.3 fps, but darktable is running its real pixel pipeline and the prototype has none, so that is not a like-for-like comparison.
- **gpui is not the cause of the failure below.** A minimal program in plain style (scroll container, 80 rows, offset set in code to 600, a timer changing a value 40 times) repaints at 30 to 37 of 40 updates for a plain `div`, a canvas, gpui-kit's `Progress` and gpui-kit's `Slider`. The same program on Zed's own `gpui 0.2.2` gives 37 of 40. Counts are the orchestrator's own recount from `traces/minimal/*.run`. See `REPORT-MINIMAL.md`.

## What does not hold yet

- **In the prototype, a slider inside the scrolled module panel does not visibly update**: 1 of 40 drag steps, 0 of 40 timer steps, with the app re-rendering every step. The same slider at scroll offset 0 updates. **The cause is some construct in the prototype, not gpui. Which construct is not yet identified.** A lane to find it and fix the prototype is running; its report will be `REPORT-BISECT.md`.
- No pixel pipeline behind the viewport. Feel with a real pipeline is unmeasured.
- All measurements use synthetic events. Real mouse is unverified; the user has two clean binaries to try, `dist/proto-pre-clean` and `dist/proto-fast-clean` in the spike workspace.

## Superseded statements in the reports

- `REPORT-DRAG.md`, `REPORT-MATRIX.md`, `REPORT-FAST.md` attribute the failure to the framework ("redraw suppression in the scrolled subtree", "no clean path"). **Wrong.** They tested only the prototype. `REPORT-MINIMAL.md` supersedes them on the cause.
- `REPORT-DRAG.md` §2.3 names the wgpu renderer as a candidate. That renderer is used on Linux and Web only; on macOS it is not in the path.
- `REPORT.md` §9 first bullet said the prototype had 3 modules. Wrong, it had 32. Retracted in `REPORT.md` §9.1.
- `REPORT.md` §8 says the gpui-kit license field on crates.io is empty. It is Apache-2.0 (orchestrator checked the crates.io API on 2026-11-25). `gpui` is Apache-2.0 as well.

## Cost so far

Prototype `main.rs` about 1,600 lines, roughly 900 of them hand-drawn darktable-style controls. gpui-kit supplies the window, an input with IME, scroll containers, AccessKit wiring and rendering. The darktable control semantics are not in gpui-kit and have to be written. First build 300 s, `target/` 3.2 GB.

## Facts about the stack

- gpui-kit 0.11.0 (Apache-2.0), renamed from gpui-component. Two backends: `gpui-pre` (default) and `gpui-fast` (opt-in feature). Both show the prototype failure and neither shows it in the minimal program.
- Rough edges found: Enter does not reach `on_key_down` (needs a key binding and an action); popovers need `.occlude()` or clicks pass through; gpui-kit's styled slider is a thumb, not darktable's fill bar; accessibility needs an explicit role per element.
- Scopes (histogram, waveform) have no ready component in egui either. LightCraft, the only egui reference, hand-draws a histogram and has no waveform. Lightamer today already has histogram and waveform as Metal kernels; darktable additionally has vectorscope and RGB parade.
