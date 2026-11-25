# REPORT: 面板滚动后拖滑杆不刷新（gpui 原型排障）

日期 2026-11-25 · 原型 `/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike`（仓外）· 产品树零改动 · 基座 `gpui-kit 0.11.0`（`gpui-pre 0.3.14` / `gpui-pre-macos 0.3.14` / `gpui-pre-wgpu 0.3.14`）· 判据与动作序列沿用补测 lane（`measure/FrameProbe.swift`，40 步 × 8 ms，`cells>=1 && maxd>=10`）。

## 0. Verdict

| 问题 | 结论 |
|---|---|
| 属于哪一类 | **重绘抑制（框架侧）**。事件投递、命中测试、坐标换算、值计算、`cx.notify()`、`render()`、canvas 绘制全部正常执行；滚过的面板里按住拖滑杆时，新画出的内容**到不了屏幕**。 |
| 是否已修 | **未修**。原型侧没有可改的业务代码（值、提交、最终画面都对），未找到不改变观感的绕过；标记实验只是诊断。 |
| 修前 | 偏移 98/602 拖同一滑杆：**1 个变化帧 / 0.68 s**（每步→画面变化中位 201–219 ms，最大 412 ms）。 |
| 修后 | 无（未修）。偏移 0 同一动作 **13–14 个变化帧**（≈20 fps，非 60）；加「每帧改宽度」的自诊断标记后 98/602 变为 20 / 12 帧，但标记本身即为可见变化，不能据此断言滑杆已恢复（见 §5）。 |

排除了三类：事件没到（到了，28–33/40，值逐步推进）、命中/坐标（命中 `m=11 p=0`，边界与窗口坐标一致）、探针（同一探针看得到滚动帧 68/68、看得到偏移 0 的拖动帧、看得到松手提交帧）。

## 1. 三个偏移位置对照

同一构建、同一滑杆（`exposure` 模块 `exposure` 参数，行 x 1167–1430，宽 263 pt，行高 40），同一 `drag 1267 <y> 1400 <y> 40 8`；偏移由 7 / 43 个 `scroll -14` 精确给出（stderr `SCROLL_OFFSET` 实测 98.0 / 602.0）。

| 列表偏移 | 应用内：收到 move / 应用值 / render | 变化帧（探针） | 每步→变化中位 / 最大 | 备注 |
|---|---|---|---|---|
| 0 | 29 / 28 / 25（drag 内） | **13**（0.70 s，18.6 fps；另一次 14） | 13.6 / 78.4 ms | 手指跟得上，但只有一半帧可见 |
| 98 | 33 / 33 / 24–25 | **1**（1.4 fps） | 201.2–219.3 / 412.5 ms | 全程只在松手后出一帧；全帧间隔仍 16.5 ms |
| 602 | 31 / 30 / 24 | **12**（17.4 fps，**加标记后**） | 16.1 / 68.5 ms | 无标记时为本轮补测 lane 的 1 帧 / 209.6 ms（`P30-drag`）；本轮无标记 602 轮因总偏移漂到 700 未命中，作废（见 §5） |

补充事实（同一批日志，`traces/P30d-inapp-counters.err`、`P30d-paint-counters.err`）：

- 40 个合成 `leftMouseDragged` 只有 **28–33 个**进入应用（位置单调、有跳号与重复），差值是 macOS/AppKit 的拖动事件合并；它不是本 bug 的主因——收到的事件每个都改了值，最终值精确（`+1.580 EV`，与 40 步终点一致）。
- 偏移 98 的拖动里 `renders_drag=25`，`CANVAS_PAINT` 打印的 `frac` 逐步推进（0.7000 → 0.7267 → 0.7517 → 0.7633 …），绘制坐标 `y=678.5`（滚动后的正确位置），而探针在该窗口 24 个 render 之间记录到 **0 个**像素变化。

## 2. 证据

### 2.1 事件与值（`src-copy/main.rs`：`on_mouse_move` 约 663 行）

```
MM t=54708.4 n=31 APPLY pos=1238.3,678.0 sx=1235.0 w=263.0 m=11 p=0 v=-1.3700 renders=38 renders_drag=25
MM t=55071.1 n=61 APPLY pos=1358.0,678.0 sx=1235.0 w=263.0 m=11 p=0 v=1.3600 renders=60 renders_drag=47
MM t=55100.4 n=63 APPLY pos=1368.0,678.0 sx=1235.0 w=263.0 m=11 p=0 v=1.5800 renders=62 renders_drag=49
DRAG_SUMMARY t=55100.6 mm_recv=63 mm_applied=61 mm_skip=0 renders=62 renders_drag=49 module=11 param=0 value=1.5800
```

`mm_skip=0`（没有 `pressed_button != Left` 的丢弃）；`pos` 是窗口坐标，`sx` 来自 mouse-down，两者同空间。

### 2.2 命中与坐标（`slider_row` 的 `on_mouse_down`）

```
SLIDER_DOWN t=25843.4 m=11 p=0 bounds=(1167.0,776.5 263.0x12.0) pos=1235.0,782.0 f=0.2586 v=-1.4500
```

偏移 0 时 track 在窗口 y 776.5；滚到 98 / 602 后同一控件在 678.5 / 174.5，mouse-down 命中的仍是 `m=11 p=0`。窗口坐标 = 全局坐标 − (32,30)，与 `frameprobe` 的 `--global` 投递一致，未混用内容坐标。

### 2.3 绘制与呈现（关键）

```
CANVAS_PAINT t=7432.9 frac=0.7000 y=678.5 x=1167.0 w=263.0     # 偏移 98，按钮按住期间
CANVAS_PAINT t=7468.2 frac=0.7517 y=678.5 x=1167.0 w=263.0
CANVAS_PAINT t=7483.5 frac=0.7633 y=678.5 x=1167.0 w=263.0
```

同一 run（`traces/P30d-off100.run`）的帧：drag 期间 24 个 render 对应帧 `maxd=0, cells=0`；唯一变化帧出现在 mouse-up 之后（`maxd=66, cells=1488`，整窗）。对照 `traces/P30d-off0b.run`：同一代码在偏移 0 时每步 `maxd=148, cells=1`（滑块填充边界一个格）。

框架侧相关位点（只读核对，未改依赖）：

- `gpui-pre-0.3.14/src/window.rs:6457` `dispatch_mouse_event`：每次事件先 `rendered_frame.hit_test(mouse_position())`；`on_mouse_move` 的 hover 判定即由此来（`elements/div.rs:303`）。命中链正常，故事件能到根 `on_mouse_move`。
- `gpui-pre-0.3.14/src/window.rs:2063-2085`：`should_draw = invalidator.is_dirty()` 时 `draw()` + `present()`；否则只 `present()`。偏移 98 的 24 次 render 说明 `draw` 在跑。
- `gpui-pre-wgpu-0.3.14/src/wgpu_renderer.rs:1088` `draw()`：`get_current_texture()` 返回 `Occluded` / `Timeout` 时**静默 `return false`**，`Window::present()`（`window.rs:4018`）忽略返回值。这是「画了但没上屏」的一个可落点；本轮没有把 surface 状态打出来，属未证实的候选（[INFERENCE]）。
- `gpui-pre-0.3.14/src/view.rs:549/639` 的 `reuse_prepaint` / `reuse_paint` 视图缓存：键含 `bounds/content_mask/text_style/opacity`，且要求视图不在 `dirty_views`。`notify` 后视图确在重绘（`render` 计数），故不是视图级缓存命中（已排除）。

### 2.4 探针自检

同一 `FrameProbe` 在同一次会话内：滚动段 7 个 `scroll` 事件产生 7 个变化帧（`cells` 134–150，整块面板位移）；偏移 0 拖动 13 帧；鼠标松开提交帧必现。抓帧区域 = `SCShareableContent` 的 `windowID`，非桌面区域。

## 3. 修了什么

无产品修复。已做的改动都在原型（仓外）且只为取数：

1. `on_mouse_move` / `on_mouse_up` / `render` / `slider_row` 加计数与 stderr 日志（`LIGHTAMER_MM_LOG=1` 开）。
2. `slider_row` 的 canvas paint 关闭里打 `frac` 与绘制坐标。
3. 诊断标记：顶栏与模块头各加一条宽度 = `renders % 16 * 6` 的色条。

第 3 项使偏移 98/602 的拖动帧数从 1 升到 20 / 12。它同时改变布局与像素，因此只能证明「按住拖动期间窗口是会被 present 的、滚过的子树也能更新」，**不能**证明 canvas 滑杆恢复。

## 4. 对 #27 的含义

- 这不是「写原型时注意一下」的用法问题：原型侧的命中、坐标、值、提交都正确；是**框架在滚动子树里对连续拖动的重绘抑制**（gpui-kit 0.11 / gpui-pre 0.3.14）。写原型时无法靠调整事件处理规避。
- 现阶段可用的工程结论：**用 canvas 自绘 + `overflow_y_scroll` + 按住拖动，三者同时出现时，不要假设 60 fps 跟手**；要么滑杆不用 canvas（等宽 div 填充 + 三角形用图片/文本），要么在拖动期间强制每帧布局失效（本轮标记的做法，但会引入 6 px 级抖动，不能进产品）。
- 上报材料：最小复现 = 本例 `main.rs`（30 模块、3 展开、滚 7×14 pt 后拖 exposure 滑杆）；现象 = draw/paint 有、上屏无；建议上游按「canvas 立即模式图元 + 非零 scroll offset + 按住拖动」复现。

## 5. 未验项

1. **滑杆本身是否随标记一起恢复**：标记帧与滑杆像素在同一次变化里，未做区域级差分（探针只给 `maxd/cells`，不给坐标）。
2. **偏移 602 的无标记复测**：本轮该轮在偏移 98 基础上又滚 602（总 700），`drag 1267 204` 未命中滑杆（无 `SLIDER_DOWN`），数据作废；602 的无标记结论仍引用补测 lane 的 `traces/P30-drag`（1 帧 / 209.6 ms）。
3. **框架内的确切一层**：是 `wgpu` surface 丢帧、present 事务未提交、还是 canvas 图元被上一帧缓存复用，未用依赖侧日志/调试器证实；`wgpu_renderer.rs:1088` 只是候选落点。
4. **是否与「按钮按住」强绑定**：只验证了按住拖动；未测「按住不动」「滚轮滚动中拖」等组合。
5. 未测不同面板高度 / 不同模块数下的阈值；未测真实鼠标（全部为 `CGEvent` 合成）。
6. 未做上游 issue 提交；未验证 gpui 更新版本是否已修。

## 附：本轮产物

- `traces/P30d-off0b.*`（偏移 0，无标记）、`P30d-off100.*`（偏移 98，无标记）、`P30d-marker98.*`（98，带标记）、`P30d-mark-off0.*` / `P30d-mark-off602.*`（带标记）。
- `traces/P30d-inapp-counters.err`（应用内计数 + 绘制日志）、`traces/P30d-paint-counters.err`（canvas 绘制日志）。
- `src-copy/main.rs` 已更新为最终测量版（含日志与标记；`LIGHTAMER_MM_LOG` 未设时只保留标记）。
