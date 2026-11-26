// SPDX-License-Identifier: GPL-3.0-or-later
//! `commands` and `run`: the engine registry through the CLI.
//!
//! `commands` prints the registered commands (id, summary, gates, params).
//! `run` executes a JSONL file — one `{"id", "params"}` call per line —
//! against a draft session, printing one outcome line per call.

use std::fmt::Write as _;
use std::path::Path;

use dt_engine::{CommandSpec, Engine, command_specs, find_command};

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

/// What `run` executed: one printable line per call plus the failure count.
pub struct RunReport {
    /// One outcome line per executed call, in file order.
    pub lines: Vec<String>,
    /// How many calls failed.
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

/// Runs a JSONL command file on a draft session.
///
/// Blank lines and `#` comment lines are skipped. `photos` selects the draft
/// members explicitly; [`None`] scans them out of the file. Every line runs
/// even after failures; the caller maps a nonzero `failed` count to its
/// failure exit.
///
/// # Errors
///
/// Returns [`Error`] when the file cannot be read.
pub fn run_file(path: &Path, photos: Option<Vec<String>>) -> Result<RunReport, Error> {
    let text = read_to_string(path)?;
    let ids = photos.unwrap_or_else(|| scan_photo_ids(&text));
    let mut engine = Engine::open_draft(ids);
    let mut report = RunReport {
        lines: Vec::new(),
        failed: 0,
    };
    for (nth, raw) in text.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let lineno = nth + 1;
        match run_one_line(&mut engine, line) {
            Ok((id, outcome)) => {
                let photos = photo_states(&engine);
                let digest = engine.state_digest_decimal();
                report.lines.push(format!(
                    "line {lineno}: {id} ok outcome={outcome} photos=[{photos}] digest={digest}"
                ));
            }
            Err((id, reason)) => {
                report.failed += 1;
                let photos = photo_states(&engine);
                let digest = engine.state_digest_decimal();
                report.lines.push(format!(
                    "line {lineno}: {id} FAIL {reason} photos=[{photos}] digest={digest}"
                ));
            }
        }
    }
    Ok(report)
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{describe_all, describe_one, run_file, scan_photo_ids};
    use crate::util::{make_temp_dir, remove_dir_quiet, write_file};

    #[test]
    fn listing_covers_every_registered_command() {
        let all = describe_all();
        for spec in dt_engine::command_specs() {
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
        let dir = make_temp_dir("dt-cli-commands").expect("temp dir");
        let file = dir.join("run.jsonl");
        write_file(
            &file,
            b"{\"id\": \"develop.copy\", \"params\": {\"id\": \"a\"}}\n{\"id\": \"develop.paste\", \"params\": {\"ids\": [\"b\"]}}\n{\"id\": \"history.goto\", \"params\": {\"id\": \"b\", \"index\": 99}}\n",
        )
        .expect("write");
        let report = run_file(&file, None).expect("run");
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
        let dir = make_temp_dir("dt-cli-commands").expect("temp dir");
        let file = dir.join("bad.jsonl");
        write_file(
            &file,
            b"{\"id\": \"develop.set\", \"params\": {\"ids\": [\"a\"], \"module\": \"__no_such_module__\", \"patch\": {}}}\n",
        )
        .expect("write");
        let report = run_file(&file, None).expect("run");
        assert_eq!(report.failed, 1);
        assert!(
            report.lines[0].contains("unknown module"),
            "{}",
            report.lines[0]
        );
        remove_dir_quiet(&dir);
        assert!(run_file(&dir.join("absent.jsonl"), None).is_err());
    }
}
