// SPDX-License-Identifier: GPL-3.0-or-later
//! Render jobs: `render.request` starts one, `render.cancel` stops it.
//!
//! Commands do bounded work only, so a render — unbounded (a future decode
//! plus a full pipe run) — starts as a job: `render.request` snapshots the
//! photo's current settings, bumps that (photo, kind) pair's generation,
//! cancels whatever render of the pair is still in flight, and returns the
//! generation and job ids at once. The work runs on a pool thread against
//! the snapshot it captured; the pixels travel back through a render
//! delivery channel that [`Engine::collect`][crate::Engine::collect] drains
//! on the engine thread, like the restore deliveries beside it.
//!
//! Latest wins: each (photo, kind) pair keeps one increasing generation.
//! A newer request sets the older job's cancel flag (the same flag the pipe
//! consults between nodes and tiles) and any late delivery from the older
//! generation is dropped on the floor — no pixels kept, no render event.
//! Different photos and different kinds never touch each other.
//!
//! The embedder injects the two sources; the engine owns neither:
//!
//! * [`InputSource`] turns a photo id into pixels, image facts, and an
//!   input identity. It may be slow (decoding lands in B2), so it only ever
//!   runs on a job thread. Without one, `render.request` is a typed error
//!   and no job starts.
//! * [`ModuleSource`] resolves module ids to modules. Without one (or with
//!   ids it does not know) the chain is short or empty and the output
//!   equals the input; unknown ids are skipped and recorded, never an error.
//!
//! The engine builds one [`Pipe`][lightamer_pipeline::Pipe] per kind itself,
//! budgeted from physical memory, and holds each behind its own mutex: two
//! renders of the same kind never run the pipe together, while different
//! kinds run side by side. A superseded job lets go at its next cancel
//! check, so it holds the lock past supersession for at most one `process`
//! call plus the tile loop's checks.
//!
//! This module never touches the store: renders read committed settings and
//! keep their pixels in memory until a newer generation replaces them or
//! the session closes.

use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;
use std::sync::mpsc::{Receiver, Sender};

use lightamer_history::{ModuleInstance, SettingValue};
use lightamer_iop_traits::{ImageInfo, SharedModule};
use lightamer_pipeline::{ModuleLookup, NodeReport, Pipe};
use lightamer_raster::{Frame, FrameExtent};
use serde_json::{Map, Value, json};

use crate::command::{self, CommandSpec, Outcome, ParamKind, ParamSpec, RunCtx, text_req};
use crate::engine::Engine;
use crate::error::CommandError;
use crate::event::Event;
use crate::jobs::{JobCtx, JobId, JobStatus};

/// Physical memory assumed when the real size is unreadable: pipe budgets
/// then derive from 8 GiB instead of failing engine construction.
pub(crate) const FALLBACK_PHYS_BYTES: u64 = 8 * 1024 * 1024 * 1024;

/// Why an instance never reached the pipe: its module id resolves nowhere.
pub const SKIP_UNKNOWN_MODULE: &str = "unknown-module";
/// Why an instance never reached the pipe: its switch is off.
pub const SKIP_DISABLED: &str = "disabled";

/// Which pipe runs a render: same shapes as
/// [`PipeKind`][lightamer_pipeline::PipeKind], as the command vocabulary.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum RenderKind {
    /// Full-resolution pipe.
    Full,
    /// Export pipe.
    Export,
    /// Preview pipe.
    Preview,
    /// Thumbnail pipe.
    Thumbnail,
}

impl RenderKind {
    /// Every kind, in pipe-slot order.
    pub const ALL: [RenderKind; 4] = [
        RenderKind::Full,
        RenderKind::Export,
        RenderKind::Preview,
        RenderKind::Thumbnail,
    ];

    /// The command word for this kind.
    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            RenderKind::Full => "full",
            RenderKind::Export => "export",
            RenderKind::Preview => "preview",
            RenderKind::Thumbnail => "thumbnail",
        }
    }

    /// Parses a command word; [`None`] for anything else.
    #[must_use]
    pub fn parse(text: &str) -> Option<RenderKind> {
        match text {
            "full" => Some(RenderKind::Full),
            "export" => Some(RenderKind::Export),
            "preview" => Some(RenderKind::Preview),
            "thumbnail" => Some(RenderKind::Thumbnail),
            _ => None,
        }
    }

    /// This kind as the pipeline names it.
    pub(crate) const fn pipe_kind(self) -> lightamer_pipeline::PipeKind {
        match self {
            RenderKind::Full => lightamer_pipeline::PipeKind::Full,
            RenderKind::Export => lightamer_pipeline::PipeKind::Export,
            RenderKind::Preview => lightamer_pipeline::PipeKind::Preview,
            RenderKind::Thumbnail => lightamer_pipeline::PipeKind::Thumbnail,
        }
    }
}

/// What a render starts from: pixels, image facts, and the input identity
/// (any change to the decoded input changes it, so the pipe cache never
/// serves a stale plane).
#[derive(Debug)]
pub struct RenderInput {
    /// Caller-built input plane (decoding is B2; B1 renders from this).
    pub frame: Frame,
    /// Decoded-image facts for `commit`.
    pub image: ImageInfo,
    /// Caller-defined input identity.
    pub input_id: u64,
}

/// Why an input source refused a photo.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InputError {
    /// One human-readable line.
    reason: String,
}

impl InputError {
    /// Builds an input refusal from a reason.
    #[must_use]
    pub fn new(reason: impl Into<String>) -> Self {
        Self {
            reason: reason.into(),
        }
    }

    /// The refusal reason.
    #[must_use]
    pub fn reason(&self) -> &str {
        &self.reason
    }
}

impl std::fmt::Display for InputError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "input source: {}", self.reason)
    }
}

impl std::error::Error for InputError {}

/// Where renders get their pixels: photo id in, frame plus facts plus input
/// identity out. Runs on job threads only; implementations must be safe to
/// call from any pool thread.
pub trait InputSource: Send + Sync {
    /// Fetches one photo's input plane.
    ///
    /// # Errors
    ///
    /// [`InputError`] when the photo has no fetchable input.
    fn fetch(&self, photo: &str) -> Result<RenderInput, InputError>;
}

/// Any closure shaped like a fetch is one (tests and small embedders).
impl<F> InputSource for F
where
    F: Fn(&str) -> Result<RenderInput, InputError> + Send + Sync,
{
    fn fetch(&self, photo: &str) -> Result<RenderInput, InputError> {
        self(photo)
    }
}

/// Shared handle to an input source.
pub type SharedInputSource = Arc<dyn InputSource>;

/// Where renders find modules by id. Runs on job threads only; `lookup`
/// must be pure (the job may ask twice for one id: once to sort skips from
/// nodes, once inside the pipe's own chain build).
pub trait ModuleSource: Send + Sync {
    /// Returns the module registered as `id`, or [`None`].
    fn lookup(&self, id: &str) -> Option<SharedModule>;
}

/// Any closure shaped like a lookup is one.
impl<F> ModuleSource for F
where
    F: Fn(&str) -> Option<SharedModule> + Send + Sync,
{
    fn lookup(&self, id: &str) -> Option<SharedModule> {
        self(id)
    }
}

/// A plain id-keyed table is a lookup.
impl<S: std::hash::BuildHasher + Send + Sync> ModuleSource for HashMap<String, SharedModule, S> {
    fn lookup(&self, id: &str) -> Option<SharedModule> {
        self.get(id).cloned()
    }
}

/// Shared handle to a module source.
pub type SharedModuleSource = Arc<dyn ModuleSource>;

/// Adapts an injected module source (or none) to the pipe's lookup: `None`
/// finds nothing, so the chain is empty and the output equals the input.
struct ModuleSourceAdapter {
    source: Option<SharedModuleSource>,
}

impl ModuleLookup for ModuleSourceAdapter {
    fn lookup(&self, id: &str) -> Option<SharedModule> {
        self.source.as_ref().and_then(|source| source.lookup(id))
    }
}

/// One photo's latest finished pixels for one kind, detached from the pipe
/// budget (copied out at delivery, so holding it never pins a render).
#[derive(Debug, Clone)]
pub struct RenderedImage {
    /// The generation that produced these pixels.
    pub generation: u64,
    /// Pixel width.
    pub width: u32,
    /// Pixel height.
    pub height: u32,
    /// Row-major working-format floats (`width * height * 4`).
    pub pixels: Vec<f32>,
}

/// One instance that never reached the pipe.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkippedModule {
    /// Module id.
    pub id: String,
    /// Multi-instance index.
    pub multi: u32,
    /// Why it was skipped ([`SKIP_UNKNOWN_MODULE`] or [`SKIP_DISABLED`]).
    pub reason: &'static str,
}

/// What one render did: per-node hit or recompute plus the skips.
#[derive(Debug, Clone)]
pub struct RenderRecord {
    /// The generation this record describes.
    pub generation: u64,
    /// The job that ran it.
    pub job: JobId,
    /// Per-node reports in execution order (see
    /// [`Pipe::last_trace`][lightamer_pipeline::Pipe::last_trace]).
    pub nodes: Vec<NodeReport>,
    /// Instances skipped before the pipe, in chain order.
    pub skipped: Vec<SkippedModule>,
}

/// One in-flight render of one (photo, kind) pair.
#[derive(Debug)]
pub(crate) struct InFlight {
    /// Its generation.
    pub(crate) generation: u64,
    /// Its job.
    pub(crate) job: JobId,
}

/// Everything the engine keeps per (photo, kind) pair.
#[derive(Debug, Default)]
pub(crate) struct RenderSlot {
    /// Latest requested generation (0 before the first request).
    pub(crate) generation: u64,
    /// The render still running, if any.
    pub(crate) in_flight: Option<InFlight>,
    /// Latest finished pixels, until a newer generation replaces them.
    pub(crate) latest: Option<RenderedImage>,
    /// Record of the latest generation's latest delivery, if any.
    pub(crate) last_record: Option<RenderRecord>,
}

/// One job's successful pixels plus its record.
#[derive(Debug)]
pub(crate) struct RenderPayload {
    pub(crate) image: RenderedImage,
    pub(crate) record: RenderRecord,
}

/// One job's typed failure.
#[derive(Debug)]
pub(crate) struct RenderFailure {
    pub(crate) reason: String,
    pub(crate) cancelled: bool,
    pub(crate) record: RenderRecord,
}

/// One job's outcome, travelling from its pool thread to [`Engine::collect`].
#[derive(Debug)]
pub(crate) struct RenderDelivery {
    pub(crate) photo: String,
    pub(crate) kind: RenderKind,
    pub(crate) generation: u64,
    pub(crate) outcome: Result<RenderPayload, RenderFailure>,
}

/// One render job's delivery channel, waiting for [`Engine::collect`].
pub(crate) struct PendingRender {
    pub(crate) job: JobId,
    pub(crate) photo: String,
    pub(crate) kind: RenderKind,
    pub(crate) generation: u64,
    pub(crate) rx: Receiver<RenderDelivery>,
}

/// The `render.*` specs, in command-id order.
pub(crate) static SPECS: &[CommandSpec] = &[
    CommandSpec {
        id: "render.request",
        summary: "Starts a render job for one photo and pipe kind, superseding the in-flight one.",
        params: &[
            ParamSpec {
                name: "photo",
                kind: ParamKind::Text,
                required: true,
                doc: "The photo id to render.",
            },
            ParamSpec {
                name: "kind",
                kind: ParamKind::Text,
                required: true,
                doc: "The pipe kind: full, export, preview, or thumbnail.",
            },
        ],
        needs_session: true,
        enabled: command::always,
        run: run_request,
    },
    CommandSpec {
        id: "render.cancel",
        summary: "Cancels the in-flight render for one photo and pipe kind, starting none.",
        params: &[
            ParamSpec {
                name: "photo",
                kind: ParamKind::Text,
                required: true,
                doc: "The photo id whose render stops.",
            },
            ParamSpec {
                name: "kind",
                kind: ParamKind::Text,
                required: true,
                doc: "The pipe kind: full, export, preview, or thumbnail.",
            },
        ],
        needs_session: true,
        enabled: command::always,
        run: run_cancel,
    },
];

/// Reads one required `photo`/`kind` pair shared by both commands.
fn photo_kind_req(
    cmd: &str,
    params: &Map<String, Value>,
) -> Result<(String, RenderKind), CommandError> {
    let photo = text_req(cmd, params, "photo")?;
    let kind_text = text_req(cmd, params, "kind")?;
    let Some(kind) = RenderKind::parse(&kind_text) else {
        return Err(CommandError::BadParam {
            cmd: cmd.to_owned(),
            key: "kind".to_owned(),
            reason: format!(
                "unknown pipe kind '{kind_text}': want full, export, preview, or thumbnail"
            ),
        });
    };
    Ok((photo, kind))
}

/// Sets one job's cancel flag when its row is still around.
fn cancel_job_flag(engine: &Engine, job: JobId) {
    if let Some(flag) = engine.job_cancel_flag(job) {
        flag.store(true, std::sync::atomic::Ordering::SeqCst);
    }
}

fn run_request(
    engine: &mut Engine,
    params: &Map<String, Value>,
    _ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "render.request";
    let (photo, kind) = photo_kind_req(CMD, params)?;
    // The request-time snapshot: the job renders exactly these settings,
    // even if the user edits the photo while it runs. Real sessions read
    // through the library's own read path; renders never write it.
    let Some(settings) = engine.photo_settings(&photo) else {
        return Err(CommandError::NoPhoto {
            cmd: CMD.to_owned(),
            photo,
        });
    };
    let Some(input) = engine.input_source() else {
        return Err(CommandError::NoInputSource {
            cmd: CMD.to_owned(),
        });
    };
    let modules = engine.module_source();
    if let Some(job) = engine
        .render_slot(&photo, kind)
        .and_then(|slot| slot.in_flight.as_ref().map(|in_flight| in_flight.job))
    {
        cancel_job_flag(engine, job);
    }
    let pipe = engine.render_pipe(kind);
    let generation = engine.render_slot_mut(&photo, kind).generation + 1;
    engine.render_slot_mut(&photo, kind).generation = generation;
    let label = format!("render {photo} {} generation {generation}", kind.name());
    let (tx, rx) = delivery_channel();
    let worker_photo = photo.clone();
    let job = engine.spawn_job("render", label, 0, move |ctx| {
        run_render_job(
            ctx,
            &tx,
            &worker_photo,
            kind,
            generation,
            &settings,
            &input,
            modules.as_ref(),
            &pipe,
        );
    });
    engine.track_render(job, photo.clone(), kind, generation, rx);
    let slot = engine.render_slot_mut(&photo, kind);
    slot.in_flight = Some(InFlight { generation, job });
    Ok(json!({"generation": generation, "job": job}))
}

fn run_cancel(
    engine: &mut Engine,
    params: &Map<String, Value>,
    _ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "render.cancel";
    let (photo, kind) = photo_kind_req(CMD, params)?;
    if engine.photo_settings(&photo).is_none() {
        return Err(CommandError::NoPhoto {
            cmd: CMD.to_owned(),
            photo,
        });
    }
    let taken = engine.render_slot_mut(&photo, kind).in_flight.take();
    let Some(in_flight) = taken else {
        // Idempotent: a cancel that finds nothing running succeeds and
        // reports it, so a cancel racing completion never errors.
        return Ok(json!({"cancelled": false}));
    };
    // Stops unfinished work only: a delivery that already finished but was
    // never collected still lands on the next `collect` (its generation is
    // current and its outcome is not a cancel).
    cancel_job_flag(engine, in_flight.job);
    Ok(json!({
        "cancelled": true,
        "generation": in_flight.generation,
        "job": in_flight.job,
    }))
}

/// Orders instances into execution order: registry-known ids by the
/// non-raw default chain, unknown ids after them sorted by
/// (module, multi). B1 has no raw-ness signal (no decode yet), so every
/// photo takes the non-raw chain; B2 routes raw photos to the raw chain.
pub(crate) fn execution_order<'a>(
    instances: impl Iterator<Item = &'a ModuleInstance>,
) -> Vec<&'a ModuleInstance> {
    let chain = lightamer_registry::jpg_chain();
    let position = |id: &str| chain.iter().position(|desc| desc.id == id);
    let mut known: Vec<(usize, &ModuleInstance)> = Vec::new();
    let mut unknown: Vec<&ModuleInstance> = Vec::new();
    for instance in instances {
        match position(&instance.module) {
            Some(index) => known.push((index, instance)),
            None => unknown.push(instance),
        }
    }
    // Stable: same-module instances keep their (module, multi) list order.
    known.sort_by_key(|(index, _)| *index);
    unknown.sort_by(|a, b| (&a.module, a.multi).cmp(&(&b.module, b.multi)));
    known
        .into_iter()
        .map(|(_, instance)| instance)
        .chain(unknown)
        .collect()
}

/// One setting value as the pipe's JSON cell: mirrors the serde derive on
/// [`SettingValue`] (`tag = "type"`, `content = "value"`, snake case) as a
/// total function, so chain building has no serialization failure mode.
pub(crate) fn setting_cell(value: &SettingValue) -> Value {
    match value {
        SettingValue::Bool(on) => json!({"type": "bool", "value": on}),
        SettingValue::Int(n) => json!({"type": "int", "value": n}),
        SettingValue::Float(x) => json!({"type": "float", "value": x}),
        SettingValue::Enum(variant) => json!({"type": "enum", "value": variant}),
        SettingValue::Text(text) => json!({"type": "text", "value": text}),
        SettingValue::Floats(list) => json!({"type": "floats", "value": list}),
    }
}

/// One instance's parameters as the pipe's JSON object.
pub(crate) fn params_object(instance: &ModuleInstance) -> Map<String, Value> {
    let mut map = Map::with_capacity(instance.params.len());
    for (name, value) in &instance.params {
        map.insert(name.clone(), setting_cell(value));
    }
    map
}

/// The wanted output region for an input extent: the whole frame at scale
/// 1.0. Only absurd extents (past `i32`) refuse, as a typed failure.
pub(crate) fn final_roi_for(extent: FrameExtent) -> Result<lightamer_geom::Roi, String> {
    let width = i32::try_from(extent.width).map_err(|_| {
        format!(
            "input width {} does not fit the pipe's regions",
            extent.width
        )
    })?;
    let height = i32::try_from(extent.height).map_err(|_| {
        format!(
            "input height {} does not fit the pipe's regions",
            extent.height
        )
    })?;
    // Widths and heights arrive as `u32` (never negative) and the scale is a
    // constant 1.0, so this arm never fires (`Roi::new` only refuses
    // negative sizes and bad scales); it stays as a typed guard.
    lightamer_geom::Roi::new(extent.x, extent.y, width, height, 1.0)
        .map_err(|err| format!("input extent is not a region: {err}"))
}

/// Sorts the snapshot's instances into pipe nodes plus skips: disabled
/// instances and ids the module source does not know never reach the pipe.
fn sort_chain(
    settings: &lightamer_history::PhotoSettings,
    modules: Option<&SharedModuleSource>,
) -> (Vec<lightamer_pipeline::PipeNode>, Vec<SkippedModule>) {
    let mut skipped = Vec::new();
    let mut nodes = Vec::new();
    for instance in execution_order(settings.instances.iter()) {
        if !instance.enabled {
            skipped.push(SkippedModule {
                id: instance.module.clone(),
                multi: instance.multi,
                reason: SKIP_DISABLED,
            });
            continue;
        }
        let found = modules.and_then(|source| source.lookup(&instance.module));
        if found.is_none() {
            skipped.push(SkippedModule {
                id: instance.module.clone(),
                multi: instance.multi,
                reason: SKIP_UNKNOWN_MODULE,
            });
            continue;
        }
        nodes.push(lightamer_pipeline::PipeNode {
            id: instance.module.clone(),
            multi: instance.multi,
            params: params_object(instance),
        });
    }
    (nodes, skipped)
}

/// One cancelled delivery: no pixels, no node reports.
fn cancelled_delivery(
    photo: &str,
    kind: RenderKind,
    generation: u64,
    job: JobId,
    skipped: Vec<SkippedModule>,
) -> RenderDelivery {
    RenderDelivery {
        photo: photo.to_owned(),
        kind,
        generation,
        outcome: Err(RenderFailure {
            reason: "superseded".to_owned(),
            cancelled: true,
            record: RenderRecord {
                generation,
                job,
                nodes: Vec::new(),
                skipped,
            },
        }),
    }
}

/// One failed delivery with the pipe's partial trace, if any.
#[allow(clippy::too_many_arguments)]
fn failed_delivery(
    photo: &str,
    kind: RenderKind,
    generation: u64,
    job: JobId,
    reason: String,
    nodes: Vec<NodeReport>,
    skipped: Vec<SkippedModule>,
) -> RenderDelivery {
    RenderDelivery {
        photo: photo.to_owned(),
        kind,
        generation,
        outcome: Err(RenderFailure {
            reason,
            cancelled: false,
            record: RenderRecord {
                generation,
                job,
                nodes,
                skipped,
            },
        }),
    }
}

/// Runs one render on a pool thread and sends its delivery. Never touches
/// the engine: the outcome travels through `tx` to [`Engine::collect`].
///
/// Order: sort skips from nodes (needs only the snapshot) → refuse early
/// when already superseded → fetch the input (outside the kind lock, since
/// a future decode may be slow) → hold the kind lock for one pipe run →
/// copy the pixels out and send them. The pipe lock releases before the
/// send; the channel is unbounded, so the send never blocks the lock.
#[allow(clippy::too_many_arguments)]
pub(crate) fn run_render_job(
    ctx: &JobCtx,
    tx: &Sender<RenderDelivery>,
    photo: &str,
    kind: RenderKind,
    generation: u64,
    settings: &lightamer_history::PhotoSettings,
    input: &SharedInputSource,
    modules: Option<&SharedModuleSource>,
    pipe: &std::sync::Mutex<Pipe>,
) {
    let job = ctx.id();
    let (nodes, skipped) = sort_chain(settings, modules);
    if ctx.is_cancelled() {
        let _ = tx.send(cancelled_delivery(photo, kind, generation, job, skipped));
        return;
    }
    let fetched = match input.fetch(photo) {
        Ok(fetched) => fetched,
        Err(err) => {
            let _ = tx.send(failed_delivery(
                photo,
                kind,
                generation,
                job,
                err.to_string(),
                Vec::new(),
                skipped,
            ));
            return;
        }
    };
    let final_out = match final_roi_for(fetched.frame.extent()) {
        Ok(final_out) => final_out,
        Err(reason) => {
            let _ = tx.send(failed_delivery(
                photo,
                kind,
                generation,
                job,
                reason,
                Vec::new(),
                skipped,
            ));
            return;
        }
    };
    let mut guard = pipe
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if ctx.is_cancelled() {
        let _ = tx.send(cancelled_delivery(photo, kind, generation, job, skipped));
        return;
    }
    let adapter = ModuleSourceAdapter {
        source: modules.cloned(),
    };
    let cancel_probe = || ctx.is_cancelled();
    let request = lightamer_pipeline::RenderRequest {
        nodes: &nodes,
        lookup: &adapter,
        image: &fetched.image,
        input: &fetched.frame,
        input_id: fetched.input_id,
        process: settings.process.0,
        final_out,
        cancel: &cancel_probe,
    };
    match guard.render(&request) {
        Ok(out) => {
            let record = RenderRecord {
                generation,
                job,
                nodes: guard.last_trace().to_vec(),
                skipped,
            };
            let frame = out.frame();
            let extent = frame.extent();
            let image = RenderedImage {
                generation,
                width: extent.width,
                height: extent.height,
                pixels: frame.as_slice().to_vec(),
            };
            drop(guard);
            let _ = tx.send(RenderDelivery {
                photo: photo.to_owned(),
                kind,
                generation,
                outcome: Ok(RenderPayload { image, record }),
            });
        }
        Err(lightamer_pipeline::RenderError::Cancelled) => {
            drop(guard);
            let _ = tx.send(cancelled_delivery(photo, kind, generation, job, skipped));
        }
        Err(err) => {
            let nodes = guard.last_trace().to_vec();
            drop(guard);
            let _ = tx.send(failed_delivery(
                photo,
                kind,
                generation,
                job,
                err.to_string(),
                nodes,
                skipped,
            ));
        }
    }
}

/// Applies one delivery to the render slots: only the latest generation
/// lands — its pixels are kept, its record filed, and its event emitted.
/// Anything older is dropped whole (no pixels, no record, no event), and a
/// cancelled delivery of any generation emits nothing (the job events
/// already told that story).
pub(crate) fn apply_delivery(
    slots: &mut BTreeMap<(String, RenderKind), RenderSlot>,
    delivery: RenderDelivery,
) -> Option<Event> {
    let slot = slots.get_mut(&(delivery.photo.clone(), delivery.kind))?;
    if delivery.generation != slot.generation {
        return None;
    }
    slot.in_flight = None;
    match delivery.outcome {
        Ok(payload) => {
            slot.latest = Some(payload.image);
            slot.last_record = Some(payload.record);
            Some(Event::RenderReady {
                photo: delivery.photo,
                kind: delivery.kind.name().to_owned(),
                generation: delivery.generation,
            })
        }
        Err(failure) => {
            if failure.cancelled {
                return None;
            }
            slot.last_record = Some(failure.record);
            Some(Event::RenderFailed {
                photo: delivery.photo,
                kind: delivery.kind.name().to_owned(),
                generation: delivery.generation,
                reason: failure.reason,
            })
        }
    }
}

/// Applies a terminal job that sent no delivery (a superseded job the
/// worker skipped before it started): clears the in-flight marker when it
/// names this job, and turns a worker-side failure of the latest
/// generation into its failed event.
pub(crate) fn apply_terminal_without_delivery(
    slots: &mut BTreeMap<(String, RenderKind), RenderSlot>,
    photo: &str,
    kind: RenderKind,
    generation: u64,
    job: JobId,
    status: &JobStatus,
) -> Option<Event> {
    let slot = slots.get_mut(&(photo.to_owned(), kind))?;
    if slot
        .in_flight
        .as_ref()
        .is_some_and(|in_flight| in_flight.job == job)
    {
        slot.in_flight = None;
    }
    if generation != slot.generation {
        return None;
    }
    match status {
        JobStatus::Failed(reason) => Some(Event::RenderFailed {
            photo: photo.to_owned(),
            kind: kind.name().to_owned(),
            generation,
            reason: reason.clone(),
        }),
        JobStatus::Queued | JobStatus::Running | JobStatus::Finished { .. } => None,
    }
}

/// Builds one tracked delivery channel: the sender travels into the job's
/// work closure, the receiver waits on the engine's pending list until
/// [`Engine::collect`][crate::Engine::collect] drains it.
pub(crate) fn delivery_channel() -> (Sender<RenderDelivery>, Receiver<RenderDelivery>) {
    std::sync::mpsc::channel()
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use std::collections::BTreeMap;

    use lightamer_history::{ModuleInstance, PhotoSettings};
    use lightamer_raster::FrameExtent;

    use super::{
        SKIP_DISABLED, SKIP_UNKNOWN_MODULE, execution_order, final_roi_for, params_object,
        setting_cell,
    };
    use crate::render::RenderKind;

    #[test]
    fn kind_words_round_trip() {
        for kind in RenderKind::ALL {
            assert_eq!(RenderKind::parse(kind.name()), Some(kind));
        }
        assert_eq!(RenderKind::parse("full"), Some(RenderKind::Full));
        assert_eq!(RenderKind::parse("Full"), None);
        assert_eq!(RenderKind::parse(""), None);
        assert_eq!(RenderKind::parse("fitted"), None);
    }

    #[test]
    fn setting_cells_mirror_the_serde_shape() {
        use lightamer_history::SettingValue;
        let cases = [
            SettingValue::Bool(true),
            SettingValue::Int(-3),
            SettingValue::Float(1.5),
            SettingValue::Enum("clip".to_owned()),
            SettingValue::Text("free".to_owned()),
            SettingValue::Floats(vec![0.0, 2.5]),
        ];
        for value in &cases {
            let wire = serde_json::to_value(value).unwrap();
            assert_eq!(setting_cell(value), wire);
        }
    }

    #[test]
    fn params_object_carries_every_entry() {
        let mut instance = ModuleInstance {
            module: "mod_a".to_owned(),
            multi: 0,
            name: None,
            enabled: true,
            params: BTreeMap::new(),
        };
        instance.params.insert(
            "gain".to_owned(),
            lightamer_history::SettingValue::Float(2.0),
        );
        let map = params_object(&instance);
        assert_eq!(map.len(), 1);
        assert_eq!(
            map.get("gain"),
            Some(&serde_json::json!({"type": "float", "value": 2.0}))
        );
    }

    fn instance(module: &str, multi: u32, enabled: bool) -> ModuleInstance {
        ModuleInstance {
            module: module.to_owned(),
            multi,
            name: None,
            enabled,
            params: BTreeMap::new(),
        }
    }

    #[test]
    fn execution_order_sorts_unknown_ids_after_known_by_module_then_multi() {
        let mut settings = PhotoSettings::default();
        // Unknown to the registry: order is (module, multi), insertion
        // order unobservable (the list keeps its own sort).
        settings.instances.upsert(instance("mod_b", 1, true));
        settings.instances.upsert(instance("mod_b", 0, true));
        settings.instances.upsert(instance("mod_a", 0, true));
        let order = execution_order(settings.instances.iter());
        let ids: Vec<(&str, u32)> = order
            .iter()
            .map(|found| (found.module.as_str(), found.multi))
            .collect();
        assert_eq!(ids, vec![("mod_a", 0), ("mod_b", 0), ("mod_b", 1)]);
        assert_eq!(SKIP_UNKNOWN_MODULE, "unknown-module");
        assert_eq!(SKIP_DISABLED, "disabled");
    }

    #[test]
    fn final_roi_covers_the_whole_frame_and_refuses_absurd_widths() {
        let roi = final_roi_for(FrameExtent::new(4, 6, 8, 10)).unwrap();
        assert_eq!((roi.x, roi.y, roi.width, roi.height), (4, 6, 8, 10));
        assert_eq!(roi.scale.to_bits(), 1.0f32.to_bits());
        let err = final_roi_for(FrameExtent::new(0, 0, u32::MAX, 8)).unwrap_err();
        assert!(err.contains("width"), "{err}");
        let err = final_roi_for(FrameExtent::new(0, 0, 8, u32::MAX)).unwrap_err();
        assert!(err.contains("height"), "{err}");
    }
}
