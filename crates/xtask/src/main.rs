// SPDX-License-Identifier: GPL-3.0-or-later
//! Repo maintenance tasks. Only `check-i18n` exists; semantic comparison lands at B17.

use std::path::Path;
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

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    if let Some("check-i18n") = args.next().as_deref() {
        let dir = args.next().unwrap_or_else(|| "i18n".to_string());
        check_i18n(&dir)
    } else {
        eprintln!("usage: cargo xtask check-i18n [DIR]");
        ExitCode::from(2)
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }
}
