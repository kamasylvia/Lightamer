// SPDX-License-Identifier: GPL-3.0-or-later
//! Oracle self-check: 8 full-res renders (3 groups × 2 backends + 2 repeats),
//! then the five §5 assertions with printed numbers.

use crate::{cmp, fetch, render, util, xmp};
use std::fmt::Write as _;
use std::fs;
use std::path::PathBuf;

/// CC0 sample file name inside the `TestRAW` dir.
pub const SAMPLE_NAME: &str = "7RM5-LosslessCompressedLarge.ARW";

/// Selftest options.
#[derive(Debug)]
pub struct Options {
    /// `oracle.lock` path.
    pub lock_path: PathBuf,
    /// Cache dir override (`None` = env/default).
    pub cache_override: Option<PathBuf>,
    /// Sample image override (`None` = `TestRAW` A7R5 shot).
    pub sample: Option<PathBuf>,
    /// Workdir to keep (`None` = temp dir, removed at the end).
    pub workdir: Option<PathBuf>,
}

/// Default sample: the CC0 A7R5 shot. Never the user photo library.
///
/// # Errors
///
/// Returns [`util::Error`] when `$HOME` is missing or the sample is absent.
pub fn default_sample() -> Result<PathBuf, util::Error> {
    let home = util::home_dir().ok_or_else(|| util::Error::new("no $HOME for default sample"))?;
    let sample = home
        .join("Library/Application Support/Lightamer/TestRAW")
        .join(SAMPLE_NAME);
    if sample.is_file() {
        Ok(sample)
    } else {
        Err(util::Error::new(format!(
            "sample missing: {}",
            sample.display()
        )))
    }
}

struct Work {
    dir: PathBuf,
    keep: bool,
    image: PathBuf,
    g1_xmp: PathBuf,
    g2_xmp: PathBuf,
    logs: PathBuf,
}

fn prepare(opts: &Options, lock: &fetch::Lock) -> Result<Work, util::Error> {
    let (dir, keep) = match &opts.workdir {
        Some(dir) => {
            fs::create_dir_all(dir).map_err(|e| util::io_error(dir, e))?;
            (dir.clone(), true)
        }
        None => (util::make_temp_dir("dt-oracle-selftest")?, false),
    };
    let sample = opts.sample.clone().map_or_else(default_sample, Ok)?;
    let image = dir.join(SAMPLE_NAME);
    fs::copy(&sample, &image).map_err(|e| util::io_error(&image, e))?;
    let exposure = xmp::ExposureParams::manual_plus_1ev();
    let flip = xmp::FlipParams::horizontal();
    let g1_xmp = dir.join("g1-exposure.xmp");
    let g2_xmp = dir.join("g2-exposure-flip.xmp");
    util::write_file(&g1_xmp, xmp::emit_xmp(SAMPLE_NAME, &[&exposure]).as_bytes())?;
    util::write_file(
        &g2_xmp,
        xmp::emit_xmp(SAMPLE_NAME, &[&exposure, &flip]).as_bytes(),
    )?;
    let logs = dir.join("logs");
    fs::create_dir_all(&logs).map_err(|e| util::io_error(&logs, e))?;
    eprintln!(
        "selftest: oracle {} workdir {}",
        lock.version,
        dir.display()
    );
    Ok(Work {
        dir,
        keep,
        image,
        g1_xmp,
        g2_xmp,
        logs,
    })
}

struct Leg {
    name: &'static str,
    group: &'static str,
    backend: render::Backend,
}

const LEGS: [Leg; 8] = [
    Leg {
        name: "g0-cpu",
        group: "g0",
        backend: render::Backend::Cpu,
    },
    Leg {
        name: "g0-cpu-r2",
        group: "g0",
        backend: render::Backend::Cpu,
    },
    Leg {
        name: "g0-cl",
        group: "g0",
        backend: render::Backend::OpenCl,
    },
    Leg {
        name: "g1-cpu",
        group: "g1",
        backend: render::Backend::Cpu,
    },
    Leg {
        name: "g1-cpu-r2",
        group: "g1",
        backend: render::Backend::Cpu,
    },
    Leg {
        name: "g1-cl",
        group: "g1",
        backend: render::Backend::OpenCl,
    },
    Leg {
        name: "g2-cpu",
        group: "g2",
        backend: render::Backend::Cpu,
    },
    Leg {
        name: "g2-cl",
        group: "g2",
        backend: render::Backend::OpenCl,
    },
];

fn render_leg(work: &Work, opts: &Options, leg: &Leg) -> Result<(), util::Error> {
    let xmp_path = match leg.group {
        "g1" => Some(work.g1_xmp.clone()),
        "g2" => Some(work.g2_xmp.clone()),
        _ => None,
    };
    let out = work.dir.join(format!("{}.png", leg.name));
    let report = render::render(&render::Options {
        image: work.image.clone(),
        xmp: xmp_path,
        out: out.clone(),
        backend: leg.backend,
        lock_path: opts.lock_path.clone(),
        cache_override: opts.cache_override.clone(),
        log_path: Some(work.logs.join(format!("{}.log", leg.name))),
        keep_tmp: false,
    })?;
    // darktable must not leave its own sidecar next to our input; drop it if so.
    let stray = work.dir.join(format!("{SAMPLE_NAME}.xmp"));
    let _ = fs::remove_file(&stray);
    eprintln!(
        "selftest: rendered {} proof={}",
        leg.name, report.backend_proof
    );
    Ok(())
}

/// Collected numbers plus failures.
struct Checks {
    lines: Vec<String>,
    failures: Vec<String>,
}

impl Checks {
    fn line(&mut self, text: String) {
        self.lines.push(text);
    }

    fn require(&mut self, ok: bool, what: &str) {
        if !ok {
            self.failures.push(what.to_owned());
        }
    }
}

fn png_of(work: &Work, name: &str) -> PathBuf {
    work.dir.join(format!("{name}.png"))
}

fn assert_repeats(checks: &mut Checks, work: &Work) -> Result<(), util::Error> {
    for (orig, name) in [("g0-cpu", "g0-cpu-r2"), ("g1-cpu", "g1-cpu-r2")] {
        let stats = cmp::compare(
            &png_of(work, orig),
            &png_of(work, name),
            &cmp::Options::default(),
        )?;
        checks.line(format!(
            "repeat {orig} vs {name}: mean_lsb={:.4} max_lsb={:.4} in_tol={:.8}",
            stats.mean_lsb, stats.max_lsb, stats.in_tol_frac
        ));
        checks.require(stats.max_lsb < 0.5, &format!("repeat {name}: max_lsb != 0"));
    }
    Ok(())
}

fn assert_backends(checks: &mut Checks, work: &Work) -> Result<(), util::Error> {
    for group in ["g0", "g1", "g2"] {
        let stats = cmp::compare(
            &png_of(work, &format!("{group}-cpu")),
            &png_of(work, &format!("{group}-cl")),
            &cmp::Options::default(),
        )?;
        checks.line(format!(
            "cpu-vs-cl {group}: mean_lsb={:.4} max_lsb={:.4} beyond_samples={} beyond_pixels={}",
            stats.mean_lsb, stats.max_lsb, stats.beyond_tol_samples, stats.beyond_tol_pixels
        ));
        checks.require(
            stats.mean_lsb < 0.05,
            &format!("{group}: cpu/cl mean >= 0.05"),
        );
        checks.require(
            stats.beyond_tol_samples <= 100,
            &format!("{group}: cpu/cl beyond-tol samples > 100"),
        );
    }
    Ok(())
}

fn assert_effect_and_mirror(checks: &mut Checks, work: &Work) -> Result<(), util::Error> {
    let plain = cmp::Options::default();
    let effect = cmp::compare(&png_of(work, "g0-cpu"), &png_of(work, "g1-cpu"), &plain)?;
    checks.line(format!(
        "exposure-effect g0 vs g1: mean_lsb={:.4} max_lsb={:.4} in_tol={:.8}",
        effect.mean_lsb, effect.max_lsb, effect.in_tol_frac
    ));
    checks.require(
        effect.mean_lsb > 100.0,
        "exposure had no effect (mean <= 100)",
    );
    let flip_check = cmp::compare(&png_of(work, "g1-cpu"), &png_of(work, "g2-cpu"), &plain)?;
    checks.line(format!(
        "flip-plain g1 vs g2: mean_lsb={:.4} in_tol={:.8}",
        flip_check.mean_lsb, flip_check.in_tol_frac
    ));
    checks.require(
        flip_check.mean_lsb > 100.0,
        "flip had no effect (mean <= 100)",
    );
    let mirror = cmp::Options {
        mirror_x_b: true,
        ..cmp::Options::default()
    };
    for backend in ["cpu", "cl"] {
        let stats = cmp::compare(
            &png_of(work, &format!("g1-{backend}")),
            &png_of(work, &format!("g2-{backend}")),
            &mirror,
        )?;
        checks.line(format!(
            "mirror g1-{backend} vs g2-{backend}: mean_lsb={:.4} max_lsb={:.4}",
            stats.mean_lsb, stats.max_lsb
        ));
        checks.require(
            stats.max_lsb < 0.5,
            &format!("mirror {backend}: not bit-exact"),
        );
    }
    Ok(())
}

fn assert_hygiene(checks: &mut Checks) {
    // Scoped to our own mountpoints: other lanes run darktable concurrently,
    // and our launcher cmdline itself contains `pgrep -fl darktable-cli`.
    let mounts_clean = util::run_capture("hdiutil", &["info"], &[]).is_ok_and(|o| {
        let text = format!(
            "{}\n{}",
            String::from_utf8_lossy(&o.stdout),
            String::from_utf8_lossy(&o.stderr)
        );
        !text.contains("dt-oracle-run")
    });
    checks.line(format!("hygiene mounts-clean={mounts_clean}"));
    checks.require(mounts_clean, "our darktable volume still mounted");
    let procs_clean = util::run_capture("pgrep", &["-f", "dt-oracle-run.*darktable-cli"], &[])
        .is_ok_and(|o| !o.success && o.stdout.is_empty());
    checks.line(format!("hygiene no-own-darktable-cli-procs={procs_clean}"));
    checks.require(procs_clean, "our darktable-cli process left behind");
    let stale_tmp = std::env::temp_dir().read_dir().is_ok_and(|entries| {
        entries.flatten().any(|e| {
            e.file_name()
                .to_string_lossy()
                .starts_with("dt-oracle-run-")
        })
    });
    checks.line(format!("hygiene no-stale-tmp={}", !stale_tmp));
    checks.require(!stale_tmp, "stale dt-oracle-run-* temp dir left behind");
}

/// Run the full selftest; returns the printable report.
///
/// # Errors
///
/// Returns [`util::Error`] carrying the full report plus failures when any
/// assertion fails, or when setup/render/compare breaks.
pub fn run(opts: &Options) -> Result<String, util::Error> {
    let lock = fetch::read_lock(&opts.lock_path)?;
    let cache = fetch::cache_dir(opts.cache_override.as_deref())?;
    let dmg = cache.join(&lock.filename);
    fetch::verify_file(&dmg, &lock).map_err(|e| {
        let _ = fs::remove_file(&dmg);
        util::Error::new(format!("selftest: refusing to run: {e}"))
    })?;
    let work = prepare(opts, &lock)?;
    let global_before = render::export_prefs(&work.dir.join("global-before.plist"))?;
    let mut checks = Checks {
        lines: Vec::new(),
        failures: Vec::new(),
    };
    let mut failed = false;
    for leg in LEGS {
        if let Err(e) = render_leg(&work, opts, &leg) {
            checks.line(format!("render {} FAILED: {e}", leg.name));
            checks.failures.push(format!("render {} failed", leg.name));
            failed = true;
            break;
        }
    }
    if !failed {
        for step in [assert_repeats, assert_backends, assert_effect_and_mirror] {
            if let Err(e) = step(&mut checks, &work) {
                checks.failures.push(format!("compare step failed: {e}"));
                break;
            }
        }
        match render::export_prefs(&work.dir.join("global-after.plist")) {
            Ok(global_after) => {
                let same = global_before.rc == global_after.rc
                    && global_before.bytes == global_after.bytes;
                checks.line(format!(
                    "prefs identical={same} bytes={}",
                    global_before.bytes.len()
                ));
                checks.require(same, "user prefs changed during selftest");
            }
            Err(e) => checks.failures.push(format!("prefs snapshot failed: {e}")),
        }
        assert_hygiene(&mut checks);
    }
    let mut report = checks.lines.join("\n");
    report.push('\n');
    if checks.failures.is_empty() {
        report.push_str("selftest: PASS\n");
    } else {
        let _ = writeln!(report, "selftest: FAIL: {}", checks.failures.join("; "));
    }
    if work.keep {
        let _ = writeln!(report, "selftest: workdir kept at {}", work.dir.display());
    } else {
        util::remove_dir_quiet(&work.dir);
        report.push_str("selftest: workdir removed\n");
    }
    if checks.failures.is_empty() {
        Ok(report)
    } else {
        Err(util::Error::new(report))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn legs_cover_three_groups_times_two_backends_plus_two_repeats() {
        assert_eq!(LEGS.len(), 8);
        let mut groups = [0, 0, 0];
        for leg in LEGS {
            match leg.group {
                "g0" => groups[0] += 1,
                "g1" => groups[1] += 1,
                "g2" => groups[2] += 1,
                _ => panic!("bad group"),
            }
        }
        assert_eq!(groups, [3, 3, 2]);
        assert_eq!(LEGS.iter().filter(|l| l.name.ends_with("-r2")).count(), 2);
    }

    #[test]
    fn checks_collect_failures() {
        let mut checks = Checks {
            lines: Vec::new(),
            failures: Vec::new(),
        };
        checks.line("n=1".to_owned());
        checks.require(true, "nope");
        checks.require(false, "boom");
        assert_eq!(checks.failures, vec!["boom".to_owned()]);
    }
}
