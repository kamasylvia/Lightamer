// SPDX-License-Identifier: GPL-3.0-or-later
//! Scratch directories and job draining for the engine integration tests.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use lightamer_engine::Engine;

static NEXT: AtomicU64 = AtomicU64::new(0);

/// A fresh empty directory for one test, removed when dropped (also on
/// test failure: `Drop` runs during unwinding).
pub struct ScratchDir {
    path: PathBuf,
}

impl ScratchDir {
    /// Creates `lightamer-engine-test-<pid>-<n>-<tag>` under the temp dir.
    pub fn new(tag: &str) -> Result<Self, Box<dyn std::error::Error>> {
        let n = NEXT.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "lightamer-engine-test-{}-{n}-{tag}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&path);
        std::fs::create_dir_all(&path)?;
        Ok(Self { path })
    }

    /// The scratch root.
    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for ScratchDir {
    fn drop(&mut self) {
        let ours = self
            .path
            .file_name()
            .and_then(|name| name.to_str())
            .is_some_and(|name| name.starts_with("lightamer-engine-test-"));
        if ours {
            let _ = std::fs::remove_dir_all(&self.path);
        }
    }
}

/// Collects until `ready` holds or 10s pass; the caller asserts afterwards
/// (a timeout surfaces as a failed assertion, not a hang).
pub fn drain_until(engine: &mut Engine, ready: impl Fn(&Engine) -> bool) {
    for _ in 0..10_000 {
        engine.collect();
        if ready(engine) {
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(1));
    }
}

/// Collects until every job in the table is terminal.
pub fn drain_all(engine: &mut Engine) {
    drain_until(engine, |engine| {
        engine.jobs().iter().all(|info| info.status.is_terminal())
    });
}

/// Blocks every pool worker until the returned sender is dropped, so a job
/// spawned meanwhile is deterministically `Queued` (no timing involved).
#[allow(dead_code)] // session_commands links this module without using the gate
pub fn gate_pool(engine: &mut Engine) -> std::sync::mpsc::Sender<()> {
    let (tx, rx) = std::sync::mpsc::channel::<()>();
    let rx = std::sync::Arc::new(std::sync::Mutex::new(rx));
    for _ in 0..lightamer_engine::POOL_SIZE {
        let waiting = std::sync::Arc::clone(&rx);
        engine.spawn_job("test.gate", "pool gate".to_owned(), 0, move |_| {
            let guard = waiting
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let _ = guard.recv();
        });
    }
    tx
}
