// Lab bench for the gpui-fast reconnaissance.
//
// One binary, one window, one mode per run. It is deliberately separate from
// src/main.rs so the darktable prototype and the two clean binaries in dist/
// keep measuring exactly what they measured before.
//
// modes (LAB_MODE):
//   text        12 pt mixed CJK/Latin sample, for a side-by-side visual check
//   list        100 000-row virtual list (gpui-base v_virtual_list)
//   surface     640x400 CVPixelBuffer updated by a timer, drawn with gpui::surface()
//   renderimage 640x400 RenderImage re-created by a timer, drawn with gpui::img()
//
// env:
//   LAB_TICK_MS   timer period for surface/renderimage (default 16)
//   LAB_ROWS      rows for list mode (default 100000)

use std::rc::Rc;
use std::sync::LazyLock;
use std::time::{Duration, Instant};

use gpui_kit::prelude::*;
use gpui_kit::*;

static T0: LazyLock<Instant> = LazyLock::new(Instant::now);

fn tt() -> f64 {
    T0.elapsed().as_secs_f64() * 1000.0
}

#[derive(Clone, Copy, PartialEq, Debug)]
enum Mode {
    Text,
    List,
    Surface,
    RenderImage,
}

fn mode_env() -> Mode {
    match std::env::var("LAB_MODE").ok().as_deref() {
        Some("list") => Mode::List,
        Some("surface") => Mode::Surface,
        Some("renderimage") => Mode::RenderImage,
        _ => Mode::Text,
    }
}

const PICTURE_W: usize = 640;
const PICTURE_H: usize = 400;

#[cfg(target_os = "macos")]
mod cv {
    use objc2_core_foundation::{CFDictionary, CFRetained, CFString};
    use objc2_core_video::{
        kCVPixelBufferIOSurfacePropertiesKey, kCVPixelFormatType_32BGRA, CVPixelBuffer,
        CVPixelBufferCreate, CVPixelBufferGetBaseAddress, CVPixelBufferGetBytesPerRow,
        CVPixelBufferLockBaseAddress, CVPixelBufferLockFlags, CVPixelBufferUnlockBaseAddress,
    };
    use std::ptr::NonNull;

    /// An IOSurface-backed BGRA pixel buffer, the kind `gpui::surface()` expects.
    pub struct Buffer {
        pub buffer: CFRetained<CVPixelBuffer>,
        pub width: usize,
        pub height: usize,
        pub nv12: bool,
    }

    impl Buffer {
        pub fn new(width: usize, height: usize) -> Option<Self> {
            use objc2_core_foundation::CFType;
            type Dict = CFDictionary<CFString, CFType>;
            let inner: CFRetained<Dict> = Dict::empty();
            let inner_cf: &CFType = inner.as_ref();
            let key: &CFString = unsafe { kCVPixelBufferIOSurfacePropertiesKey };
            let attrs: CFRetained<Dict> = Dict::from_slices(&[key], &[inner_cf]);
            // CFDictionary's default type parameters are Opaque; the CoreVideo
            // signature wants that shape. Same CFDictionary at runtime.
            let attrs_opaque: &CFDictionary =
                unsafe { &*(&*attrs as *const Dict as *const CFDictionary) };
            let mut out: *mut CVPixelBuffer = std::ptr::null_mut();
            let rc = unsafe {
                CVPixelBufferCreate(
                    None,
                    width,
                    height,
                    kCVPixelFormatType_32BGRA,
                    Some(attrs_opaque),
                    NonNull::new(&mut out).unwrap(),
                )
            };
            if rc != 0 || out.is_null() {
                eprintln!("CVPixelBufferCreate rc={rc}");
                return None;
            }
            let buffer = unsafe { CFRetained::from_raw(NonNull::new(out).unwrap()) };
            let has_surface = unsafe { objc2_core_video::CVPixelBufferGetIOSurface(&buffer) };
            eprintln!("BGRA_BUFFER iosurface={}", has_surface.is_some());
            Some(Self { buffer, width, height, nv12: false })
        }

        /// NV12 (420YpCbCr8BiPlanarFullRange), the only format gpui's surface
        /// renderer accepts on macOS. Luma carries the moving band, chroma is
        /// constant, so the picture is grey-scale but visibly changes.
        pub fn new_nv12(width: usize, height: usize) -> Option<Self> {
            use objc2_core_foundation::CFType;
            use objc2_core_video::kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
            type Dict = CFDictionary<CFString, CFType>;
            let inner: CFRetained<Dict> = Dict::empty();
            let inner_cf: &CFType = inner.as_ref();
            let key: &CFString = unsafe { kCVPixelBufferIOSurfacePropertiesKey };
            let attrs: CFRetained<Dict> = Dict::from_slices(&[key], &[inner_cf]);
            let attrs_opaque: &CFDictionary =
                unsafe { &*(&*attrs as *const Dict as *const CFDictionary) };
            let mut out: *mut CVPixelBuffer = std::ptr::null_mut();
            let rc = unsafe {
                CVPixelBufferCreate(
                    None,
                    width,
                    height,
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                    Some(attrs_opaque),
                    NonNull::new(&mut out).unwrap(),
                )
            };
            if rc != 0 || out.is_null() {
                eprintln!("CVPixelBufferCreate nv12 rc={rc}");
                return None;
            }
            let buffer = unsafe { CFRetained::from_raw(NonNull::new(out).unwrap()) };
            let has_surface = unsafe { objc2_core_video::CVPixelBufferGetIOSurface(&buffer) };
            eprintln!("NV12_BUFFER iosurface={}", has_surface.is_some());
            Some(Self { buffer, width, height, nv12: true })
        }

        pub fn fill_nv12(&self, luma: u8) {
            use objc2_core_video::{
                CVPixelBufferGetBaseAddressOfPlane, CVPixelBufferGetBytesPerRowOfPlane,
                CVPixelBufferGetHeightOfPlane, CVPixelBufferGetWidthOfPlane,
            };
            unsafe {
                let flags = CVPixelBufferLockFlags(0);
                let _ = CVPixelBufferLockBaseAddress(&self.buffer, flags);
                let y = CVPixelBufferGetBaseAddressOfPlane(&self.buffer, 0) as *mut u8;
                let ys = CVPixelBufferGetBytesPerRowOfPlane(&self.buffer, 0);
                let yh = CVPixelBufferGetHeightOfPlane(&self.buffer, 0);
                if !y.is_null() {
                    for row in 0..yh {
                        std::ptr::write_bytes(y.add(row * ys), luma, self.width);
                    }
                }
                let c = CVPixelBufferGetBaseAddressOfPlane(&self.buffer, 1) as *mut u8;
                let cs = CVPixelBufferGetBytesPerRowOfPlane(&self.buffer, 1);
                let ch = CVPixelBufferGetHeightOfPlane(&self.buffer, 1);
                let cw = CVPixelBufferGetWidthOfPlane(&self.buffer, 1);
                if !c.is_null() {
                    for row in 0..ch {
                        let p = c.add(row * cs);
                        for col in 0..cw {
                            p.add(col * 2).write(128);
                            p.add(col * 2 + 1).write(128);
                        }
                    }
                }
                let _ = CVPixelBufferUnlockBaseAddress(&self.buffer, flags);
            }
        }

        pub fn fill(&self, b: u8, g: u8, r: u8) {
            unsafe {
                let flags = CVPixelBufferLockFlags(0);
                let _ = CVPixelBufferLockBaseAddress(&self.buffer, flags);
                let base = CVPixelBufferGetBaseAddress(&self.buffer) as *mut u8;
                let stride = CVPixelBufferGetBytesPerRow(&self.buffer);
                if !base.is_null() {
                    for y in 0..self.height {
                        let row = base.add(y * stride);
                        for x in 0..self.width {
                            let p = row.add(x * 4);
                            p.write(b);
                            p.add(1).write(g);
                            p.add(2).write(r);
                            p.add(3).write(255);
                        }
                    }
                }
                let _ = CVPixelBufferUnlockBaseAddress(&self.buffer, flags);
            }
        }
    }
}

struct Lab {
    mode: Mode,
    renders: u64,
    ticks: u64,
    list_scroll: gpui_kit::base::VirtualListScrollHandle,
    rows: usize,
    row_sizes: Rc<Vec<Size<Pixels>>>,
    #[cfg(target_os = "macos")]
    buffer: Option<cv::Buffer>,
    render_image: Option<std::sync::Arc<RenderImage>>,
    value: f32,
    timer_started: bool,
}

impl Lab {
    fn new(mode: Mode, _window: &mut Window, cx: &mut Context<Self>) -> Self {
        let rows: usize = std::env::var("LAB_ROWS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(100_000);
        let row_sizes: Rc<Vec<Size<Pixels>>> =
            Rc::new((0..rows).map(|_| size(px(1100.), px(28.))).collect());
        #[cfg(target_os = "macos")]
        let nv12 = std::env::var("LAB_SURFACE_FORMAT").map(|v| v == "nv12").unwrap_or(false);
        let buffer = if mode == Mode::Surface {
            let made = if nv12 {
                cv::Buffer::new_nv12(PICTURE_W, PICTURE_H)
            } else {
                cv::Buffer::new(PICTURE_W, PICTURE_H)
            };
            match made {
                Some(b) => {
                    eprintln!("SURFACE_BUFFER ok {}x{}", b.width, b.height);
                    Some(b)
                }
                None => {
                    eprintln!("SURFACE_BUFFER failed");
                    None
                }
            }
        } else {
            None
        };
        let _ = cx;
        Self {
            mode,
            renders: 0,
            ticks: 0,
            list_scroll: gpui_kit::base::VirtualListScrollHandle::new(),
            rows,
            row_sizes,
            #[cfg(target_os = "macos")]
            buffer,
            render_image: None,
            value: 0.7,
            timer_started: false,
        }
    }

    fn start_timer(&mut self, cx: &mut Context<Self>) {
        if self.timer_started || !matches!(self.mode, Mode::Surface | Mode::RenderImage) {
            return;
        }
        if self.mode == Mode::Surface && self.buffer.is_none() {
            return;
        }
        self.timer_started = true;
        let ms: u64 = std::env::var("LAB_TICK_MS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(16);
        cx.spawn(async move |this, cx| {
            cx.background_executor()
                .timer(Duration::from_millis(500))
                .await;
            let _ = this.update(cx, |this, _| {
                eprintln!("TICK_START t={:.3} renders={}", tt(), this.renders);
            });
            for n in 0..600u32 {
                let ok = this.update(cx, |this, cx| {
                    this.ticks += 1;
                    let v = (n % 60) as f32 / 59.0;
                    this.value = v;
                    if this.mode == Mode::Surface {
                        #[cfg(target_os = "macos")]
                        if let Some(b) = &this.buffer {
                            if b.nv12 {
                                b.fill_nv12((16.0 + v * 200.0) as u8);
                            } else {
                                let r = (v * 255.0) as u8;
                                let g = ((1.0 - v) * 200.0) as u8;
                                b.fill(40, g, r);
                            }
                        }
                    } else {
                        let r = (v * 255.0) as u8;
                        let g = ((1.0 - v) * 200.0) as u8;
                        let mut buf = vec![0u8; PICTURE_W * PICTURE_H * 4];
                        for px4 in buf.chunks_exact_mut(4) {
                            px4[0] = 40;
                            px4[1] = g;
                            px4[2] = r;
                            px4[3] = 255;
                        }
                        let img = image::RgbaImage::from_raw(
                            PICTURE_W as u32,
                            PICTURE_H as u32,
                            buf,
                        )
                        .expect("image buffer");
                        this.render_image = Some(std::sync::Arc::new(RenderImage::new(vec![
                            image::Frame::new(img),
                        ])));
                    }
                    if n % 30 == 0 {
                        eprintln!(
                            "TICK n={} t={:.3} renders={} ticks={}",
                            n, tt(), this.renders, this.ticks
                        );
                    }
                    cx.notify();
                });
                if ok.is_err() {
                    break;
                }
                cx.background_executor()
                    .timer(Duration::from_millis(ms))
                    .await;
            }
            let _ = this.update(cx, |this, _| {
                eprintln!("TICK_END t={:.3} renders={} ticks={}", tt(), this.renders, this.ticks);
            });
        })
        .detach();
    }

    fn text_panel(&self) -> AnyElement {
        let line = |s: &str, family: Option<&'static str>, weight: FontWeight, size: f32| {
            let mut d = div()
                .h(px(22.))
                .flex()
                .items_center()
                .text_size(px(size))
                .text_color(rgb(0xf1f1f1))
                .child(s.to_string());
            if let Some(f) = family {
                d = d.font_family(f);
            }
            if weight != FontWeight::NORMAL {
                d = d.font_weight(weight);
            }
            d.into_any_element()
        };
        let mut col = div()
            .w(px(560.))
            .flex()
            .flex_col()
            .gap(px(0.))
            .child(line("曝光 +0.70 EV · 白平衡 5294 K · 锐化半径 25.0 px", None, FontWeight::NORMAL, 12.0))
            .child(line("曝光 +0.70 EV · 白平衡 5294 K · 锐化半径 25.0 px", Some("Helvetica Neue"), FontWeight::NORMAL, 12.0))
            .child(line("The quick brown fox jumps over the lazy dog 0123456789", None, FontWeight::NORMAL, 12.0))
            .child(line("汉化字体回退：永東國酬愛鬱靈鷹 昆曲京剧毛笔字", None, FontWeight::NORMAL, 12.0))
            .child(line("abcdefghijklmno · ABCDEFGHIJKLMNO · 0123456789", None, FontWeight::NORMAL, 12.0))
            .child(line("Weight Regular 12pt · 中文常规 12 点 · 间距测试", None, FontWeight::NORMAL, 12.0))
            .child(line("Weight Bold 12pt · 中文粗体 12 点 · 间距测试", None, FontWeight::BOLD, 12.0))
            .child(line("Menlo: il1|I O0o · 中文等宽回退测试", Some("Menlo"), FontWeight::NORMAL, 12.0));
        col = col.child(div().h(px(8.)).into_any_element());
        col = col.child(
            div()
                .text_size(px(12.))
                .text_color(rgb(0xc6c6c6))
                .child("12 pt / 2x backing store. The rows above are 22 pt high.")
                .into_any_element(),
        );
        div()
            .flex()
            .flex_col()
            .p(px(24.))
            .gap(px(6.))
            .child(col)
            .into_any_element()
    }

    fn list_panel(&self, cx: &mut Context<Self>) -> AnyElement {
        let rows = self.rows;
        let list = gpui_kit::base::v_virtual_list(
            cx.entity(),
            "big-list",
            self.row_sizes.clone(),
            move |_this, range: std::ops::Range<usize>, _window, _cx| {
                range
                    .map(|i| {
                        div()
                            .h(px(28.))
                            .w_full()
                            .px(px(10.))
                            .flex()
                            .items_center()
                            .gap(px(12.))
                            .when(i % 2 == 0, |d| d.bg(rgb(0x2b2b2b)))
                            .child(
                                div()
                                    .text_size(px(12.))
                                    .text_color(rgb(0xe6e6e6))
                                    .child(format!("Row {i:06} · sample entry · {}", i * 37 % 9973)),
                            )
                            .child(
                                div()
                                    .text_size(px(12.))
                                    .text_color(rgb(0x9a9a9a))
                                    .child(format!("{:.3}", i as f64 * 0.618)),
                            )
                            .into_any_element()
                    })
                    .collect::<Vec<_>>()
            },
        )
        .track_scroll(&self.list_scroll);
        let _ = rows;
        div()
            .size_full()
            .flex()
            .flex_col()
            .bg(rgb(0x1e1e1e))
            .child(
                div()
                    .h(px(28.))
                    .px(px(10.))
                    .flex()
                    .items_center()
                    .text_size(px(12.))
                    .text_color(rgb(0xffffff))
                    .bg(rgb(0x3a3a3a))
                    .child(format!("v_virtual_list · {} rows · 28 pt each", self.rows)),
            )
            .child(div().flex_1().min_h(px(0.)).child(list))
            .into_any_element()
    }

    fn picture_panel(&self) -> AnyElement {
        #[cfg(target_os = "macos")]
        if self.mode == Mode::Surface {
            if let Some(b) = &self.buffer {
                return div()
                    .size_full()
                    .flex()
                    .flex_col()
                    .items_center()
                    .justify_center()
                    .bg(rgb(0x202020))
                    .gap(px(12.))
                    .child(
                        div()
                            .w(px(PICTURE_W as f32))
                            .h(px(PICTURE_H as f32))
                            .child(surface(b.buffer.clone()).object_fit(ObjectFit::Fill)),
                    )
                    .child(
                        div()
                            .text_size(px(14.))
                            .text_color(rgb(0xffffff))
                            .child(format!("surface() · ticks {} · renders {}", self.ticks, self.renders)),
                    )
                    .into_any_element();
            }
            return div()
                .size_full()
                .flex()
                .items_center()
                .justify_center()
                .bg(rgb(0x202020))
                .text_color(rgb(0xff5555))
                .child("SURFACE_BUFFER failed; see stderr")
                .into_any_element();
        }
        let element: AnyElement = match &self.render_image {
            Some(arc_img) => img(arc_img.clone())
                .w(px(PICTURE_W as f32))
                .h(px(PICTURE_H as f32))
                .into_any_element(),
            None => div()
                .w(px(PICTURE_W as f32))
                .h(px(PICTURE_H as f32))
                .bg(rgb(0x303030))
                .into_any_element(),
        };
        div()
            .size_full()
            .flex()
            .flex_col()
            .items_center()
            .justify_center()
            .bg(rgb(0x202020))
            .gap(px(12.))
            .child(element)
            .child(
                div()
                    .text_size(px(14.))
                    .text_color(rgb(0xffffff))
                    .child(format!("img(RenderImage) · ticks {} · renders {}", self.ticks, self.renders)),
            )
            .into_any_element()
    }
}

impl Render for Lab {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        self.renders += 1;
        self.start_timer(cx);
        if self.renders == 1 {
            eprintln!(
                "LAB_LAYOUT mode={:?} window=1200x800 origin=40,40 content_pad=24 first_render_t={:.3}",
                self.mode, tt()
            );
        }
        let body: AnyElement = match self.mode {
            Mode::Text => self.text_panel(),
            Mode::List => self.list_panel(cx),
            Mode::Surface | Mode::RenderImage => self.picture_panel(),
        };
        div()
            .size_full()
            .bg(rgb(0x191919))
            .text_color(rgb(0xf1f1f1))
            .font_family("Helvetica Neue")
            .child(body)
    }
}

fn main() {
    let mode = mode_env();
    gpui_kit::application().run(move |cx| {
        gpui_kit::init(cx);
        let bounds = Bounds {
            origin: point(px(40.), px(40.)),
            size: size(px(1200.), px(800.)),
        };
        let options = WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: None,
            focus: true,
            show: true,
            ..Default::default()
        };
        gpui_kit::open_window(options, cx, move |window, cx| {
            cx.new(|cx| Lab::new(mode, window, cx))
        })
        .expect("open window");
        cx.activate(true);
        println!("LAB_READY mode={mode:?} pid={}", std::process::id());
    });
}
