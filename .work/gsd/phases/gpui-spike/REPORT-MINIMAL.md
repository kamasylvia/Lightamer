# REPORT: minimal reproduction — does the plain gpui/gpui-kit writing lose frames under a non-zero scroll offset?

日期 2026-11-25 · 仓内开工 HEAD `4285f69e380227360b89ef5bcda302ed8c0ae5bb` · 最小程序在仓外 `/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike/{minimal,upstream}` · 探针 `measure/FrameProbe.swift`（判据不变：`cells>=1 && maxd>=10`）· 产品树零改动

## 0. Verdict

**最普通的写法下现象不在。** 600×600 窗口、400 px 宽 `overflow_y_scroll` 容器、80 行 40 px 的普通 `div`、第 20 行放被测控件、`ScrollHandle::set_offset(-600)`、定时器每 16 ms 改值 40 次：M1（纯 div 宽度）/ M2（canvas 矩形）/ M3（gpui-kit `Progress`）/ M4（gpui-kit `Slider` + `set_value`）全部在偏移 600 下持续上屏，变化帧 36–40/40，应用内每 tick 都重绘。偏移 0（C1）与容器外固定区（C2）同样上屏。

| 问题 | 结论 |
|---|---|
| 是不是 gpui-kit 这套 gpui 的通病 | **不是**。同一依赖（`gpui-kit 0.11.0` / `gpui-pre 0.3.14`）、同一探针、同一台机器，最普通的写法 37/40 帧（M1）。 |
| 是不是上游 gpui 的问题 | **不是**。`gpui 0.2.2`（Zed 发布）：U-M1 偏移 600 = **37/40**、U-C1 偏移 0 = **37/40**，与 gpui-kit 组同值。 |
| 那前五轮的结论怎么算 | **改写**：现象是**原型特定结构/写法触发**的，不是「滚动子树内非文本绘制」这一类的框架通病。前五轮全部在同一个 1600 行原型上取得，没有独立最小对照；本轮补上了这个对照，结论相反。 |
| 现象在不在 | 最小程序里**不在**。M1–M4 在偏移 600 全部上屏；C1/C2 也上屏。 |

最小程序与原型共享了此前被指为根因的全部要素——单一实体、`overflow_y_scroll`、非零偏移、`cx.notify()`、canvas / div 几何变化、定时器驱动——仍然正常。因此这些要素**单独不足以**触发；触发点落在原型多出来而最小程序没有的东西上（§3 嫌疑清单）。

置信度：M1–M4/C1/C2 的帧数与延迟 = **高**（探针判据与时钟对齐均实测，见 §1 方法）；「上游 gpui 也没有」= **高**（同探针、同脚本、同窗口尺寸，两情形各 37/40）；「原型里到底是哪一处」= **未定位**（§5）。

## 1. Numbers

方法：应用在 `render()` 里自增重绘计数，在每次定时器更新时把 `mach_absolute_time`（= `CMClockGetHostTimeClock` 秒，实测差 4 µs）与计数写 stderr；探针录 SCK 窗口帧（`F pts cb diff maxd cells`）。两边同一时基，逐个 tick 取「其后第一个变化帧」算延迟。无任何合成输入（探针脚本只有 `wait 6000`，`--activate` 只激活窗口）。窗口实测 600×632（含 32 px 标题栏），60 Hz，探针 `scalesToFit=false`、`minimumFrameInterval=1/120`。

| # | 情形 | 被测控件 | 偏移 | 变化帧 / 40 | 每 tick→变化帧中位 | p95 / max | 应用内重绘 | 截图 |
|---|---|---|---|---|---|---|---|---|
| M1 | 纯 div 宽度 10%→90% | `div().w(relative(frac)).bg(...)` | 600 | **37**（55.6 fps） | **1.2 ms** | 22.2 / 56.9 ms | 39 | `shots/minimal/M1-mid.png` |
| M2 | gpui canvas 矩形宽度 10%→90% | `canvas` + `window.paint_quad` | 600 | **36**（54.7 fps） | **12.4 ms** | 31.0 / 62.2 ms | 39 | `shots/minimal/M2-mid.png` |
| M3 | gpui-kit `Progress` 0→100 | `Progress::new(..).value(v*100)` | 600 | **40**（60.0 fps） | **9.9 ms** | 98.9 / 131.2 ms | 40 | `shots/minimal/M3-mid.png` |
| M4 | gpui-kit `Slider` 0→1 | `SliderState::set_value`（timer 调用） | 600 | **39**（58.5 fps） | **5.9 ms** | 36.7 / 69.0 ms | 39 | `shots/minimal/M4-mid.png` |
| C1 | M1 在偏移 0 | 同上（第 1 行，见 §2 偏差） | 0 | **37**（56.9 fps） | −0.5 ms¹ | 17.0 / 49.4 ms | 39 | `shots/minimal/C1-mid.png` |
| C2 | M1 在滚动容器外固定区 | 同上，右侧 200 px 面板 | 600 | **19**（28.7 fps）² | **15.6 ms** | 37.2 / 54.1 ms | 39 | `shots/minimal/C2-mid.png` |
| U-M1 | 上游 `gpui 0.2.2`，M1 | 同 M1（无 gpui-kit） | 600 | **37**（54.9 fps） | −0.4 ms¹ | 16.6 / 39.2 ms | 39 | `shots/minimal/U-M1-mid.png` |
| U-C1 | 上游 `gpui 0.2.2`，C1 | 同上 | 0 | **37**（56.9 fps） | −0.4 ms¹ | 16.9 / 31.9 ms | 39 | `shots/minimal/U-C1-mid.png` |

¹ 负值来自判据窗口的 −2 ms 容差（前一帧已在上屏、与本次 tick 相差 <2 ms），不是丢帧；该情形 40/40 tick 都有对应变化帧。
² C2 的条宽只有 200 px，每 tick 位移 ~4.6 px，小于探针 80×45 网格的 7.5 px 采样间距；**40/40 个 tick 都匹配到了变化帧**，19 是「不同帧数」，不是「没上屏」。M1/M2 的 36–37 同理：变化帧率 ≈ 55–60 fps，缺的 1–3 个是网格阈值下的采样抖动，不是 0 帧级失败。

逐情形证据：`traces/minimal/{M1,M2,M3,M4,C1,C2}.{run,err}` 与 `{U-M1,U-C1}.{run,err}`；每情形一次运行。

**M3/M4 的混淆项（如实登记）**：`Progress` 内部有 `transition()` 数值过渡，`Slider` 内部有 spring 拇指环——两者都会在值变化时自行请求动画帧。它们在本轮的作用是「gpui-kit 组件在滚动子树里能上屏」，不能单独证明「静态几何」路径；静态几何由 M1/M2 证明。

## 2. 最小程序写法

仓外 crate `minimal/`，只依赖 `gpui-kit = "0.11.0"`（默认特性，即 `gpui-pre 0.3.14`）。`Cargo.toml` 照 `gpui-kit` README 的 `application()/init()/open_window` 示例；源码 320 行，**没有从原型 `src/main.rs` 复制任何控件代码**。

结构（`minimal/src/main.rs`）：

- 一个实体 `Minimal` 持有 `value`、`renders`、`ScrollHandle`、`Entity<SliderState>`；`Render for Minimal` 渲染整窗。
- 根：`div().size_full().flex().flex_row()`；左列 400 px `div().id("scroll-root").w(px(400.)).h_full().overflow_y_scroll().track_scroll(&scroll)`，右列 200 px 侧栏（C2 用）。
- 列表内容：`div().flex().flex_col()` + 80 个 `div().h(px(40.)).w_full().flex().flex_row().items_center()`，每行一个 `row NN` 文本；第 20 行（C1 为第 1 行）额外放被测控件。
- 定时器：`cx.spawn_in(window, async move |this, cx| { cx.background_executor().timer(2000ms).await; for n in 0..40 { this.update_in(cx, |this, window, cx| { this.value = v; /* M4: slider.update(cx, ..set_value(v, window, cx)) */ cx.notify(); }) ; timer(16ms).await; } })`。
- 偏移：另一条 `spawn_in` 任务在 200 ms 后 `scroll.set_offset(point(px(0.), px(-600.)))` + `cx.notify()`；C1 设 0。
- 诊断只写 stderr（`TICK`/`TICK_START`/`TICK_END`/`SCROLL_SET`/`CANVAS_PAINT`），**屏幕上没有任何随值变化的计数器/文本**，避免污染帧差。

不常见的写法（逐条标出）：

1. **用 `ScrollHandle::set_offset` 直接设偏移，而不是滚轮**。这是任务要求（禁合成输入），但也是与原型最大的方法差异：原型五轮的失败现场都是由 43 次合成滚轮事件滚出来的。若 bug 依赖「滚动事件路径留下的内部状态」，`set_offset` 不经过那条路径（§3.1）。
2. **用 `mach_absolute_time` 把应用日志与探针帧对齐**。因为禁合成输入，没法用 `move` 事件做时钟同步；改用同一 host clock（Swift 对照实测 `CMClockGetSeconds(CMClockGetTime(hostClock))` 与 `mach_absolute_time*timebase` 差 4 µs）。
3. **C1 的控件放在第 1 行而不是第 20 行**。偏移 0 时第 20 行（y=800）在 600 px 视口之外；放第 20 行测到的是「不可见元素」，不是「偏移 0」。C1 的容器、行高、控件、更新路径与 M1 相同，只改控件所在行。
4. **整窗一个实体、无子视图/无 `AnyView`/无 `Render for` 子组件**。原型也是单实体，所以这条不是差异，但它意味着本轮没有触到 gpui 的 view 级 retained 缓存路径。
5. **M3/M4 直接消费 gpui-kit 组件**（`Progress::new`、`Slider::new(&state)`），M4 的 `set_value` 在 timer 的 `update_in` 里调用（需要 `&mut Window`）。
6. `--activate` 只做窗口激活（`NSRunningApplication.activate`），不投递鼠标/键盘/滚轮事件。

构建：`cargo build --offline -j 6`（离线；依赖已在 registry 缓存），耗时 88 s，复用原型 `target/` 的依赖产物。

## 3. 和原型的差别（嫌疑清单）

最小程序**有**：单实体、`overflow_y_scroll`、`track_scroll`、非零偏移、`cx.notify()`、div 几何、canvas quad、gpui-kit Progress/Slider、16 ms 定时器、60 Hz 窗口。这些全部不足以触发。原型**多出**的东西，按可疑度排序：

1. **偏移是滚轮滚出来的，不是 `set_offset` 设的**。这是本轮唯一无法回避的方法差异（任务禁合成输入）。若触发点位于滚轮处理路径（滚动图层提升、惯性/事件泵、命中测试状态），最小程序天然测不到。**下一步第一优先**：用同一最小程序，改为合成 43 次 `scroll -14` 滚到 600 再测。
2. **行内交互与 hitbox**：原型每行 module header 有 `id` + `on_mouse_down`/`on_mouse_up`，整窗根还有 `on_mouse_move`/`on_mouse_up`/`on_mouse_down`；最小程序行内零交互（M4 的 Slider 自带除外）。hitbox/交互状态进入 prepaint/paint 路径，是「滚动子树内几何变化」与原型其他差异里最直接的一类。
3. **常驻 `TextInput`（IME 实体）**：原型面板顶部有 `InputState` 搜索框，窗口还有 `value_input`，根元素 `track_focus` + `on_key_down` + `on_action`；最小程序没有输入法/焦点实体。IME 平台接线可能改变帧调度或 present 路径。
4. **滚动容器的布局来源**：原型是 `flex_1().min_h(px(0.))` 在 280 px 宽 `flex_col` 面板里（高度由 flex 计算，带 border）；最小是固定 400×632。布局约束类型不同（flex 分配 vs 显式尺寸）。
5. **绘制复杂度**：原型 canvas 一次画 track quad + fill quad + `PathBuilder` 三角；div 臂（E4）用绝对定位叠层，kit 臂用 `on_children_prepainted` 取 bounds。最小 M2 只画一个 quad，M1 只有一个 in-flow div。
6. **几何尺度**：原型条高 7 px、轨道 263 px、每 tick 位移 2–3 px；最小 22 px 高、400 px 宽、每 tick ~8 px。若触发与「小面积/亚像素重绘」或场景包围盒有关，尺度可能是变量。
7. **场景规模**：原型 1440×816、30 个模块（多行、展开/折叠、条件渲染）、滚动内容 max 1576；最小 600×632、80 行纯文本、max 2600。元素/quad 数量差一个量级。
8. **overlay 尾巴**：原型根 children 末尾挂 `self.overlays(cx)`（菜单/编辑框/下拉，多数时刻为空）；最小没有 overlay 层。
9. **`render` 里读滚动状态**：原型每帧读 `modules_scroll.offset()` 并写 `Cell`；最小只在设置时读。读 scroll 状态本身可能影响 prepaint 顺序（未证）。
10. **标题栏/窗口样式**：原型 `titlebar: None`（自绘顶栏），最小用原生标题栏。与像素内容无关，列全。
11. **上游对照的做法**：`upstream/` crate 直接依赖 `gpui = "0.2.2"`，代码与 M1/C1 同构（去掉 gpui-kit 与 M2–M4/C2），`Cargo.lock` 独立。它证明「Zed 自己发布的 gpui 也没有这个现象」，同时也说明问题不在 gpui-kit 的封装层。

## 4. 对 #27 的含义

- **「gpui 在滚动子树里丢非文本绘制」不能作为选型结论**。最普通的写法（div/canvas/组件）在偏移 600 下 36–40/40 帧上屏；上游 `gpui 0.2.2` 的 M1 对照同为 37/40。前五轮的报告应改写为「原型特定结构触发，待定位」，而不是「框架重绘抑制」。
- **#27 的 UI 路线不被这个现象阻断**：滑杆/进度条可以用普通 div 或 canvas，不必为了「躲框架 bug」改成 gpui-kit 组件或每帧强制布局失效。
- **原型仍需回查**，但排查方向变了：优先做两个最小增量实验——(a) 用合成滚轮滚到 600（替代 `set_offset`）；(b) 给行加 `id` + `on_mouse_down`、根加 `on_mouse_move`。任一能复现，就把范围缩到该增量；两者都不复现，再往 TextInput/flex 布局/场景规模上加。
- **审慎边界**：本轮只证明「这些普通写法不触发」。它不证明 gpui 没有别的滚动相关缺陷，也不解释原型里那 24 次 render 对应 0 个变化帧的机制；原报告 §2.3 的 wgpu surface 候选仍未证伪，只是不再有「最小复现」支撑。

## 5. 未验项

1. **原型的具体触发点未定位**。§3 是嫌疑清单，不是已隔离的因果；没有做「给最小程序逐项加回原型特征」的实验（时间/范围）。
2. **滚轮路径未测**：本轮按任务要求只用 `set_offset`，未用合成滚轮；「滚轮滚出来的偏移」与「程序设的偏移」是否有别，未验。
3. **无重复运行**：每情形一次；变化帧数 36–40 的抖动未做多轮统计。
4. **探针分辨率**：C2 的 19 个不同变化帧是 200 px 宽、每 tick 4.6 px 位移低于网格采样间距所致；已用「每 tick 是否匹配到变化帧」补判（40/40），但更细的位移没有独立度量。
5. **M3/M4 内部动画混淆**：`Progress` 的 transition 与 `Slider` 的 spring 会自行请求动画帧；它们证明「组件能上屏」，不证明「静态几何能上屏」（后者由 M1/M2 证明）。
6. **窗口状态**：只测前台激活窗口；未测失焦、遮挡、最小化、多显示器/不同缩放。
7. **上游组只做 M1/C1**：未在上游 gpui 上跑 canvas/组件情形（任务只要求 M1/C1）。
8. **未测真实鼠标/触控板**：全部数值来自定时器 + SCK 帧流，符合本轮「不用合成输入」的约束。
