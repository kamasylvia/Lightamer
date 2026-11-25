# SPIKE-VIEWPORT — gpui-fast 原生表面里的自有 Metal 视口与 EDR

日期 2026-11-25。工作区 `/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike/`（仓外），新 crate `viewport/`。
本文件只写实测；代码读出来的结论逐条标注“代码阅读，未实测”。主体数字来自 `traces/` 下的原始轨迹（`app-run.log`、`frameprobe-v3.txt`、`footprint.txt`、`vmmap-summary.txt`）；早期调试读数来自本轮终端输出，已归档为 `traces/viewport-*.log`；屏幕规格见 `traces/display.txt`；构建时长来自终端观察，未保留构建日志。

## §0 结论表

| 项 | 结论 | 一句话证据 |
|---|---|---|
| V1 放进去并显示 | **成立** | 截图里视口内容占满 800×800pt 区域，四个亮度档的边界在 1600px 截图的 400px 处；`view_frame=(0,0 800x800)`、`layer_bounds=800x800`、`drawable=1600x1600` 三者一致 |
| V2 开 EDR | **有保留地成立** | 层 = `RGBA16Float` + `wantsExtendedDynamicRangeContent=true` + `kCGColorSpaceExtendedLinearSRGB`；drawable 回读 = `0.5/1.0/2.0/4.0`（>1.0 确实写入）。但本机屏幕 `maximumExtendedDynamicRangeColorComponentValue=1.000`（BenQ PD2705U，SDR），**屏幕上是否真以 HDR 显示未验证** |
| V3 叠放与更新 | **成立（有保留）** | 11s 探针：视口区变化 514 帧（46.7/s，中位间隔 17ms），面板区 43 帧（3.9/s），38 帧两者同时变；浮层截图盖住视口且底下内容不穿透；原生表面边界与布局逐值一致。保留项：5 帧只有面板变、视口最大空档 0.333s |
| V4 输入归属 | **未实测**（只读代码） | 默认 `input_forwarding=false`，原生表面挡住 GPUI 命中测试；`on_input` 可把指针事件转给消费者；详见 §1.4 |
| V5 内存 | **成立** | 空闲 `footprint` = 174MB，其中 IOSurface 133MB / 11 块；`IOAccelerator (graphics)` 6416KB |
| V6 无原生表面的退路 | **成立（书面，未实测）** | 动态纹理 = CPU 上传 BGRA8、无 HDR；`surface()` 只收 NV12；没有把现成 GPU 纹理交给 gpui 采样的公开 API |

**gpui 路线能不能保住带 HDR 的自有视口：能。** 视口完全绕开 gpui 的 8 位交换链，走 gpui-fast 的原生合成表面 + 自建 `CAMetalLayer`；gpui 只负责摆放、层级、输入归属。HDR 通路在 API 层全部打通（16F 层 + EDR 标记 + 扩展线性色彩空间 + 回读证明 >1.0）。但**本机显示器没有 EDR headroom**，所以“屏幕上真的更亮”这一条没有证据，换 EDR 屏幕重测前不能算验收。

## §1 逐项细节

### §1.0 crate 与版本

- `gpui-kit = 0.11.0`，`features = ["gpui-fast"]` → 实际后端 `gpui-fast 0.1.19` / `gpui-fast-apple 0.1.19` / `gpui-fast-macos 0.1.19`。
- `objc2 = 0.6`（锁定 0.6.5）+ `objc2-app-kit 0.3.2` + `objc2-quartz-core 0.3.2` + `objc2-core-graphics 0.3.2`。核对过 `gpui-fast-macos 0.1.19` 自己依赖的也是 `objc2-app-kit 0.3.2` / `objc2 0.6`，`gpui-fast-apple` 用 `objc2 0.6`：接 `usize` 用的 `NSView` 与框架同版本。（`cargo tree -i objc2-app-kit@0.3.2` 输出在 `traces/` 未单独留存，命令可复现。）
- 渲染：`metal 0.29.0`（只为 `MTLDevice`/`MTLCommandQueue`/`MTLRenderPipelineState`/`CAMetalLayer` 包装）；色彩空间与会话属性的读写走 objc2。
- 构建：`CARGO_BUILD_JOBS=6 cargo build --offline`；全量依赖编译约 5.5 分钟（含一次本 crate 编译错误），后续增量 37–102s（终端观察，构建日志未留档）。机器 guard：`GUARD PASS (heavy=0 free=72%)`（`traces/machine-guard.txt`）。

调用链（与上一轮侦察一致）：

```
Window::enable_window_composition()            // gpui-fast-0.1.19/src/fast/composition.rs
  -> WindowComposition::create_native_surface()
  -> surface.platform_surface()?.platform_handle()   // macOS: usize = NSView*
  -> 把 NSView.layer 换成 CAMetalLayer
  -> canvas(prepaint).set_bounds(bounds.to_device_pixels(scale))  // 每帧跟随布局
```

### §1.1 V1 — 放进去并显示

做法：

- 窗口 1200×800（`WindowOptions{ titlebar: None }`），左 `flex_1` 视口区、右固定 400pt gpui-kit 面板。
- 视口用 `canvas` 元素承载：prepaint 里取 `Bounds<Pixels>`，`to_device_pixels(scale)` 后调 `PlatformSurfaceAttachment::set_bounds`；这正是 gpui-fast 自己测试里的 `native_host` 写法（`composition.rs` 中 `canvas(... set_bounds ...)`）。
- NSView 由 gpui 创建，默认是普通 `CALayer`（`gpui-fast-macos-0.1.19/src/fast/composition.rs:812-836`）。我们 `setWantsLayer(true)` 后 `setLayer(CAMetalLayer)`，层属性：`device=Apple M4`、`pixelFormat=RGBA16Float`、`framebufferOnly=false`、`opaque=true`、`maximumDrawableCount=3`、`wantsExtendedDynamicRangeContent=true`、`colorspace=kCGColorSpaceExtendedLinearSRGB`。
- 每帧从 `NSView.frame()` 的尺寸 × `window.backingScaleFactor()` 算 `drawableSize`，`nextDrawable()` → 一个全屏三角形 + 片段着色器画四档亮度 `0.5 / 1.0 / 2.0 / 4.0`，底部 28px 画一条扫描标记（让每一帧都有可探测的变化）。`presentDrawable` 每 16ms 一次，主线程 async 循环驱动。

读数（`traces/app-run.log`）：

```
K INIT surface_id=CompositionSurfaceId(3v1) nsview=0x...
K colorspace name=Some(<CFString>{contents = "kCGColorSpaceExtendedLinearSRGB"})
K metal device="Apple M4" layer_pixel_format=RGBA16Float layer_wants_edr=true layer_framebuffer_only=false layer_max_drawables=3
K drawable size=1600x1600 view_points=(0.0,0.0,800.0,800.0) scale=2.00
K drawable texture_format=RGBA16Float texture=1600x1600
K RATE ... view_frame_points=(0.0,0.0 800.0x800.0) scale=2.00 canvas_logical=[0.0, 0.0, 800.0, 800.0] layer_bounds=(0.0,0.0 800.0x800.0) layer_frame=(0.0,0.0 800.0x800.0) drawable_size=1600x1600 contents_scale=2.00 backing_scale=2.00
```

即：布局给 canvas 的 800×800pt、NSView 的 frame、CAMetalLayer 的 bounds、drawable 的 1600×1600（2×）四者一致；视口没有超出/缩进布局。

截图（整窗原图在仓外 `Lightamer-gpui-spike/shots-viewport/`，仓内只放裁剪）：

- `shots/v1-band-edge-and-panel-edge.png`：截图 y=200 行像素实测 —— x `0..399` = (179,179,179)，x `400..1599` = (255,255,255)。四条 400px 的带正好是 1600px 视口的四等分；面板从 x=1600 开始。四个值里 1.0/2.0/4.0 在 SDR 屏上都被削成纯白，所以上半部只看得到第一档与“其余全白”。
- `shots/v1-bottom-strip.png`：底部标记条用 `v*0.25` 画，四档在 SDR 下可区分：实测像素 (88,88,88) / (126,125,126) / (179,179,179) / (255,255,255)，边界同样在 400/800/1200。白块是扫描标记。
- `shots/v1-panel.png`：右侧 gpui-kit 面板（两个真 `Slider` + 文本）。
- 原生表面区域没有露底：除窗口自身的圆角外，整块 1600×1600 像素都被我们的内容覆盖；圆角外是透明/黑，不是 gpui 背景。

### §1.2 V2 — 开 EDR

四项要求读数：

| 项 | 实测 |
|---|---|
| 当前屏幕 `maximumExtendedDynamicRangeColorComponentValue` | **1.000**（`maximumPotential…` 也是 1.000）；屏 = BenQ PD2705U，3008×1692，UI 1504×846@60Hz |
| drawable 像素格式 | `RGBA16Float`（`drawable.texture().pixel_format()` 与 `layer.pixelFormat()` 都是） |
| 层 `wantsExtendedDynamicRangeContent` | `true`（回读 `layer.wants_extended_dynamic_range_content()`） |
| 层色彩空间 | `kCGColorSpaceExtendedLinearSRGB`（`setColorspace` 后打印所写对象的 `CGColorSpace::get_name`；**未**回读 `layer.colorspace` 属性） |

像素回读：渲染后 `MTLTexture::get_bytes` 读 drawable 中间行（`traces/app-run.log`）：

```
K READBACK frame=60 row_y=800 texture=1600x1600 format=RGBA16Float nominal=[0.5,1.0,2.0,4.0]
  samples(x,v)=[(100,0.5),(300,0.5),(500,1.0),(700,1.0),(900,2.0),(1100,2.0),(1300,4.0),(1500,4.0)]
```

同一组 uniform 再渲染到一张 `Shared` 的 1600×1600 `RGBA16Float` 纹理、`get_bytes` 复核，读数逐值相同（`K OFFSCREEN ...`）。所以 **>1.0 的值确实写进了 16F 目标**（2.0 与 4.0 都是 f16 精确值）。

**“屏幕上真的以 HDR 显示”：没有验证，也没法在这台机器上验证。** 屏幕报告的 EDR headroom 是 1.000，即没有高出 SDR 白的分量可放；截图（`screencapture`）本身也会被系统色调映射到 SDR，不能作为 HDR 证据。试过/检查过的：`NSScreen.maximumExtendedDynamicRangeColorComponentValue`、`maximumPotentialExtendedDynamicRangeColorComponentValue`、层属性回读、drawable 像素回读。**没有**找到公开 API 能读“当前呈现的 EDR 亮度”；换一台 EDR 屏幕（XDR/支持 HDR 的显示器）重跑同一程序是唯一干净的验证路径。

一个测量坑（不影响结论，但必须写）：最初用 `MTLBlitCommandEncoder::copyFromTexture:toBuffer:` 把 drawable 行拷到 shared buffer，读到的整行恒为 `0.5`（raw `0x3800`），与截图矛盾；换成同一张 drawable 的 `get_bytes` 后读数正确。**blit 路径在本环境不可信**，最终证据以 `get_bytes` 与独立离屏纹理两路为准。

### §1.3 V3 — 与界面的叠放和更新

程序行为：

- 视口每 16ms 重画（60Hz 循环）。
- 面板每 250ms 改一次两个 `SliderState` 的值 + tick 文本 + `cx.notify()`（约 4Hz gpui 重绘）。
- 浮层 = `deferred(div().absolute())`，位于 (60,60)、640×300pt，每 2.5s 自动开/关（定时器切状态，不合成任何输入）。

探针：`measure/frameprobe-regions`（现有 `FrameProbeDense.swift` 的**派生副本**：同一 480×400 密集网格、同一阈值 `d>10`，仅加了按区域计数；不改输入、不发事件）。区域 = 视口 `x∈[0,0.6667)`、面板 `x∈[0.6667,1]`。原始轨迹 `traces/frameprobe-v3.txt`。

11.00s 窗口内（`traces/frameprobe-v3.txt`，`mark begin`/`end` 之间）：

| 指标 | 数值 |
|---|---|
| SCK 交付帧 | 660 帧 / 11.00s = 60.0fps，中位间隔 16.55ms，p95 19.20ms |
| 视口区有变化的帧 | **514**（46.7/s），中位间隔 17ms，最大空档 0.333s |
| 面板区有变化的帧 | **43**（3.9/s，与 250ms 定时器一致） |
| 两区同时变化 | 38 帧 |
| 只有面板变化 | 5 帧 |
| 两区都没变化 | 141 帧（SCK 重复帧/采样网格未命中的合计） |

结论：**在 11s 探针窗内，视口在界面重绘期间持续更新**（面板变化的 43 帧里有 38 帧视口同帧也在变；视口独立于 gpui 的 repaint，因为它是自己的 display 循环）。保留：5 帧只有面板变、以及 0.333s 最大空档，说明 60Hz 循环不是硬实时；本 spike 不判断这是 Metal 调度、SCK 采样还是主线程偶发卡顿。探针窗之外还有一段更长的主线程停顿：`traces/app-run.log` 里 t=21.79s（tick 87）到 t=24.67s（RATE 1291，+99 帧）之间 4.49s 只有约 22fps，期间没有 OVERLAY/RATE 行；这段在 probe 窗（app t≈5.6–16.6s，按 `kern.boottime` 对齐）之外，所以不改变上面的窗内统计，但“长时间稳定 60fps”**没有**被证明。另：视口 46.7/s 而不是 60/s，与标记条在 480 列采样网格上的混叠/SCK 重复帧一致。

**浮层压得住**：`shots/v3-overlay-over-viewport.png` 里 `deferred` 弹层（640×300pt @ 60,60）完整盖住视口上的档位边界（x=400 的灰/白分界在弹层矩形内不可见），弹层外边界照常可见。层级来自 gpui-fast 的合成树：base（gpui 根场景）< native surface < overlay（deferred）——与源码一致。

**原生表面边界与布局一致**：§1.1 的四组几何读数逐值相等；截图里视口内容的四等分边界在 1600px 的 400px 处，面板从 1600px 开始。

### §1.4 V4 — 输入归属（只读代码，未实测）

默认路径（`input_forwarding()` 缺省 `false`，`gpui-fast-0.1.19/src/fast/composition.rs:349-352`）：

1. GPUI 的命中测试先把原生表面当遮挡物：`hit_test`（`composition.rs:694-731`）逆序遍历输入层，遇到原生表面矩形就 `break` —— 它后面的 GPUI 命中框一个都不进结果。
2. macOS 的窗口级 `sendEvent:` 拦截（`gpui-fast-macos-0.1.19/src/fast/composition.rs:324-423`）对“没有 forwarder 的原生表面”走 `PointerRoute::AppKit`，最后 `msg_send![super(this, superclass), sendEvent: event]`（:423）把事件交回 AppKit。
3. AppKit 把它投给命中的 `NSView`——就是 gpui 建的那个普通 `NSView`（`gpui-fast-macos-.../fast/composition.rs:812-836`）。它没有 `mouseDown:` 等实现，按 responder chain 往上走；但 GPUI 侧的 `native_mouse`/`bubble_mouse`（`gpui-fast-0.1.19/src/fast/composition.rs:1579-1598`）在指针位于原生表面时抑制 GPUI 监听器。

**净效果（代码推导）**：点在视口上，默认不会命中任何 GPUI 命中框（bubble 阶段被 `bubble_mouse` 抑制），也不会被普通 NSView 处理——对 GPUI 的常规点击处理与原生视图都是惰性的。注意 GPUI 的 capture 阶段监听器仍会看到该事件（`dispatch_mouse_event` 先跑 capture），所以“点外部关弹层”这类 capture 逻辑不受影响。要让某一方收到，两条路：

- **让 GPUI 处理**：`WindowComposition::on_input(surface_id, handler)`（`composition.rs:948-990`）注册消费者并置 `input_forwarding=true`；之后 `dispatch_native`（`composition.rs:1635+`）把 `PlatformInput::{MouseDown,MouseUp,MouseMove,Scroll}` 交给 handler，坐标是窗口内容逻辑像素。注意：这**不会**把事件再发给 GPUI 的 hitbox，只给你的闭包。
- **让我们的视图处理**：保持原生表面，但把 `NSView` 换成自己的子类（或加 tracking area），实现 `mouseDown:/mouseDragged:/mouseUp:/scrollWheel:`；键盘再加 `acceptsFirstResponder`。合成路径已经把“非 forwarder 的按下”交回 AppKit，所以子类能收到。**未实测**。
- 浮层（deferred）在原生表面之上：`hit_test` 的逆序遍历里 overlay 的命中框先于 native 被看到，所以浮层可点、其下的视口点击仍被原生表面挡住（代码阅读，未点击验证）。

### §1.5 V5 — 内存

空闲（26s 后视口与面板循环都停，窗口保持）实测：

```
footprint: 174 MB
  133 MB  11 regions  IOSurface
 6416 KB  68 regions  IOAccelerator (graphics)
vmmap --summary: IOSurface 133.2M 133.1M 11 regions
```

归因（推断，非逐块实测）：我们自己的 `CAMetalLayer` = 3 块 1600×1600×8B = 61.4MB；gpui 窗口自己的层也是 3 块 2400×1600×4B = 46.1MB；合计 107.5MB，剩 ~26MB 是其它合成面/阴影。与 gpui-kit #3946 的“3–4 块窗口大小 drawable”一致，且这里是**两套**（gpui 自己的 + 我们的视口），所以 IOSurface 总量比纯 gpui 窗口高一倍左右。11 块 IOSurface 与 6 块主 drawable 的差额未逐块归因。

### §1.6 V6 — 没有原生表面时的退路（书面，未实测）

- **动态纹理**（`Window::create_dynamic_texture/update_dynamic_texture`，`gpui-fast-0.1.19/src/fast/dynamic_textures.rs:405-468`）：CPU 上传 BGRA8、tightly packed，进 gpui 的 sprite/atlas 管线。代价：每帧 GPU→CPU→GPU 往返（或至少在 CPU 侧准备一整帧），只有 8 位 SDR，>1.0 直接丢；100MP 视口不可行。**无 HDR**。
- **`surface()` / `paint_surface`**（`elements/surface.rs`，`metal_renderer.rs:1296-1300`）：只接受 `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`（NV12）。上一轮实测“不出画”，且是视频帧通道，不适合 RGBA 视口。
- **没有公开 API 把现成 `MTLTexture` 交给 gpui 采样**：`DynamicTexture::new_gpu` 只登记尺寸/版本，GPU 内存由 renderer crate 自持（`dynamic_textures.rs:17-21`、`gpui-fast-apple/.../fast/dynamic_textures.rs:89-105`）。零拷贝只剩原生表面，或 fork renderer。
- gpui-pre（默认后端）没有 `enable_window_composition`/`create_native_surface`/dynamic texture，所以“换回 pre”等于放弃自有视口。

## §2 卡点与解法

1. **`[[position]]` 在片段着色器里不是像素坐标（本环境）**：全屏三角形 + `in.pos.x / (u.w*0.25)` 得到四档全 0.5；用“把 `x/u.w` 写进颜色再回读”的探针测得片段坐标只有光栅坐标的 1/4（1600px 光栅上 x=100 对应着色器 x≈25.5）。改成顶点着色器输出 `uv`（0..1）由片段插值取档，问题消失。**这是本 spike 唯一影响画面的坑**；未见 gpui 文档提及，可能与本机 Metal 4 / drawable 组合有关。
2. **drawable 的 blit 回读不可信**：`copyFromTexture:toBuffer:` 读回整行恒 0.5（raw 0x3800），与截图/离屏渲染矛盾；同一张 drawable 的 `get_bytes` 正确。最终证据链 = `get_bytes`（drawable）+ 离屏 `RGBA16Float` 同管线复核。后续若做像素级验收，别用这条 blit 路径。
3. **SCK 看不到刚开的窗口**：`frameprobe list` 在 app 启动 ~3s 内查不到窗口，6 次轮询（每次约 1s）后才出现；第一次截图因此拿空 window id 失败。规避 = 启动后轮询到窗口出现再截。
4. **本机屏幕无 EDR headroom**：`maximumExtendedDynamicRangeColorComponentValue=1.000`。层/格式/色彩空间全对，但“屏幕更亮”在这台机器上不可证；截图是 SDR 色调映射，不能当 HDR 证据。
5. **`gpui-fast` 仍是 0.1.x**：合成路径在收敛期（#157/#165/#167、#3946、#4057），API 每周可能变；本 spike 的代码只对 0.1.19 负责。
6. **gpui 版本混用陷阱**：`objc2-app-kit` 同时有 0.2.2（accesskit_macos）与 0.3.2（gpui-fast-macos/gpui-base）；接 `usize` 必须用 0.3.2 这一套，否则 `NSView` 类型不是同一个绑定版本。

## §3 对架构的含义（UI 若用 gpui 族）

1. **视口 = 一个原生合成表面 + 一个自建 `CAMetalLayer`，与 gpui 的交换链完全解耦。** 8 位限制、EDR 缺失、gpui 的 drawable 内存都只作用于窗口层；视口自己的格式/色彩空间/呈现节奏由我们定。这是纯 Rust UI 路线保住 Apple 显示能力的关键缝。
2. **每个视口一份 `CAMetalLayer`，不要放进滚动容器。** gpui-fast #4057 的残帧问题出在滚动层缓存与 `set_bounds` 不重跑；视口应该是固定布局区（或自己处理滚动）。
3. **呈现循环自己拿**（本 spike 用 16ms 主线程 async 循环）。不要依赖 gpui 的 `cx.notify()` 驱动视口；gpui 重绘与视口刷新必须解耦，否则面板一忙视口就掉帧。反过来，`cx.notify()` 不要每帧调（gpui 文档明确每帧 notify 会退化全量重绘）。
4. **输入要显式设计**：视口区域默认吞指针。二选一：`on_input` 把指针事件交给 Rust 消费者（适合“视口自己处理手势/工具”），或自建 `NSView` 子类接收原生事件（适合需要 AppKit 手势/滚轮/键盘焦点）。浮层用 deferred 放在原生表面之上，预期可点（代码路径如此，**未点击验证**）；但**浮层底下的视口点击仍被原生表面挡住**，弹层关闭后要检查点击穿透策略。
5. **HDR 验收必须绑定显示器**：程序侧能证明的只到“16F + EDR 标记 + >1.0 像素写入 drawable”。产品验收要在 EDR 屏上做；CI/本机只能做数值断言。
6. **平台面**：本 spike 只验证 macOS。Windows 的原生表面是 `IDCompositionVisual`、Linux 是 `RawWindowHandle`（`composition.rs:324-359`），各自的 EDR/HDR 合成语义完全不同，**未验证**。gpui-fast 的 macOS 合成路径仍在收敛（#3946/#4057），升级版本要重跑本 spike 的 V1/V3。

## §4 没验证的

- **屏幕上是否真以 HDR 显示**：本机 SDR 屏（headroom 1.000），无公开读数 API；未验证。
- **V4 的鼠标/键盘行为**：只读代码，按要求未合成任何输入事件；`on_input` 与自建 `NSView` 子类两条路都未实跑。
- **浮层上的点击**是否真的先于原生表面命中（代码推导；未点击）。
- **缩放/拖拽窗口时** `set_bounds` 与 `drawableSize` 的跟随：只在 1200×800 固定窗口测过；未测 live resize。
- **多视口**（两个原生表面同时存在）、**滚动容器中的视口**（#4057 场景）、**显示器切换/EDR 屏幕**：未测。
- **Windows / Linux**：未测；本 spike 没有非 macOS 构建。
- **`gpui-fast` 升级后**的行为：未测；只对 0.1.19。
- **drawable blit 回读异常**的根因：未定位；只记录了现象与可用替代路径。

## §5 工作区保留内容与大小

仓内 `.work/gsd/phases/gpui-viewport/`（`du -sh` = **592KB**）：

- `SPIKE-VIEWPORT.md`（本文件）
- `src/`（244KB）：`Cargo.toml`、`Cargo.lock`、`main.rs`，全量源码，无构建产物
- `shots/`（192KB，4 张裁剪）：`v1-band-edge-and-panel-edge.png`、`v1-bottom-strip.png`、`v1-panel.png`、`v3-overlay-over-viewport.png`
- `traces/`（108KB）：`app-run.log`（全部 K 行）、`frameprobe-v3.txt`（原始逐帧/逐区域）、`vmmap-summary.txt`、`footprint.txt`、`machine-guard.txt`、`display.txt`（屏幕规格）、`viewport-*.log`（早期调试轮，支撑 §2 的 1/4 坐标与 0x3800 读数）
- `spike-review.log`（4.8KB，域内复审输出）

仓外工作区：

- `/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike/viewport/`（244KB）：crate 源码；`target/` 实测 **3.8GB**，按“>2GB 就删”规则**已删除**（删前 `du -sh` 记录在此）
- `/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike/shots-viewport/`（1.3MB）：三张整窗原图（`v1-bands.png`、`v3-overlay.png`、`v1-idle.png`，各 2400×1600）
- `/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike/measure/frameprobe-regions`（164KB）+ `FrameProbeRegions.swift`（24KB）：区域计数版探针（现有 dense 探针的派生副本，同一网格/阈值，只加区域计数）
- `/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike/omp-viewport-summary.md`（4KB）

产品树零改动；零 commit、零 push。

## §6 复审记录

复审实例：独立 `omp -p --auto-approve --thinking max`（只读），输出全文在 `spike-review.log`。
结论头：**PASS / 3 error + 6 minor**。以下为逐条处置（修订后已复检）。

### error → 处置

1. **“域内自审未产出 / 报告末尾无修订记录”** → 本条是复审时的快照：`spike-review.log` 当时只有 `Working...`，现在已是 4.8KB 的复审全文；本节即修订记录，§5 的 `spike-review.log` 条目改为实际大小。
2. **target 3.8G 未删、§5 无实测大小** → 已 `rm -rf viewport/target`（删前实测 3.8GB）；§5 现列各目录 `du -sh` 实测值与保留清单。
3. **“数字全部来自 traces”不成立（free% 71≠72、构建时长/屏幕规格无轨迹）** → 首段改为按来源分列：主体数字来自 traces；早期调试读数归档到 `traces/viewport-*.log`；屏幕规格归档到 `traces/display.txt`；构建时长标注“终端观察，未留构建日志”。`free=71%` 改为实测 `72%`。

### minor → 处置

1. drawable 尺寸来源 bounds → 改为 `NSView.frame()` × `backingScaleFactor()`（与 `src/main.rs:189-196` 一致）。
2. 色彩空间“回读” → 改为“打印所写对象的 `CGColorSpace::get_name`；未回读 `layer.colorspace`”。
3. 探针窗外的 2.88s/4.49s 主线程停顿 → 已写入 §1.3，并把“持续更新”限定在 11s 探针窗内；明确“长时间稳定 60fps 未被证明”。
4. “浮层即可点”与“未点击”口径不一致 → §3.4 改为“预期可点（未点击验证）”。
5. `v1-idle-band-edge.png` 与 band 边界裁剪逐字节相同 → 已删除该重复裁剪；`shots/` 现为 4 张。
6. `sendEvent:` 行号 324-418 → 改为 324-423 并点名 :423。

修订后未再发现新的数字冲突；复审提出的 3 error / 6 minor 全部关闭。
