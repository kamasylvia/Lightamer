# R1 — gpui-fast 框架本体侦察

调研时间 2026-11-25。只读：未编译、未启动图形程序、未提交。
第一手材料 = 本机 crate 缓存 `/Volumes/UNITEK/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/gpui-fast-0.1.19/`（下文路径省略该前缀）；仓库/发布数据 = GitHub API 与 crates.io API（2026-11-25 拉取）。

## §0 一页结论

- **它是什么**：Longbridge 维护的 Zed GPUI 性能分支，不是"另一个 UI 框架"，是"同一个 GPUI + 增量渲染层"。README 自述 "A performance-focused fork of Zed's GPUI with incremental rendering and native window composition"（`README.md` 首段）；crate 描述 "GPUI with gpui-fast rendering and layout optimizations"（`Cargo.toml.orig:5`）。公开 API 目标 = 上游 API（`docs/upstream-sync.md` 规则 5，仅两处例外）。
- **血统清晰**：起自 Zed main 提交 `a1b71072e5`（v0.1.0，`UPSTREAM` @tag v0.1.0），当前同步到 Zed `f126950f9d3b62666f97437ae5d4ccac2272c4db`（`UPSTREAM` @v0.1.19），与 `gpui-pre` 0.3.14 是同一 Zed 快照的两条发布线（`gpui-pre-0.3.14/Cargo.toml.orig:20-23` 的 `zed-rev` 与 gpui-fast `UPSTREAM` 同值）。
- **快在哪（作者口径）**：保留子树 + 跨帧 Taffy 节点 + 文字测量 carry/replay + 滚动层瓦片；README 给 Linux release 数据 −73%～−88% 主线程 CPU。另有独立 oracle 测试体系（`src/fast/tests/oracle.rs:2-11`）。**这些数字全部是 Linux**，本机目标平台 macOS 无同表数据（`README.md` 表格标注 "on Linux, release builds"）。
- **稳不稳**：工程纪律强（hook-only 上游文件 + `script/check-upstream` 机检 + 30 个上游文件仅 +609/−776 行，`docs/architecture.md` 末节）；但**产品年龄只有 2 个月**（仓库 2026-09-24 创建，首个 crates.io 版本 2026-10-06），19 个 crates.io 版本、间隔中位数 2 天（crates.io `/api/v1/crates/gpui-fast` versions 时间戳计算），**0.1.x 无 LTS 概念**。
- **维护主体**：Longbridge。crates.io owners = `huacnlee`（gpui-fast、gpui-pre 同主，`/api/v1/crates/<c>/owners`）；仓库 `longbridge/gpui-fast` 683 star / 94 fork；近 30 天合并 PR 84 个（GitHub search `is:pr is:merged merged:>2026-10-26`）。
- **最大结构性风险**：**仓库关闭了 issue tracker**（`gh api repos/longbridge/gpui-fast` → `has_issues:false`），缺陷只能记到 `longbridge/gpui-kit`（gpui-kit #4057 正文原话 "gpui-fast has no issue tracker, so this is filed here"）。缺陷跟踪、SLA、回归档案都依附在另一个仓。
- **与本项目最相关的三条已知坑**：① macOS `CAMetalDisplayLink` 节奏保留 3–4 块窗口大小 drawable（gpui-kit #3946；`setMaximumDrawableCount(3)` 硬编码于 `gpui-fast-apple-0.1.19/src/metal_renderer.rs:213`）；② 原生视图（WebView）与滚动层的裁剪在层晋升帧会闪一帧（gpui-kit #4057，根因 gpui-fast#157 的已知限制）；③ `test-support` 的精确 pin 与 gpui-pre 冲突（gpui-kit #3865）。

## §1 血统

**分叉点：Zed main 的具体 commit，不是 release tag。**

- v0.1.0 导入 Zed `a1b71072e5b43faef437b471e988fbb5f972c99c`（`UPSTREAM` @tag v0.1.0，字段 `zed_commit`）。
- v0.1.13 导入 `decd2399b180b64dea2a4182f9ac63545a45e7a3`（`UPSTREAM` @tag v0.1.13）。
- v0.1.19 导入 `f126950f9d3b62666f97437ae5d4ccac2272c4db`（`UPSTREAM` @v0.1.19，同时 `import_commit = 9d120903…` 保存"未改动导入"的那个提交）。
- 仓库创建 2026-09-24，首版 crates.io 2026-10-06（`gh api repos/longbridge/gpui-fast` → `created_at`；crates.io crate `created_at`）。
- UC 注：v0.1.0 的 `release.toml` 记 `snapshot_version = "0.3.8"`，v0.1.13 → `0.3.11`，v0.1.19 → `0.3.14`。即它发布时把自身 support crates 对齐到同号 `gpui-pre` 快照。

**与 gpui-pre 的关系：同源双产品，不是竞争仓。**

- `gpui-pre` 0.3.14 = "Zed's GPU-accelerated UI framework (gpui-pre snapshot of zed@f126950)"（`gpui-pre-0.3.14/Cargo.toml.orig:6`，`[package.metadata.gpui-pre] zed-rev` 同行 `f126950`）。
- gpui-fast **直接依赖** gpui-pre 的 support crates：`collections = { package = "gpui-pre-collections", version = "=0.3.14" }`、`gpui_util`、`sum_tree`、`refineable`、`http_client`、`gpui_shared_string`、`bench_metrics`（`gpui-fast-0.1.19/Cargo.toml.orig` 各 `[dependencies.*]` 段）。即二者共享同一套非 GPUI 核心件，版本精确锁死。
- `gpui-pre` 本身是生态里被广泛再分叉的"Zed GPUI 的 crates.io 快照"：GitHub 上 `ibisjp/gpui-pre`、`Pelotrio/gpui-pre`、`eidola-ai/gpui-pre`、`Haven-King/gpui-pre`、`vegidio/gpui-pre` 均以 "crates.io snapshot of Zed's gpui" 自述（`gh api search/repositories?q=gpui-pre`）。

**同步机制（仍在上游跟踪，节奏 ≈ 每周一次 merge）：**

- commit `Sync GPUI upstream d2a4fb6ded (#123)` 2026-11-09 → `Sync with zed 78f5d74 (#148)` 2026-11-16 → `Sync upstream Zed to f126950 (#178)` 2026-11-23（`gh api repos/.../commits`，PR 号）。
- 方式 = 真 merge 上游历史（同页还有 `Merge upstream zed f126950` 提交），不是 rebase。
- 可合并性靠纪律而非运气：自己的逻辑只放 `crates/<crate>/src/fast/`，上游文件只允许"hook"形态（字段、一行调用、可见性提升、`#[path]` 重定向），由 `script/check-upstream` 机检（单 hunk >8 行、单文件 >40 行、新增行未调用 `fast/` 即失败），例外逐条登记在 `script/upstream-allowlist`（`docs/upstream-sync.md` "The rules" 1–4）。
- 现状量化：30 个被跟踪上游文件与上游不同，其中 `crates/gpui/src` 占 20 个，差异 +609/−776 行（`docs/architecture.md` "Staying close to upstream"）。

**许可：** Apache-2.0，双版权 `Copyright 2022 - 2025 Zed Industries, Inc.` + `Copyright 2026 Longbridge`（`gpui-fast-0.1.19/LICENSE` 首两行；`Cargo.toml.orig:11`）。README 明确 "This is a modified fork"。

## §2 架构：「fast」到底改了什么

代码体量：`src/fast/` 51,983 行 / 全 crate 148,873 行 ≈ 35%；其中测试 22,760 行（`wc -l` 实测）。上游文件被整文件替换的只有两处，走 `#[path]` 重定向：`bounds_tree`（`src/gpui.rs:33-34`）与 `tab_stop`（`src/gpui.rs:59-60`）。

设计前提一句话（`docs/architecture.md` "Constraints"）：**"从零画出的那一帧是唯一规范"**——保留帧必须与逐帧重画逐字节相同，因此可用 oracle 机检。

### 2.1 布局（新写，替换上游"每帧清空 Taffy"）

| 模块 | 作用 |
|---|---|
| `src/fast/layout.rs:2` | Taffy 节点跨帧保留 + 样式指纹（决定能否不写节点） |
| `src/fast/layout_key.rs:2` | 从根到元素的 key 路径 → 上一帧布局节点 |
| `src/fast/layout_bounds.rs:2` | `TaffyLayoutEngine::layout_bounds` 的绝对边界缓存表 |

要点不是"保留节点"，而是**不写节点**：Taffy 的 `set_style/set_children/set_node_context` 无条件 dirty 自身及祖先，所以每个保留节点记住上次请求的样式指纹 / 子列表 / 测量输入，相同就不写（`docs/architecture.md` "Layout"）。未被认领一帧的节点释放；无 key 的临时节点帧末释放。

### 2.2 文字与字形（新写 + 上游机制扩展）

| 模块 | 作用 |
|---|---|
| `src/fast/text.rs:2` | 复用区段在新帧的落位、文字测量 carry 与 replay |
| `src/fast/glyphs.rs:2` | 一个字形的渲染算一次 per-run 而非 per-glyph |
| `src/fast/number_shaping.rs:2` | 数字按字形整形，不每次问平台 |
| `src/fast/em_metrics.rs:2` | 无 `m` 字体的 em 宽/进距 |
| `src/fast/line_break.rs:2` | 中日文禁则换行规则（仅测试构建编译，`src/fast/mod.rs` 中 `#[cfg(test)]`） |
| `src/fast/truncation.rs:2` | 按已整形宽度截断 |
| `src/fast/text_style.rs:2` | 窗口文字样式栈，记住解析结果 |
| `src/fast/interactive_text.rs:2` | 交互文本的手型光标命中盒 |

文字测量是全案最巧的一块：文本变了但**尺寸没变**（表格里跳动的价格）时，用"同一约束序列重放测量"证明 Taffy 缓存仍成立，节点保持干净；只有尺寸真变才 dirty 行/列表/窗口（`docs/architecture.md` "Text measurement"）。

### 2.3 保留视图与拼接（核心）

| 模块 | 作用 |
|---|---|
| `src/fast/retained.rs:2` | 从上一帧已画内容重画子树；`GPUI_VIEW_RETENTION=0` 在此读取（`retained.rs:293`） |
| `src/fast/dependencies.rs:2` | 子树构建期读了什么（entity/global/versioned state）及记录方式 |
| `src/fast/splice.rs:2` | 只重建变化的嵌套视图，前后从上一帧拷贝 |
| `src/fast/tracked_entities.rs:2` | 每个 entity 的通知会失效哪些窗口 |
| `src/fast/observers.rs:2` | observer 何时听到变更 |
| `src/fast/global_id.rs:2` | 复用 global element id 的增量路径哈希 |
| `src/fast/interactivity.rs:2` | 惰性分配的 listener 列表与 a11y 属性（省每节点 3 字） |

身份 = 上游已有的 `GlobalElementId`（含 entity id），**不引入平行 UI 树**；每条帧内保留 record（hitbox/dispatch/listener/primitive 区间 + 读过的依赖 + hover + 布局节点）（`docs/architecture.md` "Identity"）。五条路径：Reused / Spliced / Built-at-retained-layout / Prebuilt / Built（同文 "Drawing a view from the last frame" 表）。

### 2.4 场景、绘制顺序、dispatch

- `src/fast/scene.rs:2` — 不移动 primitive 的绘制排序；保留子树的 ordering **重放**而非重算。
- `src/fast/bounds_tree.rs:2` — 用均匀网格替换上游 R-tree（整文件重定向，`src/gpui.rs:33-34`），小 bounds 更多时更快。
- `src/fast/dispatch.rs:2` — 复用区段的 dispatch 节点一趟写完，而非逐节点 push/pop。
- `src/fast/path_cache.rs:2` — 路径三角化缓存（每线程 ≤2048 形状 / 16 MiB）。
- `src/fast/rounded_clip*.rs:2` — 圆角裁剪组的保留几何与渲染器传输。
- `src/fast/tab_stop.rs` — 整文件重定向（`src/gpui.rs:59-60`）。

### 2.5 滚动层（`src/fast/layers/`，17 个文件）

`layers/mod.rs:2-4` 一句话：滚动容器的内容画一次进瓦片，只有 offset 变化时按新偏移合成。三态策略 = Composite / Repaint / Bypass，见 `layers/policy.rs:2`；瓦片哈希复用 `layers/tiles.rs:2`；非场景记录（hitbox/listener/dispatch）平移搬运 `layers/reuse.rs:2`；输入重定位 `layers/input.rs:2`；渲染器契约 `layers/scene.rs:2`；列表层 `layers/lists.rs:2`。

**编译范围硬编码**：`layers/mod.rs:33-38` `COMPILED = cfg!(any(target_os = "linux", target_os = "macos", target_os = "windows"))`——Web/iOS 上所有层入口是 no-op。`GPUI_SCROLL_LAYERS=0` 单独关闭（`layers/mod.rs:49,75`）。

### 2.6 时钟与显示链路

- `src/fast/clock.rs:2-5` — 平台时钟改返回 `SystemTime` 而非 chrono 的 `DateTime<Utc>`；注释注明"上游在同一方向改（zed-industries/zed#67089）"。同类改动在 `scheduler` crate（PR #158 "scheduler: Use SystemTime and jiff instead of chrono"）。
- macOS 帧节奏：`gpui-fast-macos-0.1.19/src/display_link.rs:4` 起——macOS 14+ 用 `CAMetalDisplayLink` 驱动窗口；`display_link.rs:298-302` 说明空闲窗口不取 drawable，`end_frame` 在未用 drawable 且无唤醒时暂停链路（`:353-356`）。

### 2.7 其余新件

- `src/fast/composition.rs:2` — 窗口合成：原生视图夹在 GPUI 内容与浮层之间（macOS AppKit / Windows WebView2 / Linux 子 surface）。
- `src/fast/dynamic_textures.rs:2` — 给"每帧都变"的内容（视频、远程桌面）的可变 BGRA8 纹理（唯一公开 API 例外之一）。
- `src/fast/a11y.rs:2` — a11y 节点从上一帧重画。
- `src/fast/list_measure.rs:2` — `measure_all` 列表宽度变化后跨帧测量。
- `src/fast/stats.rs:2` — `LayoutStats`（仅 test/bench 编译）。

### 2.8 验证体系（判断"稳"的实证基础）

- `src/fast/tests/oracle.rs:2-11`：两个窗口跑同一随机变更序列，一个增量、一个每帧"失忆"，逐帧比对完整场景与 hitbox；并断言增量窗口确实复用了节点/子树（防止"从不保留"也能过）。
- 另有 `layers_oracle.rs`、`retained_bench.rs` 等 36 个 fast 测试文件（含 mod/support）；渲染器级像素测试在 `gpui_wgpu` 与各平台 crate（`docs/architecture.md` "Verification"）。
- CI：`ubuntu-latest / macos-latest / windows-latest` 三平台矩阵，macOS 上跑 Metal 合成分层与 dynamic texture 测试，Windows 上跑 Direct3D 滚动层测试，另有 `Link GPUI Fast with GPUI Pre` 共存测试（`.github/workflows/ci.yml` test job）。

## §3 维护状况

| 项 | 数值 | 出处 |
|---|---|---|
| 维护组织 | Longbridge（仓库 `longbridge/gpui-fast`，crate owner `huacnlee`） | GitHub API；crates.io owners |
| 仓库创建 | 2026-09-24 | `repos/longbridge/gpui-fast`.created_at |
| 最近推送 | 2026-11-25T08:01:32Z | 同上 `.pushed_at` |
| Star / Fork | 683 / 94 | 同上 |
| 贡献者 | 107（含合并进来的 Zed 上游作者，非纯 fork 贡献者） | `/contributors?anon=1` Link 尾页 |
| 提交总数 | 437（含上游 merge 历史） | `/commits?per_page=1` Link last |
| fork 自有 PR 提交 | 146（消息尾 `(#1xx)` 形态），近 30 天 83 | 提交消息统计 |
| PR 总数 / 近 30 天合并 | 179 / 84 | GitHub search `is:pr`、`is:pr is:merged merged:>2026-10-26` |
| crates.io 首版 | 2026-10-06（0.1.0） | crates.io crate.created_at |
| crates.io 版本数 | 19（0.1.0–0.1.19，**无 0.1.18**） | crates.io versions |
| 最近发布 | 0.1.19 @ 2026-11-23 | 同上 |
| 发版间隔 | 中位数 2 天；最大 7 天 | 由 versions.created_at 计算 |
| 总下载 | 259,043 | crates.io crate.downloads |
| GitHub Release | 18 个页面（0.1.17 无 release page，见 v0.1.19 正文说明） | `/releases` |
| 反依赖 | 31 个 crate 依赖 gpui-fast | crates.io reverse_dependencies meta.total |

没有人值守的 issue 面：`has_issues:false`（GitHub API），缺陷走 gpui-kit。近 30 天 84 个合并 PR 说明**节奏很快**，同样说明**变动面大**。

## §4 API 稳定性

**官方政策：不改公开 API。** `docs/upstream-sync.md` 规则 5："No new public API. gpui-fast changes how GPUI draws, not what it offers: its public API is upstream's." 仅两处登记例外：`fast::dynamic_textures`（#86）与 `WebPlatform::wgpu_context()`（#102）。

**实测 0.1.13 → 0.1.19 的公开面差异**（下载两个 crate 包逐文件比对）：

- crate 根部导出：**仅 +2 项** —— `pub use fast::app_borrow::app_is_borrowed;` 与 `pub use fast::dynamic_textures::{…};`（`src/gpui.rs` 根部 `pub use` 行 diff）。
- 公开签名集合：-18 / +77 行（`grep '^\s*pub (fn|struct|enum|trait|type)'` 去重排序后 comm）。逐条核对，破坏性样本全部落在**上游文件**，即 Zed 自身的 pre-1.0 漂移，而非 fast 层：
  - `path_builder.rs`：`Path<P>` 泛型（0.1.13）→ 非泛型 `Path`（0.1.19 `path_builder.rs:419`）。
  - `app.rs:2097`：`dismiss_system_notification(&self, tag: &str)` 返回 `()` → 返回 `Task<()>`（0.1.13 为 `app.rs:1986`）。
  - `scene.rs`：`clipped_bounds` 由 `pub` 降为 `pub(crate)`（0.1.19 `scene.rs:560`）。
- 结论：**fast 层自身 API 面几乎不动；痛点在"跟着 Zed 上游走"**。上游 rebase 是破坏性变更的唯一来源，频率 ≈ 每周 1 次 merge、每次 merge 带一批 Zed 重构（v0.1.19 正文列了 zed#66806–#66812 的渲染器重写、zed#67311/#67316 原生视图等）。

**迁移说明：没有 CHANGELOG 文件。** 仓库根目录清单无 `CHANGELOG*`（`gh api repos/.../contents`）；迁移信息只在 GitHub Release 正文（分区：Packaging / Highlights / Upstream changes / Performance / Fixes / Other）与应用面文档 `docs/retained-mode.md`（"What an application must do"）。**没有跨版本升级指南**。

## §5 平台

| 平台 | 状态 | 依据 |
|---|---|---|
| macOS | 一等公民。Metal 渲染 + `CAMetalDisplayLink` 节奏 + AppKit 原生视图合成；滚动层编译进来 | `gpui-fast-macos`/`gpui-fast-apple` crate；`fast/layers/mod.rs:33-38`；`display_link.rs:4` |
| Linux | 一等公民。wgpu（Vulkan/GL），Wayland + X11 特性 | `gpui-fast-linux`、`gpui-fast-wgpu`；CI Linux job |
| Windows | 一等公民。Direct3D 11，含 overdraw 剔除、软件适配器局部重绘、WebView2 合成 | `gpui-fast-windows`；PR #149/#150；CI Windows job |
| Web (wasm) | 可用但**fast 能力最薄**：`gpui-fast-web` 已发布，`src/fast/` 只有 `canvas_size` / `ime_edit` / `ime_keys` / `ime_position` / `wgpu_context`；滚动层 `COMPILED=false` | `gpui-fast-web-0.1.19/src/fast/`；`fast/layers/mod.rs:33-38` |
| iOS | **无 fast 后端**：`gpui-fast-platform` 在 iOS 上依赖 `gpui-pre-ios = 0.3.14`（非 fast） | `gpui-fast-platform-0.1.19/Cargo.toml.orig:51-52` |
| Android | 未支持：published `gpui-fast-platform` 无 android target 依赖；`gpui-fast-linux` 亦无 android 条目 | 同上 Cargo.toml 全文；`gpui-fast-linux-0.1.19/Cargo.toml.orig` |
| FreeBSD | cfg 里与 Linux 同路（`target_os = "freebsd"` 走 gpui_linux） | `gpui-fast-platform` 的 `cfg(all(any(linux, freebsd), not(ohos)))` 段 |

性能数据只在 Linux 采集：README 性能表脚注 "Main-thread CPU per frame, release builds on Linux"；`docs/architecture.md` "Results" 同样标注 Linux。**macOS 只有功能/内存类报告，没有同口径 CPU 表**（见 §7）。

## §6 和 gpui-kit 的关系

开启 `gpui-kit = { features = ["gpui-fast"] }` 后，变化面比"换个引擎"大，逐层如下。

**1) gpui-kit 特性只做三件事**（`gpui-kit-0.11.0/Cargo.toml.orig:23`）：

```toml
gpui-fast = ["dep:gpui-fast", "dep:gpui-fast-platform", "dep:gpui-fast-web",
             "gpui-base/gpui-fast", "gpui-component?/gpui-fast", "gpui-kit-assets?/gpui-fast"]
```

即：引入 3 个 fast crate + 把 fast 特性透传给已经启用的每一层。

**2) 类型空间整体换根（`gpui-kit-0.11.0/src/lib.rs`）**：

- `lib.rs:100-104`：`#[cfg(not(feature="gpui-fast"))] pub use ::gpui::*;` / `#[cfg(feature="gpui-fast")] pub use ::gpui_fast::*;`
- `lib.rs:108-113`：fast 下改用 fast 的宏集合（`Action`/`Render`/`test`/…）。
- `lib.rs:122`：`pub const GPUI_FAST: bool` 供上层在编译期对齐。
- `lib.rs:133-137`：`platform` 与 `web` 的重导出同步切到 `gpui-fast-platform` / `gpui-fast-web`。
- 注意：**gpui-pre 仍然在依赖图里**。`[dependencies.gpui] version="=0.3.14" package="gpui-pre"` 非 optional（`gpui-kit-0.11.0/Cargo.toml` 依赖段）。开启 fast 只是不再经它导出，两个 GPUI 核仍会被编译（Cargo 特性可加不可减；README 亦写 "Cargo features are additive, so upstream packages still compile when Fast is selected"）。CI 专门有一条 `Link GPUI Fast with GPUI Pre` 测试共存（`.github/workflows/ci.yml`）。

**3) gpui-base 用 `extern crate` 别名换引擎（`gpui-base-0.11.0/src/lib.rs:7-10`）**：

```rust
#[cfg(feature = "gpui-fast")]
extern crate gpui_fast as gpui;
```

此后 base 的全部代码零改动地指向 fast 引擎。除了别名，还有 **23 处 `#[cfg(feature="gpui-fast")]` 行为分支**（`grep -rn 'cfg(feature = "gpui-fast")' gpui-base-0.11.0/src | wc -l` = 23），例如：

- `scrollbar.rs:1720-1726`：fast 下调用 `window.paint_layer(hitbox_bounds, paint)`，上游签名是 `paint_layer(paint)`——注释写明 "GPUI Fast keeps the layer bounds to record scroll layers"。
- `resizable/mod.rs:770,776,786,792,811`、`slider.rs:1632`、`text/state.rs:1491`、`text_selection.rs:3674,5202,5209,5290,5383`：fast 专属适配与专门的 retained 回归测试（`RetainedScrollingSelectionRoot` 等）。
- `input/base/element.rs:5651,5721`。

**4) gpui-component 同款**：`extern crate gpui_fast as gpui;`（`gpui-component-0.11.0/src/lib.rs:2`）+ src 内 6 处 fast 引用（含 `extern crate`），特性透传见 `Cargo.toml.orig:18`。

**5) Windows 资源清单去重**：gpui-kit 对 gpui-fast 固定带 `features = ["windows-manifest-provided-by-host"]`（`gpui-kit-0.11.0/Cargo.toml` 的 `[dependencies.gpui-fast]` 段），避免两个引擎各嵌一份 manifest。

**6) 若要走 git 版而非 crates.io**：需要 `compat/` 里那组同名 `gpui-pre-*` 垫片做 `[patch.crates-io]`，因为 Cargo 只允许同名同版本要求替换；且 `compat/README.md` 提醒 gpui-pre 会把宏里的 `gpui::` 路径改写成 `::gpui_kit::`，而 gpui-fast 不会，需 `extern crate gpui_kit as gpui;`。

## §7 已知局限与坑（按严重度）

### A. 功能缺陷 / 行为不一致

1. **滚动容器里的原生视图（WebView）在层晋升帧闪出容器** — gpui-kit **#4057**（open，macOS 27.2.1 实测）。根因是 gpui-fast #157 的已知限制：尝试层的帧内容按层更宽的 content mask prepaint，`WebViewElement::prepaint` 取了 `window.content_mask().bounds` 当原生视图裁剪。规避 = `GPUI_SCROLL_LAYERS=0`。相关修复链 #157 → #165 → #167（`surface_clip`），#4057 说明仍有残帧。
2. **列表层默认关闭**：`uniform_list` / `list` 的层设计上覆盖但开关是关的（`fast::layers::lists::LIST_LAYERS`，`docs/architecture.md` "Lists"）；原因写明：可输入的行不给层、hover 变化重画所有持有行、加行重建整块内容。长列表滚动收益因此打折。
3. **未受追踪的状态会画旧帧**：`Rc<RefCell<_>>`、原子、静态可变、`Instant::now()`、文件/网络状态，改动必须自己 `cx.notify()`，否则视图停在旧内容（`docs/architecture.md` "What an application must do"）。这是任何增量系统的边界，但对"逐帧读时间/读文件"的图像应用是实打实的适配工作。
4. **每帧通知 = 退化回全量**：prepaint/paint 期间写 global 或 notify entity，即使值没变也算变更（同节末段）。原文举例 gpui-kit 自己的文本选择每帧重置全局导致全窗重建。

### B. 资源 / 性能成本

5. **macOS drawable 保留 3–4 块窗口大小** — gpui-kit **#3946**（open）：`CAMetalDisplayLink` 路径下 footprint 里 3–4 个窗口尺寸 IOSurface（Retina 1458×1038@2x ≈ 24 MB/块），`maximumDrawableCount` 压不住；`CVDisplayLink` 回退路径是 2 块。硬编码点 = `gpui-fast-apple-0.1.19/src/metal_renderer.rs:213` `layer.setMaximumDrawableCount(3)`；另一个 issue **#3858** 专报这个常数（"空闲多占 30~40MB"）。
6. **层重画成本高**：重画一帧要画 5 个视口的内容，代价是"无层帧的数倍"——给出 5–6.5 ms vs 0.6 ms，每滚两个视口触发一次（`docs/architecture.md` "Costs and limits"）。
7. **层瓦片内存上限 64 MB/窗口**，LRU 淘汰（同节）。
8. **保留机制本身的常数开销**：hook 指令数平均 +0.85%，最大 +2.7%（同节）。
9. **复用要拷贝**：整窗每帧都变时收益趋近 0（"all sixty" 行：10.33 ms → 7.38 ms，仅 −29%）。

### C. 工程 / 依赖

10. **精确 pin 与 gpui-pre 冲突** — gpui-kit **#3865**（open）：`test-support` 打开后 `gpui-fast` 要求 `taffy =0.15.0`、`gpui-fast-web` 要求 `unicode-properties =0.1.3`，而 `gpui-pre` 锁的是 0.15.1 / 0.1.5 → 解析失败。对"想同时跑两套后端对比"的场景是硬阻塞。
11. **仓库无 issue tracker**（`has_issues:false`），缺陷证据散落在 gpui-kit 的 PR/issue 里（#4065、#3984、#3985、#3954、#4023、#4027、#4073 等均以 gpui-fast 为上下文）。
12. **Windows 交叉编译需要 fxc.exe**：`gpui-fast-windows build.rs:35-36` 检查 `fxc.exe`，可用 `GPUI_FXC_PATH` 指定（`build.rs:109-110`），但无 fxc2/Linux 原生替代 → gpui-kit **#3902** 记录的自 Linux 交叉编译 Windows 失败（该 issue 以 gpui-pre 为主体，同一 build script 血统）。
13. **发布偶发失败**：v0.1.18 的 crates.io 发布在验证阶段中止，v0.1.19 重新打包才补上（v0.1.19 release 正文 "Packaging" 段）；v0.1.17 无 release page。

### D. 平台差异

14. **iOS 无 fast 后端**（平台 crate 依赖 `gpui-pre-ios`），Web 的 fast 只有 IME/canvas/wgpu-context 小修补。
15. **macOS 合成路径的事务耦合**：原生视图在场时需要在 Core Animation 事务里 present（#156），光标要交还给原生视图（#168），`surface_clip` 要单独加（#167）——说明合成路径仍在收敛期。

## §8 三方对照表

| 维度 | Zed 官方 `gpui` | `gpui-pre` 0.3.14 | `gpui-fast` 0.1.19 |
|---|---|---|---|
| 来源 | Zed monorepo `crates/gpui`（`crates.io/api/v1/crates/gpui` → `repository: zed-industries/zed`） | Zed main 快照，`zed-rev = f126950…`（`gpui-pre-0.3.14/Cargo.toml.orig:20-23`） | 同一 Zed 快照 + `fast/` 层（`UPSTREAM` @v0.1.19） |
| 维护者 | Zed Industries（crates.io owners：`maxbrunsfeld`、`mikayla-maki`、`MrSubidubi`、`github:zed-industries:crates-io`） | `huacnlee`（Longbridge） | `huacnlee`（Longbridge） |
| crates.io 版本 / 日期 | 0.2.2 @ **2025-10-22**（全站仅 7 个版本，最老 0.1.0 2022-06-23） | 0.3.14 @ 2026-11-23（15 个版本，0.3.0 @ 2026-09-03） | 0.1.19 @ 2026-11-23（19 个版本，0.1.0 @ 2026-10-06） |
| 许可 | Apache-2.0 | Apache-2.0（Zed 版权） | Apache-2.0（Zed + Longbridge 双版权） |
| 平台 | macOS/Linux/Windows/Web/iOS（monorepo 内） | 同左（`gpui_platform` 分派） | macOS/Linux/Windows 一等；Web 薄；iOS 回退 gpui-pre（`gpui-fast-platform` Cargo:51-52）；Android 无 |
| 性能机制 | immediate mode + `AnyView::cached` 局部复用 | 同 gpui（纯快照，无增量层） | 保留子树 + 跨帧 Taffy 节点 + 文字测量 carry/replay + 滚动层瓦片 + 网格 bounds tree + dispatch 批量拷贝 + 路径缓存（`src/fast/mod.rs` 模块表、`docs/architecture.md`） |
| 性能证据 | 无公开基准 | 无 | README Linux 表 −73%～−88%；GPUI Kit 76 个 story 中 75 个滚动 CPU 更低、平均 −37%（`README.md` "Performance vs GPUI"） |
| 与 gpui-kit 配合 | **不直接支持**：gpui-kit 依赖的是 `gpui-pre`（`gpui-kit/Cargo.toml` `[dependencies.gpui] package="gpui-pre"`） | **默认后端**，精确 pin `=0.3.14` | **可选后端**，`features=["gpui-fast"]`，声明 `0.1.19`（caret）；两层 `cfg` 适配（gpui-base 23 处、component 6 处） |
| 发布节奏 | crates.io 基本停更（最近一次 2025-10） | ≈1–2 版/周 | 中位 2 天/版，近 30 天 84 个合并 PR |
| 主要风险 | 无可用 crates 发布 → 只能 git 依赖 monorepo；API 随 main 漂移 | 与 fast 的精确 pin 互斥（#3865）；无增量能力 | 年龄 2 个月；无 issue tracker；上游 rebase 每周带入破坏性改动；macOS 内存/原生视图合成仍在收敛（#3946/#4057）；性能数据仅 Linux |

## §9 没查到的

1. **上游同步的具体冲突率**：`script/check-upstream` 的机检口径已知（>8 行/hunk、>40 行/文件即失败），但仓库未公开每次 merge 的实际冲突数/解决耗时。只能给"30 个文件有差异，+609/−776 行"这个静态量。
2. **`huacnlee` 与 Longbridge 的雇佣/治理关系**：只有 crates.io owner 与仓库归属两层事实，没有组织层面的维护承诺文档（无 GOVERNANCE / MAINTAINERS 文件，根目录清单可证）。
3. **macOS 上的同口径性能数据**：README 与 architecture 文档的基准全是 Linux release 构建；macOS 只有 drawable 内存与合成类 issue。macOS 的实际帧成本需靠另一路"本机实测"补齐。
4. **0.1.x 的语义化版本承诺**：没有 SECURITY.md / 版本策略文档；`Cargo.toml` 只有 `version = "0.1.19"`，未声明 MSRV（`rust-toolchain.toml` 存在但未核对内容）。
5. **gpui-pre 与 gpui-fast 的发布流水线是否同一套工具**：`gpui-fast/release.toml` 明确是 gpui-fast 自己的发布配置（`snapshot_version` 等），但 gpui-pre 的生成仓未定位（crates.io `repository` 字段指 zed-industries/zed，非实际发布源）。
6. **issue 全量归类**：gpui-fast 侧无 issue 可查（tracker 关闭），gpui-kit 侧 `gpui-fast` 关键词命中 188 条，本次只逐条读了 open 的 5 条（#4057/#3946/#3865/#3902/#3598）与发布说明，其余以 PR 标题抽样，未做逐条闭环。
7. **`fast/` 内部各机制的独立收益拆分**：只有作者给的聚合表（retained / layers 两组），没有逐机制 ablation；`docs/retained-mode.md`、`docs/scroll-layers.md` 未逐行核（本次只读 `architecture.md` 与源码头注）。
