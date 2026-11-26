// SPDX-License-Identifier: GPL-3.0-or-later
//! `bench`: developer timing tools, not import commands.
//!
//! `bench setup` builds a session holding `N` empty placeholder photos so
//! `bench paste` can time one paste across thousands of targets. Real import
//! is B15's `library.import`; these tools only plant empty files and rows.

use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::{Duration, Instant};

use lightamer_engine::{Engine, Event};
use serde_json::json;

use crate::util::Error;

/// The 10k gate: one paste visible (the command returned, every event
/// delivered) in under a second. Thumbnails are out of the picture.
pub const PASTE_GATE: Duration = Duration::from_secs(1);

/// What `bench setup` built.
#[derive(Debug)]
pub struct SetupReport {
    /// The session root directory.
    pub root: PathBuf,
    /// The session database file.
    pub database: PathBuf,
    /// How many placeholder photos were registered.
    pub registered: usize,
}

/// Builds a session holding `photos` empty placeholder files (`Capture/`
/// plus one library row each) and closes it again. The session is always
/// closed, even when planting fails halfway.
///
/// # Errors
///
/// Returns [`Error`] when the photo count is zero, the session cannot be
/// created, a placeholder cannot be planted, or the session cannot close.
pub fn bench_setup(parent: &Path, name: &str, photos: usize) -> Result<SetupReport, Error> {
    if photos == 0 {
        return Err(Error::new("bench setup: --photos wants at least 1"));
    }
    let mut session = lightamer_catalog::create_session(parent, name, "lightamer-cli-bench")
        .map_err(|err| Error::new(format!("bench setup: {err}")))?;
    let root = session.root().to_path_buf();
    let plant: Result<usize, Error> = (|| {
        for index in 0..photos {
            let file_name = format!("p{index:05}.arw");
            let abs = root.join("Capture").join(&file_name);
            crate::util::write_file(&abs, b"")?;
            lightamer_catalog::register_photo(
                session.connection_mut(),
                &root,
                &abs,
                &file_name,
                Some(0),
            )
            .map_err(|err| Error::new(format!("bench setup: {err}")))?;
        }
        Ok(photos)
    })();
    let database = session.db_path().to_path_buf();
    lightamer_catalog::close_session(session)
        .map_err(|err| Error::new(format!("bench setup: cannot close: {err}")))?;
    let registered = plant?;
    Ok(SetupReport {
        root,
        database,
        registered,
    })
}

/// What `bench paste` measured (or why it skipped).
#[derive(Debug)]
pub enum PasteReport {
    /// Every round timed, slowest facts first.
    Measured {
        /// Per-round wall time in milliseconds, in run order.
        runs_ms: Vec<f64>,
        /// Median of `runs_ms`.
        median_ms: f64,
        /// `PhotoChanged` events delivered per round (each should equal the
        /// photo count).
        events: Vec<usize>,
        /// Targets per round.
        photos: usize,
        /// Whether the median beat [`PASTE_GATE`] with every event delivered.
        passed: bool,
    },
    /// The machine was busy: measured numbers would be contention, not the
    /// paste. Neither pass nor fail.
    Skipped {
        /// 1-minute load average.
        load_one: f64,
        /// CPU count it was divided by.
        cpus: usize,
    },
}

/// Times pasting one clipboard over `photos` targets, `runs` rounds, each
/// round on fresh targets from the same start (round `r` pastes onto photos
/// `r * photos .. (r + 1) * photos`, so the session must hold at least
/// `runs * photos`). Seeding the source photo and copying it are not timed.
/// Each round runs from the `develop.paste` call to its return, events
/// delivered synchronously inside `execute`.
///
/// # Errors
///
/// Returns [`Error`] when a count is zero, the session cannot open, it
/// holds fewer than `runs * photos` photos, seeding fails, or a round
/// fails or pastes a short count.
pub fn bench_paste(session_path: &Path, photos: usize, runs: usize) -> Result<PasteReport, Error> {
    if photos == 0 {
        return Err(Error::new("bench paste: --photos wants at least 1"));
    }
    if runs == 0 {
        return Err(Error::new("bench paste: --runs wants at least 1"));
    }
    if let Some((load_one, cpus)) = machine_busy() {
        return Ok(PasteReport::Skipped { load_one, cpus });
    }
    let mut engine = Engine::new();
    engine.set_program("lightamer-cli-bench");
    engine
        .execute(
            "session.open",
            &json!({"path": session_path.to_string_lossy()}),
        )
        .map_err(|err| Error::new(format!("bench paste: cannot open session: {err}")))?;
    let ids = engine.photo_ids();
    let need = photos.saturating_mul(runs);
    if ids.len() < need {
        let _ = engine.execute("session.close", &json!({}));
        return Err(Error::new(format!(
            "bench paste: the session holds {} photos, need {need} ({runs} runs x {photos}; run bench setup with --photos {need})",
            ids.len()
        )));
    }
    let Some(source) = ids.first().cloned() else {
        let _ = engine.execute("session.close", &json!({}));
        return Err(Error::new("bench paste: the session holds no photos"));
    };
    // Untimed: one parameter onto the source, then onto the clipboard.
    // Any registered id works (the stubs accept every parameter); the shell
    // reads none, so the bench names the first A7a id outright.
    engine
        .execute(
            "develop.set",
            &json!({"ids": [source], "module": "rawprepare", "patch": {"p_gain": {"type": "float", "value": 1.5}}}),
        )
        .map_err(|err| Error::new(format!("bench paste: cannot seed the source: {err}")))?;
    engine
        .execute("develop.copy", &json!({"id": source}))
        .map_err(|err| Error::new(format!("bench paste: cannot copy: {err}")))?;
    let delivered: Rc<RefCell<usize>> = Rc::new(RefCell::new(0));
    let into = Rc::clone(&delivered);
    engine.subscribe(Rc::new(move |event, _| {
        if matches!(event, Event::PhotoChanged { .. }) {
            *into.borrow_mut() += 1;
        }
    }));
    let want = u64::try_from(photos).unwrap_or(u64::MAX);
    let mut runs_ms = Vec::with_capacity(runs);
    let mut events = Vec::with_capacity(runs);
    for round in 0..runs {
        let start = round.saturating_mul(photos);
        let Some(targets) = ids.get(start..start.saturating_add(photos)) else {
            let _ = engine.execute("session.close", &json!({}));
            return Err(Error::new("bench paste: photo slice out of range"));
        };
        *delivered.borrow_mut() = 0;
        let tick = Instant::now();
        let outcome = engine.execute("develop.paste", &json!({"ids": targets}));
        let elapsed = tick.elapsed();
        let outcome = outcome
            .map_err(|err| Error::new(format!("bench paste: round {} failed: {err}", round + 1)))?;
        if outcome.get("pasted").and_then(serde_json::Value::as_u64) != Some(want) {
            let _ = engine.execute("session.close", &json!({}));
            return Err(Error::new(format!(
                "bench paste: round {} pasted {outcome}",
                round + 1
            )));
        }
        runs_ms.push(elapsed.as_secs_f64() * 1000.0);
        events.push(*delivered.borrow());
    }
    engine
        .execute("session.close", &json!({}))
        .map_err(|err| Error::new(format!("bench paste: cannot close: {err}")))?;
    let mut sorted = runs_ms.clone();
    sorted.sort_by(f64::total_cmp);
    let median_ms = sorted.get(sorted.len() / 2).copied().unwrap_or(0.0);
    let passed =
        median_ms < PASTE_GATE.as_secs_f64() * 1000.0 && events.iter().all(|&got| got == photos);
    Ok(PasteReport::Measured {
        runs_ms,
        median_ms,
        events,
        photos,
        passed,
    })
}

/// One `sysctl -n` value, or [`None`] when macOS will not answer.
fn sysctl_value(name: &str) -> Option<String> {
    let out = std::process::Command::new("sysctl")
        .arg("-n")
        .arg(name)
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    String::from_utf8(out.stdout).ok()
}

/// The `Scripts/rust-budget.sh load_busy` rule, minus the machine-guard half
/// (callers run the guard separately): 1-minute load per cpu above 1.0.
/// Returns the load and cpu count when busy; detection failures measure on.
fn machine_busy() -> Option<(f64, usize)> {
    let load_one = sysctl_value("vm.loadavg").and_then(|text| {
        // "{ 2.04 2.31 2.67 }": the second whitespace field is the 1-minute load.
        text.split_whitespace()
            .nth(1)?
            .parse::<f64>()
            .ok()
            .filter(|load| load.is_finite())
    })?;
    let cpus: usize = sysctl_value("hw.ncpu")?.trim().parse::<usize>().ok()?;
    if cpus == 0 {
        return None;
    }
    let per_cpu = load_one / f64::from(u32::try_from(cpus).unwrap_or(u32::MAX));
    if per_cpu > 1.0 {
        Some((load_one, cpus))
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

    use super::{PASTE_GATE, PasteReport, bench_paste, bench_setup};

    /// A fresh empty directory for one test, removed when dropped.
    struct ScratchDir {
        path: std::path::PathBuf,
    }

    impl ScratchDir {
        fn new(tag: &str) -> Self {
            let path = std::env::temp_dir()
                .join(format!("lightamer-cli-test-{}-{tag}", std::process::id()));
            let _ = std::fs::remove_dir_all(&path);
            std::fs::create_dir_all(&path).expect("scratch");
            Self { path }
        }
    }

    impl Drop for ScratchDir {
        fn drop(&mut self) {
            let ours = self
                .path
                .file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with("lightamer-cli-test-"));
            if ours {
                let _ = std::fs::remove_dir_all(&self.path);
            }
        }
    }

    #[test]
    fn setup_registers_the_count_and_reopens() {
        let scratch = ScratchDir::new("bench-setup");
        let report = bench_setup(scratch.path.as_path(), "Shoot", 7).expect("setup runs");
        assert_eq!(report.registered, 7);
        assert!(report.root.join("Shoot.lmsessiondb").is_file());
        assert_eq!(
            report
                .root
                .join("Capture")
                .read_dir()
                .expect("read dir")
                .count(),
            7
        );
        // The session opens again: setup closed it cleanly.
        let mut engine = lightamer_engine::Engine::new();
        engine
            .execute(
                "session.open",
                &serde_json::json!({"path": report.root.to_string_lossy()}),
            )
            .expect("reopen runs");
        assert_eq!(engine.photo_ids().len(), 7);
        engine
            .execute("session.close", &serde_json::json!({}))
            .expect("close runs");
    }

    #[test]
    fn paste_times_one_hundred_photos_and_counts_events() {
        let scratch = ScratchDir::new("bench-paste-100");
        let setup = bench_setup(scratch.path.as_path(), "Shoot", 100).expect("setup runs");
        let mut measured = false;
        match bench_paste(&setup.root, 100, 1).expect("paste runs") {
            PasteReport::Measured {
                runs_ms,
                median_ms,
                events,
                photos,
                ..
            } => {
                measured = true;
                assert_eq!(photos, 100);
                assert_eq!(runs_ms.len(), 1);
                assert_eq!(events, vec![100]);
                assert!(median_ms > 0.0, "a round takes some time");
                assert!(runs_ms[0] > 0.0, "a round takes some time");
            }
            PasteReport::Skipped { .. } => {}
        }
        assert!(measured, "the test machine was busy; rerun when quiet");
        assert_eq!(PASTE_GATE.as_millis(), 1000);
    }

    #[test]
    fn paste_refuses_a_session_short_of_photos() {
        let scratch = ScratchDir::new("bench-paste-short");
        let setup = bench_setup(scratch.path.as_path(), "Shoot", 5).expect("setup runs");
        let err = bench_paste(&setup.root, 5, 2).expect_err("short session fails");
        assert!(err.to_string().contains("need 10"), "{err}");
    }
}
