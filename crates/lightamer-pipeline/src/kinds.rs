// SPDX-License-Identifier: GPL-3.0-or-later
//! Pipe kinds and their quotas.
//!
//! darktable runs five pipe types off one struct
//! (`dt_dev_pixelpipe_type_t`, `src/develop/pixelpipe.h:42-63`); B1 stands up
//! four (the second preview pipe has no counterpart yet).
//!
//! Memory budgets derive from physical RAM ([`quota_for`]): each kind takes a
//! fixed share of it within a floor and a cap. The B1-a constant table
//! ([`quota`]) survives only as the caps. The four shares add to 40% of
//! physical memory, so the four budgets together never exceed that pool — on
//! the 16 GiB dev machine the pool is 6.4 GiB, under the 9 GiB watchdog line
//! with room for the app around it.

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

/// Per-kind quotas: a memory budget plus how many planes the cache keeps.
///
/// B1-b2 removed the `max_tile_bytes` field this struct carried through B1-b:
/// tile sizes already derive from the live budget (`available / factor` with
/// the kind's floor in [`tiling::decide`](crate::tiling::decide)), a static
/// per-kind ceiling has no upstream counterpart (`tiling.c` sizes purely from
/// available memory), and keeping it would force invented precedence rules
/// for ceiling-vs-floor conflicts. One budget-driven sizing rule, no second
/// constraint.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PipeQuota {
    /// Memory budget in bytes.
    pub memory_budget: u64,
    /// Cached planes retained.
    pub cache_slots: u32,
}

/// Share of the 40% pool, in percent of physical memory: 16 + 16 + 5 + 3.
const SHARE_PCT: [(PipeKind, u32); 4] = [
    (PipeKind::Full, 16),
    (PipeKind::Export, 16),
    (PipeKind::Preview, 5),
    (PipeKind::Thumbnail, 3),
];
/// Quota for one kind. Initial values; B1-b retunes after measuring.
///
/// Since B1-b these are the **caps** ([`quota_for`] clamps to them); the live
/// budgets derive from physical memory.
#[must_use]
pub const fn quota(kind: PipeKind) -> PipeQuota {
    const GIB: u64 = 1024 * 1024 * 1024;
    const MIB: u64 = 1024 * 1024;
    match kind {
        PipeKind::Full => PipeQuota {
            memory_budget: 4 * GIB,
            cache_slots: 8,
        },
        PipeKind::Export => PipeQuota {
            memory_budget: 4 * GIB,
            cache_slots: 4,
        },
        PipeKind::Preview => PipeQuota {
            memory_budget: GIB,
            cache_slots: 4,
        },
        PipeKind::Thumbnail => PipeQuota {
            memory_budget: 512 * MIB,
            cache_slots: 2,
        },
    }
}

/// Derives every kind's budget from `total_phys_bytes` of physical RAM.
///
/// Each budget is `total * share / 100` clamped into `[floor, cap]` (floors
/// above, caps from [`quota`]). When the clamped values overflow the 40% pool
/// — only on machines too small for the floors — all four scale down
/// proportionally so their sum fits the pool exactly (floors yield; the pool
/// never does). `cache_slots` comes from [`quota`] unchanged.
///
/// Shares mirror darktable's `default` resource level
/// (`src/common/darktable.c:2334-2339`: 512/1024 of RAM for the pipe pool,
/// `data/darktableconfig.xml.in` `resourcelevel` defaulting to `default`),
/// tightened to 40% for the watchdog line; the thumbnail whole-pipe divisor
/// (`/ 3` in `dt_get_available_pipe_mem`, `pixelpipe_hb.c:359-376`) becomes
/// the thumbnail's 3% share here.
#[must_use]
pub fn quota_for(kind: PipeKind, total_phys_bytes: u64) -> PipeQuota {
    const POOL_PCT: u128 = 40;
    let pool = (u128::from(total_phys_bytes) * POOL_PCT / 100).min(u128::from(u64::MAX));
    let mut raw = [0u64; 4];
    let mut sum: u128 = 0;
    for (slot, (candidate, share)) in raw.iter_mut().zip(SHARE_PCT.iter()) {
        let want = u128::from(total_phys_bytes) * u128::from(*share) / 100;
        let floor = u128::from(floor_for(*candidate));
        let cap = u128::from(quota(*candidate).memory_budget);
        let clamped = want.clamp(floor, cap).min(u128::from(u64::MAX));
        // `clamp` bounds by `cap <= u64::MAX`, so this truncation keeps all bits.
        #[expect(clippy::cast_possible_truncation)]
        let clamped = clamped as u64;
        *slot = clamped;
        sum += u128::from(clamped);
    }
    let budgets = if sum > pool && sum > 0 {
        let mut scaled = [0u64; 4];
        for (slot, value) in scaled.iter_mut().zip(raw.iter()) {
            #[expect(clippy::cast_possible_truncation)]
            // bounded by u64::MAX just above, so no bits are lost
            let fit = (u128::from(*value) * pool / sum).min(u128::from(u64::MAX)) as u64;
            *slot = fit;
        }
        scaled
    } else {
        raw
    };
    let index = match kind {
        PipeKind::Full => 0,
        PipeKind::Export => 1,
        PipeKind::Preview => 2,
        PipeKind::Thumbnail => 3,
    };
    let mut memory_budget = 0;
    for (slot, value) in budgets.iter().enumerate() {
        if slot == index {
            memory_budget = *value;
        }
    }
    PipeQuota {
        memory_budget,
        cache_slots: quota(kind).cache_slots,
    }
}

/// Single-tile floor for the tiling decision at this kind and RAM size.
///
/// darktable floors `available / factor` at the global
/// `dt_get_singlebuffer_mem()` (`tiling.c:613-620`), whose `default` level is
/// `max(2 MiB, total / 128)` (`darktable.c:3081-3091` with fractions
/// `:2334-2339`). Full/export pipes keep that formula verbatim; preview and
/// thumbnail pipes step it down (÷256, ÷512): their frames are small, and a
/// full-size floor would force single tiles bigger than the frames they tile.
#[must_use]
pub fn singlebuffer_floor(kind: PipeKind, total_phys_bytes: u64) -> u64 {
    const TWO_MIB: u64 = 2 * 1024 * 1024;
    let divisor: u64 = match kind {
        PipeKind::Full | PipeKind::Export => 128,
        PipeKind::Preview => 256,
        PipeKind::Thumbnail => 512,
    };
    (total_phys_bytes / divisor).max(TWO_MIB)
}

/// Floor for one kind: full/export pipes hold two 61 MP working frames plus
/// cache headroom; preview holds one fitted frame plus a tile margin;
/// thumbnails are small. Floors yield when the pool cannot afford them.
fn floor_for(kind: PipeKind) -> u64 {
    const MIB: u64 = 1024 * 1024;
    match kind {
        PipeKind::Full | PipeKind::Export => 512 * MIB,
        PipeKind::Preview => 256 * MIB,
        PipeKind::Thumbnail => 128 * MIB,
    }
}

/// Physical RAM in bytes, via `sysconf` page counts.
///
/// # Errors
///
/// [`std::io::Error`] when the page count or size is unreadable (negative or
/// zero); the caller (engine setup, B1-c) falls back to a conservative
/// constant then.
/// Only `unsafe` in this crate: two `sysconf` reads. `sysconf` with
/// `_SC_PHYS_PAGES`/`_SC_PAGESIZE` takes no pointers and keeps no state; the
/// only failure mode is the `-1` return, handled above.
#[expect(unsafe_code)]
pub fn system_physical_memory() -> Result<u64, std::io::Error> {
    // SAFETY: no pointers cross the boundary; `-1` is handled below.
    let pages = unsafe { libc::sysconf(libc::_SC_PHYS_PAGES) };
    // SAFETY: no pointers cross the boundary; `-1` is handled below.
    let size = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
    let (Ok(pages), Ok(size)) = (u64::try_from(pages), u64::try_from(size)) else {
        return Err(std::io::Error::other(format!(
            "sysconf gives no physical memory (pages={pages}, size={size})"
        )));
    };
    if pages == 0 || size == 0 {
        return Err(std::io::Error::other(format!(
            "sysconf gives no physical memory (pages={pages}, size={size})"
        )));
    }
    Ok(pages.saturating_mul(size))
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{PipeKind, quota, quota_for, singlebuffer_floor, system_physical_memory};

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
        assert!(full.cache_slots >= export.cache_slots);
        assert!(preview.cache_slots >= thumb.cache_slots);
    }

    #[test]
    fn sixteen_gib_splits_the_pool_by_share() {
        const GIB: u64 = 1024 * 1024 * 1024;
        let total = 16 * GIB;
        let full = quota_for(PipeKind::Full, total).memory_budget;
        let export = quota_for(PipeKind::Export, total).memory_budget;
        let preview = quota_for(PipeKind::Preview, total).memory_budget;
        let thumb = quota_for(PipeKind::Thumbnail, total).memory_budget;
        // 16/16/5/3 % of 16 GiB, all above floors and below caps.
        assert_eq!(full, 2_748_779_069);
        assert_eq!(export, 2_748_779_069);
        assert_eq!(preview, 858_993_459);
        assert_eq!(thumb, 515_396_075);
        assert_eq!(full + export + preview + thumb, 6_871_947_672);
        // The pool is 40% of 16 GiB; that is 6.4 GiB, under the 9 GiB line.
        assert!(full + export + preview + thumb < 9 * GIB);
        // Non-budget quotas still come from the B1-a table.
        assert_eq!(quota_for(PipeKind::Full, total).cache_slots, 8);
        assert_eq!(quota_for(PipeKind::Thumbnail, total).cache_slots, 2);
    }

    #[test]
    fn huge_memory_clamps_to_caps_and_tiny_memory_fits_the_pool() {
        const GIB: u64 = 1024 * 1024 * 1024;
        // 1 TiB: every share exceeds its cap, so the table rules.
        let huge = 1024 * GIB;
        assert_eq!(
            quota_for(PipeKind::Full, huge).memory_budget,
            quota(PipeKind::Full).memory_budget
        );
        assert_eq!(
            quota_for(PipeKind::Thumbnail, huge).memory_budget,
            quota(PipeKind::Thumbnail).memory_budget
        );
        // 512 MiB: floors (1408 MiB) cannot fit 40% (204.8 MiB), so the pool
        // wins and the four budgets scale to fit it.
        let tiny = 512 * 1024 * 1024;
        let budgets = [
            quota_for(PipeKind::Full, tiny).memory_budget,
            quota_for(PipeKind::Export, tiny).memory_budget,
            quota_for(PipeKind::Preview, tiny).memory_budget,
            quota_for(PipeKind::Thumbnail, tiny).memory_budget,
        ];
        let pool = tiny * 40 / 100;
        assert!(budgets.iter().sum::<u64>() <= pool);
        assert!(budgets.iter().all(|b| *b > 0));
        // Proportionality survives the squeeze: full == export > preview > thumb.
        assert_eq!(budgets[0], budgets[1]);
        assert!(budgets[0] > budgets[2]);
        assert!(budgets[2] > budgets[3]);
    }

    #[test]
    fn singlebuffer_floors_step_down_with_pipe_size() {
        const MIB: u64 = 1024 * 1024;
        let total = 16 * 1024 * MIB;
        assert_eq!(singlebuffer_floor(PipeKind::Full, total), 128 * MIB);
        assert_eq!(singlebuffer_floor(PipeKind::Export, total), 128 * MIB);
        assert_eq!(singlebuffer_floor(PipeKind::Preview, total), 64 * MIB);
        assert_eq!(singlebuffer_floor(PipeKind::Thumbnail, total), 32 * MIB);
        // Small machines bottom out at darktable's 2 MiB floor.
        assert_eq!(singlebuffer_floor(PipeKind::Full, 100 * MIB), 2 * MIB);
        assert_eq!(singlebuffer_floor(PipeKind::Thumbnail, 100 * MIB), 2 * MIB);
    }

    #[test]
    fn physical_memory_reads_positive() {
        let total = system_physical_memory().unwrap();
        assert!(total > 0);
    }
}
