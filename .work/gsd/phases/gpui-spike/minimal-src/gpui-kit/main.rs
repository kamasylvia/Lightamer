// Minimal reproduction: does a geometry change inside an `overflow_y_scroll`
// container reach the screen when the scroll offset is non-zero?
//
// One binary, six cases selected by MINIMAL_CASE:
//   M1  plain div, width from 10% to 90%       (row 20, offset 600)
//   M2  gpui canvas rect, width from 10% to 90% (row 20, offset 600)
//   M3  gpui-kit Progress, value 0..1           (row 20, offset 600)
//   M4  gpui-kit Slider, value 0..1 via set_value (row 20, offset 600)
//   C1  M1, scroll offset 0                     (row 1: row 20 is off-screen at offset 0)
//   C2  M1, control outside the scroll container (offset 600)
//
// No synthetic input is used. The value is driven by a timer task, the scroll
// offset by ScrollHandle::set_offset.

use std::sync::LazyLock;
use std::time::Duration;

use gpui_kit::component::progress::Progress;
use gpui_kit::component::slider::{Slider, SliderState};
use gpui_kit::component::theme::{Theme, ThemeMode};
use gpui_kit::prelude::*;
use gpui_kit::*;

// ---------------------------------------------------------------------------
// Host clock. The frame probe records SCK presentation timestamps in
// CMClockGetHostTimeClock seconds; mach_absolute_time * timebase is the same
// clock, so TICK lines can be matched to probe frames without synthetic input.
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------

#[derive(Clone, Copy, PartialEq, Eq)]
enum Case {
    M1,
    M2,
    M3,
    M4,
    C1,
    C2,
}

impl Case {
    fn from_env() -> Self {
        match std::env::var("MINIMAL_CASE").ok().as_deref() {
            Some("M2") => Case::M2,
            Some("M3") => Case::M3,
            Some("M4") => Case::M4,
            Some("C1") => Case::C1,
            Some("C2") => Case::C2,
            _ => Case::M1,
        }
    }

    fn name(self) -> &'static str {
        match self {
            Case::M1 => "M1",
            Case::M2 => "M2",
            Case::M3 => "M3",
            Case::M4 => "M4",
            Case::C1 => "C1",
            Case::C2 => "C2",
        }
    }

    fn scroll_offset(self) -> f32 {
        match self {
            Case::C1 => 0.0,
            _ => 600.0,
        }
    }

    /// Row that carries the control inside the list. C1 uses row 1 because at
    /// offset 0 row 20 lies below the 600 px viewport.
    fn target_row(self) -> usize {
        match self {
            Case::C1 => 1,
            Case::C2 => usize::MAX,
            _ => 20,
        }
    }
}

struct Minimal {
    case: Case,
    value: f32,
    renders: u64,
    scroll: ScrollHandle,
    slider: Entity<SliderState>,
}

impl Minimal {
    fn new(case: Case, window: &mut Window, cx: &mut Context<Self>) -> Self {
        let slider = cx.new(|_| SliderState::new().min(0.0).max(1.0));

        // Scroll after the first layout so max_offset is known.
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
                let _ = this.update_in(cx, move |this, window, cx| {
                    this.value = value;
                    if this.case == Case::M4 {
                        this.slider.update(cx, |state, cx| {
                            state.set_value(value, window, cx);
                        });
                    }
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
                eprintln!(
                    "TICK_END t={:.6} renders={}",
                    host_seconds(),
                    this.renders
                );
            });
        })
        .detach();

        Self {
            case,
            value: 0.05,
            renders: 0,
            scroll: ScrollHandle::new(),
            slider,
        }
    }

    fn control(&self) -> AnyElement {
        let value = self.value;
        let frac = 0.1 + 0.8 * value;
        match self.case {
            Case::M1 | Case::C1 | Case::C2 => div()
                .h(px(22.))
                .w(relative(frac))
                .bg(rgb(0x3b82f6))
                .into_any_element(),
            Case::M2 => div()
                .h(px(22.))
                .w_full()
                .child(
                    canvas(
                        |bounds, _, _| bounds,
                        move |bounds, _, window, _cx| {
                            let bar = Bounds::new(bounds.origin, size(bounds.size.width * frac, px(20.)));
                            window.paint_quad(fill(bar, rgb(0x3b82f6)));
                            eprintln!(
                                "CANVAS_PAINT t={:.6} frac={:.4} y={:.1} w={:.1}",
                                host_seconds(),
                                frac,
                                bounds.origin.y / px(1.0),
                                bounds.size.width / px(1.0),
                            );
                        },
                    )
                    .size_full(),
                )
                .into_any_element(),
            Case::M3 => div()
                .h(px(22.))
                .w_full()
                .child(
                    Progress::new("minimal-progress")
                        .value(value * 100.0)
                        .w_full(),
                )
                .into_any_element(),
            Case::M4 => div()
                .h(px(22.))
                .w_full()
                .child(Slider::new(&self.slider).horizontal())
                .into_any_element(),
        }
    }
}

impl Render for Minimal {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        self.renders += 1;

        let case = self.case;
        let target = case.target_row();
        let mut rows: Vec<AnyElement> = Vec::with_capacity(80);
        for i in 0..80 {
            let row = div()
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
            let row = if i == target {
                row.child(self.control())
            } else {
                row
            };
            rows.push(row.into_any_element());
        }

        let list = div()
            .flex()
            .flex_col()
            .children(rows);

        let side = div()
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
            )
            .when(case == Case::C2, |this| {
                this.child(div().h(px(22.)).w_full().child(self.control()))
            });

        div()
            .size_full()
            .flex()
            .flex_row()
            .bg(rgb(0x101014))
            .child(
                div()
                    .id("scroll-root")
                    .w(px(400.))
                    .h_full()
                    .overflow_y_scroll()
                    .track_scroll(&self.scroll)
                    .child(list),
            )
            .child(side)
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
