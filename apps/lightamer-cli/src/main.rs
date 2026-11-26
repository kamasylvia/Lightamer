// SPDX-License-Identifier: GPL-3.0-or-later
//! Arg parsing + exit codes for lightamer-cli (hand-rolled; no arg-parser dep).
//!
//! Exit codes: 0 ok; 1 check failed (gates, verify, prefs, selftest); 2 usage/IO error.
// Binary entry shim: fallible work lives in the library and maps to an exit
// code here, so the entry itself takes the developer-tool exemption.
#![allow(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

use lightamer_cli::{capabilities, cmp, commands, fetch, render, selftest, util, xmp};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

enum Failure {
    Check(String),
    Usage(String),
}

impl From<util::Error> for Failure {
    fn from(err: util::Error) -> Self {
        Self::Usage(err.0)
    }
}

const HELP: &str = "lightamer-cli: darktable oracle tool\n\
     \n\
     fetch   --lock P [--cache-dir D]                    download + verify DMG\n\
     render  --image I [--xmp X] --out O [--backend cpu|opencl]\n\
             [--lock P] [--cache-dir D] [--log L] [--keep-tmp]\n\
     cmp     A.png B.png [--tol F] [--max-mean F] [--min-in-tol F] [--mirror-x]\n\
     emit-xmp --image I [--exposure-ev F] [--flip-x] [--output O]\n\
     selftest [--lock P] [--cache-dir D] [--sample S] [--workdir W]\n\
     capabilities
     commands [ID]                                       list engine commands
     run --file F [--photos a,b]                         run JSONL calls on a draft session
     \n\
     exit: 0 ok; 1 check failed; 2 usage/IO error";

/// Split `--flag value` / `--flag=value` / `--bool` / positionals.
struct Args {
    flags: Vec<(String, Option<String>)>,
    positionals: Vec<String>,
}

fn split_args(raw: &[String]) -> Args {
    let mut flags = Vec::new();
    let mut positionals = Vec::new();
    let mut iter = raw.iter().peekable();
    while let Some(arg) = iter.next() {
        if arg == "--" {
            positionals.extend(iter.cloned());
            break;
        }
        if let Some(name) = arg.strip_prefix("--") {
            if let Some((key, value)) = name.split_once('=') {
                flags.push((format!("--{key}"), Some(value.to_owned())));
            } else if iter.peek().is_some_and(|next| !next.starts_with("--")) {
                let value = iter.next().cloned();
                flags.push((format!("--{name}"), value));
            } else {
                flags.push((format!("--{name}"), None));
            }
        } else {
            positionals.push(arg.clone());
        }
    }
    Args { flags, positionals }
}

impl Args {
    fn value(&self, flag: &str) -> Result<Option<String>, Failure> {
        for (key, value) in &self.flags {
            if key == flag {
                return value.clone().map_or_else(
                    || Err(Failure::Usage(format!("{flag} wants a value"))),
                    |v| Ok(Some(v)),
                );
            }
        }
        Ok(None)
    }

    fn present(&self, flag: &str) -> bool {
        self.flags.iter().any(|(key, _)| key == flag)
    }

    fn check_only(&self, allowed: &[&str]) -> Result<(), Failure> {
        for (key, _) in &self.flags {
            if !allowed.contains(&key.as_str()) {
                return Err(Failure::Usage(format!("unknown flag {key}")));
            }
        }
        Ok(())
    }
}

fn lock_arg(args: &Args) -> Result<PathBuf, Failure> {
    Ok(args
        .value("--lock")?
        .map_or_else(|| PathBuf::from("Scripts/oracle.lock"), PathBuf::from))
}

fn cache_arg(args: &Args) -> Result<Option<PathBuf>, Failure> {
    Ok(args.value("--cache-dir")?.map(PathBuf::from))
}

fn cmd_fetch(args: &Args) -> Result<(), Failure> {
    args.check_only(&["--lock", "--cache-dir"])?;
    if !args.positionals.is_empty() {
        return Err(Failure::Usage("fetch takes no positionals".to_owned()));
    }
    let lock = fetch::read_lock(&lock_arg(args)?)?;
    let cache = fetch::cache_dir(cache_arg(args)?.as_deref())?;
    let dmg = fetch::ensure_dmg(&lock, &cache)?;
    println!(
        "fetch: {} {} bytes sha256={}",
        dmg.display(),
        lock.size_bytes,
        lock.sha256
    );
    Ok(())
}

fn cmd_render(args: &Args) -> Result<(), Failure> {
    args.check_only(&[
        "--image",
        "--xmp",
        "--out",
        "--backend",
        "--lock",
        "--cache-dir",
        "--log",
        "--keep-tmp",
    ])?;
    if !args.positionals.is_empty() {
        return Err(Failure::Usage("render takes no positionals".to_owned()));
    }
    let image = args
        .value("--image")?
        .ok_or_else(|| Failure::Usage("render wants --image".to_owned()))?;
    let out = args
        .value("--out")?
        .ok_or_else(|| Failure::Usage("render wants --out".to_owned()))?;
    let backend = render::Backend::parse(&args.value("--backend")?.unwrap_or("cpu".to_owned()))?;
    let report = render::render(&render::Options {
        image: PathBuf::from(image),
        xmp: args.value("--xmp")?.map(PathBuf::from),
        out: PathBuf::from(out),
        backend,
        lock_path: lock_arg(args)?,
        cache_override: cache_arg(args)?,
        log_path: args.value("--log")?.map(PathBuf::from),
        keep_tmp: args.present("--keep-tmp"),
    })
    .map_err(|e| Failure::Check(e.0))?;
    println!(
        "render: out={} ({}x{} 16-bit)",
        report.out_path.display(),
        report.png_width,
        report.png_height
    );
    println!("render: log={}", report.log_path.display());
    println!("render: proof={}", report.backend_proof);
    println!(
        "render: prefs identical={} bytes={}",
        report.prefs.identical, report.prefs.before_bytes
    );
    Ok(())
}

fn parse_f64(flag: &str, value: Option<String>) -> Result<Option<f64>, Failure> {
    value
        .map(|v| {
            v.parse::<f64>()
                .map_err(|_| Failure::Usage(format!("{flag} wants a number")))
                .and_then(|n| {
                    if n.is_finite() {
                        Ok(n)
                    } else {
                        Err(Failure::Usage(format!("{flag} wants a finite number")))
                    }
                })
        })
        .transpose()
}

fn cmd_cmp(args: &Args) -> Result<(), Failure> {
    args.check_only(&["--tol", "--max-mean", "--min-in-tol", "--mirror-x"])?;
    if args.positionals.len() != 2 {
        return Err(Failure::Usage("cmp wants exactly 2 PNGs".to_owned()));
    }
    let opts = cmp::Options {
        tol: parse_f64("--tol", args.value("--tol")?)?.unwrap_or(cmp::DEFAULT_TOL),
        max_mean_lsb: parse_f64("--max-mean", args.value("--max-mean")?)?,
        min_in_tol: parse_f64("--min-in-tol", args.value("--min-in-tol")?)?,
        mirror_x_b: args.present("--mirror-x"),
    };
    let stats = cmp::compare(
        Path::new(&args.positionals[0]),
        Path::new(&args.positionals[1]),
        &opts,
    )?;
    println!(
        "{}",
        cmp::format_stats(&stats, &args.positionals[0], &args.positionals[1])
    );
    let violations = cmp::check_gates(&stats, &opts);
    if violations.is_empty() {
        println!("cmp: gates PASS");
        Ok(())
    } else {
        Err(Failure::Check(format!(
            "gates FAIL: {}",
            violations.join("; ")
        )))
    }
}

#[allow(clippy::cast_possible_truncation)] // CLI EV is f32 by format design
fn cmd_emit_xmp(args: &Args) -> Result<(), Failure> {
    args.check_only(&["--image", "--exposure-ev", "--flip-x", "--output"])?;
    if !args.positionals.is_empty() {
        return Err(Failure::Usage("emit-xmp takes no positionals".to_owned()));
    }
    let image = args
        .value("--image")?
        .ok_or_else(|| Failure::Usage("emit-xmp wants --image".to_owned()))?;
    let mut entries: Vec<Box<dyn xmp::DtParamsEncoder>> = Vec::new();
    if let Some(ev) = parse_f64("--exposure-ev", args.value("--exposure-ev")?)? {
        entries.push(Box::new(xmp::ExposureParams {
            mode: 0,
            black: 0.0,
            exposure: ev as f32,
            percentile: 50.0,
            target_level: -4.0,
            compensate_bias: false,
            compensate_highlight: true,
        }));
    }
    if args.present("--flip-x") {
        entries.push(Box::new(xmp::FlipParams::horizontal()));
    }
    let refs: Vec<&dyn xmp::DtParamsEncoder> =
        entries.iter().map(std::convert::AsRef::as_ref).collect();
    let image_path = PathBuf::from(&image);
    let derived = image_path
        .file_name()
        .map_or(image.clone(), |n| n.to_string_lossy().into_owned());
    let doc = xmp::emit_xmp(&derived, &refs);
    let out = args
        .value("--output")?
        .map_or_else(|| PathBuf::from(format!("{image}.xmp")), PathBuf::from);
    util::write_file(&out, doc.as_bytes())?;
    println!(
        "emit-xmp: {} entries={} -> {}",
        derived,
        refs.len(),
        out.display()
    );
    Ok(())
}

fn cmd_capabilities(args: &Args) -> Result<(), Failure> {
    args.check_only(&[])?;
    if !args.positionals.is_empty() {
        return Err(Failure::Usage(
            "capabilities takes no positionals".to_owned(),
        ));
    }
    println!("{}", capabilities::render());
    Ok(())
}

fn cmd_selftest(args: &Args) -> Result<(), Failure> {
    args.check_only(&["--lock", "--cache-dir", "--sample", "--workdir"])?;
    if !args.positionals.is_empty() {
        return Err(Failure::Usage("selftest takes no positionals".to_owned()));
    }
    let opts = selftest::Options {
        lock_path: lock_arg(args)?,
        cache_override: cache_arg(args)?,
        sample: args.value("--sample")?.map(PathBuf::from),
        workdir: args.value("--workdir")?.map(PathBuf::from),
    };
    match selftest::run(&opts) {
        Ok(report) => {
            print!("{report}");
            Ok(())
        }
        Err(e) => Err(Failure::Check(e.0)),
    }
}

fn cmd_commands(args: &Args) -> Result<(), Failure> {
    args.check_only(&[])?;
    if args.positionals.len() > 1 {
        return Err(Failure::Usage("commands takes at most one ID".to_owned()));
    }
    match args.positionals.first() {
        None => print!("{}", commands::describe_all()),
        Some(id) => match commands::describe_one(id) {
            Some(text) => print!("{text}"),
            None => return Err(Failure::Usage(format!("unknown command {id}"))),
        },
    }
    Ok(())
}

fn cmd_run(args: &Args) -> Result<(), Failure> {
    args.check_only(&["--file", "--photos"])?;
    if !args.positionals.is_empty() {
        return Err(Failure::Usage("run takes no positionals".to_owned()));
    }
    let file = args
        .value("--file")?
        .ok_or_else(|| Failure::Usage("--file is required".to_owned()))?;
    let photos = args.value("--photos")?.map(|list| {
        list.split(',')
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_owned)
            .collect::<Vec<_>>()
    });
    let report = commands::run_file(Path::new(&file), photos)?;
    for line in &report.lines {
        println!("{line}");
    }
    if report.failed > 0 {
        return Err(Failure::Check(format!(
            "{} of {} lines failed",
            report.failed,
            report.lines.len()
        )));
    }
    Ok(())
}

fn run(raw: &[String]) -> Result<(), Failure> {
    if raw.is_empty() {
        return Err(Failure::Usage("want a subcommand (try help)".to_owned()));
    }
    let (sub, rest) = raw.split_at(1);
    match sub[0].as_str() {
        "fetch" => cmd_fetch(&split_args(rest)),
        "render" => cmd_render(&split_args(rest)),
        "cmp" => cmd_cmp(&split_args(rest)),
        "emit-xmp" => cmd_emit_xmp(&split_args(rest)),
        "selftest" => cmd_selftest(&split_args(rest)),
        "capabilities" => cmd_capabilities(&split_args(rest)),
        "commands" => cmd_commands(&split_args(rest)),
        "run" => cmd_run(&split_args(rest)),
        "help" | "--help" | "-h" => {
            println!("{HELP}");
            Ok(())
        }
        "version" | "--version" => {
            println!("{} {}", env!("CARGO_PKG_NAME"), env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        other => Err(Failure::Usage(format!("unknown subcommand {other}"))),
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(Failure::Check(msg)) => {
            eprint!("lightamer-cli: check failed: {msg}");
            if !msg.ends_with('\n') {
                eprintln!();
            }
            ExitCode::from(1)
        }
        Err(Failure::Usage(msg)) => {
            eprintln!("lightamer-cli: error: {msg}");
            ExitCode::from(2)
        }
    }
}
