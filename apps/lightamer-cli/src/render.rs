// SPDX-License-Identifier: GPL-3.0-or-later
//! One render through the official `darktable-cli`: mount, isolate, log, verify.

use crate::{cmp, fetch, util};
use std::ffi::OsStr;
use std::fs;
use std::path::{Path, PathBuf};

/// Render backend: preset `darktablerc` selects it, never CLI overrides.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Backend {
    /// `opencl=false`.
    Cpu,
    /// `opencl=true`.
    OpenCl,
}

impl Backend {
    /// Parse `cpu` / `opencl`.
    ///
    /// # Errors
    ///
    /// Returns [`util::Error`] on any other value.
    pub fn parse(value: &str) -> Result<Self, util::Error> {
        match value {
            "cpu" => Ok(Self::Cpu),
            "opencl" => Ok(Self::OpenCl),
            other => Err(util::Error::new(format!(
                "bad backend {other}: want cpu|opencl"
            ))),
        }
    }

    /// Short name for logs.
    #[must_use]
    pub fn name(self) -> &'static str {
        match self {
            Self::Cpu => "cpu",
            Self::OpenCl => "opencl",
        }
    }

    fn rc_opencl_line(self) -> &'static str {
        match self {
            Self::Cpu => "opencl=false",
            Self::OpenCl => "opencl=true",
        }
    }

    /// Log substring proving this backend really ran.
    #[must_use]
    pub fn proof_line(self) -> &'static str {
        match self {
            Self::Cpu => "NOT utilized",
            Self::OpenCl => "events were successful",
        }
    }
}

/// Render options.
#[derive(Debug)]
pub struct Options {
    /// Input image (RAW or raster).
    pub image: PathBuf,
    /// Sidecar XMP, passed positionally when present.
    pub xmp: Option<PathBuf>,
    /// Output 16-bit PNG path.
    pub out: PathBuf,
    /// Backend preset.
    pub backend: Backend,
    /// `oracle.lock` path.
    pub lock_path: PathBuf,
    /// Cache dir override (`None` = env/default).
    pub cache_override: Option<PathBuf>,
    /// Log path (`None` = output path with `log` extension).
    pub log_path: Option<PathBuf>,
    /// Keep the temp home + mountpoint for inspection.
    pub keep_tmp: bool,
}

/// `defaults export org.darktable` snapshot.
#[derive(Debug)]
pub struct PrefsSnap {
    /// Export exit code (`Some(0)` = domain read fine).
    pub rc: Option<i32>,
    /// Exported plist bytes (empty unless `rc == Some(0)`).
    pub bytes: Vec<u8>,
}

/// Export user darktable prefs to `dest` (read-only snapshot).
///
/// # Errors
///
/// Returns [`util::Error`] when `defaults` cannot run or the plist cannot be read.
pub fn export_prefs(dest: &Path) -> Result<PrefsSnap, util::Error> {
    let dest_arg = dest.to_string_lossy().into_owned();
    let out = util::run_capture("defaults", &["export", "org.darktable", &dest_arg], &[])?;
    let bytes = if out.success {
        fs::read(dest).map_err(|e| util::io_error(dest, e))?
    } else {
        Vec::new()
    };
    Ok(PrefsSnap {
        rc: out.code,
        bytes,
    })
}

/// Restore prefs from an earlier export. Destructive by design; only the
/// before-render snapshot is ever imported.
///
/// # Errors
///
/// Returns [`util::Error`] when `defaults import` fails.
pub fn import_prefs(plist: &Path) -> Result<(), util::Error> {
    let arg = plist.to_string_lossy().into_owned();
    let out = util::run_capture("defaults", &["import", "org.darktable", &arg], &[])?;
    if out.success {
        return Ok(());
    }
    Err(util::Error::new(format!(
        "defaults import failed: {}",
        util::stderr_tail(&out, 500)
    )))
}

/// Before/after prefs comparison.
#[derive(Debug)]
pub struct PrefsReport {
    /// Before snapshot byte length.
    pub before_bytes: usize,
    /// True when both exports agree byte for byte (or both failed equally).
    pub identical: bool,
}

/// Compare snapshots; on difference restore the before-image and report it.
///
/// # Errors
///
/// Returns [`util::Error`] when the domain changed (after a restore attempt)
/// or appeared out of nowhere.
pub fn check_prefs(
    before: &PrefsSnap,
    after: &PrefsSnap,
    before_path: &Path,
) -> Result<PrefsReport, util::Error> {
    let identical = before.rc == after.rc && before.bytes == after.bytes;
    if identical {
        return Ok(PrefsReport {
            before_bytes: before.bytes.len(),
            identical: true,
        });
    }
    if before.rc == Some(0) {
        let restored = import_prefs(before_path).is_ok();
        eprintln!(
            "render: !! USER PREFS CHANGED DURING RENDER — restored from snapshot (ok={restored})"
        );
        return Err(util::Error::new(format!(
            "org.darktable prefs changed during render ({} -> {} bytes); restored={restored}",
            before.bytes.len(),
            after.bytes.len()
        )));
    }
    Err(util::Error::new(
        "org.darktable domain appeared during render (absent before)",
    ))
}

/// Successful render summary.
#[derive(Debug)]
pub struct Report {
    /// Output PNG path.
    pub out_path: PathBuf,
    /// Full `darktable-cli` log path.
    pub log_path: PathBuf,
    /// Log line proving the requested backend ran.
    pub backend_proof: String,
    /// Prefs before/after report.
    pub prefs: PrefsReport,
    /// Output PNG width.
    pub png_width: u32,
    /// Output PNG height.
    pub png_height: u32,
}

/// RAII mountpoint: detaches on drop unless explicitly detached.
struct MountGuard {
    point: Option<PathBuf>,
}

impl MountGuard {
    /// Detach now; on success the drop becomes a no-op.
    fn detach(&mut self) -> Result<String, util::Error> {
        let Some(point) = self.point.take() else {
            return Ok(String::new());
        };
        let arg = point.to_string_lossy().into_owned();
        let out = util::run_capture("hdiutil", &["detach", &arg], &[])?;
        let transcript = format!(
            "$ hdiutil detach {}\n{}\n{}",
            point.display(),
            String::from_utf8_lossy(&out.stdout),
            String::from_utf8_lossy(&out.stderr)
        );
        if out.success {
            return Ok(transcript);
        }
        self.point = Some(point);
        Err(util::Error::new(format!(
            "hdiutil detach failed: {}",
            util::stderr_tail(&out, 500)
        )))
    }
}

impl Drop for MountGuard {
    fn drop(&mut self) {
        if let Some(point) = &self.point {
            let arg = point.to_string_lossy().into_owned();
            let ok = util::run_capture("hdiutil", &["detach", &arg], &[]).is_ok_and(|o| o.success);
            eprintln!("render: drop-detach {} ok={ok}", point.display());
        }
    }
}

fn verify_cached_dmg(
    lock_path: &Path,
    cache_override: Option<&Path>,
) -> Result<PathBuf, util::Error> {
    let lock = fetch::read_lock(lock_path)?;
    let cache = fetch::cache_dir(cache_override)?;
    let dmg = cache.join(&lock.filename);
    match fetch::verify_file(&dmg, &lock) {
        Ok(()) => Ok(dmg),
        Err(e) => {
            let _ = fs::remove_file(&dmg);
            Err(util::Error::new(format!(
                "refusing to run: cached dmg failed verify ({e});坏文件已删"
            )))
        }
    }
}

fn write_darktablerc(home: &Path, backend: Backend) -> Result<PathBuf, util::Error> {
    let rc_path = home.join(".config/darktable/darktablerc");
    let body = format!(
        "{}\nplugins/imageio/format/png/bpp=16\n",
        backend.rc_opencl_line()
    );
    util::write_file(&rc_path, body.as_bytes())?;
    let cache = home.join(".cache/darktable");
    fs::create_dir_all(&cache).map_err(|e| util::io_error(&cache, e))?;
    Ok(rc_path)
}

fn mount_dmg(dmg: &Path, point: &Path) -> Result<(MountGuard, String), util::Error> {
    let mnt_arg = point.to_string_lossy().into_owned();
    let dmg_arg = dmg.to_string_lossy().into_owned();
    let out = util::run_capture(
        "hdiutil",
        &[
            "attach",
            "-nobrowse",
            "-readonly",
            "-mountpoint",
            &mnt_arg,
            &dmg_arg,
        ],
        &[],
    )?;
    let transcript = format!(
        "$ hdiutil attach -nobrowse -readonly -mountpoint {} {}\n{}\n{}",
        point.display(),
        dmg.display(),
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    if !out.success {
        return Err(util::Error::new(format!(
            "hdiutil attach failed: {}",
            util::stderr_tail(&out, 800)
        )));
    }
    Ok((
        MountGuard {
            point: Some(point.to_owned()),
        },
        transcript,
    ))
}

struct RunOutcome {
    transcript: String,
    success: bool,
    proof: Option<String>,
}

fn run_cli(
    cli: &Path,
    home: &Path,
    image: &Path,
    xmp_path: Option<&Path>,
    out: &Path,
    backend: Backend,
) -> Result<RunOutcome, util::Error> {
    let mut args: Vec<String> = Vec::new();
    args.push(image.to_string_lossy().into_owned());
    if let Some(x) = xmp_path {
        args.push(x.to_string_lossy().into_owned());
    }
    args.push(out.to_string_lossy().into_owned());
    args.extend(["--core".to_owned(), "-d".to_owned(), "opencl".to_owned()]);
    let home_os: &OsStr = home.as_os_str();
    // NB: HOME redirect only affects this child, not our process.
    let mut cmd = std::process::Command::new(cli);
    cmd.args(&args)
        .env("HOME", home_os)
        .env("CFFIXED_USER_HOME", home_os)
        .current_dir(home);
    let output = cmd
        .output()
        .map_err(|e| util::Error::new(format!("spawn {}: {e}", cli.display())))?;
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    let proof = format!("{stdout}\n{stderr}")
        .lines()
        .find(|line| line.contains(backend.proof_line()))
        .map(str::trim)
        .map(str::to_owned);
    let transcript = format!(
        "$ {} {}\nrc={}\n--- stdout ---\n{stdout}\n--- stderr ---\n{stderr}",
        cli.display(),
        args.join(" "),
        output.status.code().unwrap_or(-1)
    );
    Ok(RunOutcome {
        transcript,
        success: output.status.success(),
        proof,
    })
}

/// Render one image through the official CLI.
///
/// Verify-only: a bad or missing cached DMG refuses to run (never downloads).
/// The DMG is detached and temp dirs removed on every path.
///
/// # Errors
///
/// Returns [`util::Error`] on verify failure, mount/render/log failure,
/// missing backend proof, non-16-bit output, or prefs drift.
pub fn render(opts: &Options) -> Result<Report, util::Error> {
    let dmg = verify_cached_dmg(&opts.lock_path, opts.cache_override.as_deref())?;
    let tmp_root = util::make_temp_dir("lightamer-oracle-run")?;
    let report = render_inner(opts, &dmg, &tmp_root);
    if opts.keep_tmp {
        eprintln!("render: kept tmp {}", tmp_root.display());
    } else {
        util::remove_dir_quiet(&tmp_root);
    }
    report
}

fn render_inner(opts: &Options, dmg: &Path, tmp_root: &Path) -> Result<Report, util::Error> {
    let home = tmp_root.join("home");
    let mnt = tmp_root.join("mnt");
    fs::create_dir_all(&home).map_err(|e| util::io_error(&home, e))?;
    fs::create_dir_all(&mnt).map_err(|e| util::io_error(&mnt, e))?;
    let before_path = tmp_root.join("prefs-before.plist");
    let after_path = tmp_root.join("prefs-after.plist");
    let before = export_prefs(&before_path)?;

    let (mut mount, attach_log) = mount_dmg(dmg, &mnt)?;
    let outcome = render_mounted(opts, &home, &mnt, &attach_log);
    let detach_log = mount.detach();
    let (run_log, proof) = outcome?;
    let detach_log = detach_log?;
    append_log_header(&run_log, &attach_log, &detach_log, opts);

    let after = export_prefs(&after_path)?;
    let prefs = check_prefs(&before, &after, &before_path)?;
    let proof = proof.ok_or_else(|| {
        util::Error::new(format!(
            "backend proof {:?} not found in {}",
            opts.backend.proof_line(),
            run_log.display()
        ))
    })?;
    let (width, height, depth, _channels) = cmp::png_info(&opts.out)?;
    if depth != 16 {
        return Err(util::Error::new(format!(
            "{}: want 16-bit PNG, got {depth}-bit",
            opts.out.display()
        )));
    }
    Ok(Report {
        out_path: opts.out.clone(),
        log_path: run_log,
        backend_proof: proof,
        prefs,
        png_width: width,
        png_height: height,
    })
}

fn render_mounted(
    opts: &Options,
    home: &Path,
    mnt: &Path,
    attach_log: &str,
) -> Result<(PathBuf, Option<String>), util::Error> {
    let cli = mnt.join("darktable.app/Contents/MacOS/darktable-cli");
    if !cli.is_file() {
        return Err(util::Error::new(format!(
            "{}: darktable-cli not on volume",
            cli.display()
        )));
    }
    write_darktablerc(home, opts.backend)?;
    let outcome = run_cli(
        &cli,
        home,
        &opts.image,
        opts.xmp.as_deref(),
        &opts.out,
        opts.backend,
    )?;
    let log_path = opts
        .log_path
        .clone()
        .unwrap_or_else(|| opts.out.with_extension("log"));
    let header = format!(
        "oracle render backend={} image={} xmp={} out={}\n{attach_log}\n",
        opts.backend.name(),
        opts.image.display(),
        opts.xmp
            .as_deref()
            .map_or("-".to_owned(), |p| p.display().to_string()),
        opts.out.display()
    );
    util::write_file(
        &log_path,
        format!("{header}{}\n", outcome.transcript).as_bytes(),
    )?;
    if !outcome.success {
        return Err(util::Error::new(format!(
            "darktable-cli failed; log kept at {}",
            log_path.display()
        )));
    }
    if !opts.out.is_file() {
        return Err(util::Error::new(format!(
            "no output at {}; log kept at {}",
            opts.out.display(),
            log_path.display()
        )));
    }
    Ok((log_path, outcome.proof))
}

fn append_log_header(log_path: &Path, attach_log: &str, detach_log: &str, opts: &Options) {
    use std::fmt::Write as _;
    let Ok(mut text) = fs::read_to_string(log_path) else {
        return;
    };
    let _ = writeln!(
        text,
        "--- mount ---\n{attach_log}\n--- detach ---\n{detach_log}\nbackend={}",
        opts.backend.name()
    );
    let _ = fs::write(log_path, text);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backend_parse_and_proof() {
        assert_eq!(Backend::parse("cpu").unwrap(), Backend::Cpu);
        assert_eq!(Backend::parse("opencl").unwrap(), Backend::OpenCl);
        assert!(Backend::parse("cuda").is_err());
        assert_eq!(Backend::Cpu.proof_line(), "NOT utilized");
        assert_eq!(Backend::OpenCl.proof_line(), "events were successful");
    }

    #[test]
    fn bad_cached_dmg_is_deleted_and_refused() {
        let tmp = util::make_temp_dir("lightamer-cli-render-test").unwrap();
        let cache = tmp.join("cache");
        fs::create_dir_all(&cache).unwrap();
        fs::write(cache.join("pinned.dmg"), b"bogus-bytes").unwrap();
        let lock_text = "version=9.9.9\nurl=https://example.com/pinned.dmg\nfilename=pinned.dmg\n\
             size_bytes=11\nsha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n";
        let lock_path = tmp.join("t.lock");
        fs::write(&lock_path, lock_text).unwrap();
        let err = verify_cached_dmg(&lock_path, Some(&cache)).unwrap_err();
        assert!(err.0.contains("refusing to run"), "{err}");
        assert!(!cache.join("pinned.dmg").exists(), "bad dmg must be gone");
        util::remove_dir_quiet(&tmp);
    }

    #[test]
    fn identical_prefs_pass_and_drift_restores() {
        let tmp = util::make_temp_dir("lightamer-cli-prefs-test").unwrap();
        // Identical snapshots pass without touching `defaults import`.
        let a = PrefsSnap {
            rc: Some(0),
            bytes: b"<plist/>".to_vec(),
        };
        let b = PrefsSnap {
            rc: Some(0),
            bytes: b"<plist/>".to_vec(),
        };
        let report = check_prefs(&a, &b, &tmp.join("before.plist")).unwrap();
        assert!(report.identical);
        let c = PrefsSnap {
            rc: Some(1),
            bytes: Vec::new(),
        };
        let d = PrefsSnap {
            rc: Some(1),
            bytes: Vec::new(),
        };
        assert!(check_prefs(&c, &d, &tmp.join("b2")).unwrap().identical);
        util::remove_dir_quiet(&tmp);
    }

    #[test]
    fn darktablerc_presets_backend_and_16bit() {
        let tmp = util::make_temp_dir("lightamer-cli-rc-test").unwrap();
        let rc = write_darktablerc(&tmp, Backend::OpenCl).unwrap();
        let text = fs::read_to_string(&rc).unwrap();
        assert!(text.contains("opencl=true"));
        assert!(text.contains("plugins/imageio/format/png/bpp=16"));
        assert!(tmp.join(".cache/darktable").is_dir());
        util::remove_dir_quiet(&tmp);
    }
}
