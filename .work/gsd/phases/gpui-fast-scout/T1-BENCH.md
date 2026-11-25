# T1 — gpui-fast 本机实测

> 侦察 T1（三路之一，唯一重活）。仓外工作区 `/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike`；产品树零改动；零 commit。
> 机器：MacBook（Apple Silicon，10 核，16 GB），macOS 27.3（26C5035r），主显示器 3008×1692 物理 / 1504×846 点 @ 60 Hz。
> 被测二进制（sha256）：pre = `98bb3430ba7b4745e1a80a535f2f2014f2a70832f4f85b938c4bd17fa95fda18`（dist/proto-pre-clean，与 proto-pre-fixed 逐字节相同）；fast = `6749a3ddc7e00d260a7f8bd37c923c0d2fefed15588bc466ccc713b58332a874`（dist/proto-fast-clean）。

## §0 结论头

| # | 项目 | pre | fast | zed（最小程序） |
|---|---|---|---|---|
| 1 | 滚动面板拖滑杆（固定曝光滑杆） | 24/27 显示帧变化，52.4 fps，步延迟中位 8.2 ms，37/40 步匹配 | 23/26，52.2 fps，8.3 ms，37/40 | 不适用（原型专属） |
| 1b | 同一动作，列表内滑杆（滚动到 602） | 22/26，50.3 fps，9.0 ms，37/40 | 23/26，53.0 fps，8.6 ms，39/40 | 不适用 |
| 2 | 30 模块面板滚轮 1 秒 | 59/69 变化帧，51.1 fps，间隔中位 16.69 ms，p95 33.37 ms，>33 ms 共 5 | 58/69，50.2 fps，16.67 ms，p95 34.27 ms，>33 ms 共 7 | 不适用（无此页面） |
| 3 | 十万行虚拟列表滚动 1 秒 | 57/65 变化帧，50.1 fps，p95 34.3 ms，内存 99 MB | 60/72，50.5 fps，p95 34.6 ms，内存 117 MB | 不适用（最小程序无列表） |
| 4 | 进程启动到窗口上屏（5 次中位） | 3769.8 ms | 3775.6 ms | 3523.6 ms（上游 gpui 0.2.2 最小程序，5 次） |
| 5 | 空闲 30 s CPU / 内存 | 0.0% / 570 MB | 0.1% / 618 MB | 不适用 |
| 5b | 连续滚动 CPU / 内存 | 23.5% / 577 MB | 24.7% / 595 MB | 不适用 |
| 6 | 12 pt 中英混排文字观感 | 两后端整窗截图**逐字节相同**（md5 相同），文字区 600 000 像素零差异 | 同左 | 不适用 |
| 7 | 程序自更新画面（外部画面接口） | surface()：不绘制（源码只认 NV12，BGRA 被断言拒绝；NV12 复测也未出画）；img(RenderImage)：59.2 fps 跟上 | surface()：同左（BGRA 实测）；RenderImage：57.2 fps 跟上 | 不适用 |
| 8 | 窗口角拖拽缩放 1 秒 | 未测成（合成事件不触发窗口缩放，AppKit 对照窗同样不动） | 未测成（同左） | 未测成 |
| 9 | 10 分钟稳定性 | 未测（任务只要求 fast） | 无崩溃、无卡死；44.0–44.6 fps 全程平直；RSS 321→1038（首 10 s 资产解码峰值）→509 MB，无增长 | 不适用 |
| 10 | 窗口表面像素格式/色域 | BGRA8Unorm，未设 colorspace（默认 sRGB），无 EDR；`maximumDrawableCount=3` | 同左（额外 overlay CAMetalLayer 复制 base 的 colorspace） | BGRA8Unorm，不设 colorspace，无 EDR |

**一句话**：已测项目里 fast 与 pre 基本同速 —— 拖动/滚动/十万行列表的帧率差 ≤ 1.5 fps、步延迟差 ≤ 0.5 ms、CPU 差 ≤ 1.2 个百分点；文字渲染逐像素相同；唯一明确的差距在"程序自更新画面"：`img(RenderImage)` fast 57.2 fps vs pre 59.2 fps（p95 24.9 vs 18.3 ms），而 `surface()` 在两边都只认 NV12、BGRA 直接被丢弃（都不出画）；`surface()` 这条对外部 GPU 画面最重要的路目前不可用。窗口表面配置两者逐字段相同（8 位 BGRA、SDR、默认 sRGB、无 EDR）。

## §1 方法

### 1.1 探针与两套网格

- 探针：`measure/frameprobe-dense`（源码 `measure/FrameProbeDense.swift`，本轮未改）。用 ScreenCaptureKit 抓**单个窗口**（`SCContentFilter(desktopIndependentWindow:)`，2× 像素、`minimumFrameInterval` 1/120 s），每帧计算与上一帧的差：**480×400 密集网格，每格中心取 1 像素**（窗口 1440×816 点时，格距 3.0×2.04 点；7 点高的滑条跨 ~3 行）。同步记录每个合成事件的发出时刻，延迟 = 事件后第一个变化帧的 PTS − 事件时刻。
- 判据（探针内建）：`cells ≥ 1 && maxd ≥ 10` 记为变化帧。
- **自检（血的教训）**：同一份轨迹同时算两套网格 —— 密集 480×400 与旧 80×45（`frameprobe-dual` 的稀疏口径）。在滚动到 602 的列表内拖 7 点滑条（T1b）上：**密集 22–23 帧变化，稀疏 0 帧**；整段轨迹稀疏口径 0 变化帧、密集 61–64 帧。自检结论：稀疏网格在本场景确实看不见 7 点条，本轮所有判读只用密集网格；每个数字都有窗口截图旁证。
- 合成事件：`CGEvent` 走 HID tap（`--global`），只发给我自己启动的窗口，且发送前 `--activate` 把该窗口置前（本轮实测：postToPid 能送达 mouseMoved，但 gpui 的滚动依赖真实 hover 状态，postToPid 不置 hover，滚动事件被丢弃 —— 见 §6 的"方法坑"）。
- 截图：`screencapture -x -o -l <windowid>`，只截自己的窗口。

### 1.2 动作序列

- T1：先把模块列表滚到偏移 602（43 次 `scroll -14`，12 ms 间隔，应用 stderr 自报 `SCROLL_OFFSET y=602.0` 确认），然后按住曝光滑杆拖 40 步、每步 8 ms、总位移 −100 px（0.7 EV → −1.58 EV，不触边界）。T1a 拖的是面板顶部固定槽里的曝光滑杆（`LIGHTAMER_FIXED=1`）；T1b 拖的是列表内、滚动后落在 y≈267 的那根 7 点滑条（同一参数，用于自检与容器内重绘）。
- T2：60 次 `scroll -14`、16 ms 间隔（≈0.96 s），偏移 0 → 840（上限 1632）。
- 事件匹配口径：40 个拖动步全部发出，macOS 实际投递到应用的 29–33 个（应用 stderr `mm_recv` 自报）；匹配率分母用**发出的步数**，分子用"步后 1 s 内有变化帧"的步数。
- 每项两个口径都报：按帧（窗口内变化帧数/帧率/间隔）与按事件（中位/p95 延迟、匹配比例）。

### 1.3 环境与纪律

- 测量前 `Scripts/machine-guard.sh` PASS（heavy=0，可用内存 53%）；`pgrep -fl "xcodebuild|test-direct|swift-build|rustc|cargo"` 为空（除了两个只读侦察 omp 进程）才开始。
- 测量窗口内不编译：Rust 编译集中在 T1/T2/T4/T5 之后与 T3/T6/T7 之前的独立时段。
- 全程 `caffeinate -dis`；编译并行度 ≤ 6；只动仓外工作区与本目录。

## §2 逐项数字

### 2.1 T1 滚动面板里拖滑杆

命令：`bench/runone.sh t1a-{pre,fast} dist/proto-{pre,fast}-clean bench/scripts/t1a-fixed.scr LIGHTAMER_FIXED=1 LIGHTAMER_MM_LOG=1`

| 口径 | pre | fast |
|---|---|---|
| 拖动窗口内显示帧数 | 27 | 26 |
| 其中变化帧数 | 24（89%） | 23（88%） |
| 变化帧率 | 52.4 fps | 52.2 fps |
| 变化帧间隔中位 / p95 | 16.67 / 17.82 ms | 16.63 / 18.54 ms |
| 步延迟中位（40 步） | 8.2 ms | 8.3 ms |
| 步延迟 p95 / 最大 | 26.6 / 46.7 ms | 27.3 / 47.4 ms |
| 匹配上变化帧的步数 | 37/40（92.5%） | 37/40（92.5%） |
| 应用实际收到的鼠标事件 | 30（应用 29 次应用了拖动） | 31（30 次） |
| 应用自报拖动窗口内 render 数 | 26 | 24 |

旁证：`shots/t1a-pre-panel.png`、`shots/t1a-fast-panel.png`（右侧面板裁剪：顶部固定槽里曝光显示 −1.580 EV，填充条与三角标记已移动；下方列表停在偏移 602）；整窗 `shots/t1a-{pre,fast}-full.png`。应用 stderr `DRAG_SUMMARY … value=-1.5800` 与截图数值一致。

**同动作、列表内滑条（T1b，自检同时是测量）**：

| 口径 | pre | fast |
|---|---|---|
| 拖动窗口内帧 / 变化帧 | 26 / 22 | 26 / 23 |
| 变化帧率 | 50.3 fps | 53.0 fps |
| 步延迟中位 / p95 | 9.0 / 57.3 ms | 8.6 / 28.0 ms |
| 匹配步数 | 37/40 | 39/40 |
| 稀疏网格同段变化帧 | **0** | **0** |

旁证：同一批 `shots/t1a-*.png` 的下半部（列表内曝光滑杆，滚动后在 y≈267 处），以及 `bench/out/t1b-{pre,fast}.png`。

### 2.2 T2 30 个模块的面板滚动

命令：`bench/runone.sh t2-{pre,fast} … bench/scripts/t2-scroll.scr`（60 次滚轮，16 ms 间隔，偏移 0→840）

| 口径 | pre | fast |
|---|---|---|
| 滚动段显示帧 / 变化帧 | 69 / 59 | 69 / 58 |
| 变化帧率 | 51.1 fps | 50.2 fps |
| 变化帧间隔中位 / p95 | 16.69 / 33.37 ms | 16.67 / 34.27 ms |
| 间隔 > 16.7 ms / > 33.3 ms 的变化帧 | 28 / 5 | 26 / 7 |
| 全部显示帧间隔 p95 | 17.48 ms | 17.77 ms |
| 滚动事件延迟中位 / p95 | 11.7 / 25.9 ms | 7.9 / 26.5 ms |
| 匹配事件 | 56/60（93%） | 57/60（95%） |

解读：两边的**显示链路本身**都是 60 Hz（全部帧 p95 < 18 ms，没有掉到 30 Hz 的段）；变化帧率 ~50 fps 是因为 60 个事件只带来 59 个"内容变了"的帧（滚动位移每帧 14 像素、事件与刷新同相）。>33 ms 的间隔各 5 与 7 个，都是单个 2 帧间隔，未形成连续卡顿。旁证：`shots/t2-{pre,fast}-scroll.png`（整窗，滚到 840 时的面板）与 `shots/t2-*-scroll-full.png`。

### 2.3 T3 十万行虚拟列表

被测程序：`src/bin/lab.rs`，`LAB_MODE=list`，用 gpui-kit 转出的 `gpui_base::v_virtual_list`（`gpui-base-0.11.0/src/virtual_list.rs:139`）放 **100 000 行、每行 28 点**，行内有递增编号文本。动作：鼠标移到列表上，60 次滚轮、16 ms 间隔（≈1 s）。
命令：`bench/t367.sh {pre,fast}`（内部走 `bench/runone.sh`）。

| 口径 | pre | fast |
|---|---|---|
| 滚动段显示帧 / 变化帧 | 65 / 57 | 72 / 60 |
| 变化帧率 | 50.1 fps | 50.5 fps |
| 变化帧间隔中位 / p95 | 16.65 / 34.29 ms | 16.86 / 34.60 ms |
| 间隔 > 16.7 / > 33.3 ms | 27 / 4 | 33 / 6 |
| 滚动事件延迟中位 / p95 | 11.2 / 36.5 ms | 8.5 / 24.0 ms |
| 匹配事件 | 59/60（98%） | 59/60（98%） |
| 进程 RSS（十万行列表静止态） | 99 MB | 117 MB |

结论：十万行不影响两边的帧率（与 T2 的 30 模块列表同一水平），虚拟化生效（RSS 只有 ~100 MB）。fast 的 RSS 高 18 MB、p95 差 ~12 ms，都在单个刷新帧量级。旁证：`bench/out/t3-{pre,fast}.png`（滚过之后的列表窗口）。

### 2.4 T4 启动到窗口上屏

方法：`bench/winpoll`（spawn 子进程 → 立刻 activate → 每 1.5 ms 轮询 `CGWindowListCopyWindowInfo`，取第一个宽 ≥ 800 且高 ≥ 300 的该 pid 窗口；`SPAWN_CALL < 1.5 ms`，轮询单次 ~2 ms）。每边 5 次。

| | 1 | 2 | 3 | 4 | 5 | 中位 |
|---|---|---|---|---|---|---|
| pre (ms) | 2725.4 | 3850.1 | 3749.4 | 3769.8 | 3789.5 | **3769.8** |
| fast (ms) | 3794.0 | 3775.6 | 3760.2 | 3763.2 | 3784.8 | **3775.6** |

**这个数不能只记在 gpui 头上**：同机对照，一个 20 行的纯 AppKit 程序（`bench/appkitwin.swift`，NSWindow + makeKeyAndOrderFront）从 spawn 到窗口出现 2.1–2.4 s；其进程内自报 `T_MAIN → T_SHOW` 就花了 2.09 s（`NSApplication.shared` + 建窗 + orderFront）。也就是说本机/本会话下 GUI 窗口上屏有 ~2 s 的系统地板，gpui 两个后端在此之上各多 ~1.4 s，**pre 与 fast 差 6 ms（噪声）**。另用 SCK 全屏抓帧交叉验证过一次（`bench/out/t4-pre-1.run`：窗口内容首帧出现在 spawn + 3989.8 ms，与 winpoll 的 3.77 s 同量级；差异来自 SCK 自己的启动预热）。
同一把尺子量最小程序（窗口 590×622）：上游 Zed gpui 0.2.2 五次 2237.9 / 3523.6 / 3524.9 / 3523.3 / 3531.0 ms，中位 **3523.6 ms**；pre 最小程序三次 3754.7 / 3749.9 / 3744.5，中位 3749.9 ms。四者都在 3.5 s 一带（原型比最小程序多 ~250 ms，与多解四张样张一致）。
旁证：窗口内容用 `shots/t1a-pre-full.png`（同一程序同一窗口）；启动计时的原始输出在 `bench/out/` 的 winpoll 日志与 `bench/out/t4-pre-1.run`。

### 2.5 T5 空闲与滚动时的占用

方法：`bench/cpuwatch.sh` 用 `ps -o cputime` 差分算精确 CPU 占率（非 `%cpu` 均值），RSS 取 `ps -o rss`。

| 状态 | pre | fast |
|---|---|---|
| 空闲 30 s CPU | 0.0% | 0.1% |
| 空闲 30 s 后 RSS | 570 MB（启动峰值 813 MB） | 618 MB（启动峰值 757 MB） |
| 连续滚动 5 s CPU（来回滚，避免滚到底饱和） | 23.5% | 24.7% |
| 滚动后 RSS | 577 MB | 595 MB |
| 滚动时变化帧率 | 50.8 fps | 51.5 fps |

说明：内存大头是四张样张 JPEG 的解码常驻（原型把 9504×6336 的样张解到内存），两后端相差 5–8%。旁证：`bench/out/t5-{pre,fast}.png`（滚动中截屏）。

### 2.6 T6 文字观感

样本：同一段 12 pt 文本，八行 —— 中英混排（默认字体）、中英混排（显式 Helvetica Neue）、纯拉丁、CJK 生僻字回退（永東國酬愛鬱靈鷹）、大小写与数字、常规字重、粗体、Menlo 等宽 + 中文回退。程序 `src/bin/lab.rs` 的 `LAB_MODE=text`，两后端同一份代码、同一窗口位置（1200×800 @ 40,40），`screencapture -x -o -l` 各截一张 2× 图。

**结果：两张图逐字节相同。** 整窗 PNG 的 md5 均为 `84e6dc41ec0fe97a1f143fc1b2bc0bad`（2400×1600）；对文字区 1250×480（600 000 像素）做逐像素差：**最大差 0，均值 0，差异像素 0**。也就是说在这段 12 pt 中英混排样本上，gpui-fast 自带文字系统的字形、字距、字重与 pre 完全一致（含 CJK 回退与 Menlo 回退），肉眼与像素两个层面都没有差别。

旁证：`shots/t6-text-side-by-side.png`（上 pre / 下 fast，原分辨率并排）、`shots/t6-text-{pre,fast}-full.png`（整窗原图）。

### 2.7 T7 程序自更新的外部画面

先找接口（源码，两后端同名同形）：
- **`gpui::surface(CVPixelBuffer)`** → `Surface` 元素：`elements/surface.rs:13`（`SurfaceSource::Surface(CFRetained<CVPixelBuffer>)`）、`:35`（构造器）、`:114`（`window.paint_surface`）。仅 macOS/iOS。
- **`gpui::RenderImage` + `img()`**：`assets.rs:43`（`RenderImage::new(Frame)`）、`elements/img.rs:37-46`（`ImageSource::Render(Arc<RenderImage>)`）、`:197`（`pub fn img`）。
- 没有第三种公开入口；`PaintSurface` 是场景内部类型（`scene.rs:1192`）。fast 的滚动层明确不缓存 surface（`fast/layers/tiles.rs:302` 注释 "layers never hold one (spec §6.5)"）。

实测（`LAB_MODE=surface` / `LAB_MODE=renderimage`，640×400，每 16 ms 重填整块颜色，探针抓 9 s）：

| 口径 | pre | fast |
|---|---|---|
| RenderImage：应用 tick / render | 271 / 274 | 271 / 274 |
| RenderImage：变化帧 / 帧率 | 533/540 → **59.2 fps**（中位 16.64 ms，p95 18.30） | 515/540 → **57.2 fps**（中位 16.73，p95 24.85） |
| RenderImage：画面内容 | 绿色矩形，颜色随 tick 变化（截图可见） | 同左（截图可见） |
| surface（BGRA）：应用 tick / render | 271 / 274 | 271 / 274 |
| surface（BGRA）：画面 | **不绘制**（画面区像素 = 背景 29,29,29，非黑块；只有标签在变） | 同左 |
| surface（NV12，仅 pre 复测）：→ | 也不绘制（540/541 帧变化全部来自标签；中心像素 29,29,29） | 未测（接口代码与 pre 同一段） |

**surface() 的结论（重要）**：两个后端都能编译、能运行，但送进去的画面**根本没有被画出来**（截图取样：画面区中心与背景同为 (29,29,29)，不是黑色填充块）。同一次运行里只有我加的 tick 标签在变，所以最初那组"59.6/57.6 fps"量到的是标签，不是画面 —— 该组数字作废，不写进结论。源码侧的第一道门是像素格式的硬断言

```
pixel_format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange   // NV12，双平面
```

（pre `gpui-pre-apple-0.3.14/src/metal_renderer.rs:1268-1271`；fast `gpui-fast-apple-0.1.19/src/metal_renderer.rs:1297-1301`；两边同一段代码）。BGRA 走进去 ensure 失败、该帧被丢弃，且**没有任何日志**。按源码把缓冲区改成 NV12（`kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`，双平面，Y 随 tick 变化）在 pre 上复测：依然不绘制。**残余不确定**：我用 `CVPixelBufferCreate` + `kCVPixelBufferIOSurfacePropertiesKey` 手搓的缓冲区，没有在 Rust 侧验证它确实拿到 IOSurface（同一份属性用 Swift 的 `CVPixelBufferCreate` 是拿到的），所以"NV12 也不画"可能是我的缓冲区不是 IOSurface-backed，也可能是 gpui 的纹理路径静默失败。可以确定的是：**BGRA 这条对图像编辑器最重要的路走不通**（源码写死只认 NV12），`surface()` 在本机两个后端上都没有产出任何画面；唯一端到端可用的是 CPU 侧 `RenderImage`（每帧一次 BGRA 上传 + 图集）。

旁证：`shots/t7s-{pre,fast}-surface.png`（surface 区域未绘制，只有标签）、`shots/t7n-pre-surface-nv12.png`、`shots/t7r-{pre,fast}-renderimage.png`（绿色矩形 + 标签）、`bench/out/t7*-*.app.err`（`SURFACE_BUFFER ok 640x400`，无错误日志）。lab 侧另有一个坑：`CVPixelBufferCreate` 的 attributes 字典用 objc2-core-foundation 0.3.2 构造时，`CFDictionary` 默认类型参数是 `Opaque`，`from_slices` 要 `K: PartialEq + Hash`；用 `CFDictionary<CFString, CFType>` 建好再转成 `&CFDictionary`（Opaque 形）传给 CoreVideo。

### 2.8 T8 窗口角拖拽缩放

**未测成**。合成拖拽（`--global`，窗口右下角 (1472,846) 向内 120×110 点，60 步、16 ms）对 gpui 两个后端的窗口都不起作用：窗口尺寸在拖拽前后都是 1440×816（`frameprobe list` 与探针自报一致），拖动窗口内变化帧 **0**（pre 0/72，fast 0/71）。
对照实验排除了"探针不会拖"：同一脚本对一只 20 行 AppKit 窗（800×632，带标题栏）同样无效（尺寸不变）。结论：本环境下合成的鼠标事件不被 WindowServer 当成缩放手势；**这不是 gpui 的问题，也没法用这套手段测**。程序化 resize（`Window::resize` 每帧改尺寸）能测重绘，但那不是"按住角拖"，本轮未做，记入 §6。

### 2.9 T9 10 分钟稳定性

对象：fast（`dist/proto-fast-clean`，固定槽曝光滑杆 + 滚动面板）。动作：10.6 分钟连续操作 —— 每轮 40 次下滚 + 40 次上滚（各 16 ms 间隔）+ 一次 20 步拖动（方向逐轮交替，避免滑杆顶到边界后不再变化），共 280 轮。探针全程抓帧，RSS 每 10 s 采样。

| 指标 | 结果 |
|---|---|
| 存活 | 639 s 后进程仍在，`kill -0` 通过；应用 stderr 中 panic/fatal/error 计数 **0** |
| 抓到帧 / 变化帧 | 38 268 / 28 261（平均 44.3 fps） |
| 逐分钟变化帧率 | 44.0, 44.6, 44.0, 44.2, 44.4, 44.5, 44.3, 44.5, 44.3, 44.5（第 11 段是收尾 38 s，27.9） |
| 逐分钟变化帧间隔 p95 | 33.7–34.0 ms，十段无漂移 |
| 输入→画面延迟 | 第 1 分钟：2633 事件全匹配，中位 8.7 / p95 25.0 ms；第 10 分钟：2643 全匹配，中位 8.3 / p95 23.4 ms |
| RSS | 起始 321 MB → 峰值 1038 MB（前 10 s，四张样张解码）→ 886 → 631 → 结束时 **509 MB**；1 分钟后最小值 509 MB，**无增长趋势**（反而回落） |

结论：10 分钟高频操作下没有崩溃、没有卡死、没有内存增长，帧率与延迟曲线平直。44 fps 而不是 60 fps 的原因在动作本身（每轮 80 个滚轮事件只有 44 帧内容变化，其余是重复帧；与 T2 的 50 fps 同源）。

### 2.10 T10 窗口表面的像素格式与色域（源码，只读）

| | pre (`gpui-pre` 0.3.14) | fast (`gpui-fast` 0.1.19) | zed (`gpui` 0.2.2) |
|---|---|---|---|
| CAMetalLayer 像素格式 | `MTLPixelFormat::BGRA8Unorm` | 同左 | 同左 |
| colorspace | 仅在 `use_display_p3=true` 时设 Display P3；否则不设（层默认 sRGB） | 同左 | 代码里没有任何 `setColorspace` |
| EDR / HDR | 无 `wantsExtendedDynamicRangeContent`，无 16F 窗口面 | 同左 | 同左 |
| opaque / drawable 数 | `setOpaque(!transparent)`、`setMaximumDrawableCount(3)` | 同左 | `set_opaque(false)`、`max 3` |
| 额外层 | 无 | 有：overlay 各用一张 CAMetalLayer，复制 base 的 colorspace | 无 |

出处（本机 cargo 缓存，路径前缀 `/Volumes/UNITEK/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/`）：
- pre：`gpui-pre-apple-0.3.14/src/metal_renderer.rs:186-210`（`configure_layer`；:190 像素格式，:191-197 P3 分支，:202 opaque，:203 drawable 数）。
- fast：`gpui-fast-apple-0.1.19/src/metal_renderer.rs:196-224`（:200 像素格式，:201-207 P3 分支，:212 opaque，:213 drawable 数）；overlay 层：`gpui-fast-apple-0.1.19/src/fast/composition.rs:28-48`（新建 CAMetalLayer + `copy_colorspace`）。
- zed：`gpui-0.2.2/src/platform/mac/metal_renderer.rs:143-146`（`set_pixel_format(BGRA8Unorm)`、`set_opaque(false)`、`set_maximum_drawable_count(3)`）；全 crate 检索 `setColorspace|wantsExtendedDynamicRangeContent|RGBA16Float` 无窗口面命中（只有离屏测试纹理用 16F）。
- `use_display_p3` 默认 false：fast `gpui-fast-0.1.19/src/platform.rs:2926`；pre `gpui-pre-0.3.14/src/platform.rs:2908`。

结论：**三个实现在 macOS 上都是 8 位 BGRA、SDR、默认 sRGB**；没有任何一个能把 HDR/EDR 画面贴到窗口上。要做 EDR 视口，三个都得改平台层（或走自绘 surface + 自己的 CAMetalLayer）。

## §3 文字观感的并排图

样本与图：`shots/t6-text-side-by-side.png`（上：pre；下：fast；原分辨率 2× 截图裁剪，未缩放）。八行内容按顺序：中英混排（默认系统字体）· 同串显式 Helvetica Neue · 纯拉丁 · CJK 生僻字回退（永東國酬愛鬱靈鷹）· 大小写与数字 · 常规字重 · 粗体 · Menlo 等宽 + 中文回退，均为 12 pt、行高 22 点、窗口 1200×800 @ (40,40)、2× backing store。

**结论：像素级没有差别。** 两次运行是不同进程、不同窗口 id（64735 / 64767）、不同后端：

- 整窗 PNG（2400×1600）md5 两边都是 `84e6dc41ec0fe97a1f143fc1b2bc0bad`；
- 文字区（1250×480 = 600 000 像素）逐像素差：**max 0，mean 0，差异像素 0**。

即在这段 12 pt 中英混排样本上，gpui-fast 自带文字系统的字形轮廓、字距、字重、CJK 回退与 Menlo 回退与 pre 逐像素一致。范围限制：只覆盖 12 pt 一个字号、这一台显示器/2× 缩放、这几种字体；其它字号/字重/语言未取样。

## §4 稳定性记录

- **fast 10 分钟压测（T9）**：见 §2.9。无崩溃、无卡死、无未响应；RSS 从 1 GB 级峰值回落到 509 MB 后平稳；逐分钟帧率与输入延迟无退化。
- **本轮全部运行**：pre/fast 原型各启动 20 次以上（T1a/T1b/T2/T5/T8/T9 + 手工），lab 两后端各 4 次，最小程序 8 次 —— 未出现一次崩溃或 hang。唯一一次异常是 T9 首次尝试时窗口 6 s 内没被列出（启动地板 3.8 s + 列表轮询窗口太短），脚本按空 wid 退出，未对被测程序造成影响。
- 机器侧：全程 `caffeinate -dis`，测量前 guard PASS；没有出现内存告警（最高单进程 RSS 1.04 GB，16 GB 机器）。
- **一个环境级观察**：本会话里从 CLI spawn 的 GUI 进程，首个窗口上屏稳定在 2.1–3.8 s（AppKit 对照程序也是 2.1 s，其中 2.09 s 花在 `NSApplication.shared` + makeKeyAndOrderFront 里）。这属于 macOS 会话状态，不是框架缺陷；所有对比都建立在"同一把尺子"上。

## §5 表面格式的源码出处

见 §2.10。

## §6 未测项与原因

- **T8 窗口缩放**：合成事件不触发 WindowServer 的缩放手势（gpui 与 AppKit 对照窗都不动）。需要真实鼠标或程序化 resize；本轮时间不够做后者。
- **方法坑（供后来者）**：同一动作必须用 `--global`（HID tap）发事件。`postToPid` 能送达 `mouseMoved`，但 gpui 的滚动/拖动依赖窗口的 hover 状态，postToPid 不产生真实 hover，滚动事件被静默丢弃 —— 本轮最早两次 T1 就是 0 事件 0 变化帧，换成 `--global` 后立刻正常。另外窗口列表里会残留已死进程的窗口项，启动新实例后必须"取新出现的 window id"，否则探针会抓到死窗口（本轮踩过一次）。
- **启动数字的系统地板**：本机从 CLI spawn 任何 GUI 窗口都要 ~2 s（AppKit 对照实测），T4 的绝对值主要反映这台机器的会话状态，不反映框架差异；差异看 pre/fast 相对值（6 ms）。
- **zed 列**：最小程序只能覆盖启动（已测，§2.4）；文字/列表/外部画面它都没有对应实现，标"不适用"。
- **surface() 的 NV12 支路**：本轮先用 BGRA 测（不绘制），再按源码断言改成 NV12 在 pre 上复测（仍不绘制）。残余不确定 = 我手搓的 CVPixelBuffer 是否真拿到 IOSurface（未在 Rust 侧断言）。下一步：从 Metal 纹理的 IOSurface 直接 `CVPixelBufferCreateWithIOSurface`，或打印 `CVPixelBufferGetIOSurface` 是否为空。
