// SPDX-License-Identifier: GPL-3.0-or-later
//! Own history model: photo settings plus a snapshot undo stack.
//!
//! A photo's look is [`PhotoSettings`] (see [`settings`]): plain data with a
//! [`ProcessVersion`], tolerant to read (unknown fields ignored, missing
//! fields defaulted, unknown modules and parameters kept) and canonical to
//! write (same settings, same bytes). [`HistoryStack`] (see [`history`])
//! layers undo steps, drag-merge interactions, copy, and batch apply on top.
//! Cache keys are [`PhotoSettings::hash64`], FNV-1a over the canonical JSON.
//!
//! The editing model follows `LightCraft` (`docs/process-versions.md` there);
//! per-file `Derived from` headers name what was taken. This crate names no
//! module: it only stores module ids supplied by others.
//!
//! ```rust
//! use std::sync::Arc;
//! use dt_history::{HistoryStack, ModuleInstance, PhotoSettings};
//!
//! let mut settings = PhotoSettings::default();
//! settings.instances.upsert(ModuleInstance {
//!     module: "mod_a".to_owned(),
//!     multi: 0,
//!     name: None,
//!     enabled: true,
//!     params: [("p_bool".to_owned(), dt_history::SettingValue::Bool(true))]
//!         .into_iter()
//!         .collect(),
//! });
//! let text = settings.canonical_json().expect("serializable");
//! assert_eq!(PhotoSettings::from_json(&text).expect("parse"), settings);
//! let mut stack = HistoryStack::new(Arc::new(settings));
//! assert!(!stack.undo());
//! ```
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

pub mod history;
pub mod settings;

pub use history::{BatchAdjustments, HISTORY_LIMIT, HistoryStack, HistoryStep, apply_batch};
pub use settings::{
    FORMAT_VERSION, InstanceList, ModuleInstance, PhotoSettings, ProcessVersion, SettingValue,
    SettingsError,
};
