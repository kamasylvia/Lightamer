// SPDX-License-Identifier: GPL-3.0-or-later
//! Identity test module: copies its input to its output unchanged.

use std::sync::Arc;

use lightamer_iop_traits::{
    CommitData, ImageInfo, IopModule, ModuleDesc, OrderKey, PipeError, Plane, PlaneMut, Roi,
    par_map_rows,
};
use serde_json::{Map, Value};

/// Opaque commit product of [`IdentityModule`]; carries nothing.
#[derive(Debug)]
pub struct IdentityCommit;

/// Test-only module behind id `test_identity`: default roi pair, default
/// tiling, `process` copies input rows to output rows.
#[derive(Debug)]
pub struct IdentityModule {
    desc: ModuleDesc,
}

impl IdentityModule {
    /// Builds the identity module.
    #[must_use]
    pub fn new() -> Self {
        Self {
            desc: ModuleDesc::stub(
                "test_identity",
                OrderKey {
                    priority: 0.0,
                    tie: 0,
                },
                OrderKey {
                    priority: 0.0,
                    tie: 0,
                },
            ),
        }
    }
}

impl Default for IdentityModule {
    fn default() -> Self {
        Self::new()
    }
}

impl IopModule for IdentityModule {
    fn desc(&self) -> &ModuleDesc {
        &self.desc
    }

    fn commit(
        &self,
        _params: &Map<String, Value>,
        _image: &ImageInfo,
    ) -> Result<CommitData, PipeError> {
        Ok(Arc::new(IdentityCommit))
    }

    fn process(
        &self,
        data: &CommitData,
        input: &Plane<'_>,
        output: &mut PlaneMut<'_>,
        rin: Roi,
        rout: Roi,
    ) -> Result<(), PipeError> {
        if data.downcast_ref::<IdentityCommit>().is_none() {
            return Err(PipeError::Backend(
                "identity opened a foreign commit".to_owned(),
            ));
        }
        if rin.width != rout.width || rin.height != rout.height {
            return Err(PipeError::RoiMismatch(format!(
                "identity needs equal shapes, got {}x{} in and {}x{} out",
                rin.width, rin.height, rout.width, rout.height
            )));
        }
        if input.width() != output.width() || input.height() != output.height() {
            return Err(PipeError::RoiMismatch(format!(
                "identity planes differ: {}x{} vs {}x{}",
                input.width(),
                input.height(),
                output.width(),
                output.height()
            )));
        }
        let rows = usize::try_from(rout.height.max(0)).map_err(|_| {
            PipeError::RoiMismatch(format!("identity height {} overflows", rout.height))
        })?;
        let row_len = usize::try_from(input.width())
            .ok()
            .and_then(|w| w.checked_mul(4))
            .ok_or_else(|| {
                PipeError::RoiMismatch(format!("identity width {} overflows", input.width()))
            })?;
        let src_stride = input.stride();
        let dst_stride = output.stride();
        par_map_rows(
            input.as_slice(),
            output.as_mut_slice(),
            rows,
            src_stride,
            dst_stride,
            row_len,
            |src, dst| dst.copy_from_slice(src),
        )
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{IdentityCommit, IdentityModule};
    use lightamer_iop_traits::{ColorSpace, IopModule};
    use std::sync::Arc;

    #[test]
    fn copies_input_to_output_unchanged() {
        let module = IdentityModule::new();
        assert_eq!(module.id(), "test_identity");
        let params = serde_json::Map::new();
        let image = lightamer_iop_traits::ImageInfo::new(4, 2, ColorSpace::Rgb);
        let data = module.commit(&params, &image).unwrap();
        assert!(data.downcast_ref::<IdentityCommit>().is_some());

        let roi = lightamer_iop_traits::Roi::new(0, 0, 4, 2, 1.0);
        assert_eq!(module.roi_out(&data, roi), roi);
        assert_eq!(module.roi_in(&data, roi), roi);

        let backing: Vec<f32> = (0i16..32).map(f32::from).collect();
        let input = lightamer_iop_traits::Plane::from_slice(&backing, 4, 2, 16).unwrap();
        let mut out = vec![0.0f32; 4 * 2 * 4];
        {
            let mut plane = lightamer_iop_traits::PlaneMut::from_slice(&mut out, 4, 2, 16).unwrap();
            module.process(&data, &input, &mut plane, roi, roi).unwrap();
        }
        assert_eq!(out, backing);
    }

    #[test]
    fn mismatched_shapes_are_rejected() {
        let module = IdentityModule::default();
        let data: Arc<dyn std::any::Any + Send + Sync> = Arc::new(IdentityCommit);
        let backing = vec![0.0f32; 16];
        let input = lightamer_iop_traits::Plane::from_slice(&backing, 2, 2, 8).unwrap();
        let mut out = vec![0.0f32; 16];
        let mut plane = lightamer_iop_traits::PlaneMut::from_slice(&mut out, 2, 2, 8).unwrap();
        let rin = lightamer_iop_traits::Roi::new(0, 0, 2, 2, 1.0);
        let rout = lightamer_iop_traits::Roi::new(0, 0, 3, 2, 1.0);
        assert!(
            module
                .process(&data, &input, &mut plane, rin, rout)
                .is_err()
        );
    }
}
