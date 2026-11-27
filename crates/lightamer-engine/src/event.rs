// SPDX-License-Identifier: GPL-3.0-or-later
//! State-change notifications, delivered after a command commits.
//!
//! An [`Event`] never carries a decision: it reports what already happened.
//! Commands collect events while they run and the engine dispatches them once,
//! in order, after the state change is committed. A failed command dispatches
//! nothing.

use std::rc::Rc;

use crate::engine::Engine;

/// Something that already happened in the engine.
///
/// Every variant is a plain snapshot fact; listeners use the engine's
/// snapshot accessors for anything more.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Event {
    /// A photo's settings or history changed.
    PhotoChanged {
        /// The photo id.
        photo: String,
        /// How many history steps the photo holds now.
        steps: usize,
        /// The cursor position now.
        cursor: usize,
    },
    /// The clipboard now holds different adjustments (or was filled).
    ClipboardChanged,
    /// A worker picked up a job.
    JobStarted {
        /// The job id.
        job: u64,
    },
    /// A job reported progress.
    JobProgress {
        /// The job id.
        job: u64,
        /// Units done so far.
        done: u64,
        /// Units in total (0 while unknown).
        total: u64,
    },
    /// A job reached a terminal state.
    JobFinished {
        /// The job id.
        job: u64,
        /// Whether the job's work ran to completion (false on panic).
        success: bool,
        /// Whether a cancel was observed (only meaningful with success).
        cancelled: bool,
    },
    /// The latest generation of one (photo, kind) pair finished rendering.
    RenderReady {
        /// The photo id.
        photo: String,
        /// The pipe kind word (`full`, `export`, `preview`, `thumbnail`).
        kind: String,
        /// The generation that finished.
        generation: u64,
    },
    /// The latest generation of one (photo, kind) pair failed (cancelled
    /// generations emit nothing; see the render module).
    RenderFailed {
        /// The photo id.
        photo: String,
        /// The pipe kind word (`full`, `export`, `preview`, `thumbnail`).
        kind: String,
        /// The generation that failed.
        generation: u64,
        /// One human-readable line saying why.
        reason: String,
    },
}

/// An event listener: called once per event, in subscription order.
///
/// The engine is passed for snapshot reads only. Calling
/// [`Engine::execute`] from a listener fails with
/// [`CommandError::Reentrant`][crate::CommandError::Reentrant]: dispatch
/// happens inside the command that produced the events, and nested commands
/// are not allowed. Subscribing or unsubscribing from a listener is safe; the
/// change applies to the next dispatch.
pub type Listener = Rc<dyn Fn(&Event, &mut Engine)>;

/// Subscription handle from [`Engine::subscribe`].
pub type ListenerId = u64;
