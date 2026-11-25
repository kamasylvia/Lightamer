use std::cell::Cell;
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::OnceLock;
use std::sync::Mutex;
use std::sync::LazyLock;
use std::collections::HashSet;
use std::time::{Duration, Instant};

static T0: OnceLock<Instant> = OnceLock::new();
static SLIDER_MAP: LazyLock<Mutex<HashSet<(usize, usize)>>> = LazyLock::new(|| Mutex::new(HashSet::new()));
fn tt() -> f64 { T0.get_or_init(Instant::now).elapsed().as_secs_f64() * 1000.0 }
fn dbg_on() -> bool { std::env::var("LIGHTAMER_MM_LOG").map(|v| v != "0").unwrap_or(false) }
fn marker_on() -> bool { std::env::var("LIGHTAMER_MARKER").map(|v| v == "1").unwrap_or(false) }
fn fixed_slot_env() -> bool { std::env::var("LIGHTAMER_FIXED").map(|v| v == "1").unwrap_or(false) }

#[derive(Clone, Copy, PartialEq)]
enum SliderMode { Canvas, Div, DivFlow, Kit }

fn slider_mode_env() -> SliderMode {
    match std::env::var("LIGHTAMER_SLIDER").ok().as_deref() {
        Some("div") => SliderMode::Div,
        Some("divflow") => SliderMode::DivFlow,
        Some("kit") => SliderMode::Kit,
        _ => SliderMode::Canvas,
    }
}

#[derive(Clone, Copy, PartialEq)]
enum TimerMode { Value, Text }

fn timer_mode_env() -> Option<TimerMode> {
    match std::env::var("LIGHTAMER_TIMER").ok().as_deref() {
        Some("value") => Some(TimerMode::Value),
        Some("text") => Some(TimerMode::Text),
        _ => None,
    }
}

use gpui_kit::component::input::{Input as TextInput, InputEvent, InputState};
use gpui_kit::component::slider::{Slider, SliderEvent, SliderState};
use gpui_kit::component::theme::{Theme, ThemeMode};
use gpui_kit::prelude::*;
use gpui_kit::*;

actions!(proto, [ConfirmCombo]);

// darktable 5.6.2 "elegant grey" palette, sampled from the official build's screenshot
// and from its shipped darktable-elegant-grey.css tokens.
const C_PANEL: u32 = 0x5e5e5e;
const C_BODY: u32 = 0x666666;
const C_SIDEBAR: u32 = 0x868686;
const C_TEXT: u32 = 0xf1f1f1;
const C_DIM: u32 = 0xc6c6c6;
const C_TRACK: u32 = 0x4b4b4b;
const C_FILL: u32 = 0xaeaeae;
const C_FILL_HOT: u32 = 0xd4d4d4;
const C_BORDER: u32 = 0x4a4a4a;
const C_SELECT: u32 = 0x777777;

#[derive(Clone, Copy)]
struct ParamDef {
    name: &'static str,
    min: f32,
    max: f32,
    default: f32,
    step: f32,
    decimals: usize,
    unit: &'static str,
    log: bool,
}

fn p(name: &'static str, min: f32, max: f32, default: f32, step: f32, decimals: usize, unit: &'static str) -> ParamDef {
    ParamDef { name, min, max, default, step, decimals, unit, log: false }
}

fn plog(name: &'static str, min: f32, max: f32, default: f32, step: f32, decimals: usize, unit: &'static str) -> ParamDef {
    ParamDef { name, min, max, default, step, decimals, unit, log: true }
}

#[derive(Clone, Copy)]
struct ComboDef {
    name: &'static str,
    options: &'static [&'static str],
    default: usize,
}

struct ModuleDef {
    name: &'static str,
    /// darktable 5.6.2 default (v50) pipeline order, from src/common/iop_order.c
    order: f32,
    group: u8,
    params: Vec<ParamDef>,
    adv: Vec<ParamDef>,
    combos: Vec<ComboDef>,
    toggles: Vec<(&'static str, bool)>,
    buttons: Vec<&'static str>,
    tabs: Vec<&'static str>,
    curve: bool,
    icons: bool,
    expanded_default: bool,
}

impl ModuleDef {
    /// One filler module: unified header + 2 or 3 sliders, collapsed by default.
    fn filler(order: f32, name: &'static str, group: u8, sliders: u8, expanded: bool) -> Self {
        let mut params = vec![
            p("strength", 0.0, 2.0, 1.0, 0.01, 3, ""),
            p("radius", 0.0, 100.0, 25.0, 0.1, 2, " px"),
        ];
        if sliders >= 3 {
            params.push(p("iterations", 1.0, 8.0, 2.0, 1.0, 0, ""));
        }
        Self {
            name,
            order,
            group,
            params,
            adv: vec![],
            combos: vec![],
            toggles: vec![],
            buttons: vec![],
            tabs: vec![],
            curve: false,
            icons: false,
            expanded_default: expanded,
        }
    }
}

fn module_defs() -> Vec<ModuleDef> {
    let mut v: Vec<ModuleDef> = Vec::new();
    v.push(ModuleDef {
        name: "exposure",
        order: 21.0,
        group: 1,
        params: vec![
            p("exposure", -3.0, 3.0, 0.7, 0.01, 3, " EV"),
            p("black level correction", -0.1, 0.1, -0.0162, 0.0001, 4, ""),
        ],
        adv: vec![p("deflicker", 0.0, 1.0, 0.0, 0.01, 2, "")],
        combos: vec![ComboDef { name: "mode", options: &["manual", "automatic"], default: 0 }],
        toggles: vec![("compensate camera exposure (+0.0 EV)", true)],
        buttons: vec!["area exposure mapping"],
        tabs: vec![],
        curve: false,
        icons: false,
        expanded_default: true,
    });
    v.push(ModuleDef {
        name: "white balance",
        order: 3.0,
        group: 2,
        params: vec![
            plog("temperature", 2000.0, 12500.0, 5294.0, 10.0, 0, " K"),
            p("tint", 0.135, 2.0, 0.981, 0.001, 3, ""),
        ],
        adv: vec![p("exposure compensation", -5.0, 5.0, 0.0, 0.01, 3, " EV")],
        combos: vec![ComboDef {
            name: "settings",
            options: &["as shot to reference", "as shot", "camera reference", "custom"],
            default: 0,
        }],
        toggles: vec![],
        buttons: vec!["channel coefficients"],
        tabs: vec![],
        curve: false,
        icons: true,
        expanded_default: true,
    });
    v.push(ModuleDef {
        name: "filmic rgb",
        order: 46.0,
        group: 1,
        params: vec![
            p("white relative exposure", 0.0, 20.0, 4.56, 0.01, 3, " EV"),
            p("black relative exposure", -20.0, 0.0, -7.65, 0.01, 3, " EV"),
            p("contrast", 0.0, 2.0, 0.85, 0.01, 3, ""),
            p("latitude", 0.0, 100.0, 31.0, 0.1, 2, " %"),
            p("shadows", 0.0, 100.0, 46.0, 0.1, 2, " %"),
            p("highlights", 0.0, 100.0, 46.0, 0.1, 2, " %"),
            p("saturation", 0.0, 100.0, 8.0, 0.1, 2, " %"),
        ],
        adv: vec![
            p("mid grey", 0.01, 1.0, 0.1845, 0.001, 4, ""),
            p("grey border", -10.0, 10.0, -2.0, 0.01, 3, " EV"),
        ],
        combos: vec![ComboDef {
            name: "preserve chrominance",
            options: &["luminance", "max RGB", "average RGB"],
            default: 0,
        }],
        toggles: vec![("extrapolate colors", false)],
        buttons: vec![],
        tabs: vec!["scene", "reconstruction", "look", "display", "options"],
        curve: true,
        icons: false,
        expanded_default: true,
    });
    // 27 filler modules: display names taken verbatim from the darktable 5.6.2
    // release tag (src/iop/*.c `name()`), placed at their v50_order positions.
    // (order, name, group, sliders, expanded)
    let fillers: &[(f32, &'static str, u8, u8, bool)] = &[
        (1.0, "raw black/white point", 0, 2, false),
        (4.0, "highlight reconstruction", 1, 3, false),
        (5.0, "raw chromatic aberrations", 3, 2, false),
        (6.0, "hot pixels", 3, 2, false),
        (8.0, "demosaic", 0, 3, false),
        (9.0, "denoise (profiled)", 4, 3, false),
        (10.0, "surface blur", 4, 2, false),
        (13.0, "lens correction", 3, 3, false),
        (14.0, "haze removal", 3, 2, false),
        (15.0, "rotate and perspective", 3, 3, false),
        (24.0, "tone equalizer", 1, 3, false),
        (24.5, "crop", 3, 2, false),
        (25.0, "graduated density", 1, 3, false),
        (27.0, "legacy equalizer", 4, 3, false),
        (28.0, "input color profile", 2, 2, true),
        (28.5, "color calibration", 2, 3, true),
        (28.5, "diffuse or sharpen", 4, 3, true),
        (28.5, "rgb primaries", 2, 3, false),
        (31.0, "defringe", 3, 2, false),
        (35.0, "sharpen", 4, 3, false),
        (41.0, "color balance", 2, 3, false),
        (41.2, "color equalizer", 2, 3, false),
        (41.5, "color balance rgb", 2, 3, false),
        (42.0, "rgb curve", 1, 3, false),
        (44.0, "base curve", 1, 3, false),
        (48.0, "tone curve", 1, 3, false),
        (68.0, "vignette", 4, 2, false),
    ];
    for &(order, name, group, sliders, expanded) in fillers {
        v.push(ModuleDef::filler(order, name, group, sliders, expanded));
    }
    v.sort_by(|a, b| a.order.total_cmp(&b.order));
    v
}

#[derive(Clone)]
struct ModuleSnap {
    enabled: bool,
    params: Vec<f32>,
    combos: Vec<usize>,
    toggles: Vec<bool>,
}

struct ModuleState {
    def: usize,
    enabled: bool,
    expanded: bool,
    advanced: bool,
    params: Vec<f32>,
    combos: Vec<usize>,
    toggles: Vec<bool>,
    instances: u32,
    active_tab: usize,
    icons: usize,
}

impl ModuleState {
    fn new(defs: &[ModuleDef], def: usize) -> Self {
        let d = &defs[def];
        let mut params: Vec<f32> = d.params.iter().map(|p| p.default).collect();
        params.extend(d.adv.iter().map(|p| p.default));
        Self {
            def,
            enabled: true,
            expanded: d.expanded_default,
            advanced: false,
            params,
            combos: d.combos.iter().map(|c| c.default).collect(),
            toggles: d.toggles.iter().map(|t| t.1).collect(),
            instances: 1,
            active_tab: 0,
            icons: 4,
        }
    }
    fn snap(&self) -> ModuleSnap {
        ModuleSnap { enabled: self.enabled, params: self.params.clone(), combos: self.combos.clone(), toggles: self.toggles.clone() }
    }
    fn restore(&mut self, s: &ModuleSnap) {
        self.enabled = s.enabled;
        self.params.clone_from(&s.params);
        self.combos.clone_from(&s.combos);
        self.toggles.clone_from(&s.toggles);
    }
}

struct HistEntry {
    label: String,
    detail: String,
    snaps: Vec<ModuleSnap>,
}

struct ImageInfo {
    path: &'static str,
    thumb: &'static str,
    w: f32,
    h: f32,
    name: &'static str,
}

struct DragState {
    module: usize,
    param: usize,
    start_x: f32,
    start_value: f32,
    width: f32,
    moved: bool,
}

struct MenuState {
    x: f32,
    y: f32,
    module: usize,
    param: usize,
}

struct EditState {
    x: f32,
    y: f32,
    module: usize,
    param: usize,
}

struct ComboOpen {
    module: usize,
    combo: usize,
    x: f32,
    y: f32,
    query: String,
    sel: usize,
}

struct Proto {
    defs: Vec<ModuleDef>,
    modules: Vec<ModuleState>,
    history: Vec<HistEntry>,
    hist_pos: usize,
    search: Entity<InputState>,
    value_input: Entity<InputState>,
    _subs: Vec<Subscription>,
    images: Vec<ImageInfo>,
    current: usize,
    zoom: f32,
    pan: Point<Pixels>,
    pan_start: Option<(f32, f32, f32, f32)>,
    drag: Option<DragState>,
    left_open: bool,
    group: Option<u8>,
    menu: Option<MenuState>,
    edit: Option<EditState>,
    combo: Option<ComboOpen>,
    editor_focus: FocusHandle,
    view_focus: FocusHandle,
    layout_w: f32,
    layout_h: f32,
    exposure_idx: usize,
    modules_scroll: ScrollHandle,
    scroll_reported: Cell<f32>,
    mm_recv: u32,
    mm_applied: u32,
    mm_skip: u32,
    renders: u32,
    renders_drag: u32,
    slider_mode: SliderMode,
    fixed_slot: bool,
    timer_mode: Option<TimerMode>,
    tick: u32,
    slider_state: Option<Entity<SliderState>>,
}


fn fmt_value(v: f32, d: &ParamDef) -> String {
    let s = if d.decimals == 0 { format!("{}", v.round() as i64) } else { format!("{:.*}", d.decimals, v) };
    if v > 0.0 && d.unit == " EV" {
        format!("+{}{}", s, d.unit)
    } else {
        format!("{}{}", s, d.unit)
    }
}

fn value_to_frac(v: f32, d: &ParamDef) -> f32 {
    if d.log {
        (v.max(d.min) / d.min).ln() / (d.max / d.min).ln()
    } else {
        (v - d.min) / (d.max - d.min)
    }
}

fn frac_to_value(f: f32, d: &ParamDef) -> f32 {
    let raw = if d.log {
        d.min * (d.max / d.min).powf(f.clamp(0.0, 1.0))
    } else {
        d.min + (d.max - d.min) * f.clamp(0.0, 1.0)
    };
    if d.step > 0.0 {
        let n = ((raw - d.min) / d.step).round();
        (d.min + n * d.step).clamp(d.min, d.max)
    } else {
        raw
    }
}

fn quad(b: Bounds<Pixels>, color: u32) -> PaintQuad {
    PaintQuad {
        bounds: b,
        corner_radii: Corners::default(),
        background: rgb(color).into(),
        border_widths: Edges::default(),
        border_color: transparent_black(),
        border_style: BorderStyle::default(),
    }
}

impl Proto {
    fn new(defs: Vec<ModuleDef>, window: &mut Window, cx: &mut Context<Self>) -> Self {
        let search = cx.new(|cx| InputState::new(window, cx).placeholder("search modules by name or tag"));
        let value_input = cx.new(|cx| InputState::new(window, cx).placeholder("value"));
        let modules: Vec<ModuleState> = (0..defs.len()).map(|i| ModuleState::new(&defs, i)).collect();
        let images = vec![
            ImageInfo { path: "assets/7RM5-LosslessCompressedLarge.jpg", thumb: "assets/thumbs/1.jpg", w: 9504.0, h: 6336.0, name: "7RM5-LosslessCompressedLarge.ARW" },
            ImageInfo { path: "assets/IMG_4276.jpg", thumb: "assets/thumbs/2.jpg", w: 6000.0, h: 4000.0, name: "IMG_4276.CR3" },
            ImageInfo { path: "assets/Nikon_Z8_raw_14_bit_lossless_compression.jpg", thumb: "assets/thumbs/3.jpg", w: 8256.0, h: 5504.0, name: "Nikon_Z8_raw_14_bit_lossless_compression.NEF" },
            ImageInfo { path: "assets/DSCF0021.jpg", thumb: "assets/thumbs/4.jpg", w: 6240.0, h: 4160.0, name: "DSCF0021.RAF" },
        ];
        let snaps: Vec<ModuleSnap> = modules.iter().map(|m| m.snap()).collect();
        let history = vec![HistEntry { label: "original".into(), detail: "".into(), snaps }];
        let exposure_idx = defs.iter().position(|d| d.name == "exposure").unwrap_or(0);
        let editor_focus = cx.focus_handle();
        let view_focus = cx.focus_handle();
        let sub_search = cx.subscribe(&search, |_, _, _: &InputEvent, cx| cx.notify());
        let sub_value = cx.subscribe(&value_input, |this, _, event: &InputEvent, cx| {
            if let InputEvent::PressEnter { .. } = event {
                this.commit_edit(cx);
            }
        });
        let slider_mode = slider_mode_env();
        let fixed_slot = fixed_slot_env();
        let timer_mode = timer_mode_env();
        if timer_mode.is_some() {
            window.focus(&editor_focus, cx);
        }
        let slider_state = if slider_mode == SliderMode::Kit {
            Some(cx.new(|_| SliderState::new().min(-3.0).max(3.0).step(0.01).default_value(0.7)))
        } else {
            None
        };
        let mut subs = vec![sub_search, sub_value];
        if let Some(state) = &slider_state {
            let ei = exposure_idx;
            subs.push(cx.subscribe(state, move |this, _state, ev: &SliderEvent, cx| {
                let v = match ev {
                    SliderEvent::Change(v) => v.end(),
                    SliderEvent::Release(v) => v.end(),
                };
                this.modules[ei].params[0] = v;
                if matches!(ev, SliderEvent::Release(_)) {
                    let pd = this.param_def(ei, 0);
                    let name = this.defs[this.modules[ei].def].name;
                    this.commit(pd.name, format!("{} → {}", name, fmt_value(v, &pd)));
                }
                cx.notify();
            }));
        }
        Self {
            defs,
            modules,
            history,
            hist_pos: 0,
            search,
            value_input,
            _subs: subs,
            images,
            current: 0,
            zoom: 1.0,
            pan: point(px(0.), px(0.)),
            pan_start: None,
            drag: None,
            left_open: true,
            group: None,
            menu: None,
            edit: None,
            combo: None,
            layout_w: 1440.0,
            layout_h: 846.0,
            exposure_idx,
            modules_scroll: ScrollHandle::new(),
            scroll_reported: Cell::new(-1.0e9),
            mm_recv: 0,
            mm_applied: 0,
            mm_skip: 0,
            renders: 0,
            renders_drag: 0,
            slider_mode,
            fixed_slot,
            timer_mode,
            tick: 0,
            slider_state,
            editor_focus,
            view_focus,
        }
    }

    fn snapshot(&self) -> Vec<ModuleSnap> {
        self.modules.iter().map(|m| m.snap()).collect()
    }

    fn commit(&mut self, label: impl Into<String>, detail: impl Into<String>) {
        let entry = HistEntry { label: label.into(), detail: detail.into(), snaps: self.snapshot() };
        self.history.truncate(self.hist_pos + 1);
        self.history.push(entry);
        if self.history.len() > 60 {
            self.history.remove(0);
        }
        self.hist_pos = self.history.len() - 1;
    }

    fn jump(&mut self, idx: usize, cx: &mut Context<Self>) {
        if idx >= self.history.len() { return; }
        self.hist_pos = idx;
        let snaps = self.history[idx].snaps.clone();
        for (m, s) in self.modules.iter_mut().zip(snaps.iter()) {
            m.restore(s);
        }
        cx.notify();
    }

    fn undo(&mut self, cx: &mut Context<Self>) {
        if self.hist_pos > 0 {
            self.jump(self.hist_pos - 1, cx);
        }
    }

    fn redo(&mut self, cx: &mut Context<Self>) {
        if self.hist_pos + 1 < self.history.len() {
            self.jump(self.hist_pos + 1, cx);
        }
    }

    fn confirm_combo(&mut self, cx: &mut Context<Self>) {
        let Some((m, c, sel)) = self.combo.as_ref().map(|cb| (cb.module, cb.combo, cb.sel)) else { return };
        let query = self.combo.as_ref().map(|cb| cb.query.clone()).unwrap_or_default();
        let def = self.modules[m].def;
        let cd = self.defs[def].combos[c];
        let filtered: Vec<usize> = (0..cd.options.len())
            .filter(|i| cd.options[*i].to_lowercase().contains(&query.to_lowercase()))
            .collect();
        if let Some(opt) = filtered.get(sel) {
            self.modules[m].combos[c] = *opt;
            let name = self.defs[def].name;
            self.commit("preset", format!("{} · {}", name, cd.name));
        }
        self.combo = None;
        cx.notify();
    }

    fn param_def(&self, module: usize, param: usize) -> ParamDef {
        let d = &self.defs[self.modules[module].def];
        if param < d.params.len() { d.params[param] } else { d.adv[param - d.params.len()] }
    }

    fn reset_param(&mut self, module: usize, param: usize, cx: &mut Context<Self>) {
        let pd = self.param_def(module, param);
        self.modules[module].params[param] = pd.default;
        let name = self.defs[self.modules[module].def].name;
        self.commit("reset", format!("{} · {}", name, pd.name));
        cx.notify();
    }

    fn commit_edit(&mut self, cx: &mut Context<Self>) {
        if let Some(edit) = self.edit.take() {
            let text = self.value_input.read(cx).value().to_string().trim().to_string();
            if let Ok(v) = text.parse::<f32>() {
                let pd = self.param_def(edit.module, edit.param);
                self.modules[edit.module].params[edit.param] = v.clamp(pd.min, pd.max);
                let name = self.defs[self.modules[edit.module].def].name;
                self.commit(pd.name, format!("{} → {}", name, fmt_value(v, &pd)));
            }
            cx.notify();
        }
    }

    fn module_filter(&self, cx: &App) -> String {
        self.search.read(cx).value().to_string().to_lowercase()
    }

    fn viewport_rect(&self) -> (f32, f32) {
        (self.layout_w - 560.0, self.layout_h - 34.0 - 104.0)
    }

    fn fit_scale(&self) -> f32 {
        let (vw, vh) = self.viewport_rect();
        let img = &self.images[self.current];
        ((vw - 24.0) / img.w).min((vh - 24.0) / img.h).max(0.0001)
    }

    fn reset_image(&mut self) {
        self.modules = (0..self.defs.len()).map(|i| ModuleState::new(&self.defs, i)).collect();
        let snaps = self.snapshot();
        self.history = vec![HistEntry { label: "original".into(), detail: "".into(), snaps }];
        self.hist_pos = 0;
        self.zoom = 1.0;
        self.pan = point(px(0.), px(0.));
    }
}

impl Render for Proto {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let size = window.viewport_size();
        self.layout_w = size.width / px(1.0);
        self.layout_h = size.height / px(1.0);
        self.renders += 1;
        if self.drag.is_some() {
            self.renders_drag += 1;
            if self.renders_drag <= 100 && dbg_on() {
                eprintln!("RENDER t={:.1} n={} drags={}", tt(), self.renders, self.renders_drag);
            }
        }
        let filter = self.module_filter(cx);

        div()
            .size_full()
            .flex()
            .flex_col()
            .bg(rgb(C_PANEL))
            .text_color(rgb(C_TEXT))
            .text_size(px(13.0))
            .font_family("Helvetica Neue")
            .track_focus(&self.editor_focus)
            .on_key_down(cx.listener(Self::on_key))
            .on_action(cx.listener(|this, _: &ConfirmCombo, _window, cx| {
                if this.edit.is_some() {
                    this.commit_edit(cx);
                } else {
                    this.confirm_combo(cx);
                }
            }))
            .on_mouse_move(cx.listener(Self::on_mouse_move))
            .on_mouse_up(MouseButton::Left, cx.listener(Self::on_mouse_up))
            .on_mouse_down(MouseButton::Left, cx.listener(|this, ev: &MouseDownEvent, window, cx| {
                if dbg_on() {
                    eprintln!("ROOT_DOWN t={:.1} pos={:.1},{:.1} clicks={}", tt(), ev.position.x / px(1.0), ev.position.y / px(1.0), ev.click_count);
                }
                if !this.search.read(cx).focus_handle(cx).is_focused(window) {
                    window.focus(&this.editor_focus, cx);
                }
            }))
            .child(self.top_bar())
            .child(
                div()
                    .flex_1()
                    .flex()
                    .flex_row()
                    .min_h(px(0.))
                    .child(self.left_panel(cx))
                    .child(self.center_column(cx))
                    .child(self.right_panel(&filter, cx)),
            )
            .children(self.overlays(cx))
    }
}

impl Proto {
    fn start_ticker(&mut self, cx: &mut Context<Self>) {
        let Some(mode) = self.timer_mode else { return; };
        let ei = self.exposure_idx;
        cx.spawn(async move |this, cx| {
            cx.background_executor().timer(Duration::from_millis(500)).await;
            if let Ok(r) = this.update(cx, |this, _| this.renders) {
                eprintln!("TICK_START t={:.1} renders={}", tt(), r);
            }
            for n in 0..40u32 {
                let ok = this.update(cx, |this, cx| {
                    match mode {
                        TimerMode::Value => { this.modules[ei].params[0] = 0.7 + 0.05 * n as f32; }
                        TimerMode::Text => { this.tick = n + 1; }
                    }
                    if dbg_on() {
                        eprintln!("TICK n={} t={:.1} renders={} value={:.4} tick={}", n, tt(), this.renders, this.modules[ei].params[0], this.tick);
                    }
                    cx.notify();
                });
                if ok.is_err() { break; }
                if n < 39 {
                    cx.background_executor().timer(Duration::from_millis(16)).await;
                }
            }
            if let Ok(r) = this.update(cx, |this, _| this.renders) {
                eprintln!("TICK_END t={:.1} renders={}", tt(), r);
            }
        }).detach();
    }

    fn on_key(&mut self, ev: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        let k = ev.keystroke.key.clone();
        if dbg_on() {
            eprintln!("KEY {:?} mods_platform={}", k, ev.keystroke.modifiers.platform);
        }
        let key = k.as_str();
        let mods = ev.keystroke.modifiers;

        if self.combo.is_some() {
            if key == "up" || key == "down" {
                if let Some(c) = &mut self.combo {
                    if key == "up" { c.sel = c.sel.saturating_sub(1); } else { c.sel += 1; }
                }
                cx.notify();
                return;
            }
            if key == "escape" {
                self.combo = None;
                cx.notify();
                return;
            }
            if key == "enter" {
                self.confirm_combo(cx);
                return;
            }
            if key.len() == 1 {
                if let Some(c) = &mut self.combo {
                    c.query.push_str(key);
                    c.sel = 0;
                }
                cx.notify();
                return;
            }
        }

        if key == "escape" {
            if dbg_on() {
                eprintln!("MENU escape");
            }
            self.menu = None;
            self.edit = None;
            self.combo = None;
            cx.notify();
            return;
        }

        if self.edit.is_some() {
            return;
        }

        if mods.platform && key == "z" {
            if mods.shift { self.redo(cx); } else { self.undo(cx); }
            return;
        }

        if self.search.read(cx).focus_handle(cx).is_focused(window)
            || self.value_input.read(cx).focus_handle(cx).is_focused(window)
        {
            return;
        }

        if key == "space" && self.timer_mode.is_some() {
            self.start_ticker(cx);
            return;
        }

        match key {
            "left" => {
                if self.current + 1 < self.images.len() {
                    self.current += 1;
                    self.reset_image();
                    cx.notify();
                }
            }
            "right" => {
                if self.current > 0 {
                    self.current -= 1;
                    self.reset_image();
                    cx.notify();
                }
            }
            _ => {}
        }
    }

    fn on_mouse_move(&mut self, ev: &MouseMoveEvent, _window: &mut Window, cx: &mut Context<Self>) {
        self.mm_recv += 1;
        let had_drag = self.drag.is_some();
        let Some(drag) = &self.drag else {
            if dbg_on() {
                eprintln!("MM t={:.1} n={} NO_DRAG pos={:.1},{:.1} pressed={:?}", tt(), self.mm_recv, ev.position.x / px(1.0), ev.position.y / px(1.0), ev.pressed_button);
            }
            return;
        };
        if ev.pressed_button != Some(MouseButton::Left) {
            self.mm_skip += 1;
            if dbg_on() {
                eprintln!("MM t={:.1} n={} SKIP_BUTTON pos={:.1},{:.1} pressed={:?}", tt(), self.mm_recv, ev.position.x / px(1.0), ev.position.y / px(1.0), ev.pressed_button);
            }
            return;
        }
        let (module, param, start_x, start_value, width) = (drag.module, drag.param, drag.start_x, drag.start_value, drag.width);
        let dx = ev.position.x / px(1.0) - start_x;
        let pd = self.param_def(module, param);
        let frac = value_to_frac(start_value, &pd) + dx / width.max(1.0);
        let v = frac_to_value(frac, &pd);
        self.modules[module].params[param] = v;
        self.mm_applied += 1;
        if let Some(d) = &mut self.drag {
            d.moved = true;
        }
        if dbg_on() || had_drag {
            eprintln!("MM t={:.1} n={} APPLY pos={:.1},{:.1} sx={:.1} w={:.1} m={} p={} v={:.4} renders={} renders_drag={}", tt(), self.mm_recv, ev.position.x / px(1.0), ev.position.y / px(1.0), start_x, width, module, param, v, self.renders, self.renders_drag);
        }
        cx.notify();
    }

    fn on_mouse_up(&mut self, _ev: &MouseUpEvent, _window: &mut Window, cx: &mut Context<Self>) {
        if let Some(d) = self.drag.take() {
            if dbg_on() {
                eprintln!("DRAG_SUMMARY t={:.1} mm_recv={} mm_applied={} mm_skip={} renders={} renders_drag={} module={} param={} value={:.4}", tt(), self.mm_recv, self.mm_applied, self.mm_skip, self.renders, self.renders_drag, d.module, d.param, self.modules[d.module].params[d.param]);
            }
            if d.moved {
                let pd = self.param_def(d.module, d.param);
                let v = self.modules[d.module].params[d.param];
                let name = self.defs[self.modules[d.module].def].name;
                self.commit(pd.name, format!("{} → {}", name, fmt_value(v, &pd)));
                cx.notify();
            }
        }
    }

    fn top_bar(&self) -> impl IntoElement {
        div()
            .h(px(34.))
            .w_full()
            .flex()
            .items_center()
            .px(px(10.))
            .gap(px(10.))
            .bg(rgb(C_PANEL))
            .border_b(px(1.))
            .border_color(rgb(C_BORDER))
            .child(div().w(px(18.)).h(px(18.)).rounded_full().bg(rgb(0x3a6ea5)))
            .when(marker_on(), |d| d.child(div().w(px(((self.renders % 16) as f32) * 6.0)).h(px(6.)).bg(rgb(0xff3b30))))
            .child(div().text_size(px(15.)).child("lightamer"))
            .child(div().text_size(px(10.)).text_color(rgb(C_DIM)).child("0.1.0 · gpui spike"))
            .child(div().flex_1())
            .child(div().child("lighttable"))
            .child(div().text_color(rgb(C_DIM)).child("|"))
            .child(div().child("darkroom"))
            .child(div().text_color(rgb(C_DIM)).child("|"))
            .child(div().text_color(rgb(C_DIM)).child("other"))
    }

    fn left_panel(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let width = if self.left_open { 280.0 } else { 26.0 };
        let body = if self.left_open {
            div()
                .flex()
                .flex_col()
                .flex_1()
                .child(self.sidebar_section("history", 340.0, cx))
                .child(self.sidebar_section("snapshots", 0.0, cx))
        } else {
            div().size_full()
        };
        div()
            .w(px(width))
            .h_full()
            .flex()
            .flex_col()
            .bg(rgb(C_SIDEBAR))
            .text_color(rgb(C_TEXT))
            .border_r(px(1.))
            .border_color(rgb(C_BORDER))
            .child(
                div()
                    .h(px(26.))
                    .w_full()
                    .flex()
                    .items_center()
                    .justify_end()
                    .pr(px(6.))
                    .child(
                        div()
                            .id("left-toggle")
                            .cursor_pointer()
                            .px(px(4.))
                            .child(if self.left_open { "‹" } else { "›" })
                            .on_mouse_down(MouseButton::Left, cx.listener(|this, _, _, cx| {
                                this.left_open = !this.left_open;
                                cx.notify();
                            })),
                    ),
            )
            .child(body)
    }

    fn sidebar_section(&self, title: &str, height: f32, cx: &mut Context<Self>) -> impl IntoElement {
        let mut col = div().flex().flex_col().w_full().min_h(px(28.));
        col = col.child(
            div()
                .h(px(28.))
                .w_full()
                .flex()
                .items_center()
                .gap(px(6.))
                .px(px(8.))
                .child(div().text_size(px(11.)).child("▸"))
                .child(div().text_size(px(12.)).child(title.to_string())),
        );
        if title == "history" {
            let items: Vec<AnyElement> = (0..self.history.len())
                .map(|i| {
                    let e = &self.history[i];
                    let selected = i == self.hist_pos;
                    let label = if e.detail.is_empty() { e.label.clone() } else { format!("{}   {}", e.label, e.detail) };
                    div()
                        .h(px(22.))
                        .w_full()
                        .px(px(14.))
                        .flex()
                        .items_center()
                        .text_size(px(12.))
                        .when(selected, |d| d.bg(rgb(C_SELECT)).text_color(rgb(0xffffff)))
                        .id(("hist", i))
                        .hover(|d| d.bg(rgb(0x777777)))
                        .cursor_pointer()
                        .child(label)
                        .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, _, cx| {
                            this.jump(i, cx);
                        }))
                        .into_any_element()
                })
                .collect();
            col = col.child(
                div()
                    .id("hist-list")
                    .h(px(height))
                    .w_full()
                    .flex()
                    .flex_col()
                    .overflow_y_scroll()
                    .children(items),
            );
        }
        col
    }

    fn center_column(&self, cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .flex_1()
            .min_w(px(0.))
            .h_full()
            .flex()
            .flex_col()
            .child(self.viewport(cx))
            .child(self.filmstrip(cx))
    }

    fn viewport(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let (vw, vh) = self.viewport_rect();
        let img_info = &self.images[self.current];
        let scale = self.fit_scale() * self.zoom;
        let w = img_info.w * scale;
        let h = img_info.h * scale;
        let left = (vw - w) / 2.0 + self.pan.x / px(1.0);
        let top = (vh - h) / 2.0 + self.pan.y / px(1.0);
        let path = PathBuf::from(img_info.path);

        div()
            .id("viewport")
            .flex_1()
            .w_full()
            .min_h(px(0.))
            .relative()
            .overflow_hidden()
            .bg(rgb(C_PANEL))
            .track_focus(&self.view_focus)
            .on_mouse_down(MouseButton::Left, cx.listener(|this, ev: &MouseDownEvent, window, cx| {
                window.focus(&this.view_focus, cx);
                this.pan_start = Some((ev.position.x / px(1.0), ev.position.y / px(1.0), this.pan.x / px(1.0), this.pan.y / px(1.0)));
                cx.notify();
            }))
            .on_mouse_move(cx.listener(|this, ev: &MouseMoveEvent, _, cx| {
                if let Some((sx, sy, px0, py0)) = this.pan_start {
                    if ev.pressed_button == Some(MouseButton::Left) {
                        this.pan = point(px(px0 + ev.position.x / px(1.0) - sx), px(py0 + ev.position.y / px(1.0) - sy));
                        cx.notify();
                    }
                }
            }))
            .on_mouse_up(MouseButton::Left, cx.listener(|this, _, _, _cx| {
                this.pan_start = None;
            }))
            .on_scroll(cx.listener(|this, ev: &ScrollEvent, _, cx| {
                let dy = match ev.delta { ScrollDelta::Pixels(p) => p.y / px(1.0), ScrollDelta::Lines(p) => p.y * 24.0 };
                let f = (dy * 0.0025).exp();
                this.zoom = (this.zoom * f).clamp(0.05, 12.0);
                cx.notify();
            }))
            .child(
                div()
                    .absolute()
                    .left(px(left))
                    .top(px(top))
                    .w(px(w))
                    .h(px(h))
                    .child(img(path).w_full().h_full().object_fit(ObjectFit::Fill)),
            )
            .child({
                // Exposure drives a visible viewport change, as in darktable, so that
                // "pointer -> picture" latency measures a picture update too.
                let ev = self.modules[self.exposure_idx].params[0];
                let (color, alpha) = if ev >= 0.0 {
                    (0xffffffu32, (ev * 0.11).min(0.55))
                } else {
                    (0x000000u32, (-ev * 0.17).min(0.78))
                };
                let a = (alpha * 255.0) as u32;
                div()
                    .absolute()
                    .left(px(left))
                    .top(px(top))
                    .w(px(w))
                    .h(px(h))
                    .bg(rgba((color << 8) | a))
            })
            .child(
                div()
                    .absolute()
                    .left(px(12.))
                    .bottom(px(8.))
                    .text_size(px(11.))
                    .text_color(rgb(C_DIM))
                    .child(format!(
                        "{}  ·  {:.0}%  ·  {:.1} MP",
                        img_info.name,
                        self.zoom * self.fit_scale() * 100.0,
                        img_info.w * img_info.h / 1e6
                    )),
            )
    }

    fn filmstrip(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let thumbs: Vec<AnyElement> = self
            .images
            .iter()
            .enumerate()
            .map(|(i, im)| {
                let selected = i == self.current;
                div()
                    .w(px(96.))
                    .h(px(84.))
                    .flex_none()
                    .p(px(3.))
                    .when(selected, |d| d.bg(rgb(0xffffff)))
                    .id(("thumb", i))
                    .cursor_pointer()
                    .child(
                        div()
                            .relative()
                            .w_full()
                            .h_full()
                            .overflow_hidden()
                            .child(img(PathBuf::from(im.thumb)).w_full().h_full().object_fit(ObjectFit::Cover)),
                    )
                    .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, window, cx| {
                        window.focus(&this.view_focus, cx);
                        this.current = i;
                        this.reset_image();
                        cx.notify();
                    }))
                    .into_any_element()
            })
            .collect();
        div()
            .h(px(104.))
            .w_full()
            .flex()
            .items_center()
            .justify_center()
            .gap(px(6.))
            .bg(rgb(C_SIDEBAR))
            .border_t(px(1.))
            .border_color(rgb(C_BORDER))
            .children(thumbs)
    }

    fn right_panel(&self, filter: &str, cx: &mut Context<Self>) -> impl IntoElement {
        // Debug evidence: the real module-list scroll offset, to stderr, on every change.
        let off = -(self.modules_scroll.offset().y / px(1.0));
        if (off - self.scroll_reported.get()).abs() >= 0.5 {
            self.scroll_reported.set(off);
            if dbg_on() {
                eprintln!("SCROLL_OFFSET y={:.1} max={:.1}", off, self.modules_scroll.max_offset().y / px(1.0));
            }
        }
        let groups = ["active", "base", "tone", "color", "correct", "effects"];
        let tabs: Vec<AnyElement> = groups
            .iter()
            .enumerate()
            .map(|(i, g)| {
                let active = self.group == Some(i as u8) || (self.group.is_none() && i == 0);
                div()
                    .id(("grp", i))
                    .w(px(20.))
                    .h(px(20.))
                    .flex()
                    .items_center()
                    .justify_center()
                    .rounded_full()
                    .border(px(1.))
                    .border_color(rgb(if active { 0xf1f1f1 } else { 0x9a9a9a }))
                    .text_size(px(9.))
                    .cursor_pointer()
                    .child(g[0..1].to_uppercase())
                    .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, _, cx| {
                        this.group = if i == 0 { None } else { Some(i as u8) };
                        cx.notify();
                    }))
                    .into_any_element()
            })
            .collect();

        let items: Vec<AnyElement> = self
            .modules
            .iter()
            .enumerate()
            .filter(|(_, m)| {
                let d = &self.defs[m.def];
                let ok_name = filter.is_empty() || d.name.to_lowercase().contains(filter);
                let ok_group = self.group.map(|g| g == 0 || d.group == g).unwrap_or(true);
                ok_name && ok_group
            })
            .map(|(i, _)| self.module_view(i, cx))
            .collect();

        div()
            .w(px(280.))
            .h_full()
            .flex()
            .flex_col()
            .bg(rgb(C_PANEL))
            .border_l(px(1.))
            .border_color(rgb(C_BORDER))
            .child(div().h(px(30.)).w_full().flex().items_center().justify_center().gap(px(6.)).children(tabs))
            .child(
                div().h(px(30.)).w_full().px(px(4.)).child(
                    TextInput::new(&self.search)
                        .appearance(false)
                        .cleanable(false)
                        .h(px(24.))
                        .w_full()
                        .text_size(px(12.))
                        .bg(rgb(0x4b4b4b)),
                ),
            )
            .when(self.fixed_slot, |d| {
                let pd = self.param_def(self.exposure_idx, 0);
                d.child(
                    div()
                        .w_full()
                        .h(px(56.))
                        .flex()
                        .flex_col()
                        .justify_center()
                        .bg(rgb(C_PANEL))
                        .border_t(px(1.))
                        .border_b(px(1.))
                        .border_color(rgb(C_BORDER))
                        .child(self.slider_row(self.exposure_idx, 0, &pd, false, cx, true)),
                )
            })
            .child(div().id("modules").flex_1().min_h(px(0.)).overflow_y_scroll().track_scroll(&self.modules_scroll).children(items))
    }

    fn module_view(&self, i: usize, cx: &mut Context<Self>) -> AnyElement {
        let m = &self.modules[i];
        let d = &self.defs[m.def];
        let name = d.name;
        let enabled = m.enabled;
        let expanded = m.expanded;
        let header = div()
            .id(("mh", i))
            .role(Role::Button)
            .aria_label(name)
            .h(px(32.))
            .w_full()
            .px(px(6.))
            .flex()
            .items_center()
            .gap(px(6.))
            .bg(rgb(C_PANEL))
            .border_b(px(1.))
            .border_color(rgb(0x505050))
            .cursor_pointer()
            .child(
                div()
                    .id(("pwr", i))
                    .w(px(14.))
                    .h(px(14.))
                    .rounded_full()
                    .border(px(2.))
                    .border_color(rgb(if enabled { 0xf1f1f1 } else { 0x8a8a8a }))
                    .bg(rgb(if enabled { 0xf1f1f1 } else { 0x5e5e5e }))
                    .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, _, cx| {
                        this.modules[i].enabled = !this.modules[i].enabled;
                        let name = this.defs[this.modules[i].def].name;
                        this.commit("on/off", name.to_string());
                        cx.notify();
                    })),
            )
            .child(div().min_w(px(0.)).truncate().text_size(px(13.)).child(name))
            .when(marker_on(), |d| d.child(div().w(px(((self.renders % 16) as f32) * 6.0)).h(px(6.)).bg(rgb(0x34c759))))
            .child(div().flex_1())
            .child(icon_btn("☰", cx.listener(move |this, _, _, cx| {
                let name = this.defs[this.modules[i].def].name;
                this.commit("preset", name.to_string());
                cx.notify();
            })))
            .child(icon_btn("⟲", cx.listener(move |this, _, _, cx| {
                let def = this.modules[i].def;
                let defaults: Vec<f32> = this.defs[def].params.iter().map(|p| p.default).collect();
                let n = this.defs[def].params.len();
                this.modules[i].params[..n].copy_from_slice(&defaults);
                let name = this.defs[def].name;
                this.commit("reset", name.to_string());
                cx.notify();
            })))
            .child(icon_btn("◫", cx.listener(move |this, _, _, cx| {
                this.modules[i].instances = this.modules[i].instances % 3 + 1;
                cx.notify();
            })))
            .child(div().text_size(px(10.)).text_color(rgb(C_DIM)).child(if expanded { "▾" } else { "▸" }))
            .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, _, cx| {
                this.modules[i].expanded = !this.modules[i].expanded;
                cx.notify();
            }));

        let mut body = div().w_full().flex().flex_col().bg(rgb(C_BODY)).text_size(px(12.));
        if expanded {
            if self.timer_mode == Some(TimerMode::Text) && i == self.exposure_idx {
                body = body.child(
                    div()
                        .h(px(60.))
                        .w_full()
                        .px(px(6.))
                        .flex()
                        .items_center()
                        .child(
                            div()
                                .font_family("Menlo")
                                .text_size(px(48.))
                                .text_color(rgb(C_TEXT))
                                .child(format!("tick {:02}", self.tick)),
                        ),
                );
            }
            if d.icons {
                let icons: Vec<AnyElement> = ["camera", "picker", "sliders", "light", "person"]
                    .iter()
                    .enumerate()
                    .map(|(k, label)| {
                        let on = self.modules[i].icons == k;
                        div()
                            .w(px(26.))
                            .h(px(22.))
                            .flex()
                            .items_center()
                            .justify_center()
                            .text_size(px(10.))
                            .when(on, |x| x.bg(rgb(0x8a8a8a)))
                            .id(("wbicon", k))
                            .hover(|x| x.bg(rgb(0x999999)))
                            .cursor_pointer()
                            .child(label[0..1].to_uppercase())
                            .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, _, cx| {
                                this.modules[i].icons = k;
                                cx.notify();
                            }))
                            .into_any_element()
                    })
                    .collect();
                body = body.child(div().h(px(26.)).w_full().flex().items_center().gap(px(2.)).px(px(4.)).children(icons));
            }
            if !d.tabs.is_empty() {
                let tabs: Vec<AnyElement> = d
                    .tabs
                    .iter()
                    .enumerate()
                    .map(|(k, t)| {
                        let on = self.modules[i].active_tab == k;
                        div()
                            .px(px(4.))
                            .h(px(22.))
                            .text_size(px(11.))
                            .when(on, |x| x.border_b(px(2.)).border_color(rgb(0xf1f1f1)))
                            .id(("tab", k))
                            .text_color(rgb(if on { C_TEXT } else { C_DIM }))
                            .cursor_pointer()
                            .child(*t)
                            .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, _, cx| {
                                this.modules[i].active_tab = k;
                                cx.notify();
                            }))
                            .into_any_element()
                    })
                    .collect();
                body = body.child(div().h(px(24.)).w_full().flex().items_center().gap(px(8.)).px(px(6.)).children(tabs));
            }
            if d.curve {
                let curve = canvas(
                    |_b, _, _| (),
                    |b, _, window, _cx| {
                        window.paint_quad(quad(b, 0x4b4b4b));
                        let mut x = b.origin.x;
                        while x < b.origin.x + b.size.width {
                            window.paint_quad(quad(Bounds::new(point(x, b.origin.y), size(px(1.), b.size.height)), 0x3f3f3f));
                            x += px(24.);
                        }
                        let mut y = b.origin.y;
                        while y < b.origin.y + b.size.height {
                            window.paint_quad(quad(Bounds::new(point(b.origin.x, y), size(b.size.width, px(1.))), 0x3f3f3f));
                            y += px(24.);
                        }
                        let mut path = PathBuilder::stroke(px(2.));
                        let curve_f = |t: f32| {
                            let s = 1.0 / (1.0 + (-(t - 0.5) * 8.0).exp());
                            s * 0.92 + 0.04
                        };
                        let steps = 48;
                        for i in 0..=steps {
                            let t = i as f32 / steps as f32;
                            let xx = b.origin.x + px(2.) + (b.size.width - px(4.)) * t;
                            let yy = b.origin.y + b.size.height - px(2.) - (b.size.height - px(4.)) * curve_f(t);
                            if i == 0 {
                                path.move_to(point(xx, yy));
                            } else {
                                path.line_to(point(xx, yy));
                            }
                        }
                        if let Ok(p) = path.build() {
                            window.paint_path(p, rgb(0xe8e8e8));
                        }
                        window.paint_quad(quad(
                            Bounds::new(
                                point(b.origin.x + b.size.width * 0.5 - px(3.), b.origin.y + b.size.height * 0.45 - px(3.)),
                                size(px(6.), px(6.)),
                            ),
                            0xd6a24a,
                        ));
                    },
                )
                .h(px(110.))
                .w_full()
                .p(px(6.));
                body = body.child(curve);
            }
            for (c, combo) in d.combos.iter().enumerate() {
                let selected = self.modules[i].combos[c];
                let selected_label = combo.options[selected.min(combo.options.len() - 1)];
                body = body.child(
                    div()
                        .h(px(30.))
                        .w_full()
                        .px(px(6.))
                        .flex()
                        .items_center()
                        .gap(px(6.))
                        .child(div().text_color(rgb(C_DIM)).child(combo.name))
                        .child(div().flex_1())
                        .child(
                            div()
                                .id(("combo", c))
                                .px(px(6.))
                                .h(px(22.))
                                .flex()
                                .items_center()
                                .gap(px(6.))
                                .bg(rgb(C_BODY))
                                .cursor_pointer()
                                .child(selected_label)
                                .child("▾")
                                .on_mouse_down(MouseButton::Left, cx.listener(move |this, ev: &MouseDownEvent, _, cx| {
                                    this.combo = Some(ComboOpen {
                                        module: i,
                                        combo: c,
                                        x: ev.position.x / px(1.0) - 150.0,
                                        y: ev.position.y / px(1.0) + 10.0,
                                        query: String::new(),
                                        sel: 0,
                                    });
                                    cx.notify();
                                })),
                        ),
                );
            }
            for (t, (label, _)) in d.toggles.iter().enumerate() {
                let on = self.modules[i].toggles[t];
                body = body.child(
                    div()
                        .h(px(26.))
                        .w_full()
                        .px(px(6.))
                        .flex()
                        .items_center()
                        .gap(px(6.))
                        .cursor_pointer()
                        .child(div().w(px(12.)).h(px(12.)).border(px(1.)).border_color(rgb(0xbbbbbb)).bg(rgb(if on { 0xdddddd } else { 0x666666 })))
                        .child(div().text_size(px(11.)).child(*label))
                        .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, _, cx| {
                            this.modules[i].toggles[t] = !this.modules[i].toggles[t];
                            let name = this.defs[this.modules[i].def].name;
                            this.commit("toggle", name.to_string());
                            cx.notify();
                        })),
                );
            }
            for (pi, pd) in d.params.iter().enumerate() {
                body = body.child(self.slider_row(i, pi, pd, false, cx, false));
                if self.timer_mode == Some(TimerMode::Text) && i == self.exposure_idx && pi == 0 {
                    body = body.child(
                        div()
                            .h(px(60.))
                            .w_full()
                            .px(px(6.))
                            .flex()
                            .items_center()
                            .child(
                                div()
                                    .font_family("Menlo")
                                    .text_size(px(48.))
                                    .text_color(rgb(C_TEXT))
                                    .child(format!("tick {:02}", self.tick)),
                            ),
                    );
                }
            }
            for b in &d.buttons {
                let label = *b;
                body = body.child(
                    div()
                        .h(px(24.))
                        .mx(px(6.))
                        .my(px(3.))
                        .flex()
                        .items_center()
                        .justify_center()
                        .border(px(1.))
                        .border_color(rgb(0x8a8a8a))
                        .bg(rgb(0x6e6e6e))
                        .text_size(px(11.))
                        .cursor_pointer()
                        .hover(|x| x.bg(rgb(0x7a7a7a)))
                        .child(label)
                        .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, _, cx| {
                            this.commit("action", label.to_string());
                            cx.notify();
                        })),
                );
            }
            let adv = d.adv.clone();
            if !adv.is_empty() {
                let open = self.modules[i].advanced;
                body = body.child(
                    div()
                        .h(px(22.))
                        .w_full()
                        .px(px(6.))
                        .flex()
                        .items_center()
                        .gap(px(6.))
                        .cursor_pointer()
                        .text_size(px(11.))
                        .text_color(rgb(C_DIM))
                        .child(if open { "▾ more settings" } else { "▸ more settings" })
                        .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, _, cx| {
                            this.modules[i].advanced = !this.modules[i].advanced;
                            cx.notify();
                        })),
                );
                if open {
                    let base = self.defs[self.modules[i].def].params.len();
                    for (k, pd) in adv.iter().enumerate() {
                        body = body.child(self.slider_row(i, base + k, pd, true, cx, false));
                    }
                }
            }
            body = body.child(
                div()
                    .h(px(20.))
                    .w_full()
                    .px(px(6.))
                    .flex()
                    .items_center()
                    .gap(px(10.))
                    .text_size(px(10.))
                    .text_color(rgb(0x8a8a8a))
                    .child("✕")
                    .child("○")
                    .child("↺")
                    .child("⊞")
                    .child("⤢")

                    .child("☰"),
            );
        }

        div()
            .w_full()
            .flex()
            .flex_col()
            .border_b(px(1.))
            .border_color(rgb(C_BORDER))
            .child(header)
            .child(body)
            .into_any_element()
    }

    fn slider_row(&self, module: usize, param: usize, pd0: &ParamDef, advanced: bool, cx: &mut Context<Self>, fixed: bool) -> AnyElement {
        let pd = *pd0;
        let value = self.modules[module].params[param];
        let frac = value_to_frac(value, &pd).clamp(0.0, 1.0);
        let bounds_cell: Rc<Cell<Bounds<Pixels>>> = Rc::new(Cell::new(Bounds::default()));
        let cell = bounds_cell.clone();
        let label = pd.name;
        let text = fmt_value(value, &pd);
        let hot = self.drag.as_ref().map(|d| d.module == module && d.param == param).unwrap_or(false);
        let fill = if hot { C_FILL_HOT } else { C_FILL };
        let mode = if module == self.exposure_idx && param == 0 { self.slider_mode } else { SliderMode::Canvas };
        let map_module = if fixed { module + 100 } else { module };

        let track: AnyElement = match mode {
            SliderMode::Div => div()
                .w_full()
                .h(px(12.))
                .relative()
                .child(div().absolute().left(px(0.)).top(px(3.)).w_full().h(px(7.)).bg(rgb(C_TRACK)))
                .child(div().absolute().left(px(0.)).top(px(3.)).w(relative(frac)).h(px(7.)).bg(rgb(fill)))
                .child(
                    div()
                        .absolute()
                        .left(relative(frac))
                        .top(px(1.))
                        .ml(px(-4.))
                        .text_size(px(9.))
                        .text_color(rgb(0xf2f2f2))
                        .child("▼"),
                )
                .into_any_element(),
            SliderMode::DivFlow => div()
                .w_full()
                .h(px(12.))
                .relative()
                .child(
                    div()
                        .w_full()
                        .h(px(12.))
                        .flex()
                        .flex_row()
                        .items_start()
                        .child(div().w(relative(frac)).h(px(7.)).mt(px(3.)).bg(rgb(fill)))
                        .child(div().flex_1().h(px(7.)).mt(px(3.)).bg(rgb(C_TRACK))),
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
                )
                .into_any_element(),
            SliderMode::Kit => {
                let logged = Rc::new(Cell::new(-1.0e9f32));
                let state = self.slider_state.clone().expect("kit slider state");
                let label_owned = label.to_string();
                div()
                    .w_full()
                    .h(px(24.))
                    .child(Slider::new(&state).accessibility_label(label_owned))
                    .on_children_prepainted(move |b, _, _| {
                        if let Some(first) = b.first() {
                            let y = first.origin.y / px(1.0);
                            if (y - logged.get()).abs() > 0.5 && dbg_on() {
                                logged.set(y);
                                eprintln!("KIT_TRACK_BOUNDS t={:.1} origin=({:.1},{:.1}) size={:.1}x{:.1}", tt(), first.origin.x / px(1.0), y, first.size.width / px(1.0), first.size.height / px(1.0));
                            }
                        }
                    })
                    .into_any_element()
            }
            SliderMode::Canvas => div()
                .w_full()
                .h(px(12.))
                .relative()
                .child(
                    canvas(
                        move |b, _, _| { cell.set(b); if dbg_on() { let mut m = SLIDER_MAP.lock().unwrap(); if m.insert((map_module, param)) { eprintln!("SLIDER_BOUNDS t={:.1} m={} p={} fixed={} origin=({:.1},{:.1}) size={:.1}x{:.1}", tt(), module, param, fixed as u8, b.origin.x / px(1.0), b.origin.y / px(1.0), b.size.width / px(1.0), b.size.height / px(1.0)); } } },
                        move |b, _, window, _cx| {
                            if dbg_on() && module == 11 && param == 0 {
                                eprintln!("CANVAS_PAINT t={:.1} frac={:.4} y={:.1} x={:.1} w={:.1} fixed={}", tt(), frac, b.origin.y / px(1.0), b.origin.x / px(1.0), b.size.width / px(1.0), fixed as u8);
                            }
                            let bar = Bounds::new(point(b.origin.x, b.origin.y + px(3.)), size(b.size.width, px(7.)));
                            window.paint_quad(quad(bar, C_TRACK));
                            let fillw = b.size.width * frac;
                            window.paint_quad(quad(Bounds::new(bar.origin, size(fillw, px(7.))), fill));
                            let x = b.origin.x + fillw;
                            let mut path = PathBuilder::fill();
                            path.move_to(point(x - px(4.), b.origin.y + px(2.)));
                            path.line_to(point(x + px(4.), b.origin.y + px(2.)));
                            path.line_to(point(x, b.origin.y + px(8.)));
                            path.close();
                            if let Ok(p) = path.build() {
                                window.paint_path(p, rgb(0xf2f2f2));
                            }
                        },
                    )
                    .absolute()
                    .size_full(),
                )
                .into_any_element(),
        };

        let row = div()
            .w_full()
            .h(px(40.))
            .px(px(6.))
            .flex()
            .flex_col()
            .justify_center()
            .pr(px(10.))
            .when(advanced, |d| d.bg(rgb(0x616161)))
            .id(("slider", module * 1000 + param + if fixed { 1_000_000 } else { 0 }))
            .role(Role::Slider)
            .aria_label(label)
            .aria_numeric_value(value as f64)
            .aria_min_numeric_value(pd.min as f64)
            .aria_max_numeric_value(pd.max as f64)
            .child(
                div()
                    .w_full()
                    .flex()
                    .items_center()
                    .child(div().text_size(px(12.)).text_color(rgb(C_DIM)).child(label))
                    .child(div().flex_1())
                    .child(div().text_size(px(12.)).font_family("Menlo").text_color(rgb(C_TEXT)).child(text)),
            )
            .child(track);

        let row = if mode == SliderMode::Kit {
            row.on_mouse_down(MouseButton::Left, cx.listener(move |_this, ev: &MouseDownEvent, _, _cx| {
                if dbg_on() {
                    eprintln!("KIT_ROW_DOWN t={:.1} pos={:.1},{:.1}", tt(), ev.position.x / px(1.0), ev.position.y / px(1.0));
                }
            }))
        } else {
            row.on_mouse_down(MouseButton::Left, cx.listener(move |this, ev: &MouseDownEvent, window, cx| {
                window.focus(&this.editor_focus, cx);
                if ev.click_count >= 2 {
                    this.reset_param(module, param, cx);
                    return;
                }
                let b = if mode == SliderMode::Div || mode == SliderMode::DivFlow {
                    Bounds::new(point(px(1167.), ev.position.y), size(px(263.), px(12.)))
                } else {
                    bounds_cell.get()
                };
                let local = (ev.position.x - b.origin.x) / px(1.0);
                let width = b.size.width / px(1.0);
                let f = (local / width.max(1.0)).clamp(0.0, 1.0);
                let v = frac_to_value(f, &pd);
                if dbg_on() {
                    eprintln!("SLIDER_DOWN t={:.1} m={} p={} fixed={} bounds=({:.1},{:.1} {:.1}x{:.1}) pos={:.1},{:.1} f={:.4} v={:.4}", tt(), module, param, fixed as u8, b.origin.x / px(1.0), b.origin.y / px(1.0), b.size.width / px(1.0), b.size.height / px(1.0), ev.position.x / px(1.0), ev.position.y / px(1.0), f, v);
                }
                this.modules[module].params[param] = v;
                this.drag = Some(DragState {
                    module,
                    param,
                    start_x: ev.position.x / px(1.0),
                    start_value: v,
                    width,
                    moved: false,
                });
                cx.notify();
            }))
            .on_mouse_down(MouseButton::Right, cx.listener(move |this, ev: &MouseDownEvent, _, cx| {
                this.combo = None;
                this.menu = Some(MenuState { x: ev.position.x / px(1.0), y: ev.position.y / px(1.0), module, param });
                cx.notify();
            }))
            .on_scroll(cx.listener(move |this, ev: &ScrollEvent, _, cx| {
                let dy = match ev.delta { ScrollDelta::Pixels(p) => p.y / px(1.0), ScrollDelta::Lines(p) => p.y * 24.0 };
                if dy.abs() < 0.01 {
                    return;
                }
                let dir = -dy.signum();
                let mult = if ev.modifiers.shift { 0.1 } else { 1.0 };
                let cur = this.modules[module].params[param];
                this.modules[module].params[param] = (cur + dir * pd.step * mult).clamp(pd.min, pd.max);
                cx.notify();
            }))
        };
        row.into_any_element()
    }

    fn overlays(&self, cx: &mut Context<Self>) -> Vec<AnyElement> {
        let mut out: Vec<AnyElement> = Vec::new();
        if let Some(menu) = &self.menu {
            let (m, p, x, y) = (menu.module, menu.param, menu.x, menu.y);
            let names = ["Reset", "Type value…", "Preset: neutral", "Preset: strong"];
            let menu_items: Vec<AnyElement> = names
                .iter()
                .enumerate()
                .map(|(k, label)| {
                    let label = *label;
                    div()
                        .h(px(22.))
                        .w_full()
                        .px(px(8.))
                        .flex()
                        .items_center()
                        .text_size(px(12.))
                        .text_color(rgb(C_TEXT))
                        .hover(|d| d.bg(rgb(0x8a8a8a)))
                        .cursor_pointer()
                        .child(label)
                        .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, window, cx| {
                            match k {
                                0 => this.reset_param(m, p, cx),
                                1 => {
                                    this.edit = Some(EditState { x, y, module: m, param: p });
                                    let cur = this.modules[m].params[p];
                                    this.value_input.update(cx, |st, cx| {
                                        st.set_value(format!("{}", cur), window, cx);
                                        st.select_all(window, cx);
                                    });
                                    let fh = this.value_input.read(cx).focus_handle(cx);
                                    window.focus(&fh, cx);
                                }
                                2 | _ => {
                                    let pd = this.param_def(m, p);
                                    let add = if k == 2 { 0.1 } else { 0.3 };
                                    this.modules[m].params[p] = (pd.default + (pd.max - pd.min) * add).clamp(pd.min, pd.max);
                                    let name = this.defs[this.modules[m].def].name;
                                    this.commit("preset", format!("{} · {}", name, pd.name));
                                }
                            }
                            this.menu = None;
                            cx.notify();
                        }))
                        .into_any_element()
                })
                .collect();
            out.push(
                div()
                    .id("menu-backdrop")
                    .absolute()
                    .left(px(0.))
                    .top(px(0.))
                    .size_full()
                    .occlude()
                    .on_mouse_down(MouseButton::Left, cx.listener(|this, _, _, cx| {
                        this.menu = None;
                        this.combo = None;
                        cx.notify();
                    }))
                    .into_any_element(),
            );
            out.push(
                div()
                    .absolute()
                    .left(px(x))
                    .top(px(y))
                    .w(px(170.))
                    .bg(rgb(0x6a6a6a))
                    .border(px(1.))
                    .border_color(rgb(0x9a9a9a))
                    .flex()
                    .flex_col()
                    .py(px(2.))
                    .occlude()
                    .children(menu_items)
                    .into_any_element(),
            );
        }
        if let Some(combo) = &self.combo {
            let d = &self.defs[self.modules[combo.module].def];
            let cd = d.combos[combo.combo];
            let q = combo.query.to_lowercase();
            let opts: Vec<(usize, &str)> = cd
                .options
                .iter()
                .enumerate()
                .filter(|(_, o)| q.is_empty() || o.to_lowercase().contains(&q))
                .map(|(i, o)| (i, *o))
                .collect();
            let sel = combo.sel.min(opts.len().saturating_sub(1));
            let (x, y, m, c) = (combo.x, combo.y, combo.module, combo.combo);
            let query_shown = combo.query.clone();
            let rows: Vec<AnyElement> = opts
                .iter()
                .enumerate()
                .map(|(k, (oi, label))| {
                    let oi = *oi;
                    div()
                        .h(px(20.))
                        .w_full()
                        .px(px(6.))
                        .flex()
                        .items_center()
                        .text_size(px(12.))
                        .when(k == sel, |x| x.bg(rgb(0x8a8a8a)))
                        .id(("opt", k))
                        .cursor_pointer()
                        .child(*label)
                        .on_mouse_down(MouseButton::Left, cx.listener(move |this, _, _, cx| {
                            this.modules[m].combos[c] = oi;
                            let name = this.defs[this.modules[m].def].name;
                            let cname = this.defs[this.modules[m].def].combos[c].name;
                            this.commit("combo", format!("{} · {}", name, cname));
                            this.combo = None;
                            cx.notify();
                        }))
                        .into_any_element()
                })
                .collect();
            out.push(
                div()
                    .id("combo-backdrop")
                    .absolute()
                    .left(px(0.))
                    .top(px(0.))
                    .size_full()
                    .occlude()
                    .on_mouse_down(MouseButton::Left, cx.listener(|this, _, _, cx| {
                        this.combo = None;
                        cx.notify();
                    }))
                    .into_any_element(),
            );
            out.push(
                div()
                    .absolute()
                    .left(px(x))
                    .top(px(y))
                    .w(px(200.))
                    .bg(rgb(0x6a6a6a))
                    .border(px(1.))
                    .border_color(rgb(0x9a9a9a))
                    .flex()
                    .flex_col()
                    .occlude()
                    .child(
                        div()
                            .h(px(22.))
                            .px(px(6.))
                            .flex()
                            .items_center()
                            .bg(rgb(0x4b4b4b))
                            .text_size(px(11.))
                            .text_color(rgb(C_DIM))
                            .child(if query_shown.is_empty() { "type to search".to_string() } else { query_shown }),
                    )
                    .children(rows)
                    .into_any_element(),
            );
        }
        if let Some(edit) = &self.edit {
            let (x, y) = (edit.x, edit.y);
            out.push(
                div()
                    .absolute()
                    .left(px(x))
                    .top(px(y))
                    .w(px(150.))
                    .bg(rgb(0x6a6a6a))
                    .border(px(1.))
                    .border_color(rgb(0x9a9a9a))
                    .p(px(4.))
                    .occlude()
                    .child(
                        TextInput::new(&self.value_input)
                            .appearance(false)
                            .h(px(22.))
                            .w_full()
                            .text_size(px(12.))
                            .bg(rgb(0x4b4b4b)),
                    )
                    .into_any_element(),
            );
        }
        out
    }
}

fn icon_btn(label: &'static str, handler: impl Fn(&MouseDownEvent, &mut Window, &mut App) + 'static) -> impl IntoElement {
    div()
        .w(px(16.))
        .h(px(16.))
        .flex()
        .items_center()
        .justify_center()
        .text_size(px(10.))
        .text_color(rgb(C_DIM))
        .cursor_pointer()
        .hover(|d| d.bg(rgb(0x777777)).text_color(rgb(0xffffff)))
        .child(label)
        .on_mouse_down(MouseButton::Left, handler)
}

fn main() {
    gpui_kit::application().run(|cx| {
        gpui_kit::init(cx);
        cx.bind_keys([KeyBinding::new("enter", ConfirmCombo, None)]);
        Theme::change(ThemeMode::Dark, None, cx);
        let bounds = Bounds { origin: point(px(32.), px(30.)), size: size(px(1440.), px(816.)) };
        let options = WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: None,
            focus: true,
            show: true,
            ..Default::default()
        };
        let defs = module_defs();
        gpui_kit::open_window(options, cx, move |window, cx| cx.new(|cx| Proto::new(defs, window, cx)))
            .expect("open window");
        cx.activate(true);
        println!("LAYOUT window=1440x846 origin=32,0 left=280 right_panel_x=1160 top_bar=34 filmstrip_h=104");
    });
}
