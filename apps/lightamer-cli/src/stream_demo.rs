// SPDX-License-Identifier: GPL-3.0-or-later
//! `stream-demo`: the B1d engine side on a synthetic session, end to end.
//!
//! Renders an over-limit synthetic frame on a draft session and walks seven
//! steps: strips on a point-only chain, blocks with a blur module, a small
//! spill limit failing typed, three rapid generations (only the latest
//! reports ready), a mid-stream cancel (budget back, no spill files), a
//! resource table, and cleanup. Every step prints; any violated expectation
//! fails the command. `--only strip|block` runs one render for probing.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Instant;

use lightamer_engine::{
    Engine, EngineConfig, Event, InputError, InputSource, RenderFacts, RenderInput, RenderKind,
    StreamMode,
};
use lightamer_iop_traits::{
    ColorSpace, CommitData, ImageInfo, IopModule, ModuleDesc, OrderKey, PipeError, PipeKind,
    PipeState, Plane, PlaneMut, Roi, SharedModule, TilingReq,
};
use lightamer_raster::{Frame, FrameExtent, PixelFormat};

use crate::render_demo::{
    DemoGain, ask, develop_gain, drain_until_generation, drain_until_job, fresh_render_events,
    print_record,
};
use crate::util::Error;

/// One render for probing instead of the whole demo.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StreamOnly {
    /// Step 1 (strips) only.
    Strip,
    /// Step 2 (blocks) only.
    Block,
}

/// How long one step waits for its render: streaming a hundreds-of-MP
/// frame takes minutes, not seconds.
const DRAIN_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(600);

/// Frame dimensions for `mp` megapixels at a 6:5 aspect ratio.
fn dims_for_mp(mp: u32) -> Result<(u32, u32), Error> {
    let pixels = u64::from(mp).saturating_mul(1_000_000);
    if pixels == 0 {
        return Err(Error::new("stream-demo: --mp wants at least 1".to_owned()));
    }
    let width = u32::try_from((pixels.saturating_mul(12) / 10).isqrt())
        .map_err(|_| Error::new(format!("stream-demo: --mp {mp} does not fit a frame")))?;
    let width = width.max(64);
    let height = u32::try_from(pixels.div_ceil(u64::from(width)))
        .map_err(|_| Error::new(format!("stream-demo: --mp {mp} does not fit a frame")))?;
    Ok((width, height.max(64)))
}

/// Synthetic pixels for an absolute region of the r = x, g = y gradient.
fn region_pixels(region: FrameExtent) -> Vec<f32> {
    let cells = u64::from(region.width)
        .saturating_mul(u64::from(region.height))
        .saturating_mul(4);
    let mut out = Vec::with_capacity(usize::try_from(cells).unwrap_or(0));
    for row in 0..region.height {
        for col in 0..region.width {
            let x = region.x.saturating_add_unsigned(col);
            let y = region.y.saturating_add_unsigned(row);
            #[expect(clippy::cast_precision_loss)]
            // demo pixels stay far below 2^24; the conversion is exact
            let (x, y) = (x as f32, y as f32);
            out.extend_from_slice(&[x, y, 0.5, 1.0]);
        }
    }
    out
}

/// Synthetic input: whole fetches for the facts, lazy regions per piece.
struct StreamDemoInput {
    width: u32,
    height: u32,
    fetches: Arc<AtomicUsize>,
    regions: Arc<Mutex<Vec<FrameExtent>>>,
}

impl StreamDemoInput {
    fn new(width: u32, height: u32) -> Self {
        Self {
            width,
            height,
            fetches: Arc::new(AtomicUsize::new(0)),
            regions: Arc::new(Mutex::new(Vec::new())),
        }
    }
}

impl InputSource for StreamDemoInput {
    fn fetch(&self, _photo: &str) -> Result<RenderInput, InputError> {
        self.fetches.fetch_add(1, Ordering::SeqCst);
        let region = FrameExtent::new(0, 0, self.width, self.height);
        let frame = Frame::from_parts(region_pixels(region), region, PixelFormat::RgbaF32Premul)
            .map_err(|err| InputError::new(err.to_string()))?;
        Ok(RenderInput {
            frame,
            image: ImageInfo::new(self.width, self.height, ColorSpace::Rgb),
            input_id: u64::from(self.width),
        })
    }

    fn probe(&self, _photo: &str) -> Result<RenderFacts, InputError> {
        Ok(RenderFacts {
            image: ImageInfo::new(self.width, self.height, ColorSpace::Rgb),
            extent: FrameExtent::new(0, 0, self.width, self.height),
        })
    }

    fn fetch_region(&self, _photo: &str, region: FrameExtent) -> Result<RenderInput, InputError> {
        if let Ok(mut held) = self.regions.lock() {
            held.push(region);
        }
        let frame = Frame::from_parts(region_pixels(region), region, PixelFormat::RgbaF32Premul)
            .map_err(|err| InputError::new(err.to_string()))?;
        Ok(RenderInput {
            frame,
            image: ImageInfo::new(self.width, self.height, ColorSpace::Rgb),
            input_id: u64::from(self.width),
        })
    }
}

/// Private demo blur module behind id `demo_blur`: honest separable box
/// blur, radius 8, clamped edges (block mode needs a spatial module).
struct DemoBlur {
    desc: ModuleDesc,
}

struct DemoBlurCommit;

impl DemoBlur {
    /// Blur radius in pixels, both passes.
    const RADIUS: usize = 8;

    fn new() -> Self {
        let key = OrderKey {
            priority: 1.0,
            tie: 0,
        };
        Self {
            desc: ModuleDesc::stub("demo_blur", key, key),
        }
    }
}

impl IopModule for DemoBlur {
    fn desc(&self) -> &ModuleDesc {
        &self.desc
    }

    fn commit(
        &self,
        _params: &serde_json::Map<String, serde_json::Value>,
        _image: &ImageInfo,
        _state: &mut PipeState,
        _kind: PipeKind,
    ) -> Result<CommitData, PipeError> {
        Ok(Arc::new(DemoBlurCommit))
    }

    fn tiling(&self, _data: &CommitData, _rin: &Roi, _rout: &Roi) -> TilingReq {
        TilingReq {
            factor: 2.0,
            maxbuf: 1.0,
            overhead: 0,
            #[expect(clippy::cast_possible_truncation)]
            // radius 8 fits u32
            overlap: Self::RADIUS as u32,
            align: 1,
        }
    }

    fn process(
        &self,
        _data: &CommitData,
        input: &Plane<'_>,
        output: &mut PlaneMut<'_>,
        _rin: Roi,
        _rout: Roi,
        _state: &mut PipeState,
    ) -> Result<(), PipeError> {
        if input.width() != output.width() || input.height() != output.height() {
            return Err(PipeError::RoiMismatch(format!(
                "demo blur planes differ: {}x{} vs {}x{}",
                input.width(),
                input.height(),
                output.width(),
                output.height()
            )));
        }
        let width = input.width() as usize;
        let height_u32 = input.height();
        let height = height_u32 as usize;
        let radius = Self::RADIUS;
        let span = radius * 2 + 1;
        #[expect(clippy::cast_precision_loss)]
        // span 17 is exact
        let count = span as f32;
        let mut tmp = vec![0.0f32; width * height * 4];
        let tap_at = |plane: &[f32], at: usize, c: usize| {
            plane
                .get(at * 4 + c)
                .copied()
                .ok_or_else(|| PipeError::Backend(format!("demo blur tap {at} leaves its plane")))
        };
        for y in 0..height_u32 {
            let src = input.row(y)?;
            let yu = y as usize;
            for x in 0..width {
                for c in 0..4 {
                    let mut sum = 0.0f32;
                    for tap in 0..span {
                        let sx = x
                            .saturating_add(tap)
                            .saturating_sub(radius)
                            .min(width.saturating_sub(1));
                        sum += tap_at(src, sx, c)?;
                    }
                    let slot = tmp.get_mut((yu * width + x) * 4 + c).ok_or_else(|| {
                        PipeError::Backend("demo blur scratch is short".to_owned())
                    })?;
                    *slot = sum / count;
                }
            }
        }
        for y in 0..height_u32 {
            let dst = output.row_mut(y)?;
            let yu = y as usize;
            for x in 0..width {
                for c in 0..4 {
                    let mut sum = 0.0f32;
                    for tap in 0..span {
                        let sy = yu
                            .saturating_add(tap)
                            .saturating_sub(radius)
                            .min(height.saturating_sub(1));
                        sum += tap_at(&tmp, sy * width + x, c)?;
                    }
                    let slot = dst
                        .get_mut(x * 4 + c)
                        .ok_or_else(|| PipeError::Backend("demo blur row is short".to_owned()))?;
                    *slot = sum / count;
                }
            }
        }
        Ok(())
    }
}

/// One streaming render's facts for the resource table.
struct StepFacts {
    /// The mode word the record reported.
    mode: &'static str,
    /// Planned pieces the run executed.
    pieces: u64,
    /// Wall milliseconds for request plus drain.
    millis: f64,
}

/// Runs one over-limit full render and returns its facts.
#[expect(clippy::too_many_arguments)]
// one demo step over its context; a params struct would just rename the args
fn run_streamed_step(
    engine: &mut Engine,
    seen: &Rc<RefCell<Vec<Event>>>,
    photo: &str,
    want_mode: StreamMode,
    want_pieces: Option<u64>,
    fetches: &Arc<AtomicUsize>,
    regions: &Arc<Mutex<Vec<FrameExtent>>>,
    out: &mut dyn FnMut(&str),
) -> Result<StepFacts, Error> {
    let mark = seen.borrow().len();
    let fetch_before = fetches.load(Ordering::SeqCst);
    let region_before = regions.lock().map_or(0, |held| held.len());
    let tick = Instant::now();
    let (generation, _) = ask(engine, photo, "full")?;
    drain_until_generation(engine, seen, photo, "full", generation, DRAIN_TIMEOUT)?;
    let millis = tick.elapsed().as_secs_f64() * 1000.0;
    let mut fresh = fresh_render_events(seen, mark);
    // A typed failure (spill limit, refusal) reports its own reason; only a
    // silent whole-frame success means the frame never streamed.
    if let Some(Event::RenderFailed { reason, .. }) = fresh.pop() {
        return Err(Error::new(format!("streaming run failed typed: {reason}")));
    }
    let record = engine
        .last_render_record(photo, RenderKind::Full)
        .ok_or_else(|| Error::new("streaming render left no record"))?;
    let streamed = record.streamed.ok_or_else(|| {
        Error::new("the over-limit frame never streamed (it fit the whole-frame budget?)")
    })?;
    if streamed.mode != want_mode {
        return Err(Error::new(format!(
            "want mode {}, got {}",
            want_mode.name(),
            streamed.mode.name()
        )));
    }
    if let Some(want) = want_pieces
        && streamed.pieces != want
    {
        return Err(Error::new(format!(
            "want {want} pieces, got {}",
            streamed.pieces
        )));
    }
    // No whole fetch on the streaming path: the probe sized the frame, then
    // one region call per piece.
    if fetches.load(Ordering::SeqCst) != fetch_before {
        return Err(Error::new("the streamed run fetched whole"));
    }
    let region_calls = regions.lock().map_or(0, |held| held.len()) - region_before;
    if u64::try_from(region_calls).unwrap_or(u64::MAX) != streamed.pieces {
        return Err(Error::new(format!(
            "the run served {} regions for {} pieces",
            region_calls, streamed.pieces
        )));
    }
    let mut fresh = fresh_render_events(seen, mark);
    match fresh.pop() {
        Some(Event::RenderReady { .. }) if fresh.is_empty() => {}
        other => {
            return Err(Error::new(format!(
                "want exactly one ready event, got {other:?}"
            )));
        }
    }
    print_record(out, &record);
    Ok(StepFacts {
        mode: streamed.mode.name(),
        pieces: streamed.pieces,
        millis,
    })
}

/// Spill-directory entries, or a failure count when unreadable.
fn spill_entries(spill: &std::path::Path) -> usize {
    std::fs::read_dir(spill).map_or(usize::MAX, Iterator::count)
}

/// Runs the demo, printing each step. Fails on any violated expectation.
///
/// # Errors
///
/// Returns [`Error`] when the size, a command, a drain, or an expectation
/// fails.
pub fn stream_demo(
    mp: u32,
    only: Option<StreamOnly>,
    out: &mut dyn FnMut(&str),
) -> Result<(), Error> {
    if !(1..=2000).contains(&mp) {
        return Err(Error::new(format!(
            "stream-demo: --mp wants 1..=2000, got {mp}"
        )));
    }
    let tmp = crate::util::make_temp_dir("lightamer-stream-demo")?;
    let result = stream_demo_inner(mp, only, &tmp, out);
    crate::util::remove_dir_quiet(&tmp);
    result
}

#[expect(clippy::too_many_lines)] // a linear demo script; splitting would scatter the step order
fn stream_demo_inner(
    mp: u32,
    only: Option<StreamOnly>,
    tmp: &std::path::Path,
    out: &mut dyn FnMut(&str),
) -> Result<(), Error> {
    let (width, height) = dims_for_mp(mp)?;
    let spill = tmp.join("spill");
    std::fs::create_dir(&spill)
        .map_err(|err| Error::new(format!("cannot make spill dir: {err}")))?;
    let mut engine = Engine::open_draft(["big"]);
    engine.set_param_lookup(|_| Some(lightamer_iop_traits::ParamsDesc::unset()));
    let input = Arc::new(StreamDemoInput::new(width, height));
    let fetches = Arc::clone(&input.fetches);
    let regions = Arc::clone(&input.regions);
    engine.set_input_source(input);
    let gain: SharedModule = Arc::new(DemoGain::new());
    let blur: SharedModule = Arc::new(DemoBlur::new());
    let table = HashMap::from([(gain.id().to_owned(), gain), (blur.id().to_owned(), blur)]);
    let source: lightamer_engine::SharedModuleSource = Arc::new(table);
    engine.set_module_source(source);
    engine.set_render_config(EngineConfig {
        spill_dir: Some(spill.clone()),
        ..EngineConfig::default()
    });
    let seen = Rc::new(RefCell::new(Vec::new()));
    let sink = Rc::clone(&seen);
    engine.subscribe(Rc::new(move |event, _| {
        sink.borrow_mut().push(event.clone());
    }));
    for (multi, gain) in [1.0, 1.5, 2.0, 2.5, 3.0].into_iter().enumerate() {
        #[expect(clippy::cast_possible_truncation)] // five demo steps; the index always fits u32
        let multi = multi as u32;
        develop_gain(&mut engine, "big", multi, gain, 0.0)?;
    }
    out("  five demo_gain instances sit on the photo's chain");

    let mut step1: Option<StepFacts> = None;
    if only.is_none_or(|step| step == StreamOnly::Strip) {
        out(&format!(
            "step 1: render {mp}MP over the whole-frame limit (full): strips"
        ));
        let strips = u64::from(height.div_ceil(64));
        let facts = run_streamed_step(
            &mut engine,
            &seen,
            "big",
            StreamMode::Strip,
            Some(strips),
            &fetches,
            &regions,
            out,
        )?;
        out(&format!(
            "step 1: mode={} pieces={} in {:.0}ms",
            facts.mode, facts.pieces, facts.millis
        ));
        step1 = Some(facts);
        if only.is_some() {
            out("demo: ALL GREEN");
            return Ok(());
        }
    }

    let mut step2: Option<StepFacts> = None;
    if only.is_none_or(|step| step == StreamOnly::Block) {
        out("step 2: add the blur module (radius 8): blocks");
        // The blur instance joins under its own id (multi 0 of demo_blur).
        engine
            .execute(
                "develop.set",
                &serde_json::json!({"ids": ["big"], "module": "demo_blur", "multi": 0,
                    "patch": {"gain": {"type": "float", "value": 0.0}}}),
            )
            .map_err(|err| Error::new(err.to_string()))?;
        let facts = run_streamed_step(
            &mut engine,
            &seen,
            "big",
            StreamMode::Block,
            None,
            &fetches,
            &regions,
            out,
        )?;
        out(&format!(
            "step 2: mode={} pieces={} in {:.0}ms",
            facts.mode, facts.pieces, facts.millis
        ));
        step2 = Some(facts);
        if only.is_some() {
            out("demo: ALL GREEN");
            return Ok(());
        }
    }

    out("step 3: spill limit refuses typed before any piece");
    let mut small = Engine::open_draft(["tiny"]);
    small.set_param_lookup(|_| Some(lightamer_iop_traits::ParamsDesc::unset()));
    small.set_input_source(Arc::new(StreamDemoInput::new(width, height)));
    let gain: SharedModule = Arc::new(DemoGain::new());
    let table = HashMap::from([(gain.id().to_owned(), gain)]);
    small.set_module_source(Arc::new(table));
    small.set_render_config(EngineConfig {
        spill_byte_limit: 1024 * 1024,
        spill_dir: Some(spill.clone()),
        ..EngineConfig::default()
    });
    let small_seen = Rc::new(RefCell::new(Vec::new()));
    let small_sink = Rc::clone(&small_seen);
    small.subscribe(Rc::new(move |event, _| {
        small_sink.borrow_mut().push(event.clone());
    }));
    develop_gain(&mut small, "tiny", 0, 2.0, 0.0)?;
    // Two nodes: the second charges input + output, so the footprint refuses
    // whole-frame and the run reaches streaming (where the spill limit bites).
    // A single node would fit whole and never consult the limit.
    develop_gain(&mut small, "tiny", 1, 2.0, 0.0)?;
    let mark = small_seen.borrow().len();
    let (gen3, _) = ask(&mut small, "tiny", "full")?;
    drain_until_generation(&mut small, &small_seen, "tiny", "full", gen3, DRAIN_TIMEOUT)?;
    let mut fresh = fresh_render_events(&small_seen, mark);
    let reason = match fresh.pop() {
        Some(Event::RenderFailed { reason, .. }) if fresh.is_empty() => reason,
        other => {
            return Err(Error::new(format!(
                "want exactly one typed failure, got popped {other:?} with rest {fresh:?}"
            )));
        }
    };
    if !reason.contains("1048576-byte limit") {
        return Err(Error::new(format!(
            "spill refusal names no limit: {reason}"
        )));
    }
    if spill_entries(&spill) != 0 {
        return Err(Error::new("the refused run left spill files"));
    }
    if small.render_budget_used(RenderKind::Full) != 0 {
        return Err(Error::new("the refused run holds budget"));
    }
    out(&format!("step 3: spill limit refused: {reason}"));

    out("step 4: fire three generations; only the latest reports");
    let mark = seen.borrow().len();
    for gain in [4.0, 5.0, 6.0] {
        develop_gain(&mut engine, "big", 0, gain, 0.0)?;
        ask(&mut engine, "big", "full")?;
    }
    let last = engine.render_generation("big", RenderKind::Full);
    drain_until_generation(&mut engine, &seen, "big", "full", last, DRAIN_TIMEOUT)?;
    let mut fresh = fresh_render_events(&seen, mark);
    let generation = match fresh.pop() {
        Some(Event::RenderReady { generation, .. }) if fresh.is_empty() => generation,
        other => {
            return Err(Error::new(format!(
                "want exactly the latest ready event, got popped {other:?} with rest {fresh:?}"
            )));
        }
    };
    if generation != last {
        return Err(Error::new(format!(
            "ready generation {generation} is not the latest {last}"
        )));
    }
    out(&format!(
        "step 4: only generation {generation} reported ready"
    ));

    out("step 5: cancel mid-stream; budget back, spill clean");
    develop_gain(&mut engine, "big", 0, 2.0, 5.0)?;
    let mark = seen.borrow().len();
    let (gen5, job5) = ask(&mut engine, "big", "full")?;
    std::thread::sleep(std::time::Duration::from_millis(500));
    engine
        .execute(
            "render.cancel",
            &serde_json::json!({"photo": "big", "kind": "full"}),
        )
        .map_err(|err| Error::new(err.to_string()))?;
    drain_until_job(&mut engine, job5, DRAIN_TIMEOUT)?;
    let fresh = fresh_render_events(&seen, mark);
    if !fresh.is_empty() {
        return Err(Error::new(format!(
            "the cancelled generation {gen5} still reported {fresh:?}"
        )));
    }
    if engine.render_budget_used(RenderKind::Full) != 0 {
        return Err(Error::new("the cancelled run holds budget"));
    }
    if spill_entries(&spill) != 0 {
        return Err(Error::new("the cancelled run left spill files"));
    }
    out("step 5: no render event: ok, budget back, spill clean");

    out("step 6: resource table (this process measured)");
    if let (Some(one), Some(two)) = (step1.as_ref(), step2.as_ref()) {
        out(&format!(
            "  strips: mode={} pieces={} in {:.0}ms",
            one.mode, one.pieces, one.millis
        ));
        out(&format!(
            "  blocks: mode={} pieces={} in {:.0}ms",
            two.mode, two.pieces, two.millis
        ));
    }
    let defaults = EngineConfig::default();
    out(&format!(
        "  frame {width}x{height} ({}MP); spill limit {} bytes; threshold {} bytes; kept cap {} bytes",
        mp, defaults.spill_byte_limit, defaults.spill_memory_threshold, defaults.kept_bytes_limit,
    ));
    for kind in RenderKind::ALL {
        out(&format!(
            "  budget used {}: {} bytes",
            kind.name(),
            engine.render_budget_used(kind)
        ));
    }

    out("step 7: clean up");
    crate::util::remove_dir_quiet(tmp);
    out("demo: ALL GREEN");
    Ok(())
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{StreamOnly, dims_for_mp, stream_demo};

    #[test]
    fn dims_for_120mp_are_12000_by_10000() {
        assert_eq!(dims_for_mp(120).unwrap(), (12000, 10000));
        assert!(dims_for_mp(0).is_err());
    }

    #[test]
    fn demo_runs_small_and_prints() {
        // 80 MP streams on a 16 GiB machine (past ~78 MP); strips only, so
        // the default suite stays fast.
        let mut lines = Vec::new();
        stream_demo(80, Some(StreamOnly::Strip), &mut |line| {
            lines.push(line.to_owned());
        })
        .unwrap();
        let text = lines.join("\n");
        assert!(text.contains("mode=strip"), "{text}");
        assert!(text.contains("pieces="), "{text}");
        assert!(text.contains("demo: ALL GREEN"), "{text}");
    }
}
