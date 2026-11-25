# R2 — gpui-fast 图像编辑器能力侦察

只读调研：不编译、不启动图形程序、不写仓外工作区、不提交。
一手材料 = 本机依赖缓存 `R=/Volumes/UNITEK/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f`：
`gpui-pre-0.3.14`（gpui-kit 默认后端）、`gpui-fast-0.1.19`，及同族平台 crate（`-apple`/`-macos`/`-linux`/`-windows`/`-wgpu`/`-web`/`-scheduler`）。
正文省略 `$R/` 前缀；行号指 `src/` 下文件。

口径：**有** = 公开 API + 可用；**部分** = 有接口但带硬约束或单平台；**没有** = 源码确认无；**没查到** = 无证据，不推断。

---

## §0 能力表

| # | 能力 | gpui-pre | gpui-fast | macOS | Windows | Linux |
|---|---|---|---|---|---|---|
| 1 | 外部 GPU 画面进窗口 | 部分：仅 `paint_surface`（CVPixelBuffer/NV12） | **有**：native surface portal / external GPU surface / dynamic texture | 有 | 有 | 有 |
| 2 | 交换链格式与色彩 | 部分：BGRA8，无 HDR | 部分：BGRA8，无 HDR | BGRA8Unorm，可选 Display P3，**无 EDR** | B8G8R8A8_UNORM，无 HDR | BGRA8/RGBA8，`color_space=Auto`，无 HDR |
| 3 | 文字 CJK/回退/IME | 有 | 有（同源 + 缓存/CJK 修复） | CoreText | DirectWrite | cosmic-text（harfrust/fontdb/swash） |
| 4 | 无障碍 | 有（AccessKit 全量） | 有（同版 + retained 回放） | NSAccessibility | UIA | AT-SPI（`accesskit_unix`） |
| 5 | 线程与调度 | 有 | 有（同 API，`jiff` 替 `chrono`） | GCD | 线程池 | 线程池 |
| 6 | 布局/停靠/可拖分栏 | 有（gpui-base 提供，与后端无关） | 有（同一份代码） | 有 | 有 | 有 |
| 7 | 大图与大列表 | 部分：`img` 进 atlas；`list` 每帧重排 | **有**：dynamic texture + 行级分层列表 | 有 | 有 | 有 |
| 8 | pre→fast 改动量 | — | 小：别名切换 + `paint_layer` 签名 | — | — | — |
| 9 | 平台覆盖 | 见 §9 | 见 §9 | 完整 | 完整 | 完整（Wayland/X11） |

一句话：**图像编辑器的三件硬需求（自有 GPU 画面、大图逐帧更新、十万行列表）在 gpui-fast 都有第一手接口；HDR/EDR 在 pre 与 fast 都没有——那是共同缺口，不是切后端的代价。**

---

## 1. 外部 GPU 画面怎么贴进窗口

gpui-fast 有四条互不替代的路径。

### 1.1 路径 A：native surface portal（结构最正，三桌面平台）

公开调用链：

1. `Window::enable_window_composition()` → `WindowComposition`
   `gpui-fast-0.1.19/src/fast/composition.rs:1262`；根导出 `src/gpui.rs:131-135`。
2. `WindowComposition::create_native_surface()` → `WindowCompositionSurface`
   `composition.rs:999`。
3. `surface.platform_surface()?.platform_handle()?`
   `composition.rs:936`、trait `composition.rs:324-359`。
   返回：macOS = `NSView` 指针（`usize`）；Windows = `IDCompositionVisual`；Linux = `raw_window_handle::RawWindowHandle`（trait doc `composition.rs:355-358`）。
4. 你在该表面上自建 GPU 上下文并绘帧（自有 swapchain / `wgpu::Surface` / `CAMetalLayer`）。GPUI 只负责摆放、层级、可见性、输入归属。

平台落点：

- **macOS**：新建 `NSView`，`setWantsLayer=YES`，加入窗口视图树，返回 `MacNativeSurface`——`gpui-fast-macos-0.1.19/src/fast/composition.rs:812-836`。
  注意：默认是普通 `CALayer`，**不是** `CAMetalLayer`；要用 Metal 需自行把 `view.layer` 换成 `CAMetalLayer`（`wantsLayer` 已真，可换）。
- **Windows**：DirectComposition，返回内部持 `IDCompositionVisual` 的 `Portal`——`gpui-fast-windows-0.1.19/src/window.rs:1068-1074`、`src/fast/composition.rs:112-127`。
- **Linux**：Wayland 建 `wl_subsurface`，X11 建子窗口——`gpui-fast-linux-0.1.19/src/fast/composition/wayland.rs:733/743`、`x11.rs:1139/1153`；平台 trait 实现 `linux/wayland/window.rs:2120/2124`、`linux/x11/window.rs:1829/1833`。

输入：原生表面默认吞指针（`input_forwarding()` 默认 false，`composition.rs:349-352`）；需要 GPUI 处理外部点击时用 `WindowComposition::on_input(id, ...)`（`composition.rs:954`）。

**pre：不存在。** `gpui-pre` 的 `Platform` trait 没有 `enable_window_composition`/`create_native_surface`/`set_composition_order`/`draw_composed`（`gpui-pre-0.3.14/src/platform.rs` 零命中），`src/` 也无 `fast` 模块（98 个 `.rs` vs fast 191 个）。

### 1.2 路径 B：注册自有平台表面

已有现成平台表面时：`WindowComposition::create_external_gpu_surface(Rc<dyn PlatformSurfaceAttachment>)`
`composition.rs:1009-1016`。

`PlatformSurfaceAttachment` 由你实现（`composition.rs:324-359`），但 `platform_handle()` 必须返回平台认识的类型：

- macOS：`usize` → `NSView`；否则 `synchronize_platform_order` 报 “native surface is not backed by an AppKit view”——`gpui-fast-macos-.../src/fast/composition.rs:919-928`。
- Windows：`IDCompositionVisual`——`gpui-fast-windows-.../src/fast/composition.rs:413-420`。
- Linux：`RawWindowHandle`。

**「外部 GPU 画面」在 API 上的真实含义 = 共享平台合成面，不是共享 GPU 纹理。**

### 1.3 路径 C：dynamic texture（CPU 上传，跨平台最省事）

```
Window::create_dynamic_texture(size, bytes, bytes_per_row) -> Result<DynamicTexture>
Window::update_dynamic_texture(tex, bounds, bytes, bytes_per_row) -> Result<()>
Window::refresh_dynamic_texture(tex) -> Result<()>       // GPU 侧写完后登记版本
Window::paint_dynamic_texture(bounds, tex) -> Result<()> // 仅 paint 阶段
Window::remove_dynamic_texture(tex)
```

定义：`gpui-fast-0.1.19/src/fast/dynamic_textures.rs:405/431/449/459/468`。

- 格式硬约束：**BGRA8**、tightly packed（`BYTES_PER_PIXEL=4`，`:36`）；`bytes_per_row` 可带 padding，内部重排。
- 纹理独立于 sprite atlas，重复更新不重排字形/图标（模块 doc `:1-21`）。
- 版本号随 `update`/`refresh` 递增，scroll-layer 的 tile 哈希包含版本 → 缓存帧会重画（`:459-470`）。
- 后端：macOS `MetalDynamicTextures`（`gpui-fast-apple-.../src/fast/dynamic_textures.rs:232`，`MTLStorageMode::Shared` 优先 `:219-228`）；Linux `WgpuDynamicTextures`（`gpui-fast-wgpu-.../src/fast/dynamic_textures.rs:611`）；Windows `DirectXDynamicTextures`（`gpui-fast-windows-.../src/fast/dynamic_textures.rs:101`，`DXGI_FORMAT_B8G8R8A8_UNORM` `:166`）。
- 限制：平台暂存上传未排空时 `update` 返回 Err，旧内容保留（doc `:435-447`）。

**pre：没有。** `gpui-pre` 全 crate 无 `dynamic_texture` 命中。

### 1.4 路径 D：`paint_surface`（CVPixelBuffer，macOS 专属）

`surface(source)` 元素 → `Window::paint_surface(bounds, CFRetained<CVPixelBuffer>)`
`gpui-fast-0.1.19/src/elements/surface.rs:13/35/114`、`src/window.rs:5703`；pre 同文件 `surface.rs` 逐字节相同，`window.rs:5649`。

**硬约束：只接受 `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`（NV12 全范围）**，否则渲染时 `anyhow::ensure!` 报错：

- fast：`gpui-fast-apple-.../src/metal_renderer.rs:1296-1300`
- pre：`gpui-pre-apple-.../src/metal_renderer.rs:1267-1271`

实现 = 两平面经 `CVMetalTextureCache` 变 `R8Unorm`+`RG8Unorm`，shader 内转（`:1305-1335`）。**这是视频帧通道，不是 RGBA 图像视口通道**；SDR、YUV、full-range。且**不依赖 window composition**：`draw_surfaces` 在普通 scene 绘制路径里调用（`metal_renderer.rs:879`）。

### 1.5 路径 E：`NativeView`（嵌入自有 NSView，macOS only，两版都有）

`NativeView::new` 非 macOS 直接失败（doc：fast `src/window/native_view.rs:32-35`；pre `:33`）。语义：合成在 GPUI 内容之下、原生命中测试之上；焦点在该 view 时键盘直通。适合「已有 NSView + CAMetalLayer」的宿主。

### 1.6 纹理共享的真实边界

- **没有公开 API 把已有 `MTLTexture`/`wgpu::Texture`/`ID3D11Texture2D` 交给 GPUI 采样。**
  `DynamicTexture::new_gpu(size)`（`dynamic_textures.rs:104`）只登记尺寸与版本，doc 明说 GPU 内存由 renderer crate 自持（`:17-21`）；Metal 查找表只由 CPU 上传填充（`gpui-fast-apple-.../src/fast/dynamic_textures.rs:89-105`），公开面没有注入入口。
- 所以零拷贝只有两条：**(a) 原生表面 portal**（你的上下文直接画到合成面，GPUI 不采样，OS 合成器叠层）；**(b) 改 renderer crate**（`pub(crate)` 面，需 fork/PR）。
- macOS 可行组合：`create_native_surface` → 取 `NSView` → 换 `CAMetalLayer` → `wgpu::SurfaceTargetUnsafe::CoreAnimationLayer` 或裸 Metal。Linux 官方示例已走通同构形态（下条）。

### 1.7 示例

官方示例 `crates/gpui_perf/examples/native_webview.rs`（README「Window composition」：`cargo run -p gpui_perf --example native_webview`）。

- Linux 段：`create_native_surface()` → `platform_handle()` downcast 成 `RawWindowHandle` → `wgpu::Instance::create_surface_unsafe` → 自建 pipeline 绘帧，每帧 `request_animation_frame`——`native_webview.rs:650-676`、`:914-921`（本机取回 `/tmp/native_webview.rs`）。
  这正是图像视口的同构形态：GPUI 给表面，自己往上画。
- macOS/Windows 段用 `create_native_surface` + 平台原生控件（WKWebView / WebView2）——`native_webview.rs:522/590`。
- **没有**「直接传一张 RGBA 纹理」的示例——因为不存在该 API。

### 1.8 已知坑

- **PR #157（merged，0.1.19 已含）**：原生表面放在 `overflow_y_scroll` 里时，滚动帧走 layer 缓存不重跑 prepaint，`set_bounds` 不调用，表面不跟滚。修复 = 统计 `surfaces_placed`（`fast/composition.rs:622`、`fast/layers/policy.rs:117`），持有表面的容器退出 layer。残留：layer 试探帧仍用更宽 mask 预绘，跨视口边缘可能被裁一帧；overscan 中未显示行可能被放到列表外。正文：`gh api repos/longbridge/gpui-fast/issues/157`。
  对我们的含义：**视口不要放进滚动容器**；面板内嵌原生表面要注意。
- **PR #165（merged）**：同一问题的裁剪侧修复。
- **X11 无合成管理器**时 overlay 靠「从原生内容挖洞」（README 表格原话 `cut out of the native content without one`），视觉正确性依赖 WM/compositor。
- macOS 的层序/输入路由是 fast 专有逻辑（`fast/composition.rs`），pre 无对应 API。

---

## 2. 交换链像素格式与色彩

### 2.1 结论

**两版、三平台，全部 8-bit SDR；源码零命中 EDR/HDR。**

- `wantsExtendedDynamicRangeContent`：pre/fast 的 apple、macos、linux、windows、wgpu crate **0 命中**。
- `rgba16Float`/`Bgra10`/`scRGB` 作窗口表面：**0 命中**（仅 `Depth32Float` 深度与测试用 16F，不在呈现路径）。

### 2.2 macOS

`MetalRenderer::configure_layer`：

- `layer.setPixelFormat(MTLPixelFormat::BGRA8Unorm)` — fast `gpui-fast-apple-.../src/metal_renderer.rs:200`；pre `gpui-pre-apple-.../src/metal_renderer.rs:190`。
- 宽色域：仅 `use_display_p3 == true` 时 `layer.setColorspace(DisplayP3)` — fast `:201-209`；pre `:191-199`。
- `use_display_p3` 来源 `WindowOptions.use_display_p3`（fast `src/platform.rs:2793`；pre `:2775`），默认 `false`（fast `:2926`）。**仅 macOS 字段**。
- `maximumDrawableCount=3`、`opaque`、`allowsNextDrawableTimeout=false` — `:211-221`。
- 合成窗口的每个 overlay 层复制 base 层色彩空间（`gpui-fast-apple-.../src/fast/composition.rs:42-49`），P3 能贯穿 overlay，但仍 8-bit。

### 2.3 Windows

- 渲染目标常量 `DXGI_FORMAT_B8G8R8A8_UNORM` — `gpui-fast-windows-0.1.19/src/directx_renderer.rs:29`。
- swapchain 用该格式：`:1383`（`Format: RENDER_TARGET_FORMAT`），`FLIP_SEQUENTIAL`；Composition 路径 `CreateSwapChainForComposition`，HWND 路径 `CreateSwapChainForHwnd`（`:1397/1426`）。
- **无** `SetColorSpace1` / `DXGI_COLOR_SPACE_*` / HDR 元数据（全 crate 0 命中）。

### 2.4 Linux（wgpu）

- 表面格式：优先 `Bgra8Unorm` → `Rgba8Unorm` → 「第一个非 sRGB」— `gpui-fast-wgpu-.../src/wgpu_renderer.rs:398-414`。
- `color_space: wgpu::SurfaceColorSpace::Auto` — `:471`。
- 呈现模式 `Fifo` 兜底，可被 `preferred_present_mode` 覆盖 — `:473-478`。
- 无 HDR/宽色域配置项。

### 2.5 对图像编辑器的含义

- 视口要显示 >1.0 高光（EDR），**gpui 这条路给不了**。可行做法 = §1.1 原生表面，自配 `CAMetalLayer.wantsExtendedDynamicRangeContent = true` + `.rgba16Float`——完全绕开 gpui 交换链，代价是自管呈现与色调映射。
- SDR 宽色域只有 macOS 的窗口级 Display P3 开关；Windows/Linux 无对应项。
- pre 与 fast 在这块逐行同构：**切后端不改变色彩能力**。

---

## 3. 文字

### 3.1 两版同源，差异只在缓存与 CJK 修复

**pre**

- 核心 crate 无 cosmic-text/swash/fontdb/harfbuzz；文字依赖只有 `icu_segmenter 2.3`（compiled_data）、`ttf-parser 0.25`（仅 SVG 文本，`svg_renderer.rs:47`）、`unicode-segmentation 1.10`（`gpui-pre-0.3.14/Cargo.toml:375,558,561`）。
- macOS 排版 = CoreText：`AppleTextSystem`（`gpui-pre-apple-.../src/text_system.rs:57`），`CTLine` 的 `layout_line`（`:540`）取 glyph/advance；字体枚举走 `zed-font-kit 0.14.1`（`gpui-pre-apple/Cargo.toml:94`）。
- 换行 = ICU：`text_system/line_wrapper.rs:545` 调 `icu_segmenter::LineSegmenter::new_for_non_complex_scripts`；整形后路径同源（`line_layout.rs:224`）。
- 回退：`text_system/font_fallbacks.rs` 只是用户名单容器；链在 `gpui-pre-apple/src/open_type.rs:105-170` 组成——用户字体描述符 + `cascade_list_for_languages(font, CFLocaleCopyPreferredLanguages())`，**按语言而非 script**，逐字符由 CoreText 在 cascade 中选。无自带枚举器。
- 字体加载有 `'m'` 守卫：度量表无 `m` 的字体被跳过（`gpui-pre-apple/src/text_system.rs:305-323`）。

**fast**

- 同一断行实现：`text_system/line_wrapper.rs:546`（文件仅多一行修改头）。`fast/line_break.rs` 仅 `#[cfg(test)]`（`fast/mod.rs:34-35`，文件自述「规则保留为测试」`:6-10`），**不参与排版**。
- `fast/text.rs` 重写测量与预绘：`layout_text:196`、`measure_text:373`、跨帧收养 `adopt_measurement:325`、`LineShaping/RecentShapes:738-816`；数字免整形 `number_shaping.rs:1-30`（挂 `text.rs:743,790`）。
- `fast/glyphs.rs` 只改光栅量化（`quantize_origin:24`），不碰 shaping。`fast/interactive_text.rs:1-31` 是点击区/hitbox，与 IME 无关。
- macOS 增量：`AppFallbacks`（应用自带字体进 cascade，`gpui-fast-apple/src/fast/font_fallbacks.rs:31,63,78`）、`SizedFonts`（按尺寸缓存 CTFont，`.../fast/text_system.rs:11,24`）、sbix 彩色位图、合成斜体；`'m'` 守卫已删。
- `fast/truncation.rs:1-20` 按整形宽度重截断（修 CJK 全角标点溢出）。
- 原生 IME 与 pre 逐字节相同（`gpui-fast-macos/src/window.rs:3686-3797` vs pre `:3661-3772`）；web 侧新增 `fast/ime_position.rs`、`ime_edit.rs`、`ime_keys.rs`。

**CJK 结论**：逐字换行与标点禁则由 ICU 的 UAX#14（CL/CP/EX/IS/NS/OP）提供 = 基本行首/行尾禁则；**无追い出し/追い込み**（不挤压、不推出）。两端同源。

**API 差异**：`TextSystem` 全部 `pub fn` 同名同签名（pre `text_system.rs:252-515` / fast `:253-512`）；`Window::text_system`/`text_style`/`rem_size` 同名（pre `window.rs:2823,2828,3507` / fast `:2856,2861,3537`）；`elements/text.rs` 的 `Text/StyledText/TextLayout/InteractiveText` 一一对应，唯一可见差异是 `TextLayout` 字段由私有变 `pub(crate)`。`font_fallbacks.rs` 两边逐字相同。

### 3.2 各平台实现

| 平台 | 排版 | 证据 |
|---|---|---|
| macOS/iOS | CoreText（font-kit 枚举） | `gpui-pre-apple/src/text_system.rs:57` |
| Linux | `gpui_wgpu::CosmicTextSystem` | `gpui-pre-linux/src/linux/text_system.rs:1`、`platform.rs:130` |
| Windows | `DirectWriteTextSystem`（非 cosmic） | `gpui-pre-windows/src/platform.rs:191`、`direct_write.rs:36` |
| Web | `WebTextSystem` 包 cosmic | `gpui-pre-web/src/text_system.rs:11,62` |

cosmic-text 0.19 实际拉入 `harfrust 0.5`、`fontdb 0.23`、`swash 0.2.6`（`cosmic-text-0.19.0/Cargo.toml:128,132,174`；启用 `gpui-pre-wgpu/Cargo.toml:66,133`）。

### 3.3 输入法（IME）

- 抽象：`EntityInputHandler`（`input.rs:26`）、`PlatformInputHandler`（`platform.rs:2120`）。
- macOS：`NSTextInputClient`（`gpui-pre-macos/src/window.rs:213`，回调 `:3661-3772`；fast `:3686-3797`）。
- Windows：IMM32，`WM_IME_STARTCOMPOSITION`/`WM_IME_COMPOSITION` → `ImmGetContext`（`gpui-fast-windows/src/events.rs:155/156/1502`）。
- Linux：Wayland text-input（`gpui-fast-linux/src/linux/wayland/window.rs:1089-1091`）；X11 XIM（`linux/x11/xim_handler.rs`，fast 多一层握手守卫 `fast/xim.rs:18`、`x11/client.rs:823`）。
- web：`fast/ime_position.rs`/`ime_edit.rs`/`ime_keys.rs`（fast 新增）。

### 3.4 已知问题

gpui-fast 仓库只有 PR、无 issue tracker，相关 PR 均已合并：#63（CJK 行首禁则，后由上游 UAX#14 取代）、#132（全角标点截断）、#177（CJK 合成斜体）、#112（自带字体进 cascade）、#111（无 `m` 字体）、#119（sbix 彩色）、#108/#109/#110（web IME 位置/按键/代理对）、#61（X11 XIM 握手）。

gpui-kit 侧：

- **#3456（open）** marked text 未拦 Command-Return 提交。
- **#3605（open）** macOS 拼音候选框跨焦点残留。
- **#3442（open）** 阿/英标点换行。
- #4024（closed）Windows IMM32 失焦不结束组合；#3286（closed）macOS 候选框跳回原点；#4112（closed）逐字宽和 vs kerning 换行。

**净结论**：macOS 上两者文字栈同源（CoreText + ICU4X + 同一 IME 代码），fast 只加缓存与若干 CJK/字体修复，接口完全兼容。

---

## 4. 无障碍

### 4.1 结论

**AccessKit 两版都完整接着；fast 没削弱，反而给 retained/layer 子树补了节点回放。角色必须逐元素声明。已知缺口集中在「点击落在滚出视口的节点」与「list 层在 a11y 激活时被禁用」。**

### 4.2 pre

- 依赖 `accesskit 0.24` — `gpui-pre-0.3.14/Cargo.toml:290`。
- 每帧全量建树：`src/window/a11y.rs:126`（`A11y`）、`:371`（`A11yNodeBuilder`）、`:304`（`A11ySubtreeBuilder`）、`:275/:283`（begin/end_frame）、`:297`（`debug_tree_json`）。
- 入树条件：元素有 id 且 `a11y_role()` 非 `None`（默认 `None`）— `src/element.rs:114`、`:447-460`。
- 角色逐元素声明：`.role(Role::X)` 写 `override_role`（`elements/div.rs:1359`）；`GenericContainer` 被过滤（`div.rs:2007-2014`）；另有 `aria_label`/`aria_description`/`aria_keyshortcuts`/`aria_active_descendant`（`div.rs:1380-1419`）。**无 `A11yRole` 类型**，无 HTML 式 aria 属性集。
- `src/_accessibility.rs` 只是文档（`:295` 末 `#[cfg(doc)] use crate::*`），无实现。

### 4.3 fast

- 依赖同上（`gpui-fast-0.1.19/Cargo.toml:99`）；`_accessibility.rs` 与 pre 逐字相同（295 行）。
- `src/window/a11y.rs` 与 pre 同版，加 13 处一行钩子转调 `fast::a11y`（`:226/:261/:279/:288`）；`A11yNodeBuilder` 增 `fast: A11yLog`（`:393`），`A11ySubtreeBuilder` 增 `SyntheticParent`（`:308/:351/:369`）。
- `src/fast/a11y.rs` = retained/layer 子树的节点回放器，**全部 `pub(crate)`，无公开 API**：文件头 `:1-29`、`Op` `:92`、`A11yLog` `:111`、`begin_frame:203`、`reuse_prepaint:259`、`replay:308`（`set_bounds` 平移 `:317-327`）、`reuse_paint:397`、`A11yStretch`/`capture:435/:449`、`carry:507`、`layer_needs_repaint:529`。
- 树仍每帧交系统：`src/window.rs:4128/4237`（`sync_active_flag`）、`:4250-4257`（`end_frame` → `platform_window.a11y_tree_update`）；激活动作走 `async_channel` 回主线程（`:1802-1900`）。

### 4.4 平台接线

| 平台 | fast | pre |
|---|---|---|
| macOS | `gpui-fast-macos/src/window.rs:2551`（`SubclassingAdapter::for_window`）、`:2568` update | `gpui-pre-macos/src/window.rs:2540/2550` |
| Linux Wayland | `gpui-fast-linux/src/linux/wayland/window.rs:2329/2334` | `.../wayland/window.rs:2292` |
| Linux X11 | `.../x11/window.rs:2057/2062` | `.../x11/window.rs:2029` |
| Windows UIA | `gpui-fast-windows/src/window.rs:1120/1136`（`Adapter::new` + `update_if_active` + `events.raise`） | `gpui-pre-windows/src/window.rs:1086/1102` |

依赖：Linux `accesskit` + `accesskit_unix`（`gpui-fast-linux/Cargo.toml:86,90`）；Windows `accesskit` + `accesskit_windows`（`gpui-fast-windows/Cargo.toml:54,58`）。

### 4.5 与滚动/分层的交互（fast 专有风险面）

- div 滚动层复合时按 delta **平移** bounds（`fast/layers/reuse.rs:119` → `a11y.rs:507/308`），**不裁剪到视口**。
- `list` 的层在 a11y 激活时**直接禁用**（`fast/layers/lists.rs:85`，`list_layers_active`）；层不完全可用时整窗回退（`fast/layers/mod.rs:132` 的 `stale`）。含义：开 VoiceOver 时长列表退回逐行重绘——正确性优先。
- 自放 bounds 的合成节点强制重绘（`a11y.rs:529`、`paint.rs:294`）。
- 回归测试逐帧比对有层/无层两窗 30 步滚动的树（`fast/tests/a11y.rs:424-500`，容差 1e-3）。

### 4.6 已知缺口

- `Action::Click` 用 `node_bounds.center()` 直接合成鼠标事件，**无可见性/命中检测**；`ScrollIntoView` 未实现——`gpui-fast/src/window.rs:7669-7682`。
- bounds 不裁剪到滚动视口 → **gpui-kit #3658（open）**：滚出视口的节点会点到同位置的别的控件。成因对 pre/fast 均成立。
- **gpui-kit #3295（open）**：list autoscroll 重试 prepaint 时 a11y builder 未随 `transact` 回滚 → `Duplicate a11y node id`（报在 pre 0.3.7）。
- fast 的 a11y PR 均已合并：#122/#126（合成子树回放压平导致 `accesskit_consumer` “duplicate child” abort）、#113/#118（tab stop 性能）。**仓库无 open 的 a11y 条目**。
- 纠正塔台线索：**#4057 不是无障碍问题**，是 WebView 在滚动层里单帧越界（层 mask，见 #157 已知限制）；**#3946 是显存**（`CAMetalDisplayLink` 常驻 IOSurface，见 §5）。

---

## 5. 线程与调度

### 5.1 结论

**两版线程模型相同；`gpui-fast-scheduler` 不是新调度器，只是把同一份 scheduler 拆出来独立发布。无工作窃取；前台优先级参数被忽略。长任务靠后台 executor + `spawn_dedicated`。**

### 5.2 `gpui-fast-scheduler` 管什么

- 公开面：`Scheduler`（`gpui-fast-scheduler-0.1.19/src/scheduler.rs:94`）、`Priority`（`:44`，权重 60/30/10 `:63`）、`SpawnTime`/`RunnableMeta`（`:73/:77`）、`SessionId`（`:241`）、`Timer`（`:249`）、`spawn_dedicated_thread`（`:187`）。
- `executor.rs`：`LocalExecutor:22`、`SendLocalExecutor:208`、`BackgroundExecutor:256`、`spawn_with_priority:275`、`spawn_realtime:294`、`DedicatedExecutor:385`、`Task:440`/`FallibleTask:665`。
- pre 的 `gpui-pre-scheduler-0.3.14` 是同一份代码（`src/scheduler.rs:1-9` 的 `pub use` 完全对应）。

### 5.3 主线程之外能做什么

- `App::spawn` 跑**主线程** `AsyncApp` — `gpui-fast/src/app.rs:2564`。
- `background_executor().spawn` 要求 `Send`，跑平台 dispatcher（macOS = GCD 全局队列，按优先级 High/Default/Low — `gpui-fast-apple/src/dispatcher.rs:33-49`）。
- `spawn_dedicated` 起真 OS 线程（`gpui-fast-scheduler/src/scheduler.rs:187-217`；用例 `gpui/src/platform_scheduler.rs:242`），可做阻塞 syscall / 长计算。
- `Entity<T>` = id + `Weak<RwLock<…>>`（`gpui-fast/src/app/entity_map.rs:354-360`，`PhantomData<fn(T)->T>` `:526`）→ 句柄 Send/Sync，但 `read/update` 需 `&App`，只能主线程。
- `ForegroundExecutor` 带 `PhantomData<Rc<()>>`（`!Send`），`SendForegroundExecutor` 给别的线程用（`executor.rs:19-53`）。

### 5.4 长任务不卡界面的手段与坑

- 正道：解码/导出/缩略图放 `background_executor().spawn(...)`，完成后 `cx.spawn` 回主线程更新。
- 阻塞 IO：`spawn_dedicated`。
- **`spawn_when_idle` 的「时间片」三平台都没实现**：trait 默认回退成 Low 优先级主队列（`gpui-fast/src/platform.rs:1608-1619`），macOS/Windows/Linux 均未覆写（grep 0 命中）；`idle_time_remaining()` 恒 `None`。
- **前台 `spawn_with_priority` 无效** — `gpui-fast/src/executor.rs:387-398`。
- 帧调度：`on_next_frame`（`src/window.rs:3105`）、`request_animation_frame`（`:3125`；先 `fast::layers::invalidate::note_animation_frame` 再 notify）。pre 无该调用（pre `window.rs:3076/3096`）。
- 卡顿检测：`App::start_hang_monitor`（`app.rs:2538`）。

### 5.5 差异

- 唯一实现差异：fast 用 `jiff` 替 `chrono`（`Cargo.toml:208`；`fast/clock.rs:1-20`，RUSTSEC-2026-0543）。
- `fast/dispatch.rs` **不是任务调度**，是命中测试 dispatch 树的批量拷贝（`:2-13`，`copy_nodes:34`）；`fast/observers.rs` 是变更序号语义。
- 工作窃取：两 crate `steal` 0 命中。`yield_now` 仅 profiler 测试路径。

### 5.6 已知问题

- gpui-fast：`hang OR freeze OR blocking OR deadlock` **0 条**。相关 PR：#179（scheduler 独立发布）、#158（去 chrono）、#85（Windows 输入后冗余帧请求，VSync 等待 130→2）。
- **gpui-kit #3946（open）**：macOS 14+ `CAMetalDisplayLink` 常驻 3–4 个窗口大小的 IOSurface，`maximumDrawableCount=2` 也压不住；帧源实现 `gpui-fast-apple/src/display_link.rs:52-95`。是内存基线，不是泄漏。
- gpui-kit #3938（closed）macOS 菜单校验死锁；#3984（closed）`WebView::build` 在 App 借用期间执行 GPUI 任务（主线程重入）。

---

## 6. 布局与停靠

### 6.1 结论

**核心 gpui 只有 flex；分栏/停靠/标签在 gpui-base（gpui-kit 转发），且与后端无关——同一份代码分别对 pre/fast 编译，不存在「仅 pre 有」的组件。**

### 6.2 核心 pre

- 无 dock/resizable 代码。布局来自 `Styled`：`styled.rs:45 flex`、`:181 flex_1`、`:208 flex_none`；`w/h/min_w/max_w` 由宏生成（`gpui-fast-macros/src/styles.rs:846/852/870/892`，pre 同构）。尺寸约束字段 `style.rs:181-239`。
- `window.rs:5703 request_layout`、`:5732 request_measured_layout`；`TaffyLayoutEngine` 每帧新建节点、bounds 存 `FxHashMap`，无跨帧保留（`taffy.rs:33-38`）。
- div **无** `resize`/`on_resize` 回调（全 crate 0 命中）；窗口尺寸变化用 `Context::observe_window_bounds`（`app/context.rs:397-411`）；程序化 `Window::resize`（`window.rs:3284`）。`WindowOptions{is_resizable, window_min_size}`（`platform.rs:2746/2762`）。

### 6.3 fast

- 同套 flex/style API；`window.rs:5757 request_layout`。新增 retained layout：节点跨帧保留，按 style 指纹决定是否重排（`fast/layout.rs:1-2,31-35`；`taffy.rs:31-37`）。窗口 resize 丢弃滚动层（`fast/layers/mod.rs:141`、`policy.rs:546`）。
- 唯一结构差异 = retained layout + resize 丢缓存；`div`/`Style`/`Window` 签名与 pre 一致。

### 6.4 分栏与停靠（gpui-base，两后端通用）

- 分栏：`h_resizable(id)`/`v_resizable(id)`（`gpui-base-0.11.0/src/resizable/mod.rs:17/22`；`gpui-component` 同名再导出 `resizable.rs:29/34`、`lib.rs:114`）；`PANEL_MIN_SIZE = 100px`（`resizable/mod.rs:14`）；group `child/size/on_resize`（`resizable/panel.rs:80/98/108`）；panel `size_range/fixed/visible`（`:277-303`）。
- 独立拖拽手柄：`resize_handle`（`resizable/resize_handle.rs:17-42`，doc 含拖拽 + 双击复位），适合自绘侧栏边缘。
- 停靠：`DockArea`（`dock/dock_area.rs:99`）`new/with_renderer/set_center/set_dock/toggle_dock/set_dock_size/add_panel`（`:126/154/232/246/301/348/371`）；`PaneTree::split/insert_panel/move_panel`（`dock/layout/edit.rs:64/46/56`）；`TabGroup`（`dock/tab_group.rs:146`）。
- `StackPanel` 只是旧序列化名（`dock/state_convert.rs:8`），0.11 无该类型；`TabPanel` 类型不存在（标签是 `TabGroup` + gpui-component 的 `TabBar/Tab`）。
- 拖拽底座 = `Div::on_drag`（`elements/div.rs:640`）。

### 6.5 fast 后端下可用性

特性链：`gpui-kit/Cargo.toml:51-58` → `gpui-component/Cargo.toml:43-45`，`gpui-component/src/lib.rs:1-2` 把 `gpui_fast` 别名成 `gpui`；dock/resizable **无 cfg 门控**（`gpui-component/src/lib.rs:74`、`gpui-base/src/lib.rs:30`），整个 component 仅 3 处 fast 条件编译。CI 三平台跑 `cargo test -p gpui-component --features gpui-fast,test-support --lib`（`gpui-kit/.github/workflows/ci.yml:158,180`），dock 集成测试 `gpui-kit/tests/integration/dock.rs`。

示例：`crates/story/src/stories/{dock,resizable,tabs,sidebar}_story.rs`。

### 6.6 已知问题

- gpui-fast 仓库无 resizable/split/panel/layout 相关 issue（只有 PR）。
- **gpui-kit #2488（open）**：Windows splitter 滞后于鼠标。
- #3619（closed）move/up 早于下一帧导致拖动丢失；#4037（closed）`ResizableState::is_resizing`（`resizable/mod.rs:67-70`）。
- Linux story 滚动 CPU：Dock 10.9%→7.8%、Tabs 22.1%→8.1%（`docs/story-scroll-cpu.md`）。

---

## 7. 大图与大列表

### 7.1 一张 2560×1600 RGBA 怎么显示

**静态图（一次上传）**：`img(Arc<RenderImage>)` — `elements/img.rs:197`；`RenderImage::new` `assets.rs:61`；`object_fit` `img.rs:155`。paint 走 `paint_image` → sprite atlas，按原生像素尺寸上传（`window.rs:5547`）。

- atlas 上限：Apple 硬编码 `MAX_ATLAS_SIZE=16384²`（`gpui-fast-apple/src/metal_atlas.rs:144-148`，默认 1024²）；wgpu 取 `max_texture_dimension_2d`（`gpui-fast-wgpu/src/wgpu_atlas.rs:55`）并有 `fits` 守卫（`fast/atlas.rs:17`，调用 `wgpu_atlas.rs:180`）。
- 2560×1600 BGRA ≈ 16.4 MB，单 tile 可容纳 → **`img()` 足够**。
- **坑（PR #103）**：超过 atlas 上限时，wgpu 已加 `fits` 守卫、失败且不留纹理；**Metal/DirectX 的同类守卫，PR 作者自述尚未加**（未能在 Apple/Windows 上运行验证），超限行为未实测。我们的图远低于上限，不受影响，但别把 100MP 全尺寸直接塞 atlas。

**每帧变的预览（调参 → 重渲染）**：用 dynamic texture，API 见 §1.3。

- `create_dynamic_texture` → 每帧 `update_dynamic_texture`（或自有 GPU 管线写完后 `refresh_dynamic_texture`）→ paint 阶段 `paint_dynamic_texture`。
- BGRA8、4 B/px（`fast/dynamic_textures.rs:41`）。
- PR #164 实测：4K 全帧 9.855→5.926 ms（−40%）；1080p 内 256² 局部更新 1.259→0.091 ms（−93%）。
- **应用不能注入自有 GPU 纹理**（`new_gpu` 只登记元数据，`dynamic_textures.rs:104` + 模块 doc `:17-21`）；零拷贝得上 §1.1 原生表面。

**pre**：无 dynamic texture（0 命中），只能 `img()` 走 atlas；每帧更新 = 每帧重上传 atlas tile。

### 7.2 十万行虚拟列表

API（两版同名）：

- `list(state, render_item: FnMut(usize, &mut Window, &mut App) -> AnyElement)` — `elements/list.rs:25`。
- `uniform_list(id, item_count, Fn(Range<usize>, ...))` — `elements/uniform_list.rs:23`，**要求等高**（doc `:2-6`）。
- `ListState::new(item_count, ListAlignment, overdraw)` — `list.rs:317`；`measure_all()` `:341`；`splice()` `:499`；行高存 `SumTree`（`:67`）。
- 列表尺寸行为 `ListSizingBehavior`（`list.rs:44`）。

**fast 增量**：`LIST_LAYERS = true`（`fast/layers/lists.rs:79`）。层保留「视口 + 两侧各一屏 overscan」的行（`:1-8`）；滚动帧只渲染新进 overscan 的行，其余复用 hitbox/listener/element state（`:10-25`）；每帧新增行预算 0.75 屏（`:505,529`）；内容 14/16 帧变化即降级（`policy.rs:41-47`）；a11y 激活时不用层（`lists.rs:85`）；仅 linux/macos/windows 编译（`fast/layers/mod.rs:33-37`）；`GPUI_SCROLL_LAYERS=0` 可关（`:74-75`）。

**规模证据**：测试用 100,000 行 × 1px `uniform_list`，fling 240 帧后布局节点被限在 8192（`fast/tests/layers_lists.rs:935-947`；`fast/layout.rs:108` `LIST_ROW_NODE_LINGER_MAX=8192`）。PR #169 实测：20,000 行 × 8 列，节点 69,013/238 MB → 9,088/107 MB，仍有 29–31 ms 尖峰（修复后 17 ms）。

**硬约束**：

- `uniform_list` 等高；`list` 行高可变但不可越界变化（doc `list.rs:2-5`）。
- 内容总高受 f32 限制，>2^27 px 后偏移只能落到 16 px 倍数（`uniform_list.rs:948` 注释）。十万行 × 40 px = 4e6 px，安全。
- 十万**可变行高**无实测（等高的有实测）。

**pre**：无 layers，每滚动帧重排/重画可见行 + overdraw（`list.rs:1078-1082`）。功能可用，代价是 CPU。

### 7.3 平台

- dynamic texture：Apple / Windows / wgpu(Linux) 都有；**web 查不到**。
- scroll layers：仅 linux/macos/windows（`fast/layers/mod.rs:33-37`）。
- Linux story 滚动 CPU（pre→fast 同机对照）：VirtualList 32.2→19.1、DataTable 18.1→13.1、Table 13.2→4.1、List 11.4→9.7、Tree 10.4→8.5、Image 7.7→6.3（`docs/story-scroll-cpu.md`）。

### 7.4 已知问题

- PR #157 / #165（merged）：滚动层与原生表面，见 §1.8；残留限制同样作用于列表行内的原生表面。
- PR #169（merged）：行布局节点上限 8192。
- PR #129（merged）宽变后 `measure_all` 分帧测量；#170/#171（merged）列表层重画预算与降级。
- gpui-kit #2037（closed）list/table 滚动卡；#2281（closed）DataTable 多列性能；#1661（closed）dock 示例快速滚动重复行。

---

## 8. pre → fast 接口差异

### 8.1 依赖与 features

| 项 | gpui-pre 0.3.14 | gpui-fast 0.1.19 | 证据 |
|---|---|---|---|
| 包名 / lib 名 | `gpui-pre` / `gpui` | `gpui-fast` / `gpui` | 两者 `Cargo.toml` `[lib] name="gpui"` |
| 宏 crate | `gpui-pre-macros =0.3.14` | `gpui-fast-macros ^0.1.19` | pre `:353`；fast `:154` |
| 调度器 | `gpui-pre-scheduler =0.3.14` | `gpui-fast-scheduler` | pre `:480`；fast `:283` |
| 时间库 | `chrono` | `jiff` | pre `:311`；fast `:208,:450` |
| 上游基线 | zed `f126950` | 包内未声明 | pre `:24-28` |
| 新增 feature | — | `windows-manifest-provided-by-host`；`screen-capture` 加 `windows-capture` | fast `:76,92` |
| 共用底层 | `collections/http_client/shared_string/util/refineable/sum_tree` | 同左（复用 `gpui-pre-*`） | fast `:115,122,158,162,174,261,340` |

### 8.2 文件级

- **仅 fast 有**：`src/fast/**` 89 个 `.rs`（`fast/*.rs` 36、`fast/layers/*` 17、`fast/tests/*` 32、`fast/misc/*` 4；`fast/mod.rs:26-62`）。pre 无 `fast/` 目录（98 vs 191 个 `.rs`）。
- **仅 pre 有**：未发现。
- **都有但不同**：`gpui.rs` 355→375、`window.rs` 11169→11241、`scene.rs` 1475→1531、`platform.rs` 4109→4127、`elements/div.rs` 5865→5946、`elements/list.rs` 3883→4000、`text_system/line.rs` 两处调用改双参。
- **基本未变**：`elements/img.rs` 行号完全一致；`style.rs` 1529→1530 且 `Style` 字段逐行一致；`element.rs` 两 trait 仅差 1 行。

### 8.3 公开 API

| 项目 | pre | fast | 性质 | 影响 |
|---|---|---|---|---|
| `Window::paint_layer` | `(f)` `window.rs:4965` | `(bounds, f)` `window.rs:5026` | **breaking** | 自定义 `Element` 必须补 bounds |
| `Scene::push_layer` | `()` `scene.rs:135` | `(bounds: Bounds<ScaledPixels>)` `scene.rs:142` | **breaking** | 直接操作 Scene 的代码需改 |
| `PlatformWindow` | — | +`draw_composed`/`enable_window_composition`/`create_native_surface`/`set_composition_order`（均有默认实现）`platform.rs:1412-1431` | 增 | 平台实现可不改 |
| `Window` 动态纹理 | — | 5 个方法 `dynamic_textures.rs:405-468` | 增 | BGRA8 |
| `Window` 合成 | — | `enable_window_composition` `composition.rs:1262`、`with_composition_surface` `:1279` | 增 | 原生表面嵌入 |
| `Scene`/`Background` | — | `is_empty`/`replay_balanced` `:479/:499`；`Background::is_opaque` `:464` | 增 | 无破坏 |
| crate 根导出 | — | 5 组 `fast::` re-export（`gpui.rs:130-145`） | 增 | 新命名空间 |
| `Element`/`IntoElement` | `element.rs:52,154` | `:53,155`，方法体逐行相同 | 无 | `fast/retained.rs` 无新公开 trait |
| `App::spawn`/`background_executor` | `app.rs:2556,2488` | `:2564,2496`，函数体逐字相同 | 无 | — |
| `Entity`/`EntityId`/`WeakEntity` | `entity_map.rs:30,515,845` | `:31,522,852`，字段/方法相同 | 无 | 内部多 `access_log` |
| `div()` | `-> Div` `div.rs:1844/1905` | `-> Div` `:1846/1907` | 无 | — |
| `Window::paint_surface` | `window.rs:5649` | 同 `:5703`（仅 mac/iOS） | 无 | 自有 GPU 直贴路径不受影响 |
| `TextSystem` / `Text` 族 | — | 同名同签名 | 无 | 见 §3 |

### 8.4 迁移实际要改什么

1. **依赖别名**：`gpui = { package = "gpui-fast", version = "0.1.19" }`（crate README `:9` 明确要求，以保住宏生成的 `gpui::` 路径）；平台层 `gpui_platform = { package = "gpui-fast-platform" }`。两个 crate 的 lib 名都叫 `gpui`，不能同时以同名 extern 引入。
2. **走 gpui-kit 只翻一个 feature**：`features = ["gpui-fast"]`（`gpui-kit/Cargo.toml:51-58`）→ 拉入 `gpui-fast`/`-platform`/`-web` 并转发给 `gpui-base`/`gpui-component`/`gpui-kit-assets`；`gpui-kit/src/lib.rs:102-104` 切换核心 re-export，`:108-115` 切宏路径，`:117` `pub use crate as gpui` 保宏路径，`:122` `GPUI_FAST` 常量供上层 `cfg`。**上层 `use gpui::...` 一行不改**；子 crate 内是 `extern crate gpui_fast as gpui;`（`gpui-base/src/lib.rs:7-8`、`gpui-component/src/lib.rs:1-2`）。
3. **代码改动点**：调用 `window.paint_layer(...)` 处补 bounds（官方写法 `gpui-base/src/scrollbar.rs:1721-1724`、`gpui-component/src/shimmer.rs:358-361`）；直接用 `Scene::push_layer` 的代码同理。其余上层 API（`Element`、`div`、`List`、`Entity`、`Application`、`Style`）抽样与清单层面均未变。
4. **行为约定**：非 tracked entity/global/list 状态的改动需 `cx.notify()`（GitHub README「Retained Mode」节；该文档未打进 crate）。crate 内只有 9 行 README，**无 CHANGELOG/MIGRATION**——迁移条目「查不到」。
5. **自有 GPU 管线**：`paint_surface`(CVPixelBuffer) 未变；改用动态纹理时 `paint_dynamic_texture(bounds, texture)` 只接受 bounds，**没有 corner radius / grayscale / object-fit**（`dynamic_textures.rs:459-464`），缩放裁剪要自己算 bounds。

---

## 9. Linux 与 Windows

逐项状态（仅源码与已合并 PR 证据，不推测）。

| # | 项 | Windows | Linux |
|---|---|---|---|
| 1 | 外部 GPU 画面 | 有：DirectComposition visual portal（`gpui-fast-windows/src/fast/composition.rs:112-127`）+ dynamic texture（D3D11，`:101`）；**无** `paint_surface`/`NativeView` | 有：Wayland `wl_subsurface` / X11 子窗口（`gpui-fast-linux/src/fast/composition/wayland.rs:743`、`x11.rs:1153`）+ wgpu dynamic texture（`:611`）；**无** `paint_surface`/`NativeView` |
| 2 | 交换链/色彩 | `DXGI_FORMAT_B8G8R8A8_UNORM`（`directx_renderer.rs:29`），无 HDR/宽色域 | `Bgra8Unorm`/`Rgba8Unorm`，`SurfaceColorSpace::Auto`（`wgpu_renderer.rs:398-414,471`），无 HDR |
| 3 | 文字/IME | DirectWrite（`gpui-pre-windows/src/platform.rs:191`）；IMM32（`events.rs:155/156`） | cosmic-text（`gpui-pre-linux/src/linux/text_system.rs:1`）；Wayland text-input（`window.rs:1089`）/X11 XIM（`xim_handler.rs`） |
| 4 | 无障碍 | UIA（`accesskit_windows`，`Cargo.toml:58`；`window.rs:1120/1136`） | AT-SPI（`accesskit_unix`，`Cargo.toml:90`；Wayland `:2329`、X11 `:2057`） |
| 5 | 线程 | 同 API；dispatcher = 线程池 | 同 API；dispatcher = 线程池 |
| 6 | 布局/停靠 | gpui-base 同一份代码，可用 | 同一份代码，可用 |
| 7 | 大图/大列表 | dynamic texture + list layers（D3D11 渲染器） | dynamic texture + list layers（wgpu 渲染器） |
| 8 | 迁移 | 同一别名切换 | 同一别名切换 |

### 9.1 Windows 专有事实与坑

- 渲染器 = Direct3D 11（`directx_renderer.rs:68-84` 的 `ID3D11Device`/`ID3D11Texture2D`），不是 wgpu。
- swapchain 两条：`CreateSwapChainForComposition`（`:1397`）与 `CreateSwapChainForHwnd`（`:1426`），均 `FLIP_SEQUENTIAL` + `B8G8R8A8_UNORM`。
- `windows-manifest-provided-by-host` feature（fast `:92`）：宿主自带 manifest 时启用（gpui-kit 默认打开，`gpui-kit/Cargo.toml:288`）。
- gpui-kit **#2488（open）**：splitter 滞后于鼠标——分栏在 Windows 上的已知手感问题。
- PR #150（merged）：软件适配器上的部分重绘（滚动帧用上一帧）——现已在 0.1.19 内。
- 无 HDR：`SetColorSpace1`/`DXGI_COLOR_SPACE_*` 0 命中。

### 9.2 Linux 专有事实与坑

- 渲染器 = wgpu：`gpui_wgpu` 由 `wayland`/`x11` feature 拉入（`gpui-fast-linux/Cargo.toml` features）。
- Wayland：合成表面是「同步 subsurface（GPUI overlay）+ 异步 subsurface（原生表面）」（`fast/composition/wayland.rs:5-7`）。
- X11：原生表面 = 子窗口；overlay 由合成管理器混合，**无合成管理器时靠挖洞**（README 表格）。
- XIM 握手守卫（`fast/xim.rs:18`、`x11/client.rs:823`，PR #61）。
- scroll layers 需要 wgpu 渲染器（`docs/scroll-layers.md`：「Linux, on the wgpu renderer」）。
- 无 HDR/宽色域配置。

### 9.3 两平台共同

- **都没有** `paint_surface`（macOS/iOS `cfg`）与 `NativeView`（doc 明言「Only macOS shows native views so far」）。
- 都支持 window composition + 外部 GPU surface + dynamic texture + list layers。
- 都无 EDR。

---

## §10 没查到的

1. **gpui-fast 的 CHANGELOG / MIGRATION / 迁移指南**：crate 内只有 9 行 README，无此类文件；仓库 `docs/` 只有 architecture / retained-mode / scroll-layers / benchmarks / releasing / upstream-sync / story-scroll-cpu / superpowers。
2. **把已有 `MTLTexture`/`wgpu::Texture`/`ID3D11Texture2D` 直接交给 GPUI 采样的公开 API**：确认不存在；`new_gpu` 仅元数据登记。
3. **gpui-pre 的 window composition 等价物**：确认不存在（`Platform` trait 无相关方法）。
4. **HDR/EDR 的任何源码路径**：三平台、两版本均 0 命中；也没有相关 issue（`HDR` 搜索 0 条，只有一条 `display p3` 命中的上游同步 PR）。
5. **macOS 上把 `create_native_surface` 的 NSView 换成 `CAMetalLayer` 的官方示例**：只在 Linux 示例里看到同构做法；macOS 段用的是 WKWebView，未演示 Metal。可行路径是 objc2 侧替换 layer，但**无第一手示例**。
6. **gpui-fast issue tracker**：仓库只用 PR，无 issue；所有“issue 编号”实为 PR 编号（`#157`/`#165`/`#169` 等正文即分析报告）。
7. **十万行可变行高列表的实测数字**：只有等高 `uniform_list` 的 100,000 行实测（`fast/tests/layers_lists.rs:935-947`）与 20,000 行 × 8 列数据（PR #169）；可变行高十万行无数据。
8. **Windows/Linux 上原生表面 + 自有 wgpu 设备共享同一 `wgpu::Device` 的示例**：Linux 示例是独立 `Instance`/`Device`（`native_webview.rs:288-320`），不是与 GPUI 共享设备；共享设备的路径查不到。
9. **gpui-fast 在 Windows 上 >16384 图像的 atlas 守卫**：PR #103 明说 Metal/DirectX 未加，只修了 wgpu；0.1.19 源码确认 `fits` 只在 wgpu 调用。

---

### 方法备注

- 四路并行只读侦察（文字 / 无障碍+调度 / 布局+列表 / API diff）+ 主线自持 GPU 与色彩；交叉核对了两处冲突（`resizable` 位置、`paint_surface` 是否依赖 composition），以源码为准修正。
- 示例来自 `gh api repos/longbridge/gpui-fast/contents/crates/gpui_perf/examples/native_webview.rs`；issue/PR 来自 `gh api search/issues`。
- 所有“有/没有”均以本机 0.1.19 / 0.3.14 源码为准；上游后续版本可能变化。
