// SPDX-License-Identifier: GPL-3.0-or-later
//! Ordered module chains: commit, geometry, negotiation.
//!
//! The caller supplies nodes in execution order (from the registry's default
//! chain) plus a [`ModuleLookup`]; this module commits each node, walks the
//! geometry both ways, and reports per-node regions. No module id is named
//! here: tests use `mod_a`-style fakes.
use std::collections::HashMap;
use std::fmt;
use std::sync::Arc;

use lightamer_geom::Roi as GeomRoi;
use lightamer_iop_traits::{
    CommitData, ImageInfo, IopModule, PipeError, PipeKind, PipeState, PixelFormat as WireFormat,
    Roi as WireRoi,
};
use lightamer_raster::PixelFormat as RasterFormat;
use serde_json::{Map, Value};

/// One module behind a shared pointer.
pub type SharedModule = Arc<dyn IopModule>;

/// Where the chain finds modules by id.
pub trait ModuleLookup {
    /// Returns the module registered as `id`, or [`None`].
    fn lookup(&self, id: &str) -> Option<SharedModule>;
}

/// Any closure shaped like a lookup is one.
impl<F> ModuleLookup for F
where
    F: Fn(&str) -> Option<SharedModule>,
{
    fn lookup(&self, id: &str) -> Option<SharedModule> {
        self(id)
    }
}

/// A plain id-keyed table is a lookup.
impl<S: std::hash::BuildHasher> ModuleLookup for HashMap<String, SharedModule, S> {
    fn lookup(&self, id: &str) -> Option<SharedModule> {
        self.get(id).cloned()
    }
}

/// One instance in execution order, as the caller passes it in.
#[derive(Debug, Clone)]
pub struct PipeNode {
    /// Module id (registry key).
    pub id: String,
    /// Multi-instance index; carried through untouched.
    pub multi: u32,
    /// Instance parameters as a JSON object.
    pub params: Map<String, Value>,
}

/// One committed node: module plus its opaque commit product.
pub struct CommittedNode {
    /// Module id.
    pub id: String,
    /// Multi-instance index.
    pub multi: u32,
    /// The module.
    pub module: SharedModule,
    /// This instance's commit product.
    pub data: CommitData,
}

impl std::fmt::Debug for CommittedNode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("CommittedNode")
            .field("id", &self.id)
            .field("multi", &self.multi)
            .finish_non_exhaustive()
    }
}

/// Per-node geometry in execution order.
#[derive(Debug, Clone, PartialEq)]
pub struct NodeGeometry {
    /// What this node must be fed.
    pub input: GeomRoi,
    /// What this node produces.
    pub output: GeomRoi,
}

/// Why chain building or geometry failed.
#[derive(Debug)]
pub enum ChainError {
    /// No module is registered as this id.
    UnknownModule(String),
    /// This module's commit refused its parameters.
    Commit {
        /// Module id.
        id: String,
        /// What commit reported.
        source: PipeError,
    },
    /// This module returned a malformed region.
    BadRoi {
        /// Module id.
        id: String,
        /// What was wrong.
        detail: String,
    },
    /// The backward pass disagrees with the forward pass here.
    Roundtrip {
        /// Module id.
        id: String,
        /// What the forward pass recorded.
        expected: String,
        /// What the backward pass recomputed.
        got: String,
    },
    /// Geometry and chain lengths differ.
    LengthMismatch {
        /// Chain length.
        chain: usize,
        /// Geometry length.
        geos: usize,
    },
}

impl fmt::Display for ChainError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ChainError::UnknownModule(id) => write!(f, "unknown module '{id}'"),
            ChainError::Commit { id, source } => write!(f, "module '{id}' commit failed: {source}"),
            ChainError::BadRoi { id, detail } => {
                write!(f, "module '{id}' returned a bad roi: {detail}")
            }
            ChainError::Roundtrip { id, expected, got } => write!(
                f,
                "module '{id}' geometry does not round-trip: forward {expected}, backward {got}"
            ),
            ChainError::LengthMismatch { chain, geos } => {
                write!(f, "chain holds {chain} nodes but geometry holds {geos}")
            }
        }
    }
}

impl std::error::Error for ChainError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            ChainError::Commit { source, .. } => Some(source),
            _ => None,
        }
    }
}

/// Commits every node in order, threading one chain state through.
///
/// `state` starts from the caller (the pipe seeds it from the image) and
/// each commit sees what earlier commits wrote; the pipe then runs
/// processing from the value this leaves behind. `kind` is the render the
/// pipe serves: it reaches every commit for kind-gated behavior.
///
/// # Errors
///
/// [`ChainError::UnknownModule`] for an unregistered id;
/// [`ChainError::Commit`] when a module refuses its parameters (earlier
/// commits are dropped with the returned error; nothing is cached in B1-a).
pub fn build_chain<L: ModuleLookup>(
    lookup: &L,
    nodes: &[PipeNode],
    image: &ImageInfo,
    state: &mut PipeState,
    kind: PipeKind,
) -> Result<Vec<CommittedNode>, ChainError> {
    let mut out = Vec::with_capacity(nodes.len());
    for node in nodes {
        let Some(module) = lookup.lookup(&node.id) else {
            return Err(ChainError::UnknownModule(node.id.clone()));
        };
        let data = module
            .commit(&node.params, image, state, kind)
            .map_err(|source| ChainError::Commit {
                id: node.id.clone(),
                source,
            })?;
        out.push(CommittedNode {
            id: node.id.clone(),
            multi: node.multi,
            module,
            data,
        });
    }
    Ok(out)
}

/// Forward pass: from the wanted final output region, backward through
/// execution order, each node's needed input becomes the previous node's
/// wanted output — the shape of `_dev_pixelpipe_process_rec` calling
/// `modify_roi_in` from the end of the list
/// (`src/develop/pixelpipe_hb.c:2575`).
///
/// Returns per-node geometry in execution order. Adjacent entries chain:
/// `geos[i].output == geos[i + 1].input`, with the last output equal to
/// `final_out`.
///
/// # Errors
///
/// [`ChainError::BadRoi`] when a module returns a malformed region (the
/// wire shape is validated at the geometry boundary, blaming the module).
pub fn forward(
    chain: &[CommittedNode],
    final_out: &GeomRoi,
) -> Result<Vec<NodeGeometry>, ChainError> {
    let mut rev: Vec<NodeGeometry> = Vec::with_capacity(chain.len());
    let mut want_out = *final_out;
    for node in chain.iter().rev() {
        let wire_in = node.module.roi_in(&node.data, to_wire(&want_out));
        let input = from_wire(&wire_in).map_err(|detail| ChainError::BadRoi {
            id: node.id.clone(),
            detail,
        })?;
        rev.push(NodeGeometry {
            input,
            output: want_out,
        });
        want_out = input;
    }
    rev.reverse();
    Ok(rev)
}

/// Backward check: from the first input region, forward through execution
/// order, each node's recomputed output must equal what [`forward`] recorded
/// — the shape of `dt_dev_pixelpipe_get_dimensions` calling
/// `modify_roi_out` down the list (`src/develop/pixelpipe_hb.c:4026`).
///
/// # Errors
///
/// [`ChainError::LengthMismatch`] for a misaligned `geos` slice;
/// [`ChainError::BadRoi`] for a malformed recomputed region;
/// [`ChainError::Roundtrip`] on the first node whose backward output differs
/// from the recorded one.
pub fn backward_check(
    chain: &[CommittedNode],
    geos: &[NodeGeometry],
    first_in: &GeomRoi,
) -> Result<(), ChainError> {
    if chain.len() != geos.len() {
        return Err(ChainError::LengthMismatch {
            chain: chain.len(),
            geos: geos.len(),
        });
    }
    let mut have_in = *first_in;
    for (node, geo) in chain.iter().zip(geos.iter()) {
        let wire_out = node.module.roi_out(&node.data, to_wire(&have_in));
        let output = from_wire(&wire_out).map_err(|detail| ChainError::BadRoi {
            id: node.id.clone(),
            detail,
        })?;
        if output != geo.output {
            return Err(ChainError::Roundtrip {
                id: node.id.clone(),
                expected: format!("{geo:?}"),
                got: format!("{output:?}"),
            });
        }
        have_in = output;
    }
    Ok(())
}

/// Geometry to the wire shape modules speak.
pub(crate) fn to_wire(roi: &GeomRoi) -> WireRoi {
    WireRoi::new(roi.x, roi.y, roi.width, roi.height, roi.scale)
}

/// Wire shape back to validated geometry.
pub(crate) fn from_wire(roi: &WireRoi) -> Result<GeomRoi, String> {
    GeomRoi::new(roi.x, roi.y, roi.width, roi.height, roi.scale)
        .map_err(|err| format!("{roi:?}: {err}"))
}

/// Raster format to the wire shape modules speak.
pub(crate) fn format_to_wire(format: RasterFormat) -> WireFormat {
    match format {
        RasterFormat::RgbaF32Premul => WireFormat::RgbaF32Premul,
        RasterFormat::RgbaU8 => WireFormat::RgbaU8,
        RasterFormat::RgbaU16 => WireFormat::RgbaU16,
        RasterFormat::MonoF32 => WireFormat::MonoF32,
    }
}

/// Wire format back to the raster format planes allocate.
pub(crate) fn format_from_wire(format: WireFormat) -> RasterFormat {
    match format {
        WireFormat::RgbaF32Premul => RasterFormat::RgbaF32Premul,
        WireFormat::RgbaU8 => RasterFormat::RgbaU8,
        WireFormat::RgbaU16 => RasterFormat::RgbaU16,
        WireFormat::MonoF32 => RasterFormat::MonoF32,
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use std::sync::Arc;

    use lightamer_geom::Roi as GeomRoi;
    use lightamer_iop_traits::{ColorSpace, ImageInfo, PipeKind, PipeState};

    use super::{ChainError, NodeGeometry, PipeNode, backward_check, build_chain, forward};
    use crate::fakes::{
        FakeBadRoi, FakeCrop, FakeFail, FakeScale, FakeShift, FakeSink, no_params, table,
    };

    fn image() -> ImageInfo {
        ImageInfo::new(400, 400, ColorSpace::Rgb)
    }

    fn node(id: &str) -> PipeNode {
        PipeNode {
            id: id.to_owned(),
            multi: 0,
            params: no_params(),
        }
    }

    fn geom(x: i32, y: i32, w: i32, h: i32) -> GeomRoi {
        GeomRoi::new(x, y, w, h, 1.0).unwrap()
    }

    /// Every node holds what it deserves: the caller hand-walks, per node,
    /// the input derived from the wanted final output and each fake's
    /// stated rule — never copied from `forward`'s return — and this checks
    /// equality plus mutual containment between the two independent
    /// derivations (never self-containment). Empty expectations are pinned
    /// by equality and `is_empty` only: any region contains the empty set,
    /// so a `contains` leg would carry no signal there.
    fn assert_chained(geos: &[NodeGeometry], expected_inputs: &[GeomRoi], final_out: &GeomRoi) {
        assert_eq!(
            geos.len(),
            expected_inputs.len(),
            "geometry/expected length"
        );
        for (index, (geo, expected)) in geos.iter().zip(expected_inputs.iter()).enumerate() {
            assert_eq!(
                geo.input, *expected,
                "node {index} input differs from the hand walk"
            );
            if expected.is_empty() {
                assert!(
                    geo.input.is_empty(),
                    "node {index}: expected empty, got {:?}",
                    geo.input
                );
            } else {
                assert!(
                    !geo.input.is_empty(),
                    "node {index}: expected non-empty, got empty"
                );
                assert!(
                    geo.input.contains(*expected),
                    "node {index}: input {:?} does not contain hand-walked {:?}",
                    geo.input,
                    expected
                );
                assert!(
                    expected.contains(geo.input),
                    "node {index}: hand-walked {:?} does not contain input {:?}",
                    expected,
                    geo.input
                );
            }
        }
        for pair in geos.windows(2) {
            assert_eq!(
                pair[0].output, pair[1].input,
                "adjacent handoff: upstream output must equal downstream input"
            );
        }
        if let Some(last) = geos.last() {
            assert_eq!(
                last.output, *final_out,
                "last output differs from wanted final"
            );
        }
    }

    #[test]
    fn identity_chain_keeps_every_region() {
        let lookup = table(vec![
            Arc::new(lightamer_testkit::IdentityModule::new()),
            Arc::new(FakeScale::new("mod_b", 1, 1)),
        ]);
        let chain = build_chain(
            &lookup,
            &[node("test_identity"), node("mod_b")],
            &image(),
            &mut PipeState::from_image(&image()),
            PipeKind::Full,
        )
        .unwrap();
        assert_eq!(chain.len(), 2);
        let final_out = geom(10, 20, 100, 60);
        let geos = forward(&chain, &final_out).unwrap();
        assert_eq!(geos.len(), 2);
        // Hand walk: both nodes are 1:1, so every input is the final itself.
        assert_chained(&geos, &[final_out, final_out], &final_out);
        backward_check(&chain, &geos, &geos[0].input).unwrap();
    }

    #[test]
    fn scale_up_grows_output_and_shrinks_input() {
        let lookup = table(vec![Arc::new(FakeScale::new("mod_up", 2, 1))]);
        let chain = build_chain(
            &lookup,
            &[node("mod_up")],
            &image(),
            &mut PipeState::from_image(&image()),
            PipeKind::Full,
        )
        .unwrap();
        let final_out = geom(0, 0, 100, 100);
        let geos = forward(&chain, &final_out).unwrap();
        // Forward asks: what input yields 100x100 out? Half: 50x50.
        assert_chained(&geos, &[geom(0, 0, 50, 50)], &final_out);
        backward_check(&chain, &geos, &geos[0].input).unwrap();
    }

    #[test]
    fn scale_down_shrinks_output_and_grows_input() {
        let lookup = table(vec![Arc::new(FakeScale::new("mod_down", 1, 2))]);
        let chain = build_chain(
            &lookup,
            &[node("mod_down")],
            &image(),
            &mut PipeState::from_image(&image()),
            PipeKind::Full,
        )
        .unwrap();
        let final_out = geom(0, 0, 100, 100);
        let geos = forward(&chain, &final_out).unwrap();
        // Forward asks: what input yields 100x100 out? Double: 200x200.
        assert_chained(&geos, &[geom(0, 0, 200, 200)], &final_out);
        backward_check(&chain, &geos, &geos[0].input).unwrap();
    }

    #[test]
    fn crop_up_down_round_trips_to_the_original() {
        let lookup = table(vec![
            Arc::new(FakeCrop::new("mod_crop", 10, 6, 20, 12)),
            Arc::new(FakeScale::new("mod_up", 2, 1)),
            Arc::new(FakeScale::new("mod_down", 1, 2)),
        ]);
        let nodes = [node("mod_crop"), node("mod_up"), node("mod_down")];
        let chain = build_chain(
            &lookup,
            &nodes,
            &image(),
            &mut PipeState::from_image(&image()),
            PipeKind::Full,
        )
        .unwrap();
        let final_out = geom(0, 0, 100, 100);
        let geos = forward(&chain, &final_out).unwrap();
        // Hand walk, back to front: down needs 200x200 in; up needs 100x100
        // in; the crop needs +20/+12 at +10/+6. Execution order below.
        assert_chained(
            &geos,
            &[
                geom(10, 6, 120, 112),
                geom(0, 0, 100, 100),
                geom(0, 0, 200, 200),
            ],
            &final_out,
        );
        backward_check(&chain, &geos, &geos[0].input).unwrap();
    }

    #[test]
    fn non_integer_scale_rounds_as_stated_and_breaks_round_trip() {
        let lookup = table(vec![Arc::new(FakeScale::new("mod_mid", 3, 2))]);
        let chain = build_chain(
            &lookup,
            &[node("mod_mid")],
            &image(),
            &mut PipeState::from_image(&image()),
            PipeKind::Full,
        )
        .unwrap();
        // Out leg rounds half up: 100 * 3/2 = 150.
        let out = chain[0].module.roi_out(
            &chain[0].data,
            lightamer_iop_traits::Roi::new(0, 0, 100, 100, 1.0),
        );
        assert_eq!((out.width, out.height), (150, 150));
        // In leg truncates: 100 * 2/3 = 66.
        let final_out = geom(0, 0, 100, 100);
        let geos = forward(&chain, &final_out).unwrap();
        assert_chained(&geos, &[geom(0, 0, 66, 66)], &final_out);
        // 66 back out is 99, not 100: lossy scales do not round-trip, and
        // the checker says so instead of silently passing.
        let err = backward_check(&chain, &geos, &geos[0].input).unwrap_err();
        assert!(matches!(err, ChainError::Roundtrip { .. }));
        assert!(err.to_string().contains("mod_mid"));
    }

    #[test]
    fn empty_final_stays_empty_and_sink_needs_no_input() {
        let lookup = table(vec![
            Arc::new(lightamer_testkit::IdentityModule::new()),
            Arc::new(FakeSink::new("mod_sink")),
        ]);
        // Empty wanted out: identity echoes emptiness both ways.
        let id_chain = build_chain(
            &lookup,
            &[node("test_identity")],
            &image(),
            &mut PipeState::from_image(&image()),
            PipeKind::Full,
        )
        .unwrap();
        let empty = geom(0, 0, 0, 0);
        let geos = forward(&id_chain, &empty).unwrap();
        assert!(geos[0].input.is_empty());
        // Empty deserved input: pinned by equality, never by containment.
        assert_chained(&geos, &[geom(0, 0, 0, 0)], &empty);
        // A sink reports it needs nothing, whatever is wanted.
        let sink_chain = build_chain(
            &lookup,
            &[node("mod_sink")],
            &image(),
            &mut PipeState::from_image(&image()),
            PipeKind::Full,
        )
        .unwrap();
        let final_out = geom(0, 0, 100, 60);
        let geos = forward(&sink_chain, &final_out).unwrap();
        assert!(geos[0].input.is_empty());
        assert_eq!(geos[0].output, final_out);
        // A sink deserves nothing: same empty-only pinning as above.
        assert_chained(&geos, &[geom(0, 0, 0, 0)], &final_out);
        // Backward cannot hold: roi_out of nothing is nothing, not the final.
        assert!(backward_check(&sink_chain, &geos, &geos[0].input).is_err());
    }

    #[test]
    fn long_chain_holds_exact() {
        let lookup = table(vec![
            Arc::new(FakeScale::new("mod_up", 2, 1)),
            Arc::new(FakeScale::new("mod_down", 1, 2)),
        ]);
        let nodes: Vec<PipeNode> = (0..32)
            .flat_map(|_| [node("mod_up"), node("mod_down")])
            .collect();
        let chain = build_chain(
            &lookup,
            &nodes,
            &image(),
            &mut PipeState::from_image(&image()),
            PipeKind::Full,
        )
        .unwrap();
        assert_eq!(chain.len(), 64);
        let final_out = geom(8, 4, 256, 256);
        let geos = forward(&chain, &final_out).unwrap();
        // 32 exact up/down pairs: even nodes (up) are fed the final itself,
        // odd nodes (down) are fed its doubling. All sizes stay even, so
        // both legs divide exactly and error cannot accumulate.
        let expected: Vec<GeomRoi> = (0..32)
            .flat_map(|_| [final_out, geom(16, 8, 512, 512)])
            .collect();
        assert_chained(&geos, &expected, &final_out);
        backward_check(&chain, &geos, &geos[0].input).unwrap();
    }

    #[test]
    fn forward_and_backward_agree_on_a_mixed_chain() {
        let lookup = table(vec![
            Arc::new(FakeShift::new("mod_shift_a", 6, 8)),
            Arc::new(FakeScale::new("mod_up", 2, 1)),
            Arc::new(FakeShift::new("mod_shift_b", 4, 2)),
        ]);
        let nodes = [node("mod_shift_a"), node("mod_up"), node("mod_shift_b")];
        let chain = build_chain(
            &lookup,
            &nodes,
            &image(),
            &mut PipeState::from_image(&image()),
            PipeKind::Full,
        )
        .unwrap();
        let final_out = geom(0, 0, 100, 100);
        let geos = forward(&chain, &final_out).unwrap();
        // Back to front: shift_b needs (4,2,100,100); up halves to
        // (2,1,50,50); shift_a needs (8,9,50,50). Even offsets keep the
        // halving exact. Execution order below.
        assert_chained(
            &geos,
            &[geom(8, 9, 50, 50), geom(2, 1, 50, 50), geom(4, 2, 100, 100)],
            &final_out,
        );
        backward_check(&chain, &geos, &geos[0].input).unwrap();
    }

    #[test]
    fn unknown_module_commit_failure_and_bad_roi_are_typed() {
        let lookup = table(vec![
            Arc::new(FakeFail::new("mod_fail")),
            Arc::new(FakeBadRoi::new("mod_bad")),
        ]);
        let err = build_chain(
            &lookup,
            &[node("mod_missing")],
            &image(),
            &mut PipeState::from_image(&image()),
            PipeKind::Full,
        )
        .unwrap_err();
        assert!(matches!(err, ChainError::UnknownModule(_)));
        assert!(err.to_string().contains("mod_missing"));

        let err = build_chain(
            &lookup,
            &[node("mod_fail")],
            &image(),
            &mut PipeState::from_image(&image()),
            PipeKind::Full,
        )
        .unwrap_err();
        assert!(matches!(err, ChainError::Commit { .. }));
        assert!(err.to_string().contains("mod_fail"));

        let chain = build_chain(
            &lookup,
            &[node("mod_bad")],
            &image(),
            &mut PipeState::from_image(&image()),
            PipeKind::Full,
        )
        .unwrap();
        let err = forward(&chain, &geom(0, 0, 64, 64)).unwrap_err();
        assert!(matches!(err, ChainError::BadRoi { .. }));
        assert!(err.to_string().contains("mod_bad"));

        let err = backward_check(&chain, &[], &geom(0, 0, 64, 64)).unwrap_err();
        assert!(matches!(err, ChainError::LengthMismatch { .. }));
    }

    #[test]
    fn multi_index_is_carried_and_closure_lookup_works() {
        let module: Arc<dyn lightamer_iop_traits::IopModule> =
            Arc::new(FakeScale::new("mod_up", 1, 1));
        let chain = build_chain(
            &|id: &str| {
                if id == "mod_up" {
                    Some(module.clone())
                } else {
                    None
                }
            },
            &[PipeNode {
                id: "mod_up".to_owned(),
                multi: 3,
                params: no_params(),
            }],
            &image(),
            &mut PipeState::from_image(&image()),
            PipeKind::Full,
        )
        .unwrap();
        assert_eq!((chain[0].id.as_str(), chain[0].multi), ("mod_up", 3));
        let boxed: Box<dyn std::error::Error> = Box::new(ChainError::UnknownModule("x".to_owned()));
        assert!(boxed.to_string().contains("unknown module"));
    }
    #[test]
    fn format_mirrors_round_trip() {
        use super::{format_from_wire, format_to_wire};
        use lightamer_raster::PixelFormat as RasterFormat;

        for format in [
            RasterFormat::RgbaF32Premul,
            RasterFormat::RgbaU8,
            RasterFormat::RgbaU16,
            RasterFormat::MonoF32,
        ] {
            assert_eq!(format_from_wire(format_to_wire(format)), format);
        }
    }
}
