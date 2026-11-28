// SPDX-License-Identifier: GPL-3.0-or-later
//! Render jobs through `execute`: latest-wins generations, cancel, failure,
//! snapshots, and the per-node record — on draft and real sessions alike.
#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

#[allow(dead_code)] // this target leaves some helpers of this module unused
mod common;
#[allow(dead_code)] // this target leaves some helpers of this module unused
mod real_common;

use std::cell::RefCell;
use std::collections::HashMap;
use std::fmt::Write as _;
use std::rc::Rc;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

use lightamer_engine::{
    Engine, Event, InputError, InputSource, JobStatus, ModuleSource, RenderInput, RenderKind,
    SharedModuleSource, command_specs,
};
use lightamer_iop_traits::{
    ColorSpace, CommitData, ImageInfo, IopModule, ModuleDesc, OrderKey, PipeError, PipeState,
    Plane, PlaneMut, Roi, SharedModule, get_float,
};
use lightamer_raster::{Frame, FrameExtent, PixelFormat};
use serde_json::{Value, json};

use common::drain_all;
use real_common::open_real_fixture;

/// Records every event the engine dispatches from here on.
fn recorder(engine: &mut Engine) -> Rc<RefCell<Vec<Event>>> {
    let seen = Rc::new(RefCell::new(Vec::new()));
    let sink = Rc::clone(&seen);
    engine.subscribe(Rc::new(move |event, _| {
        sink.borrow_mut().push(event.clone());
    }));
    seen
}

/// Only the render events, in dispatch order.
fn render_events(seen: &RefCell<Vec<Event>>) -> Vec<Event> {
    seen.borrow()
        .iter()
        .filter(|event| {
            matches!(
                event,
                Event::RenderReady { .. } | Event::RenderFailed { .. }
            )
        })
        .cloned()
        .collect()
}

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

/// What a gain chain should produce, applied in order (same multiply order
/// as the module, so bitwise).
fn scaled(mut pixels: Vec<f32>, gains: &[f32]) -> Vec<f32> {
    for gain in gains {
        for value in &mut pixels {
            *value *= *gain;
        }
    }
    pixels
}

/// Test input source: a fixed gradient, or a fixed refusal.
struct TestInput {
    width: u32,
    height: u32,
    input_id: u64,
    fail: Option<String>,
}

impl TestInput {
    fn gradient(width: u32, height: u32) -> Self {
        Self {
            width,
            height,
            input_id: 11,
            fail: None,
        }
    }

    fn failing(reason: &str) -> Self {
        Self {
            width: 16,
            height: 16,
            input_id: 11,
            fail: Some(reason.to_owned()),
        }
    }
}

impl InputSource for TestInput {
    fn fetch(&self, _photo: &str) -> Result<RenderInput, InputError> {
        if let Some(reason) = &self.fail {
            return Err(InputError::new(reason.clone()));
        }
        let frame = Frame::from_parts(
            gradient_pixels(self.width, self.height),
            FrameExtent::new(0, 0, self.width, self.height),
            PixelFormat::RgbaF32Premul,
        )
        .map_err(|err| InputError::new(err.to_string()))?;
        Ok(RenderInput {
            frame,
            image: ImageInfo::new(self.width, self.height, ColorSpace::Rgb),
            input_id: self.input_id,
        })
    }
}

/// Test gain module: multiplies every pixel by its `gain` parameter.
struct GainModule {
    desc: ModuleDesc,
    calls: Arc<AtomicUsize>,
    sleep: Duration,
}

struct GainCommit {
    gain: f32,
}

impl GainModule {
    fn new(id: &'static str, calls: Arc<AtomicUsize>, sleep: Duration) -> Self {
        let key = OrderKey {
            priority: 1.0,
            tie: 0,
        };
        Self {
            desc: ModuleDesc::stub(id, key, key),
            calls,
            sleep,
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
        self.calls.fetch_add(1, Ordering::SeqCst);
        if !self.sleep.is_zero() {
            std::thread::sleep(self.sleep);
        }
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
            if src.len() != dst.len() {
                return Err(PipeError::RoiMismatch(format!(
                    "test gain row {y} lengths differ: {} vs {}",
                    src.len(),
                    dst.len()
                )));
            }
            dst.copy_from_slice(&src);
            for value in dst.iter_mut() {
                *value *= commit.gain;
            }
        }
        Ok(())
    }
}

/// Test module source: a fixed id-keyed table.
struct MapSource {
    map: HashMap<String, SharedModule>,
}

impl MapSource {
    fn new(modules: Vec<SharedModule>) -> Self {
        Self {
            map: modules
                .into_iter()
                .map(|module| (module.id().to_owned(), module))
                .collect(),
        }
    }
}

impl ModuleSource for MapSource {
    fn lookup(&self, id: &str) -> Option<SharedModule> {
        self.map.get(id).cloned()
    }
}

/// A draft engine with sources installed and every module id accepted.
fn draft_rig(ids: &[&str], modules: Vec<SharedModule>, input: TestInput) -> Engine {
    let mut engine = Engine::open_draft(ids.iter().map(ToString::to_string));
    engine.set_param_lookup(|_| Some(lightamer_iop_traits::ParamsDesc::unset()));
    engine.set_input_source(Arc::new(input));
    if !modules.is_empty() {
        let source: SharedModuleSource = Arc::new(MapSource::new(modules));
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

/// Collects until `job` leaves `Queued` (running or already terminal).
fn wait_past_queued(engine: &mut Engine, job: u64) -> bool {
    for _ in 0..10_000 {
        engine.collect();
        let past = engine
            .job(job)
            .is_some_and(|info| !matches!(info.status, JobStatus::Queued));
        if past {
            return true;
        }
        std::thread::sleep(Duration::from_millis(1));
    }
    false
}

#[test]
fn latest_wins_three_slow_generations_keep_only_third() -> Result<(), Box<dyn std::error::Error>> {
    let calls = Arc::new(AtomicUsize::new(0));
    let module: SharedModule = Arc::new(GainModule::new(
        "mod_gain",
        Arc::clone(&calls),
        Duration::from_millis(300),
    ));
    let mut engine = draft_rig(&["a"], vec![module], TestInput::gradient(16, 16));
    let seen = recorder(&mut engine);
    set_gain(&mut engine, "a", "mod_gain", 0, 2.0)?;
    let (gen1, job1) = request(&mut engine, "a", "preview")?;
    assert_eq!(gen1, 1);
    assert!(wait_past_queued(&mut engine, job1), "job1 never started");
    // The first generation is deep in its 300 ms sleep; two newer requests
    // land before it can finish.
    std::thread::sleep(Duration::from_millis(50));
    set_gain(&mut engine, "a", "mod_gain", 0, 3.0)?;
    let (gen2, job2) = request(&mut engine, "a", "preview")?;
    set_gain(&mut engine, "a", "mod_gain", 0, 4.0)?;
    let (gen3, job3) = request(&mut engine, "a", "preview")?;
    assert_eq!((gen2, gen3), (2, 3));
    drain_all(&mut engine);
    // Exactly one render event, for the third generation.
    assert_eq!(
        render_events(&seen),
        vec![Event::RenderReady {
            photo: "a".to_owned(),
            kind: "preview".to_owned(),
            generation: 3,
        }]
    );
    // The superseded jobs report cancelled; the latest reports whole.
    let status = |job| engine.job(job).map(|info| info.status);
    assert_eq!(status(job1), Some(JobStatus::Finished { cancelled: true }));
    assert_eq!(status(job2), Some(JobStatus::Finished { cancelled: true }));
    assert_eq!(status(job3), Some(JobStatus::Finished { cancelled: false }));
    // The kept pixels are the third generation's (gain 4 over the gradient).
    let kept = engine
        .rendered_image("a", RenderKind::Preview)
        .ok_or("no kept pixels")?;
    assert_eq!(kept.generation, 3);
    assert_eq!((kept.width, kept.height), (16, 16));
    assert_eq!(kept.to_vec(), scaled(gradient_pixels(16, 16), &[4.0]));
    Ok(())
}

#[test]
fn cancel_leaves_no_ready_event_and_next_request_runs() -> Result<(), Box<dyn std::error::Error>> {
    let calls = Arc::new(AtomicUsize::new(0));
    let module: SharedModule = Arc::new(GainModule::new(
        "mod_gain",
        Arc::clone(&calls),
        Duration::from_millis(300),
    ));
    let mut engine = draft_rig(&["a"], vec![module], TestInput::gradient(16, 16));
    let seen = recorder(&mut engine);
    set_gain(&mut engine, "a", "mod_gain", 0, 2.0)?;
    let (gen1, job1) = request(&mut engine, "a", "preview")?;
    let out = engine.execute("render.cancel", &json!({"photo": "a", "kind": "preview"}))?;
    assert_eq!(out.get("cancelled"), Some(&json!(true)));
    assert_eq!(out.get("generation").and_then(Value::as_u64), Some(gen1));
    drain_all(&mut engine);
    assert_eq!(render_events(&seen), Vec::new());
    assert_eq!(
        engine.job(job1).map(|info| info.status),
        Some(JobStatus::Finished { cancelled: true })
    );
    assert!(engine.rendered_image("a", RenderKind::Preview).is_none());
    // A fresh request after the cancel renders normally.
    let (gen2, _) = request(&mut engine, "a", "preview")?;
    assert_eq!(gen2, 2);
    drain_all(&mut engine);
    assert_eq!(
        render_events(&seen),
        vec![Event::RenderReady {
            photo: "a".to_owned(),
            kind: "preview".to_owned(),
            generation: 2,
        }]
    );
    Ok(())
}

#[test]
fn cancel_without_in_flight_reports_false_and_spawns_nothing()
-> Result<(), Box<dyn std::error::Error>> {
    let calls = Arc::new(AtomicUsize::new(0));
    let module: SharedModule = Arc::new(GainModule::new(
        "mod_gain",
        Arc::clone(&calls),
        Duration::ZERO,
    ));
    let mut engine = draft_rig(&["a"], vec![module], TestInput::gradient(16, 16));
    let out = engine.execute("render.cancel", &json!({"photo": "a", "kind": "preview"}))?;
    assert_eq!(out, json!({"cancelled": false}));
    assert!(engine.jobs().is_empty());
    // A cancel racing completion is the same quiet no-op.
    set_gain(&mut engine, "a", "mod_gain", 0, 2.0)?;
    request(&mut engine, "a", "preview")?;
    drain_all(&mut engine);
    let out = engine.execute("render.cancel", &json!({"photo": "a", "kind": "preview"}))?;
    assert_eq!(out, json!({"cancelled": false}));
    Ok(())
}

#[test]
fn cancel_after_finish_before_collect_still_lands_ready() -> Result<(), Box<dyn std::error::Error>>
{
    let calls = Arc::new(AtomicUsize::new(0));
    let module: SharedModule = Arc::new(GainModule::new(
        "mod_gain",
        Arc::clone(&calls),
        Duration::ZERO,
    ));
    let mut engine = draft_rig(&["a"], vec![module], TestInput::gradient(16, 16));
    let seen = recorder(&mut engine);
    set_gain(&mut engine, "a", "mod_gain", 0, 2.0)?;
    let (gen1, _) = request(&mut engine, "a", "preview")?;
    // A millisecond render with half a second of margin: finished, but no
    // `collect` has run, so the in-flight marker is still set.
    std::thread::sleep(Duration::from_millis(500));
    let out = engine.execute("render.cancel", &json!({"photo": "a", "kind": "preview"}))?;
    assert_eq!(out.get("cancelled"), Some(&json!(true)));
    drain_all(&mut engine);
    // Cancel stops unfinished work; the finished delivery still lands.
    assert_eq!(
        render_events(&seen),
        vec![Event::RenderReady {
            photo: "a".to_owned(),
            kind: "preview".to_owned(),
            generation: gen1,
        }]
    );
    Ok(())
}

#[test]
fn supersede_isolated_across_kinds_and_photos() -> Result<(), Box<dyn std::error::Error>> {
    let calls = Arc::new(AtomicUsize::new(0));
    let module: SharedModule = Arc::new(GainModule::new(
        "mod_gain",
        Arc::clone(&calls),
        Duration::ZERO,
    ));
    let mut engine = draft_rig(&["a", "b"], vec![module], TestInput::gradient(16, 16));
    let seen = recorder(&mut engine);
    set_gain(&mut engine, "a", "mod_gain", 0, 2.0)?;
    set_gain(&mut engine, "b", "mod_gain", 0, 5.0)?;
    // All three queue while the pool is gated, so none can finish before
    // the others are requested; distinct pairs never supersede anyway.
    let gate = common::gate_pool(&mut engine);
    let (preview_a, _) = request(&mut engine, "a", "preview")?;
    let (full_a, _) = request(&mut engine, "a", "full")?;
    let (preview_b, _) = request(&mut engine, "b", "preview")?;
    assert_eq!((preview_a, full_a, preview_b), (1, 1, 1));
    drop(gate);
    drain_all(&mut engine);
    let mut ready = render_events(&seen);
    ready.sort_by(|a, b| format!("{a:?}").cmp(&format!("{b:?}")));
    assert_eq!(ready.len(), 3);
    for event in &ready {
        assert!(
            matches!(event, Event::RenderReady { generation: 1, .. }),
            "{event:?}"
        );
    }
    let kept_a = engine
        .rendered_image("a", RenderKind::Preview)
        .ok_or("a/preview kept nothing")?;
    assert_eq!(kept_a.to_vec(), scaled(gradient_pixels(16, 16), &[2.0]));
    let kept_b = engine
        .rendered_image("b", RenderKind::Preview)
        .ok_or("b/preview kept nothing")?;
    assert_eq!(kept_b.to_vec(), scaled(gradient_pixels(16, 16), &[5.0]));
    Ok(())
}

#[test]
fn module_commit_failure_reports_failed_with_reason_and_returns_budget()
-> Result<(), Box<dyn std::error::Error>> {
    let calls = Arc::new(AtomicUsize::new(0));
    let module: SharedModule = Arc::new(GainModule::new(
        "mod_gain",
        Arc::clone(&calls),
        Duration::ZERO,
    ));
    let mut engine = draft_rig(&["a"], vec![module], TestInput::gradient(16, 16));
    let seen = recorder(&mut engine);
    // A text where the gain float goes: `develop.set` keeps undeclared
    // values, the module's commit refuses them.
    engine.execute(
        "develop.set",
        &json!({"ids": ["a"], "module": "mod_gain",
                "patch": {"gain": {"type": "text", "value": "xx"}}}),
    )?;
    request(&mut engine, "a", "preview")?;
    drain_all(&mut engine);
    let events = render_events(&seen);
    assert_eq!(events.len(), 1);
    let Event::RenderFailed {
        generation, reason, ..
    } = &events[0]
    else {
        return Err("want one failed event".into());
    };
    assert_eq!(*generation, 1);
    assert!(reason.contains("mod_gain"), "{reason}");
    assert!(engine.rendered_image("a", RenderKind::Preview).is_none());
    assert_eq!(engine.render_budget_used(RenderKind::Preview), 0);
    let record = engine
        .last_render_record("a", RenderKind::Preview)
        .ok_or("no record for the failed render")?;
    assert!(record.nodes.is_empty());
    Ok(())
}

#[test]
fn input_failure_reports_failed_with_reason_and_returns_budget()
-> Result<(), Box<dyn std::error::Error>> {
    let calls = Arc::new(AtomicUsize::new(0));
    let module: SharedModule = Arc::new(GainModule::new(
        "mod_gain",
        Arc::clone(&calls),
        Duration::ZERO,
    ));
    let mut engine = draft_rig(&["a"], vec![module], TestInput::failing("no such negative"));
    let seen = recorder(&mut engine);
    set_gain(&mut engine, "a", "mod_gain", 0, 2.0)?;
    request(&mut engine, "a", "preview")?;
    drain_all(&mut engine);
    let events = render_events(&seen);
    assert_eq!(events.len(), 1);
    let Event::RenderFailed { reason, .. } = &events[0] else {
        return Err("want one failed event".into());
    };
    assert!(reason.contains("no such negative"), "{reason}");
    assert!(engine.rendered_image("a", RenderKind::Preview).is_none());
    assert_eq!(engine.render_budget_used(RenderKind::Preview), 0);
    Ok(())
}

#[test]
fn request_returns_before_slow_job_finishes() -> Result<(), Box<dyn std::error::Error>> {
    let calls = Arc::new(AtomicUsize::new(0));
    let module: SharedModule = Arc::new(GainModule::new(
        "mod_gain",
        Arc::clone(&calls),
        Duration::from_millis(500),
    ));
    let mut engine = draft_rig(&["a"], vec![module], TestInput::gradient(16, 16));
    set_gain(&mut engine, "a", "mod_gain", 0, 2.0)?;
    let (_, job) = request(&mut engine, "a", "preview")?;
    // The command is back while 500 ms of module sleep still lie ahead.
    let status = engine.job(job).map(|info| info.status);
    assert!(
        status.as_ref().is_some_and(|status| !status.is_terminal()),
        "job finished before the command returned: {status:?}"
    );
    drain_all(&mut engine);
    Ok(())
}

#[test]
fn request_rejects_unknown_missing_and_bad_kind_without_spawning() {
    let calls = Arc::new(AtomicUsize::new(0));
    let module: SharedModule = Arc::new(GainModule::new(
        "mod_gain",
        Arc::clone(&calls),
        Duration::ZERO,
    ));
    let mut engine = draft_rig(&["a"], vec![module], TestInput::gradient(16, 16));
    let err = engine
        .execute(
            "render.request",
            &json!({"photo": "a", "kind": "preview", "bogus": 1}),
        )
        .expect_err("unknown param runs");
    assert!(
        matches!(err, lightamer_engine::CommandError::UnknownParam { .. }),
        "{err}"
    );
    let err = engine
        .execute("render.request", &json!({"photo": "a"}))
        .expect_err("missing kind runs");
    assert!(
        matches!(err, lightamer_engine::CommandError::MissingParam { .. }),
        "{err}"
    );
    let err = engine
        .execute("render.request", &json!({"photo": "a", "kind": "fitted"}))
        .expect_err("bad kind runs");
    assert!(
        matches!(err, lightamer_engine::CommandError::BadParam { .. }),
        "{err}"
    );
    let err = engine
        .execute("render.cancel", &json!({"photo": "a", "kind": "fitted"}))
        .expect_err("bad kind cancels");
    assert!(
        matches!(err, lightamer_engine::CommandError::BadParam { .. }),
        "{err}"
    );
    assert!(engine.jobs().is_empty());
    assert_eq!(engine.render_generation("a", RenderKind::Preview), 0);
}

#[test]
fn request_without_input_source_is_typed_and_spawns_nothing() {
    let mut engine = Engine::open_draft(["a"]);
    engine.set_param_lookup(|_| Some(lightamer_iop_traits::ParamsDesc::unset()));
    let err = engine
        .execute("render.request", &json!({"photo": "a", "kind": "preview"}))
        .expect_err("request runs without an input source");
    assert!(
        matches!(err, lightamer_engine::CommandError::NoInputSource { .. }),
        "{err}"
    );
    assert!(engine.jobs().is_empty());
}

#[test]
fn empty_module_source_renders_identity_and_records_skips() -> Result<(), Box<dyn std::error::Error>>
{
    let mut engine = draft_rig(&["a"], Vec::new(), TestInput::gradient(16, 16));
    let seen = recorder(&mut engine);
    set_gain(&mut engine, "a", "mod_gain", 0, 2.0)?;
    set_gain(&mut engine, "a", "mod_gain", 1, 3.0)?;
    request(&mut engine, "a", "preview")?;
    drain_all(&mut engine);
    assert_eq!(render_events(&seen).len(), 1);
    let kept = engine
        .rendered_image("a", RenderKind::Preview)
        .ok_or("no kept pixels")?;
    assert_eq!(kept.to_vec(), gradient_pixels(16, 16));
    let record = engine
        .last_render_record("a", RenderKind::Preview)
        .ok_or("no record")?;
    assert!(record.nodes.is_empty());
    assert_eq!(record.skipped.len(), 2);
    for skipped in &record.skipped {
        assert_eq!(skipped.reason, "unknown-module");
    }
    assert_eq!(engine.render_budget_used(RenderKind::Preview), 0);
    Ok(())
}

#[test]
fn render_uses_request_time_settings_snapshot() -> Result<(), Box<dyn std::error::Error>> {
    let calls = Arc::new(AtomicUsize::new(0));
    let module: SharedModule = Arc::new(GainModule::new(
        "mod_gain",
        Arc::clone(&calls),
        Duration::ZERO,
    ));
    let mut engine = draft_rig(&["a"], vec![module], TestInput::gradient(16, 16));
    set_gain(&mut engine, "a", "mod_gain", 0, 2.0)?;
    let gate = common::gate_pool(&mut engine);
    request(&mut engine, "a", "preview")?;
    // An edit while the job queues: no new request, so the queued render
    // still owes the request-time gain of 2.
    set_gain(&mut engine, "a", "mod_gain", 0, 5.0)?;
    drop(gate);
    drain_all(&mut engine);
    let kept = engine
        .rendered_image("a", RenderKind::Preview)
        .ok_or("no kept pixels")?;
    assert_eq!(kept.generation, 1);
    assert_eq!(kept.to_vec(), scaled(gradient_pixels(16, 16), &[2.0]));
    Ok(())
}

#[test]
fn chain_order_and_skips_match_registry_and_switches() -> Result<(), Box<dyn std::error::Error>> {
    let calls_a = Arc::new(AtomicUsize::new(0));
    let calls_b = Arc::new(AtomicUsize::new(0));
    let module_a: SharedModule = Arc::new(GainModule::new(
        "mod_gain_a",
        Arc::clone(&calls_a),
        Duration::ZERO,
    ));
    let module_b: SharedModule = Arc::new(GainModule::new(
        "mod_gain_b",
        Arc::clone(&calls_b),
        Duration::ZERO,
    ));
    let mut engine = draft_rig(
        &["a"],
        vec![module_a, module_b],
        TestInput::gradient(16, 16),
    );
    // Inserted out of order on purpose: the chain sorts by (module, multi).
    set_gain(&mut engine, "a", "mod_gain_b", 0, 3.0)?;
    set_gain(&mut engine, "a", "mod_gain_a", 0, 2.0)?;
    engine.execute(
        "develop.set",
        &json!({"ids": ["a"], "module": "mod_gain_z", "enabled": false,
                "patch": {"gain": {"type": "float", "value": 9.0}}}),
    )?;
    set_gain(&mut engine, "a", "mod_missing", 0, 7.0)?;
    request(&mut engine, "a", "preview")?;
    drain_all(&mut engine);
    let kept = engine
        .rendered_image("a", RenderKind::Preview)
        .ok_or("no kept pixels")?;
    assert_eq!(kept.to_vec(), scaled(gradient_pixels(16, 16), &[2.0, 3.0]));
    let record = engine
        .last_render_record("a", RenderKind::Preview)
        .ok_or("no record")?;
    let ids: Vec<&str> = record.nodes.iter().map(|node| node.id.as_str()).collect();
    assert_eq!(ids, vec!["mod_gain_a", "mod_gain_b"]);
    let skips: Vec<(&str, &str)> = record
        .skipped
        .iter()
        .map(|skipped| (skipped.id.as_str(), skipped.reason))
        .collect();
    assert_eq!(
        skips,
        vec![
            ("mod_gain_z", "disabled"),
            ("mod_missing", "unknown-module"),
        ]
    );
    Ok(())
}

#[test]
fn record_matches_module_side_process_counts() -> Result<(), Box<dyn std::error::Error>> {
    let calls = Arc::new(AtomicUsize::new(0));
    let module: SharedModule = Arc::new(GainModule::new(
        "mod_gain",
        Arc::clone(&calls),
        Duration::ZERO,
    ));
    let mut engine = draft_rig(&["a"], vec![module], TestInput::gradient(16, 16));
    set_gain(&mut engine, "a", "mod_gain", 0, 2.0)?;
    set_gain(&mut engine, "a", "mod_gain", 1, 3.0)?;
    set_gain(&mut engine, "a", "mod_gain", 2, 4.0)?;
    request(&mut engine, "a", "preview")?;
    drain_all(&mut engine);
    set_gain(&mut engine, "a", "mod_gain", 1, 5.0)?;
    request(&mut engine, "a", "preview")?;
    drain_all(&mut engine);
    let record = engine
        .last_render_record("a", RenderKind::Preview)
        .ok_or("no record")?;
    assert_eq!(record.generation, 2);
    let hits: Vec<bool> = record.nodes.iter().map(|node| node.hit).collect();
    assert_eq!(hits, vec![true, false, false]);
    let counts: Vec<u32> = record.nodes.iter().map(|node| node.process_calls).collect();
    assert_eq!(counts, vec![0, 1, 1]);
    assert_eq!(calls.load(Ordering::SeqCst), 5);
    assert_eq!(record.nodes[0].millis.to_bits(), 0.0f64.to_bits());
    assert!(record.nodes[1].millis >= 0.0);
    Ok(())
}

#[test]
fn registry_grows_by_two_with_unique_params() {
    let specs = command_specs();
    assert_eq!(specs.len(), 24);
    for id in ["render.request", "render.cancel"] {
        let spec = specs
            .iter()
            .find(|spec| spec.id == id)
            .expect("render command is not registered");
        let names: Vec<&str> = spec.params.iter().map(|decl| decl.name).collect();
        assert_eq!(names, vec!["photo", "kind"]);
    }
}

/// The store's committed histories as one comparable string.
fn store_dump(db: &std::path::Path) -> Result<String, Box<dyn std::error::Error>> {
    let connection = rusqlite::Connection::open(db)?;
    let mut ids = lightamer_catalog::list_photo_uuids(&connection)?;
    ids.sort();
    let mut dump = String::new();
    for id in &ids {
        let record = lightamer_catalog::find_photo_by_uuid(&connection, id)?
            .ok_or("photo vanished mid-dump")?;
        let read = lightamer_catalog::read_history(&connection, record.id)?;
        writeln!(dump, "{id}|{}", read.cursor).unwrap();
        for step in &read.steps {
            writeln!(dump, "{}|{}", step.label, step.settings_json).unwrap();
        }
    }
    Ok(dump)
}

#[test]
fn real_session_renders_and_leaves_store_untouched() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("render-real-clean", 2)?;
    let calls = Arc::new(AtomicUsize::new(0));
    let module: SharedModule = Arc::new(GainModule::new(
        "mod_gain",
        Arc::clone(&calls),
        Duration::ZERO,
    ));
    fixture
        .engine
        .set_input_source(Arc::new(TestInput::gradient(16, 16)));
    let source: SharedModuleSource = Arc::new(MapSource::new(vec![module]));
    fixture.engine.set_module_source(source);
    let seen = recorder(&mut fixture.engine);
    let photo = fixture.uuids[0].clone();
    real_common::set_float(&mut fixture.engine, &photo, "mod_gain", "gain", 2.0)?;
    let before = store_dump(&fixture.db)?;
    let (generation, _) = request(&mut fixture.engine, &photo, "preview")?;
    drain_all(&mut fixture.engine);
    assert_eq!(
        render_events(&seen),
        vec![Event::RenderReady {
            photo: photo.clone(),
            kind: "preview".to_owned(),
            generation,
        }]
    );
    let kept = fixture
        .engine
        .rendered_image(&photo, RenderKind::Preview)
        .ok_or("no kept pixels")?;
    assert_eq!(kept.to_vec(), scaled(gradient_pixels(16, 16), &[2.0]));
    assert_eq!(store_dump(&fixture.db)?, before);
    // Closing drops the kept pixels with the session.
    real_common::close_fixture(&mut fixture)?;
    assert!(
        fixture
            .engine
            .rendered_image(&photo, RenderKind::Preview)
            .is_none()
    );
    Ok(())
}

#[test]
fn real_session_supersede_keeps_only_latest() -> Result<(), Box<dyn std::error::Error>> {
    let mut fixture = open_real_fixture("render-real-latest", 1)?;
    let calls = Arc::new(AtomicUsize::new(0));
    let module: SharedModule = Arc::new(GainModule::new(
        "mod_gain",
        Arc::clone(&calls),
        Duration::from_millis(300),
    ));
    fixture
        .engine
        .set_input_source(Arc::new(TestInput::gradient(16, 16)));
    let source: SharedModuleSource = Arc::new(MapSource::new(vec![module]));
    fixture.engine.set_module_source(source);
    let seen = recorder(&mut fixture.engine);
    let photo = fixture.uuids[0].clone();
    real_common::set_float(&mut fixture.engine, &photo, "mod_gain", "gain", 2.0)?;
    let (_, job1) = request(&mut fixture.engine, &photo, "preview")?;
    assert!(
        wait_past_queued(&mut fixture.engine, job1),
        "job1 never started"
    );
    std::thread::sleep(Duration::from_millis(50));
    real_common::set_float(&mut fixture.engine, &photo, "mod_gain", "gain", 6.0)?;
    let (gen2, _) = request(&mut fixture.engine, &photo, "preview")?;
    assert_eq!(gen2, 2);
    drain_all(&mut fixture.engine);
    assert_eq!(
        render_events(&seen),
        vec![Event::RenderReady {
            photo: photo.clone(),
            kind: "preview".to_owned(),
            generation: 2,
        }]
    );
    let kept = fixture
        .engine
        .rendered_image(&photo, RenderKind::Preview)
        .ok_or("no kept pixels")?;
    assert_eq!(kept.to_vec(), scaled(gradient_pixels(16, 16), &[6.0]));
    real_common::close_fixture(&mut fixture)?;
    Ok(())
}
