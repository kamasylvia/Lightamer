# REPORT: same matrix on the gpui-fast backend (gpui-kit `fast-backend` feature)

日期 2026-11-25 · 仓内 HEAD `5161c3dda4129fd7e7df28349342a93a72dace88`（本文件所在提交之前）· 原型 `/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike`（仓外，产品树零改动）· 后端 = `gpui-kit 0.11.0` + 特性 `gpui-fast`（`gpui-fast 0.1.19`；不打开特性仍是 `gpui-pre 0.3.14`）· 探针 = `measure/FrameProbe.swift`（与 MATRIX 轮同一个二进制、同一判据：`cells>=1 && maxd>=10`）

## 0. Conclusion

**fast 后端下故障一模一样，没有任何恢复。** 滚动偏移 602 时，canvas 滑杆（拖动 / 定时器改值）与 div 几何滑杆仍然不上屏：E1 = 1/40 帧、E2 = 0/40 帧、E4b = 1/40 帧，与 `REPORT-MATRIX.md` 的 gpui-pre 数字逐项相同；同一二进制在偏移 0 拖动是 18/40 帧。`gpui-kit` 自带 `Slider` 仍能上屏（15–16/40 帧 ≈ 21–23 fps，pre 为 14）。

| 问题 | 结论 |
|---|---|
| fast 后端下故障在不在 | **在**。四个实验的判据值与 pre 后端同值（E1 1、E2 0、E4b 1、E5 15 vs 14）。 |
| `GPUI_SCROLL_LAYERS=0` 有没有影响 | **没有可测影响**。五个实验 × 两种环境下逐项同值（E1 1/1、E2 0/0、E4b 1/1、E5 15/16、基线 18/18）。 |
| 有没有一条干净的路 | **没有**。`gpui-fast` 特性不是绕法；文本能上屏 / 几何不能上屏的分裂在两个后端上同形。 |
| 置信度 | 帧数：**高**（每项两环境各一轮 + pre 后端同日控制两轮，逐值一致）。「滚动图层是否真的被提升过」：**未证**（见 §6.1），因此「开关无影响」只能读到「在本原型上开关不改变结果」，不能读到「图层机制无罪」。 |

## 1. Numbers

同一窗口 1440×816、同一 30 模块面板；除基线外均滚到偏移 602（43 × `scroll -14`，stderr `SCROLL_OFFSET y=602.0`）。40 次更新；延迟 = 每次更新到其后第一个变化帧的中位。`-nl` = `GPUI_SCROLL_LAYERS=0`。

| # | 滚动面板里的东西 | 更新方式 | fast 默认 | fast `LAYERS=0` | pre（本轮控制 / MATRIX） |
|---|---|---|---|---|---|
| E1 | canvas 滑杆（module 11 exposure） | 按住拖动 40 步 × 8 ms | **1** / 延迟 204.4 ms | **1** / 200.1 ms | 1 / 222.7（MATRIX 218.5） |
| E2 | canvas 滑杆，定时器 16 ms × 40 | 定时器 | **0**（应用内 renders 47→86，39 次重绘） | **0**（45→84，39 次） | 0 |
| E4b | div 在流 flex 滑杆 | 按住拖动 | **1** / 216.2 ms | **1** / 213.5 ms | 1 / 221.6（MATRIX） |
| E5 | gpui-kit 样式化 `Slider` | 按住拖动 | **15**（21.5 fps）/ 11.1 ms | **16**（23.2 fps）/ 9.3 ms | 14（19.9 fps）/ 12.6 ms（MATRIX） |
| 基线 | canvas 滑杆 @ **偏移 0**（module 1 exposure） | 按住拖动 | **18**（25.7 fps）/ 9.3 ms | **18**（25.7 fps）/ 8.8 ms | **19**（27.3 fps）/ 9.5 ms（本轮 pre 复测） |
| 附：E3 | 48 px 文本标签 @ 602 | 定时器 16 ms × 40 | **40**（60.2 fps）/ 3.6 ms | 未跑 | 40（61.2 fps）（MATRIX） |

读法：

- E1/E2/E4b 在 fast 下**没有恢复到接近 40 帧**——按用户给的三条判据，落在**第三条**：两个后端都这样，问题更深，本轮不往下猜层。
- E5 在两个后端都是唯一能上屏的写法，且都是「十几帧、不是 60 fps 跟手」；fast 略高 1–2 帧，属噪声级。
- 基线本身也不是 40/40：偏移 0 拖动 18/40（25.7 fps）。pre 同日复测 19/40。判据要按「同探针同窗口」的相对值读——602 处 1 帧 vs 0 处 18–19 帧，才是「偏移 ≠ 0」这个开关。探头对 2–3 px/步的填充位移只吃到约一半变化帧（格均值 ≫ 判据线），绝对值偏低是探头口径，不是丢帧。
- E2 的 0 帧不是「没重绘」：应用内 `renders` 40 次 tick 涨 39，canvas 以新 `frac` 重绘到 `y=174.5`（滚动后的正确位置），画面 0 帧变。与 pre 完全同形。

## 2. Adaptation list

**零 API 适配。** `src/main.rs` 在 fast 后端下逐字节未改（`diff -q` 与 pre 轮存档 `src-copy/main.rs` 相同，75928 字节）。

唯一的改动是 `Cargo.toml` 加一个特性（默认仍是 pre）：

```toml
[features]
# 打开时 gpui-kit 走 gpui-fast 0.1.19；不打开保持默认 gpui-pre 0.3.14。
fast-backend = ["gpui-kit/gpui-fast"]
```

构建：`cargo build --offline --features fast-backend -j 6`（离线成功，3m33s；`Cargo.lock` 未动，gpui-fast 一族已在锁与 registry 缓存里）。

后端核验（不是看门面，是看链接结果）：

- `cargo tree --offline --locked --features fast-backend -i gpui-fast` → `gpui-fast v0.1.19 ← gpui-base/gpui-component/gpui-kit/lightamer_gpui_proto`；
- `strings dist/proto-fast-clean | grep -c GPUI_SCROLL_LAYERS` = **1**；`dist/proto-pre-clean` = **0**。
- 二进制：`dist/proto-fast-clean` sha256 `6749a3ddc7e00d260a7f8bd37c923c0d2fefed15588bc466ccc713b58332a874`（41,648,328 B）；`dist/proto-pre-clean` 原样未动 `98bb3430ba7b4745e1a80a535f2f2014f2a70832f4f85b938c4bd17fa95fda18`。
- 干净性：`env -u LIGHTAMER_MM_LOG -u LIGHTAMER_MARKER ./dist/proto-fast-clean` 起停一轮，stderr **0 字节**，无色条日志。

一个非代码的环境差异：fast 二进制下探针 `--activate` 后 `space` 键**不一定**到达应用（首轮 `KEY` 行缺席、ticker 没起）。改用「先 `click 700 400` 聚焦、再 `move` 回面板滚动」的脚本后两次都到达。这是激活/焦点时序，不是编译适配，记在 §6.4。

## 3. 两个后端到底差在哪（逐条给出处）

**1) 依赖图：pre 恒在，fast 是可选的第二后端。** `gpui-kit-0.11.0/Cargo.toml`：`[dependencies.gpui] version = "=0.3.14" package = "gpui-pre"`（**非 optional**，永远编进来）；`[dependencies.gpui-fast] version = "0.1.19" optional = true`；`features.gpui-fast = ["dep:gpui-fast", "dep:gpui-fast-platform", "dep:gpui-fast-web", "gpui-base/gpui-fast", "gpui-component?/gpui-fast", "gpui-kit-assets?/gpui-fast"]`。所以「切后端」= 打开 `gpui-fast` 特性，gpui-pre 仍留在依赖图里但不被门面导出（本轮 `cargo tree -i gpui-pre` 仍能列出，属预期）。

**2) 门面切换点。** `gpui-kit-0.11.0/src/lib.rs`：`#[cfg(not(feature = "gpui-fast"))] pub use ::gpui::*;` / `#[cfg(feature = "gpui-fast")] pub use ::gpui_fast::*;`，`platform` / `web` 同样按特性切换，另有 `pub const GPUI_FAST: bool = cfg!(feature = "gpui-fast")`。这就是「应用一行不改、同一个 `use gpui_kit::*`」的原因。

**3) 源码面差在 `fast/` 一个目录。** 同机 registry 两棵源码树顶层逐目录对比：`gpui-pre-0.3.14/src` 与 `gpui-fast-0.1.19/src` 只差一项——fast 多 `src/fast/`（51,983 行）。单文件抽样：`src/elements/canvas.rs` **逐字节相同**；`src/elements/div.rs` 差 189 行、`src/window.rs` 差 260 行、`src/scene.rs` 差 272 行。fast 的 README 原文：「GPUI with gpui-fast rendering and layout optimizations. … Forked from Zed's GPUI」。

**4) fast 多出来的东西里，与本题直接相关的是「滚动图层」。** `gpui-fast-0.1.19/src/fast/layers/mod.rs` 头注：滚动容器内容「painted once into cached tiles and composited at the scroll offset on frames where only the offset changed」；`COMPILED = cfg!(any(target_os = "linux"/"macos"/"windows"))`；`WindowLayers::default().enabled = COMPILED && std::env::var("GPUI_SCROLL_LAYERS").map_or(true, |v| v != "0")`——**这就是那个开关的正身，只存在于 gpui-fast**（`gpui-pre` 全树 grep `GPUI_SCROLL_LAYERS` / `view_retention` 零命中，也没有 `src/fast/`）。

**5) 图层的决策规则（解释了为什么拖动类实验对开关不敏感）。** `src/fast/layers/policy.rs`：`Decision::{Bypass, Repaint, Composite}`；`Composite` 只在 `policy.painted_in == context && invalidate::scroll_only(...)` 时给出（policy.rs:296-305）；`scroll_only` = 依赖没变 && hover 没变 && 内层容器没滚 && 内容视图没被通知 && owner 只滚（invalidate.rs:926-938）。更关键的一条：`src/fast/layers/mod.rs:126-134` 的 `active()` 带 `!cx.has_active_drag()` ——**按住拖动期间图层整体旁路**。所以 E1/E4b/E5 的 ON/OFF 两臂在结构上就不可能不同；只有 E2（定时器、无拖动）真正走到图层路径。

**6) 上游 issue 原文说的是同一族问题，但不是这一条。** `longbridge/gpui-kit#4057`（open）标题「webview: a WebView in a scroll container flickers outside it while scrolling (gpui-fast scroll layers, follow-up to gpui-fast#157)」，正文：「The cause is in gpui-fast and is the known limitation of longbridge/gpui-fast#157: on the frames that try a scroll layer (promotion, then each retry), the content is prepainted under the layer's wider content mask … #157 lowers how often it happens but does not remove it.」报告者环境原文：`gpui-kit = { version = "=0.10.0", features = ["gpui-fast"] }`。`gpui-fast#157`（closed）正文：「Once the container has a scroll layer, a frame that only scrolled composites the layer's cached content without prepainting it (`fast/layers/policy.rs`, `decide` → `Decision::Composite`), so `set_bounds` is never called…」——注意 #157 的病灶是**原生 surface 不跟随滚动**，#4057 是**裁剪掩码一帧外溢**；两者都要求「容器有图层且在 composite 帧」。本轮 E2 在 `LAYERS=0` 下同样 0 帧，说明**我们这条故障不需要图层**，与 #157/#4057 不是同一条因果链（也只能说明这点，再往下没有证据）。

**7) 查不到的**：gpui-fast 没有运行时开关/日志能把「本容器是否已提升、本帧是 Repaint 还是 Composite」暴露出来（`fast/layers` 全目录无 `eprintln!`；`layout_engine.retention.stats` 只有计数、无公开读出口）。因此「开关无影响」不能反过来证明图层未被使用，见 §6.1。两后端在**滚动的呈现结果**上的确切分歧层（合成器 / 呈现 / 图层）本轮同样没有证据，不做猜测。

## 4. 对 #27 的含义

1. **`gpui-fast` 特性不是 #27 的绕法。** 数一数：E1 1、E2 0、E4b 1，与 pre 同值；offset-0 基线 18 vs pre 19。想靠「换个后端」拿到跟手滑杆，这条路关掉。
2. **故障不属于「滚动图层」这一个特性。** `GPUI_SCROLL_LAYERS=0` 把图层整条关掉，E1/E2/E4b/E5/基线五项逐项不变。要么图层在本原型上从未参与（未能证否），要么图层不是必要条件；两种读法都指向「问题在更共享的一层」。
3. **可用写法仍然只有一种：用会在交互期持续请求动画帧的写法（gpui-kit `Slider`），代价 20 fps 上下，且外观是胶囊拇指而不是 dt 的填充条 + 三角。** 这与 MATRIX 轮的结论一致，fast 后端没有改善（15/16 vs 14 帧）。
4. **共同形状值得记一笔**：两个后端上都是「文本上屏、canvas/div 几何不上屏」，且应用内重绘计数正常、canvas 以新值画在正确坐标。这不是事件、状态或布局问题，是「画了但没呈现」这一类；#27 若继续在 gpui 上走，要么在框架侧修，要么承认只能用带动画泵的控件。
5. **不要再把「换后端」列为待验项。** 本轮已把这条路走完（两种后端 × 两种图层环境 × 四个实验 + 基线 + 文本对照）。

## 5. 手测

二进制：`dist/proto-fast-clean`（默认无色条、无日志副作用，stderr 0 字节）。资源是相对路径，**必须在工作区目录下启动**：

```bash
cd /Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike
./dist/proto-fast-clean
```

关滚动图层再跑一遍（对照）：

```bash
cd /Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike
GPUI_SCROLL_LAYERS=0 ./dist/proto-fast-clean
```

怎么看：鼠标移到右侧模块列表，向下滚动到中段（约 600 px，约 43 格），按住 `exposure` 那一行的滑条左右拖——看填充条与右侧数值是否跟手。预期：**不跟手**，拖动期间基本不动、松手后跳一次；把同一处滚回顶部（偏移 0）再拖，会跟手（约 26 fps，非满 60）。`GPUI_SCROLL_LAYERS=0` 下现象应当相同——若你的机器上不同，以真机为准并记录（本轮全部为合成事件）。

## 6. Unverified

1. **滚动图层是否真的被提升过**：无运行时出口可读。源码上「连续 2 帧滚动即提升」（policy.rs `PROMOTE_AFTER_SCROLLED_FRAMES = 2`）、且滚轮路径确实记了滚动（div.rs 的 wheel 监听里 `note_scrolled` + `cx.notify`），我们的脚本满足条件；但没观察到 composite 帧的证据（滚动阶段两臂的 `CANVAS_PAINT` 计数同为 68、`KIT_TRACK_BOUNDS` 同为 85）。「开关无影响」请按「本原型上开关不改变结果」读。
2. **真实鼠标**：全部 `CGEvent` 合成事件，真实鼠标未验。
3. **E5 的 15/16 帧是否就是 fast 的天花板**：未做长拖（MATRIX 的 E5-slow 为 8 fps），本轮只跑标准 40×8 ms。
4. **fast 二进制下的键盘激活**：`--activate` 后 `space` 首轮未达应用，用先点击聚焦规避；未定位是激活时序还是 fast 的窗口焦点处理。
5. **文本可测边界**：与 MATRIX 同口径，60×60 探头对 <24 px 文本基本失明；E3 只用 48 px 标签。
6. **其它偏移/尺寸/模块数**：只测偏移 0 与 602、1440×816、30 模块。
7. **上游是否已修**：`gpui-fast 0.1.19` 是锁文件里已有的版本，未试更高版本（本轮纪律：不升级依赖）。

## Appendix: artifacts

- `traces/FAST-{e1,e1-nl,e2,e2-nl,e3,e4b,e4b-nl,e5,e5-nl,e1off0,e1off0-nl}.{run,err}`：fast 后端十一轮（`.run` = SCK 帧流，`.err` = 应用内日志）。
- `traces/FAST-pre-{e1,e1off0}.{run,err}`：同日后端控制两轮（pre 二进制）。
- `traces/FAST-NUMBERS.txt`：本轮全部 segstats / 逐 tick 汇总。
- `traces/FAST-scripts/`：`drive-fast.py`（含 `PROTO_BIN` 选择）、`analyze_ticks_fast.py`、`e1off0.scr`（偏移 0 基线，drag 用全局坐标 y=274）、`e2click.scr`（先点击聚焦再 `key space`）。
- `src-copy/main.rs`（与 pre 轮逐字节相同）、`src-copy/Cargo.toml`（加了 `fast-backend` 特性）。
