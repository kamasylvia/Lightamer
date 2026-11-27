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

use lightamer_cli::{
    bench, capabilities, cmp, commands, decode, fetch, render, render_demo, selftest, util, xmp,
};
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
     run --file F [--photos a,b] [--hold S]              run JSONL calls (draft, or real sessions)
     bench setup --parent D --name N --photos K          plant K empty photos (dev tool, not import)
     bench paste --session S --photos K [--runs R]       time one paste over K photos, R rounds (dev tool)
     render-demo [--size N]                              B1 render pipeline demo on synthetic pixels
     decode --dump F [--thumb O] [--repeat N]         B2 decode probe: fields + timings + raster + thumb (dev tool)
     run on a real session prints the file's photo ids shortened to 8 chars
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

fn parse_count(flag: &str, value: Option<String>) -> Result<usize, Failure> {
    let Some(text) = value else {
        return Err(Failure::Usage(format!("{flag} is required")));
    };
    match text.parse::<usize>() {
        Ok(n) if n > 0 => Ok(n),
        _ => Err(Failure::Usage(format!(
            "{flag} wants a count of at least 1"
        ))),
    }
}

fn cmd_bench(args: &Args) -> Result<(), Failure> {
    let Some(action) = args.positionals.first() else {
        return Err(Failure::Usage("bench wants setup or paste".to_owned()));
    };
    if args.positionals.len() != 1 {
        return Err(Failure::Usage("bench takes one action".to_owned()));
    }
    match action.as_str() {
        "setup" => {
            args.check_only(&["--parent", "--name", "--photos"])?;
            let parent = args
                .value("--parent")?
                .ok_or_else(|| Failure::Usage("--parent is required".to_owned()))?;
            let name = args
                .value("--name")?
                .ok_or_else(|| Failure::Usage("--name is required".to_owned()))?;
            let photos = parse_count("--photos", args.value("--photos")?)?;
            let report = bench::bench_setup(Path::new(&parent), &name, photos)?;
            println!(
                "bench setup: session {} database {} registered {} photos",
                report.root.display(),
                report.database.display(),
                report.registered
            );
            Ok(())
        }
        "paste" => {
            args.check_only(&["--session", "--photos", "--runs"])?;
            let session = args
                .value("--session")?
                .ok_or_else(|| Failure::Usage("--session is required".to_owned()))?;
            let photos = parse_count("--photos", args.value("--photos")?)?;
            let runs = match args.value("--runs")? {
                None => 3,
                Some(text) => parse_count("--runs", Some(text))?,
            };
            match bench::bench_paste(Path::new(&session), photos, runs)? {
                bench::PasteReport::Measured {
                    runs_ms,
                    median_ms,
                    phases_ms,
                    phase_medians_ms,
                    events,
                    photos,
                    passed,
                } => {
                    for (round, ((ms, got), thirds)) in runs_ms
                        .iter()
                        .zip(events.iter())
                        .zip(phases_ms.iter())
                        .enumerate()
                    {
                        let &[read_ms, compute_ms, write_ms] = thirds;
                        println!(
                            "bench paste: round {}: {ms:.1}ms read={read_ms:.1} compute={compute_ms:.1} write={write_ms:.1} events={got}",
                            round + 1
                        );
                    }
                    let rounds: Vec<String> = events
                        .iter()
                        .map(std::string::ToString::to_string)
                        .collect();
                    let [median_read_ms, median_compute_ms, median_write_ms] = phase_medians_ms;
                    println!(
                        "bench paste: {photos} photos x {} runs: median {median_ms:.1}ms (read {median_read_ms:.1} compute {median_compute_ms:.1} write {median_write_ms:.1}) events=[{}] gate=1000ms {}",
                        runs_ms.len(),
                        rounds.join(","),
                        if passed { "PASS" } else { "FAIL" }
                    );
                    if passed {
                        Ok(())
                    } else {
                        Err(Failure::Check(format!(
                            "median {median_ms:.1}ms over the 1000ms gate"
                        )))
                    }
                }
                bench::PasteReport::Skipped { load_one, cpus } => {
                    println!(
                        "bench paste: UNRELIABLE (load {load_one:.2} on {cpus} cpus); skipping, neither pass nor fail"
                    );
                    Ok(())
                }
            }
        }
        other => Err(Failure::Usage(format!("unknown bench action {other}"))),
    }
}

fn cmd_run(args: &Args) -> Result<(), Failure> {
    args.check_only(&["--file", "--photos", "--hold"])?;
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
    let hold = match args.value("--hold")? {
        None => 0,
        Some(text) => text
            .parse::<u64>()
            .map_err(|_| Failure::Usage("--hold wants seconds".to_owned()))?,
    };
    let mut print = |line: &str| {
        println!("{line}");
        let _ = std::io::Write::flush(&mut std::io::stdout());
    };
    let report = commands::run_file(Path::new(&file), photos, hold, &mut print)?;
    if report.failed > 0 {
        return Err(Failure::Check(format!(
            "{} of {} lines failed",
            report.failed,
            report.lines.len()
        )));
    }
    Ok(())
}

fn cmd_render_demo(args: &Args) -> Result<(), Failure> {
    args.check_only(&["--size"])?;
    if !args.positionals.is_empty() {
        return Err(Failure::Usage(
            "render-demo takes no positionals".to_owned(),
        ));
    }
    let size = match args.value("--size")? {
        None => 256,
        Some(text) => text
            .parse::<u32>()
            .map_err(|_| Failure::Usage("--size wants pixels".to_owned()))?,
    };
    let mut print = |line: &str| {
        println!("{line}");
        let _ = std::io::Write::flush(&mut std::io::stdout());
    };
    render_demo::render_demo(size, &mut print)?;
    Ok(())
}

fn cmd_decode(args: &Args) -> Result<(), Failure> {
    args.check_only(&["--dump", "--thumb", "--repeat"])?;
    if !args.positionals.is_empty() {
        return Err(Failure::Usage("decode takes no positionals".to_owned()));
    }
    let dump = args
        .value("--dump")?
        .ok_or_else(|| Failure::Usage("--dump <file> is required".to_owned()))?;
    let repeat = match args.value("--repeat")? {
        None => 1,
        Some(text) => text
            .parse::<usize>()
            .map_err(|_| Failure::Usage("--repeat wants 1..=16".to_owned()))?,
    };
    if !(1..=16).contains(&repeat) {
        return Err(Failure::Usage("--repeat wants 1..=16".to_owned()));
    }
    let thumb = args.value("--thumb")?.map(PathBuf::from);
    decode::dump(&decode::DumpRequest {
        file: PathBuf::from(dump),
        thumb,
        repeat,
    })?;
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
        "bench" => cmd_bench(&split_args(rest)),
        "render-demo" => cmd_render_demo(&split_args(rest)),
        "decode" => cmd_decode(&split_args(rest)),
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
