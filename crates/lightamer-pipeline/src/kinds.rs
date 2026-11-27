// SPDX-License-Identifier: GPL-3.0-or-later
//! Pipe kinds and their quotas.
//!
//! darktable runs five pipe types off one struct
//! (`dt_dev_pixelpipe_type_t`, `src/develop/pixelpipe.h:42-63`); B1 stands up
//! four (the second preview pipe has no counterpart yet). Quotas below are
//! **initial values, retuned after B1-b measures**: memory budget, largest
//! single tile, and cached planes retained.

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

/// Per-kind quotas.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PipeQuota {
    /// Memory budget in bytes.
    pub memory_budget: u64,
    /// Largest single tile in bytes.
    pub max_tile_bytes: u64,
    /// Cached planes retained.
    pub cache_slots: u32,
}

/// Quota for one kind. Initial values; B1-b retunes after measuring.
#[must_use]
pub const fn quota(kind: PipeKind) -> PipeQuota {
    const GIB: u64 = 1024 * 1024 * 1024;
    const MIB: u64 = 1024 * 1024;
    match kind {
        PipeKind::Full => PipeQuota {
            memory_budget: 4 * GIB,
            max_tile_bytes: 256 * MIB,
            cache_slots: 8,
        },
        PipeKind::Export => PipeQuota {
            memory_budget: 4 * GIB,
            max_tile_bytes: 256 * MIB,
            cache_slots: 4,
        },
        PipeKind::Preview => PipeQuota {
            memory_budget: GIB,
            max_tile_bytes: 64 * MIB,
            cache_slots: 4,
        },
        PipeKind::Thumbnail => PipeQuota {
            memory_budget: 512 * MIB,
            max_tile_bytes: 16 * MIB,
            cache_slots: 2,
        },
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{PipeKind, quota};

    #[test]
    fn quotas_are_sane_and_ordered() {
        let full = quota(PipeKind::Full);
        let export = quota(PipeKind::Export);
        let preview = quota(PipeKind::Preview);
        let thumb = quota(PipeKind::Thumbnail);
        // Full and export share the top budget; preview and thumbnail step down.
        assert_eq!(full.memory_budget, export.memory_budget);
        assert!(full.memory_budget > preview.memory_budget);
        assert!(preview.memory_budget > thumb.memory_budget);
        assert!(full.max_tile_bytes <= full.memory_budget);
        assert!(thumb.max_tile_bytes <= thumb.memory_budget);
        assert!(full.cache_slots >= export.cache_slots);
        assert!(preview.cache_slots >= thumb.cache_slots);
    }
}
