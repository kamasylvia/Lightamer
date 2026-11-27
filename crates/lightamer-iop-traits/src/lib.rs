// SPDX-License-Identifier: GPL-3.0-or-later
//! Module descriptors, the module trait, and the shared vocabulary they use.
//!
//! A [`ModuleDesc`] is pure data owned by the module itself: the darktable
//! operation name, the two order keys, and — once later waves fill them in —
//! the parameter layout, flags, colorspace requirements, panel controls, and
//! history keys. The core only reads descriptors; it never names a module.
//!
//! [`IopModule`] is the object-safe trait every module implements so the
//! pipeline can hold mixed modules in one table (`Vec<Arc<dyn IopModule>>`).
//! Its signatures only use types from this crate: L0 crates take no
//! workspace dependencies, so the roi wire shape ([`Roi`]), the commit input
//! ([`ImageInfo`]), the tiling request ([`TilingReq`]), and the pixel views
//! ([`Plane`]/[`PlaneMut`]) all live here next to the trait. The op-rich
//! geometry type (`lightamer_geom::Roi`) and the owned buffers
//! (`lightamer_raster::Frame`) stay in their own L0 crates; the pipeline
//! converts at the boundary.
//!
//! Fields that later waves have not filled yet are [`None`]. A fresh stub
//! built with [`ModuleDesc::stub`] sets only `id` and `order`.
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

mod error;
mod image;
mod module;
mod parallel;
mod params;
mod plane;
mod roi;
mod tiling;

pub use error::PipeError;
pub use image::ImageInfo;
pub use module::{CommitData, IopModule, SharedModule};
pub use parallel::par_map_rows;
pub use params::{get_bool, get_float, get_floats, get_int, get_text};
pub use plane::{Plane, PlaneMut};
pub use roi::Roi;
pub use tiling::TilingReq;

/// Sort key placing a module in one default chain.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct OrderKey {
    /// darktable priority (the `order` value of the order-table entry).
    pub priority: f32,
    /// Row index of the module inside the darktable order table (0-based).
    ///
    /// Several modules share one priority (for example the seven modules at
    /// `28.5`); their relative order is the table row order, not the
    /// alphabetical order. The tie value is the module's own data.
    pub tie: u16,
}

/// Raw and non-raw default-chain keys of one module.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct OrderKeys {
    /// Key in the raw default chain (`v50_order`).
    pub raw: OrderKey,
    /// Key in the non-raw default chain (`v50_jpg_order`).
    pub jpg: OrderKey,
}

/// Primary darktable module tab a module belongs to.
///
/// Maps the first of `BASIC`/`TONE`/`COLOR`/`CORRECT`/`EFFECT` found in the
/// module's `default_group()`; `EFFECTS`-only modules map to
/// [`ModuleGroup::Effect`]. `TECHNICAL`/`GRADING` are search facets, not tabs,
/// and are folded away when this field is filled.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ModuleGroup {
    /// `IOP_GROUP_BASIC`.
    Base,
    /// `IOP_GROUP_TONE`.
    Tone,
    /// `IOP_GROUP_COLOR`.
    Color,
    /// `IOP_GROUP_CORRECT`.
    Correction,
    /// `IOP_GROUP_EFFECT` (also covers `IOP_GROUP_EFFECTS`-only modules).
    Effect,
}

/// One setting of our own settings model: a name plus a type.
///
/// This describes the settings we store in the session database
/// (`PLAN-AMENDMENTS.md` A-12/A-15); it is deliberately not the darktable C
/// parameter layout — no byte sizes, no field offsets, no migration
/// functions, no darktable module version.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ParamField {
    /// Setting name, e.g. `"exposure"`.
    pub name: &'static str,
    /// Setting type.
    pub ty: ParamType,
}

/// Setting value types of our own settings model.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ParamType {
    /// Floating-point number.
    Float,
    /// Integer number.
    Int,
    /// On/off switch.
    Bool,
    /// One of a fixed option list; the payload lands with the settings model.
    Enum,
    /// Editable curve; the point payload lands with the settings model.
    Curve,
}

/// Parameter description of one module: our own settings, not C layout.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ParamsDesc {
    /// Settings of this module; [`None`] means "not filled yet".
    pub fields: Option<&'static [ParamField]>,
}

impl ParamsDesc {
    /// All fields unset.
    #[must_use]
    pub const fn unset() -> Self {
        Self { fields: None }
    }
}

/// Capability flags of one module. Layout is ours, not darktable's.
///
/// Bit sources, fixed when this field is filled: `TILING` from
/// `IOP_FLAGS_ALLOW_TILING`, `BLEND` from `IOP_FLAGS_SUPPORTS_BLENDING`,
/// `HIDDEN` from `IOP_FLAGS_HIDDEN`, `DEPRECATED` from
/// `IOP_FLAGS_DEPRECATED`, and `DISTORT` from `operation_tags()` masked with
/// `DISTORT`/`CROPPING`/`GEOMETRY`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ModuleFlags(u32);

impl ModuleFlags {
    /// No flags set.
    pub const NONE: Self = Self(0);
    /// Tile-wise processing is allowed.
    pub const TILING: Self = Self(1 << 0);
    /// Blending modes are supported.
    pub const BLEND: Self = Self(1 << 1);
    /// Geometry is distorted (sourced from operation tags, not `flags()`).
    pub const DISTORT: Self = Self(1 << 2);
    /// Hidden from the user interface.
    pub const HIDDEN: Self = Self(1 << 3);
    /// Deprecated upstream; kept for history compatibility.
    pub const DEPRECATED: Self = Self(1 << 4);

    /// Empty set, same as [`ModuleFlags::NONE`].
    #[must_use]
    pub const fn empty() -> Self {
        Self(0)
    }

    /// Raw bits.
    #[must_use]
    pub const fn bits(self) -> u32 {
        self.0
    }

    /// Whether all of `other` is contained in `self`.
    #[must_use]
    pub const fn contains(self, other: Self) -> bool {
        self.0 & other.0 == other.0
    }

    /// Union of two flag sets.
    #[must_use]
    pub const fn union(self, other: Self) -> Self {
        Self(self.0 | other.0)
    }
}

/// darktable pipeline colorspace (`dt_iop_colorspace_type_t`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ColorSpace {
    /// `IOP_CS_NONE` (-1).
    None,
    /// `IOP_CS_RAW` (0).
    Raw,
    /// `IOP_CS_LAB` (1).
    Lab,
    /// `IOP_CS_RGB` (2).
    Rgb,
    /// `IOP_CS_LCH` (3).
    Lch,
    /// `IOP_CS_HSL` (4).
    Hsl,
    /// `IOP_CS_JZCZHZ` (5).
    Jzczhz,
}

/// Colorspace contract of one module.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ColorRequirement {
    /// `default_colorspace()`; used unless an override below says otherwise.
    pub default_space: ColorSpace,
    /// `input_colorspace()` override.
    pub input: ColorSpace,
    /// `output_colorspace()` override.
    pub output: ColorSpace,
}

/// One panel control, used to generate the module UI.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Control {
    /// Draggable number row (darktable bauhaus slider).
    Slider {
        /// Parameter key this control edits.
        key: &'static str,
        /// Minimum value.
        min: f32,
        /// Maximum value.
        max: f32,
        /// Default value.
        default: f32,
        /// Single-step increment.
        step: f32,
        /// Print format, e.g. `"%.2f"`.
        fmt: &'static str,
    },
    /// Drop-down list.
    Combo {
        /// Parameter key this control edits.
        key: &'static str,
        /// Option labels in order.
        options: &'static [&'static str],
        /// Default option index.
        default: usize,
    },
    /// On/off switch.
    Toggle {
        /// Parameter key this control edits.
        key: &'static str,
        /// Default state.
        default: bool,
    },
    /// Editable curve. The point payload is fixed when the UI lands.
    Curve {
        /// Parameter key this control edits.
        key: &'static str,
    },
    /// Color wheel. The channel payload is fixed when the UI lands.
    ColorWheel {
        /// Parameter key this control edits.
        key: &'static str,
    },
    /// Collapsible section header grouping the controls after it.
    Section {
        /// `i18n` key of the section title.
        title_key: &'static str,
    },
}

/// History-stack identity of one module.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct HistoryKeys {
    /// Legacy operation names mapping to this module; empty when there are none.
    pub aliases: &'static [&'static str],
    /// Whether several instances may sit on the stack at once.
    pub multi_instance: bool,
    /// Whether the module is document-level (history-only entries).
    pub doc_level: bool,
}

/// Self-description of one module. Pure data; lives with the module.
///
/// `id` and `order` are always set. Every other field starts as [`None`] and
/// is filled by later waves; [`None`] unambiguously means "not set yet".
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ModuleDesc {
    /// Unique id: the darktable operation name.
    pub id: &'static str,
    /// `i18n` key of the display name.
    pub display_key: Option<&'static str>,
    /// Primary module tab.
    pub group: Option<ModuleGroup>,
    /// Raw and non-raw default-chain keys.
    pub order: OrderKeys,
    /// Parameter block layout.
    pub params: ParamsDesc,
    /// Capability flags.
    pub flags: Option<ModuleFlags>,
    /// Colorspace contract.
    pub colorspaces: Option<ColorRequirement>,
    /// Panel controls for UI generation.
    pub panel: Option<&'static [Control]>,
    /// History-stack keys.
    pub history: Option<HistoryKeys>,
}

impl ModuleDesc {
    /// Stub with only `id` and `order` set; everything else is [`None`].
    #[must_use]
    pub const fn stub(id: &'static str, raw: OrderKey, jpg: OrderKey) -> Self {
        Self {
            id,
            display_key: None,
            group: None,
            order: OrderKeys { raw, jpg },
            params: ParamsDesc::unset(),
            flags: None,
            colorspaces: None,
            panel: None,
            history: None,
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::{ModuleDesc, OrderKey};

    #[test]
    fn package_metadata_resolves() {
        assert_ne!(env!("CARGO_PKG_NAME"), "");
        assert_ne!(env!("CARGO_PKG_VERSION"), "");
    }

    #[test]
    fn stub_sets_only_id_and_order() {
        let desc = ModuleDesc::stub(
            "example",
            OrderKey {
                priority: 1.0,
                tie: 0,
            },
            OrderKey {
                priority: 2.0,
                tie: 3,
            },
        );
        assert_eq!(desc.id, "example");
        assert_eq!(desc.order.raw.priority.to_bits(), 1.0f32.to_bits());
        assert_eq!(desc.order.jpg.tie, 3);
        assert!(desc.display_key.is_none());
        assert!(desc.group.is_none());
        assert!(desc.params.fields.is_none());
        assert!(desc.flags.is_none());
        assert!(desc.colorspaces.is_none());
        assert!(desc.panel.is_none());
        assert!(desc.history.is_none());
        assert!(format!("{desc:?}").contains("example"));
    }
}
