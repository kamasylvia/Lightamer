// SPDX-License-Identifier: GPL-3.0-or-later
//! Fake modules for pipeline tests. Ids are `mod_*` on purpose: the
//! `check-no-iop-names` task fails this crate on any darktable module name.

#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

use std::collections::HashMap;
use std::sync::Arc;

use lightamer_iop_traits::{
    ColorSpace, CommitData, ImageInfo, IopModule, ModuleDesc, OrderKey, PipeError, Plane, PlaneMut,
    Roi,
};
use serde_json::{Map, Value};

use super::chain::SharedModule;

fn desc(id: &'static str) -> ModuleDesc {
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

/// Unit commit shared by geometry-only fakes.
#[derive(Debug)]
pub struct FakeCommit;

/// Scales geometry by `num/den` forward, `den/num` back. Even sizes round-trip
/// exactly; odd sizes follow the stated rule (out: round-half-up via
/// `(v * n + d / 2) / d`; in: truncating `(v * d) / n`).
pub struct FakeScale {
    desc: ModuleDesc,
    num: i64,
    den: i64,
    colors: Option<(ColorSpace, ColorSpace)>,
}

impl FakeScale {
    pub fn new(id: &'static str, num: i64, den: i64) -> Self {
        Self {
            desc: desc(id),
            num,
            den,
            colors: None,
        }
    }

    pub fn with_colors(mut self, input: ColorSpace, output: ColorSpace) -> Self {
        self.colors = Some((input, output));
        self
    }

    fn scale_out(&self, v: i32) -> i32 {
        let scaled = i64::from(v) * self.num;
        let rounded = if scaled >= 0 {
            (scaled + self.den / 2) / self.den
        } else {
            (scaled - self.den / 2) / self.den
        };
        i32::try_from(rounded.clamp(i64::from(i32::MIN), i64::from(i32::MAX))).unwrap_or(0)
    }

    fn scale_in(&self, v: i32) -> i32 {
        let scaled = (i64::from(v) * self.den) / self.num;
        i32::try_from(scaled.clamp(i64::from(i32::MIN), i64::from(i32::MAX))).unwrap_or(0)
    }
}

impl IopModule for FakeScale {
    fn desc(&self) -> &ModuleDesc {
        &self.desc
    }

    fn colorspaces(&self) -> (ColorSpace, ColorSpace) {
        self.colors.unwrap_or((ColorSpace::Rgb, ColorSpace::Rgb))
    }

    fn commit(
        &self,
        _params: &Map<String, Value>,
        _image: &ImageInfo,
    ) -> Result<CommitData, PipeError> {
        Ok(Arc::new(FakeCommit))
    }

    fn roi_out(&self, _data: &CommitData, rin: Roi) -> Roi {
        Roi::new(
            self.scale_out(rin.x),
            self.scale_out(rin.y),
            self.scale_out(rin.width),
            self.scale_out(rin.height),
            rin.scale,
        )
    }

    fn roi_in(&self, _data: &CommitData, rout: Roi) -> Roi {
        Roi::new(
            self.scale_in(rout.x),
            self.scale_in(rout.y),
            self.scale_in(rout.width),
            self.scale_in(rout.height),
            rout.scale,
        )
    }

    fn process(
        &self,
        _data: &CommitData,
        _input: &Plane<'_>,
        _output: &mut PlaneMut<'_>,
        _rin: Roi,
        _rout: Roi,
    ) -> Result<(), PipeError> {
        Err(PipeError::Backend(
            "geometry-only fake never processes".to_owned(),
        ))
    }
}

/// Shifts geometry by `(dx, dy)`: `roi_in` adds, `roi_out` subtracts.
pub struct FakeShift {
    desc: ModuleDesc,
    dx: i32,
    dy: i32,
}

impl FakeShift {
    pub fn new(id: &'static str, dx: i32, dy: i32) -> Self {
        Self {
            desc: desc(id),
            dx,
            dy,
        }
    }
}

impl IopModule for FakeShift {
    fn desc(&self) -> &ModuleDesc {
        &self.desc
    }

    fn commit(
        &self,
        _params: &Map<String, Value>,
        _image: &ImageInfo,
    ) -> Result<CommitData, PipeError> {
        Ok(Arc::new(FakeCommit))
    }

    fn roi_out(&self, _data: &CommitData, rin: Roi) -> Roi {
        Roi::new(
            rin.x.saturating_sub(self.dx),
            rin.y.saturating_sub(self.dy),
            rin.width,
            rin.height,
            rin.scale,
        )
    }

    fn roi_in(&self, _data: &CommitData, rout: Roi) -> Roi {
        Roi::new(
            rout.x.saturating_add(self.dx),
            rout.y.saturating_add(self.dy),
            rout.width,
            rout.height,
            rout.scale,
        )
    }

    fn process(
        &self,
        _data: &CommitData,
        _input: &Plane<'_>,
        _output: &mut PlaneMut<'_>,
        _rin: Roi,
        _rout: Roi,
    ) -> Result<(), PipeError> {
        Err(PipeError::Backend(
            "geometry-only fake never processes".to_owned(),
        ))
    }
}

/// Crops: `roi_in` grows by `(dw, dh)` at offset `(dx, dy)`, `roi_out`
/// undoes both.
pub struct FakeCrop {
    desc: ModuleDesc,
    dx: i32,
    dy: i32,
    dw: i32,
    dh: i32,
}

impl FakeCrop {
    pub fn new(id: &'static str, dx: i32, dy: i32, dw: i32, dh: i32) -> Self {
        Self {
            desc: desc(id),
            dx,
            dy,
            dw,
            dh,
        }
    }
}

impl IopModule for FakeCrop {
    fn desc(&self) -> &ModuleDesc {
        &self.desc
    }

    fn commit(
        &self,
        _params: &Map<String, Value>,
        _image: &ImageInfo,
    ) -> Result<CommitData, PipeError> {
        Ok(Arc::new(FakeCommit))
    }

    fn roi_out(&self, _data: &CommitData, rin: Roi) -> Roi {
        Roi::new(
            rin.x.saturating_sub(self.dx),
            rin.y.saturating_sub(self.dy),
            rin.width.saturating_sub(self.dw).max(0),
            rin.height.saturating_sub(self.dh).max(0),
            rin.scale,
        )
    }

    fn roi_in(&self, _data: &CommitData, rout: Roi) -> Roi {
        Roi::new(
            rout.x.saturating_add(self.dx),
            rout.y.saturating_add(self.dy),
            rout.width.saturating_add(self.dw).max(0),
            rout.height.saturating_add(self.dh).max(0),
            rout.scale,
        )
    }

    fn process(
        &self,
        _data: &CommitData,
        _input: &Plane<'_>,
        _output: &mut PlaneMut<'_>,
        _rin: Roi,
        _rout: Roi,
    ) -> Result<(), PipeError> {
        Err(PipeError::Backend(
            "geometry-only fake never processes".to_owned(),
        ))
    }
}

/// Needs no input at all: `roi_in` is always empty.
pub struct FakeSink {
    desc: ModuleDesc,
}

impl FakeSink {
    pub fn new(id: &'static str) -> Self {
        Self { desc: desc(id) }
    }
}

impl IopModule for FakeSink {
    fn desc(&self) -> &ModuleDesc {
        &self.desc
    }

    fn commit(
        &self,
        _params: &Map<String, Value>,
        _image: &ImageInfo,
    ) -> Result<CommitData, PipeError> {
        Ok(Arc::new(FakeCommit))
    }

    fn roi_in(&self, _data: &CommitData, rout: Roi) -> Roi {
        Roi::new(0, 0, 0, 0, rout.scale)
    }

    fn process(
        &self,
        _data: &CommitData,
        _input: &Plane<'_>,
        _output: &mut PlaneMut<'_>,
        _rin: Roi,
        _rout: Roi,
    ) -> Result<(), PipeError> {
        Err(PipeError::Backend(
            "geometry-only fake never processes".to_owned(),
        ))
    }
}

/// Returns a malformed region (negative width).
pub struct FakeBadRoi {
    desc: ModuleDesc,
}

impl FakeBadRoi {
    pub fn new(id: &'static str) -> Self {
        Self { desc: desc(id) }
    }
}

impl IopModule for FakeBadRoi {
    fn desc(&self) -> &ModuleDesc {
        &self.desc
    }

    fn commit(
        &self,
        _params: &Map<String, Value>,
        _image: &ImageInfo,
    ) -> Result<CommitData, PipeError> {
        Ok(Arc::new(FakeCommit))
    }

    fn roi_in(&self, _data: &CommitData, rout: Roi) -> Roi {
        Roi::new(rout.x, rout.y, -4, rout.height, rout.scale)
    }

    fn process(
        &self,
        _data: &CommitData,
        _input: &Plane<'_>,
        _output: &mut PlaneMut<'_>,
        _rin: Roi,
        _rout: Roi,
    ) -> Result<(), PipeError> {
        Err(PipeError::Backend(
            "geometry-only fake never processes".to_owned(),
        ))
    }
}

/// Refuses every commit.
pub struct FakeFail {
    desc: ModuleDesc,
}

impl FakeFail {
    pub fn new(id: &'static str) -> Self {
        Self { desc: desc(id) }
    }
}

impl IopModule for FakeFail {
    fn desc(&self) -> &ModuleDesc {
        &self.desc
    }

    fn commit(
        &self,
        _params: &Map<String, Value>,
        _image: &ImageInfo,
    ) -> Result<CommitData, PipeError> {
        Err(PipeError::InvalidParams(
            "mod_fail refuses everything".to_owned(),
        ))
    }

    fn process(
        &self,
        _data: &CommitData,
        _input: &Plane<'_>,
        _output: &mut PlaneMut<'_>,
        _rin: Roi,
        _rout: Roi,
    ) -> Result<(), PipeError> {
        Err(PipeError::Backend(
            "uncommittable fake never processes".to_owned(),
        ))
    }
}

/// Lookup table builder for tests.
pub fn table(modules: Vec<SharedModule>) -> HashMap<String, SharedModule> {
    modules
        .into_iter()
        .map(|module| (module.id().to_owned(), module))
        .collect()
}

/// Empty parameters.
pub fn no_params() -> Map<String, Value> {
    Map::new()
}
