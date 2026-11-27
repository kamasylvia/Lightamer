// SPDX-License-Identifier: GPL-3.0-or-later
// Derived from lightcraft crates/engine/src/lib.rs (commit 0da998f2) — reworked:
// `Session::execute` (the single entry point, `:512`), `commit` recording one step
// (`:587`), undo/redo-as-commands (`:724`, `:749`), and the drag-merge interaction
// (`:925`-`:945`) are re-expressed on our own history model (`lightamer-history`), where the
// stack, cursor, and interaction live per photo instead of in one global undo list.
// Added here: atomic all-or-nothing calls (state snapshot plus restore), the
// reentrancy guard, the draft session, the state digest, and job spawning.
//! The engine: one entry point, snapshots, events, jobs.
//!
//! [`Engine::execute`] is the only way to change anything: the UI, the CLI,
//! and a future MCP all call it. Reads bypass it through cheap snapshot
//! accessors; notifications arrive as [`Event`]s after a call commits.

use std::collections::{BTreeMap, VecDeque};
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::atomic::AtomicBool;
use std::sync::mpsc::{Receiver, channel};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use lightamer_catalog::{HistoryRead, Session};
use lightamer_history::{BatchAdjustments, HistoryStack, HistoryStep, PhotoSettings};
use lightamer_iop_traits::ParamsDesc;
use lightamer_pipeline::Pipe;
use serde_json::Value;

use crate::command::{self, Outcome, RunCtx, checked_params};
use crate::error::CommandError;
use crate::event::{Event, Listener, ListenerId};
use crate::jobs::{JobCtx, JobId, JobInfo, JobPool, JobStatus, JobTable, Task};
use crate::render::{
    PendingRender, RenderKind, RenderRecord, RenderSlot, RenderedImage, SharedInputSource,
    SharedModuleSource,
};

/// A parameter lookup: module id to its declared fields, if any.
type ParamLookup = Rc<dyn Fn(&str) -> Option<ParamsDesc>>;

/// How many photo stacks the engine keeps loaded on a real session: past
/// this many, the least-recently-used stack without an open interaction is
/// dropped (its committed steps are already in the store, so reloading is
/// exact). Stacks are settings-only — tens of kilobytes in practice — so 64
/// covers interactive working sets (browsing, pair culling) in single-digit
/// megabytes while batch commands stream through without pinning thousands.
pub const PHOTO_CACHE_LIMIT: usize = 64;

/// Everything a command may change synchronously: the photos plus the
/// clipboard. Cloned before each call so a failure restores it whole.
#[derive(Clone, Debug, Default, PartialEq)]
pub(crate) struct EngineState {
    photos: BTreeMap<String, HistoryStack>,
    clipboard: Option<BatchAdjustments>,
}

impl EngineState {
    /// Whether the session holds this photo id.
    pub(crate) fn photos_contains(&self, id: &str) -> bool {
        self.photos.contains_key(id)
    }
}

/// What the engine holds: nothing, a draft, or a real session.
enum SessionSlot {
    /// Fresh engine, or after `session.close`.
    None,
    /// In-memory photo ids ([`Engine::open_draft`]), for tests and demos.
    Draft,
    /// A session on disk: the engine holds its lock and its connection.
    Real(Session),
}

/// A restore job's delivered session, waiting for [`Engine::collect`] to
/// install it (the worker sends before it returns, so delivery precedes
/// the job's own completion).
struct PendingRestore {
    job: JobId,
    rx: Receiver<Session>,
}

/// The command engine: session state, listeners, and the job pool.
///
/// Single-threaded by construction (`execute`, `collect`, and the snapshot
/// accessors all take `&mut self` or `&self` on the owning thread); only job
/// work runs elsewhere, against snapshots it captured.
pub struct Engine {
    state: EngineState,
    session: SessionSlot,
    program: String,
    pending_restores: Vec<PendingRestore>,
    executing: bool,
    listeners: Vec<(ListenerId, Listener)>,
    next_listener: ListenerId,
    jobs: JobTable,
    pool: JobPool,
    lookup: Option<ParamLookup>,
    lru: VecDeque<String>,
    last_phases: CommandPhases,
    input_source: Option<SharedInputSource>,
    module_source: Option<SharedModuleSource>,
    pipes: [Arc<Mutex<Pipe>>; 4],
    renders: BTreeMap<(String, RenderKind), RenderSlot>,
    pending_renders: Vec<PendingRender>,
}

/// Wall time the latest persisted batch command on a real session spent in
/// each third: reading committed rows (`read`), computing the new settings
/// and serializing them (`compute`, including the infallible swap-in and the
/// synchronous event emission), and the single store transaction through
/// commit (`write`). Zero until such a command runs; [`Engine::execute`]
/// zeroes it before every persisted command, so a read always describes the
/// latest one. The bench reports these three thirds per round.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CommandPhases {
    /// Fetching committed rows from the store.
    pub read: Duration,
    /// New settings, serialization, swap-in, events: everything but the
    /// other two thirds.
    pub compute: Duration,
    /// The single store transaction, through commit.
    pub write: Duration,
}

/// One pipe per kind, budgeted from live physical memory (or a conservative
/// 8 GiB when the size is unreadable, so construction never fails).
fn build_pipes() -> [Arc<Mutex<Pipe>>; 4] {
    RenderKind::ALL.map(|kind| {
        let pipe_kind = kind.pipe_kind();
        let pipe = Pipe::new(pipe_kind).unwrap_or_else(|_| {
            Pipe::with_budget_and_floor(
                pipe_kind,
                lightamer_pipeline::quota_for(pipe_kind, crate::render::FALLBACK_PHYS_BYTES)
                    .memory_budget,
                lightamer_pipeline::singlebuffer_floor(
                    pipe_kind,
                    crate::render::FALLBACK_PHYS_BYTES,
                ),
            )
        });
        Arc::new(Mutex::new(pipe))
    })
}

impl Engine {
    /// A fresh engine with no session: every mutating command reports
    /// [`CommandError::NoSession`] until a session opens.
    #[must_use]
    pub fn new() -> Self {
        let (results_tx, results_rx) = channel();
        Self {
            state: EngineState::default(),
            session: SessionSlot::None,
            program: "lightamer-engine".to_owned(),
            pending_restores: Vec::new(),
            executing: false,
            listeners: Vec::new(),
            next_listener: 1,
            jobs: JobTable::new(results_rx),
            pool: JobPool::new(&results_tx),
            lookup: None,
            lru: VecDeque::new(),
            last_phases: CommandPhases::default(),
            input_source: None,
            module_source: None,
            pipes: build_pipes(),
            renders: BTreeMap::new(),
            pending_renders: Vec::new(),
        }
    }

    /// Opens a draft session holding `ids`, all in memory, nothing persisted.
    ///
    /// Drafts exist for headless tests, the CLI, and future MCP demos. A
    /// real session (opened by `session.new`, `session.open`, or
    /// `session.restore`) holds the store instead; the draft constructor
    /// stays for tests.
    #[must_use]
    pub fn open_draft<I, S>(ids: I) -> Self
    where
        I: IntoIterator<Item = S>,
        S: Into<String>,
    {
        let mut engine = Self::new();
        engine.session = SessionSlot::Draft;
        for id in ids {
            engine.state.photos.insert(
                id.into(),
                HistoryStack::new(Arc::new(PhotoSettings::default())),
            );
        }
        engine
    }

    /// Overrides how module ids resolve to parameter descriptions.
    ///
    /// The default resolves through the compiled-in registry
    /// ([`lightamer_registry::find`]); the override takes precedence when set. Tests
    /// use it to supply descriptions with declared fields, which the current
    /// registry stubs do not have yet.
    pub fn set_param_lookup(&mut self, lookup: impl Fn(&str) -> Option<ParamsDesc> + 'static) {
        self.lookup = Some(Rc::new(lookup));
    }

    /// Resolves one module id to its parameter description, if known.
    pub(crate) fn params_for(&self, module: &str) -> Option<ParamsDesc> {
        if let Some(lookup) = self.lookup.as_ref() {
            return lookup(module);
        }
        lightamer_registry::find(module).map(|desc| desc.params)
    }

    /// Runs one command by id. The entry point for every frontend.
    ///
    /// The call is atomic: unknown ids, bad params, refused enablement, and
    /// run failures all leave the engine exactly as it was and dispatch no
    /// events. Drafts (and session/job commands) hold this by cloning the
    /// state and restoring it on error; persisted commands on a real session
    /// hold it by computing first, committing one store transaction, then
    /// swapping in state that cannot fail. On success the outcome reports
    /// small facts and the collected events dispatch in emission order,
    /// before `execute` returns.
    ///
    /// # Errors
    ///
    /// One [`CommandError`] per failure mode; see its variants.
    pub fn execute(&mut self, id: &str, params: &Value) -> Result<Outcome, CommandError> {
        if self.executing {
            return Err(CommandError::Reentrant { cmd: id.to_owned() });
        }
        let Some(spec) = command::find_command(id) else {
            return Err(CommandError::UnknownCommand { cmd: id.to_owned() });
        };
        let spec = *spec;
        let checked = checked_params(&spec, params)?;
        if spec.needs_session && !self.has_session() {
            return Err(CommandError::NoSession { cmd: id.to_owned() });
        }
        if let Err(reason) = (spec.enabled)(self) {
            return Err(CommandError::Disabled {
                cmd: id.to_owned(),
                reason,
            });
        }
        self.executing = true;
        // Persisted commands on a real session run the PLAN-B §1.8 path
        // instead of the clone/restore below: they compute the new memory
        // state first, commit one store transaction, then swap the computed
        // stacks in (see `real`). The swap cannot fail, so there is nothing
        // to restore; loading a photo only adds a mirror of committed store
        // rows. Drafts and session/job commands keep the snapshot below.
        if self.has_real_session() && crate::real::is_persisted(id) {
            self.last_phases = CommandPhases::default();
            let mut ctx = RunCtx::default();
            let outcome = (spec.run)(self, &checked, &mut ctx);
            self.executing = false;
            return match outcome {
                Ok(value) => {
                    let events = ctx.take();
                    self.dispatch(&events);
                    Ok(value)
                }
                Err(err) => Err(err),
            };
        }
        let snapshot = self.state.clone();
        let mut ctx = RunCtx::default();
        let outcome = (spec.run)(self, &checked, &mut ctx);
        match outcome {
            Ok(value) => {
                let events = ctx.take();
                self.dispatch(&events);
                self.executing = false;
                Ok(value)
            }
            Err(err) => {
                self.state = snapshot;
                self.executing = false;
                Err(err)
            }
        }
    }

    /// Sends one event to every subscribed listener, in subscription order,
    /// each exactly once. Listeners subscribed or removed mid-dispatch apply
    /// to the next dispatch.
    fn dispatch(&mut self, events: &[Event]) {
        if events.is_empty() || self.listeners.is_empty() {
            return;
        }
        let listeners: Vec<(ListenerId, Listener)> = self.listeners.clone();
        for event in events {
            for (_, listener) in &listeners {
                listener(event, self);
            }
        }
    }

    /// Subscribes a listener; returns its id for [`Engine::unsubscribe`].
    pub fn subscribe(&mut self, listener: Listener) -> ListenerId {
        let id = self.next_listener;
        self.next_listener = self.next_listener.wrapping_add(1);
        self.listeners.push((id, listener));
        id
    }

    /// Removes a listener; returns whether one was subscribed under `id`.
    pub fn unsubscribe(&mut self, id: ListenerId) -> bool {
        let before = self.listeners.len();
        self.listeners.retain(|(known, _)| *known != id);
        self.listeners.len() != before
    }

    /// Starts one background job on the pool (FIFO) and returns its id.
    ///
    /// The work runs on a pool thread against whatever immutable snapshot it
    /// captured; it must check [`JobCtx::is_cancelled`] between chunks and
    /// report with [`JobCtx::report`]. Start, progress, and completion surface
    /// as events once [`Engine::collect`] drains the results queue.
    pub fn spawn_job(
        &mut self,
        kind: &str,
        label: String,
        total: u64,
        work: impl FnOnce(&JobCtx) + Send + 'static,
    ) -> JobId {
        let (id, cancel) = self.jobs.insert(kind, label, total);
        self.pool.submit(Task {
            id,
            cancel,
            work: Box::new(work),
        });
        id
    }

    /// Drains the job results queue into the table and dispatches the
    /// resulting events. Engine-thread only, like everything else here.
    ///
    /// Returns how many events were dispatched.
    pub fn collect(&mut self) -> usize {
        let events = self.jobs.drain();
        let count = events.len();
        self.dispatch(&events);
        self.finish_restores();
        let render_events = self.finish_renders();
        let render_count = render_events.len();
        self.dispatch(&render_events);
        count + render_count
    }

    /// One job's cancel flag, for the `job.cancel` run function.
    pub(crate) fn job_cancel_flag(&self, id: JobId) -> Option<Arc<AtomicBool>> {
        self.jobs.cancel_flag(id)
    }
    /// The open real session, for in-crate run functions.
    pub(crate) fn real_session(&self) -> Option<&Session> {
        match &self.session {
            SessionSlot::Real(session) => Some(session),
            SessionSlot::None | SessionSlot::Draft => None,
        }
    }

    /// The open real session, mutably, for in-crate run functions (the
    /// commit half of §1.8 borrows this while the computed stacks wait in a
    /// local, so the borrow never overlaps the swap-in).
    pub(crate) fn real_session_mut(&mut self) -> Option<&mut Session> {
        match &mut self.session {
            SessionSlot::Real(session) => Some(session),
            SessionSlot::None | SessionSlot::Draft => None,
        }
    }

    /// Installs a real session (the caller checked that none is open).
    pub(crate) fn install_real_session(&mut self, session: Session) {
        self.session = SessionSlot::Real(session);
    }

    /// Takes the open real session, leaving no session behind (`None`
    /// unless a real session is open).
    pub(crate) fn take_real_session(&mut self) -> Option<Session> {
        match std::mem::replace(&mut self.session, SessionSlot::None) {
            SessionSlot::Real(session) => Some(session),
            taken => {
                self.session = taken;
                None
            }
        }
    }

    /// Clears the synchronous state after the session closes (no session
    /// means no photos and no clipboard).
    pub(crate) fn clear_after_close(&mut self) {
        self.state.photos.clear();
        self.state.clipboard = None;
        self.lru.clear();
        self.renders.clear();
        self.pending_renders.clear();
    }

    /// Loads one photo's stack from the open real session's store into the
    /// cache (a recency touch when already loaded) and returns its store id.
    /// When every cached stack is pinned by an open interaction, the fresh
    /// stack cannot stay cached and the call is refused instead of loading a
    /// photo the run function can no longer find.
    ///
    /// # Errors
    ///
    /// [`CommandError::NoSession`] when no real session is open;
    /// [`CommandError::NoPhoto`] when the store holds no such UUID (the same
    /// error a draft reports for a photo it does not hold);
    /// [`CommandError::Store`] when the store will not answer or its rows do
    /// not rebuild; [`CommandError::Disabled`] when the cache is pinned full.
    pub(crate) fn ensure_photo_loaded(&mut self, cmd: &str, id: &str) -> Result<i64, CommandError> {
        if self.state.photos.contains_key(id) {
            self.touch_photo(id);
            return self.db_photo_id(cmd, id);
        }
        let db = self.db_photo_id(cmd, id)?;
        let stack = self.load_stack(cmd, db)?;
        self.state.photos.insert(id.to_owned(), stack);
        self.touch_photo(id);
        self.evict_photos_if_over();
        if !self.state.photos.contains_key(id) {
            return Err(CommandError::Disabled {
                cmd: cmd.to_owned(),
                reason: "the photo cache is pinned full by open interactions".to_owned(),
            });
        }
        Ok(db)
    }

    /// One photo's store id for its UUID.
    ///
    /// # Errors
    ///
    /// See [`Engine::ensure_photo_loaded`].
    pub(crate) fn db_photo_id(&self, cmd: &str, id: &str) -> Result<i64, CommandError> {
        let Some(session) = self.real_session() else {
            return Err(CommandError::NoSession {
                cmd: cmd.to_owned(),
            });
        };
        match lightamer_catalog::find_photo_by_uuid(session.connection(), id) {
            Ok(Some(record)) => Ok(record.id),
            Ok(None) => Err(CommandError::NoPhoto {
                cmd: cmd.to_owned(),
                photo: id.to_owned(),
            }),
            Err(err) => Err(CommandError::Store {
                cmd: cmd.to_owned(),
                reason: err.to_string(),
            }),
        }
    }

    /// Rebuilds one photo's stack from its stored steps (labels, settings,
    /// cursor) without caching it; the caller inserts the result.
    ///
    /// # Errors
    ///
    /// See [`Engine::ensure_photo_loaded`].
    fn load_stack(&self, cmd: &str, db: i64) -> Result<HistoryStack, CommandError> {
        let store = |reason: String| CommandError::Store {
            cmd: cmd.to_owned(),
            reason,
        };
        let Some(session) = self.real_session() else {
            return Err(CommandError::NoSession {
                cmd: cmd.to_owned(),
            });
        };
        let read = lightamer_catalog::read_history(session.connection(), db)
            .map_err(|err| store(err.to_string()))?;
        let mut steps = Vec::with_capacity(read.steps.len());
        for stored in &read.steps {
            let settings = PhotoSettings::from_json(&stored.settings_json).map_err(|err| {
                store(format!(
                    "stored step {} of photo {db} does not parse: {err}",
                    stored.idx
                ))
            })?;
            steps.push(HistoryStep {
                label: stored.label.clone(),
                settings: Arc::new(settings),
            });
        }
        let cursor = usize::try_from(read.cursor).map_err(|_| {
            store(format!(
                "stored cursor {} of photo {db} does not fit",
                read.cursor
            ))
        })?;
        HistoryStack::from_steps(steps, cursor).map_err(|err| store(err.to_string()))
    }

    /// Swaps a computed stack into the cache (the §1.8 step 3): infallible by
    /// construction — the stack was fully computed before the store commit.
    pub(crate) fn insert_photo_stack(&mut self, id: &str, stack: HistoryStack) {
        self.state.photos.insert(id.to_owned(), stack);
        self.touch_photo(id);
        self.evict_photos_if_over();
    }

    /// Marks one cached photo most-recently-used.
    fn touch_photo(&mut self, id: &str) {
        self.lru.retain(|known| known != id);
        self.lru.push_back(id.to_owned());
    }

    /// Evicts least-recently-used cached stacks past [`PHOTO_CACHE_LIMIT`].
    /// Drafts never evict (no store backs them); stacks with an open
    /// interaction never evict (their live value exists only in memory), so
    /// when every cached stack is pinned the cap yields instead of looping.
    fn evict_photos_if_over(&mut self) {
        if !self.has_real_session() {
            return;
        }
        let mut pinned_seen = 0;
        while self.state.photos.len() > PHOTO_CACHE_LIMIT {
            let Some(oldest) = self.lru.pop_front() else {
                break;
            };
            let pinned = self
                .state
                .photos
                .get(&oldest)
                .is_some_and(HistoryStack::is_interaction_open);
            if pinned {
                self.lru.push_back(oldest);
                pinned_seen += 1;
                if pinned_seen >= self.lru.len() {
                    break;
                }
                continue;
            }
            pinned_seen = 0;
            self.state.photos.remove(&oldest);
        }
    }

    /// Whether this photo's stack is currently loaded (real sessions load on
    /// first use; drafts hold everything from the start).
    #[must_use]
    pub fn is_photo_loaded(&self, id: &str) -> bool {
        self.state.photos.contains_key(id)
    }

    /// How many photo stacks are currently loaded.
    #[must_use]
    pub fn loaded_photo_count(&self) -> usize {
        self.state.photos.len()
    }

    /// The read/compute/write thirds of the latest persisted batch command
    /// on a real session (zero until one runs; see [`CommandPhases`]).
    #[must_use]
    pub fn last_command_phases(&self) -> CommandPhases {
        self.last_phases
    }

    /// Records the thirds of the just-finished persisted command (called by
    /// `real` once per batch command, after the infallible swap-in).
    pub(crate) fn set_last_phases(&mut self, phases: CommandPhases) {
        self.last_phases = phases;
    }

    /// One photo's stored history without caching it: `None` when the photo
    /// is unknown or the store will not answer. Snapshot accessors serve
    /// loaded stacks from the cache and fall back to this.
    fn stored_history(&self, id: &str) -> Option<HistoryRead> {
        let session = self.real_session()?;
        let record = lightamer_catalog::find_photo_by_uuid(session.connection(), id).ok()??;
        lightamer_catalog::read_history(session.connection(), record.id).ok()
    }

    /// Remembers a restore job's delivery channel until [`Engine::collect`].
    pub(crate) fn track_restore(&mut self, job: JobId, rx: Receiver<Session>) {
        self.pending_restores.push(PendingRestore { job, rx });
    }

    /// Installs the input source renders fetch their pixels from.
    pub fn set_input_source(&mut self, source: SharedInputSource) {
        self.input_source = Some(source);
    }

    /// Installs the module source renders resolve modules through.
    pub fn set_module_source(&mut self, source: SharedModuleSource) {
        self.module_source = Some(source);
    }

    /// The installed input source, if any.
    pub(crate) fn input_source(&self) -> Option<SharedInputSource> {
        self.input_source.clone()
    }

    /// The installed module source, if any (`None` renders empty chains).
    pub(crate) fn module_source(&self) -> Option<SharedModuleSource> {
        self.module_source.clone()
    }

    /// This kind's pipe, shared with its render jobs.
    pub(crate) fn render_pipe(&self, kind: RenderKind) -> Arc<Mutex<Pipe>> {
        let [full, export, preview, thumbnail] = &self.pipes;
        let pipe = match kind {
            RenderKind::Full => full,
            RenderKind::Export => export,
            RenderKind::Preview => preview,
            RenderKind::Thumbnail => thumbnail,
        };
        Arc::clone(pipe)
    }

    /// One (photo, kind) pair's render slot, if it ever rendered.
    pub(crate) fn render_slot(&self, photo: &str, kind: RenderKind) -> Option<&RenderSlot> {
        self.renders.get(&(photo.to_owned(), kind))
    }

    /// One (photo, kind) pair's render slot, creating it on first request.
    pub(crate) fn render_slot_mut(&mut self, photo: &str, kind: RenderKind) -> &mut RenderSlot {
        self.renders.entry((photo.to_owned(), kind)).or_default()
    }

    /// One photo's latest finished pixels for one kind, if any render of
    /// the pair finished. A clone: small frames copy cheaply, full frames
    /// copy a plane.
    #[must_use]
    pub fn rendered_image(&self, photo: &str, kind: RenderKind) -> Option<RenderedImage> {
        self.render_slot(photo, kind)
            .and_then(|slot| slot.latest.clone())
    }

    /// What the latest generation's latest delivery did: per-node hit or
    /// recompute plus the skips. For demos and tests.
    #[must_use]
    pub fn last_render_record(&self, photo: &str, kind: RenderKind) -> Option<RenderRecord> {
        self.render_slot(photo, kind)
            .and_then(|slot| slot.last_record.clone())
    }

    /// Latest requested generation of one pair (0 before the first request).
    #[must_use]
    pub fn render_generation(&self, photo: &str, kind: RenderKind) -> u64 {
        self.render_slot(photo, kind)
            .map_or(0, |slot| slot.generation)
    }

    /// Budget bytes one kind's pipe currently holds (cache plus any
    /// in-flight render). For tests asserting bytes return.
    #[must_use]
    pub fn render_budget_used(&self, kind: RenderKind) -> u64 {
        self.render_pipe(kind)
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .budget()
            .used()
    }

    /// Remembers a render job's delivery channel until [`Engine::collect`].
    pub(crate) fn track_render(
        &mut self,
        job: JobId,
        photo: String,
        kind: RenderKind,
        generation: u64,
        rx: Receiver<crate::render::RenderDelivery>,
    ) {
        self.pending_renders.push(PendingRender {
            job,
            photo,
            kind,
            generation,
            rx,
        });
    }

    /// Applies render deliveries whose jobs reached a terminal state. Only
    /// the latest generation of each pair lands; anything older is dropped
    /// whole. Returns the render events to dispatch.
    fn finish_renders(&mut self) -> Vec<Event> {
        let mut events = Vec::new();
        let mut index = 0;
        while index < self.pending_renders.len() {
            let status = self
                .pending_renders
                .get(index)
                .and_then(|pending| self.jobs.info(pending.job).map(|info| info.status));
            match status {
                None => {
                    self.pending_renders.remove(index);
                }
                Some(JobStatus::Queued | JobStatus::Running) => {
                    index += 1;
                }
                Some(status) => {
                    let pending = self.pending_renders.remove(index);
                    // Delivery precedes completion on the worker (send, then
                    // return), so a finished job's message is already here;
                    // a skipped job sent nothing and clears through the
                    // terminal path instead.
                    match pending.rx.try_recv() {
                        Ok(delivery) => {
                            if let Some(event) =
                                crate::render::apply_delivery(&mut self.renders, delivery)
                            {
                                events.push(event);
                            }
                        }
                        Err(_) => {
                            if let Some(event) = crate::render::apply_terminal_without_delivery(
                                &mut self.renders,
                                &pending.photo,
                                pending.kind,
                                pending.generation,
                                pending.job,
                                &status,
                            ) {
                                events.push(event);
                            }
                        }
                    }
                }
            }
        }
        events
    }

    /// Starts the missing-file scan behind `session.open` (and behind a
    /// restored session): the scan opens its own connection, so the engine
    /// keeps holding its session while the job runs.
    pub(crate) fn spawn_scan_job(&mut self, root: PathBuf, db: PathBuf) -> JobId {
        let label = format!("scan {}", root.display());
        self.spawn_job(
            "session.scan",
            label,
            0,
            move |ctx| match lightamer_catalog::scan_missing(
                &db,
                &root,
                &|done| ctx.report(done),
                &|| ctx.is_cancelled(),
            ) {
                Ok(_) | Err(lightamer_catalog::CatalogError::Cancelled) => {}
                Err(err) => ctx.fail(err.to_string()),
            },
        )
    }

    /// Installs restore deliveries whose jobs finished whole: a finished
    /// job's session waits on its channel (the worker sends before it
    /// returns). Failed or cancelled jobs drop their pending slot. When a
    /// session opened in the meantime, the delivered one is closed instead
    /// of clobbering it.
    fn finish_restores(&mut self) {
        let mut index = 0;
        while index < self.pending_restores.len() {
            let status = self
                .pending_restores
                .get(index)
                .and_then(|pending| self.jobs.info(pending.job).map(|info| info.status));
            match status {
                None | Some(JobStatus::Finished { cancelled: true } | JobStatus::Failed(_)) => {
                    self.pending_restores.remove(index);
                }
                Some(JobStatus::Finished { cancelled: false }) => {
                    let pending = self.pending_restores.remove(index);
                    // Delivery precedes completion on the worker (send, then
                    // return), so a finished job's message is already here;
                    // anything else drops the slot without installing.
                    if let Ok(session) = pending.rx.try_recv() {
                        self.install_restored(session);
                    }
                }
                Some(JobStatus::Queued | JobStatus::Running) => {
                    index += 1;
                }
            }
        }
    }

    /// Installs a restored session and starts its scan; closes the
    /// delivered session when one is already open.
    fn install_restored(&mut self, session: Session) {
        if self.has_session() {
            let _ = lightamer_catalog::close_session(session);
            return;
        }
        let root = session.root().to_path_buf();
        let db = session.db_path().to_path_buf();
        self.install_real_session(session);
        self.spawn_scan_job(root, db);
    }

    /// Whether a session (draft or real) is open.
    #[must_use]
    pub fn has_session(&self) -> bool {
        !matches!(self.session, SessionSlot::None)
    }

    /// Whether a real (on-disk) session is open.
    #[must_use]
    pub fn has_real_session(&self) -> bool {
        matches!(self.session, SessionSlot::Real(_))
    }

    /// The open real session's root directory, if one is open.
    #[must_use]
    pub fn session_root(&self) -> Option<&Path> {
        match &self.session {
            SessionSlot::Real(session) => Some(session.root()),
            SessionSlot::None | SessionSlot::Draft => None,
        }
    }

    /// The program name the session commands hand to the store (the lock
    /// holder hint and the `created_by` row name this).
    #[must_use]
    pub fn program(&self) -> &str {
        &self.program
    }

    /// Overrides [`Engine::program`] (`lightamer-engine` by default);
    /// frontends set their own name so the holder hint names them.
    pub fn set_program(&mut self, name: &str) {
        name.clone_into(&mut self.program);
    }

    /// Whether the clipboard holds copied adjustments.
    #[must_use]
    pub fn has_clipboard(&self) -> bool {
        self.state.clipboard.is_some()
    }

    /// The open session's photo ids, in sorted order (on a real session the
    /// store lists them, so photos never loaded still show).
    #[must_use]
    pub fn photo_ids(&self) -> Vec<String> {
        if let Some(session) = self.real_session() {
            match lightamer_catalog::list_photo_uuids(session.connection()) {
                Ok(mut ids) => {
                    ids.sort();
                    ids
                }
                Err(_) => Vec::new(),
            }
        } else {
            self.state.photos.keys().cloned().collect()
        }
    }

    /// One photo's current settings (the live value mid-interaction). Loaded
    /// stacks answer from the cache; the rest read through to the store.
    #[must_use]
    pub fn photo_settings(&self, id: &str) -> Option<Arc<PhotoSettings>> {
        if let Some(stack) = self.state.photos.get(id) {
            return stack.current().cloned();
        }
        let read = self.stored_history(id)?;
        let cursor = usize::try_from(read.cursor).ok()?;
        let stored = read.steps.get(cursor)?;
        PhotoSettings::from_json(&stored.settings_json)
            .ok()
            .map(Arc::new)
    }

    /// One photo's step labels, oldest first (read-through like
    /// [`Engine::photo_settings`]).
    #[must_use]
    pub fn photo_labels(&self, id: &str) -> Option<Vec<String>> {
        if let Some(stack) = self.state.photos.get(id) {
            return Some(stack.labels().iter().map(ToString::to_string).collect());
        }
        self.stored_history(id)
            .map(|read| read.steps.iter().map(|step| step.label.clone()).collect())
    }

    /// One photo's cursor position (read-through like
    /// [`Engine::photo_settings`]).
    #[must_use]
    pub fn photo_cursor(&self, id: &str) -> Option<usize> {
        if let Some(stack) = self.state.photos.get(id) {
            return Some(stack.cursor_index());
        }
        let read = self.stored_history(id)?;
        usize::try_from(read.cursor).ok()
    }

    /// One photo's step count (read-through like [`Engine::photo_settings`]).
    #[must_use]
    pub fn photo_len(&self, id: &str) -> Option<usize> {
        if let Some(stack) = self.state.photos.get(id) {
            return Some(stack.len());
        }
        self.stored_history(id).map(|read| read.steps.len())
    }

    /// The job table, oldest first.
    #[must_use]
    pub fn jobs(&self) -> Vec<JobInfo> {
        self.jobs.infos()
    }

    /// One job row, if it is in the table.
    #[must_use]
    pub fn job(&self, id: JobId) -> Option<JobInfo> {
        self.jobs.info(id)
    }

    /// The synchronous state, for in-crate run functions and tests.
    pub(crate) const fn state(&self) -> &EngineState {
        &self.state
    }

    /// One photo's stack, for in-crate run functions.
    pub(crate) fn stack_mut(&mut self, id: &str) -> Option<&mut HistoryStack> {
        self.state.photos.get_mut(id)
    }

    /// The clipboard, for in-crate run functions.
    pub(crate) fn clipboard_mut(&mut self) -> &mut Option<BatchAdjustments> {
        &mut self.state.clipboard
    }

    /// Builds the change event for one photo after a mutation.
    pub(crate) fn photo_event(&self, id: &str) -> Option<Event> {
        let stack = self.state.photos.get(id)?;
        Some(Event::PhotoChanged {
            photo: id.to_owned(),
            steps: stack.len(),
            cursor: stack.cursor_index(),
        })
    }

    /// A stable digest of the whole synchronous state plus the job table.
    ///
    /// Drafts hash every photo's steps (labels and canonical settings),
    /// cursors, process versions (inside the canonical bytes), the clipboard,
    /// and the job rows. Real sessions hash the store's committed histories
    /// instead of the loaded mirrors — plus what memory alone holds (open
    /// drag values, the clipboard) plus the job rows — so poking the store
    /// behind the engine's back, or a drag update that never commits, moves
    /// the digest, while loading or evicting a cache mirror does not.
    /// FNV-1a over the same canonical bytes [`PhotoSettings::hash64`] uses.
    #[must_use]
    pub fn state_digest(&self) -> u64 {
        if self.has_real_session() {
            return self.digest_real_state();
        }
        self.digest_draft_state()
    }

    /// The draft half of [`Engine::state_digest`]: loaded stacks verbatim.
    fn digest_draft_state(&self) -> u64 {
        const OFFSET: u64 = 0xcbf2_9ce4_8422_2325;
        const PRIME: u64 = 0x0100_0000_01b3;
        let mut hash = OFFSET;
        let mut mix = |bytes: &[u8]| {
            for byte in bytes {
                hash ^= u64::from(*byte);
                hash = hash.wrapping_mul(PRIME);
            }
        };
        for (id, stack) in &self.state.photos {
            mix(id.as_bytes());
            mix(&stack.cursor_index().to_le_bytes());
            for index in 0..stack.len() {
                if let Some(step) = stack.step(index) {
                    mix(step.label.as_bytes());
                    mix(step
                        .settings
                        .canonical_json()
                        .unwrap_or_default()
                        .as_bytes());
                }
            }
        }
        self.mix_clipboard_and_jobs(&mut hash);
        hash
    }

    /// The real-session half of [`Engine::state_digest`]: committed histories
    /// from the store, open drag values from the loaded stacks, then the
    /// shared clipboard-and-jobs tail.
    fn digest_real_state(&self) -> u64 {
        const OFFSET: u64 = 0xcbf2_9ce4_8422_2325;
        const PRIME: u64 = 0x0100_0000_01b3;
        let mut hash = OFFSET;
        let mut mix = |bytes: &[u8]| {
            for byte in bytes {
                hash ^= u64::from(*byte);
                hash = hash.wrapping_mul(PRIME);
            }
        };
        if let Some(session) = self.real_session() {
            let mut ids =
                lightamer_catalog::list_photo_uuids(session.connection()).unwrap_or_default();
            ids.sort();
            for id in &ids {
                mix(id.as_bytes());
                match self.stored_history(id) {
                    Some(read) => {
                        mix(&read.cursor.to_le_bytes());
                        for step in &read.steps {
                            mix(step.label.as_bytes());
                            mix(step.settings_json.as_bytes());
                        }
                    }
                    None => mix(b"store-unreadable"),
                }
            }
        }
        for (id, stack) in &self.state.photos {
            if stack.is_interaction_open()
                && let Some(live) = stack.current()
            {
                mix(b"live:");
                mix(id.as_bytes());
                mix(live.canonical_json().unwrap_or_default().as_bytes());
            }
        }
        self.mix_clipboard_and_jobs(&mut hash);
        hash
    }

    /// Mixes the clipboard and the job table into `hash` (both digests share
    /// this tail, byte for byte).
    fn mix_clipboard_and_jobs(&self, hash: &mut u64) {
        const PRIME: u64 = 0x0100_0000_01b3;
        let mut mix = |bytes: &[u8]| {
            for byte in bytes {
                *hash ^= u64::from(*byte);
                *hash = hash.wrapping_mul(PRIME);
            }
        };
        match self.state.clipboard.as_ref() {
            Some(batch) => {
                mix(b"clipboard:");
                mix(serde_json::to_string(&batch.instances)
                    .unwrap_or_default()
                    .as_bytes());
            }
            None => mix(b"clipboard:-"),
        }
        for info in self.jobs() {
            mix(&info.id.to_le_bytes());
            mix(info.kind.as_bytes());
            mix(info.label.as_bytes());
            mix(format!("{:?}", info.status).as_bytes());
            mix(&info.done.to_le_bytes());
            mix(&info.total.to_le_bytes());
        }
    }

    /// [`Engine::state_digest`] as a decimal string (all 64-bit hashes this
    /// project stores or prints use the decimal form).
    #[must_use]
    pub fn state_digest_decimal(&self) -> String {
        self.state_digest().to_string()
    }
}

impl Default for Engine {
    /// Same as [`Engine::new`]: no session open.
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for Engine {
    /// Asks every unfinished job to stop, then drops the pool (which skips
    /// the queued and joins the running): no worker outlives the engine.
    /// Cooperative jobs must honor their cancel flag promptly; a job that
    /// never checks can delay this `Drop` until it returns.
    fn drop(&mut self) {
        self.jobs.cancel_all_unfinished();
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use std::cell::RefCell;
    use std::rc::Rc;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicBool, Ordering};

    use lightamer_history::{PhotoSettings, ProcessVersion};
    use lightamer_iop_traits::ParamsDesc;
    use serde_json::{Map, Value, json};

    use super::Engine;
    use crate::command::command_specs;
    use crate::error::CommandError;
    use crate::event::{Event, Listener};
    use crate::jobs::JobStatus;

    #[test]
    fn fresh_engine_has_no_session_and_empty_views() {
        let engine = Engine::new();
        assert!(!engine.has_session());
        assert_eq!(engine.photo_ids(), Vec::<String>::new());
        assert!(engine.photo_settings("p").is_none());
        assert_eq!(engine.jobs().len(), 0);
        assert!(!engine.has_clipboard());
    }

    #[test]
    fn draft_opens_with_one_step_per_photo() {
        let engine = Engine::open_draft(["b", "a"]);
        assert!(engine.has_session());
        assert_eq!(engine.photo_ids(), ["a", "b"]);
        assert_eq!(engine.photo_len("a"), Some(1));
        assert_eq!(engine.photo_cursor("a"), Some(0));
        assert_eq!(engine.photo_labels("a"), Some(vec!["import".to_owned()]));
        assert!(engine.photo_settings("a").is_some());
    }

    /// A draft with an open lookup plus a copied clipboard, ready for the
    /// atomicity table (every bad-params case below must fail on its own
    /// terms, never on a missing precondition).
    fn atomicity_draft() -> Engine {
        let mut engine = Engine::open_draft(["a", "b"]);
        engine.set_param_lookup(|_| Some(ParamsDesc::unset()));
        engine
            .execute(
                "develop.set",
                &json!({"ids": ["a"], "module": "mod_a", "patch": {"p": {"type": "bool", "value": true}}}),
            )
            .expect("seed step");
        engine
            .execute("develop.copy", &json!({"id": "a"}))
            .expect("seed clipboard");
        engine
    }

    /// Three failing param sets per registered command. Each triple covers
    /// the shape checks plus that command's own validation.
    #[allow(clippy::too_many_lines)] // a data table: one row per command
    fn bad_params_cases() -> Vec<(&'static str, Vec<Value>)> {
        let set_patch = || json!({"p": {"type": "bool", "value": true}});
        vec![
            (
                "develop.set",
                vec![
                    json!({"ids": ["a"], "module": "mod_a", "patch": set_patch(), "bogus": 1}),
                    json!({"module": "mod_a", "patch": set_patch()}),
                    json!({"ids": ["a"], "module": "mod_a", "patch": {"p": 1.5}}),
                ],
            ),
            (
                "develop.reset",
                vec![
                    json!({"ids": ["a"], "bogus": 1}),
                    json!({}),
                    json!({"ids": "a"}),
                ],
            ),
            (
                "develop.copy",
                vec![
                    json!({"id": "a", "bogus": 1}),
                    json!({}),
                    json!({"id": "__no_such_photo__"}),
                ],
            ),
            (
                "develop.paste",
                vec![
                    json!({"ids": ["a"], "bogus": 1}),
                    json!({}),
                    json!({"ids": ["__no_such_photo__"]}),
                ],
            ),
            (
                "develop.merge",
                vec![
                    json!({"ids": ["a"], "bogus": 1}),
                    json!({}),
                    json!({"ids": ["__no_such_photo__"]}),
                ],
            ),
            (
                "develop.sync",
                vec![
                    json!({"id": "a", "ids": ["a"], "bogus": 1}),
                    json!({"ids": ["a"]}),
                    json!({"id": "__no_such_photo__", "ids": ["a"]}),
                ],
            ),
            (
                "develop.beginInteraction",
                vec![
                    json!({"id": "a", "bogus": 1}),
                    json!({}),
                    json!({"id": "__no_such_photo__"}),
                ],
            ),
            (
                "develop.updateInteraction",
                vec![
                    json!({"id": "a", "module": "mod_a", "patch": set_patch(), "bogus": 1}),
                    json!({"id": "a", "module": "mod_a"}),
                    json!({"id": "a", "module": "mod_a", "patch": set_patch()}),
                ],
            ),
            (
                "develop.endInteraction",
                vec![
                    json!({"id": "a", "bogus": 1}),
                    json!({}),
                    json!({"id": "__no_such_photo__"}),
                ],
            ),
            (
                "develop.cancelInteraction",
                vec![
                    json!({"id": "a", "bogus": 1}),
                    json!({}),
                    json!({"id": "__no_such_photo__"}),
                ],
            ),
            (
                "history.undo",
                vec![
                    json!({"id": "b", "bogus": 1}),
                    json!({}),
                    // `b` still sits on its single import step: nothing to undo.
                    json!({"id": "b"}),
                ],
            ),
            (
                "history.redo",
                vec![
                    json!({"id": "a", "bogus": 1}),
                    json!({}),
                    json!({"id": "a"}),
                ],
            ),
            (
                "history.goto",
                vec![
                    json!({"id": "a", "index": 0, "bogus": 1}),
                    json!({"id": "a"}),
                    json!({"id": "a", "index": 99}),
                ],
            ),
            (
                "process.update",
                vec![
                    json!({"ids": ["a"], "bogus": 1}),
                    json!({}),
                    json!({"ids": ["__no_such_photo__"]}),
                ],
            ),
            (
                "job.cancel",
                vec![
                    json!({"job": 1, "bogus": 1}),
                    json!({}),
                    json!({"job": "1"}),
                ],
            ),
            (
                "session.new",
                vec![
                    json!({"name": "s", "parent": "p", "bogus": 1}),
                    json!({"name": "s"}),
                    json!({"name": "s", "parent": "p"}),
                ],
            ),
            (
                "session.open",
                vec![
                    json!({"path": "p", "bogus": 1}),
                    json!({}),
                    json!({"path": "p"}),
                ],
            ),
            (
                "session.close",
                vec![json!({"bogus": 1}), json!({"other": 2}), json!({})],
            ),
            (
                "session.verify",
                vec![json!({"bogus": 1}), json!({"other": 2}), json!({})],
            ),
            (
                "session.backup",
                vec![
                    json!({"dest": "d", "bogus": 1}),
                    json!({}),
                    json!({"dest": "d"}),
                ],
            ),
            (
                "session.restore",
                vec![
                    json!({"backup": "b", "dest": "d", "bogus": 1}),
                    json!({"backup": "b"}),
                    json!({"backup": "b", "dest": "d"}),
                ],
            ),
            (
                "template.save",
                vec![
                    json!({"name": "t", "bogus": 1}),
                    json!({}),
                    json!({"name": "t"}),
                ],
            ),
            (
                "render.request",
                vec![
                    json!({"photo": "a", "kind": "preview", "bogus": 1}),
                    json!({}),
                    json!({"photo": "zz", "kind": "preview"}),
                ],
            ),
            (
                "render.cancel",
                vec![
                    json!({"photo": "a", "kind": "preview", "bogus": 1}),
                    json!({}),
                    json!({"photo": "zz", "kind": "preview"}),
                ],
            ),
        ]
    }

    #[test]
    fn failing_calls_leave_state_and_digest_unchanged_for_every_command() {
        let cases = bad_params_cases();
        let registered: Vec<&str> = command_specs().iter().map(|spec| spec.id).collect();
        assert_eq!(cases.len(), registered.len(), "table covers every command");
        for (id, _) in &cases {
            assert!(registered.contains(id), "{id} is not registered");
        }
        for (id, params_list) in &cases {
            assert_eq!(params_list.len(), 3, "{id} needs exactly three bad cases");
            for (nth, params) in params_list.iter().enumerate() {
                let mut engine = atomicity_draft();
                let before_state = engine.state().clone();
                let before_digest = engine.state_digest();
                let err = engine
                    .execute(id, params)
                    .expect_err(&format!("{id} case {nth} must fail"));
                assert_eq!(
                    engine.state(),
                    &before_state,
                    "{id} case {nth} ({err}) mutated state"
                );
                assert_eq!(
                    engine.state_digest(),
                    before_digest,
                    "{id} case {nth} moved the digest"
                );
            }
        }
    }

    #[test]
    fn unknown_command_and_non_object_params_fail_cleanly() {
        let mut engine = atomicity_draft();
        let before = engine.state_digest();
        let err = engine
            .execute("no.such.command", &json!({}))
            .expect_err("unknown id");
        assert!(matches!(err, CommandError::UnknownCommand { .. }), "{err}");
        let err = engine
            .execute("develop.reset", &json!([1]))
            .expect_err("array params");
        assert!(matches!(err, CommandError::BadParam { .. }), "{err}");
        assert_eq!(engine.state_digest(), before);
    }

    #[test]
    fn every_command_refuses_without_a_session() {
        for spec in command_specs() {
            let mut engine = Engine::new();
            let empty = Value::Object(Map::default());
            let err = engine
                .execute(spec.id, &empty)
                .expect_err(&format!("{} runs?", spec.id));
            // Shape checks run before the session gate, so bare `{}` reports
            // missing params on commands that require them; the session gate
            // itself is pinned below with valid params.
            assert!(
                matches!(
                    err,
                    CommandError::MissingParam { .. } | CommandError::NoSession { .. }
                ),
                "{}: {err}",
                spec.id
            );
        }
        // With valid params, the gate reports the missing session by name.
        let mut engine = Engine::new();
        let err = engine
            .execute("develop.reset", &json!({"ids": ["a"]}))
            .expect_err("no session");
        assert!(matches!(err, CommandError::NoSession { .. }), "{err}");
    }

    #[test]
    fn listener_calls_to_execute_fail_reentrant_and_change_nothing() {
        let mut engine = atomicity_draft();
        let seen: Rc<RefCell<Vec<CommandError>>> = Rc::new(RefCell::new(Vec::new()));
        let seen_in = Rc::clone(&seen);
        let listener: Listener = Rc::new(move |_event, engine: &mut Engine| {
            let err = engine
                .execute("history.undo", &json!({"id": "a"}))
                .expect_err("nested call must fail");
            seen_in.borrow_mut().push(err);
        });
        engine.subscribe(listener);
        engine
            .execute("develop.reset", &json!({"ids": ["a"]}))
            .expect("outer call runs");
        let seen = seen.borrow();
        assert_eq!(seen.len(), 1);
        assert!(
            matches!(seen[0], CommandError::Reentrant { .. }),
            "{}",
            seen[0]
        );
        assert_eq!(engine.photo_len("a"), Some(3), "nested undo must not run");
    }

    #[test]
    fn mutating_commands_commit_one_labelled_step_per_photo() {
        let mut engine = Engine::open_draft(["a", "b"]);
        engine.set_param_lookup(|_| Some(ParamsDesc::unset()));
        engine
            .execute(
                "develop.set",
                &json!({"ids": ["a", "b"], "module": "mod_a", "patch": {}}),
            )
            .expect("set");
        for id in ["a", "b"] {
            assert_eq!(engine.photo_len(id), Some(2));
            assert_eq!(
                engine.photo_labels(id).expect("labels").last(),
                Some(&"develop.set".to_owned())
            );
        }
    }

    #[test]
    fn one_call_over_two_photos_dispatches_two_ordered_events() {
        let mut engine = Engine::open_draft(["a", "b"]);
        engine.set_param_lookup(|_| Some(ParamsDesc::unset()));
        let seen: Rc<RefCell<Vec<Event>>> = Rc::new(RefCell::new(Vec::new()));
        let seen_in = Rc::clone(&seen);
        let listener: Listener = Rc::new(move |event, _| seen_in.borrow_mut().push(event.clone()));
        engine.subscribe(listener);
        engine
            .execute("develop.reset", &json!({"ids": ["b", "a"]}))
            .expect("reset");
        assert_eq!(
            seen.borrow().clone(),
            vec![
                Event::PhotoChanged {
                    photo: "b".to_owned(),
                    steps: 2,
                    cursor: 1
                },
                Event::PhotoChanged {
                    photo: "a".to_owned(),
                    steps: 2,
                    cursor: 1
                },
            ]
        );
    }

    #[test]
    fn failing_calls_dispatch_no_events() {
        let mut engine = atomicity_draft();
        let seen: Rc<RefCell<Vec<Event>>> = Rc::new(RefCell::new(Vec::new()));
        let seen_in = Rc::clone(&seen);
        let listener: Listener = Rc::new(move |event, _| seen_in.borrow_mut().push(event.clone()));
        engine.subscribe(listener);
        for (id, params_list) in bad_params_cases() {
            for params in &params_list {
                engine.execute(id, params).expect_err("must fail");
            }
        }
        assert_eq!(seen.borrow().len(), 0);
    }

    #[test]
    fn every_listener_gets_every_event_once_until_unsubscribed() {
        let mut engine = Engine::open_draft(["a"]);
        let first: Rc<RefCell<Vec<Event>>> = Rc::new(RefCell::new(Vec::new()));
        let second: Rc<RefCell<Vec<Event>>> = Rc::new(RefCell::new(Vec::new()));
        let first_in = Rc::clone(&first);
        let second_in = Rc::clone(&second);
        engine.subscribe(Rc::new(move |event, _| {
            first_in.borrow_mut().push(event.clone());
        }));
        let drop_me = engine.subscribe(Rc::new(move |event, _| {
            second_in.borrow_mut().push(event.clone());
        }));
        engine
            .execute("develop.copy", &json!({"id": "a"}))
            .expect("copy");
        assert_eq!(first.borrow().clone(), vec![Event::ClipboardChanged]);
        assert_eq!(second.borrow().clone(), vec![Event::ClipboardChanged]);
        assert!(engine.unsubscribe(drop_me));
        assert!(!engine.unsubscribe(drop_me));
        engine
            .execute("develop.copy", &json!({"id": "a"}))
            .expect("copy again");
        assert_eq!(first.borrow().len(), 2);
        assert_eq!(
            second.borrow().len(),
            1,
            "unsubscribed listener hears nothing more"
        );
    }

    #[test]
    fn digest_is_stable_for_same_ops_and_moves_on_change() {
        let replay = || {
            let mut engine = Engine::open_draft(["a"]);
            engine.set_param_lookup(|_| Some(ParamsDesc::unset()));
            let patch = json!({"p": {"type": "float", "value": 1.0}});
            engine
                .execute(
                    "develop.set",
                    &json!({"ids": ["a"], "module": "mod_a", "patch": patch}),
                )
                .expect("set");
            engine
                .execute("develop.copy", &json!({"id": "a"}))
                .expect("copy");
            engine.state_digest()
        };
        assert_eq!(replay(), replay());
        let mut engine = Engine::open_draft(["a"]);
        engine.set_param_lookup(|_| Some(ParamsDesc::unset()));
        let calm = engine.state_digest();
        engine
            .execute("develop.reset", &json!({"ids": ["a"]}))
            .expect("reset");
        assert_ne!(engine.state_digest(), calm);
        assert_eq!(
            engine.state_digest_decimal(),
            engine.state_digest().to_string()
        );
    }

    #[test]
    fn process_update_moves_an_outdated_photo_and_labels_the_step() {
        let mut engine = Engine::open_draft(["a"]);
        // Seed an outdated photo straight into the stack (unit tests in this
        // module see the private state): process 0 predates V1.
        let stack = engine.state.photos.get_mut("a").expect("seed stack");
        let settings = PhotoSettings {
            process: ProcessVersion(0),
            ..PhotoSettings::default()
        };
        assert!(settings.process.is_outdated());
        stack.commit("seed", Arc::new(settings));
        let out = engine
            .execute("process.update", &json!({"ids": ["a"]}))
            .expect("update");
        assert_eq!(out, json!({"updated": 1}));
        assert_eq!(
            engine.photo_labels("a").expect("labels").last(),
            Some(&"process.update".to_owned())
        );
        assert_eq!(
            engine.photo_settings("a").expect("snapshot").process,
            ProcessVersion::LATEST
        );
    }

    /// Drains the queue until `ready` holds or the bound gives out.
    fn collect_until(engine: &mut Engine, ready: impl Fn(&Engine) -> bool) {
        for _ in 0..5_000 {
            engine.collect();
            if ready(engine) {
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
    }

    #[test]
    fn synthetic_job_reports_start_progress_and_successful_finish() {
        let mut engine = Engine::open_draft(["a"]);
        let seen: Rc<RefCell<Vec<Event>>> = Rc::new(RefCell::new(Vec::new()));
        let seen_in = Rc::clone(&seen);
        engine.subscribe(Rc::new(move |event, _| {
            seen_in.borrow_mut().push(event.clone());
        }));
        let total: Arc<std::sync::Mutex<u64>> = Arc::new(std::sync::Mutex::new(0));
        let total_in = Arc::clone(&total);
        let id = engine.spawn_job("sum", "synthetic sum".to_owned(), 4, move |ctx| {
            for chunk in 1..=4 {
                if ctx.is_cancelled() {
                    return;
                }
                *total_in
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner) += chunk;
                ctx.report(chunk);
            }
        });
        assert_eq!(id, 1);
        collect_until(&mut engine, |engine| {
            matches!(
                engine.job(id).map(|info| info.status),
                Some(JobStatus::Finished { .. })
            )
        });
        assert_eq!(
            *total
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner),
            10
        );
        assert_eq!(
            seen.borrow().clone(),
            vec![
                Event::JobStarted { job: id },
                Event::JobProgress {
                    job: id,
                    done: 1,
                    total: 4
                },
                Event::JobProgress {
                    job: id,
                    done: 2,
                    total: 4
                },
                Event::JobProgress {
                    job: id,
                    done: 3,
                    total: 4
                },
                Event::JobProgress {
                    job: id,
                    done: 4,
                    total: 4
                },
                Event::JobFinished {
                    job: id,
                    success: true,
                    cancelled: false
                },
            ]
        );
        let info = engine.job(id).expect("table row");
        assert_eq!(info.kind, "sum");
        assert_eq!(info.done, 4);
        assert!(matches!(
            info.status,
            JobStatus::Finished { cancelled: false }
        ));
    }

    #[test]
    fn job_cancel_stops_at_the_next_chunk_and_reports_cancelled() {
        let mut engine = Engine::open_draft(["a"]);
        let (release_tx, release_rx) = std::sync::mpsc::channel::<()>();
        let id = engine.spawn_job("gated", "gated work".to_owned(), 2, move |ctx| {
            ctx.report(1);
            let _ = release_rx.recv();
            if ctx.is_cancelled() {
                return;
            }
            ctx.report(2);
        });
        collect_until(&mut engine, |engine| {
            engine.job(id).is_some_and(|info| info.done == 1)
        });
        let out = engine
            .execute("job.cancel", &json!({"job": id}))
            .expect("cancel runs");
        assert_eq!(out, json!({"cancelled": id}));
        release_tx.send(()).unwrap_or(());
        collect_until(&mut engine, |engine| {
            matches!(
                engine.job(id).map(|info| info.status),
                Some(JobStatus::Finished { cancelled: true })
            )
        });
        let info = engine.job(id).expect("table row");
        assert!(
            matches!(info.status, JobStatus::Finished { cancelled: true }),
            "{:?}",
            info.status
        );
    }

    #[test]
    fn job_cancel_refuses_an_empty_table_and_an_unknown_job() {
        let mut engine = Engine::open_draft(["a"]);
        let err = engine
            .execute("job.cancel", &json!({"job": 1}))
            .expect_err("empty table");
        assert!(matches!(err, CommandError::Disabled { .. }), "{err}");
        engine.spawn_job("noop", "noop".to_owned(), 0, |_| {});
        let err = engine
            .execute("job.cancel", &json!({"job": 99}))
            .expect_err("unknown job");
        assert!(matches!(err, CommandError::JobNotFound { .. }), "{err}");
    }

    #[test]
    fn panicking_job_fails_without_hurting_the_pool() {
        let mut engine = Engine::open_draft(["a"]);
        let id = engine.spawn_job("boom", "panicking work".to_owned(), 0, |ctx| {
            // A runtime-computed overrun (the lint-clean way to panic here).
            let values = [1_u64];
            let overrun = ctx.id().to_string().len() + 4;
            let _ = values[overrun];
        });
        collect_until(&mut engine, |engine| {
            matches!(
                engine.job(id).map(|info| info.status),
                Some(JobStatus::Failed(_))
            )
        });
        let info = engine.job(id).expect("table row");
        assert!(
            matches!(info.status, JobStatus::Failed(_)),
            "{:?}",
            info.status
        );
        // The pool survives: a later job still runs to completion.
        let done = Arc::new(AtomicBool::new(false));
        let done_in = Arc::clone(&done);
        let next = engine.spawn_job("after", "aftermath".to_owned(), 0, move |_| {
            done_in.store(true, Ordering::SeqCst);
        });
        collect_until(&mut engine, |_| done.load(Ordering::SeqCst));
        assert!(matches!(
            engine.job(next).map(|info| info.status),
            Some(JobStatus::Finished { .. })
        ));
    }

    #[test]
    fn dropping_the_engine_stops_jobs_and_joins_workers() {
        let mut engine = Engine::open_draft(["a"]);
        engine.spawn_job("long", "cooperative loop".to_owned(), 200, |ctx| {
            for _ in 0..200 {
                if ctx.is_cancelled() {
                    return;
                }
                std::thread::sleep(std::time::Duration::from_millis(1));
            }
        });
        drop(engine);
        // Returning here proves the join: `Drop` blocks until the flagged
        // job observes the cancel and the workers exit.
    }
}
