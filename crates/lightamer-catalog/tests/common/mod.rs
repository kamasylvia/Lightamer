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

// Only the history tests use these; each target compiles this module
// separately, so the imports stay inside the helpers (a top-level import
// would warn as unused in the targets that never call them).
#[allow(dead_code)]
/// Canonical JSON of the default settings.
pub fn default_settings_json() -> Result<String, Box<dyn std::error::Error>> {
    use lightamer_history::PhotoSettings;

    Ok(PhotoSettings::default().canonical_json()?)
}

#[allow(dead_code)]
/// Canonical JSON of default settings plus one integer parameter, so each
/// (`module`, `param`, `value`) triple is a distinct snapshot.
pub fn settings_json(
    module: &str,
    param: &str,
    value: i64,
) -> Result<String, Box<dyn std::error::Error>> {
    use std::collections::BTreeMap;

    use lightamer_history::{ModuleInstance, PhotoSettings, SettingValue};

    let mut settings = PhotoSettings::default();
    let mut params = BTreeMap::new();
    params.insert(param.to_owned(), SettingValue::Int(value));
    settings.instances.upsert(ModuleInstance {
        module: module.to_owned(),
        multi: 0,
        name: None,
        enabled: true,
        params,
    });
    Ok(settings.canonical_json()?)
}

#[allow(dead_code)]
/// Canonical JSON of default settings under another process number.
pub fn settings_json_with_process(process: u32) -> Result<String, Box<dyn std::error::Error>> {
    use lightamer_history::{PhotoSettings, ProcessVersion};

    let settings = PhotoSettings {
        process: ProcessVersion(process),
        ..PhotoSettings::default()
    };
    Ok(settings.canonical_json()?)
}
