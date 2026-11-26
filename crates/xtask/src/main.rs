// SPDX-License-Identifier: GPL-3.0-or-later
//! Repo maintenance tasks: i18n keys, order fixture/stubs, sync, name checks, layering.

mod apple_boundary;
mod gen_stubs;
mod iop_order;
mod layers;
mod no_names;
mod sync;

use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

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
/// `cargo` binary honouring `CARGO` when set.
fn cargo_program() -> String {
    std::env::var("CARGO").unwrap_or_else(|_| "cargo".to_owned())
}

/// Runs `cargo metadata --no-deps` at the workspace root, returns stdout text.
fn metadata_text() -> Result<String, String> {
    let root = iop_order::workspace_root();
    let out = Command::new(cargo_program())
        .args(["metadata", "--format-version", "1", "--no-deps"])
        .current_dir(&root)
        .output()
        .map_err(|err| format!("cargo metadata: {err}"))?;
    if !out.status.success() {
        return Err(format!(
            "cargo metadata failed:\n{}",
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    String::from_utf8(out.stdout).map_err(|err| format!("cargo metadata: bad UTF-8: {err}"))
}

/// Workspace member names in one class, sorted.
fn class_names(crates: &[layers::Crate], class: layers::Class) -> Vec<&str> {
    let mut names: Vec<&str> = crates
        .iter()
        .filter(|c| layers::classify(&c.name) == Some(class))
        .map(|c| c.name.as_str())
        .collect();
    names.sort_unstable();
    names
}

/// Prints the layer table and fails on any violation.
fn cmd_layers() -> Result<(), String> {
    let crates = layers::from_metadata(&metadata_text()?)?;
    println!("Dependency layering (FRAMEWORK.md T-F9)\n");
    for layer in 0..=5 {
        let names = class_names(&crates, layers::Class::Layer(layer));
        println!("L{layer}: {}", names.join(", "));
    }
    println!(
        "testkit: {}",
        class_names(&crates, layers::Class::Testkit).join(", ")
    );
    println!(
        "exempt: {}",
        class_names(&crates, layers::Class::Exempt).join(", ")
    );
    let unregistered: Vec<&str> = crates
        .iter()
        .filter(|c| layers::classify(&c.name).is_none())
        .map(|c| c.name.as_str())
        .collect();
    if !unregistered.is_empty() {
        println!("UNREGISTERED: {}", unregistered.join(", "));
    }
    println!("\n{:<28} {:<14} workspace deps", "crate", "layer");
    for c in &crates {
        let ws: Vec<String> = c
            .deps
            .iter()
            .filter(|d| d.workspace)
            .map(|d| {
                let k = match d.kind {
                    layers::DepKind::Normal => "",
                    layers::DepKind::Dev => " (dev)",
                    layers::DepKind::Build => " (build)",
                };
                format!("{}{k}", d.name)
            })
            .collect();
        println!(
            "{:<28} {:<14} {}",
            c.name,
            layers::describe(layers::classify(&c.name)),
            ws.join(", ")
        );
    }
    let violations = layers::check(&crates);
    println!();
    if violations.is_empty() {
        println!("OK: {} crates, no layering violations.", crates.len());
        Ok(())
    } else {
        println!("{} violation(s):", violations.len());
        for v in &violations {
            println!("  - {v}");
        }
        Err(format!("{} layering violation(s)", violations.len()))
    }
}

/// Prints usage; always exits 2.
fn usage() -> ExitCode {
    eprintln!(
        "usage: cargo xtask <check-i18n [DIR] | gen-iop-stubs [--upstream PATH] | check-order-sync [--upstream PATH] | check-no-iop-names | layers | check-apple-boundary>"
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
        "layers" => {
            if args.len() != 1 {
                eprintln!("usage: cargo xtask layers");
                return ExitCode::from(2);
            }
            exit_from(cmd_layers())
        }
        "check-apple-boundary" => {
            if args.len() != 1 {
                eprintln!("usage: cargo xtask check-apple-boundary");
                return ExitCode::from(2);
            }
            exit_from(apple_boundary::run())
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
