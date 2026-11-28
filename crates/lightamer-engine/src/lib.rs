// SPDX-License-Identifier: GPL-3.0-or-later
//! The command engine: every frontend's single entry point.
//!
//! `lightamer-engine` owns the "everything is a command" dispatch: the UI, the CLI,
//! and a future MCP all change state through [`Engine::execute`]. Reads bypass
//! it through cheap snapshot accessors; notifications arrive as [`Event`]s.
//!
//! # The `execute` contract
//!
//! * **Atomic.** A call either fully applies or changes nothing. Drafts (and
//!   session/job commands) hold this by cloning the synchronous state (every
//!   photo's settings, history, cursor, and process version, plus the
//!   clipboard) before the run function and restoring it whole on any error.
//!   Persisted commands on a real session hold it by computing the new state
//!   first, committing one store transaction, then swapping in state that
//!   cannot fail. [`Engine::state_digest`] hashes that state plus the job
//!   table for tests and the CLI.
//! * **Typed errors.** Every failure is one [`CommandError`] variant with a
//!   human-readable line: unknown command, unknown or missing parameter, bad
//!   value, refused enablement, no session, no photo, no interaction, empty
//!   clipboard, unknown job, reentrant call.
//! * **Bounded work only.** A command finishes quickly: this wave touches
//!   memory only, and from B13' a command may additionally carry at most one
//!   bounded write (one small transaction). Unbounded work — copies, folder
//!   scans, decodes, renders, encodes, whole-package backups, network waits —
//!   never runs inside a command; a command starts it as a job (see below).
//! * **One step per photo.** A command that edits history commits exactly one
//!   step per photo it touches, labelled with the command id.
//! * **No running while disabled.** Each declaration carries an enablement
//!   check (e.g. a session must be open); a refusal fails the call before
//!   anything else happens.
//! * **No reentrancy.** Dispatch happens inside the producing call, so an
//!   event listener that calls `execute` gets [`CommandError::Reentrant`]
//!   instead of a nested execution.
//!
//! A fresh engine has no session and every mutating command refuses to run.
//! [`Engine::open_draft`] opens a draft session — a set of photo ids held in
//! memory with nothing persisted — for headless tests, the CLI, and future
//! MCP demos. `session.new`, `session.open`, and `session.restore` open real
//! sessions instead (the store's lock plus its connection); the draft
//! constructor stays for tests.
//!
//! # Adding a command
//!
//! 1. Append a [`CommandSpec`] to the owning area's `SPECS` array
//!    (`develop`, `history`, `jobs`, or `session`): a stable id, a one-line
//!    [`ParamSpec`] list, an enablement check, and the run function.
//! 2. Validate everything up front in the run function (all photos first,
//!    then mutate), commit one step per photo labelled with the command id,
//!    and queue change events on the [`command::RunCtx`].
//! 3. Add tests: the happy path, each error the command can return, the
//!    atomicity row (state and digest unchanged on error), and the events the
//!    call emits. Never register a command the engine cannot run yet — an
//!    "unimplemented" command is a lie the registry must not tell.
//!
//! What stays out of a declaration: menu placement, shortcuts (UI-layer data),
//! and journal/replay flags (not needed here).
//!
//! # Jobs
//!
//! [`Engine::spawn_job`] queues work on a fixed pool of [`POOL_SIZE`] threads
//! (FIFO). The work sees an immutable snapshot it captured plus a [`JobCtx`]
//! (cancel flag, progress sender); it never touches the engine. Progress and
//! completion land in a results queue that [`Engine::collect`] drains into
//! the job table and dispatches as events — engine thread only. [`JobInfo`]
//! rows (id, kind, label, status, progress) stay readable after completion.
//! `job.cancel` sets a job's flag; the worker observes it between chunks and
//! the completion event reports `cancelled`. Dropping the engine asks every
//! unfinished job to stop and joins the workers, so no thread outlives it.
//!
//! # Events and snapshots
//!
//! Commands queue [`Event`]s while they run; the engine dispatches them once,
//! in order, after the call commits — and dispatches none when the call
//! fails. Listeners ([`Engine::subscribe`]) receive each event exactly once
//! and may read snapshots but must not call `execute`. Snapshots
//! ([`Engine::photo_settings`], [`Engine::jobs`], …) are cheap clones a UI
//! can take every frame.
//!
//! # What this crate never does
//!
//! No files, no network, no threads outside the job pool, no module names:
//! commands resolve module ids through the registry at runtime, and the
//! `check-no-iop-names` task fails the build if a baseline module id ever
//! appears in these sources, tests included.
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

pub mod command;
mod develop;
pub mod engine;
pub mod error;
pub mod event;
mod history;
pub mod jobs;
mod real;
mod render;
mod session;

pub use command::{CommandSpec, Outcome, ParamKind, ParamSpec, command_specs, find_command};
pub use engine::{CommandPhases, Engine};
pub use error::CommandError;
pub use event::{Event, Listener, ListenerId};
pub use jobs::{JobCtx, JobId, JobInfo, JobStatus, POOL_SIZE};
pub use render::{
    DEFAULT_KEPT_BYTE_LIMIT, DEFAULT_SPILL_BYTE_LIMIT, DEFAULT_SPILL_MEMORY_THRESHOLD,
    EngineConfig, InputError, InputSource, ModuleSource, RenderFacts, RenderInput, RenderKind,
    RenderRecord, RenderedImage, RenderedStore, SKIP_DISABLED, SKIP_UNKNOWN_MODULE,
    SharedInputSource, SharedModuleSource, SkippedModule, StreamMode, StreamReport,
};

#[cfg(test)]
mod tests {
    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }
}
