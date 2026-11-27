// SPDX-License-Identifier: GPL-3.0-or-later
//! Typed decode errors: one code plus one human sentence per failure.
//!
//! [`ErrorCode`] mirrors the C `RS_ERR_*` values one-to-one (see
//! `csrc/rawspeed_shim.h`); [`DecodeError`] pairs a code with the detail
//! line the C layer captured (usually rawspeed's own message).

use std::fmt;

/// Stable decode failure code. Discriminants equal the C `RS_ERR_*` values.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(i32)]
pub enum ErrorCode {
    /// File missing or unreadable.
    NotFound = 1,
    /// No RAW decoder accepts this file.
    NotRaw = 2,
    /// The camera is unknown to the camera database.
    UnknownCamera = 3,
    /// Empty, cut short, or read out of bounds.
    Truncated = 4,
    /// The decoder or decompressor failed on readable input.
    DecompressFailed = 5,
    /// Out of memory.
    OutOfMemory = 6,
    /// The file's compression is not supported.
    UnsupportedCompression = 7,
    /// No embedded thumbnail in this file.
    ThumbnailUnavailable = 8,
    /// Null handle, misuse, camera-database failure, or unknown cause.
    Internal = 9,
    /// Content (or variant) this decoder does not handle: non-JPEG/PNG/TIFF
    /// bytes in the raster path, camera-RAW TIFFs, CMYK JPEGs, sub-8-bit or
    /// palette rasters. Rust-layer only; the C ABI never emits it.
    UnsupportedFormat = 10,
}

impl ErrorCode {
    /// The C-side numeric code.
    #[must_use]
    pub const fn as_i32(self) -> i32 {
        self as i32
    }

    /// Map a C code back; unknown values become [`ErrorCode::Internal`].
    #[must_use]
    pub const fn from_i32(code: i32) -> Self {
        match code {
            1 => Self::NotFound,
            2 => Self::NotRaw,
            3 => Self::UnknownCamera,
            4 => Self::Truncated,
            5 => Self::DecompressFailed,
            6 => Self::OutOfMemory,
            7 => Self::UnsupportedCompression,
            8 => Self::ThumbnailUnavailable,
            10 => Self::UnsupportedFormat,
            _ => Self::Internal,
        }
    }

    /// The one human sentence for this code.
    #[must_use]
    pub const fn message(self) -> &'static str {
        match self {
            Self::NotFound => "file missing or unreadable",
            Self::NotRaw => "not a supported RAW file",
            Self::UnknownCamera => "camera unknown to the camera database",
            Self::Truncated => "file is truncated or empty",
            Self::DecompressFailed => "RAW decompression failed",
            Self::OutOfMemory => "out of memory",
            Self::UnsupportedCompression => "compression not supported",
            Self::ThumbnailUnavailable => "embedded thumbnail not available",
            Self::Internal => "internal decode error",
            Self::UnsupportedFormat => "unsupported file format",
        }
    }
}

/// A decode failure: a typed code plus a detail line.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DecodeError {
    /// The failure code.
    code: ErrorCode,
    /// Detail line (usually rawspeed's own message); may be empty.
    detail: String,
}

impl DecodeError {
    /// Build an error from a code and a detail line.
    #[must_use]
    pub fn new(code: ErrorCode, detail: impl Into<String>) -> Self {
        Self {
            code,
            detail: detail.into(),
        }
    }

    /// The failure code.
    #[must_use]
    pub fn code(&self) -> ErrorCode {
        self.code
    }

    /// The detail line (may be empty).
    #[must_use]
    pub fn detail(&self) -> &str {
        &self.detail
    }

    /// The human sentence for the code (without detail).
    #[must_use]
    pub fn message(&self) -> &'static str {
        self.code.message()
    }
}

impl fmt::Display for DecodeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.detail.is_empty() {
            write!(f, "{}", self.code.message())
        } else {
            write!(f, "{}: {}", self.code.message(), self.detail)
        }
    }
}

impl std::error::Error for DecodeError {}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::*;

    #[test]
    fn codes_round_trip() {
        for code in 1..=10 {
            assert_eq!(ErrorCode::from_i32(code).as_i32(), code);
        }
    }

    #[test]
    fn unknown_codes_become_internal() {
        for code in [0, -1, 99, i32::MIN, i32::MAX] {
            assert_eq!(ErrorCode::from_i32(code), ErrorCode::Internal);
        }
    }

    #[test]
    fn display_without_detail_is_just_the_sentence() {
        let err = DecodeError::new(ErrorCode::Truncated, "");
        assert_eq!(err.to_string(), "file is truncated or empty");
    }

    #[test]
    fn display_with_detail_appends_it() {
        let err = DecodeError::new(ErrorCode::NotRaw, "No decoder found. Sorry.");
        assert_eq!(
            err.to_string(),
            "not a supported RAW file: No decoder found. Sorry."
        );
    }
}
