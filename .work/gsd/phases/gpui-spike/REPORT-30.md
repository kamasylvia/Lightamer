# gpui 原型补测：30 个模块的面板（滚动 / 拖动 / 展开后滚动）

日期 2026-11-25 · 开工 HEAD `eac61e2d`（仓内产品树零改动）· 原型在仓外 `/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike/` · 机器 Apple M4 / 16 GB / macOS 27.3 / 内建 60 Hz 面板（1504×846 pt），窗口 1440×816。

## 0. Verdict

| 情形 | 变化帧率 | 帧间隔中位 / p95 | >16.7 ms | >33.3 ms | 结论 |
|---|---|---|---|---|---|
| 1. 滚动（30 模块，顶→中段） | **58.0 fps**（68 个变化帧 / 1.173 s，输入 80 个滚轮事件） | **16.64 / 18.05 ms** | 28 / 67 | **0** | 跟手：中位 = 面板 60 Hz，无一帧超过 33.3 ms |
| 2. 满面板拖滑杆（中段） | **未取得有效读数**（40 步拖动只落 1 个变化帧） | 全帧 16.60 / 18.59 ms（无变化帧可算） | — | — | **不能断言**；同机制对视口拖动对照 = 60.7 fps |
| 3. 展开 5 个填充模块后再滚 | **57.7 fps**（68 / 1.179 s，输入 80 事件） | **16.69 / 17.55 ms** | 33 / 67 | **0** | 跟手，与情形 1 无实质差异 |

**是否保持 60 fps**：滚动与展开后滚动两项，变化帧节奏跟住 60 Hz 面板（中位 16.6–16.7 ms，p95 ≤18.1 ms，>33.3 ms 帧为 0）；changed fps 本身受合成输入事件率（68 事件/s）约束，低于 60 不是掉帧。**拖动滑杆一项没有测成**：合成 `leftMouseDragged` 在滚动的模块面板内只被应用吃到 1 个中间位置，实时重绘无法计量；同一探针/同一机制的视口拖动得到 60.7 fps，说明工具能看到拖动重绘，缺口在滑杆所在的滚动面板子树（见 §4）。

## 1. 数字表

窗口 1440×816（屏幕原点 32,30），右栏 280 pt。模块列表 30 个（3 个完整模块 + 27 个填充模块），列表内容高 2298 pt、视口 722 pt，`max_offset` 1576（展开 5 个后 1816）——列表确实可滚。

| 指标 | 情形 1 滚动 | 情形 3 展开后滚动 |
|---|---|---|
| 滚轮事件 / 时长 | 80 / 1.173 s（68 事件/s） | 80 / 1.179 s（68 事件/s） |
| 列表滚动偏移（stderr） | 0 → 1120 pt | 602 → 1722 pt |
| 变化帧数 | 68 | 68 |
| 变化帧率（帧/秒） | 58.0 | 57.7 |
| 变化帧间隔中位 | 16.64 ms | 16.69 ms |
| 变化帧间隔 p95 | 18.05 ms | 17.55 ms |
| 变化帧间隔最大 | 21.38 ms | 33.02 ms |
| 间隔 >16.7 ms | 28 / 67 | 33 / 67 |
| 间隔 >33.3 ms | 0 / 67 | 0 / 67 |
| 输入→首个变化帧 中位 / p95 / 最大 | 7.4 / 14.2 / 56.4 ms | 6.4 / 14.3 / 45.6 ms |
| 全部帧间隔中位 / p95 | 16.64 / 18.02 ms | 16.69 / 17.47 ms |

情形 2（拖滑杆，offset 602，拖 exposure 滑杆 +0.730 → +1.580 EV，40 步 × 8 ms）：

| 指标 | 值 | 说明 |
|---|---|---|
| 拖动窗口内变化帧 | **1**（全程 3） | 无效样本；值最终正确提交（历史条目 `exposure → +1.580 EV`） |
| 全帧间隔中位 / p95 | 16.60 / 18.59 ms | 面板持续出帧，只是画面不变 |
| drag_down → 首变化帧 | 53.0 ms | 单样本 |
| drag_step → 首变化帧 | 中位 209.6 / p95 375.1 / 最大 393.5 ms（40 个事件） | 事件全部在 up 之前，但应用只对最后一个位置重绘 → 该分布不成立 |
| drag_up → 首变化帧 | 69.8 ms | 提交帧 |
| 对照：视口拖动（40 步 × 8 ms） | **60.7 fps**，22 个变化帧 / 363 ms，中位 16.48 ms，p95 17.30 ms，>33.3 = 0 | 同一探针、同一合成机制；证明拖动重绘可被观测 |

重复性：拖滑杆另做 20 步 × 100 ms（2 s）一轮，仍只有 2 个变化帧；把步长放慢到 100 ms/步不改善，说明不是事件率/合帧阈值问题。

## 2. 方法与自检

**模块列表**：`src/main.rs` 的 `module_defs()` 数据驱动生成——3 个完整模块（exposure、white balance、filmic rgb）+ 27 个填充模块（统一头部 + 2–3 个滑杆），全部按 darktable 5.6.2 默认 RAW 管线 `v50_order` 的次序排列。填充模块显示名逐条取自本机 darktable 仓库 `release-5.6.2` 标签的 `src/iop/*.c` `name()`（如 `raw black/white point`、`highlight reconstruction`、`denoise (profiled)`、`surface blur`、`rotate and perspective`、`legacy equalizer`、`color calibration`、`diffuse or sharpen`、`rgb primaries`、`color balance rgb`、`tone curve`、`vignette`），管道坐标取自同标签 `src/common/iop_order.c` 的 `v50_order[]`（1.0 … 68.0）。默认展开：3 个完整模块 + 3 个填充模块（input color profile、color calibration、diffuse or sharpen）；本轮又点了 2 个（tone equalizer、crop）凑满 5 个填充模块展开，用于情形 3。

**滚动偏移证据**：原型在 `right_panel()` 每次渲染时读 `ScrollHandle`，偏移变化 ≥0.5 pt 就向 stderr 打一行 `SCROLL_OFFSET y=<偏移> max=<最大偏移>`。每轮测量的首末行：

- 情形 1：`y=-0.0 max=0.0`（首帧，尚未布局）→ `y=16.0 max=1576.0` → … → `y=1104.0` / `y=1120.0 max=1576.0`。80 个事件各推进 14 pt，偏移单调增大；`max=1576 > 0` 证明 30 个模块确实溢出视口。
- 情形 3：`y=602.0 max=1816.0` → … → `y=1722.0 max=1816.0`；展开 5 个填充模块后 `max` 从 1576 涨到 1816，滚动条行程同步变长。
- 情形 2：拖动期间无任何 `SCROLL_OFFSET` 变化（列表没有因拖动而滚动）。

**探针**：沿用上一条 lane 的 `measure/FrameProbe.swift`（SCK 单窗抓帧，120 Hz 请求 / 60 Hz 交付，80×45 网格帧差，`cells>=1 && maxd>=10` 记变化帧；`CGEvent` 合成输入并记录发出时刻）。`--global --activate` 投递（`postToPid` 的悬停路径不成立，实测滚轮不生效）。帧间隔全部取帧 PTS。分组统计用本轮新增的 `measure/segstats.py`（按 `mark begin/end` 切段，规则与 `frameprobe summary` 相同），原始摘要与分段统计一并入库。

**自检**：本机 60 Hz 面板；三轮测量的全帧间隔中位 16.5–16.7 ms，与上一条 lane `measure/SelfCheck.swift` 的 16.67 ms/帧、探针读数 16.60–16.66 ms 一致。变化帧判定可能低估「小面积重绘」（三角形滑块移动只占 1–2 个网格格），因此 §1 的变化帧率是保守值。

## 3. 截图

`shots/panel-30-modules.jpg`（1440×816 窗口，滚动偏移 1050 pt：同屏可见 input color profile、color calibration、diffuse or sharpen 三个展开模块，上方还有 graduated density / legacy equalizer 的折叠头）。原图由 `screencapture -l <windowID>` 取自己启动的原型窗口，转 JPEG 质量 88；含窗口阴影（截图工具行为），窗口内容 1440×816。

## 4. 卡点与未验项

1. **拖滑杆的实时帧率未测成**（最重要的一项）。40 步 / 20 步合成拖动，应用只对最终位置重绘一次；值、历史提交、最终画面都正确，但中间过程没有可计量的帧。已排除：事件率（8 ms 与 100 ms 步长结果相同）、探头（同机制视口拖动 60.7 fps）、坐标（拖动命中了滑杆行并改了值）。未排除：滚动面板子树里 `MouseMoveEvent` 的投递/重绘路径（需要给 `on_mouse_move` 加计数探针再编译一轮，本轮时间盒已到）。
2. darktable 对照未做（按要求本轮不装 dt；上一条 lane 已查明合成滚轮滚不动它的列表）。
3. 变化帧率受输入事件率约束：68 事件/s → 58 fps。要测「60 事件/s 输入下是否 60 fps」需要更密的合成事件，本轮未做。
4. 单机单显示器、一次会话；未做重复轮次（情形 1 与 3 各一轮）。
5. 填充模块只有滑杆外形，没有各自的真实参数语义与像素管线；本测只回答列表规模下的滚动/拖动 UI 手感。
6. 首帧 `SCROLL_OFFSET y=-0.0 max=0.0` 是布局前读数，属正常；其余行均为布局后真实偏移。

## 5. 复现

```bash
cd /Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike
cargo build -j 6
caffeinate -dis ./target/debug/lightamer_gpui_proto > proto.out 2> proto.err &
./measure/frameprobe list | grep lightamer_gpui_proto          # 取 windowID
./measure/frameprobe run --pid <pid> --window-id <wid> \
  --out traces/P30-scroll.run --script traces/scroll60b.txt --activate --global
./measure/frameprobe summary traces/P30-scroll.run
./measure/segstats.py traces/P30-scroll.run
```
