// SPDX-License-Identifier: GPL-3.0-or-later
//! Streaming renders through `execute`: over-limit auto-switch, retention,
//! and the ignored 200 MP timing run — on draft sessions.
#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

#[allow(dead_code)] // this target leaves some helpers of this module unused
mod common;

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Instant;

use lightamer_engine::{
    Engine, Event, InputError, InputSource, RenderInput, RenderKind, SharedModuleSource, StreamMode,
};
use lightamer_iop_traits::{
    ColorSpace, CommitData, ImageInfo, IopModule, ModuleDesc, OrderKey, PipeError, PipeState,
    Plane, PlaneMut, Roi, SharedModule, TilingReq, get_float,
};
use lightamer_pipeline::{PipeKind, quota_for, singlebuffer_floor};
use lightamer_raster::{Frame, FrameExtent, PixelFormat};
use serde_json::{Value, json};

use common::drain_all;

/// Synthetic pixels: r = x, g = y, b = 0.5, a = 1.0.
fn gradient_pixels(width: u32, height: u32) -> Vec<f32> {
    let mut out = Vec::with_capacity(width as usize * height as usize * 4);
    for y in 0..height {
        for x in 0..width {
            #[expect(clippy::cast_precision_loss)] // test pixels are small; the conversion is exact
            let (x, y) = (x as f32, y as f32);
            out.extend_from_slice(&[x, y, 0.5, 1.0]);
        }
    }
    out
}

/// Synthetic pixels for an absolute region of the same gradient.
fn region_pixels(region: FrameExtent) -> Vec<f32> {
    let cells = u64::from(region.width)
        .saturating_mul(u64::from(region.height))
        .saturating_mul(4);
    let mut out = Vec::with_capacity(usize::try_from(cells).unwrap_or(0));
    for row in 0..region.height {
        for col in 0..region.width {
            let x = region.x.saturating_add_unsigned(col);
            let y = region.y.saturating_add_unsigned(row);
            #[expect(clippy::cast_precision_loss)] // test pixels are small; the conversion is exact
            let (x, y) = (x as f32, y as f32);
            out.extend_from_slice(&[x, y, 0.5, 1.0]);
        }
    }
    out
}

/// Region-capable test input: whole fetches for the facts, lazy regions
/// per piece (an over-limit frame must never fetch whole twice), every
/// region call counted.
struct RegionInput {
    width: u32,
    height: u32,
    fetches: Arc<AtomicUsize>,
    regions: Arc<Mutex<Vec<FrameExtent>>>,
}

impl RegionInput {
    fn new(width: u32, height: u32) -> Self {
        Self {
            width,
            height,
            fetches: Arc::new(AtomicUsize::new(0)),
            regions: Arc::new(Mutex::new(Vec::new())),
        }
    }
}

impl InputSource for RegionInput {
    fn fetch(&self, _photo: &str) -> Result<RenderInput, InputError> {
        self.fetches.fetch_add(1, Ordering::SeqCst);
        let frame = Frame::from_parts(
            gradient_pixels(self.width, self.height),
            FrameExtent::new(0, 0, self.width, self.height),
            PixelFormat::RgbaF32Premul,
        )
        .map_err(|err| InputError::new(err.to_string()))?;
        Ok(RenderInput {
            frame,
            image: ImageInfo::new(self.width, self.height, ColorSpace::Rgb),
            input_id: 11,
        })
    }

    fn fetch_region(&self, _photo: &str, region: FrameExtent) -> Result<RenderInput, InputError> {
        self.regions.lock().unwrap().push(region);
        let frame = Frame::from_parts(region_pixels(region), region, PixelFormat::RgbaF32Premul)
            .map_err(|err| InputError::new(err.to_string()))?;
        Ok(RenderInput {
            frame,
            image: ImageInfo::new(self.width, self.height, ColorSpace::Rgb),
            input_id: 11,
        })
    }
}

/// Test gain module: multiplies every pixel by its `gain` parameter.
struct GainModule {
    desc: ModuleDesc,
}

struct GainCommit {
    gain: f32,
}

impl GainModule {
    fn named(id: &'static str) -> Self {
        let key = OrderKey {
            priority: 1.0,
            tie: 0,
        };
        Self {
            desc: ModuleDesc::stub(id, key, key),
        }
    }
}

impl IopModule for GainModule {
    fn desc(&self) -> &ModuleDesc {
        &self.desc
    }

    fn commit(
        &self,
        params: &serde_json::Map<String, Value>,
        _image: &ImageInfo,
        _state: &mut PipeState,
    ) -> Result<CommitData, PipeError> {
        #[expect(clippy::cast_possible_truncation)]
        // test gains are small; the downcast cannot lose them
        let gain = get_float(params, "gain")? as f32;
        Ok(Arc::new(GainCommit { gain }))
    }

    fn process(
        &self,
        data: &CommitData,
        input: &Plane<'_>,
        output: &mut PlaneMut<'_>,
        rin: Roi,
        rout: Roi,
        _state: &mut PipeState,
    ) -> Result<(), PipeError> {
        let Some(commit) = data.downcast_ref::<GainCommit>() else {
            return Err(PipeError::Backend(
                "test gain opened a foreign commit".to_owned(),
            ));
        };
        if rin.width != rout.width || rin.height != rout.height {
            return Err(PipeError::RoiMismatch(format!(
                "test gain needs equal shapes, got {}x{} in and {}x{} out",
                rin.width, rin.height, rout.width, rout.height
            )));
        }
        for y in 0..rout.height.max(0).cast_unsigned() {
            let src = input.row(y)?.to_vec();
            let dst = output.row_mut(y)?;
            dst.copy_from_slice(&src);
            for value in dst.iter_mut() {
                *value *= commit.gain;
            }
        }
        Ok(())
    }
}

/// Test blur module: honest separable box blur, radius 8, clamped edges.
struct BlurModule {
    desc: ModuleDesc,
}

struct BlurCommit;

impl BlurModule {
    /// Blur radius in pixels, both passes.
    const RADIUS: usize = 8;

    fn named(id: &'static str) -> Self {
        let key = OrderKey {
            priority: 1.0,
            tie: 0,
        };
        Self {
            desc: ModuleDesc::stub(id, key, key),
        }
    }
}

impl IopModule for BlurModule {
    fn desc(&self) -> &ModuleDesc {
        &self.desc
    }

    fn commit(
        &self,
        _params: &serde_json::Map<String, Value>,
        _image: &ImageInfo,
        _state: &mut PipeState,
    ) -> Result<CommitData, PipeError> {
        Ok(Arc::new(BlurCommit))
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
                "test blur planes differ: {}x{} vs {}x{}",
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
                        sum += src[sx * 4 + c];
                    }
                    tmp[(yu * width + x) * 4 + c] = sum / count;
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
                        sum += tmp[(sy * width + x) * 4 + c];
                    }
                    dst[x * 4 + c] = sum / count;
                }
            }
        }
        Ok(())
    }
}

/// A draft engine with sources installed and every module id accepted.
fn draft_rig(ids: &[&str], modules: Vec<SharedModule>, input: RegionInput) -> Engine {
    let mut engine = Engine::open_draft(ids.iter().map(ToString::to_string));
    engine.set_param_lookup(|_| Some(lightamer_iop_traits::ParamsDesc::unset()));
    engine.set_input_source(Arc::new(input));
    if !modules.is_empty() {
        let mut map = HashMap::new();
        for module in modules {
            map.insert(module.id().to_owned(), module);
        }
        let source: SharedModuleSource = Arc::new(map);
        engine.set_module_source(source);
    }
    engine
}

/// One `develop.set` of a gain on one instance.
fn set_gain(
    engine: &mut Engine,
    id: &str,
    module: &str,
    multi: u32,
    gain: f64,
) -> Result<(), Box<dyn std::error::Error>> {
    engine.execute(
        "develop.set",
        &json!({"ids": [id], "module": module, "multi": multi,
                "patch": {"gain": {"type": "float", "value": gain}}}),
    )?;
    Ok(())
}

/// One `render.request`, returning (generation, job).
fn request(
    engine: &mut Engine,
    photo: &str,
    kind: &str,
) -> Result<(u64, u64), Box<dyn std::error::Error>> {
    let out = engine.execute("render.request", &json!({"photo": photo, "kind": kind}))?;
    let generation = out
        .get("generation")
        .and_then(Value::as_u64)
        .ok_or("render.request hid its generation")?;
    let job = out
        .get("job")
        .and_then(Value::as_u64)
        .ok_or("render.request hid its job")?;
    Ok((generation, job))
}

/// Records every event the engine dispatches from here on.
fn recorder(engine: &mut Engine) -> Rc<RefCell<Vec<Event>>> {
    let seen = Rc::new(RefCell::new(Vec::new()));
    let sink = Rc::clone(&seen);
    engine.subscribe(Rc::new(move |event, _| {
        sink.borrow_mut().push(event.clone());
    }));
    seen
}

/// Physical memory in bytes, or `None` when macOS will not answer.
fn physical_memory() -> Option<u64> {
    let out = std::process::Command::new("sysctl")
        .args(["-n", "hw.memsize"])
        .output()
        .ok()?;
    String::from_utf8_lossy(&out.stdout).trim().parse().ok()
}

#[test]
fn full_auto_streams_an_over_limit_frame_end_to_end() -> Result<(), Box<dyn std::error::Error>> {
    // A frame just past this machine's two-node whole-frame limit: with two
    // nodes the second charges input + output, so the limit is
    // (budget - 2 * floor) / 2 bytes, and a hundred extra rows put the frame
    // over it on any machine this suite runs on.
    let phys = physical_memory().ok_or("sysctl hw.memsize refused")?;
    let budget = quota_for(PipeKind::Full, phys).memory_budget;
    let floor = singlebuffer_floor(PipeKind::Full, phys);
    let max_px = (budget - 2 * floor) / 2 / 16;
    let width: u32 = 9000;
    let height = u32::try_from(max_px / u64::from(width) + 100)?; // ~78 MP here
    let strips = u64::from(height.div_ceil(64));
    let gain_a: SharedModule = Arc::new(GainModule::named("mod_gain_a"));
    let gain_b: SharedModule = Arc::new(GainModule::named("mod_gain_b"));
    let mut engine = draft_rig(
        &["a"],
        vec![gain_a, gain_b],
        RegionInput::new(width, height),
    );
    set_gain(&mut engine, "a", "mod_gain_a", 0, 2.0)?;
    set_gain(&mut engine, "a", "mod_gain_b", 0, 0.5)?;
    let (generation, _) = request(&mut engine, "a", "full")?;
    assert_eq!(generation, 1);
    drain_all(&mut engine);
    let record = engine
        .last_render_record("a", RenderKind::Full)
        .ok_or("no record")?;
    let streamed = record
        .streamed
        .ok_or("the over-limit frame never streamed")?;
    assert_eq!(streamed.mode, StreamMode::Strip);
    assert_eq!(streamed.pieces, strips);
    // The 1.2 GiB output exceeds the 1 GiB retention cap on its own: the
    // render reports ready (its record filed) but keeps no pixels.
    assert!(engine.rendered_image("a", RenderKind::Full).is_none());
    Ok(())
}

#[test]
fn retention_read_marks_newest() -> Result<(), Box<dyn std::error::Error>> {
    let gain: SharedModule = Arc::new(GainModule::named("mod_gain"));
    let mut engine = draft_rig(&["a", "b", "c"], vec![gain], RegionInput::new(16, 16));
    engine.set_render_config(lightamer_engine::EngineConfig {
        kept_bytes_limit: 8 * 1024,
        ..lightamer_engine::EngineConfig::default()
    });
    for photo in ["a", "b"] {
        set_gain(&mut engine, photo, "mod_gain", 0, 2.0)?;
        request(&mut engine, photo, "preview")?;
    }
    drain_all(&mut engine);
    assert!(engine.rendered_image("a", RenderKind::Preview).is_some());
    // Reading `a` marked it newest: landing `c` evicts `b`, not `a`.
    set_gain(&mut engine, "c", "mod_gain", 0, 2.0)?;
    request(&mut engine, "c", "preview")?;
    drain_all(&mut engine);
    assert!(engine.rendered_image("a", RenderKind::Preview).is_some());
    assert!(engine.rendered_image("b", RenderKind::Preview).is_none());
    assert!(engine.rendered_image("c", RenderKind::Preview).is_some());
    Ok(())
}

#[test]
fn thumbnail_renders_emit_events_but_keep_no_pixels() -> Result<(), Box<dyn std::error::Error>> {
    let gain: SharedModule = Arc::new(GainModule::named("mod_gain"));
    let mut engine = draft_rig(&["a"], vec![gain], RegionInput::new(16, 16));
    let seen = recorder(&mut engine);
    set_gain(&mut engine, "a", "mod_gain", 0, 2.0)?;
    request(&mut engine, "a", "thumbnail")?;
    drain_all(&mut engine);
    let ready: Vec<Event> = seen
        .borrow()
        .iter()
        .filter(|event| matches!(event, Event::RenderReady { .. }))
        .cloned()
        .collect();
    assert_eq!(ready.len(), 1);
    assert!(engine.rendered_image("a", RenderKind::Thumbnail).is_none());
    assert!(
        engine
            .last_render_record("a", RenderKind::Thumbnail)
            .is_some()
    );
    Ok(())
}
/// Peak resident set in bytes, or zero when the kernel will not answer.
#[expect(unsafe_code)] // one getrusage call; the contract is in the SAFETY comment below
fn peak_rss_bytes() -> u64 {
    // SAFETY: `getrusage` writes a plain struct through a live pointer;
    // a failure (never observed) reports zero instead of a number.
    let mut usage = std::mem::MaybeUninit::<libc::rusage>::zeroed();
    let ok = unsafe { libc::getrusage(libc::RUSAGE_SELF, usage.as_mut_ptr()) == 0 };
    if !ok {
        return 0;
    }
    let usage = unsafe { usage.assume_init() };
    u64::try_from(usage.ru_maxrss).unwrap_or(0)
}

/// One load line when the machine is quiet enough to time, else `None`.
fn quiet_line(label: &str) -> Option<String> {
    let uptime = std::process::Command::new("uptime").output().ok()?;
    let text = String::from_utf8_lossy(&uptime.stdout).into_owned();
    let load_text = text
        .split("load averages:")
        .nth(1)
        .or_else(|| text.split("load average:").nth(1))?;
    let one_minute: f64 = load_text
        .split([',', ' '])
        .find_map(|part| part.trim().parse().ok())?;
    let ncpu = std::process::Command::new("sysctl")
        .args(["-n", "hw.ncpu"])
        .output()
        .ok()
        .and_then(|out| String::from_utf8_lossy(&out.stdout).trim().parse().ok())
        .unwrap_or(4u32);
    if one_minute / f64::from(ncpu) > 1.0 {
        return None;
    }
    Some(format!("{label} load {one_minute:.2} on {ncpu} cpus"))
}

/// Streaming timing: a 200 MP synthetic frame (20000x10000) through five
/// nodes and the engine's own render jobs, strip mode then block mode in
/// one process (serial: parallel runs stack their resident sets and distort
/// the numbers). Ignored by default; run it on a quiet machine in release
/// mode: `cargo test --release -p lightamer-engine --locked -- --ignored
/// stream_200mp --test-threads=1 --nocapture`.
#[test]
#[ignore = "timing bench: needs a quiet machine and a release build"]
fn stream_200mp_through_render_jobs() -> Result<(), Box<dyn std::error::Error>> {
    const WIDTH: u32 = 20000;
    const HEIGHT: u32 = 10000;
    const STOP_RSS_BYTES: u64 = 8 * 1024 * 1024 * 1024;
    let Some(line) = quiet_line("stream 200mp jobs") else {
        println!("stream-200mp-jobs = UNRELIABLE (machine busy; see load line) SKIP-GATE");
        return Ok(());
    };
    println!("stream-200mp-jobs {line}");
    // Strips: five gains; 10000 rows at 64 rows a strip is 157 pieces.
    let mut engine = draft_rig(
        &["strip"],
        vec![
            Arc::new(GainModule::named("mod_g0")),
            Arc::new(GainModule::named("mod_g1")),
            Arc::new(GainModule::named("mod_g2")),
            Arc::new(GainModule::named("mod_g3")),
            Arc::new(GainModule::named("mod_g4")),
        ],
        RegionInput::new(WIDTH, HEIGHT),
    );
    for (slot, gain) in [2.0, 0.5, 1.5, 2.0, 0.5].iter().enumerate() {
        set_gain(&mut engine, "strip", &format!("mod_g{slot}"), 0, *gain)?;
    }
    let tick = Instant::now();
    request(&mut engine, "strip", "full")?;
    drain_all(&mut engine);
    let strip_ms = tick.elapsed().as_secs_f64() * 1000.0;
    let record = engine
        .last_render_record("strip", RenderKind::Full)
        .ok_or("strip run left no record")?;
    let streamed = record.streamed.ok_or("strip run never streamed")?;
    assert_eq!(streamed.mode, StreamMode::Strip);
    assert_eq!(streamed.pieces, 157);
    let strip_peak = peak_rss_bytes();
    println!(
        "stream-200mp-jobs strip peak rss = {}MB in {strip_ms:.0}ms",
        strip_peak / 1024 / 1024
    );
    assert!(
        strip_peak < STOP_RSS_BYTES,
        "strip peak {strip_peak} over the stop line"
    );
    drop(engine);
    // Blocks: the blur's overlap of 8 sums the margin. The side follows the
    // documented block formula over this machine's full budget (32 pieces
    // here: 8 by 4 at side 2605).
    let phys = physical_memory().ok_or("sysctl hw.memsize refused")?;
    let budget = quota_for(PipeKind::Full, phys).memory_budget;
    let bytes_per_pixel = lightamer_pipeline::STREAM_BYTES_PER_PIXEL;
    let side = (budget / 4 / bytes_per_pixel)
        .isqrt()
        .saturating_sub(2 * 8)
        .clamp(512, 8192);
    let side_u32 = u32::try_from(side)?;
    let want_blocks = u64::from(WIDTH.div_ceil(side_u32)) * u64::from(HEIGHT.div_ceil(side_u32));
    let mut engine = draft_rig(
        &["block"],
        vec![
            Arc::new(GainModule::named("mod_g0")),
            Arc::new(GainModule::named("mod_g1")),
            Arc::new(GainModule::named("mod_g2")),
            Arc::new(GainModule::named("mod_g3")),
            Arc::new(BlurModule::named("mod_blur")),
        ],
        RegionInput::new(WIDTH, HEIGHT),
    );
    for (slot, gain) in [2.0, 0.5, 1.5, 2.0].iter().enumerate() {
        set_gain(&mut engine, "block", &format!("mod_g{slot}"), 0, *gain)?;
    }
    set_gain(&mut engine, "block", "mod_blur", 0, 0.0)?;
    let tick = Instant::now();
    request(&mut engine, "block", "full")?;
    drain_all(&mut engine);
    let block_ms = tick.elapsed().as_secs_f64() * 1000.0;
    let record = engine
        .last_render_record("block", RenderKind::Full)
        .ok_or("block run left no record")?;
    let streamed = record.streamed.ok_or("block run never streamed")?;
    assert_eq!(streamed.mode, StreamMode::Block);
    assert_eq!(streamed.pieces, want_blocks);
    let block_peak = peak_rss_bytes();
    println!(
        "stream-200mp-jobs block peak rss = {}MB in {block_ms:.0}ms",
        block_peak / 1024 / 1024
    );
    assert!(
        block_peak < STOP_RSS_BYTES,
        "block peak {block_peak} over the stop line"
    );
    // Both outputs exceed the retention cap alone: ready, filed, kept none.
    assert!(engine.rendered_image("block", RenderKind::Full).is_none());
    Ok(())
}
