// SPDX-License-Identifier: GPL-3.0-or-later
//! Cache keys and the plane cache.
//!
//! Each node's key folds everything its output depends on: the pipe kind, the
//! input identity, the process version, every upstream node's
//! position/id/multi/params (chained, so any upstream change re-keys this
//! node and all below it), and this node's input/output geometry (scales
//! bitwise). That mirrors darktable's
//! `_dev_pixelpipe_cache_basichash` + roi fold
//! (`src/develop/pixelpipe_cache.c:99-184`): image id, pipe type, per-piece
//! `piece->hash` (op + instance + params, `imageop.c:2562-2595`), folded roi.
//!
//! The hash is FNV-1a over a domain tag plus little-endian fields — the same
//! algorithm history's `hash64` uses, reimplemented here so the pipeline takes
//! no history dependency for one hash function. Test vectors below pin the
//! standard outputs.

use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::Arc;

use serde_json::{Map, Value};

use super::budgeted::SharedFrame;
use super::chain::{NodeGeometry, PipeNode};
use super::kinds::PipeKind;
use lightamer_iop_traits::{
    CfaColor, CfaPattern, ColorSpace, ImageInfo, PixelFormat as WireFormat, RawFacts,
};

/// FNV-1a offset basis (64-bit).
const FNV_OFFSET: u64 = 0xcbf2_9ce4_8422_2325;

/// FNV-1a prime (64-bit).
const FNV_PRIME: u64 = 0x0100_0000_01b3;

/// Domain tag: keeps pipe keys distinct from history hashes even if a byte
/// stream ever coincided.
const DOMAIN: &str = "lightamer.pipe.cache.v1";

/// FNV-1a over `bytes` from the offset basis.
fn fnv1a(bytes: &[u8]) -> u64 {
    let mut hash = FNV_OFFSET;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(FNV_PRIME);
    }
    hash
}

/// Continues `hash` over `bytes`.
fn mix(hash: u64, bytes: &[u8]) -> u64 {
    let mut out = hash;
    for byte in bytes {
        out ^= u64::from(*byte);
        out = out.wrapping_mul(FNV_PRIME);
    }
    out
}

/// Canonical bytes of one instance's parameters: JSON with object keys sorted
/// at every level, so equal parameters hash equally whatever insertion order
/// built them. Sorting is done here (not trusted to the map): the workspace
/// unifies `serde_json` with `preserve_order`, so `Map` keeps insertion order
/// and a plain `to_string` would key identical parameters differently.
fn canonical_params(params: &Map<String, Value>) -> String {
    let mut out = String::new();
    push_object(params, &mut out);
    out
}

/// Appends one JSON value in canonical form (sorted object keys, recursion).
fn push_value(value: &Value, out: &mut String) {
    match value {
        Value::Null => out.push_str("null"),
        Value::Bool(then) => out.push_str(if *then { "true" } else { "false" }),
        Value::Number(number) => out.push_str(&number.to_string()),
        Value::String(text) => out.push_str(&serde_json::to_string(text).unwrap_or_default()),
        Value::Array(items) => {
            out.push('[');
            for (index, item) in items.iter().enumerate() {
                if index > 0 {
                    out.push(',');
                }
                push_value(item, out);
            }
            out.push(']');
        }
        Value::Object(map) => push_object(map, out),
    }
}

/// Appends one JSON object in canonical form: entries sorted by key.
fn push_object(map: &Map<String, Value>, out: &mut String) {
    let mut entries: Vec<(&String, &Value)> = map.iter().collect();
    entries.sort_by(|left, right| left.0.cmp(right.0));
    out.push('{');
    for (index, (key, value)) in entries.iter().enumerate() {
        if index > 0 {
            out.push(',');
        }
        out.push_str(&serde_json::to_string(key).unwrap_or_default());
        out.push(':');
        push_value(value, out);
    }
    out.push('}');
}

/// One pipe kind's key tag.
fn kind_tag(kind: PipeKind) -> &'static str {
    match kind {
        PipeKind::Full => "full",
        PipeKind::Export => "export",
        PipeKind::Preview => "preview",
        PipeKind::Thumbnail => "thumbnail",
    }
}

/// Per-node cache keys for a committed render: `keys[i]` folds the render
/// identity (kind, input id, process version) plus nodes `0..=i`, each with
/// position, id, multi-instance index, canonical params, and both regions.
///
/// The result has one key per node; a shorter geometry slice truncates (the
/// renderer always passes matching slices, so truncation only guards).
///
/// Image facts fold as a fixed default here; renders pass their real facts
/// through [`chain_keys_with_image`].
#[must_use]
pub fn chain_keys(
    kind: PipeKind,
    input_id: u64,
    process: u32,
    nodes: &[PipeNode],
    geos: &[NodeGeometry],
) -> Vec<u64> {
    chain_keys_with_image(
        kind,
        input_id,
        process,
        &ImageInfo::new(0, 0, ColorSpace::Rgb),
        nodes,
        geos,
    )
}

/// Per-node cache keys with image facts folded in: same contract as
/// [`chain_keys`], plus the decoded size, input space, buffer format, and
/// RAW facts. Changed facts re-key the chain, repeated facts hit it;
/// floats fold by bits.
#[must_use]
pub fn chain_keys_with_image(
    kind: PipeKind,
    input_id: u64,
    process: u32,
    image: &ImageInfo,
    nodes: &[PipeNode],
    geos: &[NodeGeometry],
) -> Vec<u64> {
    let mut key = fnv1a(DOMAIN.as_bytes());
    key = mix(key, kind_tag(kind).as_bytes());
    key = mix(key, &input_id.to_le_bytes());
    key = mix(key, &process.to_le_bytes());
    key = mix_image(key, image);
    let mut keys = Vec::with_capacity(nodes.len());
    for (index, (node, geo)) in nodes.iter().zip(geos.iter()).enumerate() {
        // Fixed-width positions and lengths; saturation only guards platforms
        // where memory outgrows u64 (impossible in practice).
        let position = u64::try_from(index).unwrap_or(u64::MAX);
        key = mix(key, &position.to_le_bytes());
        let id_len = u64::try_from(node.id.len()).unwrap_or(u64::MAX);
        key = mix(key, &id_len.to_le_bytes());
        key = mix(key, node.id.as_bytes());
        key = mix(key, &node.multi.to_le_bytes());
        let params = canonical_params(&node.params);
        let params_len = u64::try_from(params.len()).unwrap_or(u64::MAX);
        key = mix(key, &params_len.to_le_bytes());
        key = mix(key, params.as_bytes());
        for roi in [&geo.input, &geo.output] {
            key = mix(key, &roi.x.to_le_bytes());
            key = mix(key, &roi.y.to_le_bytes());
            key = mix(key, &roi.width.to_le_bytes());
            key = mix(key, &roi.height.to_le_bytes());
            key = mix(key, &roi.scale.to_bits().to_le_bytes());
        }
        keys.push(key);
    }
    keys
}

/// Folds image facts into a running key: size, space and format tags, then
/// the RAW facts field by field (floats by bits, options tagged).
fn mix_image(mut key: u64, image: &ImageInfo) -> u64 {
    key = mix(key, &image.width.to_le_bytes());
    key = mix(key, &image.height.to_le_bytes());
    key = mix(key, &[space_tag(image.input_space)]);
    key = mix(key, &[format_tag(image.format)]);
    match &image.raw {
        None => mix(key, &[0]),
        Some(raw) => mix_raw(key, raw),
    }
}

/// One byte per colorspace, fixed here (never `as u8`: enum order is not
/// a stability contract).
fn space_tag(space: ColorSpace) -> u8 {
    match space {
        ColorSpace::None => 1,
        ColorSpace::Raw => 2,
        ColorSpace::Lab => 3,
        ColorSpace::Rgb => 4,
        ColorSpace::Lch => 5,
        ColorSpace::Hsl => 6,
        ColorSpace::Jzczhz => 7,
    }
}

/// One byte per wire format, fixed here like [`space_tag`].
fn format_tag(format: WireFormat) -> u8 {
    match format {
        WireFormat::RgbaF32Premul => 1,
        WireFormat::RgbaU8 => 2,
        WireFormat::RgbaU16 => 3,
        WireFormat::MonoF32 => 4,
    }
}

/// One byte per CFA color, fixed here like [`space_tag`].
fn cfa_tag(color: CfaColor) -> u8 {
    match color {
        CfaColor::Red => 1,
        CfaColor::Green => 2,
        CfaColor::Blue => 3,
        CfaColor::Cyan => 4,
        CfaColor::Magenta => 5,
        CfaColor::Yellow => 6,
        CfaColor::White => 7,
        CfaColor::FujiGreen => 8,
        CfaColor::Unknown => 9,
    }
}

/// Folds RAW facts field by field after a presence tag.
fn mix_raw(mut key: u64, raw: &RawFacts) -> u64 {
    key = mix(key, &[1]);
    for black in raw.black {
        key = mix(key, &black.to_le_bytes());
    }
    key = mix(key, &raw.white.to_le_bytes());
    key = mix_floats(key, &raw.wb);
    key = mix_opt_floats(key, raw.xyz_to_cam_d65.as_ref());
    key = mix_opt_floats(key, raw.cam_to_xyz_d65.as_ref());
    key = match &raw.cfa {
        CfaPattern::None => mix(key, &[0]),
        CfaPattern::Bayer(cells) => {
            key = mix(key, &[1]);
            for cell in cells {
                key = mix(key, &[cfa_tag(*cell)]);
            }
            key
        }
        CfaPattern::XTrans(cells) => {
            key = mix(key, &[2]);
            for cell in cells {
                key = mix(key, &[cfa_tag(*cell)]);
            }
            key
        }
    };
    key = mix(key, &raw.crop_x.to_le_bytes());
    key = mix(key, &raw.crop_y.to_le_bytes());
    key = mix(key, &raw.p_width.to_le_bytes());
    key = mix(key, &raw.p_height.to_le_bytes());
    key = mix(key, &raw.linear_response_limit.to_bits().to_le_bytes());
    for flag in [
        raw.hdr,
        raw.four_bayer,
        raw.s_raw,
        raw.monochrome,
        raw.monochrome_bayer,
        raw.load_ok,
        raw.camera_missing_sample,
    ] {
        key = mix(key, &[u8::from(flag)]);
    }
    key
}

/// Folds floats by bits: `0.0` and `-0.0` key apart, equal bits key together.
fn mix_floats<const N: usize>(mut key: u64, values: &[f32; N]) -> u64 {
    for v in values {
        key = mix(key, &v.to_bits().to_le_bytes());
    }
    key
}

/// Folds an optional float array after a presence tag.
fn mix_opt_floats<const N: usize>(mut key: u64, values: Option<&[f32; N]>) -> u64 {
    match values {
        None => mix(key, &[0]),
        Some(v) => {
            key = mix(key, &[1]);
            mix_floats(key, v)
        }
    }
}

/// Least-recently-used plane store, counted in bytes and slots.
///
/// Entries hold `Arc<SharedFrame>`: evicting drops the cache's handle, and
/// the budget bytes return when the last holder anywhere drops. Insertion
/// evicts the least recently used entries until the new plane fits both caps;
/// a plane bigger than the byte cap is refused (`false`) and the render that
/// made it still succeeds uncached.
#[derive(Debug, Default)]
pub struct PlaneCache {
    slots: usize,
    cap_bytes: u64,
    bytes: u64,
    entries: HashMap<u64, Arc<SharedFrame>>,
    /// Least recently used at the front, most recent at the back.
    order: VecDeque<u64>,
}

impl PlaneCache {
    /// An empty cache holding at most `slots` planes and `cap_bytes` of them.
    /// A zero slot count disables storing (every insert refuses).
    #[must_use]
    pub fn new(slots: u32, cap_bytes: u64) -> Self {
        Self {
            slots: usize::try_from(slots).unwrap_or(0),
            cap_bytes,
            bytes: 0,
            entries: HashMap::new(),
            order: VecDeque::new(),
        }
    }

    /// Entries currently held.
    #[must_use]
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// Whether no plane is cached.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Bytes currently cached.
    #[must_use]
    pub fn bytes(&self) -> u64 {
        self.bytes
    }

    /// Looks up `key` without touching recency. The renderer peeks mid-run
    /// and touches hits at once, so a hit stays most-recently-used even when
    /// a later node cancels or fails; completed planes keep their entries
    /// under content-determined keys, and only half-written work (a node that
    /// never finished) stays out.
    pub fn peek(&self, key: u64) -> Option<Arc<SharedFrame>> {
        self.entries.get(&key).map(Arc::clone)
    }

    /// Marks `key` most recently used. Unknown keys are ignored.
    pub fn touch(&mut self, key: u64) {
        if self.entries.contains_key(&key) {
            self.order.retain(|held| *held != key);
            self.order.push_back(key);
        }
    }

    /// Evicts the least-recently-used entry outside `protected`, returning its
    /// key. `None` when every entry is protected or the cache is empty.
    ///
    /// The renderer calls this before an allocation the budget refused:
    /// entries hit by the running render stay (their planes are its live
    /// inputs), everything else yields oldest-first until the plane fits.
    /// Evicting an entry whose plane nobody else holds returns its budget
    /// bytes; an entry held elsewhere just loses its cache seat. Mirrors
    /// upstream's oldest-line reuse (`_get_oldest_cacheline` /
    /// `_get_cacheline`, `pixelpipe_cache.c:208-255`).
    pub fn evict_oldest_except(&mut self, protected: &HashSet<u64>) -> Option<u64> {
        let victim = self
            .order
            .iter()
            .find(|key| !protected.contains(*key))
            .copied()?;
        self.remove(victim);
        Some(victim)
    }

    /// Stores `plane` under `key`, evicting least-recently-used entries until
    /// it fits both caps. Re-storing a key replaces the plane and refreshes
    /// recency. Returns whether the plane is cached (`false` = bigger than
    /// the byte cap, or a slot-less cache: the caller renders on uncached).
    pub fn insert(&mut self, key: u64, plane: Arc<SharedFrame>) -> bool {
        if self.slots == 0 {
            return false;
        }
        let bytes = plane.bytes();
        if bytes > self.cap_bytes {
            return false;
        }
        if self.entries.contains_key(&key) {
            self.remove(key);
        }
        while self.entries.len() >= self.slots || self.bytes.saturating_add(bytes) > self.cap_bytes
        {
            let Some(oldest) = self.order.pop_front() else {
                break;
            };
            self.remove(oldest);
        }
        self.bytes += bytes;
        self.entries.insert(key, plane);
        self.order.push_back(key);
        true
    }

    /// Drops every entry.
    pub fn clear(&mut self) {
        self.entries.clear();
        self.order.clear();
        self.bytes = 0;
    }

    /// Removes one entry, returning its bytes to the cache tally (the budget
    /// bytes follow the entry's last `Arc` holder, not this tally).
    fn remove(&mut self, key: u64) {
        if let Some(entry) = self.entries.remove(&key) {
            self.bytes = self.bytes.saturating_sub(entry.bytes());
            self.order.retain(|held| *held != key);
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use lightamer_geom::Roi as GeomRoi;
    use lightamer_raster::{FrameExtent, PixelFormat};
    use lightamer_sysmem::Budget;
    use serde_json::{Value, json};
    use std::collections::HashSet;
    use std::sync::Arc;

    use super::{DOMAIN, PlaneCache, chain_keys, fnv1a};
    use crate::PipeNode;
    use crate::budgeted::{SharedFrame, alloc_shared};
    use crate::chain::NodeGeometry;
    use crate::fakes::no_params;
    use crate::kinds::PipeKind;

    fn node(id: &str) -> PipeNode {
        PipeNode {
            id: id.to_owned(),
            multi: 0,
            params: no_params(),
        }
    }

    fn geo_pair(side: i32) -> NodeGeometry {
        let roi = GeomRoi::new(0, 0, side, side, 1.0).unwrap();
        NodeGeometry {
            input: roi,
            output: roi,
        }
    }

    #[test]
    fn fnv_vectors_match_the_standard() {
        assert_eq!(fnv1a(b""), 0xcbf2_9ce4_8422_2325);
        assert_eq!(fnv1a(b"foobar"), 0x8594_4171_f739_67e8);
        // The domain tag is folded, so it must be stable too.
        assert_eq!(fnv1a(DOMAIN.as_bytes()), fnv1a(DOMAIN.as_bytes()));
    }

    #[test]
    fn every_key_dimension_flips_the_key() {
        let nodes = vec![node("mod_a"), node("mod_b")];
        let geos = vec![geo_pair(8), geo_pair(8)];
        let base = chain_keys(PipeKind::Full, 7, 1, &nodes, &geos);
        assert_eq!(base.len(), 2);
        // Position: identical twins never share a key (position 0 folds
        // differently from position 1; the cumulative chain already separates
        // them, the explicit position fold pins it).
        let twins = vec![node("mod_a"), node("mod_a")];
        let twin_geos = vec![geo_pair(8), geo_pair(8)];
        let twin_keys = chain_keys(PipeKind::Full, 7, 1, &twins, &twin_geos);
        assert_ne!(twin_keys[0], twin_keys[1]);
        // Kind, input id, process version.
        assert_ne!(chain_keys(PipeKind::Preview, 7, 1, &nodes, &geos), base);
        assert_ne!(chain_keys(PipeKind::Full, 8, 1, &nodes, &geos), base);
        assert_ne!(chain_keys(PipeKind::Full, 7, 2, &nodes, &geos), base);
        // Second node's own id and multi index.
        let mut renamed = nodes.clone();
        renamed[1].id = "mod_c".to_owned();
        assert_ne!(
            chain_keys(PipeKind::Full, 7, 1, &renamed, &geos)[1],
            base[1]
        );
        let mut multi = nodes.clone();
        multi[1].multi = 3;
        assert_ne!(chain_keys(PipeKind::Full, 7, 1, &multi, &geos)[1], base[1]);
        // Second node's params (canonical JSON, insertion order irrelevant).
        let mut changed = nodes.clone();
        let mut params = no_params();
        params.insert("gain".to_owned(), json!({"type": "float", "value": 2.0}));
        changed[1].params = params;
        assert_ne!(
            chain_keys(PipeKind::Full, 7, 1, &changed, &geos)[1],
            base[1]
        );
        // Geometry: input region, output region, scale bits.
        let mut moved = geos.clone();
        moved[1].output = GeomRoi::new(1, 0, 8, 8, 1.0).unwrap();
        assert_ne!(chain_keys(PipeKind::Full, 7, 1, &nodes, &moved)[1], base[1]);
        let mut scaled = geos.clone();
        scaled[1].input = GeomRoi::new(0, 0, 8, 8, 0.5).unwrap();
        assert_ne!(
            chain_keys(PipeKind::Full, 7, 1, &nodes, &scaled)[1],
            base[1]
        );
    }

    #[test]
    fn upstream_change_rekeys_node_and_downstream_only() {
        let nodes = vec![node("mod_a"), node("mod_b"), node("mod_c")];
        let geos = vec![geo_pair(8), geo_pair(8), geo_pair(8)];
        let base = chain_keys(PipeKind::Full, 7, 1, &nodes, &geos);
        let mut changed = nodes.clone();
        let mut params = no_params();
        params.insert("on".to_owned(), json!({"type": "bool", "value": true}));
        changed[1].params = params;
        let next = chain_keys(PipeKind::Full, 7, 1, &changed, &geos);
        // The chain folds upstream-first: node 0 keeps its key, nodes 1-2 move.
        assert_eq!(next[0], base[0]);
        assert_ne!(next[1], base[1]);
        assert_ne!(next[2], base[2]);
    }

    #[test]
    fn params_key_ignores_insertion_order() {
        let mut first = no_params();
        first.insert("a".to_owned(), json!({"type": "int", "value": 1}));
        first.insert("b".to_owned(), json!({"type": "int", "value": 2}));
        let mut second = no_params();
        second.insert("b".to_owned(), json!({"type": "int", "value": 2}));
        second.insert("a".to_owned(), json!({"type": "int", "value": 1}));
        let nodes_first = vec![PipeNode {
            id: "mod_a".to_owned(),
            multi: 0,
            params: first,
        }];
        let nodes_second = vec![PipeNode {
            id: "mod_a".to_owned(),
            multi: 0,
            params: second,
        }];
        let geos = vec![geo_pair(8)];
        assert_eq!(
            chain_keys(PipeKind::Full, 7, 1, &nodes_first, &geos),
            chain_keys(PipeKind::Full, 7, 1, &nodes_second, &geos)
        );
    }

    #[test]
    fn nested_params_key_ignores_insertion_order() {
        // Nested objects are `Map`s too (insertion-ordered under the
        // workspace's `preserve_order`): canonical form sorts every level.
        let mut inner_first = no_params();
        inner_first.insert("x".to_owned(), json!(1));
        inner_first.insert("y".to_owned(), json!(2));
        let mut inner_second = no_params();
        inner_second.insert("y".to_owned(), json!(2));
        inner_second.insert("x".to_owned(), json!(1));
        let mut first = no_params();
        first.insert(
            "cell".to_owned(),
            json!({"type": "floats", "value": [1.0, 2.0]}),
        );
        first.insert("nested".to_owned(), Value::Object(inner_first));
        let mut second = no_params();
        second.insert("nested".to_owned(), Value::Object(inner_second));
        second.insert(
            "cell".to_owned(),
            json!({"type": "floats", "value": [1.0, 2.0]}),
        );
        let nodes_first = vec![PipeNode {
            id: "mod_a".to_owned(),
            multi: 0,
            params: first,
        }];
        let nodes_second = vec![PipeNode {
            id: "mod_a".to_owned(),
            multi: 0,
            params: second,
        }];
        let geos = vec![geo_pair(8)];
        assert_eq!(
            chain_keys(PipeKind::Full, 7, 1, &nodes_first, &geos),
            chain_keys(PipeKind::Full, 7, 1, &nodes_second, &geos)
        );
    }

    fn cached_plane(budget: &Arc<Budget>, side: u32) -> Arc<SharedFrame> {
        Arc::new(
            alloc_shared(
                budget,
                FrameExtent::new(0, 0, side, side),
                PixelFormat::RgbaF32Premul,
            )
            .unwrap(),
        )
    }

    #[test]
    fn insert_evicts_least_recently_used_by_bytes() {
        let budget = Arc::new(Budget::new(10_000_000));
        // Two 8x8 planes (1024 bytes each) fit 2048; the third evicts key 1.
        let mut cache = PlaneCache::new(8, 2_048);
        assert!(cache.insert(1, cached_plane(&budget, 8)));
        assert!(cache.insert(2, cached_plane(&budget, 8)));
        assert_eq!(cache.bytes(), 2_048);
        assert!(cache.insert(3, cached_plane(&budget, 8)));
        assert_eq!(cache.len(), 2);
        assert!(cache.peek(1).is_none());
        assert!(cache.peek(2).is_some());
        assert!(cache.peek(3).is_some());
        // Touching key 2 makes key 3 the victim next.
        cache.touch(2);
        assert!(cache.insert(4, cached_plane(&budget, 8)));
        assert!(cache.peek(2).is_some());
        assert!(cache.peek(3).is_none());
        assert!(cache.peek(4).is_some());
    }

    #[test]
    fn oversized_plane_is_refused_and_slot_cap_binds() {
        let budget = Arc::new(Budget::new(10_000_000));
        let mut cache = PlaneCache::new(8, 1_000);
        assert!(!cache.insert(1, cached_plane(&budget, 8)));
        assert!(cache.is_empty());
        // Slots bind before bytes: one slot keeps only the newest plane.
        let mut cache = PlaneCache::new(1, 10_000_000);
        assert!(cache.insert(1, cached_plane(&budget, 8)));
        assert!(cache.insert(2, cached_plane(&budget, 8)));
        assert_eq!(cache.len(), 1);
        assert!(cache.peek(2).is_some());
    }

    #[test]
    fn eviction_returns_budget_when_cache_holds_last_arc() {
        let budget = Arc::new(Budget::new(10_000_000));
        let mut cache = PlaneCache::new(1, 10_000_000);
        assert!(cache.insert(1, cached_plane(&budget, 8)));
        assert_eq!(budget.used(), 1_024);
        assert!(cache.insert(2, cached_plane(&budget, 8)));
        // Key 1's plane had no other holder: its bytes are back.
        assert_eq!(budget.used(), 1_024);
        cache.clear();
        assert_eq!(budget.used(), 0);
    }
    #[test]
    fn evict_oldest_except_skips_protected_oldest_first() {
        let budget = Arc::new(Budget::new(10_000_000));
        let mut cache = PlaneCache::new(8, 10_000_000);
        // Empty cache: nothing to evict.
        assert_eq!(cache.evict_oldest_except(&HashSet::new()), None);
        assert!(cache.insert(1, cached_plane(&budget, 8)));
        assert!(cache.insert(2, cached_plane(&budget, 8)));
        assert!(cache.insert(3, cached_plane(&budget, 8)));
        assert_eq!(budget.used(), 3_072);
        // Oldest-first order is 1, 2, 3; protecting 1 yields 2, then 3, and
        // then nothing: the protected entry never yields.
        let one = HashSet::from([1]);
        assert_eq!(cache.evict_oldest_except(&one), Some(2));
        assert_eq!(cache.bytes(), 2_048);
        assert_eq!(budget.used(), 2_048);
        assert_eq!(cache.evict_oldest_except(&one), Some(3));
        assert_eq!(cache.evict_oldest_except(&one), None);
        assert_eq!(cache.len(), 1);
        assert!(cache.peek(1).is_some());
        // Unprotected, the last entry yields too and every byte is back.
        assert_eq!(cache.evict_oldest_except(&HashSet::new()), Some(1));
        assert!(cache.is_empty());
        assert_eq!(cache.bytes(), 0);
        assert_eq!(budget.used(), 0);
    }
    fn sample_raw() -> lightamer_iop_traits::RawFacts {
        lightamer_iop_traits::RawFacts {
            black: [512, 512, 512, 512],
            white: 15360,
            wb: [2.0, 1.0, 1.5, 1.0],
            xyz_to_cam_d65: None,
            cam_to_xyz_d65: None,
            cfa: lightamer_iop_traits::CfaPattern::Bayer([
                lightamer_iop_traits::CfaColor::Red,
                lightamer_iop_traits::CfaColor::Green,
                lightamer_iop_traits::CfaColor::Green,
                lightamer_iop_traits::CfaColor::Blue,
            ]),
            crop_x: 0,
            crop_y: 0,
            p_width: 9568,
            p_height: 6376,
            linear_response_limit: 1.0,
            hdr: false,
            four_bayer: false,
            s_raw: false,
            monochrome: false,
            monochrome_bayer: false,
            load_ok: true,
            camera_missing_sample: false,
        }
    }

    fn sample_image() -> lightamer_iop_traits::ImageInfo {
        lightamer_iop_traits::ImageInfo::new(9568, 6376, lightamer_iop_traits::ColorSpace::Raw)
            .with_format(lightamer_iop_traits::PixelFormat::MonoF32)
            .with_raw(sample_raw())
    }

    #[test]
    fn every_image_fact_flips_the_key() {
        let nodes = vec![node("mod_a"), node("mod_b")];
        let geos = vec![geo_pair(8), geo_pair(8)];
        let keys = |image: &lightamer_iop_traits::ImageInfo| {
            super::chain_keys_with_image(PipeKind::Full, 7, 1, image, &nodes, &geos)
        };
        let base = keys(&sample_image());
        let mut size = sample_image();
        size.width = 100;
        assert_ne!(keys(&size), base);
        let mut height = sample_image();
        height.height = 100;
        assert_ne!(keys(&height), base);
        let mut space = sample_image();
        space.input_space = lightamer_iop_traits::ColorSpace::Rgb;
        assert_ne!(keys(&space), base);
        let mut format = sample_image();
        format.format = lightamer_iop_traits::PixelFormat::RgbaF32Premul;
        assert_ne!(keys(&format), base);
        let mut no_raw = sample_image();
        no_raw.raw = None;
        assert_ne!(keys(&no_raw), base);
        let flips: [fn(&mut lightamer_iop_traits::RawFacts); 19] = [
            |raw: &mut lightamer_iop_traits::RawFacts| raw.black[2] = 513,
            |raw: &mut lightamer_iop_traits::RawFacts| raw.white = 15361,
            |raw: &mut lightamer_iop_traits::RawFacts| raw.wb[0] = 2.5,
            |raw: &mut lightamer_iop_traits::RawFacts| raw.wb[1] = -0.0,
            |raw: &mut lightamer_iop_traits::RawFacts| {
                raw.xyz_to_cam_d65 = Some([0.0; 9]);
            },
            |raw: &mut lightamer_iop_traits::RawFacts| {
                raw.cam_to_xyz_d65 = Some([1.0; 9]);
            },
            |raw: &mut lightamer_iop_traits::RawFacts| {
                raw.cfa = lightamer_iop_traits::CfaPattern::None;
            },
            |raw: &mut lightamer_iop_traits::RawFacts| raw.crop_x = 8,
            |raw: &mut lightamer_iop_traits::RawFacts| raw.crop_y = 8,
            |raw: &mut lightamer_iop_traits::RawFacts| raw.p_width = 9567,
            |raw: &mut lightamer_iop_traits::RawFacts| raw.p_height = 6375,
            |raw: &mut lightamer_iop_traits::RawFacts| raw.linear_response_limit = 0.5,
            |raw: &mut lightamer_iop_traits::RawFacts| raw.hdr = true,
            |raw: &mut lightamer_iop_traits::RawFacts| raw.four_bayer = true,
            |raw: &mut lightamer_iop_traits::RawFacts| raw.s_raw = true,
            |raw: &mut lightamer_iop_traits::RawFacts| raw.monochrome = true,
            |raw: &mut lightamer_iop_traits::RawFacts| raw.monochrome_bayer = true,
            |raw: &mut lightamer_iop_traits::RawFacts| raw.load_ok = false,
            |raw: &mut lightamer_iop_traits::RawFacts| raw.camera_missing_sample = true,
        ];
        for flip in flips {
            let mut image = sample_image();
            if let Some(raw) = image.raw.as_mut() {
                flip(raw);
            }
            assert_ne!(keys(&image), base);
        }
    }

    #[test]
    fn repeated_facts_hit_the_key_bitwise() {
        let nodes = vec![node("mod_a"), node("mod_b")];
        let geos = vec![geo_pair(8), geo_pair(8)];
        let keys = |image: &lightamer_iop_traits::ImageInfo| {
            super::chain_keys_with_image(PipeKind::Full, 7, 1, image, &nodes, &geos)
        };
        assert_eq!(keys(&sample_image()), keys(&sample_image()));
        let mut nan_a = sample_image();
        let mut nan_b = sample_image();
        if let Some(raw) = nan_a.raw.as_mut() {
            raw.wb[0] = f32::from_bits(0x7fc0_0001);
        }
        if let Some(raw) = nan_b.raw.as_mut() {
            raw.wb[0] = f32::from_bits(0x7fc0_0001);
        }
        assert_eq!(keys(&nan_a), keys(&nan_b));
    }
}
