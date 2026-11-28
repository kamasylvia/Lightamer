// SPDX-License-Identifier: GPL-3.0-or-later
//! `render-demo`: the B1 render pipeline on a synthetic session, end to end.
//!
//! Builds a throwaway session with three empty placeholder photos, hangs
//! five private gain modules (defined here — the testkit crate stays a
//! dev-dependency) on one photo's chain, and walks seven steps: a first
//! render with its per-node table, a re-render after one parameter edit
//! (node 1 hits on unchanged upstream keys while the edited node and its
//! downstream recompute; node 0 recomputes only because the 4-slot preview
//! cache holds 4 of the 5 planes), three rapid generations (only the latest
//! reports ready), a cancelled slow render (no ready event), an idle-timing
//! render on a second photo, and cleanup. Every step prints; any violated
//! expectation fails the command.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::Arc;
use std::time::{Duration, Instant};

use lightamer_engine::{
    Engine, Event, InputError, InputSource, RenderInput, RenderKind, RenderRecord,
    SharedModuleSource,
};
use lightamer_iop_traits::{
    ColorSpace, CommitData, ImageInfo, IopModule, ModuleDesc, OrderKey, PipeError, PipeState,
    Plane, PlaneMut, Roi, SharedModule, get_float,
};
use lightamer_raster::{Frame, FrameExtent, PixelFormat};
use serde_json::{Map, Value, json};

use crate::util::Error;

/// How long one step waits for its render before failing instead of hanging.
const STEP_TIMEOUT: Duration = Duration::from_secs(60);

/// Synthetic input: a size×size gradient, stable across renders.
struct DemoInput {
    size: u32,
}

impl InputSource for DemoInput {
    fn fetch(&self, _photo: &str) -> Result<RenderInput, InputError> {
        let width = self.size;
        let mut buf = Vec::with_capacity(width as usize * width as usize * 4);
        for y in 0..width {
            for x in 0..width {
                #[expect(clippy::cast_precision_loss)]
                // demo pixels are small; the conversion is exact
                let (x, y) = (x as f32, y as f32);
                buf.extend_from_slice(&[x, y, 0.5, 1.0]);
            }
        }
        let frame = Frame::from_parts(
            buf,
            FrameExtent::new(0, 0, width, width),
            PixelFormat::RgbaF32Premul,
        )
        .map_err(|err| InputError::new(err.to_string()))?;
        Ok(RenderInput {
            frame,
            image: ImageInfo::new(width, width, ColorSpace::Rgb),
            input_id: u64::from(width),
        })
    }
}

/// Private demo gain module behind id `demo_gain`: multiplies every pixel
/// by `gain`, optionally sleeping `sleep_ms` first (the slow render step).
pub(crate) struct DemoGain {
    desc: ModuleDesc,
}

struct DemoGainCommit {
    gain: f32,
    sleep_ms: u64,
}

impl DemoGain {
    pub(crate) fn new() -> Self {
        let key = OrderKey {
            priority: 1.0,
            tie: 0,
        };
        Self {
            desc: ModuleDesc::stub("demo_gain", key, key),
        }
    }

    /// One optional float cell, defaulting to zero when absent or unshaped.
    fn opt_float(params: &Map<String, Value>, key: &str) -> f64 {
        params
            .get(key)
            .and_then(|cell| cell.get("value"))
            .and_then(Value::as_f64)
            .unwrap_or(0.0)
    }
}

impl IopModule for DemoGain {
    fn desc(&self) -> &ModuleDesc {
        &self.desc
    }

    fn commit(
        &self,
        params: &Map<String, Value>,
        _image: &ImageInfo,
        _state: &mut PipeState,
    ) -> Result<CommitData, PipeError> {
        #[expect(clippy::cast_possible_truncation)]
        // demo gains are small; the downcast cannot lose them
        let gain = get_float(params, "gain")? as f32;
        #[expect(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        // clamped at zero above; saturation on absurd values is fine for a demo sleep
        let sleep_ms = Self::opt_float(params, "sleep_ms").max(0.0) as u64;
        Ok(Arc::new(DemoGainCommit { gain, sleep_ms }))
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
        let Some(commit) = data.downcast_ref::<DemoGainCommit>() else {
            return Err(PipeError::Backend(
                "demo gain opened a foreign commit".to_owned(),
            ));
        };
        if commit.sleep_ms > 0 {
            std::thread::sleep(Duration::from_millis(commit.sleep_ms));
        }
        if rin.width != rout.width || rin.height != rout.height {
            return Err(PipeError::RoiMismatch(format!(
                "demo gain needs equal shapes, got {}x{} in and {}x{} out",
                rin.width, rin.height, rout.width, rout.height
            )));
        }
        for y in 0..rout.height.max(0).cast_unsigned() {
            let src = input.row(y)?.to_vec();
            let dst = output.row_mut(y)?;
            if src.len() != dst.len() {
                return Err(PipeError::RoiMismatch(format!(
                    "demo gain row {y} lengths differ: {} vs {}",
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

/// One `develop.set` of a gain (plus an optional sleep) on one instance.
pub(crate) fn develop_gain(
    engine: &mut Engine,
    id: &str,
    multi: u32,
    gain: f64,
    sleep_ms: f64,
) -> Result<(), Error> {
    engine
        .execute(
            "develop.set",
            &json!({"ids": [id], "module": "demo_gain", "multi": multi,
                    "patch": {"gain": {"type": "float", "value": gain},
                              "sleep_ms": {"type": "float", "value": sleep_ms}}}),
        )
        .map_err(|err| Error::new(err.to_string()))?;
    Ok(())
}

/// One `render.request`, returning (generation, job).
pub(crate) fn ask(engine: &mut Engine, photo: &str, kind: &str) -> Result<(u64, u64), Error> {
    let out = engine
        .execute("render.request", &json!({"photo": photo, "kind": kind}))
        .map_err(|err| Error::new(err.to_string()))?;
    let generation = out
        .get("generation")
        .and_then(Value::as_u64)
        .ok_or_else(|| Error::new("render.request hid its generation"))?;
    let job = out
        .get("job")
        .and_then(Value::as_u64)
        .ok_or_else(|| Error::new("render.request hid its job"))?;
    Ok((generation, job))
}

/// Collects until `generation` of one pair reports ready or failed.
/// Generations count per (photo, kind) pair, so the photo and kind join
/// the match — another pair's event with the same number must not pass.
pub(crate) fn drain_until_generation(
    engine: &mut Engine,
    seen: &RefCell<Vec<Event>>,
    photo: &str,
    kind: &str,
    generation: u64,
    timeout: Duration,
) -> Result<(), Error> {
    let start = Instant::now();
    loop {
        engine.collect();
        let done = seen.borrow().iter().any(|event| match event {
            Event::RenderReady {
                photo: ready_photo,
                kind: ready_kind,
                generation: ready,
            }
            | Event::RenderFailed {
                photo: ready_photo,
                kind: ready_kind,
                generation: ready,
                ..
            } => ready_photo == photo && ready_kind == kind && *ready == generation,
            _ => false,
        });
        if done {
            return Ok(());
        }
        if start.elapsed() > timeout {
            return Err(Error::new(format!(
                "generation {generation} of {photo}/{kind} reported nothing in time"
            )));
        }
        std::thread::sleep(Duration::from_millis(5));
    }
}

/// Collects until `job` is terminal.
pub(crate) fn drain_until_job(
    engine: &mut Engine,
    job: u64,
    timeout: Duration,
) -> Result<(), Error> {
    let start = Instant::now();
    loop {
        engine.collect();
        if engine
            .job(job)
            .is_some_and(|info| info.status.is_terminal())
        {
            return Ok(());
        }
        if start.elapsed() > timeout {
            return Err(Error::new(format!("job {job} never finished")));
        }
        std::thread::sleep(Duration::from_millis(5));
    }
}

/// Only the render events.
fn render_only(events: &[Event]) -> Vec<Event> {
    events
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

/// Render events dispatched since `mark` (a past `seen` length).
pub(crate) fn fresh_render_events(seen: &RefCell<Vec<Event>>, mark: usize) -> Vec<Event> {
    let seen = seen.borrow();
    render_only(seen.get(mark..).unwrap_or(&[]))
}

/// Prints one per-node table.
pub(crate) fn print_record(out: &mut dyn FnMut(&str), record: &RenderRecord) {
    out(&format!(
        "  generation {} job {}: {} nodes, {} skipped",
        record.generation,
        record.job,
        record.nodes.len(),
        record.skipped.len()
    ));
    out("  node | id | hit | process calls | ms");
    for (index, node) in record.nodes.iter().enumerate() {
        out(&format!(
            "  {index} | {} multi={} | {} | {} | {:.3}",
            node.id,
            node.multi,
            if node.hit { "hit " } else { "miss" },
            node.process_calls,
            node.millis
        ));
    }
}

/// Runs the seven-step demo, printing each step. Fails on any violated
/// expectation or timeout.
///
/// # Errors
///
/// Returns [`Error`] when the session, a command, a drain, or an
/// expectation fails.
pub fn render_demo(size: u32, out: &mut dyn FnMut(&str)) -> Result<(), Error> {
    if !(8..=1024).contains(&size) {
        return Err(Error::new(format!(
            "render-demo: --size wants 8..=1024, got {size}"
        )));
    }
    let tmp = crate::util::make_temp_dir("lightamer-render-demo")?;
    let result = render_demo_inner(size, &tmp, out);
    crate::util::remove_dir_quiet(&tmp);
    result
}

#[expect(clippy::too_many_lines)] // a linear demo script; splitting would scatter the step order
fn render_demo_inner(
    size: u32,
    tmp: &std::path::Path,
    out: &mut dyn FnMut(&str),
) -> Result<(), Error> {
    out(&format!(
        "step 1: plant a session with three empty photos ({size}x{size})"
    ));
    let setup = crate::bench::bench_setup(tmp, "Demo", 3)?;
    let mut engine = Engine::new();
    engine.set_param_lookup(|_| Some(lightamer_iop_traits::ParamsDesc::unset()));
    engine.set_input_source(Arc::new(DemoInput { size }));
    let gain: SharedModule = Arc::new(DemoGain::new());
    let table = HashMap::from([(gain.id().to_owned(), gain)]);
    let source: SharedModuleSource = Arc::new(table);
    engine.set_module_source(source);
    engine
        .execute(
            "session.open",
            &json!({"path": setup.root.to_string_lossy()}),
        )
        .map_err(|err| Error::new(err.to_string()))?;
    let photos = engine.photo_ids();
    let (Some(first), Some(second)) = (photos.first(), photos.get(1)) else {
        return Err(Error::new("demo session holds fewer than two photos"));
    };
    let first = first.clone();
    let second = second.clone();
    let seen = Rc::new(RefCell::new(Vec::new()));
    let sink = Rc::clone(&seen);
    engine.subscribe(Rc::new(move |event, _| {
        sink.borrow_mut().push(event.clone());
    }));
    for (multi, gain) in [1.0, 1.5, 2.0, 2.5, 3.0].into_iter().enumerate() {
        #[expect(clippy::cast_possible_truncation)] // five demo steps; the index always fits u32
        let multi = multi as u32;
        develop_gain(&mut engine, &first, multi, gain, 0.0)?;
    }
    out("  five demo_gain instances sit on the first photo's chain");

    out("step 2: render once (preview)");
    let (gen1, _) = ask(&mut engine, &first, "preview")?;
    drain_until_generation(&mut engine, &seen, &first, "preview", gen1, STEP_TIMEOUT)?;
    let record = engine
        .last_render_record(&first, RenderKind::Preview)
        .ok_or_else(|| Error::new("first render left no record"))?;
    print_record(out, &record);

    out("step 3: change the middle gain, render again");
    develop_gain(&mut engine, &first, 2, 2.75, 0.0)?;
    let (gen2, _) = ask(&mut engine, &first, "preview")?;
    drain_until_generation(&mut engine, &seen, &first, "preview", gen2, STEP_TIMEOUT)?;
    let record = engine
        .last_render_record(&first, RenderKind::Preview)
        .ok_or_else(|| Error::new("second render left no record"))?;
    print_record(out, &record);
    // Five nodes on a four-slot preview cache: the fifth insert evicts the
    // first plane, so node 0 recomputes on capacity (its key is unchanged —
    // node 1's key folds node 0's contribution, and node 1 hits). This shape
    // leans on the B1-b rules (upstream-most-recently-used reverse touch +
    // oldest-first eviction skipping this run's hits): without them node 0's
    // recompute would evict node 1's plane instead. The edit still recomputes
    // only itself and its downstream.
    let hits: Vec<bool> = record.nodes.iter().map(|node| node.hit).collect();
    if hits != vec![false, true, false, false, false] {
        return Err(Error::new(format!(
            "want [evicted, hit, miss, miss, miss], got {hits:?}"
        )));
    }
    out("  node 1 hits (upstream keys unchanged), nodes 2-4 recompute: ok");
    out("  note: node 0 recomputes only because the 4-slot preview cache");
    out("  holds 4 of the 5 planes; its key is unchanged (node 1 hits on it)");

    out("step 4: fire three generations without waiting (only the latest reports)");
    let mark = seen.borrow().len();
    let mut fired = Vec::new();
    for gain in [1.1, 1.2, 1.3] {
        develop_gain(&mut engine, &first, 0, gain, 0.0)?;
        fired.push(ask(&mut engine, &first, "preview")?);
    }
    let Some(last) = fired.last() else {
        return Err(Error::new("no generations fired"));
    };
    drain_until_generation(&mut engine, &seen, &first, "preview", last.0, STEP_TIMEOUT)?;
    let fresh = fresh_render_events(&seen, mark);
    if fresh.len() != 1 {
        return Err(Error::new(format!(
            "want exactly one render event, got {fresh:?}"
        )));
    }
    let Some(Event::RenderReady { generation, .. }) = fresh.first() else {
        return Err(Error::new(format!("want one ready event, got {fresh:?}")));
    };
    if *generation != last.0 {
        return Err(Error::new(format!(
            "want the ready event for generation {}, got {generation}",
            last.0
        )));
    }
    out(&format!("  render events: {fresh:?}"));
    for (generation, job) in &fired {
        let status = engine
            .job(*job)
            .map_or_else(|| "gone".to_owned(), |info| format!("{:?}", info.status));
        out(&format!("  job {job} generation {generation}: {status}"));
    }

    out("step 5: start a slow render, cancel it (no ready event)");
    develop_gain(&mut engine, &first, 0, 1.3, 1500.0)?;
    let mark = seen.borrow().len();
    let (slow_gen, slow_job) = ask(&mut engine, &first, "preview")?;
    let cancelled = engine
        .execute("render.cancel", &json!({"photo": first, "kind": "preview"}))
        .map_err(|err| Error::new(err.to_string()))?;
    if cancelled.get("cancelled") != Some(&json!(true)) {
        return Err(Error::new(format!(
            "cancel reported no in-flight render: {cancelled}"
        )));
    }
    drain_until_job(&mut engine, slow_job, STEP_TIMEOUT)?;
    let fresh = fresh_render_events(&seen, mark);
    if !fresh.is_empty() {
        return Err(Error::new(format!(
            "a cancelled render must emit no render event, got {fresh:?}"
        )));
    }
    out(&format!(
        "  generation {slow_gen} cancelled, no render event: ok"
    ));
    develop_gain(&mut engine, &first, 0, 1.3, 0.0)?;

    out("step 6: idle timing on the second photo (preview, all miss)");
    for (multi, gain) in [1.1, 1.2, 1.3, 1.4, 1.5].into_iter().enumerate() {
        #[expect(clippy::cast_possible_truncation)] // five demo steps; the index always fits u32
        let multi = multi as u32;
        develop_gain(&mut engine, &second, multi, gain, 0.0)?;
    }
    let (idle_gen, _) = ask(&mut engine, &second, "preview")?;
    drain_until_generation(
        &mut engine,
        &seen,
        &second,
        "preview",
        idle_gen,
        STEP_TIMEOUT,
    )?;
    let record = engine
        .last_render_record(&second, RenderKind::Preview)
        .ok_or_else(|| Error::new("idle render left no record"))?;
    print_record(out, &record);
    if record.nodes.iter().any(|node| node.hit) {
        return Err(Error::new("idle render should miss every node"));
    }

    out("step 7: close the session, remove the temp dir");
    engine
        .execute("session.close", &json!({}))
        .map_err(|err| Error::new(err.to_string()))?;
    out("demo: ALL GREEN");
    Ok(())
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::render_demo;

    #[test]
    fn demo_runs_small_and_reports_green() {
        let mut lines = Vec::new();
        render_demo(32, &mut |line| lines.push(line.to_owned())).unwrap();
        let text = lines.join("\n");
        for step in 1..=7 {
            assert!(text.contains(&format!("step {step}")), "{text}");
        }
        assert!(text.contains("hit"), "{text}");
        assert!(text.contains("miss"), "{text}");
        assert!(text.contains("demo: ALL GREEN"), "{text}");
    }
}
