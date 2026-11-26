// SPDX-License-Identifier: GPL-3.0-or-later
//! One-way XMP fixtures for the oracle: strongly-typed params → darktable bytes.
//!
//! Layouts mirror the oracle binary (darktable 5.6.2, params `repr(C)` LE);
//! field tables live in `fixtures/oracle/README.md`. Future modules add one
//! [`DtParamsEncoder`] each; the document writer stays untouched.

use std::fmt::Write as _;

/// Encoder from strongly-typed module params to darktable's param blob.
///
/// Implementors write exactly the bytes the oracle binary `memcpy`s for
/// `(operation, modversion)`; see `fixtures/oracle/README.md`.
pub trait DtParamsEncoder {
    /// darktable operation name, e.g. `exposure`.
    fn operation(&self) -> &'static str;
    /// Module version the oracle binary expects.
    fn modversion(&self) -> u32;
    /// Little-endian param bytes, exactly `params_size` long.
    fn encode_le(&self) -> Vec<u8>;
}

/// Blend version/params every fixture entry carries (verbatim from the proven spike XMP).
pub const BLENDOP_VERSION: u32 = 10;
/// Compressed default blend blob; accepted as-is by the 5.6.2 oracle.
pub const BLENDOP_PARAMS: &str = "gz14eJxjYIAACQYYOOHEgAYY0QVwggZ7CB6pfNoAAEkgGQQ=";

/// Fixed `DateTimeOriginal` all fixtures carry (byte-stable output).
pub const FIXTURE_DATETIME: &str = "2026:11:25 00:00:00";

/// Strongly-typed `exposure` params (`dt_iop_exposure_params_t`, v7, 28 bytes).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ExposureParams {
    /// 0 = manual, 1 = deflicker.
    pub mode: i32,
    /// Black level correction.
    pub black: f32,
    /// Exposure correction in EV.
    pub exposure: f32,
    /// Deflicker percentile.
    pub percentile: f32,
    /// Deflicker target level.
    pub target_level: f32,
    /// Compensate exposure bias.
    pub compensate_bias: bool,
    /// Compensate highlight preservation.
    pub compensate_highlight: bool,
}

impl ExposureParams {
    /// Manual mode, +1 EV, spike-proven companion values.
    #[must_use]
    pub fn manual_plus_1ev() -> Self {
        Self {
            mode: 0,
            black: 0.0,
            exposure: 1.0,
            percentile: 50.0,
            target_level: -4.0,
            compensate_bias: false,
            compensate_highlight: true,
        }
    }
}

impl DtParamsEncoder for ExposureParams {
    fn operation(&self) -> &'static str {
        "exposure"
    }

    fn modversion(&self) -> u32 {
        7
    }

    fn encode_le(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(28);
        out.extend_from_slice(&self.mode.to_le_bytes());
        out.extend_from_slice(&self.black.to_le_bytes());
        out.extend_from_slice(&self.exposure.to_le_bytes());
        out.extend_from_slice(&self.percentile.to_le_bytes());
        out.extend_from_slice(&self.target_level.to_le_bytes());
        out.extend_from_slice(&i32::from(self.compensate_bias).to_le_bytes());
        out.extend_from_slice(&i32::from(self.compensate_highlight).to_le_bytes());
        out
    }
}

/// Strongly-typed `flip` params (`dt_iop_flip_params_t`, v2, 4 bytes).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FlipParams {
    /// `dt_image_orientation_t` bits; 2 = flip horizontally.
    pub orientation: u32,
}

impl FlipParams {
    /// Horizontal flip (`ORIENTATION_FLIP_X`).
    #[must_use]
    pub fn horizontal() -> Self {
        Self { orientation: 2 }
    }
}

impl DtParamsEncoder for FlipParams {
    fn operation(&self) -> &'static str {
        "flip"
    }

    fn modversion(&self) -> u32 {
        2
    }

    fn encode_le(&self) -> Vec<u8> {
        self.orientation.to_le_bytes().to_vec()
    }
}

/// One lowercase hex digit for a 4-bit nibble.
fn hex_nibble(nibble: u8) -> char {
    (match nibble {
        0..=9 => b'0' + nibble,
        _ => b'a' + (nibble - 10),
    }) as char
}

/// Lowercase hex of bytes (darktable's default XMP encoding).
#[must_use]
pub fn hex_lower(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for &byte in bytes {
        out.push(hex_nibble(byte >> 4));
        out.push(hex_nibble(byte & 0xf));
    }
    out
}

fn escape_attr(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

/// Emit a minimal darktable sidecar: changed modules only, auto-presets off,
/// no XML comments (a leading comment makes darktable reject the whole file).
#[must_use]
pub fn emit_xmp(derived_from: &str, entries: &[&dyn DtParamsEncoder]) -> String {
    let mut doc = String::with_capacity(2048);
    doc.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    doc.push_str("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\" x:xmptk=\"XMP Core 4.4.0-Exiv2\">\n");
    doc.push_str(" <rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\n");
    doc.push_str("  <rdf:Description rdf:about=\"\"\n");
    doc.push_str("    xmlns:exif=\"http://ns.adobe.com/exif/1.0/\"\n");
    doc.push_str("    xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\"\n");
    doc.push_str("    xmlns:xmpMM=\"http://ns.adobe.com/xap/1.0/mm/\"\n");
    doc.push_str("    xmlns:darktable=\"http://darktable.sf.net/\"\n");
    let _ = writeln!(doc, "   exif:DateTimeOriginal=\"{FIXTURE_DATETIME}\"");
    doc.push_str("   xmp:Rating=\"0\"\n");
    let _ = writeln!(
        doc,
        "   xmpMM:DerivedFrom=\"{}\"",
        escape_attr(derived_from)
    );
    doc.push_str("   darktable:xmp_version=\"4\"\n");
    doc.push_str("   darktable:raw_params=\"0\"\n");
    doc.push_str("   darktable:auto_presets_applied=\"0\"\n");
    let _ = writeln!(doc, "   darktable:history_end=\"{}\">", entries.len());
    doc.push_str("   <darktable:masks_history>\n");
    doc.push_str("    <rdf:Seq/>\n");
    doc.push_str("   </darktable:masks_history>\n");
    doc.push_str("   <darktable:history>\n");
    doc.push_str("    <rdf:Seq>\n");
    for (num, entry) in entries.iter().enumerate() {
        let params = hex_lower(&entry.encode_le());
        doc.push_str("     <rdf:li\n");
        let _ = writeln!(doc, "      darktable:num=\"{num}\"");
        let _ = writeln!(doc, "      darktable:operation=\"{}\"", entry.operation());
        doc.push_str("      darktable:enabled=\"1\"\n");
        let _ = writeln!(doc, "      darktable:modversion=\"{}\"", entry.modversion());
        let _ = writeln!(doc, "      darktable:params=\"{params}\"");
        doc.push_str("      darktable:multi_name=\"\"\n");
        doc.push_str("      darktable:multi_priority=\"0\"\n");
        let _ = writeln!(doc, "      darktable:blendop_version=\"{BLENDOP_VERSION}\"");
        let _ = writeln!(doc, "      darktable:blendop_params=\"{BLENDOP_PARAMS}\"/>");
    }
    doc.push_str("    </rdf:Seq>\n");
    doc.push_str("   </darktable:history>\n");
    doc.push_str("  </rdf:Description>\n");
    doc.push_str(" </rdf:RDF>\n");
    doc.push_str("</x:xmpmeta>\n");
    doc
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::*;

    /// Canonical file name the golden fixtures use.
    const GOLDEN_NAME: &str = "7RM5-LosslessCompressedLarge.ARW";

    fn fixture(name: &str) -> String {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../fixtures/oracle")
            .join(name);
        let text = std::fs::read_to_string(&path);
        assert!(text.is_ok(), "missing {name}");
        text.unwrap_or_default()
    }

    #[test]
    fn exposure_encodes_spike_hex() {
        let bytes = ExposureParams::manual_plus_1ev().encode_le();
        assert_eq!(bytes.len(), 28);
        assert_eq!(
            hex_lower(&bytes),
            "00000000000000000000803f00004842000080c00000000001000000"
        );
    }

    #[test]
    fn flip_encodes_orientation_bits() {
        assert_eq!(FlipParams::horizontal().encode_le(), vec![2, 0, 0, 0]);
    }

    #[test]
    fn g1_matches_golden_byte_for_byte() {
        let exposure = ExposureParams::manual_plus_1ev();
        let doc = emit_xmp(GOLDEN_NAME, &[&exposure]);
        assert_eq!(doc, fixture("expected-g1-exposure.xmp"));
    }

    #[test]
    fn g2_matches_golden_byte_for_byte() {
        let exposure = ExposureParams::manual_plus_1ev();
        let flip = FlipParams::horizontal();
        let doc = emit_xmp(GOLDEN_NAME, &[&exposure, &flip]);
        assert_eq!(doc, fixture("expected-g2-exposure-flip.xmp"));
    }

    #[test]
    fn output_has_no_xml_comments() {
        let exposure = ExposureParams::manual_plus_1ev();
        let flip = FlipParams::horizontal();
        for doc in [
            emit_xmp(GOLDEN_NAME, &[&exposure]),
            emit_xmp(GOLDEN_NAME, &[&exposure, &flip]),
            emit_xmp(GOLDEN_NAME, &[]),
        ] {
            assert!(!doc.contains("<!--"), "XML comment leaked into XMP");
        }
    }

    #[test]
    fn interface_accepts_future_encoders() {
        struct Dummy;
        impl DtParamsEncoder for Dummy {
            fn operation(&self) -> &'static str {
                "dummy"
            }
            fn modversion(&self) -> u32 {
                1
            }
            fn encode_le(&self) -> Vec<u8> {
                vec![1, 2, 3, 4]
            }
        }
        let dummy = Dummy;
        let doc = emit_xmp("a.RAW", &[&dummy]);
        assert!(doc.contains("darktable:operation=\"dummy\""));
        assert!(doc.contains("darktable:params=\"01020304\""));
        assert!(doc.contains("darktable:history_end=\"1\""));
    }
}
