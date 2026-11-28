// SPDX-License-Identifier: GPL-3.0-or-later
//! The object-safe module trait.

use std::any::Any;
use std::sync::Arc;

use serde_json::{Map, Value};

use super::{
    ColorSpace, ImageInfo, ModuleDesc, ModuleFlags, PipeError, PixelFormat, Plane, PlaneMut, Roi,
    TilingReq,
};

/// Opaque per-instance commit product: `commit` seals it, only the module
/// that made it knows how to open it again (downcast).
///
/// `Arc` shares it across the threads a tiled run spreads over.
pub type CommitData = Arc<dyn Any + Send + Sync>;

/// One discovered module behind a shared pointer: the registry table holds
/// these, mixing every module kind in a single `Vec`.
pub type SharedModule = Arc<dyn IopModule>;

/// One implemented module behind its id: what domain `IMPLEMENTED` tables hold.
pub type ImplementedModule = (&'static str, fn() -> SharedModule);

/// What every pipeline module implements.
///
/// Object-safe by construction (only `&self` receivers, no generics, no
/// associated types): the CORE-DESIGN §1 sketch used `Params`/`Piece`
/// associated types, which cannot sit behind one `dyn` table — auto-
/// discovery needs exactly that table, so parameters arrive as the JSON
/// object the history model stores and commit products travel as
/// [`CommitData`].
///
/// Callback map to `src/iop/iop_api.h` in `refs/dt-master`:
/// `desc` → `op`/`flags()`; `colorspaces` → `default/input/output_colorspace`
/// (`iop_api.h:97-110`, defaulting to `default_colorspace` per
/// `src/develop/format.c:81-93`); `commit` → `commit_params` (`:199`);
/// `output_format` → no upstream counterpart (our declaration: per-node
/// plane formats, like `stats` below);
/// `roi_out`/`roi_in` → `modify_roi_out`/`modify_roi_in` (`:213-243`,
/// identity by default per `src/develop/imageop.c:108-125`); `tiling` →
/// `tiling_callback` (`:119-124`, default per `src/develop/tiling.c:1903-1921`);
/// `process` → `process`.
pub trait IopModule: Send + Sync {
    /// This module's self-description: id, flags, colorspace contract.
    fn desc(&self) -> &ModuleDesc;

    /// Module id, from the description.
    fn id(&self) -> &str {
        self.desc().id
    }

    /// Capability flags; an unfilled description means no flags.
    fn flags(&self) -> ModuleFlags {
        self.desc().flags.unwrap_or_else(ModuleFlags::empty)
    }

    /// Expected input and produced output colorspaces.
    ///
    /// A filled description wins; otherwise (Rgb, Rgb): this pipeline's
    /// working space is linear RGB and its buffers are RGBA, so an
    /// undescribed module is assumed RGB-native on both sides.
    fn colorspaces(&self) -> (ColorSpace, ColorSpace) {
        self.desc()
            .colorspaces
            .map_or((ColorSpace::Rgb, ColorSpace::Rgb), |req| {
                (req.input, req.output)
            })
    }

    /// Seals this instance's parameters into opaque per-instance data.
    ///
    /// `params` is the instance's JSON object (`{"type": ..., "value": ...}`
    /// cells); `image` carries the decoded size and input colorspace. Reads
    /// belong to the [`get_float`](super::get_float)-family helpers.
    ///
    /// # Errors
    ///
    /// [`PipeError::InvalidParams`] for malformed parameters.
    fn commit(
        &self,
        params: &Map<String, Value>,
        image: &ImageInfo,
    ) -> Result<CommitData, PipeError>;

    /// Pixel format this module outputs for `input`.
    ///
    /// Identity by default: most modules keep the format they are given.
    /// The pipe threads this from the input frame to size every node plane;
    /// a module that changes format (mosaic in, RGBA out) overrides it.
    fn output_format(&self, input: PixelFormat) -> PixelFormat {
        input
    }

    /// Output region this module produces for input region `rin`.
    /// Identity by default.
    fn roi_out(&self, data: &CommitData, rin: Roi) -> Roi {
        let _ = data;
        rin
    }

    /// Input region this module needs to produce output region `rout`.
    /// Identity by default.
    fn roi_in(&self, data: &CommitData, rout: Roi) -> Roi {
        let _ = data;
        rout
    }

    /// Memory/overlap/alignment needs; darktable's default callback unless
    /// overridden.
    fn tiling(&self, data: &CommitData, rin: &Roi, rout: &Roi) -> TilingReq {
        let _ = data;
        TilingReq::default_for(rin, rout)
    }

    /// What whole-image statistics this module needs before it renders.
    ///
    /// [`StatsNeeds::Local`](super::StatsNeeds) by default: output pixels
    /// depend only on their support region, so the module streams band by
    /// band with no extra help.
    fn stats(&self) -> super::StatsNeeds {
        super::StatsNeeds::Local
    }

    /// Renders `rin` of `input` into `rout` of `output`.
    ///
    /// # Errors
    ///
    /// [`PipeError::RoiMismatch`] for misaligned regions;
    /// [`PipeError::Backend`] when the commit product is foreign.
    fn process(
        &self,
        data: &CommitData,
        input: &Plane<'_>,
        output: &mut PlaneMut<'_>,
        rin: Roi,
        rout: Roi,
    ) -> Result<(), PipeError>;
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use std::sync::Arc;

    use serde_json::{Map, Value};

    use super::{CommitData, IopModule};
    use crate::{ColorSpace, ImageInfo, ModuleDesc, OrderKey, PipeError, Plane, PlaneMut, Roi};

    /// Minimal local module: multiplies every pixel by a gain.
    struct Doubler {
        desc: ModuleDesc,
    }

    struct DoublerCommit {
        gain: f32,
    }

    impl IopModule for Doubler {
        fn desc(&self) -> &ModuleDesc {
            &self.desc
        }

        fn commit(
            &self,
            params: &Map<String, Value>,
            _image: &ImageInfo,
        ) -> Result<CommitData, PipeError> {
            // Test gains are small; the downcast cannot lose them.
            #[expect(clippy::cast_possible_truncation)]
            let gain = crate::get_float(params, "gain").unwrap_or(2.0) as f32;
            Ok(Arc::new(DoublerCommit { gain }))
        }

        fn process(
            &self,
            data: &CommitData,
            input: &Plane<'_>,
            output: &mut PlaneMut<'_>,
            rin: Roi,
            rout: Roi,
        ) -> Result<(), PipeError> {
            let commit = data
                .downcast_ref::<DoublerCommit>()
                .ok_or_else(|| PipeError::Backend("doubler opened a foreign commit".to_owned()))?;
            if rin.width != rout.width || rin.height != rout.height {
                return Err(PipeError::RoiMismatch(
                    "doubler needs equal shapes".to_owned(),
                ));
            }
            for y in 0..rout.height.max(0).cast_unsigned() {
                let src = input.row(y)?;
                let dst = output.row_mut(y)?;
                for (to, from) in dst.iter_mut().zip(src.iter()) {
                    *to = *from * commit.gain;
                }
            }
            Ok(())
        }
    }

    fn stub_desc(id: &'static str) -> ModuleDesc {
        ModuleDesc::stub(
            id,
            OrderKey {
                priority: 1.0,
                tie: 0,
            },
            OrderKey {
                priority: 1.0,
                tie: 0,
            },
        )
    }

    fn image() -> ImageInfo {
        ImageInfo::new(4, 2, ColorSpace::Rgb)
    }

    /// Second local module: fills the output with zeros.
    struct Zeroer {
        desc: ModuleDesc,
    }

    struct ZeroerCommit;

    impl IopModule for Zeroer {
        fn desc(&self) -> &ModuleDesc {
            &self.desc
        }

        fn commit(
            &self,
            _params: &Map<String, Value>,
            _image: &ImageInfo,
        ) -> Result<CommitData, PipeError> {
            Ok(Arc::new(ZeroerCommit))
        }

        fn process(
            &self,
            data: &CommitData,
            _input: &Plane<'_>,
            output: &mut PlaneMut<'_>,
            _rin: Roi,
            rout: Roi,
        ) -> Result<(), PipeError> {
            if data.downcast_ref::<ZeroerCommit>().is_none() {
                return Err(PipeError::Backend(
                    "zeroer opened a foreign commit".to_owned(),
                ));
            }
            for y in 0..rout.height.max(0).cast_unsigned() {
                output.row_mut(y)?.fill(0.0);
            }
            Ok(())
        }
    }

    #[test]
    fn two_different_modules_share_one_dyn_table() {
        // Object safety proof: two local modules of different types, one
        // Vec, dispatched through `dyn`. (The testkit identity joins the
        // same table shape in the pipeline tests; a dev-dependency here
        // would cycle the crates and split the trait type.)
        let doubler = Doubler {
            desc: stub_desc("test_doubler"),
        };
        let zeroer = Zeroer {
            desc: stub_desc("test_zeroer"),
        };
        let table: Vec<Arc<dyn IopModule>> = vec![Arc::new(doubler), Arc::new(zeroer)];
        assert_eq!(table[0].id(), "test_doubler");
        assert_eq!(table[1].id(), "test_zeroer");

        let params: Map<String, Value> =
            serde_json::from_str(r#"{"gain": {"type": "float", "value": 3.0}}"#).unwrap();
        let commits: Vec<CommitData> = table
            .iter()
            .map(|module| module.commit(&params, &image()).unwrap())
            .collect();

        let rin = Roi::new(0, 0, 4, 2, 1.0);
        for (module, data) in table.iter().zip(&commits) {
            // Default roi pair and tiling: identity and dt's default factor.
            assert_eq!(module.roi_out(data, rin), rin);
            assert_eq!(module.roi_in(data, rin), rin);
            assert_eq!(module.tiling(data, &rin, &rin).factor, 2.0);
        }

        // Each module processes through the same `dyn` call shape.
        let backing = vec![1.0f32; 4 * 2 * 4];
        let input = Plane::from_slice(&backing, 4, 2, 16).unwrap();
        let mut out_a = vec![0.0f32; 4 * 2 * 4];
        {
            let mut plane_a = PlaneMut::from_slice(&mut out_a, 4, 2, 16).unwrap();
            table[0]
                .process(&commits[0], &input, &mut plane_a, rin, rin)
                .unwrap();
        }
        assert!(out_a.iter().all(|v| v.to_bits() == 3.0f32.to_bits()));

        let mut out_b = vec![9.0f32; 4 * 2 * 4];
        {
            let mut plane_b = PlaneMut::from_slice(&mut out_b, 4, 2, 16).unwrap();
            table[1]
                .process(&commits[1], &input, &mut plane_b, rin, rin)
                .unwrap();
        }
        assert!(out_b.iter().all(|v| *v == 0.0));
    }

    #[test]
    fn foreign_commit_is_a_backend_error() {
        let doubler = Doubler {
            desc: stub_desc("test_doubler"),
        };
        let foreign: CommitData = Arc::new(7u32);
        let backing = vec![1.0f32; 4];
        let input = Plane::from_slice(&backing, 1, 1, 4).unwrap();
        let mut out = vec![0.0f32; 4];
        let mut plane = PlaneMut::from_slice(&mut out, 1, 1, 4).unwrap();
        let roi = Roi::new(0, 0, 1, 1, 1.0);
        let err = doubler
            .process(&foreign, &input, &mut plane, roi, roi)
            .unwrap_err();
        assert!(matches!(err, PipeError::Backend(_)));
    }

    #[test]
    fn undescribed_module_defaults_to_rgb_pair_and_no_flags() {
        let doubler = Doubler {
            desc: stub_desc("test_doubler"),
        };
        assert_eq!(doubler.colorspaces(), (ColorSpace::Rgb, ColorSpace::Rgb));
        assert_eq!(doubler.flags(), crate::ModuleFlags::empty());
    }
    #[test]
    fn default_output_format_is_identity() {
        let doubler = Doubler {
            desc: stub_desc("test_doubler"),
        };
        assert_eq!(
            doubler.output_format(crate::PixelFormat::RgbaF32Premul),
            crate::PixelFormat::RgbaF32Premul
        );
        assert_eq!(
            doubler.output_format(crate::PixelFormat::MonoF32),
            crate::PixelFormat::MonoF32
        );
    }
}
