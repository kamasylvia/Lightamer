// SPDX-License-Identifier: GPL-3.0-or-later
//! Typed pipeline errors.

use std::fmt;

/// What can go wrong inside one module call.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PipeError {
    /// A parameter is missing, mistyped, or out of domain.
    InvalidParams(String),
    /// Regions do not line up (bad roi, shape mismatch).
    RoiMismatch(String),
    /// The pixel format is not supported here.
    UnsupportedFormat(String),
    /// Anything else the backend reports.
    Backend(String),
}

impl fmt::Display for PipeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            PipeError::InvalidParams(detail) => write!(f, "invalid parameters: {detail}"),
            PipeError::RoiMismatch(detail) => write!(f, "roi mismatch: {detail}"),
            PipeError::UnsupportedFormat(detail) => write!(f, "unsupported format: {detail}"),
            PipeError::Backend(detail) => write!(f, "backend error: {detail}"),
        }
    }
}

impl std::error::Error for PipeError {}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::PipeError;

    #[test]
    fn each_kind_reads_human() {
        assert_eq!(
            format!(
                "{}",
                PipeError::InvalidParams("missing 'exposure'".to_owned())
            ),
            "invalid parameters: missing 'exposure'"
        );
        assert_eq!(
            format!(
                "{}",
                PipeError::RoiMismatch("input 4x4, output 8x8".to_owned())
            ),
            "roi mismatch: input 4x4, output 8x8"
        );
        assert_eq!(
            format!(
                "{}",
                PipeError::UnsupportedFormat("RGBA8 display buffer".to_owned())
            ),
            "unsupported format: RGBA8 display buffer"
        );
        assert_eq!(
            format!("{}", PipeError::Backend("OpenCL queue busy".to_owned())),
            "backend error: OpenCL queue busy"
        );
        let boxed: Box<dyn std::error::Error> = Box::new(PipeError::Backend("x".to_owned()));
        assert!(boxed.to_string().contains("backend error"));
    }
}
