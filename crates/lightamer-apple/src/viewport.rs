// SPDX-License-Identifier: GPL-3.0-or-later
//! Native viewport seam: attach a caller-owned surface handle, draw, detach.
//!
//! The seam is one integer. The UI framework owns a native surface whose
//! platform handle on macOS is a pointer-sized integer; this crate turns that
//! integer plus an initial rectangle into a [`ViewportHandle`]. Handles and
//! pointer events are only valid inside this process and address space.
//!
//! The public surface carries no framework types: rectangles, geometry, input
//! events, and errors are plain data defined here. The macOS backend (inside
//! `macos.rs`) owns the Metal objects; the empty backend reports
//! [`ViewportError::Unsupported`] for every operation while keeping the same
//! interface, so all platforms compile and the empty path is unit-testable.

use std::fmt;

/// Logical-point rectangle handed to the viewport (origin top-left).
#[derive(Debug, Clone, Copy)]
pub struct ViewportRect {
    /// Left edge in logical points.
    pub x: f64,
    /// Top edge in logical points.
    pub y: f64,
    /// Width in logical points.
    pub width: f64,
    /// Height in logical points.
    pub height: f64,
}

/// Geometry observed from the live native surface.
#[derive(Debug, Clone)]
pub struct ViewportGeom {
    /// Native view frame origin x in points.
    pub view_x: f64,
    /// Native view frame origin y in points.
    pub view_y: f64,
    /// Native view frame width in points.
    pub view_w: f64,
    /// Native view frame height in points.
    pub view_h: f64,
    /// Backing scale factor (device pixels per point).
    pub scale: f64,
    /// Layer bounds width in points.
    pub layer_w: f64,
    /// Layer bounds height in points.
    pub layer_h: f64,
    /// Drawable width in device pixels.
    pub drawable_w: u64,
    /// Drawable height in device pixels.
    pub drawable_h: u64,
    /// Rendering device name (e.g. the system graphics device).
    pub device_name: String,
    /// Whether the layer pixel format is 16-bit float.
    pub float16: bool,
    /// Whether the layer asked for extended dynamic range content.
    pub edr: bool,
}

/// Per-frame draw report.
#[derive(Debug, Clone, Copy)]
pub struct FrameReport {
    /// Whether a drawable was acquired and presented.
    pub presented: bool,
    /// Drawable width in device pixels this frame.
    pub drawable_w: u64,
    /// Drawable height in device pixels this frame.
    pub drawable_h: u64,
    /// Scan-marker phase in `[0, 1)` drawn this frame.
    pub marker: f32,
    /// Middle-row band samples in display order, present only on the
    /// backend's designated readback frame (numeric HDR proof).
    pub samples: Option<[f32; 8]>,
}

/// Viewport failure modes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ViewportError {
    /// This machine has no native viewport backend.
    Unsupported,
    /// The handle is null or does not name a live native surface.
    InvalidHandle,
    /// The backend failed; the string is a human-readable cause.
    Backend(String),
}

impl fmt::Display for ViewportError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Unsupported => write!(f, "native viewport unsupported on this machine"),
            Self::InvalidHandle => write!(f, "invalid native surface handle"),
            Self::Backend(cause) => write!(f, "viewport backend failed: {cause}"),
        }
    }
}

impl std::error::Error for ViewportError {}

/// Pointer press/move/release/scroll, in viewport-local logical points.
///
/// Origin top-left, matching the UI framework's logical pixels, so both input
/// paths (framework callback and native view subclass) produce identical data.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NativePointerKind {
    /// Button pressed.
    Down,
    /// Pointer moved (button state carried in [`NativePointerEvent::button`]).
    Move,
    /// Button released.
    Up,
    /// Wheel or trackpad scroll.
    Scroll,
}

/// Modifier key state at the time of a pointer event.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
#[expect(clippy::struct_excessive_bools)] // Four independent key facts; a bitflag would hide names.
pub struct ModifierState {
    /// Shift held.
    pub shift: bool,
    /// Control held.
    pub control: bool,
    /// Option/Alt held.
    pub option: bool,
    /// Command held.
    pub command: bool,
}

/// One native pointer event, plain data.
#[derive(Debug, Clone, Copy)]
pub struct NativePointerEvent {
    /// What happened.
    pub kind: NativePointerKind,
    /// Viewport-local x in logical points (origin top-left).
    pub x: f64,
    /// Viewport-local y in logical points (origin top-left).
    pub y: f64,
    /// Button number (`0` = primary; `None` for hover moves and scrolls).
    pub button: Option<u32>,
    /// Modifier state.
    pub modifiers: ModifierState,
    /// Event timestamp in seconds (platform clock).
    pub timestamp_secs: f64,
    /// Scroll delta x (pixels for precise devices, lines otherwise).
    pub scroll_dx: f64,
    /// Scroll delta y (pixels for precise devices, lines otherwise).
    pub scroll_dy: f64,
}

/// Input delivery callback owned by the viewport while attached.
pub type ViewportInputSink = Box<dyn Fn(NativePointerEvent) + Send + 'static>;

/// Crate-internal viewport implementation behind [`ViewportHandle`].
///
pub(crate) trait ViewportBackend: Send {
    /// Notes a new logical rectangle. Pixels always derive from the live
    /// view each frame; the rectangle is a hint, not a command.
    fn set_rect(&self, rect: ViewportRect);
    /// Draws one test-pattern frame and presents it.
    fn draw_frame(&self, frame: u64) -> Result<FrameReport, ViewportError>;
    /// Reads back live geometry from the native surface.
    fn geometry(&self) -> Result<ViewportGeom, ViewportError>;
    /// Releases backend objects (idempotent; also runs on drop).
    fn detach(self: Box<Self>);
}

/// Owned native viewport. Dropping detaches.
pub struct ViewportHandle {
    inner: Option<Box<dyn ViewportBackend>>,
}

impl ViewportHandle {
    /// Records a new logical rectangle for the viewport.
    pub fn set_rect(&self, rect: ViewportRect) {
        if let Some(inner) = self.inner.as_ref() {
            inner.set_rect(rect);
        }
    }

    /// Draws one frame of the test pattern and presents it.
    ///
    /// # Errors
    ///
    /// Returns [`ViewportError`] when the surface is gone or the backend fails.
    pub fn draw_frame(&self, frame: u64) -> Result<FrameReport, ViewportError> {
        match self.inner.as_ref() {
            Some(inner) => inner.draw_frame(frame),
            None => Err(ViewportError::InvalidHandle),
        }
    }

    /// Reads back live geometry from the native surface.
    ///
    /// # Errors
    ///
    /// Returns [`ViewportError`] when the surface is gone or the backend fails.
    pub fn geometry(&self) -> Result<ViewportGeom, ViewportError> {
        match self.inner.as_ref() {
            Some(inner) => inner.geometry(),
            None => Err(ViewportError::InvalidHandle),
        }
    }

    /// Detaches the viewport, releasing backend objects. Idempotent.
    pub fn detach(mut self) {
        if let Some(inner) = self.inner.take() {
            inner.detach();
        }
    }
}

impl Drop for ViewportHandle {
    fn drop(&mut self) {
        if let Some(inner) = self.inner.take() {
            inner.detach();
        }
    }
}

/// Draws nothing; exists so the handle type is nameable without a backend.
impl fmt::Debug for ViewportHandle {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ViewportHandle")
            .field("attached", &self.inner.is_some())
            .finish()
    }
}

/// Device-pixel drawable size for a logical rectangle at a scale factor.
///
/// Shared by the backend and the tests so the rounding rule has one home:
/// round to nearest, clamp at zero; a zero-area rectangle yields `(0, 0)`.
#[must_use]
pub fn drawable_size(rect: &ViewportRect, scale: f64) -> (u64, u64) {
    #[expect(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let convert = |points: f64| {
        let pixels = (points * scale).round().clamp(0.0, f64::from(u32::MAX));
        pixels as u64
    };
    (convert(rect.width), convert(rect.height))
}

/// Attaches a viewport to a caller-owned native surface handle.
///
/// The handle crosses as one integer and is only valid in this process.
/// `rect` is the initial logical rectangle; pixels always derive from the
/// live surface afterwards.
///
/// # Errors
///
/// Returns [`ViewportError::Unsupported`] where no backend exists,
/// [`ViewportError::InvalidHandle`] for a null handle, or
/// [`ViewportError::Backend`] when the backend fails.
pub fn attach_viewport(
    native_handle: usize,
    rect: ViewportRect,
) -> Result<ViewportHandle, ViewportError> {
    super::capabilities::selected_backend()
        .attach_viewport(native_handle, &rect, None)
        .map(|inner| ViewportHandle { inner: Some(inner) })
}

/// Attaches a viewport that also delivers native pointer input to `sink`.
///
/// Same as [`attach_viewport`], plus a native input path whose events arrive
/// as [`NativePointerEvent`] on the main thread.
///
/// # Errors
///
/// Same as [`attach_viewport`].
pub fn attach_viewport_with_input(
    native_handle: usize,
    rect: ViewportRect,
    sink: ViewportInputSink,
) -> Result<ViewportHandle, ViewportError> {
    super::capabilities::selected_backend()
        .attach_viewport(native_handle, &rect, Some(sink))
        .map(|inner| ViewportHandle { inner: Some(inner) })
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

    use super::super::capabilities::BackendProbe;
    use super::*;

    #[test]
    fn error_lines_read_clean() {
        assert_eq!(
            ViewportError::Unsupported.to_string(),
            "native viewport unsupported on this machine"
        );
        assert_eq!(
            ViewportError::InvalidHandle.to_string(),
            "invalid native surface handle"
        );
        assert_eq!(
            ViewportError::Backend("no device".to_string()).to_string(),
            "viewport backend failed: no device"
        );
    }

    #[test]
    fn drawable_size_rounds_half_up_and_clamps() {
        let rect = ViewportRect {
            x: 0.0,
            y: 0.0,
            width: 800.0,
            height: 600.0,
        };
        assert_eq!(drawable_size(&rect, 2.0), (1600, 1200));
        assert_eq!(drawable_size(&rect, 1.0), (800, 600));
        let odd = ViewportRect {
            x: 0.0,
            y: 0.0,
            width: 100.5,
            height: 0.4,
        };
        assert_eq!(drawable_size(&odd, 1.0), (101, 0));
        let negative = ViewportRect {
            x: 0.0,
            y: 0.0,
            width: -3.0,
            height: 10.0,
        };
        assert_eq!(drawable_size(&negative, 2.0), (0, 20));
    }

    #[test]
    fn empty_backend_reports_unsupported() {
        let rect = ViewportRect {
            x: 0.0,
            y: 0.0,
            width: 10.0,
            height: 10.0,
        };
        assert!(matches!(
            super::super::empty::EmptyBackend.attach_viewport(0x1000, &rect, None),
            Err(ViewportError::Unsupported)
        ));
        assert!(matches!(
            super::super::empty::EmptyBackend.attach_viewport(
                0x1000,
                &rect,
                Some(Box::new(|_| {}))
            ),
            Err(ViewportError::Unsupported)
        ));
    }

    #[test]
    fn null_handle_is_invalid_on_any_backend() {
        let rect = ViewportRect {
            x: 0.0,
            y: 0.0,
            width: 10.0,
            height: 10.0,
        };
        let err = attach_viewport(0, rect).unwrap_err();
        assert!(matches!(
            err,
            ViewportError::Unsupported | ViewportError::InvalidHandle
        ));
    }

    #[test]
    fn detached_handle_reports_invalid() {
        struct Stub;
        impl ViewportBackend for Stub {
            fn set_rect(&self, _rect: ViewportRect) {}
            fn draw_frame(&self, _frame: u64) -> Result<FrameReport, ViewportError> {
                Ok(FrameReport {
                    presented: false,
                    drawable_w: 0,
                    drawable_h: 0,
                    marker: 0.0,
                    samples: None,
                })
            }
            fn geometry(&self) -> Result<ViewportGeom, ViewportError> {
                Err(ViewportError::Unsupported)
            }
            fn detach(self: Box<Self>) {}
        }
        let handle = ViewportHandle {
            inner: Some(Box::new(Stub)),
        };
        handle.set_rect(ViewportRect {
            x: 0.0,
            y: 0.0,
            width: 1.0,
            height: 1.0,
        });
        handle.detach();
    }
}
