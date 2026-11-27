// SPDX-License-Identifier: GPL-3.0-or-later
//! Row-parallel helper for module authors.
//!
//! [`par_map_rows`] runs one closure per row over a `src`/`dst` row pair in
//! parallel (rayon): each row is `row_len` floats starting at `row * stride`
//! in its buffer. Writes are disjoint by construction, so the parallel result
//! is bitwise identical to a serial row loop whatever the thread count is.
//!
//! Tiles stay serial in B1-b: the pipeline calls [`par_map_rows`] only inside
//! one module's `process`, never across tiles.

use super::PipeError;

/// Runs `f(src_row, dst_row)` for each of `rows` rows in parallel.
///
/// Row `r` reads `row_len` floats at `src[r * src_stride..]` and writes
/// `row_len` floats at `dst[r * dst_stride..]`. Strides may exceed `row_len`
/// (sub-buffer rows); every row pair is disjoint, so lanes never alias and the
/// outcome equals a serial loop bitwise.
///
/// A `rows` of zero is a successful no-op (buffers are still checked for the
/// stride contract below, but no row is touched).
///
/// # Errors
///
/// [`PipeError::RoiMismatch`] when `row_len` exceeds either stride or either
/// buffer is shorter than the rows it must hold. Bounds are checked before a
/// single lane spawns; no lane can panic on addressing afterwards.
pub fn par_map_rows<F>(
    src: &[f32],
    dst: &mut [f32],
    rows: usize,
    src_stride: usize,
    dst_stride: usize,
    row_len: usize,
    f: F,
) -> Result<(), PipeError>
where
    F: Fn(&[f32], &mut [f32]) + Sync + Send,
{
    if row_len > src_stride || row_len > dst_stride {
        return Err(PipeError::RoiMismatch(format!(
            "parallel rows need row_len {row_len} within strides {src_stride}/{dst_stride}"
        )));
    }
    if rows == 0 {
        return Ok(());
    }
    // Checked `usize` math: anything unrepresentable cannot fit in memory
    // either, so it reports as a short buffer, never a wrap or a trap.
    let need = |stride: usize| -> Option<usize> {
        (rows - 1)
            .checked_mul(stride)
            .and_then(|prefix| prefix.checked_add(row_len))
    };
    match need(src_stride) {
        Some(need) if need <= src.len() => {}
        _ => {
            return Err(PipeError::RoiMismatch(format!(
                "parallel rows need {rows} rows of stride {src_stride}, source holds {} floats",
                src.len()
            )));
        }
    }
    match need(dst_stride) {
        Some(need) if need <= dst.len() => {}
        _ => {
            return Err(PipeError::RoiMismatch(format!(
                "parallel rows need {rows} rows of stride {dst_stride}, destination holds {} floats",
                dst.len()
            )));
        }
    }

    let lanes = rayon::current_num_threads().max(1);
    let chunk_rows = rows.div_ceil(lanes.saturating_mul(4));
    rayon::scope(|scope| {
        let work = &f;
        let mut src_rest = src;
        let mut dst_rest = dst;
        let mut first_row = 0;
        while first_row < rows {
            let last_row = (first_row + chunk_rows).min(rows);
            // Elements the chunk spans, gaps between its rows included; the
            // pre-checks above guarantee both splits succeed. The next chunk
            // starts a full stride past this one's last row, so the trailing
            // gap (`stride - row_len`) is skipped after the split.
            let src_take = (last_row - 1) * src_stride + row_len - first_row * src_stride;
            let dst_take = (last_row - 1) * dst_stride + row_len - first_row * dst_stride;
            let (Some((src_chunk, src_next)), Some((dst_chunk, dst_next))) = (
                src_rest.split_at_checked(src_take),
                dst_rest.split_at_mut_checked(dst_take),
            ) else {
                // Unreachable by construction (lengths pre-checked); stopping
                // the loop beats touching memory the contract did not grant.
                return;
            };
            src_rest = src_next.get(src_stride - row_len..).unwrap_or(&[]);
            dst_rest = dst_next.get_mut(dst_stride - row_len..).unwrap_or(&mut []);
            let first = first_row;
            let last = last_row;
            scope.spawn(move |_| {
                for row in first..last {
                    let src_off = (row - first) * src_stride;
                    let dst_off = (row - first) * dst_stride;
                    let (Some(s), Some(d)) = (
                        src_chunk.get(src_off..src_off + row_len),
                        dst_chunk.get_mut(dst_off..dst_off + row_len),
                    ) else {
                        // Unreachable by construction; skip rather than trap.
                        continue;
                    };
                    work(s, d);
                }
            });
            first_row = last_row;
        }
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::par_map_rows;

    fn serial_copy(src: &[f32], dst: &mut [f32], rows: usize, stride: usize, row_len: usize) {
        for row in 0..rows {
            let pair = (
                src.get(row * stride..row * stride + row_len),
                dst.get_mut(row * stride..row * stride + row_len),
            );
            assert!(
                pair.0.is_some() && pair.1.is_some(),
                "test rows exceed the buffers"
            );
            let (Some(s), Some(d)) = pair else {
                return;
            };
            d.copy_from_slice(s);
        }
    }

    #[test]
    #[allow(clippy::cast_precision_loss)]
    fn parallel_copy_matches_serial_bitwise() {
        let rows = 137usize;
        let width = 61usize;
        let stride = width * 4;
        let row_len = stride;
        let src: Vec<f32> = (0..rows * stride).map(|i| i as f32 * 0.25 - 7.0).collect();
        let mut want = vec![0.0f32; rows * stride];
        serial_copy(&src, &mut want, rows, stride, row_len);
        let mut got = vec![f32::NAN; rows * stride];
        par_map_rows(&src, &mut got, rows, stride, stride, row_len, |s, d| {
            d.copy_from_slice(s);
        })
        .unwrap();
        assert_eq!(got, want);
        assert_eq!(got, src);
    }

    #[test]
    #[allow(clippy::cast_precision_loss)]
    fn strided_rows_only_touch_row_len() {
        // Gaps between rows must survive: the tool writes row_len floats per
        // row and never the padding a sub-buffer stride leaves behind.
        let rows = 9usize;
        let row_len = 8usize;
        let stride = 12usize;
        let src: Vec<f32> = (0..rows * stride).map(|i| i as f32).collect();
        let mut got = vec![-1.0f32; rows * stride];
        par_map_rows(&src, &mut got, rows, stride, stride, row_len, |s, d| {
            d.copy_from_slice(s);
        })
        .unwrap();
        for row in 0..rows {
            assert_eq!(
                &got[row * stride..row * stride + row_len],
                &src[row * stride..row * stride + row_len]
            );
            assert!(
                got[row * stride + row_len..(row + 1) * stride]
                    .iter()
                    .all(|v| v.to_bits() == (-1.0f32).to_bits())
            );
        }
    }

    #[test]
    fn single_row_and_empty_rows_run() {
        let src = vec![1.0f32, 2.0, 3.0, 4.0];
        let mut dst = vec![0.0f32; 4];
        par_map_rows(&src, &mut dst, 1, 4, 4, 4, |s, d| {
            d.copy_from_slice(s);
        })
        .unwrap();
        assert_eq!(dst, src);
        let mut empty: Vec<f32> = Vec::new();
        let ran = std::sync::atomic::AtomicBool::new(false);
        par_map_rows(&[], &mut empty, 0, 4, 4, 4, |_, _| {
            ran.store(true, std::sync::atomic::Ordering::Relaxed);
        })
        .unwrap();
        assert!(!ran.load(std::sync::atomic::Ordering::Relaxed));
    }

    #[test]
    fn short_buffers_and_wide_rows_are_typed_errors() {
        let src = vec![0.0f32; 16];
        let mut dst = vec![0.0f32; 16];
        // row_len past either stride.
        assert!(par_map_rows(&src, &mut dst, 2, 8, 8, 9, |_, _| {}).is_err());
        // Two rows of stride 8 need 16 floats; one short on each side.
        let short = vec![0.0f32; 15];
        assert!(par_map_rows(&short, &mut dst, 2, 8, 8, 8, |_, _| {}).is_err());
        let mut short_dst = vec![0.0f32; 15];
        assert!(par_map_rows(&src, &mut short_dst, 2, 8, 8, 8, |_, _| {}).is_err());
        let err = par_map_rows(&short, &mut dst, 2, 8, 8, 8, |_, _| {}).unwrap_err();
        assert!(err.to_string().contains("source holds"));
    }
}
