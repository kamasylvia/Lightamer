// SPDX-License-Identifier: GPL-3.0-or-later
//! Plane comparison for transcription tests: mean/max absolute difference
//! plus the in-tolerance share, with the gate constants beside them.

/// Tolerance band for the share gate: one 16-bit step.
pub const TOLERANCE: f32 = 1.0 / 65535.0;

/// Gate on the mean absolute difference (plan golden gate).
pub const MEAN_ABS_GATE: f32 = 1.0 / 65535.0;

/// Gate on the share of pixels within [`TOLERANCE`] (plan golden gate).
pub const IN_TOLERANCE_GATE: f64 = 0.9999;

/// Comparison of two planes: mean and max absolute difference plus the
/// share of pixels within [`TOLERANCE`].
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Comparison {
    /// Mean absolute difference.
    pub mean_abs: f64,
    /// Max absolute difference.
    pub max_abs: f32,
    /// Share of pixels with `|a - b| <= TOLERANCE`.
    pub in_tolerance: f64,
}

/// Compares `actual` against `expected` element-wise over the common
/// prefix. Length mismatch counts the overhang as infinitely different
/// (fails every gate); empty pairs pass vacuously with a share of one.
#[must_use]
#[expect(clippy::cast_precision_loss)]
// Lane counts below 2^53 convert exactly; test tiles are kilobytes.
pub fn compare_planes(actual: &[f32], expected: &[f32]) -> Comparison {
    let count = actual.len().max(expected.len());
    if count == 0 {
        return Comparison {
            mean_abs: 0.0,
            max_abs: 0.0,
            in_tolerance: 1.0,
        };
    }
    let mut total = 0.0;
    let mut max_abs: f32 = 0.0;
    let mut inside = 0u64;
    for index in 0..count {
        let pair = (actual.get(index), expected.get(index));
        let diff = match pair {
            (Some(a), Some(e)) => (a - e).abs(),
            (None, None) => continue, // unreachable: index < max length
            (Some(_), None) | (None, Some(_)) => f32::INFINITY,
        };
        total += f64::from(diff);
        max_abs = max_abs.max(diff);
        if diff <= TOLERANCE {
            inside += 1;
        }
    }
    Comparison {
        mean_abs: total / count as f64,
        max_abs,
        in_tolerance: inside as f64 / count as f64,
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{IN_TOLERANCE_GATE, MEAN_ABS_GATE, compare_planes};

    #[test]
    fn identical_planes_compare_zero_and_full_share() {
        let plane = [0.0, 0.5, 1.0, 2.5];
        let diff = compare_planes(&plane, &plane);
        assert_eq!(diff.mean_abs, 0.0);
        assert_eq!(diff.max_abs, 0.0);
        assert_eq!(diff.in_tolerance, 1.0);
        assert!(diff.mean_abs < f64::from(MEAN_ABS_GATE));
        assert!(diff.in_tolerance > IN_TOLERANCE_GATE);
    }

    #[test]
    fn single_outlier_shows_in_max_and_share() {
        let actual = [0.0, 0.0, 0.0, 1.0];
        let expected = [0.0, 0.0, 0.0, 0.0];
        let diff = compare_planes(&actual, &expected);
        assert_eq!(diff.mean_abs, 0.25);
        assert_eq!(diff.max_abs, 1.0);
        assert_eq!(diff.in_tolerance, 0.75);
    }

    #[test]
    fn length_mismatch_fails_every_gate() {
        let diff = compare_planes(&[0.0, 0.0], &[0.0]);
        assert!(diff.mean_abs.is_infinite());
        assert!(diff.max_abs.is_infinite());
        assert!(diff.in_tolerance < 1.0);
    }

    #[test]
    fn empty_planes_pass_vacuously() {
        let diff = compare_planes(&[], &[]);
        assert_eq!(diff.mean_abs, 0.0);
        assert_eq!(diff.in_tolerance, 1.0);
    }
}
