# gpui-kit + gpui darktable replication: status

Orchestrator's one-page status. When a report in this folder disagrees with this page, this page wins. Last updated 2026-11-25, after the bisect round.

## The question

Can gpui + gpui-kit reproduce darktable's darkroom page, its interactions and its feel? Raised for #27, and as one input to the open cross-platform / Rust decision on #24.

## Answer

**Yes on the UI layer, within the limits below.** A prototype reproduces darktable 5.6.2's darkroom page skeleton and its control anatomy, and the UI layer keeps 60 fps while a slider is dragged inside a scrolled 30-module panel. The prototype has no pixel pipeline behind the viewport, so the feel with real processing is unmeasured. Every measurement uses synthetic events; a real mouse has not been tried.

## What holds

Numbers below are the orchestrator's own recounts from the raw traces unless marked otherwise.

- **Page.** Three regions, module header anatomy, fill-bar slider with a triangle marker and an inline monospace value, combobox, checkbox, collapsible section, history, filmstrip, view switch. Visible gaps: no scopes block, no group icon strip, icons are characters, rows 10-15% taller than darktable. `REPORT.md` §1, `shots/compare-*.jpg`.
- **Interactions.** 7 of the 12 items in #27 match. 2 differ because darktable behaves differently from what was assumed, 1 is not achieved on either side (keyboard reach of the module header), 1 is better in the prototype (Chinese IME; darktable's own inputs do not take it), 1 unverified. `REPORT.md` §2.
- **Slider drag inside the scrolled panel.** 22 of 24 display frames changed during the drag, scored on a 480×400 grid. At the top of the list the same drag gives 21 of 24. `traces/bisect/DUAL-drag602.run`, `DUAL-drag0.run`.
- **Real captures during that drag** show fill, marker and value moving: `traces/bisect/drag-s01.png` (25.30 px) and `drag-s05.png` (81.00 px).
- **Scrolling a 30-module panel.** 68 changed frames in 1.17 s, interval median 16.6 ms, none over 33 ms. `traces/P30-scroll60b.*`.
- **darktable's slider drag measured 19.3 fps** with the same probe. darktable is running its real pixel pipeline; the prototype has none. Not a like-for-like comparison, and darktable was not re-measured on the dense grid.
- **gpui itself is fine.** A minimal program in plain style (scroll container, offset set in code to 600, a timer changing a value 40 times) repaints at 30 to 37 of 40 updates for a plain `div`, a canvas, gpui-kit's `Progress` and gpui-kit's `Slider`, on the sparse grid. The same program on Zed's `gpui 0.2.2` gives 37 of 40. `REPORT-MINIMAL.md`.
- **Event delivery.** macOS delivered 30 of 40 synthetic drag steps; the app applied 29.

## The scrolled-panel "failure" was a measurement artifact

Five rounds concluded that geometry changes inside a scrolled container were not presented, first in the prototype, then "in the framework". That was wrong. The cause is the probe.

`measure/FrameProbe.swift` scores an 80×45 grid with **one pixel at the centre of each cell** (lines 62 to 100). On the 816 pt window that is a row pitch of 18 pt. The slider bar is 7 pt high. After scrolling, the bar fell between two sample rows, so the probe scored 1 of 24 frames while a dense grid on the same frames scores 22. The minimal program shows the same thing: a 7 px quad scores 0 of 40 on the sparse grid and 40 of 40 on the dense grid, with the code unchanged. No render fix was needed. `dist/proto-pre-fixed` is byte-identical to `dist/proto-pre-clean`. See `REPORT-BISECT.md`.

Consequence for every earlier number in this folder that came from the sparse grid: it is a lower bound. Any feature thinner than 18 pt can be missed at some scroll offsets.

## Superseded statements

- `REPORT-DRAG.md`, `REPORT-MATRIX.md`, `REPORT-FAST.md`: the failure is attributed to the framework ("redraw suppression in the scrolled subtree", "no clean path"). Wrong. The cause is the probe's sampling.
- `REPORT-MINIMAL.md`: right that gpui is not the cause, wrong that the cause is "some construct in the prototype".
- The previous version of this page said the same ("some construct in the prototype, not yet identified"). Wrong, for the same reason.
- `REPORT-DRAG.md` §2.3 names the wgpu renderer as a candidate. That renderer runs on Linux and Web only.
- `REPORT.md` §9 first bullet said the prototype had 3 modules. It had 32. Retracted in `REPORT.md` §9.1.
- `REPORT.md` §8 says the gpui-kit license field on crates.io is empty. It is Apache-2.0. `gpui` is Apache-2.0 as well.

## Cost so far

Prototype `main.rs` about 1,600 lines, roughly 900 of them hand-drawn darktable-style controls. gpui-kit supplies the window, an input with IME, scroll containers, AccessKit wiring and rendering. The darktable control semantics are not in gpui-kit and have to be written. First build 300 s, `target/` 3.2 GB.

## Facts about the stack

- gpui-kit 0.11.0 (Apache-2.0), renamed from gpui-component. Two backends: `gpui-pre` (default) and `gpui-fast` (opt-in feature). Both behaved the same in every test.
- Rough edges: Enter does not reach `on_key_down` (needs a key binding and an action); popovers need `.occlude()` or clicks pass through; gpui-kit's styled slider is a thumb, not darktable's fill bar; accessibility needs an explicit role per element.
- Scopes (histogram, waveform) have no ready component in egui either. LightCraft, the only egui reference, hand-draws a histogram and has no waveform. Lightamer today has histogram and waveform as Metal kernels; darktable additionally has vectorscope and RGB parade.

## Not verified

- A real mouse. Two clean binaries are in the spike workspace under `dist/`: `proto-pre-clean` and `proto-fast-clean`.
- Feel with a real pixel pipeline behind the viewport.
- darktable re-measured on the dense grid.
- The timer-driven cases on the dense grid, the resizable split, Linux and Windows.
