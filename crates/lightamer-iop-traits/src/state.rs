// SPDX-License-Identifier: GPL-3.0-or-later
//! Chain state: the facts modules pass along the pipe.
//!
//! Mirrors `dt_iop_buffer_dsc_t` (`src/develop/format.h:35-64` in
//! `refs/dt-master`), minus what this pipe does not need: `cst` lives in our
//! colorspace declarations ([`ColorRequirement`](super::ColorRequirement)),
//! and the `rawprepare` sub-record is only read by exposure-class modules
//! outside the RAW head. The CFA pattern rides one enum ([`CfaPattern`]):
//! upstream's `filters` + `xtrans[6][6]` pair merges into a single value, so
//! an X-Trans table without an X-Trans pattern is unrepresentable.
//!
//! The pipe owns one value per render: it starts from
//! [`PipeState::from_image`], threads through every `commit` in chain order,
//! then evolves node by node through `process` (each node sees what the
//! previous node's processing left, like `pipe->dsc` at
//! `src/develop/pixelpipe_hb.c:2816`). Tiled nodes reset
//! [`PipeState::processed_maximum`] per tile from the node's entry value
//! (`src/develop/tiling.c:757-758`); every other field carries across tiles.
//! Cached planes store the post-node value beside them and restore it on a
//! hit, like upstream's per-cacheline `dsc`
//! (`src/develop/pixelpipe_cache.c:350-351`).
//!
//! Modules read and write this through `&mut` (never owned, never shared):
//! `channels`/`datatype` describe the current input buffer and only the pipe
//! writes them (from its format threading, like `output_format` feeding
//! `pipe->dsc` at `pixelpipe_hb.c:2006`); every other field is a module's to
//! read or write.

use super::{CfaPattern, ImageInfo, PixelFormat};

/// Scalar type of the buffer flowing through the pipe: what `commit` and
/// `process` compare when they branch on it (rawprepare's `TYPE_UINT16` vs
/// `TYPE_FLOAT` legs).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BufferDataType {
    /// 32-bit float lanes: everything this pipe allocates.
    Float,
    /// 16-bit integer lanes: unrepresentable in this pipe (decode feeds
    /// `f32`), kept so transcribed branches can name the upstream leg.
    Uint16,
}

/// White-balance facts the temperature module publishes and the highlights
/// module reads (`dsc.temperature`, `format.h:52-56`).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TemperatureState {
    /// Whether a temperature module published these values.
    pub enabled: bool,
    /// Per-channel multipliers, R/G/B/G2.
    pub coeffs: [f32; 4],
}

/// Facts modules pass along the chain: plain data, stack-resident,
/// [`Copy`]. No allocation behind any field.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PipeState {
    /// CFA layout of the current buffer (Bayer cells already crop-adjusted
    /// by rawprepare's processing, like `pipe->dsc.filters`).
    pub cfa: CfaPattern,
    /// Channels of the current input buffer (1 mono, 4 RGBA). Written by
    /// the pipe from its format threading, read by modules.
    pub channels: u32,
    /// Scalar type of the current input buffer. Written by the pipe, read
    /// by modules; always [`BufferDataType::Float`] on this pipe.
    pub datatype: BufferDataType,
    /// Per-channel sensor saturation propagated through the modules
    /// (`dsc.processed_maximum`).
    pub processed_maximum: [f32; 4],
    /// White-balance facts (`dsc.temperature`).
    pub temperature: TemperatureState,
}

impl PipeState {
    /// Starting value for an image: CFA from its RAW facts (none without
    /// them), channels from its buffer format, float lanes, unit maxima,
    /// unpublished white balance.
    ///
    /// Unit maxima match upstream's non-RAW init
    /// (`pixelpipe_hb.c:332-335`); RAW captures inherit their load-time value
    /// there, but rawprepare's processing unconditionally resets to 1.0
    /// (`src/iop/rawprepare.c:447`), so nothing downstream can tell.
    #[must_use]
    pub fn from_image(image: &ImageInfo) -> Self {
        Self {
            cfa: image.raw.map_or(CfaPattern::None, |raw| raw.cfa),
            channels: image.format.channel_count(),
            datatype: BufferDataType::Float,
            processed_maximum: [1.0; 4],
            temperature: TemperatureState {
                enabled: false,
                coeffs: [1.0; 4],
            },
        }
    }

    /// Points the input-buffer descriptor at `format`: the pipe calls this
    /// before every node's processing, so modules always read the descriptor
    /// of the buffer they are actually given.
    pub fn set_input(&mut self, format: PixelFormat) {
        self.channels = format.channel_count();
        self.datatype = BufferDataType::Float;
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::super::{CfaColor, ColorSpace, RawFacts};
    use super::{BufferDataType, CfaPattern, ImageInfo, PipeState, PixelFormat};

    fn raw_info(cfa: CfaPattern) -> ImageInfo {
        ImageInfo::new(64, 64, ColorSpace::Raw)
            .with_format(PixelFormat::MonoF32)
            .with_raw(RawFacts {
                black: [0; 4],
                white: 1,
                wb: [1.0; 4],
                xyz_to_cam_d65: None,
                cam_to_xyz_d65: None,
                cfa,
                crop_x: 0,
                crop_y: 0,
                p_width: 64,
                p_height: 64,
                linear_response_limit: 1.0,
                hdr: false,
                four_bayer: false,
                s_raw: false,
                monochrome: false,
                monochrome_bayer: false,
                load_ok: true,
                camera_missing_sample: false,
            })
    }

    #[test]
    fn starts_from_image_facts() {
        let bayer = CfaPattern::Bayer([
            CfaColor::Red,
            CfaColor::Green,
            CfaColor::Green,
            CfaColor::Blue,
        ]);
        let state = PipeState::from_image(&raw_info(bayer));
        assert_eq!(state.cfa, bayer);
        assert_eq!(state.channels, 1);
        assert_eq!(state.datatype, BufferDataType::Float);
        assert_eq!(state.processed_maximum, [1.0; 4]);
        assert!(!state.temperature.enabled);
        assert_eq!(state.temperature.coeffs, [1.0; 4]);
    }

    #[test]
    fn starts_patternless_without_raw_facts() {
        let state = PipeState::from_image(&ImageInfo::new(8, 8, ColorSpace::Rgb));
        assert_eq!(state.cfa, CfaPattern::None);
        assert_eq!(state.channels, 4);
    }

    #[test]
    fn input_descriptor_follows_the_format() {
        let mut state = PipeState::from_image(&ImageInfo::new(8, 8, ColorSpace::Rgb));
        state.set_input(PixelFormat::MonoF32);
        assert_eq!(state.channels, 1);
        assert_eq!(state.datatype, BufferDataType::Float);
    }

    #[test]
    fn stays_stack_sized() {
        assert!(size_of::<PipeState>() <= 96);
    }
}
