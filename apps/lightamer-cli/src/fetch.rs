// SPDX-License-Identifier: GPL-3.0-or-later
//! Oracle DMG pinning: lock file, single-file cache, `curl` download, `shasum` verify.

use crate::util::{self, Error};
use std::fs;
use std::path::{Path, PathBuf};

/// Env var overriding the default oracle cache dir.
pub const CACHE_ENV: &str = "LIGHTAMER_ORACLE_CACHE";

/// Default cache dir under `$HOME`.
pub const CACHE_DEFAULT_REL: &str = "Library/Caches/lightamer-oracle";

/// Parsed `Scripts/oracle.lock`.
#[derive(Debug, Clone)]
pub struct Lock {
    /// Pinned darktable release, e.g. `5.6.2`.
    pub version: String,
    /// DMG download URL.
    pub url: String,
    /// Cache file name.
    pub filename: String,
    /// Exact DMG byte size.
    pub size_bytes: u64,
    /// Lowercase hex sha256 of the DMG.
    pub sha256: String,
}

/// Parse lock text (`key=value` lines, `#` comments, blank lines ignored).
///
/// # Errors
///
/// Returns [`Error`] on malformed lines, unknown keys, bad values, or missing keys.
pub fn parse_lock(text: &str) -> Result<Lock, Error> {
    let mut version: Option<String> = None;
    let mut url: Option<String> = None;
    let mut filename: Option<String> = None;
    let mut size_bytes: Option<u64> = None;
    let mut sha256: Option<String> = None;
    for (lineno, raw) in text.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let (key, value) = line
            .split_once('=')
            .ok_or_else(|| Error::new(format!("lock line {}: want key=value", lineno + 1)))?;
        let value = value.trim().to_owned();
        match key.trim() {
            "version" => version = Some(value),
            "url" => url = Some(value),
            "filename" => {
                if value.contains('/') || value.is_empty() {
                    return Err(Error::new(format!(
                        "lock line {}: bad filename",
                        lineno + 1
                    )));
                }
                filename = Some(value);
            }
            "size_bytes" => {
                let n: u64 = value
                    .parse()
                    .map_err(|_| Error::new(format!("lock line {}: bad size_bytes", lineno + 1)))?;
                size_bytes = Some(n);
            }
            "sha256" => {
                let hex = value.to_lowercase();
                let ok = hex.len() == 64 && hex.bytes().all(|b| b.is_ascii_hexdigit());
                if !ok {
                    return Err(Error::new(format!("lock line {}: bad sha256", lineno + 1)));
                }
                sha256 = Some(hex);
            }
            unknown => {
                return Err(Error::new(format!(
                    "lock line {}: unknown key {unknown}",
                    lineno + 1
                )));
            }
        }
    }
    Ok(Lock {
        version: version.ok_or_else(|| Error::new("lock: missing version"))?,
        url: url.ok_or_else(|| Error::new("lock: missing url"))?,
        filename: filename.ok_or_else(|| Error::new("lock: missing filename"))?,
        size_bytes: size_bytes.ok_or_else(|| Error::new("lock: missing size_bytes"))?,
        sha256: sha256.ok_or_else(|| Error::new("lock: missing sha256"))?,
    })
}

/// Read and parse a lock file.
///
/// # Errors
///
/// Returns [`Error`] when the file cannot be read or parsed.
pub fn read_lock(path: &Path) -> Result<Lock, Error> {
    parse_lock(&util::read_to_string(path)?)
}

/// Resolve the cache dir: explicit override, `$LIGHTAMER_ORACLE_CACHE`, or default.
///
/// # Errors
///
/// Returns [`Error`] when no override/env is set and `$HOME` is missing.
pub fn cache_dir(override_dir: Option<&Path>) -> Result<PathBuf, Error> {
    if let Some(dir) = override_dir {
        return Ok(dir.to_owned());
    }
    if let Some(env) = std::env::var_os(CACHE_ENV) {
        return Ok(PathBuf::from(env));
    }
    util::home_dir()
        .map(|h| h.join(CACHE_DEFAULT_REL))
        .ok_or_else(|| Error::new("no cache dir: set LIGHTAMER_ORACLE_CACHE or $HOME"))
}

/// Verify size + sha256 (via system `shasum`) of a file against the lock.
///
/// # Errors
///
/// Returns [`Error`] when the file is missing, the size differs, `shasum`
/// fails, or the hash differs.
pub fn verify_file(path: &Path, lock: &Lock) -> Result<(), Error> {
    let len = fs::metadata(path)
        .map_err(|e| util::io_error(path, e))?
        .len();
    if len != lock.size_bytes {
        return Err(Error::new(format!(
            "size mismatch for {}: got {len}, want {}",
            path.display(),
            lock.size_bytes
        )));
    }
    let path_arg = path.to_string_lossy().into_owned();
    let out = util::run_capture("shasum", &["-a", "256", &path_arg], &[])?;
    if !out.success {
        return Err(Error::new(format!(
            "shasum failed for {}: {}",
            path.display(),
            util::stderr_tail(&out, 500)
        )));
    }
    let stdout = String::from_utf8_lossy(&out.stdout);
    let got = stdout
        .split_whitespace()
        .next()
        .unwrap_or("")
        .to_lowercase();
    if got != lock.sha256 {
        return Err(Error::new(format!(
            "sha256 mismatch for {}: got {got}, want {}",
            path.display(),
            lock.sha256
        )));
    }
    Ok(())
}

/// Remove every `*.dmg` in `cache` except `keep`; returns removed names.
///
/// # Errors
///
/// Returns [`Error`] when the cache dir cannot be listed or a file cannot be removed.
#[expect(clippy::case_sensitive_file_extension_comparisons)] // we only manage our own lowercase names
pub fn prune_cache(cache: &Path, keep: &str) -> Result<Vec<String>, Error> {
    let mut removed = Vec::new();
    let entries = fs::read_dir(cache).map_err(|e| util::io_error(cache, e))?;
    for entry in entries {
        let entry = entry.map_err(|e| util::io_error(cache, e))?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if name == keep || !name.ends_with(".dmg") {
            continue;
        }
        let path = entry.path();
        if path.is_file() {
            fs::remove_file(&path).map_err(|e| util::io_error(&path, e))?;
            removed.push(name);
        }
    }
    Ok(removed)
}

fn download(lock: &Lock, part: &Path) -> Result<(), Error> {
    let part_arg = part.to_string_lossy().into_owned();
    let out = util::run_capture(
        "curl",
        &["-fSL", "--retry", "2", "-o", &part_arg, &lock.url],
        &[],
    )?;
    if !out.success {
        return Err(Error::new(format!(
            "curl failed for {}: {}",
            lock.url,
            util::stderr_tail(&out, 800)
        )));
    }
    Ok(())
}

/// Ensure the pinned DMG is verified in the cache, downloading once when needed.
///
/// A bad `.part` file is always removed; on success the cache holds exactly
/// one DMG (older ones are pruned).
///
/// # Errors
///
/// Returns [`Error`] on download or verification failure.
pub fn ensure_dmg(lock: &Lock, cache: &Path) -> Result<PathBuf, Error> {
    fs::create_dir_all(cache).map_err(|e| util::io_error(cache, e))?;
    let dest = cache.join(&lock.filename);
    if dest.is_file() {
        match verify_file(&dest, lock) {
            Ok(()) => {
                prune_cache(cache, &lock.filename)?;
                return Ok(dest);
            }
            Err(e) => {
                eprintln!("fetch: cached dmg failed verify ({e}); re-downloading");
                let _ = fs::remove_file(&dest);
            }
        }
    }
    let part = cache.join(format!("{}.part-{}", lock.filename, std::process::id()));
    let _ = fs::remove_file(&part);
    let result = download(lock, &part).and_then(|()| verify_file(&part, lock));
    match result {
        Ok(()) => {
            fs::rename(&part, &dest).map_err(|e| util::io_error(&dest, e))?;
            prune_cache(cache, &lock.filename)?;
            Ok(dest)
        }
        Err(e) => {
            let _ = fs::remove_file(&part);
            Err(e)
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::*;

    const SAMPLE: &str = "# comment\n\nversion=5.6.2\nurl=https://example.com/a.dmg\n\
         filename=a.dmg\nsize_bytes=8\n\
         sha256=9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08\n";

    #[test]
    fn parses_sample_lock() {
        let lock = parse_lock(SAMPLE).unwrap();
        assert_eq!(lock.version, "5.6.2");
        assert_eq!(lock.size_bytes, 8);
        assert_eq!(lock.filename, "a.dmg");
    }

    #[test]
    fn rejects_unknown_key_and_bad_hash() {
        assert!(parse_lock("bogus=1\n").is_err());
        assert!(parse_lock("sha256=xyz\nversion=1\nurl=u\nfilename=f\nsize_bytes=1\n").is_err());
        assert!(parse_lock("version=1\n").is_err());
    }

    #[test]
    fn cache_dir_prefers_override_then_env() {
        let dir = cache_dir(Some(Path::new("/tmp/x"))).unwrap();
        assert_eq!(dir, Path::new("/tmp/x"));
    }

    #[test]
    fn verify_accepts_test_vector_and_rejects_tamper() {
        let tmp = util::make_temp_dir("lightamer-cli-fetch-test").unwrap();
        let file = tmp.join("t.bin");
        fs::write(&file, b"test").unwrap();
        let mut lock = parse_lock(SAMPLE).unwrap();
        lock.filename = "t.bin".to_owned();
        lock.size_bytes = 4;
        // sha256("test") =
        // 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08
        assert!(verify_file(&file, &lock).is_ok());
        fs::write(&file, b"tampered!").unwrap();
        assert!(verify_file(&file, &lock).is_err());
        util::remove_dir_quiet(&tmp);
    }

    #[test]
    fn prune_keeps_only_pinned_dmg() {
        let tmp = util::make_temp_dir("lightamer-cli-prune-test").unwrap();
        fs::write(tmp.join("a.dmg"), b"x").unwrap();
        fs::write(tmp.join("old.dmg"), b"x").unwrap();
        fs::write(tmp.join("note.txt"), b"x").unwrap();
        let removed = prune_cache(&tmp, "a.dmg").unwrap();
        assert_eq!(removed, vec!["old.dmg".to_owned()]);
        assert!(tmp.join("a.dmg").exists() && tmp.join("note.txt").exists());
        util::remove_dir_quiet(&tmp);
    }
}
