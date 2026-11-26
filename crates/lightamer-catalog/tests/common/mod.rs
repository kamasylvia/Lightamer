// SPDX-License-Identifier: GPL-3.0-or-later
//! Scratch directories: every test builds its own session roots under the
//! system temp dir and removes them afterwards. Nothing here ever touches
//! the real Application Support dir or the user's photo library.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT: AtomicU64 = AtomicU64::new(0);

/// A fresh empty directory for one test, removed when dropped (also on
/// test failure: `Drop` runs during unwinding).
pub struct ScratchDir {
    path: PathBuf,
}

impl ScratchDir {
    /// Creates `lightamer-catalog-test-<pid>-<n>-<tag>` under the temp dir.
    pub fn new(tag: &str) -> Result<Self, Box<dyn std::error::Error>> {
        let n = NEXT.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "lightamer-catalog-test-{}-{n}-{tag}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&path);
        std::fs::create_dir_all(&path)?;
        Ok(Self { path })
    }

    /// The scratch root.
    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for ScratchDir {
    fn drop(&mut self) {
        let ours = self
            .path
            .file_name()
            .and_then(|name| name.to_str())
            .is_some_and(|name| name.starts_with("lightamer-catalog-test-"));
        if ours {
            let _ = std::fs::remove_dir_all(&self.path);
        }
    }
}

// Only some test targets use every helper; each target compiles this module
// separately, so unused-here helpers would warn elsewhere.
#[allow(dead_code)]
/// Lists every file under `dir` as root-relative `/`-separated paths.
pub fn relative_file_list(dir: &Path) -> Result<Vec<String>, Box<dyn std::error::Error>> {
    let mut out = Vec::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(top) = stack.pop() {
        let mut entries: Vec<PathBuf> = Vec::new();
        for entry in std::fs::read_dir(&top)? {
            entries.push(entry?.path());
        }
        entries.sort();
        for path in entries {
            if path.is_dir() {
                stack.push(path);
            } else if let Ok(relative) = path.strip_prefix(dir) {
                out.push(
                    relative
                        .components()
                        .map(|c| c.as_os_str().to_string_lossy().into_owned())
                        .collect::<Vec<_>>()
                        .join("/"),
                );
            }
        }
    }
    out.sort();
    Ok(out)
}
