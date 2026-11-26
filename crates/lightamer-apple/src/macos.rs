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

    fn attach_viewport(
        &self,
        native_handle: usize,
        rect: &super::viewport::ViewportRect,
        sink: Option<super::viewport::ViewportInputSink>,
    ) -> Result<Box<dyn super::viewport::ViewportBackend>, super::viewport::ViewportError> {
        MacOsViewport::attach(native_handle, rect, sink)
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
// ---------------------------------------------------------------------------
// Viewport (A7b): native surface + Metal test pattern + native input path.
//
// The UI framework owns the native surface; this backend borrows its handle
// (one integer) and swaps the view's layer for a `CAMetalLayer` configured
// exactly like the gpui-viewport spike: 16-bit float, EDR content enabled,
// extended linear sRGB. Rendering uses `objc2-metal` only (no `metal`
// crate): device, queue, one MSL library, one pipeline, per-frame drawable.
//
// Everything here runs on the main thread: AppKit views are main-thread
// objects and the gpui host drives frames from its main-thread loop.
// ---------------------------------------------------------------------------

use super::viewport::{
    FrameReport, ModifierState, NativePointerEvent, NativePointerKind, ViewportBackend,
    ViewportError, ViewportGeom, ViewportInputSink, ViewportRect, drawable_size,
};
use objc2::rc::{Allocated, Retained};
use objc2::runtime::{AnyObject, ProtocolObject};
use objc2::{AnyThread, MainThreadMarker, MainThreadOnly, msg_send};
use objc2_app_kit::{
    NSAutoresizingMaskOptions, NSEvent, NSEventModifierFlags, NSTrackingArea,
    NSTrackingAreaOptions, NSView,
};
use objc2_core_foundation::CGSize;
use objc2_core_graphics::kCGColorSpaceExtendedLinearSRGB;
use objc2_foundation::{NSDictionary, NSString};
use objc2_metal::{
    MTLClearColor, MTLCommandBuffer, MTLCommandEncoder, MTLCommandQueue, MTLLibrary, MTLLoadAction,
    MTLOrigin, MTLPixelFormat, MTLPrimitiveType, MTLRegion, MTLRenderCommandEncoder,
    MTLRenderPassDescriptor, MTLRenderPipelineDescriptor, MTLRenderPipelineState, MTLSize,
    MTLStoreAction, MTLTexture,
};
use objc2_quartz_core::{CALayer, CAMetalDrawable, CAMetalLayer};
use std::cell::Cell;
use std::collections::HashMap;
use std::ffi::c_void;
use std::ptr::NonNull;
use std::sync::{LazyLock, Mutex};

/// Test-pattern shader: four brightness bands plus a sweeping scan marker.
/// Verbatim from the gpui-viewport spike (own code).
const VIEWPORT_MSL: &str = r"
#include <metal_stdlib>
using namespace metal;

struct VOut {
    float4 pos [[position]];
    float2 uv;
};

vertex VOut v_main(uint vid [[vertex_id]]) {
    float2 p[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    float2 t[3] = { float2(0.0, 1.0), float2(2.0, 1.0), float2(0.0, -1.0) };
    VOut o;
    o.pos = float4(p[vid], 0.0, 1.0);
    o.uv = t[vid];
    return o;
}

struct U {
    float w;
    float h;
    float v0;
    float v1;
    float v2;
    float v3;
    float marker;
    float pad;
};

fragment float4 f_main(VOut in [[stage_in]], constant U &u [[buffer(0)]]) {
    float x = in.uv.x * u.w;
    float y = in.uv.y * u.h;
    int band = clamp(int(in.uv.x * 4.0), 0, 3);
    float v = band == 0 ? u.v0 : (band == 1 ? u.v1 : (band == 2 ? u.v2 : u.v3));
    float3 c = float3(v);

    if (y > u.h - 28.0) {
        float mx = fract(u.marker) * u.w;
        if (abs(x - mx) < 8.0) {
            c = float3(1.0);
        } else {
            c = float3(v * 0.25);
        }
    }
    return float4(c, 1.0);
}
";

/// Nominal band values; the two above 1.0 prove 16-bit float storage.
const BAND_VALUES: [f32; 4] = [0.5, 1.0, 2.0, 4.0];
/// Scan-marker advance per frame (phase wraps at 1.0).
const MARKER_STEP: f32 = 0.013;
/// Frame on which the drawable middle row is read back for numeric HDR proof.
const READBACK_FRAME: u64 = 60;

/// Frame uniforms, matching struct `U` in [`VIEWPORT_MSL`].
#[repr(C)]
#[derive(Clone, Copy)]
struct Uniforms {
    w: f32,
    h: f32,
    v: [f32; 4],
    marker: f32,
    pad: f32,
}

// Native input sinks by subview address. Main thread only in practice; the
// mutex only guards against teardown racing an in-flight event.
static INPUT_SINKS: LazyLock<Mutex<HashMap<usize, ViewportInputSink>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

// `NSView` subclass that forwards pointer events to the registered sink.
//
// Installed as a full-area subview of the framework-owned view (path B), so
// no class-swapping of framework objects is needed.
objc2::define_class!(
    #[unsafe(super(NSView))]
    #[thread_kind = MainThreadOnly]
    #[name = "DtViewportInputView"]
    struct ViewportInputView;

    impl ViewportInputView {
        #[unsafe(method(mouseDown:))]
        fn __mouse_down(&self, event: &NSEvent) {
            Self::deliver(self, NativePointerKind::Down, event, false);
        }

        #[unsafe(method(mouseDragged:))]
        fn __mouse_dragged(&self, event: &NSEvent) {
            Self::deliver(self, NativePointerKind::Move, event, false);
        }

        #[unsafe(method(mouseMoved:))]
        fn __mouse_moved(&self, event: &NSEvent) {
            Self::deliver(self, NativePointerKind::Move, event, true);
        }

        #[unsafe(method(mouseUp:))]
        fn __mouse_up(&self, event: &NSEvent) {
            Self::deliver(self, NativePointerKind::Up, event, false);
        }

        #[unsafe(method(scrollWheel:))]
        fn __scroll_wheel(&self, event: &NSEvent) {
            Self::deliver(self, NativePointerKind::Scroll, event, false);
        }
    }
);

impl ViewportInputView {
    /// Converts one `AppKit` event to viewport-local data and calls the sink.
    ///
    /// `hover` marks button-free moves: they carry no button, matching the
    /// framework path. Scroll deltas are read only for scroll events.
    fn deliver(view: &ViewportInputView, kind: NativePointerKind, event: &NSEvent, hover: bool) {
        // SAFETY: `ViewportInputView` subclasses `NSView`; the instance prefix
        // is a valid `NSView` with the same lifetime.
        let nsview: &NSView = unsafe { &*std::ptr::from_ref(view).cast::<NSView>() };
        let in_window = event.locationInWindow();
        let local = nsview.convertPoint_fromView(in_window, None);
        let height = nsview.bounds().size.height;
        let flags = event.modifierFlags();
        // Scroll deltas exist only on scroll events. Reading them on moves
        // aborts the process (3x reproduced on synthetic moves, bisected to
        // `scrollingDeltaX`; real scroll events read fine), so each read stays
        // behind the kind check.
        let is_scroll = kind == NativePointerKind::Scroll;
        let pointer = NativePointerEvent {
            kind,
            x: local.x,
            y: height - local.y,
            button: if hover {
                None
            } else {
                u32::try_from(event.buttonNumber().max(0)).ok()
            },
            modifiers: ModifierState {
                shift: flags.contains(NSEventModifierFlags::Shift),
                control: flags.contains(NSEventModifierFlags::Control),
                option: flags.contains(NSEventModifierFlags::Option),
                command: flags.contains(NSEventModifierFlags::Command),
            },
            timestamp_secs: event.timestamp(),
            scroll_dx: if is_scroll {
                event.scrollingDeltaX()
            } else {
                0.0
            },
            scroll_dy: if is_scroll {
                event.scrollingDeltaY()
            } else {
                0.0
            },
        };
        let key = std::ptr::from_ref(view) as usize;
        if let Ok(sinks) = INPUT_SINKS.lock()
            && let Some(sink) = sinks.get(&key)
        {
            sink(pointer);
        }
    }
}

/// macOS viewport: borrowed host view, owned Metal objects, optional subview.
struct MacOsViewport {
    /// View carrying our layer: the host view (path A) or our subview.
    /// Borrowed; the UI framework owns the host for the attach lifetime.
    render_view: *mut NSView,
    /// Path-B input subview, kept alive while attached.
    owned_subview: Option<Retained<ViewportInputView>>,
    /// Sink map key while a path-B sink is registered.
    sink_key: Option<usize>,
    layer: Retained<CAMetalLayer>,
    device: Retained<ProtocolObject<dyn MTLDevice>>,
    queue: Retained<ProtocolObject<dyn MTLCommandQueue>>,
    pipeline: Retained<ProtocolObject<dyn MTLRenderPipelineState>>,
    drawable_w: Cell<u64>,
    drawable_h: Cell<u64>,
    marker: Cell<f32>,
}

// SAFETY: all methods run on the main thread (AppKit requirement, documented
// on the module); the struct only crosses threads as an inert handle.
unsafe impl Send for MacOsViewport {}

/// f16 bits (little-endian half float) to `f32`. Verbatim from the spike.
fn f16_to_f32(bits: u16) -> f32 {
    let sign = (bits >> 15) & 1;
    let exp = i32::from((bits >> 10) & 0x1f);
    let frac = f32::from(bits & 0x3ff);
    let value = if exp == 0 {
        if frac == 0.0 {
            0.0
        } else {
            frac * 2f32.powi(-24)
        }
    } else if exp == 0x1f {
        if frac == 0.0 { f32::INFINITY } else { f32::NAN }
    } else {
        (1.0 + frac / 1024.0) * 2f32.powi(exp - 15)
    };
    if sign == 1 { -value } else { value }
}

/// Device pixels as `f32` uniforms. Drawables never exceed 2^32 pixels per
/// side ([`drawable_size`] clamps there), so the conversion is exact for all
/// real sizes; the clamp keeps absurd inputs finite.
#[allow(clippy::cast_possible_truncation, clippy::cast_precision_loss)]
fn pixels_to_f32(pixels: u64) -> f32 {
    u32::try_from(pixels).unwrap_or(u32::MAX) as f32
}

/// Points as whole device pixels, matching [`drawable_size`].
#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
fn points_to_pixels(points: f64) -> u64 {
    points.round().clamp(0.0, f64::from(u32::MAX)) as u64
}

impl MacOsViewport {
    /// Attaches to `native_handle`, which must name a live `NSView` on the
    /// main thread. A `Some` sink installs the path-B input subview.
    fn attach(
        native_handle: usize,
        _rect: &ViewportRect,
        sink: Option<ViewportInputSink>,
    ) -> Result<Box<dyn ViewportBackend>, ViewportError> {
        if native_handle == 0 {
            return Err(ViewportError::InvalidHandle);
        }
        // SAFETY: caller contract — the handle names a live `NSView`, this
        // runs on the main thread, and the view outlives the attachment.
        let host: &NSView = unsafe { &*(native_handle as *const NSView) };
        let device = MTLCreateSystemDefaultDevice()
            .ok_or_else(|| ViewportError::Backend("no system Metal device".to_string()))?;
        let queue = device
            .newCommandQueue()
            .ok_or_else(|| ViewportError::Backend("no Metal command queue".to_string()))?;
        let source = NSString::from_str(VIEWPORT_MSL);
        let library = device
            .newLibraryWithSource_options_error(&source, None)
            .map_err(|err| ViewportError::Backend(format!("MSL compile failed: {err:?}")))?;
        let vertex_name = NSString::from_str("v_main");
        let fragment_name = NSString::from_str("f_main");
        let vertex = library
            .newFunctionWithName(&vertex_name)
            .ok_or_else(|| ViewportError::Backend("missing vertex function v_main".to_string()))?;
        let fragment = library.newFunctionWithName(&fragment_name).ok_or_else(|| {
            ViewportError::Backend("missing fragment function f_main".to_string())
        })?;
        let descriptor = MTLRenderPipelineDescriptor::new();
        descriptor.setVertexFunction(Some(&vertex));
        descriptor.setFragmentFunction(Some(&fragment));
        let attachments = descriptor.colorAttachments();
        // SAFETY: pipeline descriptors always vend color attachment 0.
        let attachment = unsafe { attachments.objectAtIndexedSubscript(0) };
        attachment.setPixelFormat(MTLPixelFormat::RGBA16Float);
        attachment.setBlendingEnabled(false);
        let pipeline = device
            .newRenderPipelineStateWithDescriptor_error(&descriptor)
            .map_err(|err| ViewportError::Backend(format!("pipeline failed: {err:?}")))?;

        let layer = CAMetalLayer::new();
        layer.setDevice(Some(&device));
        layer.setPixelFormat(MTLPixelFormat::RGBA16Float);
        layer.setFramebufferOnly(false);
        layer.setOpaque(true);
        layer.setMaximumDrawableCount(3);
        layer.setWantsExtendedDynamicRangeContent(true);
        // SAFETY: `extern` framework constant, immutable and always present
        // on macOS; reading it has no preconditions.
        let edr_space = unsafe { CGColorSpace::with_name(Some(kCGColorSpaceExtendedLinearSRGB)) };
        if let Some(space) = edr_space {
            layer.setColorspace(Some(&space));
        }
        // SAFETY: `CAMetalLayer` subclasses `CALayer`; the pointer is a valid
        // `CALayer` reference with the layer's lifetime.
        let as_calayer: &CALayer = unsafe { &*Retained::as_ptr(&layer).cast::<CALayer>() };

        let (render_view, owned_subview, sink_key) = match sink {
            None => {
                host.setWantsLayer(true);
                host.setLayer(Some(as_calayer));
                (native_handle as *mut NSView, None, None)
            }
            Some(sink) => {
                let subview = Self::install_input_subview(host)?;
                let key = Retained::as_ptr(&subview) as usize;
                INPUT_SINKS
                    .lock()
                    .map_err(|_| ViewportError::Backend("input sink lock poisoned".to_string()))?
                    .insert(key, sink);
                // SAFETY: same subclass-prefix reason as above.
                let subview_ns: &NSView = unsafe { &*Retained::as_ptr(&subview).cast::<NSView>() };
                subview_ns.setWantsLayer(true);
                subview_ns.setLayer(Some(as_calayer));
                (
                    Retained::as_ptr(&subview) as *mut NSView,
                    Some(subview),
                    Some(key),
                )
            }
        };
        Ok(Box::new(Self {
            render_view,
            owned_subview,
            sink_key,
            layer,
            device,
            queue,
            pipeline,
            drawable_w: Cell::new(0),
            drawable_h: Cell::new(0),
            marker: Cell::new(0.0),
        }))
    }

    /// Installs the path-B input subview covering the host view.
    fn install_input_subview(host: &NSView) -> Result<Retained<ViewportInputView>, ViewportError> {
        let frame = host.bounds();
        let mtm = MainThreadMarker::new().ok_or_else(|| {
            ViewportError::Backend("input subview needs the main thread".to_string())
        })?;
        let allocated: Allocated<ViewportInputView> = ViewportInputView::alloc(mtm);
        // SAFETY: `initWithFrame:` on a freshly allocated view with the host
        // bounds; the standard initializer, no further preconditions.
        let subview: Retained<ViewportInputView> =
            unsafe { msg_send![allocated, initWithFrame: frame] };
        // SAFETY: subclass-prefix cast, same reason as the layer cast.
        let subview_ns: &NSView = unsafe { &*Retained::as_ptr(&subview).cast::<NSView>() };
        subview_ns.setAutoresizingMask(
            NSAutoresizingMaskOptions::ViewWidthSizable
                | NSAutoresizingMaskOptions::ViewHeightSizable,
        );
        host.addSubview(subview_ns);
        let options = NSTrackingAreaOptions::MouseMoved
            | NSTrackingAreaOptions::ActiveAlways
            | NSTrackingAreaOptions::InVisibleRect;
        // SAFETY: every object pointer is a valid `AnyObject` pointer; the
        // tracking area retains its owner, so use-after-free is impossible.
        let owner: &AnyObject = unsafe { &*Retained::as_ptr(&subview).cast::<AnyObject>() };
        let user_info: Option<&NSDictionary<AnyObject, AnyObject>> = None;
        // SAFETY: `initWithRect:options:owner:userInfo:` with the live view
        // as owner and no user info; no further preconditions.
        let area: Retained<NSTrackingArea> = unsafe {
            msg_send![NSTrackingArea::alloc(), initWithRect: frame, options: options, owner: owner, userInfo: user_info]
        };
        subview_ns.addTrackingArea(&area);
        Ok(subview)
    }

    /// Live view frame plus backing scale.
    fn view_frame(&self) -> (f64, f64, f64, f64, f64) {
        // SAFETY: `render_view` names the live layer-hosting view; attach
        // and detach bracket its lifetime on the main thread.
        let view: &NSView = unsafe { &*self.render_view };
        let frame = view.frame();
        let scale = view.window().map_or(2.0, |w| w.backingScaleFactor());
        (
            frame.origin.x,
            frame.origin.y,
            frame.size.width,
            frame.size.height,
            scale,
        )
    }

    /// Reads the middle-row band samples of `texture` (numeric HDR proof).
    ///
    /// Returns zeros for degenerate sizes rather than touching the GPU with
    /// a nonsense region; the width cap is Metal's maximum 2D texture side.
    fn readback_samples(
        texture: &ProtocolObject<dyn MTLTexture>,
        width: u64,
        height: u64,
    ) -> [f32; 8] {
        let zeros = [0.0f32; 8];
        if !(16..=16_384).contains(&width) || height == 0 {
            return zeros;
        }
        let w = usize::try_from(width).unwrap_or(0);
        let h = usize::try_from(height).unwrap_or(0);
        if w < 16 || h == 0 {
            return zeros;
        }
        let stride = w.saturating_mul(8);
        let mut row = vec![0u16; w.saturating_mul(4)];
        let region = MTLRegion {
            origin: MTLOrigin {
                x: 0,
                y: h / 2,
                z: 0,
            },
            size: MTLSize {
                width: w,
                height: 1,
                depth: 1,
            },
        };
        if let Some(bytes) = NonNull::new(row.as_mut_ptr().cast::<c_void>()) {
            // SAFETY: `row` holds `w * 4` half-floats (`stride` bytes);
            // the region is the one in-bounds middle row of the texture.
            unsafe {
                texture.getBytes_bytesPerRow_fromRegion_mipmapLevel(bytes, stride, region, 0);
            }
        }
        let mut samples = [0.0f32; 8];
        for (slot, sample) in samples.iter_mut().enumerate() {
            let slot = u64::try_from(slot).unwrap_or(7);
            let x = width.saturating_mul(slot.saturating_mul(2).saturating_add(1)) / 16;
            let index = usize::try_from(x.saturating_mul(4)).unwrap_or(usize::MAX);
            *sample = f16_to_f32(row.get(index).copied().unwrap_or(0));
        }
        samples
    }
    /// Encodes the test pattern into `texture` and schedules presentation.
    /// Returns the committed command buffer, or `None` when no encoder could
    /// be made (a soft per-frame miss, not a backend error).
    fn encode_present(
        &self,
        texture: &ProtocolObject<dyn MTLTexture>,
        uniforms: &Uniforms,
        drawable: &ProtocolObject<dyn CAMetalDrawable>,
    ) -> Option<Retained<ProtocolObject<dyn MTLCommandBuffer>>> {
        let pass = MTLRenderPassDescriptor::renderPassDescriptor();
        let colors = pass.colorAttachments();
        // SAFETY: render-pass descriptors always vend color attachment 0.
        let attachment = unsafe { colors.objectAtIndexedSubscript(0) };
        attachment.setTexture(Some(texture));
        attachment.setLoadAction(MTLLoadAction::Clear);
        attachment.setClearColor(MTLClearColor {
            red: 0.0,
            green: 0.0,
            blue: 0.0,
            alpha: 1.0,
        });
        attachment.setStoreAction(MTLStoreAction::Store);
        let commands = self.queue.commandBuffer()?;
        let encoder = commands.renderCommandEncoderWithDescriptor(&pass)?;
        encoder.setRenderPipelineState(&self.pipeline);
        if let Some(bytes) = NonNull::new(std::ptr::from_ref(uniforms).cast_mut().cast::<c_void>())
        {
            // SAFETY: `uniforms` outlives the encoding call and the byte
            // length matches the struct; index 0 is the shader's buffer.
            unsafe {
                encoder.setFragmentBytes_length_atIndex(bytes, std::mem::size_of::<Uniforms>(), 0);
            }
        }
        // SAFETY: the pipeline state is set; this draws the fullscreen
        // triangle (3 vertices) that the shader expects.
        unsafe {
            encoder.drawPrimitives_vertexStart_vertexCount(MTLPrimitiveType::Triangle, 0, 3);
        }
        encoder.endEncoding();
        commands.presentDrawable(ProtocolObject::from_ref(drawable));
        commands.commit();
        Some(commands)
    }
}

impl ViewportBackend for MacOsViewport {
    fn set_rect(&self, _rect: ViewportRect) {
        // Intentionally record-only: pixels derive from the live view every
        // frame, so there is nothing to store. The rectangle exists because
        // the seam takes an initial rectangle at attach time.
    }

    fn draw_frame(&self, frame: u64) -> Result<FrameReport, ViewportError> {
        let (_, _, view_w, view_h, scale) = self.view_frame();
        let rect = ViewportRect {
            x: 0.0,
            y: 0.0,
            width: view_w,
            height: view_h,
        };
        let (width, height) = drawable_size(&rect, scale);
        if width < 4 || height < 4 {
            return Ok(FrameReport {
                presented: false,
                drawable_w: width,
                drawable_h: height,
                marker: self.marker.get(),
                samples: None,
            });
        }
        if self.drawable_w.get() != width || self.drawable_h.get() != height {
            self.layer.setDrawableSize(CGSize {
                width: f64::from(u32::try_from(width).unwrap_or(u32::MAX)),
                height: f64::from(u32::try_from(height).unwrap_or(u32::MAX)),
            });
            self.layer.setContentsScale(scale);
            self.drawable_w.set(width);
            self.drawable_h.set(height);
        }
        let Some(drawable) = self.layer.nextDrawable() else {
            return Ok(FrameReport {
                presented: false,
                drawable_w: width,
                drawable_h: height,
                marker: self.marker.get(),
                samples: None,
            });
        };
        let texture = drawable.texture();
        let marker = self.marker.get();
        let uniforms = Uniforms {
            w: pixels_to_f32(width),
            h: pixels_to_f32(height),
            v: BAND_VALUES,
            marker,
            pad: 0.0,
        };
        let Some(commands) = self.encode_present(&texture, &uniforms, &drawable) else {
            return Ok(FrameReport {
                presented: false,
                drawable_w: width,
                drawable_h: height,
                marker,
                samples: None,
            });
        };

        let samples = if frame == READBACK_FRAME {
            commands.waitUntilCompleted();
            Some(Self::readback_samples(&texture, width, height))
        } else {
            None
        };
        self.marker.set((marker + MARKER_STEP) % 1.0);
        Ok(FrameReport {
            presented: true,
            drawable_w: width,
            drawable_h: height,
            marker,
            samples,
        })
    }

    fn geometry(&self) -> Result<ViewportGeom, ViewportError> {
        let (view_x, view_y, view_w, view_h, scale) = self.view_frame();
        let bounds = self.layer.bounds();
        let drawable = self.layer.drawableSize();
        Ok(ViewportGeom {
            view_x,
            view_y,
            view_h,
            view_w,
            scale,
            layer_w: bounds.size.width,
            layer_h: bounds.size.height,
            drawable_w: points_to_pixels(drawable.width),
            drawable_h: points_to_pixels(drawable.height),
            device_name: self.device.name().to_string(),
            float16: self.layer.pixelFormat() == MTLPixelFormat::RGBA16Float,
            edr: self.layer.wantsExtendedDynamicRangeContent(),
        })
    }

    fn detach(self: Box<Self>) {
        if let Some(key) = self.sink_key {
            if let Ok(mut sinks) = INPUT_SINKS.lock() {
                sinks.remove(&key);
            }
            if let Some(subview) = self.owned_subview.as_ref() {
                // SAFETY: subclass-prefix cast, same reason as construction.
                let view: &NSView = unsafe { &*Retained::as_ptr(subview).cast::<NSView>() };
                view.removeFromSuperview();
            }
        }
    }
}
