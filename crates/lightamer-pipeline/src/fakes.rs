// SPDX-License-Identifier: GPL-3.0-or-later
//! Fake modules for pipeline tests. Ids are `mod_*` on purpose: the
//! `check-no-iop-names` task fails this crate on any darktable module name.

#![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

use std::collections::HashMap;
use std::sync::{Arc, Mutex, atomic::AtomicUsize};

use lightamer_iop_traits::{
    ColorSpace, CommitData, ImageInfo, IopModule, ModuleDesc, OrderKey, PipeError, Plane, PlaneMut,
    Roi, TilingReq, get_float,
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

/// Shared probe behind counting fakes: how often `process` ran and which
/// regions it saw, per module instance.
#[derive(Debug, Default)]
pub struct Probe {
    calls: AtomicUsize,
    regions: Mutex<Vec<(Roi, Roi)>>,
}

impl Probe {
    /// An untouched probe.
    pub fn new() -> Self {
        Self::default()
    }

    /// `process` calls so far.
    pub fn calls(&self) -> usize {
        self.calls.load(std::sync::atomic::Ordering::SeqCst)
    }

    /// `(rin, rout)` per call, in call order.
    pub fn regions(&self) -> Vec<(Roi, Roi)> {
        self.regions.lock().unwrap().clone()
    }

    fn record(&self, rin: Roi, rout: Roi) {
        self.calls.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        self.regions.lock().unwrap().push((rin, rout));
    }
}

/// Copies its input to its output, counting calls and regions.
pub struct FakeCopy {
    desc: ModuleDesc,
    probe: Arc<Probe>,
}

impl FakeCopy {
    /// A copying fake behind `id`, reporting to `probe`.
    pub fn new(id: &'static str, probe: Arc<Probe>) -> Self {
        Self {
            desc: desc(id),
            probe,
        }
    }

    /// Copies input rows to output rows; both planes must match `rin`/`rout`.
    pub fn copy_planes(
        input: &Plane<'_>,
        output: &mut PlaneMut<'_>,
        rin: Roi,
        rout: Roi,
    ) -> Result<(), PipeError> {
        if rin.width != rout.width || rin.height != rout.height {
            return Err(PipeError::RoiMismatch(format!(
                "copy fake needs equal shapes, got {}x{} in and {}x{} out",
                rin.width, rin.height, rout.width, rout.height
            )));
        }
        if input.width() != output.width() || input.height() != output.height() {
            return Err(PipeError::RoiMismatch(format!(
                "copy fake planes differ: {}x{} vs {}x{}",
                input.width(),
                input.height(),
                output.width(),
                output.height()
            )));
        }
        for y in 0..rout.height.max(0).cast_unsigned() {
            let src = input.row(y)?;
            let dst = output.row_mut(y)?;
            if src.len() != dst.len() {
                return Err(PipeError::RoiMismatch(format!(
                    "copy fake row {y} lengths differ: {} vs {}",
                    src.len(),
                    dst.len()
                )));
            }
            dst.copy_from_slice(src);
        }
        Ok(())
    }
}

impl IopModule for FakeCopy {
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

    fn process(
        &self,
        _data: &CommitData,
        input: &Plane<'_>,
        output: &mut PlaneMut<'_>,
        rin: Roi,
        rout: Roi,
    ) -> Result<(), PipeError> {
        self.probe.record(rin, rout);
        Self::copy_planes(input, output, rin, rout)
    }
}

/// Per-instance gain from `{"gain": {"type": "float", "value": g}}`.
#[derive(Debug)]
pub struct GainCommit {
    gain: f32,
}

/// Multiplies every pixel by its `gain` parameter, counting calls.
pub struct FakeGain {
    desc: ModuleDesc,
    probe: Arc<Probe>,
}

impl FakeGain {
    /// A gain fake behind `id`, reporting to `probe`.
    pub fn new(id: &'static str, probe: Arc<Probe>) -> Self {
        Self {
            desc: desc(id),
            probe,
        }
    }
}

impl IopModule for FakeGain {
    fn desc(&self) -> &ModuleDesc {
        &self.desc
    }

    fn commit(
        &self,
        params: &Map<String, Value>,
        _image: &ImageInfo,
    ) -> Result<CommitData, PipeError> {
        #[expect(clippy::cast_possible_truncation)]
        // test gains are small; the downcast cannot lose them
        let gain = get_float(params, "gain")? as f32;
        Ok(Arc::new(GainCommit { gain }))
    }

    fn process(
        &self,
        data: &CommitData,
        input: &Plane<'_>,
        output: &mut PlaneMut<'_>,
        rin: Roi,
        rout: Roi,
    ) -> Result<(), PipeError> {
        self.probe.record(rin, rout);
        let Some(commit) = data.downcast_ref::<GainCommit>() else {
            return Err(PipeError::Backend(
                "gain fake opened a foreign commit".to_owned(),
            ));
        };
        FakeCopy::copy_planes(input, output, rin, rout)?;
        for y in 0..rout.height.max(0).cast_unsigned() {
            let dst = output.row_mut(y)?;
            for value in dst.iter_mut() {
                *value *= commit.gain;
            }
        }
        Ok(())
    }
}

/// Copies like [`FakeCopy`] but reports a heavy tiling request, forcing grids.
pub struct FakeMem {
    desc: ModuleDesc,
    probe: Arc<Probe>,
    factor: f32,
    overlap: u32,
}

impl FakeMem {
    /// A copying fake with `factor`/`overlap` tiling needs.
    pub fn new(id: &'static str, probe: Arc<Probe>, factor: f32, overlap: u32) -> Self {
        Self {
            desc: desc(id),
            probe,
            factor,
            overlap,
        }
    }
}

impl IopModule for FakeMem {
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

    fn tiling(&self, _data: &CommitData, _rin: &Roi, _rout: &Roi) -> TilingReq {
        TilingReq {
            factor: self.factor,
            maxbuf: 1.0,
            overhead: 0,
            overlap: self.overlap,
            align: 1,
        }
    }

    fn process(
        &self,
        _data: &CommitData,
        input: &Plane<'_>,
        output: &mut PlaneMut<'_>,
        rin: Roi,
        rout: Roi,
    ) -> Result<(), PipeError> {
        self.probe.record(rin, rout);
        FakeCopy::copy_planes(input, output, rin, rout)
    }
}

/// Writes a per-pixel value derived from absolute coordinates, ignoring its
/// input: `v = (x * 131 + y) as f32` in all four channels. Tiled and untiled
/// runs agree bitwise because the value only depends on where the pixel is.
pub struct FakePosition {
    desc: ModuleDesc,
    probe: Arc<Probe>,
}

impl FakePosition {
    /// A position-writing fake behind `id`, reporting to `probe`.
    pub fn new(id: &'static str, probe: Arc<Probe>) -> Self {
        Self {
            desc: desc(id),
            probe,
        }
    }
}

impl IopModule for FakePosition {
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

    fn tiling(&self, _data: &CommitData, _rin: &Roi, _rout: &Roi) -> TilingReq {
        TilingReq {
            factor: 8.0,
            maxbuf: 1.0,
            overhead: 0,
            overlap: 4,
            align: 1,
        }
    }

    fn process(
        &self,
        _data: &CommitData,
        input: &Plane<'_>,
        output: &mut PlaneMut<'_>,
        rin: Roi,
        rout: Roi,
    ) -> Result<(), PipeError> {
        self.probe.record(rin, rout);
        if input.width() != output.width() || input.height() != output.height() {
            return Err(PipeError::RoiMismatch(format!(
                "position fake planes differ: {}x{} vs {}x{}",
                input.width(),
                input.height(),
                output.width(),
                output.height()
            )));
        }
        for y in 0..rout.height.max(0).cast_unsigned() {
            let dst = output.row_mut(y)?;
            let gy = i64::from(rout.y) + i64::from(y);
            let pixels = dst.len() / 4;
            for lx in 0..pixels {
                let local = i64::try_from(lx).unwrap_or(0);
                let gx = i64::from(rout.x) + local;
                #[expect(clippy::cast_precision_loss)]
                // test coordinates are small; the conversion is exact
                let value = (gx * 131 + gy) as f32;
                let base = lx * 4;
                dst[base] = value;
                dst[base + 1] = value;
                dst[base + 2] = value;
                dst[base + 3] = value;
            }
        }
        Ok(())
    }
}

/// Scales geometry like [`FakeScale`] and fills its output with ones,
/// validating that both planes match the regions the pipe passes in.
pub struct FakeScaleCopy {
    desc: ModuleDesc,
    probe: Arc<Probe>,
    num: i64,
    den: i64,
}

impl FakeScaleCopy {
    /// A scaling fake (`num`/`den`), reporting to `probe`.
    pub fn new(id: &'static str, probe: Arc<Probe>, num: i64, den: i64) -> Self {
        Self {
            desc: desc(id),
            probe,
            num,
            den,
        }
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

impl IopModule for FakeScaleCopy {
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
        input: &Plane<'_>,
        output: &mut PlaneMut<'_>,
        rin: Roi,
        rout: Roi,
    ) -> Result<(), PipeError> {
        self.probe.record(rin, rout);
        let (Ok(rw), Ok(rh), Ok(ow), Ok(oh)) = (
            u32::try_from(rin.width),
            u32::try_from(rin.height),
            u32::try_from(rout.width),
            u32::try_from(rout.height),
        ) else {
            return Err(PipeError::RoiMismatch(
                "scale fake got negative regions".to_owned(),
            ));
        };
        if input.width() != rw || input.height() != rh {
            return Err(PipeError::RoiMismatch(format!(
                "scale fake input is {}x{}, region says {rw}x{rh}",
                input.width(),
                input.height()
            )));
        }
        if output.width() != ow || output.height() != oh {
            return Err(PipeError::RoiMismatch(format!(
                "scale fake output is {}x{}, region says {ow}x{oh}",
                output.width(),
                output.height()
            )));
        }
        for y in 0..oh {
            output.row_mut(y)?.fill(1.0);
        }
        Ok(())
    }
}

/// A source module: needs no input (`roi_in` is empty), produces a fixed
/// `width` by `height` frame, fills it with threes.
pub struct FakeSource {
    desc: ModuleDesc,
    probe: Arc<Probe>,
    width: i32,
    height: i32,
}

impl FakeSource {
    /// A source fake producing `width` by `height`, reporting to `probe`.
    pub fn new(id: &'static str, probe: Arc<Probe>, width: i32, height: i32) -> Self {
        Self {
            desc: desc(id),
            probe,
            width,
            height,
        }
    }
}

impl IopModule for FakeSource {
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
        Roi::new(0, 0, self.width, self.height, rin.scale)
    }

    fn roi_in(&self, _data: &CommitData, rout: Roi) -> Roi {
        Roi::new(0, 0, 0, 0, rout.scale)
    }

    fn process(
        &self,
        _data: &CommitData,
        input: &Plane<'_>,
        output: &mut PlaneMut<'_>,
        rin: Roi,
        rout: Roi,
    ) -> Result<(), PipeError> {
        self.probe.record(rin, rout);
        if input.width() != 0 || input.height() != 0 {
            return Err(PipeError::RoiMismatch(format!(
                "source fake input must be empty, got {}x{}",
                input.width(),
                input.height()
            )));
        }
        for y in 0..rout.height.max(0).cast_unsigned() {
            output.row_mut(y)?.fill(3.0);
        }
        Ok(())
    }
}

/// Commits fine, then fails `process` with a backend error (after recording).
pub struct FakeBackendFail {
    desc: ModuleDesc,
    probe: Arc<Probe>,
}

impl FakeBackendFail {
    /// A backend-failing fake behind `id`, reporting to `probe`.
    pub fn new(id: &'static str, probe: Arc<Probe>) -> Self {
        Self {
            desc: desc(id),
            probe,
        }
    }
}

impl IopModule for FakeBackendFail {
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

    fn process(
        &self,
        _data: &CommitData,
        _input: &Plane<'_>,
        _output: &mut PlaneMut<'_>,
        rin: Roi,
        rout: Roi,
    ) -> Result<(), PipeError> {
        self.probe.record(rin, rout);
        Err(PipeError::Backend(
            "mod_backendfail always fails".to_owned(),
        ))
    }
}

/// Separable box blur of radius `actual`, claiming `overlap` in its tiling
/// request. Honest when the two agree; a liar when `claimed < actual`
/// (streaming then starves it of context and the seams show).
///
/// Summation order (both passes): rows top to bottom, pixels left to right,
/// taps low to high, `+=` accumulation, one `/ count` per pass. The streaming
/// tests feed it constant fields, where the blur is exact whatever the order.
pub struct FakeBlur {
    desc: ModuleDesc,
    probe: Arc<Probe>,
    actual: u32,
    claimed: u32,
}

impl FakeBlur {
    /// A blur fake behind `id`, reporting to `probe`.
    pub fn new(id: &'static str, probe: Arc<Probe>, actual: u32, claimed: u32) -> Self {
        Self {
            desc: desc(id),
            probe,
            actual,
            claimed,
        }
    }
}

impl IopModule for FakeBlur {
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

    fn tiling(&self, _data: &CommitData, _rin: &Roi, _rout: &Roi) -> TilingReq {
        TilingReq {
            factor: 2.0,
            maxbuf: 1.0,
            overhead: 0,
            overlap: self.claimed,
            align: 1,
        }
    }

    fn process(
        &self,
        _data: &CommitData,
        input: &Plane<'_>,
        output: &mut PlaneMut<'_>,
        rin: Roi,
        rout: Roi,
    ) -> Result<(), PipeError> {
        self.probe.record(rin, rout);
        if input.width() != output.width() || input.height() != output.height() {
            return Err(PipeError::RoiMismatch(format!(
                "blur fake planes differ: {}x{} vs {}x{}",
                input.width(),
                input.height(),
                output.width(),
                output.height()
            )));
        }
        let width = usize::try_from(input.width()).unwrap_or(0);
        let height = usize::try_from(input.height()).unwrap_or(0);
        let radius = usize::try_from(self.actual).unwrap_or(0);
        let span = radius.saturating_mul(2).saturating_add(1);
        #[expect(clippy::cast_precision_loss)]
        // test radii stay far below 2^24; the conversion is exact
        let count = span as f32;
        // Horizontal pass into a scratch plane, then vertical into output.
        let mut tmp = vec![0.0f32; width.saturating_mul(height).saturating_mul(4)];
        for y in 0..height {
            let src = input.row(u32::try_from(y).unwrap_or(u32::MAX))?;
            for x in 0..width {
                for c in 0..4 {
                    let mut sum = 0.0f32;
                    for tap in 0..span {
                        let sx = x
                            .saturating_add(tap)
                            .saturating_sub(radius)
                            .min(width.saturating_sub(1));
                        sum += src[sx * 4 + c];
                    }
                    tmp[(y * width + x) * 4 + c] = sum / count;
                }
            }
        }
        for y in 0..height {
            let dst = output.row_mut(u32::try_from(y).unwrap_or(u32::MAX))?;
            for x in 0..width {
                for c in 0..4 {
                    let mut sum = 0.0f32;
                    for tap in 0..span {
                        let sy = y
                            .saturating_add(tap)
                            .saturating_sub(radius)
                            .min(height.saturating_sub(1));
                        sum += tmp[(sy * width + x) * 4 + c];
                    }
                    dst[x * 4 + c] = sum / count;
                }
            }
        }
        Ok(())
    }
}

/// Transposes regions about the origin and shifts them one pixel: a
/// geometry-changing module streaming must refuse. `roi_out` inverts
/// `roi_in`, so the round-trip check passes and admission is what refuses.
pub struct FakeSpin {
    desc: ModuleDesc,
    probe: Arc<Probe>,
}

impl FakeSpin {
    /// A transposing fake behind `id`, reporting to `probe`.
    pub fn new(id: &'static str, probe: Arc<Probe>) -> Self {
        Self {
            desc: desc(id),
            probe,
        }
    }
}

impl IopModule for FakeSpin {
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
            rin.y,
            rin.x.saturating_sub(1),
            rin.height,
            rin.width,
            rin.scale,
        )
    }

    fn roi_in(&self, _data: &CommitData, rout: Roi) -> Roi {
        Roi::new(
            rout.y.saturating_add(1),
            rout.x,
            rout.height,
            rout.width,
            rout.scale,
        )
    }

    fn process(
        &self,
        _data: &CommitData,
        _input: &Plane<'_>,
        _output: &mut PlaneMut<'_>,
        rin: Roi,
        rout: Roi,
    ) -> Result<(), PipeError> {
        self.probe.record(rin, rout);
        Err(PipeError::Backend(
            "spin fake is refused before it ever processes".to_owned(),
        ))
    }
}

/// Copies like [`FakeCopy`] but declares whole-image statistics.
pub struct FakeWhole {
    desc: ModuleDesc,
    probe: Arc<Probe>,
}

impl FakeWhole {
    /// A whole-image fake behind `id`, reporting to `probe`.
    pub fn new(id: &'static str, probe: Arc<Probe>) -> Self {
        Self {
            desc: desc(id),
            probe,
        }
    }
}

impl IopModule for FakeWhole {
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

    fn stats(&self) -> lightamer_iop_traits::StatsNeeds {
        lightamer_iop_traits::StatsNeeds::WholeImage
    }

    fn process(
        &self,
        _data: &CommitData,
        input: &Plane<'_>,
        output: &mut PlaneMut<'_>,
        rin: Roi,
        rout: Roi,
    ) -> Result<(), PipeError> {
        self.probe.record(rin, rout);
        FakeCopy::copy_planes(input, output, rin, rout)
    }
}

/// Copies like [`FakeCopy`] but declares proxy statistics.
pub struct FakeProxy {
    desc: ModuleDesc,
    probe: Arc<Probe>,
}

impl FakeProxy {
    /// A proxy-stats fake behind `id`, reporting to `probe`.
    pub fn new(id: &'static str, probe: Arc<Probe>) -> Self {
        Self {
            desc: desc(id),
            probe,
        }
    }
}

impl IopModule for FakeProxy {
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

    fn stats(&self) -> lightamer_iop_traits::StatsNeeds {
        lightamer_iop_traits::StatsNeeds::Proxy {
            max_long_edge: 2048,
        }
    }

    fn process(
        &self,
        _data: &CommitData,
        input: &Plane<'_>,
        output: &mut PlaneMut<'_>,
        rin: Roi,
        rout: Roi,
    ) -> Result<(), PipeError> {
        self.probe.record(rin, rout);
        FakeCopy::copy_planes(input, output, rin, rout)
    }
}

/// Grows its input region by `grow` pixels per side (shrinking back in
/// `roi_out`, so the round-trip check passes) while claiming `overlap`.
/// A halo expressed through regions instead of the tiling request: admission
/// takes it when the claim covers the growth and refuses it otherwise.
pub struct FakeGrow {
    desc: ModuleDesc,
    probe: Arc<Probe>,
    grow: u32,
    overlap: u32,
}

impl FakeGrow {
    /// A growing fake behind `id`, reporting to `probe`.
    pub fn new(id: &'static str, probe: Arc<Probe>, grow: u32, overlap: u32) -> Self {
        Self {
            desc: desc(id),
            probe,
            overlap,
            grow,
        }
    }
}

impl IopModule for FakeGrow {
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
        let grow = i32::try_from(self.grow).unwrap_or(0);
        Roi::new(
            rin.x.saturating_add(grow),
            rin.y.saturating_add(grow),
            rin.width.saturating_sub(grow.saturating_mul(2)).max(0),
            rin.height.saturating_sub(grow.saturating_mul(2)).max(0),
            rin.scale,
        )
    }

    fn roi_in(&self, _data: &CommitData, rout: Roi) -> Roi {
        let grow = i32::try_from(self.grow).unwrap_or(0);
        Roi::new(
            rout.x.saturating_sub(grow),
            rout.y.saturating_sub(grow),
            rout.width.saturating_add(grow.saturating_mul(2)),
            rout.height.saturating_add(grow.saturating_mul(2)),
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
        input: &Plane<'_>,
        output: &mut PlaneMut<'_>,
        rin: Roi,
        rout: Roi,
    ) -> Result<(), PipeError> {
        self.probe.record(rin, rout);
        FakeCopy::copy_planes(input, output, rin, rout)
    }
}
