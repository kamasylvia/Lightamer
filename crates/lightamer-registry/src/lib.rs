// SPDX-License-Identifier: GPL-3.0-or-later
//! Aggregated module registry: every descriptor, lookup, default chains.
//!
//! Depends on the four domain crates and concatenates their `MODULES` tables.
//! This crate names no module of its own; the `check-no-iop-names` task fails
//! the build if a baseline module name ever appears here as a string literal.
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

use lightamer_iop_traits::ModuleDesc;

/// Every known descriptor, grouped by domain crate.
///
/// The order is a build detail (domain order, then module id); use
/// [`raw_chain`] or [`jpg_chain`] for pipe order.
#[must_use]
pub fn all_descs() -> Vec<&'static ModuleDesc> {
    lightamer_iop_raw::MODULES
        .iter()
        .chain(lightamer_iop_geom::MODULES.iter())
        .chain(lightamer_iop_color::MODULES.iter())
        .chain(lightamer_iop_display::MODULES.iter())
        .copied()
        .collect()
}

/// Finds a descriptor by id; [`None`] when unknown.
///
/// ```rust
/// assert!(lightamer_registry::find("__no_such_module__").is_none());
/// ```
///
/// Linear scan; fine at this scale (about a hundred modules).
#[must_use]
pub fn find(id: &str) -> Option<&'static ModuleDesc> {
    all_descs().into_iter().find(|desc| desc.id == id)
}

/// Compares two descriptors by the raw (`priority`, `tie`) key.
fn raw_cmp(a: &ModuleDesc, b: &ModuleDesc) -> std::cmp::Ordering {
    a.order
        .raw
        .priority
        .total_cmp(&b.order.raw.priority)
        .then_with(|| a.order.raw.tie.cmp(&b.order.raw.tie))
}

/// Compares two descriptors by the non-raw (`priority`, `tie`) key.
fn jpg_cmp(a: &ModuleDesc, b: &ModuleDesc) -> std::cmp::Ordering {
    a.order
        .jpg
        .priority
        .total_cmp(&b.order.jpg.priority)
        .then_with(|| a.order.jpg.tie.cmp(&b.order.jpg.tie))
}

/// Raw default chain: descriptors sorted by (`priority`, `tie`).
#[must_use]
pub fn raw_chain() -> Vec<&'static ModuleDesc> {
    let mut descs = all_descs();
    descs.sort_by(|a, b| raw_cmp(a, b));
    descs
}

/// Non-raw default chain: descriptors sorted by (`priority`, `tie`).
#[must_use]
pub fn jpg_chain() -> Vec<&'static ModuleDesc> {
    let mut descs = all_descs();
    descs.sort_by(|a, b| jpg_cmp(a, b));
    descs
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{all_descs, jpg_chain, raw_chain};
    use lightamer_iop_traits::ModuleDesc;

    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }

    #[test]
    fn chains_cover_every_descriptor_without_duplicates() {
        let all = all_descs();
        for chain in [raw_chain(), jpg_chain()] {
            assert_eq!(chain.len(), all.len());
            let mut ids: Vec<&str> = chain.iter().map(|desc| desc.id).collect();
            ids.sort_unstable();
            ids.dedup();
            assert_eq!(ids.len(), all.len());
        }
    }

    /// Whether `chain` is ordered by the raw (or jpg) key, compared as bits.
    fn is_sorted(chain: &[&ModuleDesc], raw: bool) -> bool {
        let keys: Vec<(u32, u16)> = chain
            .iter()
            .map(|desc| {
                let key = if raw { desc.order.raw } else { desc.order.jpg };
                (key.priority.to_bits(), key.tie)
            })
            .collect();
        let mut sorted = keys.clone();
        sorted.sort_unstable();
        keys == sorted
    }

    /// One fixture row: both keys of one module, in raw-table row order.
    struct FixtureRow {
        name: String,
        raw_prio: f32,
        raw_tie: u16,
        jpg_prio: f32,
        jpg_tie: u16,
    }

    /// Reads the one `dt-order-*.json` fixture (twin of the xtask parser;
    /// tests cannot import that binary crate, so the parse is duplicated).
    fn fixture_rows() -> Vec<FixtureRow> {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures");
        let mut found = Vec::new();
        for entry in std::fs::read_dir(&dir).expect("fixtures dir") {
            let path = entry.expect("fixture entry").path();
            let name = path
                .file_name()
                .expect("file name")
                .to_string_lossy()
                .into_owned();
            let is_fixture = path
                .extension()
                .is_some_and(|ext| ext.eq_ignore_ascii_case("json"));
            if is_fixture && name.starts_with("dt-order-") {
                found.push(path);
            }
        }
        assert_eq!(found.len(), 1, "exactly one order fixture: {found:?}");
        let text = std::fs::read_to_string(&found[0]).expect("fixture text");
        let mut rows = Vec::new();
        for line in text.lines().filter(|line| line.contains("\"name\"")) {
            let name = string_field(line, "\"name\"");
            let raw_prio = number_field(line, "\"raw_prio\"")
                .parse::<f32>()
                .expect("raw_prio");
            let jpg_prio = number_field(line, "\"jpg_prio\"")
                .parse::<f32>()
                .expect("jpg_prio");
            let raw_tie = number_field(line, "\"raw_tie\"")
                .parse::<u16>()
                .expect("raw_tie");
            let jpg_tie = number_field(line, "\"jpg_tie\"")
                .parse::<u16>()
                .expect("jpg_tie");
            rows.push(FixtureRow {
                name,
                raw_prio,
                raw_tie,
                jpg_prio,
                jpg_tie,
            });
        }
        assert!(!rows.is_empty(), "fixture holds no rows");
        rows
    }

    /// Value of `"key": "<value>"` on one fixture line.
    fn string_field(line: &str, key: &str) -> String {
        let after = after_key(line, key);
        let rest = after.strip_prefix('"').expect("string value");
        let end = rest.find('"').expect("string end");
        rest[..end].to_owned()
    }

    /// Value of `"key": <number>` on one fixture line.
    fn number_field(line: &str, key: &str) -> String {
        let token: String = after_key(line, key)
            .chars()
            .take_while(|chr| chr.is_ascii_digit() || *chr == '.')
            .collect();
        assert!(!token.is_empty() && token != ".", "{key}: expected number");
        token
    }

    /// Text after `"key":` on one fixture line.
    fn after_key<'a>(line: &'a str, key: &str) -> &'a str {
        let pos = line.find(key).expect("key present");
        let rest = &line[pos + key.len()..];
        let colon = rest.find(':').expect("colon present");
        rest[colon + 1..].trim_start()
    }

    #[test]
    fn raw_chain_matches_fixture_position_by_position() {
        let mut fixture = fixture_rows();
        // The C table rows are not priority-monotonic (e.g. 36.0 sits past
        // 37.0); pipe order is the (priority, tie) sort, not the row order.
        fixture.sort_by(|a, b| {
            a.raw_prio
                .total_cmp(&b.raw_prio)
                .then_with(|| a.raw_tie.cmp(&b.raw_tie))
        });
        let chain = raw_chain();
        assert_eq!(chain.len(), fixture.len(), "raw chain length");
        for (index, (desc, row)) in chain.iter().zip(fixture.iter()).enumerate() {
            assert_eq!(desc.id, row.name, "raw position {index}");
            assert_eq!(
                desc.order.raw.priority.to_bits(),
                row.raw_prio.to_bits(),
                "raw prio {index}"
            );
            assert_eq!(desc.order.raw.tie, row.raw_tie, "raw tie {index}");
        }
    }

    #[test]
    fn jpg_chain_matches_fixture_position_by_position() {
        let mut fixture = fixture_rows();
        fixture.sort_by(|a, b| {
            a.jpg_prio
                .total_cmp(&b.jpg_prio)
                .then_with(|| a.jpg_tie.cmp(&b.jpg_tie))
        });
        let chain = jpg_chain();
        assert_eq!(chain.len(), fixture.len(), "jpg chain length");
        for (index, (desc, row)) in chain.iter().zip(fixture.iter()).enumerate() {
            assert_eq!(desc.id, row.name, "jpg position {index}");
            assert_eq!(
                desc.order.jpg.priority.to_bits(),
                row.jpg_prio.to_bits(),
                "jpg prio {index}"
            );
            assert_eq!(desc.order.jpg.tie, row.jpg_tie, "jpg tie {index}");
        }
    }

    #[test]
    fn swapped_tie_changes_raw_order() {
        let chain = raw_chain();
        let pair = chain
            .windows(2)
            .position(|pair| {
                pair[0].order.raw.priority.to_bits() == pair[1].order.raw.priority.to_bits()
            })
            .expect("baseline holds a shared raw priority");
        let (before_first, before_second) = (chain[pair].id, chain[pair + 1].id);
        let mut reordered: Vec<ModuleDesc> = chain.iter().map(|desc| **desc).collect();
        let tie = reordered[pair].order.raw.tie;
        reordered[pair].order.raw.tie = reordered[pair + 1].order.raw.tie;
        reordered[pair + 1].order.raw.tie = tie;
        reordered.sort_by(super::raw_cmp);
        let pos = |id: &str| {
            reordered
                .iter()
                .position(|desc| desc.id == id)
                .expect("id kept")
        };
        assert!(
            pos(before_second) < pos(before_first),
            "swapped ties must flip the pair order"
        );
    }

    #[test]
    fn ids_are_unique() {
        let all = all_descs();
        let mut ids: Vec<&str> = all.iter().map(|desc| desc.id).collect();
        ids.sort_unstable();
        let len = ids.len();
        ids.dedup();
        assert_eq!(ids.len(), len, "duplicate module ids");
    }

    #[test]
    fn chains_are_sorted_by_priority_then_tie() {
        assert!(is_sorted(&raw_chain(), true));
        assert!(is_sorted(&jpg_chain(), false));
    }
}
