// gpui-fast native-surface viewport spike.
//
// One window: left = our own CAMetalLayer/Metal viewport on a gpui-fast native
// composition surface; right = a gpui-kit panel. The viewport redraws every
// frame; the panel changes on a slower timer; a deferred gpui overlay opens
// periodically above the native surface.
//
// Everything this program observes is printed to stdout as `K <key> ...` lines
// so the run can be audited from traces/app.log alone.

use std::cell::Cell;
use std::rc::Rc;
use std::time::{Duration, Instant};

use anyhow::{Context as _, Result};
use gpui_kit::component::slider::{Slider, SliderState};
use gpui_kit::prelude::*;
use gpui_kit::*;
use metal::*;
use core_graphics_types::geometry::CGSize;
use objc2::MainThreadMarker;
use objc2_app_kit::{NSScreen, NSView, NSWindow};
use objc2_core_graphics::{kCGColorSpaceExtendedLinearSRGB, CGColorSpace};
use objc2_quartz_core::{CALayer, CAMetalLayer};

// ---------------------------------------------------------------------------
// Metal
// ---------------------------------------------------------------------------

const MSL: &str = r#"
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

    // Bottom strip: a sweeping marker so every frame changes something the
    // screen-capture probe can see. The four band interiors stay static.
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
"#;

#[repr(C)]
#[derive(Clone, Copy)]
struct Uniforms {
    w: f32,
    h: f32,
    v: [f32; 4],
    marker: f32,
    pad: f32,
}

fn f16_to_f32(bits: u16) -> f32 {
    let sign = (bits >> 15) & 1;
    let exp = ((bits >> 10) & 0x1f) as i32;
    let frac = (bits & 0x3ff) as f32;
    let v = if exp == 0 {
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
    if sign == 1 { -v } else { v }
}

struct MetalView {
    view: *mut NSView,
    layer: MetalLayer,
    device: Device,
    queue: CommandQueue,
    pipeline: RenderPipelineState,
    frames: Cell<u64>,
    drawable_w: Cell<u64>,
    drawable_h: Cell<u64>,
    mount_logged: Cell<bool>,
}

impl MetalView {
    fn attach(view: *mut NSView) -> Result<Rc<MetalView>> {
        let device = Device::system_default().context("MTLCreateSystemDefaultDevice returned nil")?;
        let queue = device.new_command_queue();
        let lib = device
            .new_library_with_source(MSL, &CompileOptions::new())
            .map_err(|e| anyhow::anyhow!("MSL compile failed: {e}"))?;
        let vf = lib
            .get_function("v_main", None)
            .map_err(|e| anyhow::anyhow!("vertex fn: {e}"))?;
        let ff = lib
            .get_function("f_main", None)
            .map_err(|e| anyhow::anyhow!("fragment fn: {e}"))?;
        let desc = RenderPipelineDescriptor::new();
        desc.set_vertex_function(Some(&vf));
        desc.set_fragment_function(Some(&ff));
        let att = desc
            .color_attachments()
            .object_at(0)
            .context("no color attachment 0")?;
        att.set_pixel_format(MTLPixelFormat::RGBA16Float);
        att.set_blending_enabled(false);
        let pipeline = device
            .new_render_pipeline_state(&desc)
            .map_err(|e| anyhow::anyhow!("pipeline: {e}"))?;

        let layer = MetalLayer::new();
        layer.set_device(&device);
        layer.set_pixel_format(MTLPixelFormat::RGBA16Float);
        layer.set_framebuffer_only(false);
        layer.set_opaque(true);
        layer.set_maximum_drawable_count(3);
        layer.set_wants_extended_dynamic_range_content(true);
        if let Some(cs) = CGColorSpace::with_name(Some(unsafe { kCGColorSpaceExtendedLinearSRGB })) {
            let ca: &CAMetalLayer = unsafe { &*((&*layer) as *const MetalLayerRef as *const CAMetalLayer) };
            ca.setColorspace(Some(&cs));
            println!("K colorspace name={:?}", CGColorSpace::get_name(Some(&cs)));
        } else {
            println!("K colorspace FAILED kCGColorSpaceExtendedLinearSRGB");
        }

        unsafe {
            let nsview: &NSView = &*view;
            nsview.setWantsLayer(true);
            let ca_layer: &CALayer = &*((&*layer) as *const MetalLayerRef as *const CALayer);
            nsview.setLayer(Some(ca_layer));
        }
        println!(
            "K metal device={:?} layer_pixel_format={:?} layer_wants_edr={} layer_framebuffer_only={} layer_max_drawables={}",
            device.name(),
            layer.pixel_format(),
            layer.wants_extended_dynamic_range_content(),
            layer.framebuffer_only(),
            layer.maximum_drawable_count()
        );

        Ok(Rc::new(MetalView {
            view,
            layer,
            device,
            queue,
            pipeline,
            frames: Cell::new(0),
            drawable_w: Cell::new(0),
            drawable_h: Cell::new(0),
            mount_logged: Cell::new(false),
        }))
    }

    fn view_frame(&self) -> (f64, f64, f64, f64, f64) {
        unsafe {
            let view: &NSView = &*self.view;
            let r = view.frame();
            let scale = view
                .window()
                .map(|w: objc2::rc::Retained<NSWindow>| w.backingScaleFactor())
                .unwrap_or(2.0);
            (
                r.origin.x,
                r.origin.y,
                r.size.width,
                r.size.height,
                scale,
            )
        }
    }

    fn verify_offscreen(&self, w: u64, h: u64, uniforms: &Uniforms) {
        let d = TextureDescriptor::new();
        d.set_texture_type(MTLTextureType::D2);
        d.set_pixel_format(MTLPixelFormat::RGBA16Float);
        d.set_width(w);
        d.set_height(h);
        d.set_usage(MTLTextureUsage::RenderTarget);
        d.set_storage_mode(MTLStorageMode::Shared);
        let tex = self.device.new_texture(&d);
        let rpd = RenderPassDescriptor::new();
        let ca = rpd.color_attachments().object_at(0).expect("att");
        ca.set_texture(Some(&tex));
        ca.set_load_action(MTLLoadAction::Clear);
        ca.set_clear_color(MTLClearColor::new(0.0, 0.0, 0.0, 1.0));
        ca.set_store_action(MTLStoreAction::Store);
        let cb = self.queue.new_command_buffer();
        let enc = cb.new_render_command_encoder(&rpd);
        enc.set_render_pipeline_state(&self.pipeline);
        enc.set_fragment_bytes(
            0,
            std::mem::size_of::<Uniforms>() as u64,
            uniforms as *const Uniforms as *const std::ffi::c_void,
        );
        enc.draw_primitives(MTLPrimitiveType::Triangle, 0, 3);
        enc.end_encoding();
        cb.commit();
        cb.wait_until_completed();

        let stride = w * 8;
        let mut buf = vec![0u16; (w as usize) * 4];
        tex.get_bytes(
            buf.as_mut_ptr() as *mut std::ffi::c_void,
            stride,
            MTLRegion {
                origin: MTLOrigin { x: 0, y: h / 2, z: 0 },
                size: MTLSize { width: w, height: 1, depth: 1 },
            },
            0,
        );
        let mut samples = Vec::new();
        for k in 0..8u64 {
            let x = (w * (2 * k + 1)) / 16;
            samples.push((x, f16_to_f32(buf[(x as usize) * 4])));
        }
        println!(
            "K OFFSCREEN texture={}x{} format={:?} storage=Shared samples(x,v)={:?}",
            tex.width(),
            tex.height(),
            tex.pixel_format(),
            samples
        );
    }

    fn layer_geom(&self) -> String {
        let ca: &CAMetalLayer = unsafe { &*((&*self.layer) as *const MetalLayerRef as *const CAMetalLayer) };
        let bounds = ca.bounds();
        let frame = ca.frame();
        let ds = ca.drawableSize();
        format!(
            "layer_bounds=({:.1},{:.1} {:.1}x{:.1}) layer_frame=({:.1},{:.1} {:.1}x{:.1}) drawable_size={:.0}x{:.0} contents_scale={:.2} backing_scale={:.2}",
            bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height,
            frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
            ds.width, ds.height,
            ca.contentsScale(),
            self.view_frame().4
        )
    }

    fn draw(&self) -> bool {
        let (vx, vy, vw, vh, scale) = self.view_frame();
        let w = (vw * scale).round() as u64;
        let h = (vh * scale).round() as u64;
        if w < 4 || h < 4 {
            return false;
        }
        if self.drawable_w.get() != w || self.drawable_h.get() != h {
            self.layer.set_drawable_size(CGSize { width: w as f64, height: h as f64 });
            self.layer.set_contents_scale(scale);
            self.drawable_w.set(w);
            self.drawable_h.set(h);
            println!("K drawable size={}x{} view_points=({:.1},{:.1},{:.1},{:.1}) scale={:.2}", w, h, vx, vy, vw, vh, scale);
        }

        let Some(drawable) = self.layer.next_drawable() else {
            println!("K DRAWABLE_NIL");
            return false;
        };
        let texture = drawable.texture();
        if !self.mount_logged.get() {
            self.mount_logged.set(true);
            println!(
                "K drawable texture_format={:?} texture={}x{}",
                texture.pixel_format(),
                texture.width(),
                texture.height()
            );
        }

        let frame = self.frames.get();
        let marker = (frame as f32 * 0.013) % 1.0;
        let uniforms = Uniforms {
            w: w as f32,
            h: h as f32,
            v: [0.5, 1.0, 2.0, 4.0],
            marker,
            pad: 0.0,
        };
        let rpd = RenderPassDescriptor::new();
        let ca = rpd
            .color_attachments()
            .object_at(0)
            .expect("attachment 0");
        ca.set_texture(Some(texture));
        ca.set_load_action(MTLLoadAction::Clear);
        ca.set_clear_color(MTLClearColor::new(0.0, 0.0, 0.0, 1.0));
        ca.set_store_action(MTLStoreAction::Store);

        let readback = frame == 60 || frame == 240;

        let cb = self.queue.new_command_buffer();
        let enc = cb.new_render_command_encoder(&rpd);
        enc.set_render_pipeline_state(&self.pipeline);
        enc.set_fragment_bytes(
            0,
            std::mem::size_of::<Uniforms>() as u64,
            &uniforms as *const Uniforms as *const std::ffi::c_void,
        );
        enc.draw_primitives(MTLPrimitiveType::Triangle, 0, 3);
        enc.end_encoding();

        cb.present_drawable(drawable);
        cb.commit();

        if readback {
            cb.wait_until_completed();
            let mut direct = vec![0u16; (w as usize) * 4];
            texture.get_bytes(
                direct.as_mut_ptr() as *mut std::ffi::c_void,
                w * 8,
                MTLRegion {
                    origin: MTLOrigin { x: 0, y: h / 2, z: 0 },
                    size: MTLSize { width: w, height: 1, depth: 1 },
                },
                0,
            );
            let samples: Vec<(u64, f32)> = (0..8u64)
                .map(|k| {
                    let x = (w * (2 * k + 1)) / 16;
                    (x, f16_to_f32(direct[(x as usize) * 4]))
                })
                .collect();
            println!(
                "K READBACK frame={} row_y={} texture={}x{} format={:?} nominal=[0.5,1.0,2.0,4.0] samples(x,v)={:?}",
                frame,
                h / 2,
                texture.width(),
                texture.height(),
                texture.pixel_format(),
                samples
            );
        }
        if frame % 120 == 0 {
            println!(
                "K FRAME {} view=({:.1},{:.1} {:.1}x{:.1}) drawable={}x{} marker={:.3}",
                frame, vx, vy, vw, vh, w, h, marker
            );
            if frame == 120 {
                self.verify_offscreen(w, h, &uniforms);
            }
        }

        self.frames.set(frame + 1);
        true
    }
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

struct Proto {
    surface: Option<WindowCompositionSurface>,
    surface_id: Option<CompositionSurfaceId>,
    metal: Option<Rc<MetalView>>,
    started: Instant,
    tick: u64,
    value_a: f32,
    value_b: f32,
    overlay_open: bool,
    slider_a: Entity<SliderState>,
    slider_b: Entity<SliderState>,
    canvas_bounds: Rc<Cell<[f32; 4]>>,
    init_error: Option<String>,
    tasks: Vec<Task<()>>,
}

fn env_f32(key: &str, default: f32) -> f32 {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse::<f32>().ok())
        .unwrap_or(default)
}

impl Proto {
    fn new(window: &mut Window, cx: &mut Context<Self>) -> Self {
        let _ = window;
        let _ = cx;
        Self {
            surface: None,
            surface_id: None,
            metal: None,
            started: Instant::now(),
            tick: 0,
            value_a: 0.7,
            value_b: 0.2,
            overlay_open: false,
            slider_a: cx.new(|_| SliderState::new().min(0.0).max(1.0).step(0.01).default_value(0.7)),
            slider_b: cx.new(|_| SliderState::new().min(0.0).max(1.0).step(0.01).default_value(0.2)),
            canvas_bounds: Rc::new(Cell::new([0.0; 4])),
            init_error: None,
            tasks: Vec::new(),
        }
    }

    fn screen_edr() -> (f64, f64) {
        let Some(mtm) = MainThreadMarker::new() else {
            return (f64::NAN, f64::NAN);
        };
        let Some(screen) = NSScreen::mainScreen(mtm) else {
            return (f64::NAN, f64::NAN);
        };
        (
            screen.maximumExtendedDynamicRangeColorComponentValue(),
            screen.maximumPotentialExtendedDynamicRangeColorComponentValue(),
        )
    }

    fn ensure_init(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.surface.is_some() || self.init_error.is_some() {
            return;
        }
        println!("K INIT begin");
        let result: Result<(WindowCompositionSurface, CompositionSurfaceId, Rc<MetalView>)> = (|| {
            let comp = window.enable_window_composition()?;
            let surface = comp.create_native_surface()?;
            let id = surface.id();
            let handle = surface.platform_surface()?.platform_handle()?;
            let view_ptr = *handle
                .downcast::<usize>()
                .map_err(|_| anyhow::anyhow!("macOS platform_handle is not usize"))?;
            println!("K INIT surface_id={:?} nsview=0x{:x}", id, view_ptr);
            let metal = MetalView::attach(view_ptr as *mut NSView)?;
            Ok((surface, id, metal))
        })();

        match result {
            Ok((surface, id, metal)) => {
                let (max_edr, pot_edr) = Self::screen_edr();
                println!(
                    "K EDR screen_maximum_edr={:.3} screen_potential_edr={:.3}",
                    max_edr, pot_edr
                );
                self.surface = Some(surface);
                self.surface_id = Some(id);
                self.metal = Some(metal.clone());
                self.start_tasks(window, cx, metal);
                println!("K INIT ok");
            }
            Err(error) => {
                let msg = format!("{error:#}");
                println!("K INIT FAIL {msg}");
                self.init_error = Some(msg);
            }
        }
    }

    fn start_tasks(&mut self, window: &mut Window, cx: &mut Context<Self>, metal: Rc<MetalView>) {
        let executor = cx.background_executor().clone();
        let started = self.started;
        let static_after = env_f32("VIEWPORT_STATIC_AFTER", 26.0) as f64;
        let exec = executor.clone();
        let draw_task = cx.spawn_in(window, async move |weak, cx| {
            let mut last_log = Instant::now();
            let mut last_frames = 0u64;
            loop {
                exec.timer(Duration::from_millis(16)).await;
                let elapsed = started.elapsed().as_secs_f64();
                if elapsed >= static_after {
                    println!("K IDLE stop at t={elapsed:.2}s (viewport stopped, window stays up)");
                    break;
                }
                metal.draw();
                if last_log.elapsed() >= Duration::from_secs(2) {
                    let frames = metal.frames.get();
                    let (vx, vy, vw, vh, scale) = metal.view_frame();
                    let canvas = weak
                        .read_with(cx, |this, _| this.canvas_bounds.get())
                        .unwrap_or([0.0; 4]);
                    println!(
                        "K RATE frames={frames} (+{}) view_frame_points=({vx:.1},{vy:.1} {vw:.1}x{vh:.1}) scale={scale:.2} canvas_logical={canvas:?} t={elapsed:.2}s {}",
                        frames - last_frames,
                        metal.layer_geom()
                    );
                    last_frames = frames;
                    last_log = Instant::now();
                }
            }
        });
        let panel_exec = executor;
        let panel_task = cx.spawn_in(window, async move |weak, cx| {
            loop {
                panel_exec.timer(Duration::from_millis(250)).await;
                let elapsed = started.elapsed().as_secs_f64();
                if elapsed >= static_after {
                    break;
                }
                let toggled = weak
                    .update_in(cx, |this, window, cx| {
                        this.tick += 1;
                        let t = this.tick as f32;
                        this.value_a = 0.5 + 0.5 * (t * 0.09).sin();
                        this.value_b = 0.5 + 0.5 * (t * 0.05 + 1.7).cos();
                        let a = this.value_a;
                        let b = this.value_b;
                        let sa = this.slider_a.clone();
                        let sb = this.slider_b.clone();
                        sa.update(cx, |state, cx| state.set_value(a, window, cx));
                        sb.update(cx, |state, cx| state.set_value(b, window, cx));
                        this.overlay_open = ((elapsed / 2.5) as i64) % 2 == 1;
                        cx.notify();
                        this.overlay_open
                    })
                    .ok();
                if let Some(open) = toggled {
                    println!("K OVERLAY open={open} t={elapsed:.2}s tick={}", elapsed_tick(elapsed));
                }
            }
        });
        self.tasks.push(draw_task);
        self.tasks.push(panel_task);
    }

    fn panel(&self) -> impl IntoElement {
        div()
            .w(px(400.))
            .h_full()
            .flex()
            .flex_col()
            .gap_3()
            .p_4()
            .bg(rgb(0x1b1b21))
            .child(
                div()
                    .text_size(px(16.))
                    .text_color(rgb(0xffffff))
                    .child("gpui-kit panel (SDR)"),
            )
            .child(div().text_color(rgb(0x9aa0a6)).child(format!(
                "tick {}   t={:.2}s",
                self.tick,
                self.started.elapsed().as_secs_f32()
            )))
            .child(div().h(px(28.)).child(Slider::new(&self.slider_a)))
            .child(
                div()
                    .text_color(rgb(0xffffff))
                    .child(format!("slider A = {:.3}", self.value_a)),
            )
            .child(div().h(px(28.)).child(Slider::new(&self.slider_b)))
            .child(
                div()
                    .text_color(rgb(0xffffff))
                    .child(format!("slider B = {:.3}", self.value_b)),
            )
            .child(div().text_color(rgb(0x9aa0a6)).child(format!(
                "overlay auto-toggles every 2.5s (open={})",
                self.overlay_open
            )))
            .child(div().text_color(rgb(0x9aa0a6)).child(
                "viewport: native CAMetalLayer, rgba16Float, extended linear sRGB, EDR on",
            ))
    }
}

fn elapsed_tick(elapsed: f64) -> i64 {
    (elapsed * 4.0) as i64
}

impl Render for Proto {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        self.ensure_init(window, cx);

        let left = if let Some(surface) = self.surface.clone() {
            let logb = self.canvas_bounds.clone();
            canvas(
                move |bounds, window, _cx| {
                    if let Ok(ps) = surface.platform_surface() {
                        let dev = bounds.to_device_pixels(window.scale_factor());
                        if let Err(error) = ps.set_bounds(dev) {
                            println!("K SET_BOUNDS FAIL {error:#}");
                        }
                    }
                    logb.set([
                        bounds.origin.x.as_f32(),
                        bounds.origin.y.as_f32(),
                        bounds.size.width.as_f32(),
                        bounds.size.height.as_f32(),
                    ]);
                },
                |_, _, _, _| {},
            )
            .size_full()
            .into_any_element()
        } else {
            div()
                .size_full()
                .flex()
                .items_center()
                .justify_center()
                .text_color(rgb(0xff6666))
                .child(
                    self.init_error
                        .clone()
                        .unwrap_or_else(|| "initializing native composition surface...".into()),
                )
                .into_any_element()
        };

        let overlay = deferred(
            div()
                .absolute()
                .left(px(60.))
                .top(px(60.))
                .w(px(640.))
                .h(px(300.))
                .rounded(px(10.))
                .bg(rgb(0x2d2f3a))
                .border_1()
                .border_color(rgb(0x6b7280))
                .p_4()
                .flex()
                .flex_col()
                .gap_2()
                .child(
                    div()
                        .text_size(px(18.))
                        .text_color(rgb(0xffffff))
                        .child("Deferred popup menu (drawn above native content)"),
                )
                .child(div().text_color(rgb(0xd0d4dc)).child("Item 1 - Enable HDR viewport"))
                .child(div().text_color(rgb(0xd0d4dc)).child("Item 2 - Expose to ColorSync"))
                .child(div().text_color(rgb(0xd0d4dc)).child("Item 3 - Reset"))
                .child(div().text_color(rgb(0x9aa0a6)).child(format!(
                    "tick {} / overlay toggles every 2.5s",
                    self.tick
                ))),
        )
        .with_priority(10);

        div()
            .size_full()
            .flex()
            .flex_row()
            .bg(rgb(0x101014))
            .child(div().flex_1().h_full().overflow_hidden().child(left))
            .child(self.panel())
            .when(self.overlay_open, |this| this.child(overlay))
    }
}

fn main() {
    gpui_kit::application().run(|cx| {
        gpui_kit::init(cx);
        let bounds = Bounds {
            origin: point(px(60.), px(60.)),
            size: size(px(1200.), px(800.)),
        };
        let options = WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: None,
            focus: true,
            show: true,
            ..Default::default()
        };
        gpui_kit::open_window(options, cx, |window, cx| cx.new(|cx| Proto::new(window, cx)))
            .expect("open window");
        cx.activate(true);
        println!("K APP window=1200x800 layout=left:flex viewport, right:400 panel");
    });
}
