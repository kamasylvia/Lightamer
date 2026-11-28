// SPDX-License-Identifier: GPL-3.0-or-later
//! Whole-image statistics declarations and the overlap consistency check.
//!
//! A module that renders any pixel from statistics of the whole frame (a
//! histogram auto-exposure, a whole-frame maximum) cannot stream band by band
//! without help. [`StatsNeeds`] declares that need; the default is
//! [`StatsNeeds::Local`] (no full-frame statistics), so existing modules keep
//! their behavior without touching this file.
//!
//! The overlap side is separate: [`check_overlap_covers`] tests one module's
//! two declarations against each other — the halo its `tiling()` request
//! claims ([`TilingReq::overlap`](super::TilingReq)) must cover the growth its
//! `roi_in` reports. A module that claims zero overlap while growing its
//! input region contradicts itself, and streaming it would silently render
//! seams. This check is declaration-vs-declaration only; it never runs
//! `process`, so a module that lies inside `process` (reads past its declared
//! support) is caught by full-frame-vs-stream bitwise tests instead.

use std::fmt;

use super::{CommitData, IopModule, Roi};

/// What whole-image statistics a module needs before it renders.
///
/// darktable answers this with one bit (`process_tiling_ready = FALSE` means
/// "render me whole-frame or not at all"); Lumen RAW and `LightCraft` compute
/// statistics from a downscaled proxy instead. This enum leaves room for the
/// proxy leg while defaulting every module to [`StatsNeeds::Local`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StatsNeeds {
    /// Output pixels depend only on their support region (default).
    Local,
    /// Must see the full frame; streaming refuses these until a later wave
    /// teaches it whole-frame fallbacks.
    WholeImage,
    /// Accepts statistics from a downscaled proxy frame; the proxy leg lands
    /// with the first module that needs it, so streaming refuses these for now.
    Proxy {
        /// Long edge of the proxy frame the statistics may come from.
        max_long_edge: u32,
    },
}

/// Why an overlap declaration contradicts its module's `roi_in`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OverlapError {
    /// `roi_in` changes scale, so pixel growth has no meaning here; the
    /// caller checks geometry separately.
    ScaleChange {
        /// Scale bits `roi_in` returned.
        in_scale_bits: u32,
        /// Scale bits the output region carries.
        out_scale_bits: u32,
    },
    /// `overlap` is smaller than the `roi_in` growth on at least one side.
    Uncovered {
        /// The claimed overlap in pixels.
        overlap: u32,
        /// `roi_in` growth in pixels: left, top, right, bottom. Negative
        /// entries are shrinkage (fine); any entry above `overlap` is the lie.
        growth: [i64; 4],
    },
}

impl fmt::Display for OverlapError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            OverlapError::ScaleChange {
                in_scale_bits,
                out_scale_bits,
            } => write!(
                f,
                "roi_in changes scale ({in_scale_bits:#x} vs {out_scale_bits:#x}); overlap consistency needs equal scales"
            ),
            OverlapError::Uncovered { overlap, growth } => write!(
                f,
                "overlap {overlap} does not cover the roi_in growth (left {}, top {}, right {}, bottom {})",
                growth[0], growth[1], growth[2], growth[3]
            ),
        }
    }
}

impl std::error::Error for OverlapError {}

/// Checks one module's `overlap` against its own `roi_in` at `rout`.
///
/// Calls `roi_in` for the growth and `tiling` for the claimed overlap, then
/// requires the claim to cover the growth on all four sides. An empty
/// `roi_in` (the module needs no input) always passes: there is no support
/// region to contradict. Scale-changing modules fail as
/// [`OverlapError::ScaleChange`]; geometry itself is the caller's check, not
/// this function's.
///
/// # Errors
///
/// [`OverlapError`] when the two declarations contradict each other.
pub fn check_overlap_covers(
    module: &dyn IopModule,
    data: &CommitData,
    rout: &Roi,
) -> Result<(), OverlapError> {
    let rin = module.roi_in(data, *rout);
    if rin.width <= 0 || rin.height <= 0 {
        return Ok(());
    }
    if rin.scale.to_bits() != rout.scale.to_bits() {
        return Err(OverlapError::ScaleChange {
            in_scale_bits: rin.scale.to_bits(),
            out_scale_bits: rout.scale.to_bits(),
        });
    }
    let req = module.tiling(data, &rin, rout);
    let growth = [
        i64::from(rout.x) - i64::from(rin.x),
        i64::from(rout.y) - i64::from(rin.y),
        i64::from(rin.x) + i64::from(rin.width) - i64::from(rout.x) - i64::from(rout.width),
        i64::from(rin.y) + i64::from(rin.height) - i64::from(rout.y) - i64::from(rout.height),
    ];
    let cover = i64::from(req.overlap);
    if growth.iter().all(|side| *side <= cover) {
        Ok(())
    } else {
        Err(OverlapError::Uncovered {
            overlap: req.overlap,
            growth,
        })
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use std::sync::Arc;

    use serde_json::{Map, Value};

    use super::{OverlapError, check_overlap_covers};
    use crate::{
        CommitData, ImageInfo, IopModule, ModuleDesc, OrderKey, PipeError, PipeState, Plane,
        PlaneMut, Roi, TilingReq,
    };

    /// A module whose `roi_in` grows by `grow` pixels per side and whose
    /// `tiling` claims `overlap`; `process` never runs in these tests.
    struct Grower {
        desc: ModuleDesc,
        grow: i32,
        overlap: u32,
    }

    impl Grower {
        fn new(grow: i32, overlap: u32) -> Self {
            let key = OrderKey {
                priority: 1.0,
                tie: 0,
            };
            Self {
                desc: ModuleDesc::stub("stats_probe", key, key),
                grow,
                overlap,
            }
        }
    }

    impl IopModule for Grower {
        fn desc(&self) -> &ModuleDesc {
            &self.desc
        }

        fn commit(
            &self,
            _params: &Map<String, Value>,
            _image: &ImageInfo,
            _state: &mut PipeState,
            _kind: crate::PipeKind,
        ) -> Result<CommitData, PipeError> {
            Ok(Arc::new(()))
        }

        fn roi_in(&self, _data: &CommitData, rout: Roi) -> Roi {
            Roi::new(
                rout.x - self.grow,
                rout.y - self.grow,
                rout.width + 2 * self.grow,
                rout.height + 2 * self.grow,
                rout.scale,
            )
        }

        fn tiling(&self, _data: &CommitData, _rin: &Roi, _rout: &Roi) -> TilingReq {
            TilingReq {
                factor: 2.0,
                maxbuf: 1.0,
                overhead: 0,
                overlap: self.overlap,
                align: 1,
            }
        }

        fn process(
            &self,
            _data: &CommitData,
            _input: &Plane<'_>,
            _output: &mut PlaneMut<'_>,
            _rin: Roi,
            _rout: Roi,
            _state: &mut PipeState,
        ) -> Result<(), PipeError> {
            Err(PipeError::Backend("stats probe never processes".to_owned()))
        }
    }

    fn data_of(module: &Grower) -> CommitData {
        let image = ImageInfo::new(64, 64, crate::ColorSpace::Rgb);
        let mut state = crate::PipeState::from_image(&image);
        module
            .commit(&Map::new(), &image, &mut state, crate::PipeKind::Full)
            .unwrap()
    }

    #[test]
    fn identity_module_with_zero_overlap_is_consistent() {
        let module = Grower::new(0, 0);
        let data = data_of(&module);
        let rout = Roi::new(100, 100, 64, 64, 1.0);
        assert_eq!(check_overlap_covers(&module, &data, &rout), Ok(()));
    }

    #[test]
    fn overlap_covering_the_growth_is_consistent() {
        let module = Grower::new(4, 8);
        let data = data_of(&module);
        let rout = Roi::new(100, 100, 64, 64, 1.0);
        assert_eq!(check_overlap_covers(&module, &data, &rout), Ok(()));
    }

    #[test]
    fn overlap_below_the_growth_is_uncovered_on_all_sides() {
        let module = Grower::new(8, 0);
        let data = data_of(&module);
        let rout = Roi::new(100, 100, 64, 64, 1.0);
        assert_eq!(
            check_overlap_covers(&module, &data, &rout),
            Err(OverlapError::Uncovered {
                overlap: 0,
                growth: [8, 8, 8, 8],
            })
        );
    }

    #[test]
    fn overlap_error_reads_as_a_sentence() {
        let err = OverlapError::Uncovered {
            overlap: 0,
            growth: [8, 8, 8, 8],
        };
        assert_eq!(
            err.to_string(),
            "overlap 0 does not cover the roi_in growth (left 8, top 8, right 8, bottom 8)"
        );
    }
}
