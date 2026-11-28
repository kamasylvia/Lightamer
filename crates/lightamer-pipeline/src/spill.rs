// SPDX-License-Identifier: GPL-3.0-or-later
//! Streaming output assembly: in RAM or spilled to a temp file.
//!
//! [`StreamSink`] collects the pieces a [`Pipe::render_stream`](super::render::Pipe::render_stream)
//! run hands out and joins them into one output frame. Outputs at or below a
//! caller-chosen memory threshold stay in RAM; bigger ones spill to an
//! anonymous temp file (Lumen `allocate`, `lumen/large_image.py:23-36`) that
//! the OS deletes on drop, so cancelled, failed, and finished runs leave no
//! residue. Total bytes face a caller-passed limit and refuse typed past it.

use std::fs::File;
use std::path::Path;

use lightamer_raster::{Frame, FrameExtent, PixelFormat};
use memmap2::MmapMut;

use super::render::RenderError;
use super::stream::StreamPiece;

// Bytes per pixel come from the sink's own format (never a constant: RGBA
// counts 16, mono counts 4).

/// Where an unfinished [`StreamSink`] writes its pieces.
#[derive(Debug)]
enum SinkStore {
    /// In-RAM frame.
    Memory(Frame),
    /// Memory-mapped temp file.
    Mapped(MappedFrame),
}

/// Collects streaming pieces into one output frame.
///
/// Created before the run (it needs the full extent, the memory threshold,
/// and the byte limit upfront), fed from the sink closure, finished after the
/// last piece. Dropping an unfinished sink deletes its temp file: cancel and
/// error paths leave nothing behind.
#[derive(Debug)]
pub struct StreamSink {
    /// The full output extent.
    full: FrameExtent,
    /// Pixel format of the assembled output.
    format: PixelFormat,
    /// Total output bytes.
    total: u64,
    /// Piece bytes received so far.
    received: u64,
    /// Where pieces land.
    store: SinkStore,
}

impl StreamSink {
    /// Prepares RGBA assembly of `full`: outputs of at most
    /// `memory_threshold` bytes stay in RAM, bigger ones spill to an
    /// anonymous temp file under `dir` (or the system temp directory when
    /// [`None`]), and anything past `byte_limit` refuses here, before the
    /// run starts.
    ///
    /// # Errors
    ///
    /// [`RenderError::Spill`] when the output exceeds `byte_limit`, overflows
    /// its byte count, or the temp file/mapping fails.
    pub fn new(
        full: FrameExtent,
        memory_threshold: u64,
        byte_limit: u64,
        dir: Option<&Path>,
    ) -> Result<Self, RenderError> {
        Self::new_with_format(
            full,
            PixelFormat::RgbaF32Premul,
            memory_threshold,
            byte_limit,
            dir,
        )
    }

    /// Prepares assembly of `full` in `format`: same contract as
    /// [`StreamSink::new`], sized by the format's own bytes per pixel.
    ///
    /// # Errors
    ///
    /// [`RenderError::Spill`] when the output exceeds `byte_limit`, overflows
    /// its byte count, or the temp file/mapping fails.
    pub fn new_with_format(
        full: FrameExtent,
        format: PixelFormat,
        memory_threshold: u64,
        byte_limit: u64,
        dir: Option<&Path>,
    ) -> Result<Self, RenderError> {
        let fail = |detail: String| RenderError::Spill { detail };
        let bpp = format.bytes_per_pixel();
        let total = full.area_u64().checked_mul(bpp).ok_or_else(|| {
            fail(format!(
                "streaming output {full:?} overflows its byte count"
            ))
        })?;
        if total > byte_limit {
            return Err(fail(format!(
                "streaming output needs {total} bytes over the {byte_limit}-byte limit"
            )));
        }
        // Empty outputs stay in RAM: a zero-length mapping is rejected
        // outright on some platforms.
        let store = if full.is_empty() || total <= memory_threshold {
            let frame = Frame::alloc(full, format)
                .map_err(|err| fail(format!("streaming assembly: {err}")))?;
            SinkStore::Memory(frame)
        } else {
            let file = match dir {
                Some(dir) => tempfile::tempfile_in(dir),
                None => tempfile::tempfile(),
            }
            .map_err(|err| fail(format!("streaming spill file: {err}")))?;
            file.set_len(total)
                .map_err(|err| fail(format!("streaming spill resize: {err}")))?;
            // SAFETY: the file is a private anonymous temp file sized before
            // mapping, held only here, and never touched except through this
            // mapping — no external modification can invalidate it.
            #[expect(unsafe_code)]
            let map = unsafe { MmapMut::map_mut(&file) }
                .map_err(|err| fail(format!("streaming spill map: {err}")))?;
            SinkStore::Mapped(MappedFrame {
                extent: full,
                map,
                file,
            })
        };
        Ok(Self {
            full,
            format,
            total,
            received: 0,
            store,
        })
    }

    /// Whether this sink spills to disk (`false` = assembling in RAM).
    #[must_use]
    pub fn spilled(&self) -> bool {
        matches!(self.store, SinkStore::Mapped(_))
    }

    /// Writes one piece into the output at its extent. Pieces may arrive in
    /// any order, but each output pixel must arrive exactly once: `finish`
    /// compares the received byte count against the total.
    ///
    /// # Errors
    ///
    /// [`RenderError::Spill`] when the piece leaves the output or its bytes
    /// disagree with its extent.
    pub fn push(&mut self, piece: &StreamPiece) -> Result<(), RenderError> {
        let fail = |detail: String| RenderError::Spill { detail };
        if !self.full.contains(piece.extent) {
            return Err(fail(format!(
                "stream piece {:?} leaves its output {:?}",
                piece.extent, self.full
            )));
        }
        if piece.plane.frame.format() != self.format {
            return Err(fail(format!(
                "stream piece {:?} is {:?}, sink assembles {:?}",
                piece.extent,
                piece.plane.frame.format(),
                self.format
            )));
        }
        let floats = piece.plane.frame.as_slice();
        let bytes: &[u8] = bytemuck::cast_slice(floats);
        let bpp = self.format.bytes_per_pixel();
        let want = piece
            .extent
            .area_u64()
            .checked_mul(bpp)
            .ok_or_else(|| fail(format!("stream piece {:?} overflows", piece.extent)))?;
        let got = u64::try_from(bytes.len())
            .map_err(|_| fail(format!("stream piece {:?} overflows", piece.extent)))?;
        if got != want {
            return Err(fail(format!(
                "stream piece {:?} holds {got} bytes, needs {want}",
                piece.extent
            )));
        }
        let fx = u64::from(self.full.width);
        let dx = piece
            .extent
            .x
            .checked_sub(self.full.x)
            .and_then(|off| u64::try_from(off).ok())
            .ok_or_else(|| fail(format!("stream piece {:?} overflows", piece.extent)))?;
        let dy = piece
            .extent
            .y
            .checked_sub(self.full.y)
            .and_then(|off| u64::try_from(off).ok())
            .ok_or_else(|| fail(format!("stream piece {:?} overflows", piece.extent)))?;
        let start = dy
            .checked_mul(fx)
            .and_then(|rows| rows.checked_add(dx))
            .and_then(|pixels| pixels.checked_mul(bpp))
            .ok_or_else(|| fail(format!("stream piece {:?} overflows", piece.extent)))?;
        let start = usize::try_from(start)
            .map_err(|_| fail(format!("stream piece {:?} overflows", piece.extent)))?;
        let end = start
            .checked_add(bytes.len())
            .ok_or_else(|| fail(format!("stream piece {:?} overflows", piece.extent)))?;
        // Pieces are contiguous runs of full output rows only when they span
        // the full width; otherwise each row lands separately.
        let full_rows = piece.extent.width == self.full.width;
        match &mut self.store {
            SinkStore::Memory(frame) => {
                let all = frame.as_mut_slice();
                let dst: &mut [u8] = bytemuck::cast_slice_mut(all);
                if full_rows {
                    let slot = dst
                        .get_mut(start..end)
                        .ok_or_else(|| fail("stream piece leaves its output".to_owned()))?;
                    slot.copy_from_slice(bytes);
                } else {
                    Self::copy_rows(dst, bytes, &self.full, &piece.extent, bpp)?;
                }
            }
            SinkStore::Mapped(mapped) => {
                if full_rows {
                    let slot = mapped
                        .map
                        .get_mut(start..end)
                        .ok_or_else(|| fail("stream piece leaves its output".to_owned()))?;
                    slot.copy_from_slice(bytes);
                } else {
                    Self::copy_rows(&mut mapped.map, bytes, &self.full, &piece.extent, bpp)?;
                }
            }
        }
        self.received = self.received.saturating_add(got);
        Ok(())
    }

    /// Copies a partial-width piece row by row into flat output bytes.
    fn copy_rows(
        dst: &mut [u8],
        src: &[u8],
        full: &FrameExtent,
        piece: &FrameExtent,
        bpp: u64,
    ) -> Result<(), RenderError> {
        let fail = |detail: String| RenderError::Spill { detail };
        let bpp = usize::try_from(bpp)
            .ok()
            .ok_or_else(|| fail("stream output stride overflows".to_owned()))?;
        let full_stride = usize::try_from(full.width)
            .ok()
            .and_then(|width| width.checked_mul(bpp))
            .ok_or_else(|| fail("stream output stride overflows".to_owned()))?;
        let piece_stride = usize::try_from(piece.width)
            .ok()
            .and_then(|width| width.checked_mul(bpp))
            .ok_or_else(|| fail("stream piece stride overflows".to_owned()))?;
        let dx = piece
            .x
            .checked_sub(full.x)
            .and_then(|off| usize::try_from(off).ok())
            .and_then(|off| off.checked_mul(bpp))
            .ok_or_else(|| fail("stream piece offset overflows".to_owned()))?;
        let dy = piece
            .y
            .checked_sub(full.y)
            .and_then(|off| usize::try_from(off).ok())
            .ok_or_else(|| fail("stream piece offset overflows".to_owned()))?;
        let rows = usize::try_from(piece.height)
            .ok()
            .ok_or_else(|| fail("stream piece height overflows".to_owned()))?;
        for row in 0..rows {
            let src_start = row
                .checked_mul(piece_stride)
                .ok_or_else(|| fail("stream piece rows overflow".to_owned()))?;
            let src_end = src_start
                .checked_add(piece_stride)
                .ok_or_else(|| fail("stream piece rows overflow".to_owned()))?;
            let seg = src
                .get(src_start..src_end)
                .ok_or_else(|| fail("stream piece bytes disagree".to_owned()))?;
            let dst_row = dy
                .checked_add(row)
                .and_then(|r| r.checked_mul(full_stride))
                .and_then(|base| base.checked_add(dx))
                .ok_or_else(|| fail("stream output rows overflow".to_owned()))?;
            let dst_end = dst_row
                .checked_add(piece_stride)
                .ok_or_else(|| fail("stream output rows overflow".to_owned()))?;
            let slot = dst
                .get_mut(dst_row..dst_end)
                .ok_or_else(|| fail("stream piece leaves its output".to_owned()))?;
            slot.copy_from_slice(seg);
        }
        Ok(())
    }

    /// Finishes assembly, returning the joined output.
    ///
    /// # Errors
    ///
    /// [`RenderError::Spill`] when the received bytes do not add up to the
    /// output (a piece never arrived, or arrived twice).
    pub fn finish(self) -> Result<StreamedOutput, RenderError> {
        if self.received != self.total {
            return Err(RenderError::Spill {
                detail: format!(
                    "streaming output incomplete: got {} of {} bytes",
                    self.received, self.total
                ),
            });
        }
        match self.store {
            SinkStore::Memory(frame) => Ok(StreamedOutput::Memory(frame)),
            SinkStore::Mapped(mapped) => Ok(StreamedOutput::Mapped(mapped)),
        }
    }
}

/// One assembled streaming output: an in-RAM frame or a memory-mapped file.
#[derive(Debug)]
pub enum StreamedOutput {
    /// Assembled in RAM.
    Memory(Frame),
    /// Assembled in a temp file; dropping deletes it.
    Mapped(MappedFrame),
}

impl StreamedOutput {
    /// The output extent.
    #[must_use]
    pub const fn extent(&self) -> FrameExtent {
        match self {
            StreamedOutput::Memory(frame) => frame.extent(),
            StreamedOutput::Mapped(mapped) => mapped.extent(),
        }
    }
    /// The output bytes, row-major 32-bit floats.
    #[must_use]
    pub fn as_bytes(&self) -> &[u8] {
        match self {
            StreamedOutput::Memory(frame) => bytemuck::cast_slice(frame.as_slice()),
            StreamedOutput::Mapped(mapped) => mapped.as_bytes(),
        }
    }
}

/// A streaming output assembled in a memory-mapped temp file. Dropping
/// deletes the file; the mapping never links a visible path (the temp file
/// is anonymous from creation), so no residue can survive any exit.
#[derive(Debug)]
pub struct MappedFrame {
    /// The output extent.
    extent: FrameExtent,
    /// The mapped output bytes.
    map: MmapMut,
    /// The temp file behind the mapping.
    #[expect(dead_code)]
    // held, never read: it keeps the mapping valid and deletes the file on drop
    file: File,
}

impl MappedFrame {
    /// The output extent.
    #[must_use]
    pub const fn extent(&self) -> FrameExtent {
        self.extent
    }

    /// The output bytes, row-major 32-bit floats.
    #[must_use]
    pub fn as_bytes(&self) -> &[u8] {
        &self.map
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use std::sync::Arc;

    use lightamer_raster::{FrameExtent, PixelFormat};
    use lightamer_sysmem::Budget;

    use super::{StreamSink, StreamedOutput};
    use crate::budgeted::alloc_shared;
    use crate::stream::StreamPiece;

    /// One piece filled with `fill` in every lane.
    fn piece(
        budget: &Arc<Budget>,
        x: i32,
        y: i32,
        width: u32,
        height: u32,
        fill: f32,
    ) -> StreamPiece {
        let extent = FrameExtent::new(x, y, width, height);
        let mut plane = alloc_shared(budget, extent, PixelFormat::RgbaF32Premul).unwrap();
        plane.frame.as_mut_slice().fill(fill);
        StreamPiece { extent, plane }
    }

    fn budget() -> Arc<Budget> {
        Arc::new(Budget::new(1024 * 1024 * 1024))
    }

    #[test]
    fn ram_sink_assembles_strips_in_any_order() {
        let budget = budget();
        let full = FrameExtent::new(0, 0, 64, 48);
        let mut sink = StreamSink::new(full, u64::MAX, u64::MAX, None).unwrap();
        assert!(!sink.spilled());
        // Arrival order must not matter.
        sink.push(&piece(&budget, 0, 32, 64, 16, 2.0)).unwrap();
        sink.push(&piece(&budget, 0, 0, 64, 32, 1.0)).unwrap();
        let out = sink.finish().unwrap();
        assert!(matches!(out, StreamedOutput::Memory(_)));
        let bytes: &[u8] = out.as_bytes();
        assert_eq!(bytes.len(), 64 * 48 * 16);
        let floats: &[f32] = bytemuck::cast_slice(bytes);
        assert!(
            floats[0..64 * 32 * 4]
                .iter()
                .all(|value| value.to_bits() == 1.0f32.to_bits())
        );
        assert!(
            floats[64 * 32 * 4..]
                .iter()
                .all(|value| value.to_bits() == 2.0f32.to_bits())
        );
    }

    #[test]
    fn disk_sink_assembles_blocks_and_leaves_no_residue() {
        let budget = budget();
        let full = FrameExtent::new(0, 0, 64, 48);
        let dir = tempfile::tempdir().unwrap();
        let mut sink = StreamSink::new(full, 0, u64::MAX, Some(dir.path())).unwrap();
        assert!(sink.spilled());
        sink.push(&piece(&budget, 0, 0, 32, 24, 1.0)).unwrap();
        sink.push(&piece(&budget, 32, 0, 32, 24, 2.0)).unwrap();
        sink.push(&piece(&budget, 0, 24, 32, 24, 3.0)).unwrap();
        sink.push(&piece(&budget, 32, 24, 32, 24, 4.0)).unwrap();
        let out = sink.finish().unwrap();
        assert!(matches!(out, StreamedOutput::Mapped(_)));
        let floats: &[f32] = bytemuck::cast_slice(out.as_bytes());
        // Quadrant fills land at their rows: top rows read 1|2, bottom 3|4.
        for y in 0..48 {
            for x in 0..64 {
                let want = if y < 24 {
                    if x < 32 { 1.0 } else { 2.0 }
                } else if x < 32 {
                    3.0
                } else {
                    4.0
                };
                assert_eq!(floats[(y * 64 + x) * 4], want, "pixel ({x},{y})");
            }
        }
        drop(out);
        let left: Vec<_> = std::fs::read_dir(dir.path()).unwrap().collect();
        assert!(left.is_empty());
    }

    #[test]
    fn sink_over_the_byte_limit_refuses_upfront() {
        let full = FrameExtent::new(0, 0, 64, 48);
        let err = StreamSink::new(full, u64::MAX, 1024, None).unwrap_err();
        assert!(matches!(err, crate::render::RenderError::Spill { .. }));
        assert!(err.to_string().contains("limit"));
    }

    #[test]
    fn unfinished_sink_finishes_incomplete() {
        let budget = budget();
        let full = FrameExtent::new(0, 0, 64, 48);
        let dir = tempfile::tempdir().unwrap();
        let mut sink = StreamSink::new(full, 0, u64::MAX, Some(dir.path())).unwrap();
        sink.push(&piece(&budget, 0, 0, 64, 32, 1.0)).unwrap();
        let err = sink.finish().unwrap_err();
        assert!(matches!(err, crate::render::RenderError::Spill { .. }));
        assert!(err.to_string().contains("incomplete"));
        let left: Vec<_> = std::fs::read_dir(dir.path()).unwrap().collect();
        assert!(left.is_empty());
    }

    #[test]
    fn piece_outside_the_frame_is_a_typed_error() {
        let budget = budget();
        let full = FrameExtent::new(0, 0, 64, 48);
        let mut sink = StreamSink::new(full, u64::MAX, u64::MAX, None).unwrap();
        let err = sink
            .push(&piece(&budget, 1000, 1000, 8, 8, 1.0))
            .unwrap_err();
        assert!(matches!(err, crate::render::RenderError::Spill { .. }));
    }

    #[test]
    #[expect(clippy::cast_precision_loss)] // test frames are small; the conversion is exact
    fn stream_into_spill_matches_the_whole_frame() {
        use lightamer_geom::Roi as GeomRoi;
        use lightamer_iop_traits::{ColorSpace, ImageInfo};
        use lightamer_raster::Frame;
        use serde_json::json;

        use crate::chain::PipeNode;
        use crate::fakes::{FakeCopy, FakeGain, Probe, no_params, table};
        use crate::kinds::PipeKind;
        use crate::render::{Pipe, RenderRequest};

        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::new(Probe::new()))),
            Arc::new(FakeGain::new("mod_g0", Arc::new(Probe::new()))),
            Arc::new(FakeGain::new("mod_g1", Arc::new(Probe::new()))),
        ]);
        let gain = |id: &str, value: f64| {
            let mut params = no_params();
            params.insert("gain".to_owned(), json!({"type": "float", "value": value}));
            PipeNode {
                id: id.to_owned(),
                multi: 0,
                params,
            }
        };
        let nodes = vec![
            PipeNode {
                id: "mod_a".to_owned(),
                multi: 0,
                params: no_params(),
            },
            gain("mod_g0", 2.0),
            gain("mod_g1", 0.5),
        ];
        let len = 200usize * 150 * 4;
        let buf: Vec<f32> = (0..len).map(|i| i as f32 * 0.125 - 3.0).collect();
        let input = Frame::from_parts(
            buf,
            FrameExtent::new(0, 0, 200, 150),
            PixelFormat::RgbaF32Premul,
        )
        .unwrap();
        let final_out = GeomRoi::new(0, 0, 200, 150, 1.0).unwrap();
        let no_cancel = || false;
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &ImageInfo::new(200, 150, ColorSpace::Rgb),
            input: &input,
            input_id: 7,
            process: 1,
            final_out,
            cancel: &no_cancel,
        };
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 64 * 1024 * 1024, 1024 * 1024);
        let whole = pipe.render(&req).unwrap();
        // Forced to disk (zero threshold) inside a scratch dir the test owns.
        let dir = tempfile::tempdir().unwrap();
        let full = FrameExtent::new(0, 0, 200, 150);
        let mut sink = StreamSink::new(full, 0, 8 * 1024 * 1024 * 1024, Some(dir.path())).unwrap();
        assert!(sink.spilled());
        pipe.render_stream(&req, |piece| sink.push(&piece)).unwrap();
        let out = sink.finish().unwrap();
        let want: &[u8] = bytemuck::cast_slice(whole.frame().as_slice());
        assert_eq!(out.as_bytes(), want);
        drop(out);
        let left: Vec<_> = std::fs::read_dir(dir.path()).unwrap().collect();
        assert!(left.is_empty());
    }

    #[test]
    #[expect(clippy::cast_precision_loss)] // test frames are small; the conversion is exact
    fn cancelled_run_leaves_no_spill_residue() {
        use std::sync::atomic::{AtomicUsize, Ordering};

        use lightamer_geom::Roi as GeomRoi;
        use lightamer_iop_traits::{ColorSpace, ImageInfo};
        use lightamer_raster::Frame;
        use serde_json::json;

        use crate::chain::PipeNode;
        use crate::fakes::{FakeCopy, FakeGain, Probe, no_params, table};
        use crate::kinds::PipeKind;
        use crate::render::{Pipe, RenderError, RenderRequest};

        let lookup = table(vec![
            Arc::new(FakeCopy::new("mod_a", Arc::new(Probe::new()))),
            Arc::new(FakeGain::new("mod_g", Arc::new(Probe::new()))),
        ]);
        let mut gain = no_params();
        gain.insert("gain".to_owned(), json!({"type": "float", "value": 2.0}));
        let nodes = vec![
            PipeNode {
                id: "mod_a".to_owned(),
                multi: 0,
                params: no_params(),
            },
            PipeNode {
                id: "mod_g".to_owned(),
                multi: 0,
                params: gain,
            },
        ];
        let len = 200usize * 150 * 4;
        let buf: Vec<f32> = (0..len).map(|i| i as f32 * 0.125 - 3.0).collect();
        let input = Frame::from_parts(
            buf,
            FrameExtent::new(0, 0, 200, 150),
            PixelFormat::RgbaF32Premul,
        )
        .unwrap();
        // Entry check plus one piece runs; the second piece never starts, so
        // the spill sink stays unfinished and must delete itself on drop.
        let calls = AtomicUsize::new(0);
        let cancel = || calls.fetch_add(1, Ordering::SeqCst) >= 2;
        let req = RenderRequest {
            nodes: &nodes,
            lookup: &lookup,
            image: &ImageInfo::new(200, 150, ColorSpace::Rgb),
            input: &input,
            input_id: 7,
            process: 1,
            final_out: GeomRoi::new(0, 0, 200, 150, 1.0).unwrap(),
            cancel: &cancel,
        };
        let mut pipe = Pipe::with_budget_and_floor(PipeKind::Full, 64 * 1024 * 1024, 1024 * 1024);
        let dir = tempfile::tempdir().unwrap();
        let full = FrameExtent::new(0, 0, 200, 150);
        let mut sink = StreamSink::new(full, 0, 8 * 1024 * 1024 * 1024, Some(dir.path())).unwrap();
        assert!(sink.spilled());
        let err = pipe
            .render_stream(&req, |piece| sink.push(&piece))
            .unwrap_err();
        assert!(matches!(err, RenderError::Cancelled));
        assert_eq!(pipe.budget().used(), 0);
        assert_eq!(pipe.cache_len(), 0);
        drop(sink);
        let left: Vec<_> = std::fs::read_dir(dir.path()).unwrap().collect();
        assert!(left.is_empty());
    }
    /// One mono piece filled with `fill`.
    fn mono_piece(
        budget: &Arc<Budget>,
        x: i32,
        y: i32,
        width: u32,
        height: u32,
        fill: f32,
    ) -> StreamPiece {
        let extent = FrameExtent::new(x, y, width, height);
        let mut plane = alloc_shared(budget, extent, PixelFormat::MonoF32).unwrap();
        plane.frame.as_mut_slice().fill(fill);
        StreamPiece { extent, plane }
    }

    #[test]
    fn mono_sink_sizes_by_four_bytes_per_pixel() {
        let budget = budget();
        let full = FrameExtent::new(0, 0, 64, 48);
        let mut sink =
            StreamSink::new_with_format(full, PixelFormat::MonoF32, u64::MAX, u64::MAX, None)
                .unwrap();
        assert!(!sink.spilled());
        sink.push(&mono_piece(&budget, 0, 32, 64, 16, 2.0)).unwrap();
        sink.push(&mono_piece(&budget, 0, 0, 64, 32, 1.0)).unwrap();
        let out = sink.finish().unwrap();
        assert!(matches!(out, StreamedOutput::Memory(_)));
        let bytes: &[u8] = out.as_bytes();
        assert_eq!(bytes.len(), 64 * 48 * 4);
        let floats: &[f32] = bytemuck::cast_slice(bytes);
        assert!(
            floats[0..64 * 32]
                .iter()
                .all(|value| value.to_bits() == 1.0f32.to_bits())
        );
        assert!(
            floats[64 * 32..]
                .iter()
                .all(|value| value.to_bits() == 2.0f32.to_bits())
        );
    }

    #[test]
    fn mono_disk_sink_assembles_partial_width_pieces() {
        let budget = budget();
        let full = FrameExtent::new(0, 0, 64, 48);
        let dir = tempfile::tempdir().unwrap();
        let mut sink =
            StreamSink::new_with_format(full, PixelFormat::MonoF32, 0, u64::MAX, Some(dir.path()))
                .unwrap();
        assert!(sink.spilled());
        // Half-width pieces land row by row, not as one run.
        sink.push(&mono_piece(&budget, 0, 0, 32, 48, 1.0)).unwrap();
        sink.push(&mono_piece(&budget, 32, 0, 32, 48, 2.0)).unwrap();
        let out = sink.finish().unwrap();
        assert!(matches!(out, StreamedOutput::Mapped(_)));
        let bytes: &[u8] = out.as_bytes();
        assert_eq!(bytes.len(), 64 * 48 * 4);
        let floats: &[f32] = bytemuck::cast_slice(bytes);
        for y in 0..48 {
            for x in 0..64 {
                let want = if x < 32 { 1.0 } else { 2.0 };
                assert_eq!(floats[y * 64 + x], want, "pixel ({x},{y})");
            }
        }
        drop(out);
        let left: Vec<_> = std::fs::read_dir(dir.path()).unwrap().collect();
        assert!(left.is_empty());
    }

    #[test]
    fn piece_of_other_format_is_refused() {
        let budget = budget();
        let full = FrameExtent::new(0, 0, 64, 48);
        let mut mono =
            StreamSink::new_with_format(full, PixelFormat::MonoF32, u64::MAX, u64::MAX, None)
                .unwrap();
        let err = mono.push(&piece(&budget, 0, 0, 64, 48, 1.0)).unwrap_err();
        assert!(matches!(err, crate::render::RenderError::Spill { .. }));
        let mut rgba = StreamSink::new(full, u64::MAX, u64::MAX, None).unwrap();
        let err = rgba
            .push(&mono_piece(&budget, 0, 0, 64, 48, 1.0))
            .unwrap_err();
        assert!(matches!(err, crate::render::RenderError::Spill { .. }));
    }
}
