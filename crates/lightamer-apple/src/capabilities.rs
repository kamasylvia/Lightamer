// SPDX-License-Identifier: GPL-3.0-or-later
//! Capability table types, the single backend-selection point, and the
//! once-per-process [`capabilities()`] cache.
//!
//! The table holds platform facts only ("what this machine provides"), never
//! feature flags ("what we implemented"). Each field is honestly probed; a
//! probe that cannot observe something reports it absent.

use std::sync::OnceLock;

/// Which backend produced a [`Capabilities`] table.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Backend {
    /// No Apple frameworks: every probe reports absent.
    Empty,
    /// macOS probes against the real frameworks.
    MacOs,
}

/// Image formats `ImageIO` may be able to write.
///
/// Membership in [`Capabilities::writable_image_formats`] means the format's
/// UTI appeared in `CGImageDestinationCopyTypeIdentifiers` on this machine.
/// Nothing is assumed: the empty backend reports none.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ImageFormat {
    /// `public.jpeg`.
    Jpeg,
    /// `public.png`.
    Png,
    /// `public.tiff`.
    Tiff,
    /// `public.heic`.
    Heic,
    /// `public.avif`.
    Avif,
    /// `org.webp`.
    WebP,
}

/// Presence of the Vision request classes the app may use.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
#[expect(clippy::struct_excessive_bools)] // Five independent probe facts; a bitflag would hide names.
pub struct VisionRequests {
    /// `VNDetectFaceRectanglesRequest`.
    pub face_rectangles: bool,
    /// `VNDetectFaceLandmarksRequest`.
    pub face_landmarks: bool,
    /// `VNDetectRectanglesRequest`.
    pub rectangles: bool,
    /// `VNDetectHorizonRequest`.
    pub horizon: bool,
    /// `VNGeneratePersonSegmentationRequest`.
    pub person_segmentation: bool,
}

/// Standard color spaces constructible on this machine.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub struct StandardSpaces {
    /// `CGColorSpaceCreateWithName(kCGColorSpaceSRGB)` succeeded.
    pub srgb: bool,
    /// `CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3)` succeeded.
    pub display_p3: bool,
}

/// Platform facts probed from Apple frameworks (or honestly absent).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Capabilities {
    /// Which backend produced this table.
    pub backend: Backend,
    /// Default Metal device name, when a device exists.
    pub metal_device_name: Option<String>,
    /// `ImageIO` writable formats among the six [`ImageFormat`]s.
    pub writable_image_formats: Vec<ImageFormat>,
    /// `CIRAWFilter` class presence.
    pub ci_raw_filter: bool,
    /// Vision request class presence.
    pub vision_requests: VisionRequests,
    /// Standard color space construction.
    pub standard_spaces: StandardSpaces,
}

/// Crate-internal probe behind [`capabilities()`].
///
/// Never public: framework types must not leak, and every backend reports
/// through the same plain-data [`Capabilities`]. The same trait also carries
/// viewport attachment so the backend-selection point below stays the only
/// one in the crate.
pub(crate) trait BackendProbe {
    /// Runs the lightweight probes (no decode, no sample, no window).
    fn probe(&self) -> Capabilities;
    /// Attaches a viewport to a caller-owned native surface handle.
    ///
    /// A `None` sink means framework-driven input; `Some` installs the
    /// backend's native input path.
    fn attach_viewport(
        &self,
        native_handle: usize,
        rect: &super::viewport::ViewportRect,
        sink: Option<super::viewport::ViewportInputSink>,
    ) -> Result<Box<dyn super::viewport::ViewportBackend>, super::viewport::ViewportError>;
}

// The single backend-selection point of the whole crate: two complete `cfg`
// branches, no scattered `cfg` statements anywhere else.
#[cfg(target_os = "macos")]
pub(crate) fn selected_backend() -> &'static dyn BackendProbe {
    &super::macos::MacOsBackend
}

#[cfg(not(target_os = "macos"))]
pub(crate) fn selected_backend() -> &'static dyn BackendProbe {
    &super::empty::EmptyBackend
}

static CACHE: OnceLock<Capabilities> = OnceLock::new();

/// The capability table, probed once per process.
///
/// The first call runs the backend probes; later calls return the same table.
#[must_use]
pub fn capabilities() -> &'static Capabilities {
    CACHE.get_or_init(|| selected_backend().probe())
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

    use super::*;

    #[test]
    fn empty_backend_reports_nothing() {
        let caps = super::super::empty::EmptyBackend.probe();
        assert_eq!(caps.backend, Backend::Empty);
        assert_eq!(caps.metal_device_name, None);
        assert_eq!(caps.writable_image_formats, Vec::new());
        assert!(!caps.ci_raw_filter);
        assert_eq!(caps.vision_requests, VisionRequests::default());
        assert!(!caps.vision_requests.face_rectangles);
        assert!(!caps.vision_requests.face_landmarks);
        assert!(!caps.vision_requests.rectangles);
        assert!(!caps.vision_requests.horizon);
        assert!(!caps.vision_requests.person_segmentation);
        assert_eq!(caps.standard_spaces, StandardSpaces::default());
        assert!(!caps.standard_spaces.srgb);
        assert!(!caps.standard_spaces.display_p3);
    }

    #[test]
    fn empty_backend_is_selected_somewhere() {
        // The empty backend is not compile-only: this executes its probe on
        // every platform (including macOS) and checks the discriminant.
        let caps = super::super::empty::EmptyBackend.probe();
        assert!(matches!(caps.backend, Backend::Empty));
        // `selected_backend` resolves on this host too (which arm depends on
        // the target); both arms must produce a well-formed table.
        let selected = selected_backend().probe();
        assert!(matches!(selected.backend, Backend::Empty | Backend::MacOs));
    }

    #[test]
    fn capability_table_has_every_field() {
        // Exhaustive destructuring: adding a field breaks this test until the
        // test names it, so every field stays covered.
        let Capabilities {
            backend,
            metal_device_name,
            writable_image_formats,
            ci_raw_filter,
            vision_requests:
                VisionRequests {
                    face_rectangles,
                    face_landmarks,
                    rectangles,
                    horizon,
                    person_segmentation,
                },
            standard_spaces: StandardSpaces { srgb, display_p3 },
        } = capabilities();
        assert!(matches!(backend, Backend::Empty | Backend::MacOs));
        // Touch every binding so none is dead: any platform fact is a bool or
        // an honest `Option`/`Vec`, never a placeholder.
        let _ = (
            metal_device_name,
            writable_image_formats,
            ci_raw_filter,
            face_rectangles,
            face_landmarks,
            rectangles,
            horizon,
            person_segmentation,
            srgb,
            display_p3,
        );
    }

    #[test]
    fn capabilities_returns_same_table() {
        assert!(std::ptr::eq(capabilities(), capabilities()));
    }
}
