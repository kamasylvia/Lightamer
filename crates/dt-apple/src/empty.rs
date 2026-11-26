// SPDX-License-Identifier: GPL-3.0-or-later
//! The empty backend: honestly reports that nothing is provided.
//!
//! Compiled on every platform (macOS included) so its correctness is checked
//! by the host test run. Standard library only.

use super::capabilities::{Backend, BackendProbe, Capabilities};

/// [`BackendProbe`] that provides nothing.
#[allow(dead_code)] // On macOS only tests construct it; other targets select it.
pub(crate) struct EmptyBackend;

impl BackendProbe for EmptyBackend {
    fn probe(&self) -> Capabilities {
        Capabilities {
            backend: Backend::Empty,
            metal_device_name: None,
            writable_image_formats: Vec::new(),
            ci_raw_filter: false,
            vision_requests: super::capabilities::VisionRequests::default(),
            standard_spaces: super::capabilities::StandardSpaces::default(),
        }
    }
}
