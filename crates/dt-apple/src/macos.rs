// SPDX-License-Identifier: GPL-3.0-or-later
//! The macOS backend: lightweight probes against Apple frameworks.
//!
//! This is the only module in the workspace allowed to name Apple bindings.
//! Probes observe (class lookup, one device object, a format list, two color
//! spaces); they decode nothing, read no sample, open no window. Minimal
//! calls follow `SPIKE-RUST-APPLE-src/src/s1`–`s4` (see
//! `docs/APPLE-BOUNDARY.md` for the file map).
#![allow(unsafe_code)]
#![deny(unsafe_op_in_unsafe_fn)]
#![deny(clippy::undocumented_unsafe_blocks)]

use super::capabilities::{
    Backend, BackendProbe, Capabilities, ImageFormat, StandardSpaces, VisionRequests,
};
use objc2::rc::autoreleasepool;
use objc2::runtime::AnyClass;
use objc2_core_foundation::{CFArray, CFRetained, CFString};
use objc2_core_graphics::{CGColorSpace, kCGColorSpaceDisplayP3, kCGColorSpaceSRGB};
use objc2_image_io::CGImageDestination;
use objc2_metal::{MTLCreateSystemDefaultDevice, MTLDevice};
use std::ffi::CStr;

/// [`BackendProbe`] against the real macOS frameworks.
pub(crate) struct MacOsBackend;

/// UTI per writable format we care about. Only these six are recognized.
const FORMAT_UTIS: [(ImageFormat, &str); 6] = [
    (ImageFormat::Jpeg, "public.jpeg"),
    (ImageFormat::Png, "public.png"),
    (ImageFormat::Tiff, "public.tiff"),
    (ImageFormat::Heic, "public.heic"),
    (ImageFormat::Avif, "public.avif"),
    (ImageFormat::WebP, "org.webp"),
];

impl BackendProbe for MacOsBackend {
    fn probe(&self) -> Capabilities {
        autoreleasepool(|_| Self::probe_inner())
    }
}

impl MacOsBackend {
    fn probe_inner() -> Capabilities {
        Self::linkage_pins();
        let metal_device_name =
            MTLCreateSystemDefaultDevice().map(|device| device.name().to_string());
        // SAFETY: `extern` framework constants, immutable and always present
        // on macOS; reading them has no preconditions.
        let (srgb, display_p3) = unsafe {
            (
                CGColorSpace::with_name(Some(kCGColorSpaceSRGB)).is_some(),
                CGColorSpace::with_name(Some(kCGColorSpaceDisplayP3)).is_some(),
            )
        };
        Capabilities {
            backend: Backend::MacOs,
            metal_device_name,
            writable_image_formats: Self::writable_formats(),
            ci_raw_filter: Self::class_present(c"CIRAWFilter"),
            vision_requests: VisionRequests {
                face_rectangles: Self::class_present(c"VNDetectFaceRectanglesRequest"),
                face_landmarks: Self::class_present(c"VNDetectFaceLandmarksRequest"),
                rectangles: Self::class_present(c"VNDetectRectanglesRequest"),
                horizon: Self::class_present(c"VNDetectHorizonRequest"),
                person_segmentation: Self::class_present(c"VNGeneratePersonSegmentationRequest"),
            },
            standard_spaces: StandardSpaces { srgb, display_p3 },
        }
    }

    /// Reference one symbol per framework probed only by class lookup.
    ///
    /// `CoreImage` and `Vision` have no other call site in this backend; without a
    /// referenced symbol the linker could drop the framework and the lookups
    /// below would wrongly report absent. Taking addresses is panic-free and
    /// fault-free; `black_box` keeps the loads from being optimized out.
    fn linkage_pins() {
        use objc2_core_image::kCIInputImageKey;
        use objc2_vision::VNImageOptionProperties;
        let pins = (
            std::ptr::addr_of!(kCIInputImageKey),
            std::ptr::addr_of!(VNImageOptionProperties),
        );
        std::hint::black_box(pins);
    }

    fn class_present(name: &CStr) -> bool {
        AnyClass::get(name).is_some()
    }

    fn writable_formats() -> Vec<ImageFormat> {
        // SAFETY: FFI with no preconditions; Apple guarantees a retained array.
        let ids = unsafe { CGImageDestination::type_identifiers() };
        // SAFETY: Apple documents the elements as UTI strings (`CFString`).
        let ids: CFRetained<CFArray<CFString>> = unsafe { CFRetained::cast_unchecked(ids) };
        let mut listed = Vec::new();
        for index in 0..ids.len() {
            if let Some(uti) = ids.get(index) {
                listed.push(uti.to_string());
            }
        }
        FORMAT_UTIS
            .iter()
            .filter(|(_, uti)| listed.iter().any(|have| have == uti))
            .map(|(format, _)| *format)
            .collect()
    }
}
