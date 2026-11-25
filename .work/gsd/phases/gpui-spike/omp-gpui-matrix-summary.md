# REPORT: 滚动面板「画了不上屏」的写法判别矩阵（gpui 原型）

日期 2026-11-25 · 仓内 HEAD `b4d01acfa342dec43eaef282e3dd48b111d99741` · 原型 `/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike`（仓外，产品树零改动）· 基座 `gpui-kit 0.11.0`（`gpui-pre 0.3.14`）· 探头 = `measure/FrameProbe.swift`（SCK 窗口帧流，60×60 网格，变化帧判据 `cells>=1 && maxd>=10`，沿用前两轮）。

## 0. Conclusion

**卡在「滚动子树内的非文本绘制」上。** 滚动偏移 ≠ 0 时，canvas 图元与 div 几何（填充宽、三角位置）的新画面都到不了屏幕；纯文本内容更新能上屏。不是鼠标/拖动的问题（E2 定时器同样 0 帧），不是 canvas 专属（E4 的 div 滑杆同样 1 帧），是滚动容器对子树内非文本绘制的呈现抑制。

| 问题 | 结论 |
|---|---|
| 卡在哪一类写法 | **滚动子树内 canvas 绘制 + div 几何变化**。文本内容在滚动子树内可正常上屏（E3 40/40 帧）。 |
| 有没有绕法 | 有，但只有一种实测可用：**gpui-kit 自带 `Slider`（E5，14/40 帧 ≈ 20 fps；3.6 s 长拖 29 帧 ≈ 8 fps）**。推断其原因是拇指 hover 环的 spring 在拖动期间持续 `request_animation_frame()`，把呈现泵撑住（源码 `gpui-base/src/motion.rs:721` 内 `window.request_animation_frame()`；未做隔离实验，标 [INFERENCE]）。纯 div 写法（E4/E4b）与 canvas 一样不行。 |
| 是否与「在滚动容器里」绑定 | **是**。同一 canvas 滑杆放在滚动容器外的固定区（E6）18/40 帧、每步中位 8.8 ms。 |
| 是否与滚动偏移绑定 | **是**。同一 canvas 滑杆定时器更新：偏移 0 时 39/40 帧（E7v），偏移 602 时 0/40 帧（E2）。 |
| 置信度 | 帧数/延迟：**高**（七项 + 两个变体，E1/E6 用最终二进制复跑一致）。E5 成功的原因：**中**（源码指向动画帧泵，未隔离）。 |

## 1. Matrix

同一窗口 1440×816、同一 30 模块面板；除 E7 外均滚到偏移 602（43 × `scroll -14`，stderr `SCROLL_OFFSET y=602.0`）。40 次更新；延迟 = 每次更新到其后第一个变化帧，取中位。

| # | 滚动面板里的东西 | 更新方式 | 变化帧 / 40 | 每更新→变化中位 | 应用内重绘次数 |
|---|---|---|---|---|---|
| E1 | 现有 canvas 滑杆（exposure） | 按住拖动 40 步 × 8 ms | **1**（0.70 s，1.4 fps） | **218.5 ms**（p95 393.6，max 412.5） | 25（`renders_drag`） |
| E2 | 现有 canvas 滑杆（exposure） | 定时器 16 ms 改值，40 次 | **0**（0.656 s） | 无变化帧可配（> 656 ms） | 39 |
| E3 | 普通文本标签（48 px，"tick 00"…"tick 39"） | 定时器 16 ms 改文字，40 次 | **40**（0.654 s，61.2 fps） | **9.8 ms**（p95 31.0，max 64.3） | 39 |
| E4 | div 拼的滑杆（绝对定位填充 `w(relative(frac))` + 文本三角 ▼） | 按住拖动 | **1**（0.702 s） | **205.1 ms**（p95 379.5，max 398.0） | 23 |
| E4b（额外变体） | div 滑杆，填充改为 **在流 flex 子项**（`fill w(relative) + remainder flex_1`） | 按住拖动 | **1**（0.699 s） | **221.6 ms**（p95 394.9，max 413.8） | 25 |
| E5 | gpui-kit 样式化 `Slider`（`gpui_kit::component::slider`） | 按住拖动 | **14**（0.703 s，19.9 fps） | **12.6 ms**（p95 48.3，max 57.2） | 未计数（见 §5.6） |
| E5-slow（额外） | 同上，长拖 40 步 × 80 ms（3.65 s） | 按住拖动 | **29**（8.0 fps；中点间隔 84 ms，max 415 ms） | 51.1 ms | 未计数 |
| E6 | 现有 canvas 滑杆，放在**滚动容器之外**的右侧固定条 | 按住拖动 | **18**（0.695 s，25.9 fps） | **8.8 ms**（p95 31.1，max 50.6） | 24 |
| E7v | E2 在偏移 0 重做（canvas + 定时器） | 定时器 | **39**（0.662 s，58.9 fps） | **9.2 ms**（p95 34.8） | 39 |
| E7t | E3 在偏移 0 重做（文本 + 定时器） | 定时器 | **24**（0.657 s，36.5 fps） | **11.3 ms**（p95 44.4） | 39 |

读法对号（用户给的判据）：

- **E2 不变、E3 变** → 命中的是第一条的「canvas 元素在滚动子树里」。补充事实把范围扩大：**非文本绘制**都中招——E4/E4b 的 div 几何同样只有 1 帧。
- **E2 和 E3 都不变** → 不成立（E3 40/40）。注意 E3 的 12 px / 24 px 版本分别只有 0 / 2-3 帧：那是 60×60 探头分辨率看不见小字号，不是「没上屏」；48 px 版本才进入可测区。
- **E4 或 E5 变** → E4 不变，**E5 变**。可用写法 = gpui-kit `Slider`；纯 div 不可用。
- **E6 变** → 成立。触发条件是「在滚动容器里」。
- 结果对不上「只 canvas」：如实列出，E4/E4b 是反例。

## 2. Evidence

产物：`traces/MATRIX-*.run`（SCK 帧流）、`traces/MATRIX-*.err`（应用内日志）、`traces/MATRIX-NUMBERS.txt`（本轮全部 segstats/逐 tick 汇总）。位移与命中均由 `SCROLL_OFFSET` / `SLIDER_DOWN` / `CANVAS_PAINT` / `KIT_TRACK_BOUNDS` 实测。

### E1 基线（1 帧）

```
SCROLL_OFFSET y=602.0 max=1576.0
CANVAS_PAINT t=3335.7 frac=0.7133 y=174.5 x=1167.0 w=263.0 fixed=0
MM ... n=31 APPLY ... m=11 p=0 v=1.5800 renders=68 renders_drag=24
DRAG_SUMMARY ... renders=68 renders_drag=25 module=11 param=0 value=1.5800
changed=1 changed_fps=1.4   lat drag_step n=40 med=218.5ms
```

### E2 canvas 定时器（0 帧）

40 次 `TICK`、应用 `renders` 45→84（39 次重绘），canvas 每次以新 `frac` 重绘：`0.7000 → … → 0.9417`，绘制坐标 `y=174.5`（滚动后的正确位置）；同一 0.656 s 窗口内变化帧 **0**。

```
TICK n=0  t=3165.7 renders=45 value=0.7000
TICK n=39 t=3821.3 renders=84 value=2.6500
TICK_END t=3821.4 renders=84
CANVAS_PAINT t=3833.1 frac=0.9417 y=174.5 x=1167.0
changed_in_window=0  changed_fps=0.0  app_renders_in_ticker=39
```

补充（`shots/matrix/e2-value-unchanged.png`，before/after 两轮窗口截图裁切）：偏移 602 时滑杆行数值在 tick 前为 `+0.720 EV`，tick 进行中截图仍为 `+0.720 EV`，滑条填充未动——与 0 帧一致。E2 行内的 12 px 数值文本也属于「小字号探不到」范围，故不以它单独下结论。

### E3 文本定时器（40 帧）

48 px 标签（同一代码路径，仅为探头可测放大）：40 次 tick 对应 **40 个变化帧**，逐 tick 中位 9.8 ms；`TICK_END renders=81`、`TICK_START renders=42`（39 次重绘）。24 px 版本只有 2 帧、12 px 版本 0 帧——探头 60×60 网格的采样点落不进小字号笔画，属测量分辨率问题（E7t 24 px 也只 3 帧）。

```
e3: ticks=40 window=0.654s changed_in_window=40 changed_fps=61.2
per_tick_lat n=40 med=9.8ms p95=31.0ms max=64.3ms
```

### E4 / E4b div 滑杆（各 1 帧）

- E4（绝对定位填充）：`SLIDER_DOWN bounds=(1167.0,180.0 263.0x12.0)`，`mm_applied=33`、`renders_drag=23`，探头 **1** 帧 / 中位 205.1 ms。
- E4b（在流 flex 填充，排除「absolute 不触发布局」的解释）：`renders_drag=25`、`mm_applied=33`，仍 **1** 帧 / 221.6 ms。

### E5 gpui-kit Slider（14 帧；长拖 8 fps）

`KIT_TRACK_BOUNDS` 随滚动到 y=168.5（24 px 高轨），拖动由组件自身处理；`drag_step` 中位 12.6 ms，0.703 s 内 14 帧。把同一次拖动拉长到 3.646 s：29 帧（8 fps），按下后的前 0.7 s 有 ~5 帧来自拇指环动画，其后约每 100 ms 一帧，**不是 60 fps 跟手**。源码依据：`gpui-component/src/slider.rs` 的 `ThumbRing::new` 调 `spring(...)`，`gpui-base/src/motion.rs:721` 的 `spring` 在未 settle 时每帧 `window.request_animation_frame()`；拖动期间 pressed 环持续动画。该归因为 [INFERENCE]。

### E6 容器外（18 帧）

固定条（滚动容器之外，`fixed=1`）的 canvas：`y=125.5`、`frac 0.6750 → 0.7633`，探头 **18** 帧 / 中位 8.8 ms；同一二进制同一脚本只把拖动目标换到固定条。`SCROLL_OFFSET y=602.0 max=1632.0`（列表视口因固定条缩短，偏移仍到 602）。

### E7 偏移 0 对照

- E7v（canvas，偏移 0）：**39** 帧、58.9 fps、中位 9.2 ms。
- E7t（文本，偏移 0）：**24** 帧、36.5 fps、中位 11.3 ms（48 px 标签；24 px 只 3 帧）。
- 与 E2/E3 的同项对比：canvas 0→39，文本 40→24，均证明「偏移 ≠ 0」是开关。

## 3. Meaning for #27

1. **dt 式滑杆（填充条 + 三角标）在 gpui 当前版本上不能直接用 canvas 或 div 几何实现并放进滚动列表。** 事件、值、绘制、`cx.notify()` 都正常，卡在滚动容器对子树的呈现：偏移 ≠ 0 时，canvas 四边/路径与 div 宽高位置的新帧不上屏；文本内容例外。
2. **可用的绕法只有一种实测通过：用 gpui-kit 的 `Slider` 组件**（或任何在交互期间持续 `request_animation_frame()` 的写法），代价是帧率降到 **8–20 fps**，且外观是圆角胶囊拇指，不是 dt 的填充条 + 三角。要保持 dt 外观，需要自己画填充/三角并另外挂一个动画帧泵（例如拖动期间每帧请求一帧），这属于对框架缺陷的临时补丁，不是干净的写法。
3. **把控件放到滚动容器外**（E6）能恢复 ~26 fps，但违背 dt 的模块列表布局；只能作为原型阶段的取舍。
4. 干净修复应在框架侧（滚动子树的呈现/缓存失效），原型侧无法靠调整事件处理规避。
5. 复现最小面：30 模块、`overflow_y_scroll`、滚到 ~600、canvas 或 div 几何滑杆、按住拖动或定时改值；文本标签不触发。

## 4. Clean build

当前二进制默认无色条、无日志副作用（`LIGHTAMER_MARKER` 未设 = 关闭；`LIGHTAMER_MM_LOG` 未设 = 静默；实测 stderr 0 字节）。sha256 `98bb3430ba7b4745e1a80a535f2f2014f2a70832f4f85b938c4bd17fa95fda18`。

启动（资源是相对路径，必须在仓外工作区启动）：

```bash
cd /Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike
./target/debug/lightamer_gpui_proto
```

观察方法：鼠标移到右侧模块列表，向下滚动到中段（约 600 px，约 43 格），按住 `exposure` 滑杆左右拖；看滑条填充与右侧数值是否跟手。预期（按本轮结论）：**不跟手**——拖动期间数值/填充基本不动，松手后才跳一次。把同一滑杆滚回顶部（偏移 0）再拖，会跟手（~60 fps 的六成）。若用真实鼠标观察到与合成事件不同的现象，以真机为准并记录。

## 5. Unverified

1. **真实鼠标**：本轮全部为 `CGEvent` 合成事件（`postToHID` + `--global`）；真实鼠标未验。
2. **E5 成功的机制**：动画帧泵是源码指向的 [INFERENCE]，未做「禁用拇指环动画再拖」的隔离实验。
3. **文本的可测边界**：60×60 探头对 <24 px 文字基本失明；12 px 数值文本无法用探头判定。E3/E7t 的「文本能上屏」只对 48 px 纯文本标签成立，未证明滑杆行内 12 px 数值文本同样能上屏（E2 截图显示它没动，但截图可能读的是最后呈现缓冲）。
4. **框架内确切一层**：滚动容器的哪一级缓存/呈现路径（layer 复用、surface 提交、damage 计算）未证实，本轮只做行为对照。
5. **其它偏移/尺寸**：只测偏移 0 与 602、1440×816、30 模块；其它偏移、窗口尺寸、模块数未扫。
6. **E5 应用内重绘次数**：kit 模式下组件自己接管拖动，本原型的 `renders_drag` 不计数；只报了画面帧数与逐事件延迟。
7. **`screencapture` 与 SCK 的口径差**：截图可能读最后呈现缓冲而非显示流；帧数一律以 SCK trace 为准，截图仅作旁证。
8. 没做上游 issue 提交，未验证更新版本是否已修。

## Appendix: artifacts

- `traces/MATRIX-{e1,e2,e3,e4,e4b,e5,e5slow,e6,e7v,e7t}.run` / `.err`
- `traces/MATRIX-NUMBERS.txt`（segstats + 逐 tick 汇总）
- `src-copy/main.rs`（本轮最终源码：marker/log 环境门控、`LIGHTAMER_SLIDER=canvas|div|divflow|kit`、`LIGHTAMER_FIXED=1`、`LIGHTAMER_TIMER=value|text`）
