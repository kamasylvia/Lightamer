// SPDX-License-Identifier: GPL-3.0-or-later
//! `lightamer-gpui`: interface window with the owned native viewport.
//!
//! Left is the viewport area carried by a framework `canvas`; the canvas hands
//! its laid-out rectangle to the native surface each paint, and `lightamer-apple`
//! draws the test pattern on its own native layer behind one integer seam.
//! Right is a fixed-width panel with two sliders and text.
//!
//! Input has two measured paths (default framework callback; `--input-path b`
//! selects the native subclass path): both land as [`ViewportInput`], one
//! `INPUT` log line each, counted for the probe. No input issues commands in
//! this wave. The draw loop owns its own 16ms rhythm and never notifies the
//! framework per frame.
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

use gpui_kit::component::slider::{Slider, SliderState};
use gpui_kit::prelude::*;
use gpui_kit::{
    Bounds, DispatchEventResult, Entity, PlatformInput, Task, Window, WindowBounds,
    WindowCompositionSurface, WindowOptions, canvas, div, point, px, rgb, size,
};
use lightamer_apple::{Backend, ViewportHandle, ViewportRect, capabilities};
use lightamer_engine::command_specs;
use lightamer_gpui::{ViewportInput, convert_native_input, convert_platform_input};
use std::cell::Cell;
use std::rc::Rc;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

/// Which measured input path delivers pointer events.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum InputPath {
    /// Framework surface callback (`on_input`).
    Framework,
    /// Native view subclass in `lightamer-apple`.
    Native,
}

impl InputPath {
    /// Short log word (`a`/`b`).
    const fn word(self) -> &'static str {
        match self {
            Self::Framework => "a",
            Self::Native => "b",
        }
    }
}

/// Parsed command line.
struct Args {
    path: InputPath,
    quit_after: Option<Duration>,
    panel_tick: Duration,
}

/// Parses `--input-path a|b`, `--quit-after-secs N`, `--panel-tick-ms N`.
fn parse_args() -> Result<Args, String> {
    let mut path = InputPath::Framework;
    let mut quit_after: Option<Duration> = None;
    let mut panel_tick = Duration::from_millis(250);
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--input-path" => {
                let value = args.next().ok_or("--input-path needs a|b")?;
                path = match value.as_str() {
                    "a" => InputPath::Framework,
                    "b" => InputPath::Native,
                    _ => return Err(format!("--input-path wants a|b, got {value}")),
                };
            }
            "--quit-after-secs" => {
                let value = args.next().ok_or("--quit-after-secs needs seconds")?;
                let secs: f64 = value.parse().map_err(|_| format!("bad seconds: {value}"))?;
                if !secs.is_finite() || secs < 0.0 {
                    return Err(format!("bad seconds: {value}"));
                }
                quit_after = Some(Duration::from_secs_f64(secs));
            }
            "--panel-tick-ms" => {
                let value = args.next().ok_or("--panel-tick-ms needs milliseconds")?;
                let ms: u64 = value.parse().map_err(|_| format!("bad millis: {value}"))?;
                panel_tick = Duration::from_millis(ms.max(1));
            }
            "-h" | "--help" => {
                return Err(
                    "usage: lightamer-gpui [--input-path a|b] [--quit-after-secs N] [--panel-tick-ms N]"
                        .to_string(),
                );
            }
            other => return Err(format!("unknown arg: {other}")),
        }
    }
    Ok(Args {
        path,
        quit_after,
        panel_tick,
    })
}

/// One `INPUT` log line plus the shared probe counter.
fn log_input(seq: u64, path: InputPath, input: &ViewportInput) {
    let button = input.button.map_or("none".to_string(), |b| b.to_string());
    let mods = input.modifiers;
    let word = |on: bool, letter: char| if on { letter } else { '-' };
    println!(
        "INPUT seq={seq} path={} kind={} x={:.1} y={:.1} button={button} mods={}{}{}{} ts={:.3} dx={:.1} dy={:.1}",
        path.word(),
        input.kind.word(),
        input.x,
        input.y,
        word(mods.shift, 's'),
        word(mods.control, 'c'),
        word(mods.option, 'o'),
        word(mods.command, 'm'),
        input.timestamp_secs,
        input.scroll_dx,
        input.scroll_dy,
    );
}

struct ViewportApp {
    surface: Option<WindowCompositionSurface>,
    viewport: Option<Rc<ViewportHandle>>,
    path: InputPath,
    started: Instant,
    quit_after: Option<Duration>,
    panel_tick: Duration,
    tick: u64,
    value_a: f32,
    value_b: f32,
    slider_a: Entity<SliderState>,
    slider_b: Entity<SliderState>,
    canvas_rect: Rc<Cell<[f64; 4]>>,
    input_count: Arc<AtomicU64>,
    init_error: Option<String>,
    tasks: Vec<Task<()>>,
}

impl ViewportApp {
    fn new(
        path: InputPath,
        quit_after: Option<Duration>,
        panel_tick: Duration,
        cx: &mut Context<Self>,
    ) -> Self {
        Self {
            surface: None,
            viewport: None,
            path,
            started: Instant::now(),
            quit_after,
            panel_tick,
            tick: 0,
            value_a: 0.7,
            value_b: 0.2,
            slider_a: cx.new(|_| {
                SliderState::new()
                    .min(0.0)
                    .max(1.0)
                    .step(0.01)
                    .default_value(0.7)
            }),
            slider_b: cx.new(|_| {
                SliderState::new()
                    .min(0.0)
                    .max(1.0)
                    .step(0.01)
                    .default_value(0.2)
            }),
            canvas_rect: Rc::new(Cell::new([0.0; 4])),
            input_count: Arc::new(AtomicU64::new(0)),
            init_error: None,
            tasks: Vec::new(),
        }
    }

    /// Attaches the native surface and viewport once; on failure records text
    /// for the placeholder instead of retrying every paint.
    fn ensure_init(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.viewport.is_some() || self.init_error.is_some() {
            return;
        }
        println!(
            "APP init path={} engine_commands={}",
            self.path.word(),
            command_specs().len()
        );
        match Self::attach(
            window,
            self.path,
            Rc::clone(&self.canvas_rect),
            &self.input_count,
            self.started,
        ) {
            Ok((surface, viewport)) => {
                self.surface = Some(surface);
                self.viewport = Some(Rc::clone(&viewport));
                self.start_tasks(window, cx, &viewport);
                println!(
                    "APP tasks={} input_path={}",
                    self.tasks.len(),
                    self.path.word()
                );
                println!("APP init ok");
            }
            Err(message) => {
                println!("APP init FAIL {message}");
                self.init_error = Some(message);
            }
        }
    }

    /// Creates the native surface, swaps in our viewport, and wires input.
    /// The only thing crossing into `lightamer-apple` is one integer handle.
    fn attach(
        window: &mut Window,
        path: InputPath,
        canvas_rect: Rc<Cell<[f64; 4]>>,
        input_count: &Arc<AtomicU64>,
        started: Instant,
    ) -> Result<(WindowCompositionSurface, Rc<ViewportHandle>), String> {
        if capabilities().backend != Backend::MacOs {
            return Err("native viewport unavailable on this machine".to_string());
        }
        let composition = window
            .enable_window_composition()
            .map_err(|error| format!("composition: {error:#}"))?;
        let surface = composition
            .create_native_surface()
            .map_err(|error| format!("surface: {error:#}"))?;
        let id = surface.id();
        let boxed = surface
            .platform_surface()
            .map_err(|error| format!("platform surface: {error:#}"))?
            .platform_handle()
            .map_err(|error| format!("platform handle: {error:#}"))?;
        let raw = boxed
            .downcast::<usize>()
            .map_err(|_| "platform handle is not an integer".to_string())?;
        // Initial rectangle only; pixels follow the live laid-out view.
        let rect = ViewportRect {
            x: 0.0,
            y: 0.0,
            width: 800.0,
            height: 800.0,
        };
        let viewport = match path {
            InputPath::Framework => {
                lightamer_apple::attach_viewport(*raw, rect).map_err(|error| error.to_string())?
            }
            InputPath::Native => {
                let counter = Arc::clone(input_count);
                let sink = Box::new(move |event: lightamer_apple::NativePointerEvent| {
                    let input = convert_native_input(&event);
                    let seq = counter.fetch_add(1, Ordering::Relaxed);
                    log_input(seq, InputPath::Native, &input);
                });
                lightamer_apple::attach_viewport_with_input(*raw, rect, sink)
                    .map_err(|error| error.to_string())?
            }
        };
        if path == InputPath::Framework {
            let counter = Arc::clone(input_count);
            composition
                .on_input(id, move |event: &PlatformInput| {
                    let rect = canvas_rect.get();
                    let stamp = started.elapsed().as_secs_f64();
                    if let Some(input) = convert_platform_input(event, (rect[0], rect[1]), stamp) {
                        let seq = counter.fetch_add(1, Ordering::Relaxed);
                        log_input(seq, InputPath::Framework, &input);
                    }
                    DispatchEventResult::default()
                })
                .map_err(|error| format!("input callback: {error:#}"))?;
        }
        let raw_usize: usize = *raw;
        println!("APP surface id={id:?} handle=0x{raw_usize:x}");
        Ok((surface, Rc::new(viewport)))
    }

    /// Starts the draw loop (own 16ms rhythm, no framework notify per frame)
    /// and the slower panel tick.
    fn start_tasks(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
        viewport: &Rc<ViewportHandle>,
    ) {
        let executor = cx.background_executor().clone();
        let started = self.started;
        let quit_after = self.quit_after;
        let ticker = executor.clone();
        let worker = Rc::clone(viewport);
        let draw = cx.spawn_in(window, async move |weak, cx| {
            let mut frame: u64 = 0;
            loop {
                ticker.timer(Duration::from_millis(16)).await;
                if let Some(limit) = quit_after
                    && started.elapsed() >= limit
                {
                    println!("APP quit t={:.1}s", started.elapsed().as_secs_f64());
                    let _ = cx.update(|_, cx| cx.quit());
                    break;
                }
                match worker.draw_frame(frame) {
                    Ok(report) => {
                        if let Some(samples) = report.samples {
                            println!("APP readback frame={frame} samples={samples:?}");
                        }
                        if frame.is_multiple_of(120) {
                            match worker.geometry() {
                                Ok(geom) => {
                                    let canvas = weak
                                        .read_with(cx, |app, _| app.canvas_rect.get())
                                        .unwrap_or([0.0; 4]);
                                    println!(
                                        "GEOM frame={frame} canvas=[{:.1} {:.1} {:.1} {:.1}] view=({:.1},{:.1} {:.1}x{:.1}) layer=({:.1}x{:.1}) drawable={}x{} scale={:.2} float16={} edr={} device={}",
                                        canvas[0],
                                        canvas[1],
                                        canvas[2],
                                        canvas[3],
                                        geom.view_x,
                                        geom.view_y,
                                        geom.view_w,
                                        geom.view_h,
                                        geom.layer_w,
                                        geom.layer_h,
                                        geom.drawable_w,
                                        geom.drawable_h,
                                        geom.scale,
                                        geom.float16,
                                        geom.edr,
                                        geom.device_name,
                                    );
                                }
                                Err(error) => println!("APP geom FAIL {error}"),
                            }
                        }
                    }
                    Err(error) => println!("APP draw FAIL frame={frame} {error}"),
                }
                frame = frame.wrapping_add(1);
            }
        });
        let panel_tick = self.panel_tick;
        let panel = cx.spawn_in(window, async move |weak, cx| {
            loop {
                executor.timer(panel_tick).await;
                let changed = weak
                    .update_in(cx, |app, window, cx| {
                        app.tick = app.tick.wrapping_add(1);
                        let step = f32::from(u16::try_from(app.tick % 1000).unwrap_or(0));
                        app.value_a = 0.5 + 0.5 * (step * 0.09).sin();
                        app.value_b = 0.5 + 0.5 * (step * 0.05 + 1.7).cos();
                        let (a, b) = (app.value_a, app.value_b);
                        let slider_a = app.slider_a.clone();
                        let slider_b = app.slider_b.clone();
                        slider_a.update(cx, |state, cx| state.set_value(a, window, cx));
                        slider_b.update(cx, |state, cx| state.set_value(b, window, cx));
                        cx.notify();
                    })
                    .is_ok();
                if !changed {
                    break;
                }
            }
        });
        self.tasks.push(draw);
        self.tasks.push(panel);
    }

    fn panel(&self) -> impl IntoElement {
        div()
            .w(px(400.))
            .h_full()
            .flex()
            .flex_col()
            .gap_3()
            .p_4()
            .bg(rgb(0x1b_1b21))
            .child(
                div()
                    .text_size(px(16.))
                    .text_color(rgb(0xff_ffff))
                    .child("develop panel (framework)"),
            )
            .child(div().text_color(rgb(0x9a_a0a6)).child(format!(
                "tick {} t={:.2}s",
                self.tick,
                self.started.elapsed().as_secs_f32()
            )))
            .child(div().h(px(28.)).child(Slider::new(&self.slider_a)))
            .child(
                div()
                    .text_color(rgb(0xff_ffff))
                    .child(format!("slider A = {:.3}", self.value_a)),
            )
            .child(div().h(px(28.)).child(Slider::new(&self.slider_b)))
            .child(
                div()
                    .text_color(rgb(0xff_ffff))
                    .child(format!("slider B = {:.3}", self.value_b)),
            )
            .child(
                div()
                    .text_color(rgb(0x9a_a0a6))
                    .child("viewport: owned layer behind one integer seam"),
            )
    }
}

impl Render for ViewportApp {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        self.ensure_init(window, cx);

        let left = if let Some(surface) = self.surface.clone() {
            let seen = Rc::clone(&self.canvas_rect);
            let viewport = self.viewport.clone();
            canvas(
                move |bounds, window, _cx| {
                    if let Ok(platform) = surface.platform_surface() {
                        let device = bounds.to_device_pixels(window.scale_factor());
                        if let Err(error) = platform.set_bounds(device) {
                            println!("APP set-bounds FAIL {error:#}");
                        }
                    }
                    let rect = ViewportRect {
                        x: f64::from(bounds.origin.x.as_f32()),
                        y: f64::from(bounds.origin.y.as_f32()),
                        width: f64::from(bounds.size.width.as_f32()),
                        height: f64::from(bounds.size.height.as_f32()),
                    };
                    seen.set([rect.x, rect.y, rect.width, rect.height]);
                    if let Some(viewport) = viewport.as_ref() {
                        viewport.set_rect(rect);
                    }
                },
                |_, (), _, _| {},
            )
            .size_full()
            .into_any_element()
        } else {
            div()
                .size_full()
                .flex()
                .items_center()
                .justify_center()
                .text_color(rgb(0xff_6666))
                .child(
                    self.init_error
                        .clone()
                        .unwrap_or_else(|| "initializing native viewport...".to_string()),
                )
                .into_any_element()
        };

        div()
            .size_full()
            .flex()
            .flex_row()
            .bg(rgb(0x10_1014))
            .child(div().flex_1().h_full().overflow_hidden().child(left))
            .child(self.panel())
    }
}

fn main() {
    let args = match parse_args() {
        Ok(args) => args,
        Err(message) => {
            eprintln!("{message}");
            std::process::exit(2);
        }
    };
    gpui_kit::application().run(move |cx| {
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
        let path = args.path;
        let quit_after = args.quit_after;
        let panel_tick = args.panel_tick;
        if gpui_kit::open_window(options, cx, |_, cx| {
            cx.new(|cx| ViewportApp::new(path, quit_after, panel_tick, cx))
        })
        .is_err()
        {
            eprintln!("lightamer-gpui: open window failed");
            std::process::exit(1);
        }
        cx.activate(true);
        println!("APP window=1200x800 layout=left:flex viewport, right:400 panel");
    });
}
