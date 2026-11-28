// SPDX-License-Identifier: GPL-3.0-or-later
//! Which pipe runs a render: the commit-time render kind.
//!
//! darktable runs five pipe types off one struct
//! (`dt_dev_pixelpipe_type_t`, `src/develop/pixelpipe.h:41-57`); this pipe
//! stands up four (the second preview pipe has no counterpart yet).
//! Modules read the kind at commit for kind-gated behavior (hotpixels'
//! `markfixed` drops on thumbnail and export, like upstream's
//! `dt_pipe_is_thumb` / `dt_pipe_is_export` check in `commit_params`).

/// Which pipe runs: same shape, different quotas.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PipeKind {
    /// Full-resolution interactive pipe.
    Full,
    /// Export pipe.
    Export,
    /// Preview pipe.
    Preview,
    /// Thumbnail pipe.
    Thumbnail,
}
