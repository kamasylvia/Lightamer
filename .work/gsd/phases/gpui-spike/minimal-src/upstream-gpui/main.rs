// Upstream gpui (crates.io gpui 0.2.2, the Zed-published crate): M1 / C1 only.
// Same program as minimal/src/main.rs, minus gpui-kit and minus the M2-M4/C2 cases.

use std::sync::LazyLock;
use std::time::Duration;

use gpui::*;

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

#[derive(Clone, Copy, PartialEq, Eq)]
enum Case {
    M1,
    C1,
}

impl Case {
    fn from_env() -> Self {
        match std::env::var("UPSTREAM_CASE").ok().as_deref() {
            Some("C1") => Case::C1,
            _ => Case::M1,
        }
    }

    fn name(self) -> &'static str {
        match self {
            Case::M1 => "M1",
            Case::C1 => "C1",
        }
    }

    fn scroll_offset(self) -> f32 {
        match self {
            Case::C1 => 0.0,
            _ => 600.0,
        }
    }

    fn target_row(self) -> usize {
        match self {
            Case::C1 => 1,
            _ => 20,
        }
    }
}

struct Minimal {
    case: Case,
    value: f32,
    renders: u64,
    scroll: ScrollHandle,
}

impl Minimal {
    fn new(case: Case, window: &mut Window, cx: &mut Context<Self>) -> Self {
        let offset = case.scroll_offset();
        cx.spawn_in(window, async move |this, cx| {
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

        cx.spawn_in(window, async move |this, cx| {
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
        }
    }
}

impl Render for Minimal {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        self.renders += 1;

        let case = self.case;
        let target = case.target_row();
        let frac = 0.1 + 0.8 * self.value;
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
                row.child(div().h(px(22.)).w(relative(frac)).bg(rgb(0x3b82f6)))
            } else {
                row
            };
            rows.push(row.into_any_element());
        }

        let list = div().flex().flex_col().children(rows);

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
            );

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
    Application::new().run(move |cx| {
        let bounds = Bounds {
            origin: point(px(80.), px(80.)),
            size: size(px(600.), px(600.)),
        };
        let options = WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: Some(TitlebarOptions {
                title: Some(format!("upstream {}", case.name()).into()),
                appears_transparent: false,
                traffic_light_position: None,
            }),
            focus: true,
            show: true,
            ..Default::default()
        };
        cx.open_window(options, move |window, cx| {
            cx.new(|cx| Minimal::new(case, window, cx))
        })
        .expect("open window");
        cx.activate(true);
        eprintln!("WINDOW_OPEN t={:.6} case={}", host_seconds(), case.name());
    });
}
