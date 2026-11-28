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
//! keep their pixels under a byte cap (least-recently-used evicted;
//! thumbnails never kept) until a newer generation replaces them or the
//! session closes.

use std::collections::{BTreeMap, HashMap, VecDeque};
use std::path::PathBuf;
use std::sync::mpsc::{Receiver, Sender};
use std::sync::{Arc, MutexGuard};

use lightamer_history::{ModuleInstance, SettingValue};
use lightamer_iop_traits::{ImageInfo, SharedModule};
use lightamer_pipeline::{
    MappedFrame, ModuleLookup, NodeReport, Pipe, RenderError, StreamSink, StreamedOutput,
};
use lightamer_raster::{Frame, FrameExtent, PixelFormat};
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

    /// Whether over-limit frames of this kind switch to streaming on their
    /// own: full and export only. Preview and thumbnail keep refusing, so a
    /// frame that never fit their small quotas fails loudly at the caller's
    /// door instead of quietly streaming.
    pub(crate) const fn auto_streams(self) -> bool {
        matches!(self, RenderKind::Full | RenderKind::Export)
    }
}

/// Default cap for streaming spill output: 8 GiB (A-24).
pub const DEFAULT_SPILL_BYTE_LIMIT: u64 = 8 * 1024 * 1024 * 1024;
/// Default cap for retained render results: 1 GiB (about one 61 MP output).
pub const DEFAULT_KEPT_BYTE_LIMIT: u64 = 1024 * 1024 * 1024;
/// Streaming outputs at or below this assemble in RAM (Lumen `MAP_BYTES`).
pub const DEFAULT_SPILL_MEMORY_THRESHOLD: u64 = 256 * 1024 * 1024;

/// Render-side engine configuration: streaming spill limits and the
/// retention cap. The settings panel owns the UI later (A-24); until then
/// the embedder sets this directly.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EngineConfig {
    /// Streaming outputs past this refuse typed before running anything.
    pub spill_byte_limit: u64,
    /// Where spill files land (`None` = the system temp directory). The
    /// engine only passes this down; the pipeline makes and deletes files.
    pub spill_dir: Option<PathBuf>,
    /// Retained render results past this evict least-recently-used first.
    pub kept_bytes_limit: u64,
    /// Streaming outputs at or below this assemble in RAM; bigger ones
    /// spill to a memory-mapped temp file.
    pub spill_memory_threshold: u64,
}

impl Default for EngineConfig {
    fn default() -> Self {
        Self {
            spill_byte_limit: DEFAULT_SPILL_BYTE_LIMIT,
            spill_dir: None,
            kept_bytes_limit: DEFAULT_KEPT_BYTE_LIMIT,
            spill_memory_threshold: DEFAULT_SPILL_MEMORY_THRESHOLD,
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
/// What a render knows about its input before fetching a pixel: decoded
/// image facts plus the full-frame extent. The job probes this first and
/// routes over-limit frames to streaming without ever holding a whole frame.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RenderFacts {
    /// Decoded-image facts for `commit`.
    pub image: ImageInfo,
    /// The full input extent, in absolute frame coordinates.
    pub extent: FrameExtent,
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
/// identity out; [`InputSource::probe`] answers the facts alone, without
/// pixels. Runs on job threads only; implementations must be safe to call
/// from any pool thread.
pub trait InputSource: Send + Sync {
    /// Fetches one photo's input plane.
    ///
    /// # Errors
    ///
    /// [`InputError`] when the photo has no fetchable input.
    fn fetch(&self, photo: &str) -> Result<RenderInput, InputError>;
    /// Probes one photo's input facts without fetching any pixels.
    ///
    /// The render job calls this before anything else on streaming
    /// candidates (full/export kinds with a non-empty chain) and routes
    /// over-limit frames to streaming on the probed size alone; preview,
    /// thumbnail, and empty-chain jobs never probe.
    ///
    /// Sources must report the true frame size: the direct-stream path
    /// trusts the probed extent for planning and output without ever
    /// comparing it against real pixels. A probe larger than the truth
    /// overruns the default region reader into a typed refusal; a probe
    /// smaller than the truth plans small and delivers a frame the size
    /// of the probe, silently dropping the rest.
    ///
    /// The default fetches the whole frame and keeps its facts (exactly what
    /// B1d-b always fetched first); sources serving frames that never fit
    /// RAM override it with a cheap answer, or the whole-frame path pays
    /// for two decodes (one inside the probe, one for the pixels).
    ///
    /// # Errors
    ///
    /// [`InputError`] when the photo has no fetchable input.
    fn probe(&self, photo: &str) -> Result<RenderFacts, InputError> {
        let whole = self.fetch(photo)?;
        Ok(RenderFacts {
            image: whole.image,
            extent: whole.frame.extent(),
        })
    }

    /// Fetches one photo's input restricted to `region` (absolute frame
    /// coordinates). The streaming fallback calls this once per planned
    /// input region instead of holding the whole frame.
    ///
    /// The default fetches the whole frame and crops (bitwise what B1-c
    /// always fed the pipe); sources serving frames that never fit RAM
    /// override it with a region reader.
    ///
    /// # Errors
    ///
    /// [`InputError`] when the photo has no fetchable input or the region
    /// leaves the frame.
    fn fetch_region(&self, photo: &str, region: FrameExtent) -> Result<RenderInput, InputError> {
        let whole = self.fetch(photo)?;
        crop_region(&whole.frame, region).map(|frame| RenderInput {
            frame,
            image: whole.image,
            input_id: whole.input_id,
        })
    }
}

/// Crops `region` (absolute frame coordinates) out of a whole input frame.
fn crop_region(whole: &Frame, region: FrameExtent) -> Result<Frame, InputError> {
    let view = whole
        .view(region)
        .map_err(|err| InputError::new(err.to_string()))?;
    let mut frame = Frame::alloc(region, PixelFormat::RgbaF32Premul)
        .map_err(|err| InputError::new(err.to_string()))?;
    for row in 0..region.height {
        let src = view
            .row(row)
            .map_err(|err| InputError::new(err.to_string()))?;
        let dst = frame
            .row_mut(row)
            .map_err(|err| InputError::new(err.to_string()))?;
        if src.len() != dst.len() {
            return Err(InputError::new(format!(
                "input region {region:?} rows disagree: {} vs {} floats",
                src.len(),
                dst.len()
            )));
        }
        dst.copy_from_slice(src);
    }
    Ok(frame)
}
/// [`StreamInput`][lightamer_pipeline::StreamInput] over an engine input
/// source: each planned piece input becomes one `fetch_region` call. Region
/// refusals surface as frame errors carrying the source's own reason.
struct RegionStreamInput<'a> {
    /// Where regions come from.
    input: &'a SharedInputSource,
    /// The photo id.
    photo: &'a str,
}

impl lightamer_pipeline::StreamInput for RegionStreamInput<'_> {
    fn fetch_region(&self, region: FrameExtent) -> Result<Frame, lightamer_pipeline::RenderError> {
        self.input
            .fetch_region(self.photo, region)
            .map(|got| got.frame)
            .map_err(|err| lightamer_pipeline::RenderError::Frame {
                detail: err.to_string(),
            })
    }
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
/// budget (copied or mapped out at delivery, so holding it never pins a
/// render). Cloning shares a mapped file and copies RAM pixels.
#[derive(Debug, Clone)]
pub struct RenderedImage {
    /// The generation that produced these pixels.
    pub generation: u64,
    /// Pixel width.
    pub width: u32,
    /// Pixel height.
    pub height: u32,
    /// Where the pixels live.
    pub store: RenderedStore,
}

/// Where a [`RenderedImage`]'s pixels live.
#[derive(Debug, Clone)]
pub enum RenderedStore {
    /// Row-major working-format floats (`width * height * 4`).
    Memory(Vec<f32>),
    /// A memory-mapped spill file, shared: evicting the retention drops
    /// only its own handle, so a caller still holding the image keeps
    /// reading it and the file dies with the last holder.
    Mapped(Arc<MappedFrame>),
}

impl RenderedImage {
    /// Working-format bytes this image counts in retention (`width *
    /// height * 16`, saturating on absurd extents).
    #[must_use]
    pub fn byte_len(&self) -> u64 {
        u64::from(self.width)
            .saturating_mul(u64::from(self.height))
            .saturating_mul(16)
    }

    /// Whether these pixels live in a mapped spill file.
    #[must_use]
    pub fn is_mapped(&self) -> bool {
        matches!(self.store, RenderedStore::Mapped(_))
    }

    /// The pixels as working-format floats, row-major. Mapped pixels decode
    /// from the file's native-endian bytes; RAM pixels clone.
    #[must_use]
    pub fn to_vec(&self) -> Vec<f32> {
        match &self.store {
            RenderedStore::Memory(pixels) => pixels.clone(),
            RenderedStore::Mapped(mapped) => {
                let bytes = mapped.as_bytes();
                let (words, _) = bytes.as_chunks::<4>();
                let mut out = Vec::with_capacity(words.len());
                for word in words {
                    out.push(f32::from_ne_bytes(*word));
                }
                out
            }
        }
    }
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
    /// How the run streamed (`None` = a whole-frame render).
    pub streamed: Option<StreamReport>,
}

/// How one streaming render ran, for demos and the resource table.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StreamReport {
    /// Strip or block mode.
    pub mode: StreamMode,
    /// Planned pieces the run executed.
    pub pieces: u64,
}

/// Which streaming shape a run used: engine words for
/// [`StreamMode`][lightamer_pipeline::StreamMode].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StreamMode {
    /// Full-width strips (a point-only chain).
    Strip,
    /// Margin blocks (some module reaches past its pixel).
    Block,
}

impl StreamMode {
    /// The mode word demos print.
    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            StreamMode::Strip => "strip",
            StreamMode::Block => "block",
        }
    }
}

impl From<lightamer_pipeline::StreamMode> for StreamMode {
    fn from(mode: lightamer_pipeline::StreamMode) -> Self {
        match mode {
            lightamer_pipeline::StreamMode::Strip => StreamMode::Strip,
            lightamer_pipeline::StreamMode::Block => StreamMode::Block,
        }
    }
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

/// Retention ledger: which (photo, kind) pairs hold pixels, oldest first,
/// and their total bytes. Mirrors the slots: a key sits here exactly when
/// its slot's `latest` is `Some` (thumbnails never land, so never sit here).
#[derive(Debug, Default)]
pub(crate) struct KeptImages {
    /// Keys holding pixels, oldest first.
    order: VecDeque<(String, RenderKind)>,
    /// Their total [`RenderedImage::byte_len`].
    bytes: u64,
}

impl KeptImages {
    /// Marks `key` newest (a land or a read).
    pub(crate) fn touch(&mut self, key: &(String, RenderKind)) {
        if let Some(pos) = self.order.iter().position(|held| held == key) {
            self.order.remove(pos);
        }
        self.order.push_back(key.clone());
    }
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
    let config = engine.render_config();
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
            &config,
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
                streamed: None,
            },
        }),
    }
}

/// One failed delivery with the pipe's partial trace, if any.
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
                streamed: None,
            },
        }),
    }
}

/// Runs one render on a pool thread and sends its delivery. Never touches
/// the engine: the outcome travels through `tx` to [`Engine::collect`].
///
/// Order: sort skips from nodes (needs only the snapshot) → refuse early
/// when already superseded → probe the input size on streaming candidates
/// only (no pixels) → hold the
/// kind lock and compare against the pipe's own largest frame: full and
/// export kinds over it stream directly (regions arrive per planned piece;
/// the whole input is never fetched) → otherwise drop the lock, fetch the
/// input whole (outside the kind lock, since a future decode may be slow),
/// and hold the lock for one pipe run → copy the pixels out and send them.
/// The pipe lock releases before the send; the channel is unbounded, so the
/// send never blocks the lock. A whole attempt that still refuses as too
/// large (a chain whose nodes disagree in size) drops its input and streams
/// too; every other error, and every preview/thumbnail refusal, fails typed
/// as before.
#[expect(clippy::too_many_arguments)] // one job launch with its context, input, and pipe; a params struct would just rename the args
#[expect(clippy::too_many_lines)] // a linear job script (sort, fetch, whole attempt, stream handoff); splitting would scatter the delivery sends
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
    config: &EngineConfig,
) {
    let job = ctx.id();
    let (nodes, skipped) = sort_chain(settings, modules);
    if ctx.is_cancelled() {
        let _ = tx.send(cancelled_delivery(photo, kind, generation, job, skipped));
        return;
    }
    // Facts before pixels, and only when streaming is possible: preview,
    // thumbnail, and empty chains can never route to streaming, so probing
    // them would only burn a whole fetch (the default probe) for nothing.
    let facts = if kind.auto_streams() && !nodes.is_empty() {
        match input.probe(photo) {
            Ok(facts) => Some(facts),
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
        }
    } else {
        None
    };
    let guard = pipe
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if ctx.is_cancelled() {
        let _ = tx.send(cancelled_delivery(photo, kind, generation, job, skipped));
        return;
    }
    // A streaming kind whose probed frame tops the pipe's own largest frame
    // streams directly; the whole input is never fetched on this path.
    // (Facts exist exactly when this job could stream: full/export kinds
    // with a non-empty chain.)
    if let Some(facts) = facts
        && u64::from(facts.extent.width)
            .saturating_mul(u64::from(facts.extent.height))
            .saturating_mul(16)
            > guard.max_frame_bytes()
    {
        let final_out = match final_roi_for(facts.extent) {
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
        run_stream_fallback(StreamFallback {
            ctx,
            tx,
            photo,
            kind,
            generation,
            input,
            modules,
            guard,
            nodes,
            skipped,
            image: facts.image,
            final_out,
            config,
        });
        return;
    }
    drop(guard);
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
                streamed: None,
            };
            let frame = out.frame();
            let extent = frame.extent();
            let image = RenderedImage {
                generation,
                width: extent.width,
                height: extent.height,
                store: RenderedStore::Memory(frame.as_slice().to_vec()),
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
        Err(RenderError::FrameTooLarge { .. }) if kind.auto_streams() => {
            // The whole input drops here, before the per-region loop, so an
            // over-limit frame never sits in RAM twice (fetched whole plus
            // streamed regions).
            // Copied out first so `request` dies here and its borrows of the
            // fetched input and the node list end before the moves below.
            let final_out = request.final_out;
            let RenderInput { frame, image, .. } = fetched;
            drop(frame);
            run_stream_fallback(StreamFallback {
                ctx,
                tx,
                photo,
                kind,
                generation,
                input,
                modules,
                guard,
                nodes,
                skipped,
                image,
                final_out,
                config,
            });
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

/// Everything the streaming fallback needs: the job's context and delivery
/// path, the kind lock it already holds, and the input facts. No whole
/// frame travels with it: the direct path never fetches one, and the
/// over-limit backstop drops its whole attempt first.
struct StreamFallback<'a> {
    /// The running job (id plus its cancel flag).
    ctx: &'a JobCtx,
    /// Where the delivery goes.
    tx: &'a Sender<RenderDelivery>,
    /// The photo id.
    photo: &'a str,
    /// Full or export (the only kinds that reach the fallback).
    kind: RenderKind,
    /// This run's generation.
    generation: u64,
    /// Where regions come from.
    input: &'a SharedInputSource,
    /// Where modules resolve from, if any.
    modules: Option<&'a SharedModuleSource>,
    /// The held kind lock.
    guard: MutexGuard<'a, Pipe>,
    /// Sorted pipe nodes.
    nodes: Vec<lightamer_pipeline::PipeNode>,
    /// Instances skipped before the pipe.
    skipped: Vec<SkippedModule>,
    /// Decoded-image facts for `commit`.
    image: ImageInfo,
    /// Wanted final output region.
    final_out: lightamer_geom::Roi,
    /// Spill limits for this run.
    config: &'a EngineConfig,
}

/// One planned region as a fetchable extent.
fn extent_for_roi(roi: &lightamer_geom::Roi, what: &str) -> Result<FrameExtent, String> {
    let width = u32::try_from(roi.width)
        .map_err(|_| format!("streaming {what} width {} is not an extent", roi.width))?;
    let height = u32::try_from(roi.height)
        .map_err(|_| format!("streaming {what} height {} is not an extent", roi.height))?;
    Ok(FrameExtent::new(roi.x, roi.y, width, height))
}

/// Runs one render piece by piece through the pipe's region-source entry.
/// Never touches the engine: the outcome travels through `tx` like the
/// whole-frame path, and the kind lock releases before the send.
///
/// Order: assemble the output ([`StreamSink`][lightamer_pipeline::StreamSink],
/// RAM or a memory-mapped spill file) → one [`Pipe::render_stream_from`][lightamer_pipeline::Pipe::render_stream_from]
/// call over a region adapter (the pipe plans once and pulls each grown
/// input through [`InputSource::fetch_region`]) → finish the sink. Planning
/// lives in the pipe alone; the engine only connects the source and the
/// sink. A superseded run yields between pieces (the pipe probes the same
/// flag before every piece); cancel or any error drops the sink, so the
/// spill file (when mapped) dies with it. Refusals pass through typed: a
/// module the plan refuses, a spill limit, or a region the source will not
/// serve all fail the delivery with the pipeline's or source's own reason —
/// never a quiet fallback.
#[expect(clippy::too_many_lines)] // a linear job script (sink, one streaming call, delivery); splitting would scatter the delivery sends
fn run_stream_fallback(job: StreamFallback<'_>) {
    let StreamFallback {
        ctx,
        tx,
        photo,
        kind,
        generation,
        input,
        modules,
        mut guard,
        nodes,
        skipped,
        image,
        final_out,
        config,
    } = job;
    let job_id = ctx.id();
    let adapter = ModuleSourceAdapter {
        source: modules.cloned(),
    };
    let full = match extent_for_roi(&final_out, "output") {
        Ok(full) => full,
        Err(reason) => {
            let _ = tx.send(failed_delivery(
                photo,
                kind,
                generation,
                job_id,
                reason,
                Vec::new(),
                skipped,
            ));
            return;
        }
    };
    let mut sink = match StreamSink::new(
        full,
        config.spill_memory_threshold,
        config.spill_byte_limit,
        config.spill_dir.as_deref(),
    ) {
        Ok(sink) => sink,
        Err(err) => {
            let _ = tx.send(failed_delivery(
                photo,
                kind,
                generation,
                job_id,
                err.to_string(),
                Vec::new(),
                skipped,
            ));
            return;
        }
    };
    let cancel_probe = || ctx.is_cancelled();
    let req = lightamer_pipeline::StreamRequest {
        nodes: &nodes,
        lookup: &adapter,
        image: &image,
        final_out,
        cancel: &cancel_probe,
    };
    let source = RegionStreamInput { input, photo };
    let summary = match guard.render_stream_from(&req, &source, |emitted| sink.push(&emitted)) {
        Ok(summary) => summary,
        Err(RenderError::Cancelled) => {
            drop(guard);
            let _ = tx.send(cancelled_delivery(photo, kind, generation, job_id, skipped));
            return;
        }
        Err(err) => {
            let _ = tx.send(failed_delivery(
                photo,
                kind,
                generation,
                job_id,
                err.to_string(),
                guard.last_trace().to_vec(),
                skipped,
            ));
            return;
        }
    };
    let output = match sink.finish() {
        Ok(output) => output,
        Err(err) => {
            let _ = tx.send(failed_delivery(
                photo,
                kind,
                generation,
                job_id,
                err.to_string(),
                guard.last_trace().to_vec(),
                skipped,
            ));
            return;
        }
    };
    let extent = output.extent();
    let image = RenderedImage {
        generation,
        width: extent.width,
        height: extent.height,
        store: match output {
            StreamedOutput::Memory(frame) => RenderedStore::Memory(frame.as_slice().to_vec()),
            StreamedOutput::Mapped(mapped) => RenderedStore::Mapped(Arc::new(mapped)),
        },
    };
    let record = RenderRecord {
        generation,
        job: job_id,
        nodes: guard.last_trace().to_vec(),
        skipped,
        streamed: Some(StreamReport {
            mode: StreamMode::from(summary.mode),
            pieces: u64::from(summary.pieces),
        }),
    };
    drop(guard);
    let _ = tx.send(RenderDelivery {
        photo: photo.to_owned(),
        kind,
        generation,
        outcome: Ok(RenderPayload { image, record }),
    });
}

/// Applies one delivery to the render slots: only the latest generation
/// lands — its pixels are kept, its record filed, and its event emitted.
/// Anything older is dropped whole (no pixels, no record, no event), and a
/// cancelled delivery of any generation emits nothing (the job events
/// already told that story).
///
/// Kept pixels sit under `kept_cap` bytes, least-recently-used evicted
/// first; a landed image bigger than the cap alone evicts everything else,
/// then itself (delivered, its event fired, but not kept). Thumbnail
/// pixels never land here at all (the thumbnail cache owns them later);
/// their records still file and their events still fire.
pub(crate) fn apply_delivery(
    slots: &mut BTreeMap<(String, RenderKind), RenderSlot>,
    kept: &mut KeptImages,
    kept_cap: u64,
    delivery: RenderDelivery,
) -> Option<Event> {
    let key = (delivery.photo.clone(), delivery.kind);
    {
        let slot = slots.get_mut(&key)?;
        if delivery.generation != slot.generation {
            return None;
        }
        slot.in_flight = None;
    }
    match delivery.outcome {
        Ok(payload) => {
            if delivery.kind != RenderKind::Thumbnail {
                let landed_len = payload.image.byte_len();
                if let Some(slot) = slots.get_mut(&key)
                    && let Some(old) = slot.latest.replace(payload.image)
                {
                    kept.bytes = kept.bytes.saturating_sub(old.byte_len());
                }
                kept.touch(&key);
                kept.bytes = kept.bytes.saturating_add(landed_len);
                while kept.bytes > kept_cap {
                    let Some(oldest) = kept.order.pop_front() else {
                        break;
                    };
                    let Some(victim) = slots.get_mut(&oldest) else {
                        continue;
                    };
                    if let Some(evicted) = victim.latest.take() {
                        kept.bytes = kept.bytes.saturating_sub(evicted.byte_len());
                    }
                }
            }
            if let Some(slot) = slots.get_mut(&key) {
                slot.last_record = Some(payload.record);
            }
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
            if let Some(slot) = slots.get_mut(&key) {
                slot.last_record = Some(failure.record);
            }
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
    use std::collections::{BTreeMap, HashMap};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::{Arc, Mutex};

    use lightamer_history::{ModuleInstance, PhotoSettings, SettingValue};
    use lightamer_iop_traits::{
        ColorSpace, CommitData, ImageInfo, IopModule, ModuleDesc, OrderKey, PipeError, Plane,
        PlaneMut, Roi, SharedModule, StatsNeeds, get_float,
    };
    use lightamer_pipeline::{Pipe, PipeKind, PipeNode};
    use lightamer_raster::{Frame, FrameExtent, PixelFormat};

    use super::{
        EngineConfig, InputError, InputSource, KeptImages, RenderKind, RenderRecord, RenderSlot,
        RenderedImage, RenderedStore, SKIP_DISABLED, SKIP_UNKNOWN_MODULE, StreamMode,
        apply_delivery, execution_order, final_roi_for, params_object, run_render_job,
        setting_cell,
    };
    use crate::jobs::JobCtx;

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
    /// Synthetic pixels: r = x, g = y, b = 0.5, a = 1.0, absolute coords.
    fn gradient_pixels(width: u32, height: u32) -> Vec<f32> {
        let mut out = Vec::with_capacity(width as usize * height as usize * 4);
        for y in 0..height {
            for x in 0..width {
                #[expect(clippy::cast_precision_loss)]
                // test pixels are small; the conversion is exact
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
                #[expect(clippy::cast_precision_loss)]
                // test pixels are small; the conversion is exact
                let (x, y) = (x as f32, y as f32);
                out.extend_from_slice(&[x, y, 0.5, 1.0]);
            }
        }
        out
    }

    /// What a gain chain should produce, applied in order (same multiply
    /// order as the module, so bitwise).
    fn scaled(mut pixels: Vec<f32>, gains: &[f32]) -> Vec<f32> {
        for gain in gains {
            for value in &mut pixels {
                *value *= *gain;
            }
        }
        pixels
    }

    /// Test gain module: multiplies every pixel by its `gain` parameter.
    struct TestGain {
        desc: ModuleDesc,
    }

    struct TestGainCommit {
        gain: f32,
    }

    impl TestGain {
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

    impl IopModule for TestGain {
        fn desc(&self) -> &ModuleDesc {
            &self.desc
        }

        fn commit(
            &self,
            params: &serde_json::Map<String, serde_json::Value>,
            _image: &ImageInfo,
        ) -> Result<CommitData, PipeError> {
            #[expect(clippy::cast_possible_truncation)]
            // test gains are small; the downcast cannot lose them
            let gain = get_float(params, "gain")? as f32;
            Ok(Arc::new(TestGainCommit { gain }))
        }

        fn process(
            &self,
            data: &CommitData,
            input: &Plane<'_>,
            output: &mut PlaneMut<'_>,
            rin: Roi,
            rout: Roi,
        ) -> Result<(), PipeError> {
            let Some(commit) = data.downcast_ref::<TestGainCommit>() else {
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
    /// Same math on every path, so streaming must match whole-frame bitwise.
    struct TestBlur {
        desc: ModuleDesc,
    }

    struct TestBlurCommit;

    impl TestBlur {
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

    impl IopModule for TestBlur {
        fn desc(&self) -> &ModuleDesc {
            &self.desc
        }

        fn commit(
            &self,
            _params: &serde_json::Map<String, serde_json::Value>,
            _image: &ImageInfo,
        ) -> Result<CommitData, PipeError> {
            Ok(Arc::new(TestBlurCommit))
        }

        fn tiling(
            &self,
            _data: &CommitData,
            _rin: &Roi,
            _rout: &Roi,
        ) -> lightamer_iop_traits::TilingReq {
            lightamer_iop_traits::TilingReq {
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
            // Horizontal pass into scratch, then vertical into output.
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

    /// Test module needing whole-image statistics: streaming must refuse it
    /// before any `process` call.
    struct TestStats {
        desc: ModuleDesc,
        calls: Arc<AtomicUsize>,
    }

    struct TestStatsCommit;

    impl IopModule for TestStats {
        fn desc(&self) -> &ModuleDesc {
            &self.desc
        }

        fn stats(&self) -> StatsNeeds {
            StatsNeeds::WholeImage
        }

        fn commit(
            &self,
            _params: &serde_json::Map<String, serde_json::Value>,
            _image: &ImageInfo,
        ) -> Result<CommitData, PipeError> {
            Ok(Arc::new(TestStatsCommit))
        }

        fn process(
            &self,
            _data: &CommitData,
            input: &Plane<'_>,
            output: &mut PlaneMut<'_>,
            _rin: Roi,
            _rout: Roi,
        ) -> Result<(), PipeError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            for y in 0..output.height() {
                let src = input.row(y)?.to_vec();
                let dst = output.row_mut(y)?;
                dst.copy_from_slice(&src);
            }
            Ok(())
        }
    }

    /// Test input source: a fixed gradient, or a fixed refusal.
    struct TestInput {
        width: u32,
        height: u32,
        fail: Option<String>,
    }

    impl InputSource for TestInput {
        fn fetch(&self, _photo: &str) -> Result<super::RenderInput, InputError> {
            if let Some(reason) = &self.fail {
                return Err(InputError::new(reason.clone()));
            }
            let frame = Frame::from_parts(
                gradient_pixels(self.width, self.height),
                FrameExtent::new(0, 0, self.width, self.height),
                PixelFormat::RgbaF32Premul,
            )
            .map_err(|err| InputError::new(err.to_string()))?;
            Ok(super::RenderInput {
                frame,
                image: ImageInfo::new(self.width, self.height, ColorSpace::Rgb),
                input_id: 11,
            })
        }
    }

    /// Test input source with a region reader: regions compute straight from
    /// the gradient (no whole fetch), every call recorded. Optionally trips
    /// the shared cancel flag on one call, for deterministic mid-stream
    /// cancels.
    struct CountingInput {
        width: u32,
        height: u32,
        fetches: Arc<AtomicUsize>,
        regions: Arc<Mutex<Vec<FrameExtent>>>,
        probes: Arc<AtomicUsize>,
        fail_fetch: bool,
        cancel_on_call: Option<(Arc<std::sync::atomic::AtomicBool>, usize)>,
    }

    impl CountingInput {
        fn new(width: u32, height: u32) -> Self {
            Self {
                width,
                height,
                fetches: Arc::new(AtomicUsize::new(0)),
                regions: Arc::new(Mutex::new(Vec::new())),
                probes: Arc::new(AtomicUsize::new(0)),
                fail_fetch: false,
                cancel_on_call: None,
            }
        }
    }

    impl InputSource for CountingInput {
        fn fetch(&self, _photo: &str) -> Result<super::RenderInput, InputError> {
            self.fetches.fetch_add(1, Ordering::SeqCst);
            if self.fail_fetch {
                return Err(InputError::new(
                    "whole fetch refused: the probe and the region reader serve this photo",
                ));
            }
            let frame = Frame::from_parts(
                gradient_pixels(self.width, self.height),
                FrameExtent::new(0, 0, self.width, self.height),
                PixelFormat::RgbaF32Premul,
            )
            .map_err(|err| InputError::new(err.to_string()))?;
            Ok(super::RenderInput {
                frame,
                image: ImageInfo::new(self.width, self.height, ColorSpace::Rgb),
                input_id: 11,
            })
        }

        fn fetch_region(
            &self,
            _photo: &str,
            region: FrameExtent,
        ) -> Result<super::RenderInput, InputError> {
            let calls = self.regions.lock().map_or(0, |mut held| {
                held.push(region);
                held.len()
            });
            if let Some((flag, at)) = &self.cancel_on_call
                && calls == *at
            {
                flag.store(true, Ordering::SeqCst);
            }
            let frame =
                Frame::from_parts(region_pixels(region), region, PixelFormat::RgbaF32Premul)
                    .map_err(|err| InputError::new(err.to_string()))?;
            Ok(super::RenderInput {
                frame,
                image: ImageInfo::new(self.width, self.height, ColorSpace::Rgb),
                input_id: 11,
            })
        }

        fn probe(&self, _photo: &str) -> Result<super::RenderFacts, InputError> {
            self.probes.fetch_add(1, Ordering::SeqCst);
            Ok(super::RenderFacts {
                image: ImageInfo::new(self.width, self.height, ColorSpace::Rgb),
                extent: FrameExtent::new(0, 0, self.width, self.height),
            })
        }
    }
    /// Test input source whose probe lies about the size while regions keep
    /// the default crop-from-whole reader: real pixels stay `width` by
    /// `height`, the probe claims the lied extent. `fetch_region` stays
    /// default on purpose, so overruns hit its containment check.
    struct LyingProbeInput {
        width: u32,
        height: u32,
        probe_width: u32,
        probe_height: u32,
    }

    impl InputSource for LyingProbeInput {
        fn fetch(&self, _photo: &str) -> Result<super::RenderInput, InputError> {
            let frame = Frame::from_parts(
                gradient_pixels(self.width, self.height),
                FrameExtent::new(0, 0, self.width, self.height),
                PixelFormat::RgbaF32Premul,
            )
            .map_err(|err| InputError::new(err.to_string()))?;
            Ok(super::RenderInput {
                frame,
                image: ImageInfo::new(self.width, self.height, ColorSpace::Rgb),
                input_id: 11,
            })
        }

        fn probe(&self, _photo: &str) -> Result<super::RenderFacts, InputError> {
            Ok(super::RenderFacts {
                image: ImageInfo::new(self.probe_width, self.probe_height, ColorSpace::Rgb),
                extent: FrameExtent::new(0, 0, self.probe_width, self.probe_height),
            })
        }
    }
    /// Settings holding one enabled instance per `(module, gain)`.
    fn settings_with(mods: &[(&str, f64)]) -> PhotoSettings {
        let mut settings = PhotoSettings::default();
        for (module, gain) in mods {
            let mut params = BTreeMap::new();
            params.insert("gain".to_owned(), SettingValue::Float(*gain));
            settings.instances.upsert(ModuleInstance {
                module: (*module).to_owned(),
                multi: 0,
                name: None,
                enabled: true,
                params,
            });
        }
        settings
    }

    /// A module source holding `modules` by id (a plain table is one).
    fn table_source(modules: Vec<SharedModule>) -> super::SharedModuleSource {
        let mut map = HashMap::new();
        for module in modules {
            map.insert(module.id().to_owned(), module);
        }
        Arc::new(map)
    }

    /// Runs one render job inline (no pool) and returns its delivery.
    #[expect(clippy::too_many_arguments)]
    // one test harness over the job's own arguments
    fn run_once(
        kind: RenderKind,
        generation: u64,
        settings: &PhotoSettings,
        input: &super::SharedInputSource,
        modules: Option<&super::SharedModuleSource>,
        pipe: &Mutex<lightamer_pipeline::Pipe>,
        config: &EngineConfig,
        cancel: &Arc<std::sync::atomic::AtomicBool>,
    ) -> super::RenderDelivery {
        let (ctx, _drain) = JobCtx::for_test(7, Arc::clone(cancel));
        let (tx, rx) = std::sync::mpsc::channel();
        run_render_job(
            &ctx, &tx, "a", kind, generation, settings, input, modules, pipe, config,
        );
        rx.recv().unwrap()
    }

    /// A fresh unused cancel flag.
    fn live_flag() -> Arc<std::sync::atomic::AtomicBool> {
        Arc::new(std::sync::atomic::AtomicBool::new(false))
    }

    /// A pipe too small for whole frames but roomy for pieces.
    fn tiny_pipe(budget: u64) -> Mutex<lightamer_pipeline::Pipe> {
        Mutex::new(Pipe::with_budget_and_floor(
            PipeKind::Full,
            budget,
            64 * 1024,
        ))
    }

    /// A config assembling everything in RAM with generous limits.
    fn ram_config() -> EngineConfig {
        EngineConfig {
            spill_byte_limit: u64::MAX,
            spill_dir: None,
            kept_bytes_limit: u64::MAX,
            spill_memory_threshold: u64::MAX,
        }
    }

    /// Pixels from a direct `render_stream` run assembled through a sink.
    #[expect(clippy::too_many_arguments)]
    // one test harness over the request's own fields
    fn direct_stream_pixels(
        pipe: &mut lightamer_pipeline::Pipe,
        nodes: &[PipeNode],
        lookup: &super::ModuleSourceAdapter,
        image: &ImageInfo,
        input: &Frame,
        input_id: u64,
        process: u32,
        final_out: lightamer_geom::Roi,
    ) -> Vec<f32> {
        let no_cancel = || false;
        let req = lightamer_pipeline::RenderRequest {
            nodes,
            lookup,
            image,
            input,
            input_id,
            process,
            final_out,
            cancel: &no_cancel,
        };
        let full = super::extent_for_roi(&final_out, "output").unwrap();
        let mut sink = lightamer_pipeline::StreamSink::new(full, u64::MAX, u64::MAX, None).unwrap();
        pipe.render_stream(&req, |piece| sink.push(&piece)).unwrap();
        match sink.finish().unwrap() {
            lightamer_pipeline::StreamedOutput::Memory(frame) => frame.as_slice().to_vec(),
            lightamer_pipeline::StreamedOutput::Mapped(mapped) => RenderedImage {
                generation: 0,
                width: mapped.extent().width,
                height: mapped.extent().height,
                store: RenderedStore::Mapped(Arc::new(mapped)),
            }
            .to_vec(),
        }
    }

    /// Pixels from a direct whole-frame `render`.
    #[expect(clippy::too_many_arguments)]
    // one test harness over the request's own fields
    fn whole_pixels(
        pipe: &mut lightamer_pipeline::Pipe,
        nodes: &[PipeNode],
        lookup: &super::ModuleSourceAdapter,
        image: &ImageInfo,
        input: &Frame,
        input_id: u64,
        process: u32,
        final_out: lightamer_geom::Roi,
    ) -> Vec<f32> {
        let no_cancel = || false;
        let req = lightamer_pipeline::RenderRequest {
            nodes,
            lookup,
            image,
            input,
            input_id,
            process,
            final_out,
            cancel: &no_cancel,
        };
        pipe.render(&req).unwrap().frame().as_slice().to_vec()
    }

    /// One pipe node calling `module` with a gain parameter.
    fn gain_node(module: &str, gain: f64) -> PipeNode {
        let mut params = serde_json::Map::new();
        params.insert(
            "gain".to_owned(),
            serde_json::json!({"type": "float", "value": gain}),
        );
        PipeNode {
            id: module.to_owned(),
            multi: 0,
            params,
        }
    }

    /// One finished memory image for retention tests.
    fn kept_image(generation: u64, width: u32, height: u32) -> RenderedImage {
        RenderedImage {
            generation,
            width,
            height,
            store: RenderedStore::Memory(vec![0.0; width as usize * height as usize * 4]),
        }
    }

    /// One successful delivery for retention tests.
    fn kept_delivery(
        photo: &str,
        kind: RenderKind,
        generation: u64,
        image: RenderedImage,
    ) -> super::RenderDelivery {
        super::RenderDelivery {
            photo: photo.to_owned(),
            kind,
            generation,
            outcome: Ok(super::RenderPayload {
                image,
                record: RenderRecord {
                    generation,
                    job: 1,
                    nodes: Vec::new(),
                    skipped: Vec::new(),
                    streamed: None,
                },
            }),
        }
    }

    /// Slots holding one current generation per key.
    fn slotted(keys: &[(&str, RenderKind, u64)]) -> BTreeMap<(String, RenderKind), RenderSlot> {
        let mut slots = BTreeMap::new();
        for (photo, kind, generation) in keys {
            slots.insert(
                ((*photo).to_owned(), *kind),
                RenderSlot {
                    generation: *generation,
                    ..RenderSlot::default()
                },
            );
        }
        slots
    }
    #[test]
    fn fetch_region_default_crops_the_whole_frame() {
        let source = TestInput {
            width: 64,
            height: 48,
            fail: None,
        };
        let whole = source.fetch("a").unwrap().frame.as_slice().to_vec();
        // A sub-region equals the same rows sliced out of the whole frame.
        let region = FrameExtent::new(8, 8, 16, 16);
        let got = source.fetch_region("a", region).unwrap();
        assert_eq!(got.frame.extent(), region);
        assert_eq!(got.frame.as_slice(), region_pixels(region));
        let mut want = Vec::new();
        for row in 8usize..24 {
            let start = (row * 64 + 8) * 4;
            want.extend_from_slice(&whole[start..start + 16 * 4]);
        }
        assert_eq!(got.frame.as_slice(), want);
        // The whole frame back equals a plain fetch, bitwise.
        let full = source
            .fetch_region("a", FrameExtent::new(0, 0, 64, 48))
            .unwrap();
        assert_eq!(full.frame.as_slice(), whole);
        assert_eq!(full.input_id, 11);
        // A region leaving the frame refuses typed instead of clipping.
        let err = source
            .fetch_region("a", FrameExtent::new(60, 0, 16, 16))
            .unwrap_err();
        assert!(!err.reason().is_empty(), "{err}");
    }

    #[test]
    fn full_streams_once_per_strip_and_matches_whole_and_direct() {
        let input = CountingInput::new(256, 256);
        let fetches = Arc::clone(&input.fetches);
        let regions = Arc::clone(&input.regions);
        let input: super::SharedInputSource = Arc::new(input);
        let gain: SharedModule = Arc::new(TestGain::named("mod_gain"));
        let modules = table_source(vec![gain]);
        let settings = settings_with(&[("mod_gain", 2.0)]);
        let pipe = tiny_pipe(1024 * 1024);
        let delivery = run_once(
            RenderKind::Full,
            1,
            &settings,
            &input,
            Some(&modules),
            &pipe,
            &ram_config(),
            &live_flag(),
        );
        // No whole fetch anywhere on the streaming path: the probe sized the
        // frame, then one region call per strip.
        assert_eq!(fetches.load(Ordering::SeqCst), 0);
        assert_eq!(regions.lock().unwrap().len(), 4);
        let outcome = delivery.outcome.unwrap();
        assert_eq!(
            outcome.record.streamed,
            Some(crate::render::StreamReport {
                mode: StreamMode::Strip,
                pieces: 4,
            })
        );
        assert_eq!(outcome.record.nodes.len(), 1);
        assert_eq!(outcome.record.nodes[0].process_calls, 4);
        assert!(!outcome.record.nodes[0].hit);
        // Engine-streamed pixels equal a whole-frame render and a direct
        // streaming run, bitwise.
        let engine_pixels = outcome.image.to_vec();
        let whole_input = TestInput {
            width: 256,
            height: 256,
            fail: None,
        }
        .fetch("a")
        .unwrap();
        let adapter = super::ModuleSourceAdapter {
            source: Some(modules),
        };
        let nodes = vec![gain_node("mod_gain", 2.0)];
        let final_out = super::final_roi_for(whole_input.frame.extent()).unwrap();
        let mut fat = Pipe::with_budget_and_floor(PipeKind::Full, 64 * 1024 * 1024, 64 * 1024);
        let want_whole = whole_pixels(
            &mut fat,
            &nodes,
            &adapter,
            &whole_input.image,
            &whole_input.frame,
            whole_input.input_id,
            1,
            final_out,
        );
        let mut thin = Pipe::with_budget_and_floor(PipeKind::Full, 1024 * 1024, 64 * 1024);
        let want_stream = direct_stream_pixels(
            &mut thin,
            &nodes,
            &adapter,
            &whole_input.image,
            &whole_input.frame,
            whole_input.input_id,
            1,
            final_out,
        );
        assert_eq!(engine_pixels, want_whole);
        assert_eq!(engine_pixels, want_stream);
        assert!(!outcome.image.is_mapped());
    }
    #[test]
    fn preview_refuses_over_limit_while_export_streams() {
        let gain: SharedModule = Arc::new(TestGain::named("mod_gain"));
        let modules = table_source(vec![gain]);
        let settings = settings_with(&[("mod_gain", 2.0)]);
        // Preview: the same over-limit frame fails typed, no region call.
        let preview_in = CountingInput::new(256, 256);
        let preview_regions = Arc::clone(&preview_in.regions);
        let preview_in: super::SharedInputSource = Arc::new(preview_in);
        let pipe = tiny_pipe(1024 * 1024);
        let failed = run_once(
            RenderKind::Preview,
            1,
            &settings,
            &preview_in,
            Some(&modules),
            &pipe,
            &ram_config(),
            &live_flag(),
        );
        let failure = failed.outcome.unwrap_err();
        assert!(!failure.cancelled);
        assert!(
            failure.reason.contains("too large"),
            "unexpected: {}",
            failure.reason
        );
        assert_eq!(preview_regions.lock().unwrap().len(), 0);
        // Export: the twin streaming kind streams like full.
        let export_in = CountingInput::new(256, 256);
        let export_regions = Arc::clone(&export_in.regions);
        let export_in: super::SharedInputSource = Arc::new(export_in);
        let done = run_once(
            RenderKind::Export,
            1,
            &settings,
            &export_in,
            Some(&modules),
            &pipe,
            &ram_config(),
            &live_flag(),
        );
        let outcome = done.outcome.unwrap();
        assert_eq!(
            outcome.record.streamed.map(|run| run.mode),
            Some(StreamMode::Strip)
        );
        assert_eq!(export_regions.lock().unwrap().len(), 4);
        assert_eq!(
            outcome.image.to_vec(),
            scaled(gradient_pixels(256, 256), &[2.0])
        );
    }

    #[test]
    fn three_streamed_deliveries_land_only_latest() {
        let gain: SharedModule = Arc::new(TestGain::named("mod_gain"));
        let modules = table_source(vec![gain]);
        let pipe = tiny_pipe(1024 * 1024);
        let input: super::SharedInputSource = Arc::new(CountingInput::new(64, 64));
        let mut deliveries = Vec::new();
        for (generation, gain) in [(1, 2.0), (2, 3.0), (3, 4.0)] {
            let settings = settings_with(&[("mod_gain", gain)]);
            deliveries.push(run_once(
                RenderKind::Full,
                generation,
                &settings,
                &input,
                Some(&modules),
                &pipe,
                &ram_config(),
                &live_flag(),
            ));
        }
        let mut slots = slotted(&[("a", RenderKind::Full, 3)]);
        let mut kept = KeptImages::default();
        let mut events = Vec::new();
        for delivery in deliveries {
            events.push(apply_delivery(&mut slots, &mut kept, u64::MAX, delivery));
        }
        assert_eq!(events[0], None);
        assert_eq!(events[1], None);
        assert!(matches!(
            events[2],
            Some(crate::event::Event::RenderReady { generation: 3, .. })
        ));
        let kept_pixels = slots[&("a".to_owned(), RenderKind::Full)]
            .latest
            .as_ref()
            .unwrap()
            .to_vec();
        assert_eq!(kept_pixels, scaled(gradient_pixels(64, 64), &[4.0]));
    }

    #[test]
    fn cancelled_stream_returns_budget_and_leaves_no_spill() {
        // Spill files are anonymous (unlinked at creation): no directory
        // listing can observe them. Residue-freedom here means the mapped
        // sink dropped (its file dies with it) and every budget byte came
        // back; the stream demo asserts its dedicated spill dir stays empty.
        let flag = live_flag();
        let mut source = CountingInput::new(256, 256);
        source.cancel_on_call = Some((Arc::clone(&flag), 2));
        let regions = Arc::clone(&source.regions);
        let source: super::SharedInputSource = Arc::new(source);
        let gain: SharedModule = Arc::new(TestGain::named("mod_gain"));
        let modules = table_source(vec![gain]);
        let settings = settings_with(&[("mod_gain", 2.0)]);
        let pipe = tiny_pipe(1024 * 1024);
        let config = EngineConfig {
            spill_byte_limit: u64::MAX,
            spill_dir: None,
            kept_bytes_limit: u64::MAX,
            spill_memory_threshold: 1,
        };
        let delivery = run_once(
            RenderKind::Full,
            1,
            &settings,
            &source,
            Some(&modules),
            &pipe,
            &config,
            &flag,
        );
        let failure = delivery.outcome.unwrap_err();
        assert!(failure.cancelled);
        // Aborted right after the second region call; the mapped sink died
        // with the run and every budget byte came back.
        assert_eq!(regions.lock().unwrap().len(), 2);
        assert_eq!(pipe.lock().unwrap().budget().used(), 0);
    }

    #[test]
    fn spill_limit_refuses_before_any_piece() {
        // Refused before the sink exists, so no spill dir is even needed.
        let source = CountingInput::new(256, 256);
        let regions = Arc::clone(&source.regions);
        let source: super::SharedInputSource = Arc::new(source);
        let gain: SharedModule = Arc::new(TestGain::named("mod_gain"));
        let modules = table_source(vec![gain]);
        let settings = settings_with(&[("mod_gain", 2.0)]);
        let pipe = tiny_pipe(1024 * 1024);
        let config = EngineConfig {
            spill_byte_limit: 100,
            spill_dir: None,
            kept_bytes_limit: u64::MAX,
            spill_memory_threshold: u64::MAX,
        };
        let delivery = run_once(
            RenderKind::Full,
            1,
            &settings,
            &source,
            Some(&modules),
            &pipe,
            &config,
            &live_flag(),
        );
        let failure = delivery.outcome.unwrap_err();
        assert!(!failure.cancelled);
        assert!(
            failure.reason.contains("over the 100-byte limit"),
            "unexpected: {}",
            failure.reason
        );
        assert_eq!(regions.lock().unwrap().len(), 0);
        assert_eq!(pipe.lock().unwrap().budget().used(), 0);
    }

    #[test]
    fn thumbnail_pixels_skip_retention() {
        let mut slots = slotted(&[("a", RenderKind::Thumbnail, 1)]);
        let mut kept = KeptImages::default();
        let event = apply_delivery(
            &mut slots,
            &mut kept,
            u64::MAX,
            kept_delivery("a", RenderKind::Thumbnail, 1, kept_image(1, 16, 16)),
        );
        assert!(matches!(
            event,
            Some(crate::event::Event::RenderReady { .. })
        ));
        let slot = &slots[&("a".to_owned(), RenderKind::Thumbnail)];
        assert!(slot.latest.is_none());
        assert!(slot.last_record.is_some());
        assert_eq!(kept.bytes, 0);
        assert!(kept.order.is_empty());
    }

    #[test]
    fn retention_evicts_oldest_first_by_bytes() {
        let mut slots = slotted(&[
            ("a", RenderKind::Full, 1),
            ("b", RenderKind::Full, 1),
            ("c", RenderKind::Full, 1),
            ("d", RenderKind::Full, 1),
        ]);
        let mut kept = KeptImages::default();
        // Three 4 KiB images under an 8 KiB cap: the first one goes.
        for photo in ["a", "b", "c"] {
            let event = apply_delivery(
                &mut slots,
                &mut kept,
                8 * 1024,
                kept_delivery(photo, RenderKind::Full, 1, kept_image(1, 16, 16)),
            );
            assert!(event.is_some());
        }
        assert!(slots[&("a".to_owned(), RenderKind::Full)].latest.is_none());
        assert!(slots[&("b".to_owned(), RenderKind::Full)].latest.is_some());
        assert!(slots[&("c".to_owned(), RenderKind::Full)].latest.is_some());
        assert_eq!(kept.bytes, 8 * 1024);
        // One 16 KiB image over the same cap: delivered, then evicted with
        // everything else — retention holds nothing.
        let event = apply_delivery(
            &mut slots,
            &mut kept,
            8 * 1024,
            kept_delivery("d", RenderKind::Full, 1, kept_image(1, 32, 32)),
        );
        assert!(event.is_some());
        assert!(slots[&("d".to_owned(), RenderKind::Full)].latest.is_none());
        assert_eq!(kept.bytes, 0);
    }

    #[test]
    fn caller_held_mapped_images_survive_eviction() {
        // A 256x256 frame (four strips) spilling to disk: 1 MiB mapped.
        // Anonymous spill files (system temp dir): the caller's clone keeps
        // reading after retention evicts its own handle.
        let run_mapped = || {
            let source: super::SharedInputSource = Arc::new(CountingInput::new(256, 256));
            let gain: SharedModule = Arc::new(TestGain::named("mod_gain"));
            let modules = table_source(vec![gain]);
            let settings = settings_with(&[("mod_gain", 2.0)]);
            let pipe = tiny_pipe(1024 * 1024);
            let config = EngineConfig {
                spill_byte_limit: u64::MAX,
                spill_dir: None,
                kept_bytes_limit: u64::MAX,
                spill_memory_threshold: 1,
            };
            run_once(
                RenderKind::Full,
                1,
                &settings,
                &source,
                Some(&modules),
                &pipe,
                &config,
                &live_flag(),
            )
        };
        let first = run_mapped().outcome.unwrap();
        assert!(first.image.is_mapped());
        let mut slots = slotted(&[("a", RenderKind::Full, 1), ("b", RenderKind::Full, 1)]);
        let mut kept = KeptImages::default();
        let held = first.image.clone();
        apply_delivery(
            &mut slots,
            &mut kept,
            1536 * 1024,
            kept_delivery("a", RenderKind::Full, 1, first.image),
        );
        // Landing a second mapped image evicts the first from retention —
        // but the caller's clone still reads the live file.
        let second = run_mapped().outcome.unwrap();
        apply_delivery(
            &mut slots,
            &mut kept,
            1536 * 1024,
            kept_delivery("b", RenderKind::Full, 1, second.image),
        );
        assert!(slots[&("a".to_owned(), RenderKind::Full)].latest.is_none());
        assert!(slots[&("b".to_owned(), RenderKind::Full)].latest.is_some());
        assert_eq!(held.to_vec(), scaled(gradient_pixels(256, 256), &[2.0]));
    }

    #[test]
    fn engine_config_defaults_match_a24() {
        let config = EngineConfig::default();
        assert_eq!(config.spill_byte_limit, 8 * 1024 * 1024 * 1024);
        assert_eq!(config.spill_dir, None);
        assert_eq!(config.kept_bytes_limit, 1024 * 1024 * 1024);
        assert_eq!(config.spill_memory_threshold, 256 * 1024 * 1024);
        assert_eq!(
            (
                super::DEFAULT_SPILL_BYTE_LIMIT,
                super::DEFAULT_KEPT_BYTE_LIMIT,
                super::DEFAULT_SPILL_MEMORY_THRESHOLD
            ),
            (
                config.spill_byte_limit,
                config.kept_bytes_limit,
                config.spill_memory_threshold
            )
        );
    }

    #[test]
    fn input_refusal_passes_through_typed() {
        let source: super::SharedInputSource = Arc::new(TestInput {
            width: 256,
            height: 256,
            fail: Some("mosaic does not fit memory".to_owned()),
        });
        let gain: SharedModule = Arc::new(TestGain::named("mod_gain"));
        let modules = table_source(vec![gain]);
        let settings = settings_with(&[("mod_gain", 2.0)]);
        let pipe = tiny_pipe(1024 * 1024);
        let delivery = run_once(
            RenderKind::Full,
            1,
            &settings,
            &source,
            Some(&modules),
            &pipe,
            &ram_config(),
            &live_flag(),
        );
        let failure = delivery.outcome.unwrap_err();
        assert!(!failure.cancelled);
        assert!(
            failure.reason.contains("mosaic does not fit memory"),
            "unexpected: {}",
            failure.reason
        );
    }

    #[test]
    fn empty_chain_out_of_budget_passes_through_without_streaming() {
        // No module source: every instance skips, the chain is empty, and an
        // empty chain skips the footprint check — so a tiny budget fails the
        // output plane as out-of-budget, never as too-large-to-stream.
        let source = CountingInput::new(256, 256);
        let regions = Arc::clone(&source.regions);
        let source: super::SharedInputSource = Arc::new(source);
        let settings = settings_with(&[("mod_gain", 2.0)]);
        let pipe = tiny_pipe(1024);
        let delivery = run_once(
            RenderKind::Full,
            1,
            &settings,
            &source,
            None,
            &pipe,
            &ram_config(),
            &live_flag(),
        );
        let failure = delivery.outcome.unwrap_err();
        assert!(!failure.cancelled);
        assert!(
            failure.reason.contains("out of budget"),
            "unexpected: {}",
            failure.reason
        );
        assert_eq!(regions.lock().unwrap().len(), 0);
    }

    #[test]
    fn stream_refusal_passes_through_without_fallback() {
        let calls = Arc::new(AtomicUsize::new(0));
        let key = OrderKey {
            priority: 1.0,
            tie: 0,
        };
        let stats: SharedModule = Arc::new(TestStats {
            desc: ModuleDesc::stub("mod_stats", key, key),
            calls: Arc::clone(&calls),
        });
        let modules = table_source(vec![stats]);
        let settings = settings_with(&[("mod_stats", 0.0)]);
        let source = CountingInput::new(256, 256);
        let regions = Arc::clone(&source.regions);
        let source: super::SharedInputSource = Arc::new(source);
        let pipe = tiny_pipe(1024 * 1024);
        let delivery = run_once(
            RenderKind::Full,
            1,
            &settings,
            &source,
            Some(&modules),
            &pipe,
            &ram_config(),
            &live_flag(),
        );
        let failure = delivery.outcome.unwrap_err();
        assert!(!failure.cancelled);
        assert!(
            failure
                .reason
                .contains("streaming refused module 'mod_stats'"),
            "unexpected: {}",
            failure.reason
        );
        // Refused before anything allocated: no region call, no process
        // call, no budget held.
        assert_eq!(regions.lock().unwrap().len(), 0);
        assert_eq!(calls.load(Ordering::SeqCst), 0);
        assert_eq!(pipe.lock().unwrap().budget().used(), 0);
    }

    #[test]
    fn block_stream_matches_direct_and_whole() {
        // A 1024x1024 frame under a 24 MiB budget: the blur's overlap of 8
        // plans 2x2 blocks of side 512; the frame footprint (two 16 MiB
        // planes on the second node plus scratch) refuses whole-frame first,
        // with room to spare for the routing crop planes.
        let input = CountingInput::new(1024, 1024);
        let regions = Arc::clone(&input.regions);
        let input: super::SharedInputSource = Arc::new(input);
        let blur: SharedModule = Arc::new(TestBlur::named("mod_blur"));
        let gain: SharedModule = Arc::new(TestGain::named("mod_gain"));
        let modules = table_source(vec![blur, gain]);
        let settings = settings_with(&[("mod_blur", 0.0), ("mod_gain", 2.0)]);
        let pipe = tiny_pipe(24 * 1024 * 1024);
        let delivery = run_once(
            RenderKind::Full,
            1,
            &settings,
            &input,
            Some(&modules),
            &pipe,
            &ram_config(),
            &live_flag(),
        );
        assert_eq!(regions.lock().unwrap().len(), 4);
        let outcome = delivery.outcome.unwrap();
        assert_eq!(
            outcome.record.streamed.map(|run| (run.mode, run.pieces)),
            Some((StreamMode::Block, 4))
        );
        // Engine-streamed pixels equal a whole-frame render and a direct
        // streaming run, bitwise.
        let engine_pixels = outcome.image.to_vec();
        let whole_input = TestInput {
            width: 1024,
            height: 1024,
            fail: None,
        }
        .fetch("a")
        .unwrap();
        let adapter = super::ModuleSourceAdapter {
            source: Some(modules),
        };
        // Unknown ids sort by (module, multi): blur runs before gain.
        let nodes = vec![gain_node("mod_blur", 0.0), gain_node("mod_gain", 2.0)];
        let final_out = super::final_roi_for(whole_input.frame.extent()).unwrap();
        let mut fat = Pipe::with_budget_and_floor(PipeKind::Full, 256 * 1024 * 1024, 64 * 1024);
        let want_whole = whole_pixels(
            &mut fat,
            &nodes,
            &adapter,
            &whole_input.image,
            &whole_input.frame,
            whole_input.input_id,
            1,
            final_out,
        );
        let mut thin = Pipe::with_budget_and_floor(PipeKind::Full, 24 * 1024 * 1024, 64 * 1024);
        let want_stream = direct_stream_pixels(
            &mut thin,
            &nodes,
            &adapter,
            &whole_input.image,
            &whole_input.frame,
            whole_input.input_id,
            1,
            final_out,
        );
        assert_eq!(engine_pixels, want_whole);
        assert_eq!(engine_pixels, want_stream);
    }

    #[test]
    fn probe_default_matches_fetch_facts_field_for_field() {
        let source = TestInput {
            width: 64,
            height: 48,
            fail: None,
        };
        let fetched = source.fetch("a").unwrap();
        let probed = source.probe("a").unwrap();
        assert_eq!(probed.image, fetched.image);
        assert_eq!(probed.extent, fetched.frame.extent());
    }

    #[test]
    fn streaming_decision_precedes_any_pixel_fetch() {
        // Whole fetches refuse outright; the probe and the region reader
        // serve. A streamed delivery then proves the job sized the frame
        // from the probe and never touched whole pixels.
        let mut source = CountingInput::new(256, 256);
        source.fail_fetch = true;
        let fetches = Arc::clone(&source.fetches);
        let regions = Arc::clone(&source.regions);
        let source: super::SharedInputSource = Arc::new(source);
        let gain: SharedModule = Arc::new(TestGain::named("mod_gain"));
        let modules = table_source(vec![gain]);
        let settings = settings_with(&[("mod_gain", 2.0)]);
        let pipe = tiny_pipe(1024 * 1024);
        let delivery = run_once(
            RenderKind::Full,
            1,
            &settings,
            &source,
            Some(&modules),
            &pipe,
            &ram_config(),
            &live_flag(),
        );
        let outcome = delivery.outcome.unwrap();
        assert_eq!(
            outcome.record.streamed.map(|run| (run.mode, run.pieces)),
            Some((StreamMode::Strip, 4))
        );
        assert_eq!(fetches.load(Ordering::SeqCst), 0);
        assert_eq!(regions.lock().unwrap().len(), 4);
        assert_eq!(
            outcome.image.to_vec(),
            scaled(gradient_pixels(256, 256), &[2.0])
        );
    }

    #[test]
    fn lying_probe_larger_than_truth_fails_typed_on_default_regions() {
        // Real 256x256 pixels, probe claims 512x512: the job plans the lied
        // size and routes direct, then the default region reader overruns
        // the real frame into a typed refusal — never a quiet wrong frame.
        let source: super::SharedInputSource = Arc::new(LyingProbeInput {
            width: 256,
            height: 256,
            probe_width: 512,
            probe_height: 512,
        });
        let gain: SharedModule = Arc::new(TestGain::named("mod_gain"));
        let modules = table_source(vec![gain]);
        let settings = settings_with(&[("mod_gain", 2.0)]);
        let pipe = tiny_pipe(1024 * 1024);
        let delivery = run_once(
            RenderKind::Full,
            1,
            &settings,
            &source,
            Some(&modules),
            &pipe,
            &ram_config(),
            &live_flag(),
        );
        let failure = delivery.outcome.unwrap_err();
        assert!(!failure.cancelled);
        assert!(!failure.reason.is_empty(), "empty refusal reason");
    }

    #[test]
    fn lying_probe_smaller_than_truth_delivers_the_probed_size() {
        // Real 512x512 pixels, probe claims 256x256: the job plans the lied
        // size and delivers a 256x256 frame. This pins the consequence of a
        // lying source, not desired behavior — sources must report true sizes.
        let source: super::SharedInputSource = Arc::new(LyingProbeInput {
            width: 512,
            height: 512,
            probe_width: 256,
            probe_height: 256,
        });
        let gain: SharedModule = Arc::new(TestGain::named("mod_gain"));
        let modules = table_source(vec![gain]);
        let settings = settings_with(&[("mod_gain", 2.0)]);
        let pipe = tiny_pipe(1024 * 1024);
        let delivery = run_once(
            RenderKind::Full,
            1,
            &settings,
            &source,
            Some(&modules),
            &pipe,
            &ram_config(),
            &live_flag(),
        );
        let outcome = delivery.outcome.unwrap();
        assert_eq!(
            outcome.record.streamed.map(|run| (run.mode, run.pieces)),
            Some((StreamMode::Strip, 4))
        );
        assert_eq!((outcome.image.width, outcome.image.height), (256, 256));
        assert_eq!(
            outcome.image.to_vec(),
            scaled(gradient_pixels(256, 256), &[2.0])
        );
    }

    #[test]
    fn jobs_that_cannot_stream_never_probe() {
        // Preview, thumbnail, and empty chains can never route to streaming,
        // so none of them pays for a probe.
        let gain: SharedModule = Arc::new(TestGain::named("mod_gain"));
        let modules = table_source(vec![gain]);
        let settings = settings_with(&[("mod_gain", 2.0)]);
        for kind in [RenderKind::Preview, RenderKind::Thumbnail] {
            let source = CountingInput::new(256, 256);
            let probes = Arc::clone(&source.probes);
            let source: super::SharedInputSource = Arc::new(source);
            let pipe = tiny_pipe(1024 * 1024);
            let delivery = run_once(
                kind,
                1,
                &settings,
                &source,
                Some(&modules),
                &pipe,
                &ram_config(),
                &live_flag(),
            );
            assert!(delivery.outcome.is_err());
            assert_eq!(probes.load(Ordering::SeqCst), 0);
        }
        // Empty chain on a streaming kind: same, no probe.
        let source = CountingInput::new(256, 256);
        let probes = Arc::clone(&source.probes);
        let source: super::SharedInputSource = Arc::new(source);
        let pipe = tiny_pipe(1024);
        let delivery = run_once(
            RenderKind::Full,
            1,
            &settings,
            &source,
            None,
            &pipe,
            &ram_config(),
            &live_flag(),
        );
        assert!(delivery.outcome.is_err());
        assert_eq!(probes.load(Ordering::SeqCst), 0);
    }

    #[test]
    fn preview_whole_fetch_runs_exactly_once() {
        // Preview never probes, so its one whole fetch is its only input
        // call: no probe, no region, exactly one fetch.
        let source = CountingInput::new(256, 256);
        let fetches = Arc::clone(&source.fetches);
        let probes = Arc::clone(&source.probes);
        let regions = Arc::clone(&source.regions);
        let source: super::SharedInputSource = Arc::new(source);
        let gain: SharedModule = Arc::new(TestGain::named("mod_gain"));
        let modules = table_source(vec![gain]);
        let settings = settings_with(&[("mod_gain", 2.0)]);
        let pipe = Mutex::new(Pipe::with_budget_and_floor(
            PipeKind::Full,
            64 * 1024 * 1024,
            64 * 1024,
        ));
        let delivery = run_once(
            RenderKind::Preview,
            1,
            &settings,
            &source,
            Some(&modules),
            &pipe,
            &ram_config(),
            &live_flag(),
        );
        let outcome = delivery.outcome.unwrap();
        assert_eq!((outcome.image.width, outcome.image.height), (256, 256));
        assert_eq!(fetches.load(Ordering::SeqCst), 1);
        assert_eq!(probes.load(Ordering::SeqCst), 0);
        assert!(regions.lock().unwrap().is_empty());
    }
}
