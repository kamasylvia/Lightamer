// SPDX-License-Identifier: GPL-3.0-or-later
//! `commands` and `run`: the engine registry through the CLI.
//!
//! `commands` prints the registered commands (id, summary, gates, params).
//! `run` executes a JSONL file — one `{"id", "params"}` call per line —
//! against a draft session, or sessionless when the file names session
//! commands, draining each line's jobs before the next line.

use std::cell::RefCell;
use std::fmt::Write as _;
use std::path::Path;
use std::rc::Rc;
use std::time::{Duration, Instant};

use lightamer_engine::{CommandSpec, Engine, Event, JobStatus, command_specs, find_command};

use crate::util::{Error, read_to_string};

/// Renders one spec against a draft engine (which only feeds the enablement
/// check; the listing itself is static registry data).
fn describe_into(out: &mut String, spec: &CommandSpec, engine: &Engine) {
    let _ = writeln!(out, "{} — {}", spec.id, spec.summary);
    let gate = if spec.needs_session {
        "needs session"
    } else {
        "no session needed"
    };
    let now = match (spec.enabled)(engine) {
        Ok(()) => "enabled now: yes".to_owned(),
        Err(reason) => format!("enabled now: no ({reason})"),
    };
    let _ = writeln!(out, "  {gate}; {now}");
    for param in spec.params {
        let need = if param.required {
            "required"
        } else {
            "optional"
        };
        let _ = writeln!(
            out,
            "  {}: {} ({need}) — {}",
            param.name,
            param.kind.kind_name(),
            param.doc
        );
    }
}

/// The full registry listing: every command with gates and params.
#[must_use]
pub fn describe_all() -> String {
    let engine = Engine::open_draft(Vec::<String>::new());
    let mut out = String::new();
    for spec in command_specs() {
        describe_into(&mut out, spec, &engine);
    }
    out
}

/// One command's listing, or [`None`] for an unregistered id.
#[must_use]
pub fn describe_one(id: &str) -> Option<String> {
    let spec = find_command(id)?;
    let engine = Engine::open_draft(Vec::<String>::new());
    let mut out = String::new();
    describe_into(&mut out, spec, &engine);
    Some(out)
}

/// Collects the photo ids a JSONL file names (`params.id` / `params.ids`,
/// sorted, deduplicated) so `run` can open its draft without a `--photos`
/// flag. Unparseable lines are skipped here; they fail loudly at execution.
#[must_use]
pub fn scan_photo_ids(text: &str) -> Vec<String> {
    let mut ids = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Ok(call) = serde_json::from_str::<serde_json::Value>(line) else {
            continue;
        };
        let params = call.get("params");
        if let Some(id) = params.and_then(|p| p.get("id")).and_then(|v| v.as_str()) {
            push_unique(&mut ids, id);
        }
        if let Some(list) = params.and_then(|p| p.get("ids")).and_then(|v| v.as_array()) {
            for id in list.iter().filter_map(|v| v.as_str()) {
                push_unique(&mut ids, id);
            }
        }
    }
    ids.sort();
    ids
}

/// Pushes unless already present (photo lists are short; clarity over speed).
fn push_unique(ids: &mut Vec<String>, id: &str) {
    if !ids.iter().any(|known| known == id) {
        ids.push(id.to_owned());
    }
}
/// Commands that run against a real session: a file naming any of them
/// starts sessionless instead of opening a draft.
const SESSION_COMMANDS: [&str; 7] = [
    "session.new",
    "session.open",
    "session.close",
    "session.verify",
    "session.backup",
    "session.restore",
    "template.save",
];

/// Commands that open a real session: a file naming any of them refuses
/// `--photos` (draft members and real sessions do not mix).
const SESSION_STARTERS: [&str; 3] = ["session.new", "session.open", "session.restore"];

/// How long one line waits for its jobs before the run fails instead of
/// hanging forever.
const JOB_DRAIN_TIMEOUT: Duration = Duration::from_secs(120);

/// The command ids a JSONL file names, in file order. Unparseable lines
/// are skipped here; they fail loudly at execution.
fn file_command_ids(text: &str) -> Vec<String> {
    let mut ids = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Ok(call) = serde_json::from_str::<serde_json::Value>(line) else {
            continue;
        };
        if let Some(id) = call.get("id").and_then(|value| value.as_str()) {
            ids.push(id.to_owned());
        }
    }
    ids
}

/// What `run` executed: outcome, job, and hold lines plus the failure count.
#[derive(Debug)]
pub struct RunReport {
    /// One line per executed call (in file order), each followed by its
    /// jobs' event lines, plus hold lines when `--hold` is set.
    pub lines: Vec<String>,
    /// How many calls failed (plus a timed-out drain or a failed hold).
    pub failed: usize,
}

/// Executes one JSONL line against the engine.
fn run_one_line(
    engine: &mut Engine,
    line: &str,
) -> Result<(String, serde_json::Value), (String, String)> {
    let call: serde_json::Value =
        serde_json::from_str(line).map_err(|err| ("?".to_owned(), format!("bad JSON: {err}")))?;
    let id = call
        .get("id")
        .and_then(|v| v.as_str())
        .ok_or_else(|| ("?".to_owned(), "missing string \"id\"".to_owned()))?
        .to_owned();
    let params = call
        .get("params")
        .cloned()
        .unwrap_or(serde_json::Value::Null);
    engine.execute(&id, &params).map_or_else(
        |err| Err((id.clone(), err.to_string())),
        |outcome| Ok((id.clone(), outcome)),
    )
}

/// `id:steps:cursor` per photo, comma-joined, for outcome lines.
fn photo_states(engine: &Engine) -> String {
    engine
        .photo_ids()
        .iter()
        .map(|id| {
            let steps = engine.photo_len(id).unwrap_or(0);
            let cursor = engine.photo_cursor(id).unwrap_or(0);
            format!("{id}:{steps}:{cursor}")
        })
        .collect::<Vec<_>>()
        .join(",")
}

/// `short:steps:cursor` for the file's watched ids, comma-joined, for
/// real-session outcome lines. Ids shorten to 8 characters; ids the open
/// session does not hold show `?:?`.
fn watched_states(engine: &Engine, watched: &[String]) -> String {
    watched
        .iter()
        .map(|id| {
            let short: String = id.chars().take(8).collect();
            match (engine.photo_len(id), engine.photo_cursor(id)) {
                (Some(steps), Some(cursor)) => format!("{short}:{steps}:{cursor}"),
                _ => format!("{short}:?:?"),
            }
        })
        .collect::<Vec<_>>()
        .join(",")
}

/// Outcome-line photo states: a real session prints the file's own watched
/// ids (shortened); drafts and lines before any session opens print the
/// engine members as before.
fn line_states(engine: &Engine, wants_session: bool, watched: &[String]) -> String {
    if wants_session && engine.has_real_session() {
        watched_states(engine, watched)
    } else {
        photo_states(engine)
    }
}

/// Runs a JSONL command file and drains every line's jobs before the next
/// line, so a file runs deterministically from top to bottom.
///
/// Blank lines and `#` comment lines are skipped. Files naming session
/// commands start sessionless (and refuse `photos`: draft members and
/// real sessions do not mix); every other file opens a draft, with
/// `photos` selecting its members explicitly or [`None`] scanning them
/// out of the file. Once a real session is open, outcome lines print the
/// file's own watched ids (`params.id` / `params.ids` anywhere in the file)
/// as `short:steps:cursor` with ids shortened to 8 characters; lines before
/// any session opens print `photos=[]`. Every line runs even after failures;
/// the caller maps a nonzero `failed` count to its failure exit. `hold_secs`
/// parks an open real session that long after the last line, then closes it.
/// `sink` receives every line as it is produced (the binary prints and
/// flushes; tests record or ignore).
///
/// # Errors
///
/// Returns [`Error`] when the file cannot be read, or when `photos` meets
/// a file that opens a real session.
pub fn run_file(
    path: &Path,
    photos: Option<Vec<String>>,
    hold_secs: u64,
    sink: &mut dyn FnMut(&str),
) -> Result<RunReport, Error> {
    let text = read_to_string(path)?;
    let ids = file_command_ids(&text);
    let wants_session = ids.iter().any(|id| SESSION_COMMANDS.contains(&id.as_str()));
    let watched = scan_photo_ids(&text);
    if photos.is_some() && ids.iter().any(|id| SESSION_STARTERS.contains(&id.as_str())) {
        return Err(Error(
            "run: --photos selects a draft session, but the file opens a real one (session.new/open/restore)".to_owned(),
        ));
    }
    let mut engine = if wants_session {
        Engine::new()
    } else {
        Engine::open_draft(photos.unwrap_or_else(|| scan_photo_ids(&text)))
    };
    engine.set_program("lightamer-cli");
    let seen: Rc<RefCell<Vec<Event>>> = Rc::new(RefCell::new(Vec::new()));
    let into = Rc::clone(&seen);
    engine.subscribe(Rc::new(move |event, _| {
        into.borrow_mut().push(event.clone());
    }));
    let mut taken = 0;
    let mut emitter = Emitter::new(sink);
    for (nth, raw) in text.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let lineno = nth + 1;
        match run_one_line(&mut engine, line) {
            Ok((id, outcome)) => {
                let photos = line_states(&engine, wants_session, &watched);
                let digest = engine.state_digest_decimal();
                emitter.push(format!(
                    "line {lineno}: {id} ok outcome={outcome} photos=[{photos}] digest={digest}"
                ));
            }
            Err((id, reason)) => {
                emitter.report.failed += 1;
                let photos = line_states(&engine, wants_session, &watched);
                let digest = engine.state_digest_decimal();
                emitter.push(format!(
                    "line {lineno}: {id} FAIL {reason} photos=[{photos}] digest={digest}"
                ));
            }
        }
        drain_jobs(&mut engine, &seen, &mut taken, lineno, &mut emitter);
    }
    if hold_secs > 0 {
        hold_session(&mut engine, hold_secs, &mut emitter);
    }
    Ok(emitter.report)
}

/// Collects the report while streaming every line to the caller's sink as
/// it is produced (so `--hold` announces itself before it sleeps, and a
/// `--hold` holder is visible in its log while it holds).
struct Emitter<'a> {
    report: RunReport,
    sink: &'a mut dyn FnMut(&str),
}

impl<'a> Emitter<'a> {
    fn new(sink: &'a mut dyn FnMut(&str)) -> Self {
        Self {
            report: RunReport {
                lines: Vec::new(),
                failed: 0,
            },
            sink,
        }
    }

    fn push(&mut self, line: String) {
        (self.sink)(&line);
        self.report.lines.push(line);
    }
}

/// Collects until no job is unfinished, rendering each new job event as a
/// report line. Photo and clipboard events stay unprinted: the outcome
/// lines already carry that state.
fn drain_jobs(
    engine: &mut Engine,
    seen: &RefCell<Vec<Event>>,
    taken: &mut usize,
    lineno: usize,
    emitter: &mut Emitter,
) {
    let start = Instant::now();
    loop {
        engine.collect();
        flush_job_events(engine, seen, taken, lineno, emitter);
        if engine.jobs().iter().all(|info| info.status.is_terminal()) {
            return;
        }
        if start.elapsed() > JOB_DRAIN_TIMEOUT {
            emitter.report.failed += 1;
            emitter.push(format!(
                "line {lineno}: jobs TIMEOUT after {}s",
                JOB_DRAIN_TIMEOUT.as_secs()
            ));
            return;
        }
        std::thread::sleep(Duration::from_millis(5));
    }
}

/// Renders the job events arrived since the last flush.
fn flush_job_events(
    engine: &Engine,
    seen: &RefCell<Vec<Event>>,
    taken: &mut usize,
    lineno: usize,
    emitter: &mut Emitter,
) {
    let events = seen.borrow();
    for event in events.iter().skip(*taken) {
        match event {
            Event::JobStarted { job } => {
                emitter.push(format!("line {lineno}: job {job} started"));
            }
            Event::JobProgress { job, done, total } => {
                emitter.push(format!("line {lineno}: job {job} progress {done}/{total}"));
            }
            Event::JobFinished {
                job,
                success,
                cancelled,
            } => {
                let mut line = format!(
                    "line {lineno}: job {job} finished success={success} cancelled={cancelled}"
                );
                if !success
                    && let Some(info) = engine.job(*job)
                    && let JobStatus::Failed(reason) = &info.status
                {
                    let _ = write!(line, " reason={reason}");
                }
                emitter.push(line);
            }
            Event::PhotoChanged { .. }
            | Event::ClipboardChanged
            | Event::RenderReady { .. }
            | Event::RenderFailed { .. } => {}
        }
    }
    *taken = events.len();
}

/// Holds the open real session for `hold_secs`, then closes it (the
/// dual-open demo parks one process here while another tries to open).
fn hold_session(engine: &mut Engine, hold_secs: u64, emitter: &mut Emitter) {
    let Some(root) = engine.session_root().map(|root| root.display().to_string()) else {
        emitter.push("hold: no real session open, nothing held".to_owned());
        return;
    };
    emitter.push(format!("hold: keeping {root} open for {hold_secs}s"));
    std::thread::sleep(Duration::from_secs(hold_secs));
    match engine.execute("session.close", &serde_json::Value::Null) {
        Ok(_) => emitter.push(format!("hold: closed {root}")),
        Err(err) => {
            emitter.report.failed += 1;
            emitter.push(format!("hold: FAIL {err}"));
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{describe_all, describe_one, run_file, scan_photo_ids};
    use crate::util::{make_temp_dir, remove_dir_quiet, sweep_stale_temp_dirs, write_file};

    /// A temp dir that deletes itself even when the test panics.
    struct GuardDir {
        path: std::path::PathBuf,
    }

    impl GuardDir {
        fn hold() -> Result<Self, crate::util::Error> {
            // Killed predecessors can never clean after themselves.
            let _ = sweep_stale_temp_dirs("lightamer-cli-hold");
            Ok(Self {
                path: make_temp_dir("lightamer-cli-hold")?,
            })
        }
    }

    impl Drop for GuardDir {
        fn drop(&mut self) {
            remove_dir_quiet(&self.path);
        }
    }

    #[test]
    fn listing_covers_every_registered_command() {
        let all = describe_all();
        for spec in lightamer_engine::command_specs() {
            assert!(all.contains(spec.id), "missing {}", spec.id);
            assert!(all.contains(spec.summary), "missing summary of {}", spec.id);
            for param in spec.params {
                assert!(
                    all.contains(param.name),
                    "missing {}.{}",
                    spec.id,
                    param.name
                );
            }
        }
        assert!(all.contains("needs session"), "{all}");
    }

    #[test]
    fn single_listing_round_trips_and_rejects_unknown() {
        let one = describe_one("develop.set").expect("known id");
        assert!(one.contains("develop.set"), "{one}");
        assert!(one.contains("photo-ids"), "{one}");
        assert!(describe_one("no.such.command").is_none());
    }

    #[test]
    fn scan_collects_ids_from_both_param_shapes() {
        let text = "# comment\n\n{\"id\": \"develop.copy\", \"params\": {\"id\": \"b\"}}\n{\"id\": \"develop.reset\", \"params\": {\"ids\": [\"a\", \"b\"]}}\nnot json\n";
        assert_eq!(scan_photo_ids(text), ["a", "b"]);
    }

    #[test]
    fn run_file_executes_reports_and_counts_failures() {
        let dir = make_temp_dir("lightamer-cli-commands").expect("temp dir");
        let file = dir.join("run.jsonl");
        write_file(
            &file,
            b"{\"id\": \"develop.copy\", \"params\": {\"id\": \"a\"}}\n{\"id\": \"develop.paste\", \"params\": {\"ids\": [\"b\"]}}\n{\"id\": \"history.goto\", \"params\": {\"id\": \"b\", \"index\": 99}}\n",
        )
        .expect("write");
        let report = run_file(&file, None, 0, &mut |_| {}).expect("run");
        assert_eq!(report.failed, 1);
        assert_eq!(report.lines.len(), 3);
        assert!(
            report.lines[0].contains("develop.copy ok"),
            "{}",
            report.lines[0]
        );
        assert!(
            report.lines[0].contains("photos=[a:1:0,b:1:0]"),
            "{}",
            report.lines[0]
        );
        assert!(
            report.lines[1].contains("develop.paste ok"),
            "{}",
            report.lines[1]
        );
        assert!(
            report.lines[1].contains("photos=[a:1:0,b:2:1]"),
            "{}",
            report.lines[1]
        );
        assert!(report.lines[2].contains("FAIL"), "{}", report.lines[2]);
        assert!(
            report.lines[2].contains("out of range"),
            "{}",
            report.lines[2]
        );
        for line in &report.lines {
            assert!(line.contains("digest="), "{line}");
        }
        remove_dir_quiet(&dir);
    }

    #[test]
    fn run_file_reports_an_unknown_module_and_missing_file() {
        let dir = make_temp_dir("lightamer-cli-commands").expect("temp dir");
        let file = dir.join("bad.jsonl");
        write_file(
            &file,
            b"{\"id\": \"develop.set\", \"params\": {\"ids\": [\"a\"], \"module\": \"__no_such_module__\", \"patch\": {}}}\n",
        )
        .expect("write");
        let report = run_file(&file, None, 0, &mut |_| {}).expect("run");
        assert_eq!(report.failed, 1);
        assert!(
            report.lines[0].contains("unknown module"),
            "{}",
            report.lines[0]
        );
        remove_dir_quiet(&dir);
        assert!(run_file(&dir.join("absent.jsonl"), None, 0, &mut |_| {}).is_err());
    }
    /// One JSONL line, serialized so paths never break quoting.
    fn jsonl(id: &str, params: &serde_json::Value) -> String {
        format!("{}\n", serde_json::json!({"id": id, "params": params}))
    }

    #[test]
    fn run_file_runs_session_commands_without_a_draft() {
        let dir = make_temp_dir("lightamer-cli-session").expect("temp dir");
        let file = dir.join("session.jsonl");
        let parent = dir.to_string_lossy().into_owned();
        let mut text = String::new();
        text.push_str(&jsonl(
            "session.new",
            &serde_json::json!({"name": "Demo", "parent": parent}),
        ));
        text.push_str(&jsonl("session.verify", &serde_json::json!({})));
        text.push_str(&jsonl("session.close", &serde_json::json!({})));
        write_file(&file, text.as_bytes()).expect("write");
        let report = run_file(&file, None, 0, &mut |_| {}).expect("run");
        assert_eq!(report.failed, 0);
        assert_eq!(report.lines.len(), 3, "{:?}", report.lines);
        assert!(
            report.lines[0].contains("session.new ok"),
            "{}",
            report.lines[0]
        );
        assert!(
            report.lines[1].contains("session.verify ok"),
            "{}",
            report.lines[1]
        );
        assert!(
            report.lines[1].contains("\"count\":0"),
            "{}",
            report.lines[1]
        );
        assert!(
            report.lines[2].contains("session.close ok"),
            "{}",
            report.lines[2]
        );
        assert!(dir.join("Demo/Demo.lmsessiondb").is_file());
        remove_dir_quiet(&dir);
    }

    #[test]
    fn run_file_rejects_photos_with_session_starters() {
        let dir = make_temp_dir("lightamer-cli-photos").expect("temp dir");
        let file = dir.join("starter.jsonl");
        write_file(
            &file,
            jsonl("session.open", &serde_json::json!({"path": "/tmp/nowhere"})).as_bytes(),
        )
        .expect("write");
        let err = run_file(&file, Some(vec!["a".to_owned()]), 0, &mut |_| {})
            .expect_err("photos + starter");
        assert!(err.to_string().contains("--photos"), "{err}");
        remove_dir_quiet(&dir);
    }

    #[test]
    fn run_file_drains_backup_job_and_prints_its_events() {
        let dir = make_temp_dir("lightamer-cli-drain").expect("temp dir");
        let file = dir.join("backup.jsonl");
        let parent = dir.to_string_lossy().into_owned();
        let dest = dir.join("vault").to_string_lossy().into_owned();
        let mut text = String::new();
        text.push_str(&jsonl(
            "session.new",
            &serde_json::json!({"name": "Demo", "parent": parent}),
        ));
        text.push_str(&jsonl("session.backup", &serde_json::json!({"dest": dest})));
        text.push_str(&jsonl("session.close", &serde_json::json!({})));
        write_file(&file, text.as_bytes()).expect("write");
        let report = run_file(&file, None, 0, &mut |_| {}).expect("run");
        assert_eq!(report.failed, 0, "{:?}", report.lines);
        let backup_at = report
            .lines
            .iter()
            .position(|line| line.contains("session.backup ok"))
            .expect("backup line");
        let started_at = report
            .lines
            .iter()
            .position(|line| line.contains("job 1 started"))
            .expect("started");
        let finished_at = report
            .lines
            .iter()
            .position(|line| line.contains("finished success=true cancelled=false"))
            .expect("finished");
        assert!(
            backup_at < started_at && started_at < finished_at,
            "{:?}",
            report.lines
        );
        assert!(dir.join("vault/vault.lmsessiondb").is_file());
        remove_dir_quiet(&dir);
    }

    #[test]
    fn run_file_hold_keeps_session_then_closes() {
        let guard = GuardDir::hold().expect("temp dir");
        let dir = &guard.path;
        let file = dir.join("hold.jsonl");
        let parent = dir.to_string_lossy().into_owned();
        write_file(
            &file,
            jsonl(
                "session.new",
                &serde_json::json!({"name": "Demo", "parent": parent}),
            )
            .as_bytes(),
        )
        .expect("write");
        let report = run_file(&file, None, 1, &mut |_| {}).expect("run");
        assert_eq!(report.failed, 0, "{:?}", report.lines);
        assert!(
            report
                .lines
                .iter()
                .any(|line| line.contains("hold: keeping")),
            "{:?}",
            report.lines
        );
        assert!(
            report
                .lines
                .iter()
                .any(|line| line.contains("hold: closed")),
            "{:?}",
            report.lines
        );
        // The hold closed the session: its lock is free.
        let mut engine = lightamer_engine::Engine::new();
        let root = dir.join("Demo").to_string_lossy().into_owned();
        engine
            .execute("session.open", &serde_json::json!({"path": root}))
            .expect("reopen");
        engine
            .execute("session.close", &serde_json::json!({}))
            .expect("close");
        // No explicit cleanup: the guard deletes the dir on scope exit,
        // even when an assert above panics.
    }
    #[test]
    fn run_file_streams_every_line_to_the_sink() {
        let dir = make_temp_dir("lightamer-cli-stream").expect("temp dir");
        let file = dir.join("one.jsonl");
        write_file(
            &file,
            jsonl("develop.copy", &serde_json::json!({"id": "a"})).as_bytes(),
        )
        .expect("write");
        let mut streamed: Vec<String> = Vec::new();
        let report =
            run_file(&file, None, 0, &mut |line| streamed.push(line.to_owned())).expect("run");
        assert_eq!(streamed, report.lines);
        assert_eq!(streamed.len(), 1);
        remove_dir_quiet(&dir);
    }
}
