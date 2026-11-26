// SPDX-License-Identifier: GPL-3.0-or-later
// Derived from lightcraft crates/engine/src/activity.rs (commit 0da998f2) — reworked:
// the Activity registry (TaskGuard/Handle/Unit/detail strings) is replaced by a small
// fixed-size thread pool with a FIFO queue: LightCraft spreads work over per-area
// workers, while this engine funnels every background job through one pool so the
// job table, cancel flags, and progress/completion events have a single owner.
// Cancel stays flag-based (checked between chunks); progress and completion cross
// back to the engine thread through one results queue drained by `collect`.
//! Background jobs: a fixed pool, a readable table, cancel flags.
//!
//! Commands do bounded work only. Anything unbounded (copies, scans, decodes,
//! renders, encodes, backups, network waits) starts as a job: the work runs
//! on a pool thread against an immutable snapshot it captured, progress and
//! completion land in a results queue, and [`Engine::collect`][crate::Engine::collect]
//! turns the queue into [`Event`]s on the engine thread.
//!
//! This wave registers no command that starts a job (there is no real
//! background work yet); the pool, the table, and `job.cancel` ship now so
//! B1 (render) and B15 (thumbnails) build on them directly.

use std::collections::BTreeMap;
use std::panic::AssertUnwindSafe;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{Receiver, Sender, channel};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;

use serde_json::{Map, Value, json};

use crate::command::{CommandSpec, Outcome, ParamKind, ParamSpec, RunCtx, uint_req};
use crate::engine::Engine;
use crate::error::CommandError;
use crate::event::Event;

/// Worker threads in the pool: four keeps a render, a thumbnail batch, an
/// export, and one spare in flight without oversubscribing a laptop.
pub const POOL_SIZE: usize = 4;

/// Job-table id, minted 1, 2, … per engine.
pub type JobId = u64;

/// Where one job stands. Terminal states stay in the table so frontends and
/// tests can read how a job ended.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum JobStatus {
    /// Accepted, waiting for a worker.
    Queued,
    /// A worker picked it up.
    Running,
    /// The work returned; `cancelled` says a cancel was observed.
    Finished {
        /// Whether the job saw its cancel flag before returning.
        cancelled: bool,
    },
    /// The work panicked; the pool survives. Holds the panic payload text.
    Failed(String),
}

impl JobStatus {
    /// Whether the job reached a terminal state.
    #[must_use]
    pub const fn is_terminal(&self) -> bool {
        match self {
            JobStatus::Queued | JobStatus::Running => false,
            JobStatus::Finished { .. } | JobStatus::Failed(_) => true,
        }
    }
}

/// One job row as readers see it.
#[derive(Clone, Debug)]
pub struct JobInfo {
    /// The job id.
    pub id: JobId,
    /// A stable kind (`render`, `thumbs`, …), chosen by the spawner.
    pub kind: String,
    /// English label; the frontend translates it.
    pub label: String,
    /// Where the job stands.
    pub status: JobStatus,
    /// Units done so far.
    pub done: u64,
    /// Units in total (0 while unknown).
    pub total: u64,
}

/// What a running job sees: its id, its cancel flag, and a progress sender.
///
/// The work closure captures whatever immutable snapshot it needs; it never
/// touches the engine. Between chunks it checks [`JobCtx::is_cancelled`] and
/// reports with [`JobCtx::report`]; both are lock-free and never block.
pub struct JobCtx {
    id: JobId,
    cancel: Arc<AtomicBool>,
    results: Sender<JobMsg>,
}

impl JobCtx {
    /// The running job's id.
    #[must_use]
    pub const fn id(&self) -> JobId {
        self.id
    }

    /// Whether someone asked this job to stop. Check between chunks.
    #[must_use]
    pub fn is_cancelled(&self) -> bool {
        self.cancel.load(Ordering::SeqCst)
    }

    /// Reports `done` units. Delivery is asynchronous via [`Engine::collect`].
    pub fn report(&self, done: u64) {
        let _ = self.results.send(JobMsg {
            id: self.id,
            body: MsgBody::Progress { done },
        });
    }
}

/// One queued unit of background work.
pub(crate) struct Task {
    pub(crate) id: JobId,
    pub(crate) cancel: Arc<AtomicBool>,
    pub(crate) work: Box<dyn FnOnce(&JobCtx) + Send>,
}

/// One worker-to-engine message.
pub(crate) struct JobMsg {
    id: JobId,
    body: MsgBody,
}

pub(crate) enum MsgBody {
    Started,
    Progress { done: u64 },
    Finished { cancelled: bool },
    Failed { reason: String },
}

/// The fixed-size pool. Dropping it stops the workers: queued tasks are
/// skipped (the engine is going away, so there is no one to report to) and
/// running tasks — whose cancel flags the engine sets first — are joined, so
/// no worker thread outlives the engine.
pub(crate) struct JobPool {
    tasks: Option<Sender<Task>>,
    shutdown: Arc<AtomicBool>,
    workers: Vec<Option<JoinHandle<()>>>,
}

impl JobPool {
    /// Starts [`POOL_SIZE`] workers reporting to `results`.
    pub(crate) fn new(results: &Sender<JobMsg>) -> Self {
        let (tx, rx) = channel::<Task>();
        let rx = Arc::new(Mutex::new(rx));
        let shutdown = Arc::new(AtomicBool::new(false));
        let mut workers = Vec::with_capacity(POOL_SIZE);
        for index in 0..POOL_SIZE {
            let rx = Arc::clone(&rx);
            let results = results.clone();
            let shutdown = Arc::clone(&shutdown);
            let name = format!("lightamer-engine-job-{index}");
            // A spawn failure degrades the pool instead of failing
            // construction: thread spawn only fails when the OS refuses, and
            // a smaller pool still drains every job. The slot stays `None`
            // and `Drop` skips it.
            let spawned = std::thread::Builder::new()
                .name(name)
                .spawn(move || worker_loop(&rx, &results, &shutdown));
            workers.push(spawned.ok());
        }
        Self {
            tasks: Some(tx),
            shutdown,
            workers,
        }
    }

    /// Queues one task for the next free worker (FIFO).
    pub(crate) fn submit(&self, task: Task) {
        if let Some(tx) = self.tasks.as_ref() {
            let _ = tx.send(task);
        }
    }
}

impl Drop for JobPool {
    fn drop(&mut self) {
        self.shutdown.store(true, Ordering::SeqCst);
        drop(self.tasks.take());
        for worker in &mut self.workers {
            if let Some(handle) = worker.take() {
                let _ = handle.join();
            }
        }
    }
}

/// One worker: take tasks FIFO, skip them once the engine is going away,
/// else run with cancel-before-start and panic capture.
fn worker_loop(
    rx: &Arc<Mutex<Receiver<Task>>>,
    results: &Sender<JobMsg>,
    shutdown: &Arc<AtomicBool>,
) {
    loop {
        let task = {
            let guard = rx.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            guard.recv()
        };
        let Ok(task) = task else {
            return;
        };
        if shutdown.load(Ordering::SeqCst) {
            continue;
        }
        if task.cancel.load(Ordering::SeqCst) {
            let _ = results.send(JobMsg {
                id: task.id,
                body: MsgBody::Finished { cancelled: true },
            });
            continue;
        }
        let ctx = JobCtx {
            id: task.id,
            cancel: Arc::clone(&task.cancel),
            results: results.clone(),
        };
        let _ = results.send(JobMsg {
            id: task.id,
            body: MsgBody::Started,
        });
        let outcome = std::panic::catch_unwind(AssertUnwindSafe(|| (task.work)(&ctx)));
        match outcome {
            Ok(()) => {
                let _ = results.send(JobMsg {
                    id: task.id,
                    body: MsgBody::Finished {
                        cancelled: ctx.is_cancelled(),
                    },
                });
            }
            Err(payload) => {
                let _ = results.send(JobMsg {
                    id: task.id,
                    body: MsgBody::Failed {
                        reason: panic_text(&payload),
                    },
                });
            }
        }
    }
}

/// Best-effort text of a panic payload (`&str` / `String`, else a placeholder).
fn panic_text(payload: &Box<dyn std::any::Any + Send>) -> String {
    if let Some(text) = payload.downcast_ref::<&str>() {
        (*text).to_owned()
    } else if let Some(text) = payload.downcast_ref::<String>() {
        text.clone()
    } else {
        "job panicked".to_owned()
    }
}

/// One table row: the readable info plus the live cancel flag.
struct JobEntry {
    info: JobInfo,
    cancel: Arc<AtomicBool>,
}

/// The job table: rows plus the results receiver drained by `collect`.
pub(crate) struct JobTable {
    next: JobId,
    entries: BTreeMap<JobId, JobEntry>,
    results: Receiver<JobMsg>,
}

impl JobTable {
    pub(crate) fn new(results: Receiver<JobMsg>) -> Self {
        Self {
            next: 1,
            entries: BTreeMap::new(),
            results,
        }
    }

    /// Inserts a queued row and returns its id and cancel flag.
    pub(crate) fn insert(
        &mut self,
        kind: &str,
        label: String,
        total: u64,
    ) -> (JobId, Arc<AtomicBool>) {
        let id = self.next;
        self.next = self.next.wrapping_add(1);
        let cancel = Arc::new(AtomicBool::new(false));
        self.entries.insert(
            id,
            JobEntry {
                info: JobInfo {
                    id,
                    kind: kind.to_owned(),
                    label,
                    status: JobStatus::Queued,
                    done: 0,
                    total,
                },
                cancel: Arc::clone(&cancel),
            },
        );
        (id, cancel)
    }

    pub(crate) fn cancel_flag(&self, id: JobId) -> Option<Arc<AtomicBool>> {
        self.entries.get(&id).map(|entry| Arc::clone(&entry.cancel))
    }

    /// Sets every unfinished job's cancel flag (engine shutdown path).
    pub(crate) fn cancel_all_unfinished(&self) {
        for entry in self.entries.values() {
            if !entry.info.status.is_terminal() {
                entry.cancel.store(true, Ordering::SeqCst);
            }
        }
    }

    /// Applies one worker message; returns the event to dispatch, if any.
    fn apply(&mut self, msg: JobMsg) -> Option<Event> {
        let entry = self.entries.get_mut(&msg.id)?;
        match msg.body {
            MsgBody::Started => {
                entry.info.status = JobStatus::Running;
                Some(Event::JobStarted { job: msg.id })
            }
            MsgBody::Progress { done } => {
                entry.info.done = done;
                Some(Event::JobProgress {
                    job: msg.id,
                    done,
                    total: entry.info.total,
                })
            }
            MsgBody::Finished { cancelled } => {
                entry.info.status = JobStatus::Finished { cancelled };
                Some(Event::JobFinished {
                    job: msg.id,
                    success: true,
                    cancelled,
                })
            }
            MsgBody::Failed { reason } => {
                entry.info.status = JobStatus::Failed(reason);
                Some(Event::JobFinished {
                    job: msg.id,
                    success: false,
                    cancelled: false,
                })
            }
        }
    }

    /// Drains every pending message, newest table state wins.
    pub(crate) fn drain(&mut self) -> Vec<Event> {
        let mut events = Vec::new();
        while let Ok(msg) = self.results.try_recv() {
            if let Some(event) = self.apply(msg) {
                events.push(event);
            }
        }
        events
    }

    pub(crate) fn infos(&self) -> Vec<JobInfo> {
        self.entries
            .values()
            .map(|entry| entry.info.clone())
            .collect()
    }

    pub(crate) fn info(&self, id: JobId) -> Option<JobInfo> {
        self.entries.get(&id).map(|entry| entry.info.clone())
    }
}

/// The `job.*` specs: only `job.cancel` this wave (no command starts a job
/// yet; spawning is engine API covered by tests).
pub(crate) static SPECS: &[CommandSpec] = &[CommandSpec {
    id: "job.cancel",
    summary: "Asks a background job to stop at its next chunk boundary.",
    params: &[ParamSpec {
        name: "job",
        kind: ParamKind::Integer,
        required: true,
        doc: "The job id from the job table.",
    }],
    needs_session: true,
    enabled: has_jobs,
    run: run_cancel,
}];

/// Refuses while the job table is empty: with no jobs, no id can resolve.
///
/// # Errors
///
/// The human-readable reason when the table holds no jobs.
pub fn has_jobs(engine: &Engine) -> Result<(), String> {
    if engine.jobs().is_empty() {
        Err("no jobs in the table".to_owned())
    } else {
        Ok(())
    }
}
/// Cancels one job: sets its flag; the worker observes it between chunks and
/// the completion event reports `cancelled`. Cancelling a finished job is a
/// no-op success.
fn run_cancel(
    engine: &mut Engine,
    params: &Map<String, Value>,
    _ctx: &mut RunCtx,
) -> Result<Outcome, CommandError> {
    const CMD: &str = "job.cancel";
    let id = uint_req(CMD, params, "job")?;
    let Some(flag) = engine.job_cancel_flag(id) else {
        return Err(CommandError::JobNotFound {
            cmd: CMD.to_owned(),
            job: id,
        });
    };
    flag.store(true, Ordering::SeqCst);
    Ok(json!({"cancelled": id}))
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::POOL_SIZE;

    #[test]
    fn pool_size_is_the_documented_four() {
        assert_eq!(POOL_SIZE, 4);
    }
}
