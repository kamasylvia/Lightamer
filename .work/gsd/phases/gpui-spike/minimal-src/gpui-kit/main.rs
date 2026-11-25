// Bisect harness for the gpui-spike scroll/drag repaint problem.
//
// The original minimal reproduction (M1..C2) proved the plain writing works.
// This build adds the prototype's geometry/drawing arms so each suspect can be
// added one at a time:
//
//   M1  plain div width (timer)                 offset 600
//   M2  canvas quad width (timer)               offset 600
//   E1  canvas dt-style slider (drag)           offset 600
//   E2  canvas dt-style slider (timer)          offset 600
//   E4  div dt-style slider (drag)              offset 600
//   C1  M1 at offset 0
//
// env:
//   MINIMAL_CASE   M1|M2|E1|E2|E4|C1
//   MINIMAL_SCROLL set (default) | none      none => the probe wheel-scrolls
//   MINIMAL_SUSPECT comma list: S2 (row+root mouse handlers on every row),
//                  S3 (flex-sized scroll container with 30px bars above),
//                  S5 (TextInput + track_focus + on_key_down),
//                  S7 (render reads scroll offset into a Cell + overlay tail)
//   MINIMAL_ROWS   default 80

use std::cell::Cell;
use std::rc::Rc;
use std::sync::LazyLock;
use std::time::Duration;

use gpui_kit::component::input::Input;
use gpui_kit::component::input::InputState;
use gpui_kit::component::theme::{Theme, ThemeMode};
use gpui_kit::prelude::*;
use gpui_kit::*;

#[repr(C)]
struct MachTimebaseInfo {
    numer: u32,
    denom: u32,
}

unsafe extern "C" {
    fn mach_absolute_time() -> u64;
    fn mach_timebase_info(info: *mut MachTimebaseInfo) -> i32;
}

static HOST_SCALE: LazyLock<f64> = LazyLock::new(|| {
    let mut tb = MachTimebaseInfo { numer: 0, denom: 0 };
    unsafe { mach_timebase_info(&mut tb) };
    tb.numer as f64 / tb.denom as f64 / 1e9
});

fn host_seconds() -> f64 {
    unsafe { mach_absolute_time() as f64 * *HOST_SCALE }
}

fn suspect(s: &str) -> bool {
    std::env::var("MINIMAL_SUSPECT")
        .map(|v| v.split(',').any(|x| x.trim() == s))
        .unwrap_or(false)
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Case {
    M1,
    M2,
    E1,
    E2,
    E4,
    C1,
}

impl Case {
    fn from_env() -> Self {
        match std::env::var("MINIMAL_CASE").ok().as_deref() {
            Some("M2") => Case::M2,
            Some("E1") => Case::E1,
            Some("E2") => Case::E2,
            Some("E4") => Case::E4,
            Some("C1") => Case::C1,
            _ => Case::M1,
        }
    }

    fn name(self) -> &'static str {
        match self {
            Case::M1 => "M1",
            Case::M2 => "M2",
            Case::E1 => "E1",
            Case::E2 => "E2",
            Case::E4 => "E4",
            Case::C1 => "C1",
        }
    }

    fn drag_driven(self) -> bool {
        matches!(self, Case::E1 | Case::E4)
    }

    fn scroll_offset(self) -> f32 {
        std::env::var("MINIMAL_OFFSET")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(if self == Case::C1 { 0.0 } else { 600.0 })
    }

    fn target_row(self) -> usize {
        if self == Case::C1 { 1 } else { 20 }
    }
}

struct Drag {
    start_x: f32,
    start_value: f32,
    width: f32,
    moved: bool,
}

struct Minimal {
    case: Case,
    value: f32,
    renders: u64,
    scroll: ScrollHandle,
    drag: Option<Drag>,
    mm: u64,
    scroll_reported: Cell<f32>,
    search: Entity<InputState>,
    editor_focus: FocusHandle,
}

impl Minimal {
    fn new(case: Case, window: &mut Window, cx: &mut Context<Self>) -> Self {
        let search = cx.new(|cx| InputState::new(window, cx).placeholder("search"));
        let editor_focus = cx.focus_handle();

        if std::env::var("MINIMAL_SCROLL").ok().as_deref() != Some("none") {
            let offset = case.scroll_offset();
            cx.spawn_in(window, async move |this, mut cx| {
                cx.background_executor()
                    .timer(Duration::from_millis(200))
                    .await;
                let _ = this.update_in(cx, |this, _window, cx| {
                    this.scroll.set_offset(point(px(0.), px(-offset)));
                    cx.notify();
                    eprintln!(
                        "SCROLL_SET t={:.6} requested={:.1} offset={:.1} max={:.1}",
                        host_seconds(),
                        offset,
                        this.scroll.offset().y / px(1.0),
                        this.scroll.max_offset().y / px(1.0),
                    );
                });
            })
            .detach();
        }

        // 2 s after the window opens: 40 updates, one every 16 ms.
        cx.spawn_in(window, async move |this, mut cx| {
            cx.background_executor()
                .timer(Duration::from_millis(2000))
                .await;
            let _ = this.update_in(cx, |this, _window, _cx| {
                eprintln!(
                    "TICK_START t={:.6} renders={} pid={}",
                    host_seconds(),
                    this.renders,
                    std::process::id()
                );
            });
            for n in 0..40u32 {
                let value = n as f32 / 39.0;
                let _ = this.update_in(cx, move |this, _window, cx| {
                    this.value = value;
                    eprintln!(
                        "TICK n={} t={:.6} renders={} value={:.4}",
                        n,
                        host_seconds(),
                        this.renders,
                        value
                    );
                    cx.notify();
                });
                if n < 39 {
                    cx.background_executor()
                        .timer(Duration::from_millis(16))
                        .await;
                }
            }
            let _ = this.update_in(cx, |this, _window, _cx| {
                eprintln!("TICK_END t={:.6} renders={}", host_seconds(), this.renders);
            });
        })
        .detach();

        Self {
            case,
            value: 0.05,
            renders: 0,
            scroll: ScrollHandle::new(),
            drag: None,
            mm: 0,
            scroll_reported: Cell::new(-1.0),
            search,
            editor_focus,
        }
    }

    fn on_mouse_down(
        &mut self,
        ev: &MouseDownEvent,
        bounds: Bounds<Pixels>,
        _window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let width = bounds.size.width / px(1.0);
        if width <= 0.0 {
            return;
        }
        let local = (ev.position.x - bounds.origin.x) / px(1.0);
        let frac = (local / width).clamp(0.0, 1.0);
        self.value = frac;
        self.drag = Some(Drag {
            start_x: ev.position.x / px(1.0),
            start_value: frac,
            width,
            moved: false,
        });
        self.mm = 0;
        eprintln!(
            "SLIDER_DOWN t={:.6} bounds=({:.1},{:.1} {:.1}x{:.1}) pos={:.1},{:.1} f={:.4}",
            host_seconds(),
            bounds.origin.x / px(1.0),
            bounds.origin.y / px(1.0),
            bounds.size.width / px(1.0),
            bounds.size.height / px(1.0),
            ev.position.x / px(1.0),
            ev.position.y / px(1.0),
            frac
        );
        cx.notify();
    }

    fn on_mouse_move(&mut self, ev: &MouseMoveEvent, _window: &mut Window, cx: &mut Context<Self>) {
        self.mm += 1;
        let Some(d) = &self.drag else { return };
        let dx = ev.position.x / px(1.0) - d.start_x;
        let frac = (d.start_value + dx / d.width.max(1.0)).clamp(0.0, 1.0);
        self.value = frac;
        if let Some(d) = &mut self.drag {
            d.moved = true;
        }
        cx.notify();
    }

    fn on_mouse_up(&mut self, _ev: &MouseUpEvent, _window: &mut Window, cx: &mut Context<Self>) {
        if let Some(d) = self.drag.take() {
            eprintln!(
                "DRAG_SUMMARY t={:.6} mm={} moved={} value={:.4}",
                host_seconds(),
                self.mm,
                d.moved,
                self.value
            );
            cx.notify();
        }
    }

    fn control(&self, cx: &mut Context<Self>) -> AnyElement {
        let value = self.value;
        let frac = value.clamp(0.0, 1.0);
        match self.case {
            Case::M1 | Case::C1 => div()
                .h(px(22.))
                .w(relative(0.1 + 0.8 * frac))
                .bg(rgb(0x3b82f6))
                .into_any_element(),
            Case::M2 => div()
                .h(px(22.))
                .w_full()
                .child(
                    canvas(
                        |bounds, _, _| bounds,
                        move |bounds, _, window, _cx| {
                            let bar =
                                Bounds::new(bounds.origin, size(bounds.size.width * frac, px(20.)));
                            window.paint_quad(fill(bar, rgb(0x3b82f6)));
                        },
                    )
                    .size_full(),
                )
                .into_any_element(),
            Case::E1 | Case::E2 | Case::E4 if std::env::var("MINIMAL_ARM").ok().as_deref().is_some() => {
                let arm = std::env::var("MINIMAL_ARM").unwrap();
                let f = frac;
                let one = move |b: Bounds<Pixels>, _: Bounds<Pixels>, w: &mut Window, _: &mut App| {
                    let bar = Bounds::new(b.origin, size(b.size.width * f, px(7.)));
                    w.paint_quad(fill(bar, rgb(0x3b82f6)));
                };
                match arm.as_str() {
                    "m2" => div()
                        .h(px(22.))
                        .w_full()
                        .child(
                            canvas(|b, _, _| b, move |b, _, w, _| {
                                let bar = Bounds::new(b.origin, size(b.size.width * f, px(20.)));
                                w.paint_quad(fill(bar, rgb(0x3b82f6)));
                            })
                            .size_full(),
                        )
                        .into_any_element(),
                    "m2rel" => div()
                        .h(px(22.))
                        .w_full()
                        .relative()
                        .child(
                            canvas(|b, _, _| b, move |b, _, w, _| {
                                let bar = Bounds::new(b.origin, size(b.size.width * f, px(20.)));
                                w.paint_quad(fill(bar, rgb(0x3b82f6)));
                            })
                            .absolute()
                            .size_full(),
                        )
                        .into_any_element(),
                    "thin1" => div()
                        .w(px(300.))
                        .h(px(12.))
                        .relative()
                        .child(
                            canvas(|b, _, _| b, one)
                                .absolute()
                                .size_full(),
                        )
                        .into_any_element(),
                    _ => div().into_any_element(),
                }
            }
            Case::E1 | Case::E2 | Case::E4 => {
                let cell = Rc::new(Cell::new(Bounds::default()));
                let c = cell.clone();
                if self.case == Case::E4 {
                    // div dt-style: absolute fill + triangle glyph
                    let row = div()
                        .w(px(300.))
                        .h(px(12.))
                        .relative()
                        .child(
                            canvas(move |b, _, _| c.set(b), |_, _, _, _| {})
                                .absolute()
                                .size_full(),
                        )
                        .child(
                            div()
                                .absolute()
                                .left(px(0.))
                                .top(px(3.))
                                .w_full()
                                .h(px(7.))
                                .bg(rgb(0x4b4b4b)),
                        )
                        .child(
                            div()
                                .absolute()
                                .left(px(0.))
                                .top(px(3.))
                                .w(relative(frac))
                                .h(px(7.))
                                .bg(rgb(0xaeaeae)),
                        )
                        .child(
                            div()
                                .absolute()
                                .left(relative(frac))
                                .top(px(1.))
                                .ml(px(-4.))
                                .text_size(px(9.))
                                .text_color(rgb(0xf2f2f2))
                                .child("▼"),
                        );
                    let c2 = cell.clone();
                    row.on_mouse_down(MouseButton::Left, cx.listener(move |this, ev, window, cx| {
                        this.on_mouse_down(ev, c2.get(), window, cx);
                    }))
                    .into_any_element()
                } else {
                    // canvas dt-style: track quad + fill quad + PathBuilder triangle
                    let draw = std::env::var("MINIMAL_DRAW").unwrap_or_else(|_| "full".into());
                    let d = draw.clone();
                    let cv = canvas(
                        move |b, _, _| c.set(b),
                        move |b, _, window, _cx| {
                            if std::env::var("MINIMAL_LOG").map(|v| v == "1").unwrap_or(false) {
                                eprintln!("CV_PAINT t={:.6} frac={:.4} y={:.1} w={:.1}", host_seconds(), frac, b.origin.y / px(1.0), b.size.width / px(1.0));
                            }
                            let bar = Bounds::new(
                                point(b.origin.x, b.origin.y + px(3.)),
                                size(b.size.width, px(7.)),
                            );
                            if d != "pathonly" {
                                window.paint_quad(fill(bar, rgb(0x4b4b4b)));
                                let fillw = b.size.width * frac;
                                window.paint_quad(fill(
                                    Bounds::new(bar.origin, size(fillw, px(7.))),
                                    rgb(0xaeaeae),
                                ));
                            }
                            if d != "quads" {
                                let fillw = b.size.width * frac;
                                let x = b.origin.x + fillw;
                                let mut path = PathBuilder::fill();
                                path.move_to(point(x - px(4.), b.origin.y + px(2.)));
                                path.line_to(point(x + px(4.), b.origin.y + px(2.)));
                                path.line_to(point(x, b.origin.y + px(8.)));
                                path.close();
                                if let Ok(p) = path.build() {
                                    window.paint_path(p, rgb(0xf2f2f2));
                                }
                            }
                        },
                    );
                    let cv = if draw == "flow" {
                        cv.w(px(300.)).h(px(12.))
                    } else {
                        cv.absolute().size_full()
                    };
                    let row = div().w(px(300.)).h(px(12.)).relative().child(cv);
                    let c2 = cell.clone();
                    let row = if std::env::var("MINIMAL_NODOWN").map(|v| v == "1").unwrap_or(false) {
                        row
                    } else {
                        row.on_mouse_down(MouseButton::Left, cx.listener(move |this, ev, window, cx| {
                            this.on_mouse_down(ev, c2.get(), window, cx);
                        }))
                    };
                    row.into_any_element()
                }
            }
        }
    }

    fn make_row(&self, i: usize, target: usize, cx: &mut Context<Self>) -> AnyElement {
        let mut row = div()
            .h(px(40.))
            .w_full()
            .flex()
            .flex_row()
            .items_center()
            .gap(px(8.))
            .px(px(8.))
            .child(
                div()
                    .w(px(52.))
                    .text_size(px(13.))
                    .text_color(rgb(0xb0b0b8))
                    .child(format!("row {i:02}")),
            );
        if suspect("S2") {
            let mut srow = row.id(("mrow", i)).on_mouse_down(
                MouseButton::Left,
                cx.listener(|_this, _ev: &MouseDownEvent, _, cx| cx.notify()),
            );
            if i == target {
                srow = srow.child(self.control(cx));
            }
            return srow.into_any_element();
        }
        if i == target {
            row = row.child(self.control(cx));
        }
        row.into_any_element()
    }
}

impl Render for Minimal {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        self.renders += 1;
        let case = self.case;
        let rows_n: usize = std::env::var("MINIMAL_ROWS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(80);
        let target = case.target_row();

        if suspect("S7") {
            let off = -(self.scroll.offset().y / px(1.0));
            if (off - self.scroll_reported.get()).abs() >= 0.5 {
                self.scroll_reported.set(off);
                eprintln!(
                    "SCROLL_OFFSET y={:.1} max={:.1}",
                    off,
                    self.scroll.max_offset().y / px(1.0)
                );
            }
        }

        let rows: Vec<AnyElement> = (0..rows_n)
            .map(|i| self.make_row(i, target, cx))
            .collect();
        let list = div().flex().flex_col().children(rows);

        let mut root = div().size_full().flex().flex_row().bg(rgb(0x101014));

        if suspect("S3") || suspect("S5") {
            let mut col = div()
                .w(px(280.))
                .h_full()
                .flex()
                .flex_col()
                .bg(rgb(0x1a1a20))
                .child(div().h(px(30.)).w_full().child("tabs"))
                .child(div().h(px(30.)).w_full().child("search"));
            if suspect("S5") {
                col = col.child(
                    div()
                        .h(px(30.))
                        .w_full()
                        .child(Input::new(&self.search).h(px(24.)).w_full()),
                );
            }
            col = col.child(
                div()
                    .id("modules")
                    .flex_1()
                    .min_h(px(0.))
                    .overflow_y_scroll()
                    .track_scroll(&self.scroll)
                    .child(list),
            );
            root = root.child(col).child(div().flex_1());
        } else {
            root = root.child(
                div()
                    .id("scroll-root")
                    .w(px(400.))
                    .h_full()
                    .overflow_y_scroll()
                    .track_scroll(&self.scroll)
                    .child(list),
            );
            root = root.child(
                div()
                    .w(px(200.))
                    .h_full()
                    .flex()
                    .flex_col()
                    .gap(px(12.))
                    .px(px(16.))
                    .py(px(16.))
                    .bg(rgb(0x1a1a20))
                    .child(
                        div()
                            .text_size(px(14.))
                            .text_color(rgb(0xf0f0f0))
                            .child(format!("case {}", case.name())),
                    ),
            );
        }

        if suspect("S5") {
            root = root
                .track_focus(&self.editor_focus)
                .on_key_down(cx.listener(|_this, _ev: &KeyDownEvent, _, cx| cx.notify()));
        }
        if suspect("S7") {
            root = root.relative().child(
                div()
                    .absolute()
                    .right(px(8.))
                    .bottom(px(8.))
                    .child("overlay"),
            );
        }
        if case.drag_driven() || suspect("S2") {
            root = root
                .on_mouse_move(cx.listener(Self::on_mouse_move))
                .on_mouse_up(MouseButton::Left, cx.listener(Self::on_mouse_up));
        }
        root
    }
}

fn main() {
    let case = Case::from_env();
    gpui_kit::application().run(move |cx| {
        gpui_kit::init(cx);
        Theme::change(ThemeMode::Dark, None, cx);
        let bounds = Bounds {
            origin: point(px(80.), px(80.)),
            size: size(px(600.), px(600.)),
        };
        let options = WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: Some(TitlebarOptions {
                title: Some(format!("minimal {}", case.name()).into()),
                appears_transparent: false,
                traffic_light_position: None,
            }),
            focus: true,
            show: true,
            ..Default::default()
        };
        gpui_kit::open_window(options, cx, move |window, cx| {
            cx.new(|cx| Minimal::new(case, window, cx))
        })
        .expect("open window");
        cx.activate(true);
        eprintln!("WINDOW_OPEN t={:.6} case={}", host_seconds(), case.name());
    });
}
