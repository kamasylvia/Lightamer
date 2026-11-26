// SPDX-License-Identifier: GPL-3.0-or-later
//! Repo maintenance tasks: i18n keys, order fixture/stubs, sync, name checks.

mod gen_stubs;
mod iop_order;
mod no_names;
mod sync;

use std::path::{Path, PathBuf};
use std::process::ExitCode;

fn count_key_tables(dir: &Path) -> Option<usize> {
    let entries = std::fs::read_dir(dir).ok()?;
    let mut n = 0;
    for entry in entries {
        let entry = entry.ok()?;
        let path = entry.path();
        if path.extension().is_some_and(|ext| ext == "json") {
            n += 1;
        }
    }
    Some(n)
}

fn check_i18n(dir: &str) -> ExitCode {
    match count_key_tables(Path::new(dir)) {
        None => {
            println!(
                "xtask check-i18n: no key-table dir '{dir}' (i18n starts at B17); nothing to compare."
            );
        }
        Some(0) => {
            println!("xtask check-i18n: no key tables under '{dir}'; nothing to compare.");
        }
        Some(n) => {
            println!(
                "xtask check-i18n: found {n} key table(s) under '{dir}'; semantic comparison lands at B17."
            );
        }
    }
    ExitCode::SUCCESS
}

/// Default upstream checkout: the sibling spike's `refs/dt-master`.
fn default_upstream() -> PathBuf {
    iop_order::workspace_root().join("../Lightamer-rust-spike/refs/dt-master")
}

/// Parses `--upstream PATH` (optional) from the rest of the args.
fn parse_upstream(args: &[String]) -> Result<PathBuf, String> {
    if args.is_empty() {
        return Ok(default_upstream());
    }
    if args.len() == 2 && args[0] == "--upstream" {
        return Ok(PathBuf::from(&args[1]));
    }
    Err(format!("expected [--upstream PATH], got {args:?}"))
}

/// Runs a task taking `--upstream PATH`, mapping errors to exit codes.
fn run_with_upstream(args: &[String], task: fn(&Path) -> Result<(), String>) -> ExitCode {
    match parse_upstream(args) {
        Ok(upstream) => exit_from(task(&upstream)),
        Err(err) => {
            eprintln!("xtask: {err}");
            ExitCode::from(2)
        }
    }
}

/// Maps a task result to an exit code, printing the error.
fn exit_from(result: Result<(), String>) -> ExitCode {
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("xtask: {err}");
            ExitCode::from(1)
        }
    }
}

/// Prints usage; always exits 2.
fn usage() -> ExitCode {
    eprintln!(
        "usage: cargo xtask <check-i18n [DIR] | gen-iop-stubs [--upstream PATH] | check-order-sync [--upstream PATH] | check-no-iop-names>"
    );
    ExitCode::from(2)
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some(cmd) = args.first() else {
        return usage();
    };
    match cmd.as_str() {
        "check-i18n" => {
            let dir = args.get(1).map_or("i18n", String::as_str);
            check_i18n(dir)
        }
        "gen-iop-stubs" => run_with_upstream(&args[1..], gen_stubs::run),
        "check-order-sync" => run_with_upstream(&args[1..], sync::run),
        "check-no-iop-names" => {
            if args.len() != 1 {
                eprintln!("usage: cargo xtask check-no-iop-names");
                return ExitCode::from(2);
            }
            exit_from(no_names::run())
        }
        _ => usage(),
    }
}

#[cfg(test)]
mod tests {
    use super::{PathBuf, parse_upstream};

    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }

    #[test]
    fn upstream_flag_parses() {
        assert!(parse_upstream(&[]).is_ok());
        let args = ["--upstream".to_owned(), "elsewhere".to_owned()];
        assert_eq!(
            parse_upstream(&args).expect("flag"),
            PathBuf::from("elsewhere")
        );
        assert!(parse_upstream(&["--bogus".to_owned()]).is_err());
    }
}
