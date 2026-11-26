// SPDX-License-Identifier: GPL-3.0-or-later
//! Stored photo paths: in-session relative vs external absolute.
//!
//! `photos.path_kind = 0` stores a path relative to the session root
//! (`Capture/…`, always `/`-separated); `= 1` stores an absolute path to a
//! referenced file outside the session. Both directions are lexical (no
//! file-system access, so missing files convert fine), and anything that
//! would quietly resolve outside the session root is refused instead of
//! being normalized into place.

use std::path::{Component, Path, PathBuf};

use crate::error::CatalogError;

/// Which form a stored photo path takes (mirrors `photos.path_kind`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PathKind {
    /// Relative to the session root (`path_kind = 0`).
    InSession,
    /// Absolute path to a file outside the session (`path_kind = 1`).
    External,
}

impl PathKind {
    /// The `photos.path_kind` integer for this kind.
    #[must_use]
    pub fn as_db(self) -> i64 {
        match self {
            Self::InSession => 0,
            Self::External => 1,
        }
    }

    /// Parses a `photos.path_kind` integer; `None` for anything but 0 or 1.
    #[must_use]
    pub fn from_db(value: i64) -> Option<Self> {
        match value {
            0 => Some(Self::InSession),
            1 => Some(Self::External),
            _ => None,
        }
    }
}

/// Converts an on-disk path to its stored form: under the session root it
/// becomes [`PathKind::InSession`] plus the root-relative path, anywhere
/// else [`PathKind::External`] plus the absolute path. A relative input is
/// read against the session root. Redundant separators and `.` segments are
/// cleaned; `..` that stays inside resolves, `..` that would leave the root
/// (or the file-system root) is refused.
///
/// # Errors
///
/// [`CatalogError::BadPath`] when the path cannot be represented (empty,
/// escapes the session root, or has a non-Unicode form this build refuses).
pub fn to_stored(root: &Path, path: &Path) -> Result<(PathKind, String), CatalogError> {
    if path.is_absolute() {
        let cleaned = clean_absolute(path)?;
        if root.is_absolute() {
            let clean_root = clean_absolute(root)?;
            if let Ok(relative) = cleaned.strip_prefix(&clean_root) {
                let stored = join_components(relative)?;
                if stored.is_empty() {
                    return Err(CatalogError::BadPath(
                        "the session root itself is not a photo path".to_owned(),
                    ));
                }
                return Ok((PathKind::InSession, stored));
            }
        }
        return Ok((PathKind::External, cleaned.to_string_lossy().into_owned()));
    }
    Ok((PathKind::InSession, clean_relative(path)?))
}
/// Resolves a stored path back to an absolute path: [`PathKind::InSession`]
/// joins the root-relative form onto the root, [`PathKind::External`]
/// re-validates the absolute form. Anything that would land outside the
/// root (in-session) or is not absolute (external) is refused.
///
/// # Errors
///
/// [`CatalogError::BadPath`] when the stored text is not a valid path of
/// its kind.
pub fn to_absolute(root: &Path, kind: PathKind, stored: &str) -> Result<PathBuf, CatalogError> {
    match kind {
        PathKind::InSession => {
            let cleaned = clean_relative(Path::new(stored))?;
            Ok(root.join(cleaned))
        }
        PathKind::External => {
            let path = Path::new(stored);
            if !path.is_absolute() {
                return Err(CatalogError::BadPath(format!(
                    "external stored path is not absolute: {stored}"
                )));
            }
            clean_absolute(path)
        }
    }
}

/// Lexically cleans a relative path to `/`-separated stored form, refusing
/// anything absolute, empty, or escaping above its start.
fn clean_relative(path: &Path) -> Result<String, CatalogError> {
    if path.is_absolute() {
        return Err(CatalogError::BadPath(format!(
            "in-session path must be relative: {}",
            path.display()
        )));
    }
    let cleaned = join_components(path)?;
    if cleaned.is_empty() {
        return Err(CatalogError::BadPath("in-session path is empty".to_owned()));
    }
    Ok(cleaned)
}

/// Lexically cleans an absolute path (resolves `.`/`..`, drops redundant
/// separators), refusing `..` above the file-system root.
fn clean_absolute(path: &Path) -> Result<PathBuf, CatalogError> {
    if !path.is_absolute() {
        return Err(CatalogError::BadPath(format!(
            "expected an absolute path: {}",
            path.display()
        )));
    }
    let mut parts: Vec<String> = Vec::new();
    for component in path.components() {
        match component {
            Component::Prefix(prefix) => {
                return Err(CatalogError::BadPath(format!(
                    "non-Unix path prefix is not supported: {}",
                    prefix.as_os_str().to_string_lossy()
                )));
            }
            Component::RootDir | Component::CurDir => {}
            Component::ParentDir => {
                if parts.pop().is_none() {
                    return Err(CatalogError::BadPath(format!(
                        "path escapes the file-system root: {}",
                        path.display()
                    )));
                }
            }
            Component::Normal(part) => {
                parts.push(part.to_string_lossy().into_owned());
            }
        }
    }
    let mut cleaned = PathBuf::from("/");
    for part in &parts {
        cleaned.push(part);
    }
    Ok(cleaned)
}

/// Joins normal components with `/`, resolving `.`/`..` lexically and
/// refusing prefixes, roots, and escapes above the start.
fn join_components(path: &Path) -> Result<String, CatalogError> {
    let mut parts: Vec<String> = Vec::new();
    for component in path.components() {
        match component {
            Component::Prefix(_) | Component::RootDir => {
                return Err(CatalogError::BadPath(format!(
                    "in-session path must be relative: {}",
                    path.display()
                )));
            }
            Component::CurDir => {}
            Component::ParentDir => {
                if parts.pop().is_none() {
                    return Err(CatalogError::BadPath(format!(
                        "in-session path escapes the session root: {}",
                        path.display()
                    )));
                }
            }
            Component::Normal(part) => {
                parts.push(part.to_string_lossy().into_owned());
            }
        }
    }
    Ok(parts.join("/"))
}
