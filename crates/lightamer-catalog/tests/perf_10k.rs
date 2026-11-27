// SPDX-License-Identifier: GPL-3.0-or-later
//! Timing bench (ignored by default): paste one step onto 10,000 photos in
//! a single transaction, reporting the three phase totals plus the whole
//! transaction, for both synchronous modes, median of three runs.
//!
//! Run alone on a quiet machine:
//! `cargo test -p lightamer-catalog --locked --test perf_10k -- --ignored --nocapture`

mod common;

use std::time::{Duration, Instant};

use lightamer_catalog::{
    HistoryWriter, PushRequest, close_session, create_session, register_photo,
};
use lightamer_history::PhotoSettings;

use common::{ScratchDir, settings_json};

/// Photos per run (one pasted step each, one transaction).
const PHOTOS: i64 = 10_000;
/// Runs per synchronous mode (the report takes the median).
const RUNS: i32 = 3;

/// One measured run: the writer's phase totals plus the whole transaction.
struct Run {
    snapshot: Duration,
    steps: Duration,
    photos: Duration,
    total: Duration,
}

#[test]
#[ignore = "timing bench: run alone on a quiet machine"]
fn bench_paste_10k_reports_phases_for_both_sync_modes() -> Result<(), Box<dyn std::error::Error>> {
    if load_busy()? {
        println!("perf: UNRELIABLE (machine busy) SKIP");
        return Ok(());
    }
    for mode in ["NORMAL", "FULL"] {
        let mut runs = Vec::new();
        for run in 1..=RUNS {
            let measured = paste_10k_once(&format!("perf-{mode}-{run}"), mode)?;
            println!(
                "perf: sync={mode} run={run} snapshot={} steps={} photos={} total={}",
                millis(measured.snapshot),
                millis(measured.steps),
                millis(measured.photos),
                millis(measured.total),
            );
            runs.push(measured);
        }
        let (snapshot, steps, photos, total) = medians(&runs)?;
        println!(
            "perf: sync={mode} median snapshot={} steps={} photos={} total={}",
            millis(snapshot),
            millis(steps),
            millis(photos),
            millis(total),
        );
    }
    Ok(())
}

/// Registers 10,000 photos over empty placeholders (setup, unmeasured),
/// then pushes one pasted step onto each in a single transaction and times it.
fn paste_10k_once(tag: &str, synchronous: &str) -> Result<Run, Box<dyn std::error::Error>> {
    let scratch = ScratchDir::new(tag)?;
    let mut session = create_session(scratch.path(), "Shoot", "perf-test")?;
    let root = session.root().to_path_buf();
    for number in 1..=PHOTOS {
        let name = format!("img-{number:05}.arw");
        let path = root.join("Capture").join(&name);
        std::fs::write(&path, [])?;
        register_photo(session.connection_mut(), &root, &path, &name, Some(0))?;
    }
    session
        .connection_mut()
        .pragma_update(None, "synchronous", synchronous)?;
    let level: i64 = session
        .connection()
        .query_row("PRAGMA synchronous", [], |row| row.get(0))?;
    assert_eq!(level, if synchronous == "FULL" { 2 } else { 1 });

    let json = settings_json("exposure", "ev", 1)?;
    let key = PhotoSettings::from_json(&json)?.hash64_decimal();
    let items = (1..=PHOTOS)
        .map(|id| PushRequest {
            photo_id: id,
            label: "develop.paste",
            canonical_json: json.as_str(),
        })
        .collect::<Vec<_>>();
    let mut writer = HistoryWriter::begin(session.connection_mut())?;
    let start = Instant::now();
    let outcomes = writer.push_many(&items)?;
    assert_eq!(outcomes.len(), 10_000);
    let stats = *writer.stats();
    let hits = writer.snapshot_cache_hits();
    let skips = writer.redo_delete_skips();
    writer.commit()?;
    let total = start.elapsed();
    assert_eq!(stats.pushes, 10_000);
    assert_eq!(hits, 9_999);
    assert_eq!(skips, 10_000);

    let landed: i64 = session.connection().query_row(
        "SELECT COUNT(*) FROM photos WHERE cursor = 1 AND current_hash = ?1",
        [&key],
        |row| row.get(0),
    )?;
    assert_eq!(landed, PHOTOS);
    close_session(session)?;
    Ok(Run {
        snapshot: stats.snapshot,
        steps: stats.steps,
        photos: stats.photos,
        total,
    })
}

/// Medians of the three runs, per field.
fn medians(
    runs: &[Run],
) -> Result<(Duration, Duration, Duration, Duration), Box<dyn std::error::Error>> {
    let pick = |field: fn(&Run) -> Duration| -> Result<Duration, Box<dyn std::error::Error>> {
        let mut values: Vec<Duration> = runs.iter().map(field).collect();
        values.sort();
        values
            .get(1)
            .copied()
            .ok_or_else(|| "expected three runs".into())
    };
    Ok((
        pick(|run| run.snapshot)?,
        pick(|run| run.steps)?,
        pick(|run| run.photos)?,
        pick(|run| run.total)?,
    ))
}

/// True when the machine is too busy to time (the `rust-budget.sh`
/// `load_busy` rule: 1-minute load over cores above 1.0). Unparseable
/// load output counts as quiet but is printed.
fn load_busy() -> Result<bool, Box<dyn std::error::Error>> {
    let output = std::process::Command::new("uptime").output()?;
    let text = String::from_utf8_lossy(&output.stdout).into_owned();
    let load = parse_load1(&text);
    let cpus = std::thread::available_parallelism().map_or(4, std::num::NonZero::get);
    let cpus = f64::from(u32::try_from(cpus)?);
    println!("perf: load: {text} cpus={cpus}");
    Ok(load.is_some_and(|load| load / cpus > 1.0))
}

/// The 1-minute load average from `uptime` output (macOS `load averages:`
/// or Linux `load average:`), if it parses.
fn parse_load1(text: &str) -> Option<f64> {
    let marker = if text.contains("load averages:") {
        "load averages:"
    } else {
        "load average:"
    };
    let (_, tail) = text.split_once(marker)?;
    let first = tail.split_whitespace().next()?;
    first.trim_end_matches(',').parse().ok()
}

/// A duration as `123.4ms`.
fn millis(span: Duration) -> String {
    format!("{:.1}ms", span.as_secs_f64() * 1000.0)
}
