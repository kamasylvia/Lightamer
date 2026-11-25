# PLAN — Rust 全量重写的分波开发计划（darktable 功能面 + gpui 界面）

> **本计划有修订，执行前必须连同 `PLAN-AMENDMENTS.md` 一起读**：基线改为上游 master 的 `679d594f5d`（不钉 `release-5.7.0` tag），阶段 A 连跑，脚本统一放 `Scripts/`，rawspeed 钉 `0c16fee77`。

> 本文件是可照着派活的计划，不是调研。调研正本在上一级 `.work/gsd/phases/rust-core/`：`FEATURE-SCOPE.md`、`HISTORY-COMPAT.md`、`SPIKE-RUST-APPLE.md`、`CORE-DESIGN.md`、`VERIFY.md`；界面调研在同级的 `.work/gsd/phases/{gpui-spike,gpui-fast-scout,gpui-viewport,appkit-migration}/`（与本目录平级，不在本目录内）。
> 落盘基线：仓库 HEAD `1f9c1adb83399b5e403a8419d5fc65859c9f5a2f`（本 lane 执行 `git rev-parse HEAD` 亲核）。
> 上游参考：`refs/dt-master` @ `679d594f5d` = **`release-5.7.0-2234`**（即 5.7.0 之后 2,234 个提交）。**参数布局与顺序一律钉 `release-5.7.0` tag，不钉 master**（理由与证据见 §1.3）。
> 日期 2026-11-26。全文中文；英文标题、标识符、命令保持原文。

---

## §0 一页纸

**目标**：Rust 一套代码，功能 = darktable + darktamer 自定义，界面复刻 darktable（gpui 族），历史能从 XMP 读成相同观感。

**阶段与规模（估算）**

| 阶段 | 内容 | 波数 | lane | lane 墙钟 |
|---|---|---:|---:|---:|
| A 地基 | 许可/骨架/自动发现/历史/对照工具/Apple 边界/核心-界面/视口 | 9 | 17 | 43.5 h |
| B 第 0 期 | 21 模块 + 管线 + 解码 + 历史 + 蒙版 + 图库 + 导出 + 暗房 UI | 20 | 76 | 208 h |
| **A+B** | **第一个能日常修图的版本** | **29** | **93** | **251.5 h（含自审 ≈302 h ≈ 38 个 8h 日）** |
| C 第 1 期 | 调色全量、修饰、HDR/软打样、检索标签、批量导出、独有功能 | ≈22 | ≈130 | ≈325 h |
| D 第 2 期 | 打印、联机、地图、幻灯片、Lua、20 个长尾模块 | ≈10 | ≈60 | ≈150 h |

**第一个能日常用的版本**：**B20 之后**（导入→灯箱→暗房→导出闭环，21 个模块与 darktable 对照通过）。B11 之后 CLI 已能逐模块过 golden；B16 之后无界面全链闭环。

**三个最大的风险**
1. **参数布局钉错版本**（已实证）：调研的 `temperature` v5/24B、`colorin` v8/1048B、`demosaic` 60B、`highlights` 40B 都是 **master** 值；`release-5.7.0` 是 v4/20B、v7/1044B、48B、48B。若照 T2 实现，第一张 XMP 就对不上。唯一真值 = tag 生成的夹具 + oracle 的 modversion 回读（A4b）。
2. **模块移植量**：第 0 期 21 个模块 47,986 行 C/C++（38 lane），其中 demosaic 的 RCD 与 lens 的 lensfun 接入是真实风险；第 1 期还有 50 个模块（+ 基线之外的 spektrafilm 等）。
3. **UI 底座未定型**：gpui-fast 0.1.x 两个月大、无 issue tracker、上游周更；视口的输入归属**只读过代码未实测**；EDR 在本机 SDR 屏上不可验收。

**质量门（每波必过）**：fmt/clippy/test + 触碰像素就过 oracle（mean<1 LSB16、in_tol>0.9999）+ 确定性双跑逐位 + `Scripts/guard.sh` + 一次一个重活 + 新依赖过 A1。

**检查点**：阶段 A 与阶段 B 的**每一波**停下来给用户看；C 起连跑只汇报。

**与调研冲突处已改（不止两处，全表见 §1.3）**：`CORE-DESIGN.md` §6 无自动发现（→ §2.2 + A3）；§7 第 ① 步「参数版本 1、不做迁移」（→ §2.4 + A4b）；§1 的 S6/S12 只做 blend 短路（→ §1.2 第 13 条上调蒙版范围）；T2 的 4 处字节数、模块计数 98/93、`spektrafilm` 的可用性；crate 名 `dt-mask-blend` → 本计划的 `dt-blend`。

---

## §1 裁决清单与本计划的技术取舍

### §1.1 用户裁决 → 计划落点（逐条）

> 本节及全文的 `#26/#27/#28/#32/#33/#34` 均指 GitHub `kamasylvia/Lightamer` 的 issue。

| 裁决 | 落点 |
|---|---|
| 功能 = darktable + darktamer 自定义；UI 复刻 darktable | §2、§3（B17–B19）、§4（C/D 覆盖 5.7.0 余下的 72 个模块 + 基线外 5 个） |
| Lightamer 独有功能保留（全景/焦点/HDR 合成、节点 DRT、版本分支、AI 标签评分、软打样）排第 1 期 | §4 C-7～C-9 |
| 胶片模拟用 dt 的 `spektrafilm`，不用 SpektraLab 资产 | C-2；T9 明确 `SpectralFilm*` 不是源 |
| 人像三件（#35–#37）不排期 | §4 显式列为「不排期」；T9 的 SkinSmoothKernels 归「用不上」 |
| 全 Rust；界面 gpui 族（gpui-fast/gpui-kit/gpui） | §2.6；A7a/A7b、B17–B19 |
| Apple 能力独占一个模块，只在 macOS 构建存在 | §2.7；A6 |
| 模块自动发现注册：核心不写名单、不写槽号；模块自带描述 | §2.2；A3；T3/T4 |
| 解码主路径 rawspeed | §2.3；B2；A6 的 CIRAW 默认关 |
| 核心对界面只暴露命令/查询/事件流；面板从描述生成 | §2.5；A7a；A3 的 `panel` 字段 |
| GPL-3.0，可移植 dt 代码并标注 | T1；每 wave 的 DoD |
| 第 0 期打开 dt/darktamer 修过的图同观感；写回 dt 格式无限延后 | B12（读）、B13（我们自己的双写）；§2.4 |
| 历史只读 XMP；只看 dt 数据库的历史不支持 | B12；§2.4 |
| 我们自己的修改两处存（本地库 + 原图 XMP 的自有命名空间），写 XMP 保留 dt 全部内容 | B13；A4a 的三条测试 |
| 旧 Swift 版冻结，输出/库/sidecar 不兼容；验收对照 = dt 官方 | §2.8 末段（冻结与不读清单）；A5；B20；全文的对照列 |
| 第 0 期每波停；之后连跑 | §5.3 |
| 不重启 fontd；只有 SDR 屏 | §5.2 的计时纪律；§6 R8 |

### §1.2 我定的技术取舍（带理由；不成立的已写明替代）

1. **去马赛克只移植 RCD + passthrough**（用户已定）。补充：Phase 0 **只支持 Bayer**；X-Trans 走 passthrough + 明确警告，Markesteijn 排 C。理由：用户实拍库是 Sony ARW（Bayer）；RCD 是 dt 默认；`rawspeed` 确认无 Bayer 去马赛克（`interpolators/` 仅 Canon sRAW）。若第 0 期要覆盖富士，B4 加 2 lane（不推荐，观感仍会与 dt 的 Markesteijn 不同）。
2. **第 0 期全 CPU**（用户已定）。着色器后置到 WGSL + wgpu；Metal 快路径只在 Apple 模块。理由：dt 的 20/21 模块有 CL 双版但 CPU/GPU 差异注释零命中，CPU 已能过 golden；本机对照噪声底已证 CPU/CL 同构。
3. **Apple 模块的 CIRAW 解码第 0 期默认关**（用户已定）。补充：连"疑难机型回退"也先不进 UI，只留能力表里的开关 + 日志。理由：rawspeed→内存 DNG→CIRAW 的偏色 22.8/255 未解（T5），默认开 = 默认错色。
4. **参数布局：手写 `#[repr(C)]` + 由 clang 生成 sizeof/offsetof 夹具**，不用 bindgen。理由：dt 头文件拖 glib/GTK；bindgen 会把构建绑到系统头；夹具 JSON 一次生成入库，测试逐字段对照，既钉住布局又不引入构建期 C 依赖。夹具只覆盖 `vendor/dt-5.7.0/` 里逐字拷贝的 params 结构体 + 枚举常量。
5. **迁移链只要最近两版 + 旧版丢条目**（HISTORY-COMPAT §9 推荐 B）。理由：与 dt 行为一致（dt 也是失败即丢该条、不断链），工作量收敛；混合参数读到 v15（用户已定），blend 迁移链按 dt 的 if 链转写（纯函数）。
6. **XMP 库不定死，A4a 三测后定**（用户已定）。我的倾向：`xmp_toolkit` 若 cmake 可用则在 GPL 兼容与语义正确性上最稳；否则 XML 直改（`quick-xml`），因为"保留未知 key"可以退化为"只改我们的节点、其余字节不动"，这比自研 RDF 语义更安全。
7. **模块发现用「域 crate 内 build.rs 扫目录」**（不用 linkme/ctor）。理由与坑见 T4：Cargo 没有 glob 依赖，linkme 方案仍要手改聚合 crate 的 Cargo.toml，等于留了名单；目录扫描让"加一个目录"真的成立，代价是域 crate 整包重编（4 个域 crate 把代价限住）。
8. **顺序 = 描述里的 (优先级, tie 序)，raw/jpg 两套**。理由：v50 与 v50_jpg 名集相同但 24 个模块优先级不同；28.5 的 6 个模块只有表行序能复现。tie 序是模块自己的数据（它在 dt 表里的行序），不是核心的槽号。
9. **oracle 官方包留带校验的缓存**：`~/.cache/lightamer-oracle/<sha256>.dmg` + 仓内 `oracle.lock` 记 sha/大小/URL；每次运行先验 sha，不匹配才重下。理由：88 MB × 每波多次渲染，重下慢且不可复现；缓存 + 锁定 sha 同时解决离线与确定性。
10. **源码与 oracle 同 tag 钉死**：首选 `release-5.7.0`（本地 tag 可读，无需下载源码）。若官方没有 5.7.0 的 macOS dmg，则降级 5.6.2 并**先跑一次全 21 模块的 tag 差异报告**（`git diff release-5.6.2..release-5.7.0 -- src/iop/`），差异项按 5.6.2 重钉。禁止"master 源码 + 任意二进制"的组合。
11. **核心↔界面：进程内、命令/查询/事件三件套 + 不透明渲染目标句柄**。视口的像素不走事件流，走 `PresentSink`（A7a 定类型、dt-apple 实现），UI 只拿 `u64` 句柄。理由：既要"UI 只见三件套"，又要 100MP 不走 CPU 回读；把像素传输定义成"能力对象"而不是消息，避免事件流被大缓冲污染。
12. **视口输入先走 `on_input` 转发**（gpui-fast 的 `PlatformInput` → 核心的 `ViewportInput` 事件），键盘走窗口级绑定。理由：纯 Rust、无 AppKit 子类；SPIKE-VIEWPORT 只读代码证明这条路存在。A7b 必须实测；不成立则退到自建 `NSView` 子类（`acceptsFirstResponder` + tracking area），代价是 UI 里多一处 objc2（视口表面处理本来就允许）。
13. **第 0 期蒙版范围上调**（与 `CORE-DESIGN.md` 的"blend 只做 DISABLED + 均匀不透明度"不同）。理由：用户要求"dt 修过的图同观感"，而 dt 的蒙版极常用；只做短路会让带蒙版的图观感不一致。第 0 期做：drawn（brush/ellipse/gradient）+ parametric（亮度/色彩范围，含 blendif 64 参）+ 组合模式 + normal 混合 + 几何模块的 mask 变形；**不做**：mask manager 独立面板、path 蒙版、从模块取栅格、羽化/精修（C）。
14. **导出格式第 0 期 = JPEG/PNG/TIFF（8/16 位）**，HEIC/AVIF/WebP/JXL/PDF/XCF 排 C。理由：纯 Rust 可覆盖前三个；后几个要 C 库（libheif/libavif/libwebp）或平台 API，且不是"修图闭环"的必要条件。
15. **不含 DRT**：第 0 期显示链 = `colorout + gamma`（dt 默认）。节点式 DRT 是 Lightamer 独有功能，排 C。
16. **第 0 期不接 MCP**；MCP 面在 C 作为"独有功能回归"处理（现有 34 工具契约不是本计划的前置）。

### §1.3 与调研冲突的更正（逐条，含证据）

| 冲突 | 调研写法 | 更正 | 证据 |
|---|---|---|---|
| `CORE-DESIGN.md` §6 仓库布局 | 无模块自动发现/注册 | A3 采用域 crate 目录扫描 + 描述字段（T3/T4） | 用户裁决（2026-11-25 夜）；任务书点名 |
| `CORE-DESIGN.md` §7 第 ① 步 | 「参数版本 1，不做旧版本迁移」 | 按 dt 的 C 布局 + modversion + 最近两版迁移链（§2.4、A4b） | `HISTORY-COMPAT.md` §0/§9；用户裁决 |
| `CORE-DESIGN-TABLES.md` T2 的 params 字节 | temperature 24B、demosaic 60B、highlights 40B、colorin 1048B | `release-5.7.0` 手算 20B / 48B / 48B / 1044B；T2 是 master 值 | `git show release-5.7.0:src/iop/{temperature,demosaic,highlights,colorin}.c` 的 params 结构体 |
| `FEATURE-SCOPE.md` §0 的模块计数 | 103 个 iop 源 / 98 个 `add_iop` | 那是 **fork HEAD** 的计数；钉住 `release-5.7.0` 的 v50 表是 **93 个具名模块**（+ 哨兵）。差集 = 5.7.0 之后新增的 4 个（contrastntexture/demosaicscale/satcurvergb/spektrafilm）+ fork 的 3 个 + 其它 | `git show release-5.7.0:src/common/iop_order.c` 与工作树的同名文件逐名 diff：`{contrastntexture, demosaicscale, satcurvergb, spektrafilm}` 只在工作树 |
| `spektrafilm` 的可用性 | 用户要求胶片模拟用 dt 的 `spektrafilm` | **5.7.0 发布版没有这个模块**（`git show release-5.7.0:src/iop/spektrafilm.c` 不存在；v50 表无此项）。它只存在于 master/fork | 同上。处置：C 期从 master 取源并钉提交；**没有官方 oracle 可对照**，验收降为参数往返 + 目视 + 与 darktamer 的成片比对 |
| `HISTORY-COMPAT` 的 9 个 modversion 样例 | temperature v5、colorin v8 | `release-5.7.0` 与 `release-5.6.2` 都是 temperature v4、colorin v7；master 才是 v5/v8 | 同上；两 tag 逐条 `git show` 比对 |
| `CORE-DESIGN.md` §9 | rawspeed「LGPL-2.1（静态链接可重链接义务）」 | 上游近年为 LGPL-3.0；两说冲突，A1 以 gitlink 提交的 LICENSE 为准。无论 2.1-or-later 还是 3.0，都可整体按 GPL-3.0 分发 | rawspeed 子模块本机未 checkout，`src/external/rawspeed` 为空；A1 先 `git submodule update` 取 LICENSE |
| `CORE-DESIGN.md` §4 的对照配方 | 官方包 5.6.2 | 改为与源码同 tag（首选 5.7.0）；5.6.2 仅作降级 | `git describe` = release-5.7.0-2234 |
| `VERIFY.md` §5 的行号 | `develop.c` 省略目录 | 实为 `src/develop/develop.c`（VERIFY 已自行更正，计划照用） | `VERIFY.md` §5 |
| `gpui-spike/STATUS.md` 的旧结论 | 五轮「滚动容器不重绘」 | 探针采样伪影；密集网格同帧 22/24 | `REPORT-BISECT.md`；T1 的自检节 |
| `appkit-migration/*` | 按「Swift + AppKit」前提写 | 只采用 Q1/Q2/Q4/Q5（控件词汇、布局主题、测试策略）；Q3/Q6–Q8 作废 | 该目录 `STATUS.md` |

---

## §2 架构基线（只写采纳部分与对调研的修订）

### §2.1 crate 与数据流

```text
dt-gpui (UI) ──命令/查询/事件──> dt-app (装配) ──> dt-core (管线) ──> dt-iop-* (模块)
                     │                                   │
                     ├─ dt-history (XMP+参数布局)          ├─ dt-decode (rawspeed)
                     ├─ dt-library (SQLite)                ├─ dt-color (lcms2)
                     ├─ dt-export                          └─ dt-blend (蒙版)
                     └─ PresentSink (句柄) ──> dt-apple (CIRAW/ColorSync/Vision/ImageIO/Metal)
```

`dt-core` 的 `Frame` = float32 RGBA 连续缓冲 + `Roi{x,y,w,h,scale}`；像素链内部一律 premultiplied alpha 语义（dt 的 blend 前置条件）。`PipeError` 非 panic。模块内 rayon 按行切；跨模块串行（对应 dt 的递归管线段）。

### §2.2 模块描述与自动发现（修订 `CORE-DESIGN.md` §6）

- 4 个域 crate（raw/geom/color/display），每 crate 的 `build.rs` 递归扫 `src/modules/*/mod.rs`，生成 `mod` 声明与 `pub static MODULES: &[&ModuleDesc]`，`include!` 进 crate 根。
- 描述字段见 T3：`id`（dt op 名）、`group`、`order{raw,jpg}`（含 tie）、`params{struct,size,version,migrate}`、`flags`、`colorspaces`、`panel`（控件数组）、`history{alias,multi_instance,doc_level}`。
- 默认顺序 = 按 `(priority, tie)` 排序，raw 与 jpg 两条链；用户自定义顺序存数据（图库/项目），只在运行期覆盖，**不改模块源码**。
- 核心代码里出现任何一个 dt 的 op 名字符串 = 违规（除 `dt-history` 的映射表，它是数据驱动的产物，来自描述聚合）。机检：`rg '"(rawprepare|temperature|demosaic|exposure|colorout)"' crates/dt-core crates/dt-api` = 0。
- 发现机制的机检见 T4（造 `zz_probe` 目录 → 测试断言在册 → 删除）。

### §2.3 解码

rawspeed（C++）经薄 C ABI（`rs_open/rs_decode/rs_free`，坏文件返回码不 abort）+ 进程内单份 `CameraMetaData`。输出 = 16 位马赛克 + 黑/白电平 + WB 系数 + XYZ→camera 矩阵 + 裁剪框。栅格（JPEG/TIFF/PNG）走纯 Rust。CIRAW 只在 `dt-apple`，默认关。
**降采样档**：第 0 期只做"整帧解码 + 管线缩放"（fitted 2560 由 finalscale/scale 处理）；小档解码（1/4、1/16 马赛克）排 C 的 #28 面。

### §2.4 参数布局与历史（修订 `CORE-DESIGN.md` §7）

- `#[repr(C)]` 逐模块复刻；夹具 JSON（`fixtures/layout-5.7.0.json`）= `{struct, size, align, fields[{name,offset,size}], enums{name:value}}`，由 clang 对 `vendor/dt-5.7.0/` 的逐字头生成（一次生成、入库、随 tag 变更重生成）。
- modversion 表 = 描述字段；迁移链 = `fn(old_ver, &[u8]) -> Result<Params>`，只保留最近两版；失败 → 丢该条并记日志（dt 行为）。
- 未知 op：读时保留（写回原样）、DB→内存时跳过；`modversion` 超前 → 用默认参数保留条目并告警（dt 行为）。
- blend 参数 = `DEVELOP_BLEND_VERSION 15` 整块 + 1→15 迁移链；第 0 期只用 `mask_mode`/`opacity`/`mask_id`/`blendif` 子集，其余字段**原样保留**（读进来 → 写回去逐字节）。
- 端序：只支持小端（dt 本身无端序处理），文档记死。
- 历史栈 = dt 的 `history_end` 语义（position < end 才启用）；多实例键 = `operation + multi_priority`。
- 我们自己的修改：本地库 `history` 表 + 原图旁的 XMP 自有命名空间 `lightamer:history`（命名空间名 A4a 定稿）。**写 XMP 时只增改我们的节点，dt 的 41 个已知 key 与未知 key 全部原样保留。**

### §2.5 核心↔界面接口

```rust
// dt-api
pub enum Command { OpenImage(PathBuf), SetParam{image,module,instance,patch}, BeginEdit(..), EndEdit(..),
                   Undo, Redo, ImportFolder(PathBuf), Export(ExportRequest), SetView(ViewId),
                   ViewportInput(ViewportInput), BindViewport{surface: SurfaceId, w:u32,h:u32,fmt:PixelFmt} }
pub enum Query { ImageList, ModuleList, ModuleState{..}, Capabilities, Thumb{..} }
pub enum Event { ImageOpened{id,gen}, RenderReady{gen}, Progress{..}, Error{..}, RegistryChanged }
```

- 传输：进程内，`crossbeam-channel`；查询是同步 RPC（带超时），事件是广播流；渲染请求按"最新胜出"合并（同一输出面只保留最新 generation）。
- 像素：`SurfaceId(u64)` + `PresentSink` trait（`dt-api` 定义，`dt-apple` 用 IOSurface/CAMetalLayer 实现，`dt-cli` 用 CPU 缓冲实现）。核心只写 sink，不知道 Metal。
- 面板：`ModuleDesc.panel` 的 `Control` 数组（`Slider{key,min,max,default,step,fmt}`/`Combo`/`Toggle`/`Curve`/`ColorWheel`/`Section`），UI 只渲染，不硬编码任何模块面板。

### §2.6 界面

gpui-kit 0.11.0 + `gpui-fast` feature（`gpui-fast 0.1.19`），版本锁死并在 `Cargo.lock` 固定。布局 = darktable 三区（左：导航/快照/历史；中：视口；右：模块列表；下：胶片条）。控件词汇 = 复刻 `dt_bauhaus`：整行可拖、双击复位、右键菜单、行内等宽数值、20 px 行高。面板 chrome = 启用开关/名称/预设菜单/复位/多实例/折叠高级区。
**视口** = gpui-fast 原生合成表面 + 自建 `CAMetalLayer`（16F + EDR 标记 + 扩展线性色彩空间），每视口一份层、不放进滚动容器、独立 16 ms 呈现循环。输入 = `on_input` 转发（A7b 定）。

### §2.7 Apple 模块边界

`dt-apple` 恒为 workspace 成员；crate 根 `#![cfg(target_os="macos")]`，非 macOS 编成空壳；其 objc2/Metal 依赖只放在 `[target.'cfg(target_os="macos")'.dependencies]`。`dt-app::capabilities()` 返回 `{decode:[RawSpeed, CiRaw], gpu:[Cpu, Wgpu, Metal], vision:bool, imageio_formats:[..]}`；UI 只读能力表，不做 `cfg!`。
机检：① 非 Apple crate 的 `cargo tree` 不含 objc2/core-image/Metal；② `dt-cli` 的二进制 `nm -u | grep -iE 'objc|CoreImage|ColorSync|Vision'` = 0（feature 关时）；③ `rg -l 'objc2|core-foundation|metal::' crates --glob '!crates/dt-apple/**'` = 0。

### §2.8 验收对照

`Scripts/oracle.sh`：缓存并校验 dmg → 只读挂载 → `HOME`/`CFFIXED_USER_HOME` 双隔离 → 预置 `darktablerc`（opencl 关、png bpp=16）→ `darktable-cli IN XMP OUT.png` → `dt-cli cmp`（16 位 RGB，mean/max/in_tol/±1px shift）。
**门**：`mean < 1.0`（LSB16）且 `in_tol(≤1) > 0.9999`；几何模块允许 ±1 px 搜索后判定。噪声底：重复渲染逐位相同；CPU 路径自身 `in_tol ≥ 0.99999994`。
样张 = CC0 套件（`~/Library/Application Support/Lightamer/TestRAW/` 六件 + repo 回落），**永不读用户照片库**。

**旧 Swift 树冻结（第 14 条裁决的落点）**：`App/`、`LightamerCore/`、`LightamerIOP/` 只作只读参考；**不读**它的 `.lra` sidecar、`.lalb` 项目库、UserDefaults 键族与 MCP 工具契约；验收永远以 dt 官方二进制为基准，不以它的输出为基准。它的 73 个 `.metal` 只按 T9 的参考口径使用。

---

## §3 阶段 A 与阶段 B 的逐波计划

### §3.0 共用任务书模板（每个波的任务书都必须原样包含）

> 输入集合：钉住的 `release-5.7.0` 源文件路径（`git show` 取出）、`fixtures/` 下对应的夹具与 XMP、`CORE-DESIGN.md` 的 trait 与管线 13 步、本波卡片点名的上游文件。
> 变换规则：C/C++ 逐行转 Rust，OpenMP→rayon 按行切、`float`→`f32` 不升精度；保留原版权头并追加 `Modified for Lightamer: <date> <what>`；不移植 GUI/CL/cairo；不改任何封存面；新增依赖先过 A1。
> 验收清单：本波卡片第 5 条的命令逐条跑绿；触碰像素的再跑 oracle 门（mean<1 LSB16、in_tol>0.9999）；双跑逐位；`fmt/clippy -D warnings`；`Scripts/guard.sh` PASS；任务书末尾附「未做/未验」三行。
> 通用纪律：不 commit 到保护区（`.work/` 外不写计划面文件）；一次只跑一个重活；报告里每个数字给命令。

### 阶段 A — 地基（9 波，17 lane）

#### A1 许可证与依赖核查
1. **目标**：把每个依赖的许可证、链接方式、义务写成一份可审计的表，并落到 `LICENSE`/`NOTICE`/SPDX 头。
2. **范围**：`docs/LICENSE-AUDIT.md`、`NOTICE`、`LICENSE`、`scripts/check-licenses.sh`；不改代码。不做：法务级意见（只做工程核查）。
3. **输入**：T1；dt 5.7.0 的 `src/external/`；rawspeed 的 gitlink 提交（需一次 `git submodule update`）。
4. **产出**：审计表（每个 crate/每个 C 库/每个数据包）、`NOTICE` 初版、许可检查脚本（`cargo metadata` 的 license 字段对照允许清单 + 白名单例外）。
5. **验收**：`scripts/check-licenses.sh` 退出 0；`cargo metadata --format-version 1 | jq -r '.packages[].license'` 每一项都在允许清单；`NOTICE` 覆盖全部依赖（脚本比对条目数）；rawspeed 的 LICENSE 原文引用进审计表（含文件名与行）。
6. **对照**：无（法律面），但与 dt 的 `LICENSES/` 目录结构对齐。
7. **回退**：纯文档 + 脚本，`git revert` 即可。
8. **估时**：1 lane × 2 h（估算；校准 = 同类文档 lane 的实测）。
9. **风险**：rawspeed 许可证两说冲突 → 若 gitlink 取不到（无网），本波标「未完成」并阻塞 A2 的依赖定版；**需要用户裁决？否**，按实际 LICENSE 文本执行。
10. **任务书草案**：输入 = T1 + `src/external/` 全部子模块 + gitlink 提交的 LICENSE；变换规则 = 逐项登记「许可证/链接方式/义务/我们怎么做」，GPL-3.0-or-later 为项目变体；验收 = 三条脚本 + 人工核对 rawspeed/lensfun 数据；产出 = 审计表 + NOTICE + 脚本。

#### A2 仓库骨架
1. **目标**：`cargo` 工作区、脚本、守卫、体积预算就位，后续每波都有地方落。
2. **范围**：`Cargo.toml`、`rust-toolchain.toml`（1.100.0）、`Scripts/{guard,build,test,budget}.sh`、`.cargo/config.toml`、空 crate 骨架（T2 的 19 个）、CI-lite 脚本。不做：任何业务逻辑、UI。
3. **输入**：T2；现有 `Scripts/machine-guard.sh`（复用，不重写）；A1 的依赖定版。
4. **产出**：`cargo build --workspace` 绿；`Scripts/test.sh` 跑空测试绿；预算脚本输出构建时长/二进制体积/`target` 体积；`xtask check-i18n` 骨架（键表比对，B17 起强制）。
5. **验收**：`time Scripts/build.sh --cold` ≤ 6 min；`Scripts/budget.sh` 三项都在 T2 门内；`Scripts/guard.sh` 退出 0；`cargo fmt --check` 与 `cargo clippy --workspace -- -D warnings` 绿。
6. **对照**：无。
7. **回退**：骨架是新增目录，删目录即回退（不碰旧树）。
8. **估时**：2 lane × 2 h（估算）。
9. **风险**：Rust 1.100 与 gpui 族的 MSRV 冲突（A2 先只建核心 crate，UI crate 到 A7b 再建）；**否**。
10. **任务书草案**：输入 = T2 的布局与预算；变换规则 = 只建空壳与脚本，不写业务；验收 = 四条命令；产出 = 工作区 + 脚本 + 首份预算报告。

#### A3 模块描述与自动发现注册
1. **目标**：加一个目录就被发现；默认顺序从描述算出且等于 dt 的 v50/v50_jpg；核心零 op 名。
2. **范围**：`dt-iop-traits` 的 `ModuleDesc`、4 个域 crate 的 `build.rs` 扫描、`dt-registry`（顺序计算）、`fixtures/dt-order-5.7.0.json`、`xtask` 的 `sync-check`。不做：任何模块的像素实现。
3. **输入**：T3/T4/T5；`release-5.7.0` 的 `src/common/iop_order.c`；`CORE-DESIGN.md` §1 的回调映射。
4. **产出**：描述结构 + 扫描器 + 顺序计算 + 夹具 + 三条测试（raw 链、jpg 链、tie 负测）+ 探针模块发现测试。
5. **验收**：`cargo test -p dt-registry` 绿（93 条逐位）；T4 的 `zz_probe` 脚本绿；`rg '"(rawprepare|demosaic|colorout)"' crates/dt-core crates/dt-api` = 0；`cargo check -p dt-iop-color` ≤ 40 s。
6. **对照**：顺序夹具 = dt 表；tie 负测证明不是碰巧。
7. **回退**：新增 crate + 夹具，删除即回退；`build.rs` 的目录扫描若在 CI 上有坑，退到方案 C（生成清单入库 + diff 校验），代价是多一步生成。
8. **估时**：3 lane × 2.5 h（估算）。
9. **风险**：`build.rs` 对目录的 `rerun-if-changed` 递归语义在 Cargo 版本间有差异 → 用「目录路径」而非文件列表，并在 A3 记录实测（增删文件是否触发重编）；**否**。
10. **任务书草案**：输入 = T3/T4/T5 + `iop_order.c`；变换规则 = 目录扫描生成 `mod` 与注册表，顺序按 `(prio,tie)` 排序，raw/jpg 两链；验收 = 三条顺序测试 + 探针发现 + 零 op 名 grep；产出 = 描述/扫描/顺序/夹具。

#### A4a XMP 库选型（三测定案）
1. **目标**：用三条测试在 `xmp_toolkit`/`xmpkit`/XML 直改之间定一个，并留下可复跑的证据。
2. **范围**：`crates/dt-history-spike`（临时，定案后删）、`fixtures/xmp/`（dt 真写的 sidecar 三份）、决策记录 `docs/XMP-DECISION.md`。不做：产品化的读写器（A4b 做）。
3. **输入**：T6；oracle 产出的 XMP（A5 尚未就绪时用 dt 树内样例 `src/tests/masking/flexi/xmps/G1_bare_uniform.xmp` + 手工 dt 命令行生成一份）。
4. **产出**：三候选各自过/不过三测的日志、决策记录（含构建方式与许可）。
5. **验收**：T6 三条测试对选定库全绿；测试 2 用 canonical XML 比较；测试 3 用官方 dt 手工重写一次（只读挂载 + `--configdir` 隔离，命令见 A5 配方；A5 就绪后由 `Scripts/oracle.sh` 复跑）。
6. **对照**：dt 的写回结果（测试 3）。
7. **回退**：spike crate 删除；决策记录保留。
8. **估时**：1 lane × 3 h（估算；若 xmp_toolkit 的 cmake 构建失败，时间用满）。
9. **风险**：`xmp_toolkit` 在 macOS 27 的 cmake 构建失败 → 直接落到 XML 直改，不纠缠；**否**。
10. **任务书草案**：输入 = T6 + 三份真 XMP；变换规则 = 三测按序跑、不通过就换候选；验收 = 三条测试全绿 + 决策记录；产出 = 日志 + 决策。

#### A4b 参数布局、迁移链与历史读
1. **目标**：dt 写的 XMP 能读成我们内存里的 21 模块参数栈，逐字节正确。
2. **范围**：`dt-history`（布局夹具、`repr(C)` 结构、modversion 表、迁移链、blend/masks 读、多实例、未知项语义）、`vendor/dt-5.7.0/`、`fixtures/layout-5.7.0.json`。不做：写 XMP（B13）、模块像素。
3. **输入**：T5 的 21 行 + `release-5.7.0` 的 21 个 params 结构体 + `blend.h`/`masks.h`；`HISTORY-COMPAT.md` §3/§5/§6。
4. **产出**：夹具生成器（C + clang，一次性）、21 个 `repr(C)` 结构 + 偏移测试、迁移链骨架（每模块最近两版）、历史栈反序列化、`dt-cli history dump`。
5. **验收**：`cargo test -p dt-history --layout`（每个字段 offset/size 与夹具相等，21×N 条）；`dt-cli history dump <xmp>` 与期望 JSON 相等（3 份真 XMP）；**另用官方 cli 手工渲染一份 XMP（同 A5 配方，手工跑，不等 A5 产品化）**，其每条 `modversion` 与 `params` 长度与我们的描述表相等；未知 op/modversion 超前/迁移失败三负测按 dt 语义通过。A5 就绪后由 `Scripts/oracle.sh` 自动复跑这条。
6. **对照**：oracle 的 XMP（读回逐字节）+ `HISTORY-COMPAT` Table 6 的 exposure 样例。
7. **回退**：`dt-history` 与 vendor 目录是新增；删除即回退。
8. **估时**：3 lane × 3 h（估算）。
9. **风险**：glib 类型（`gboolean`=int）与 dt 枚举值需在夹具里钉住（否则 offset 对、语义错）→ 夹具同时输出枚举常量值；**否**。
10. **任务书草案**：输入 = 21 个结构体（`git show release-5.7.0:` 取出逐字拷贝）+ `blend.h` + 3 份真 XMP；变换规则 = 夹具先于代码、`repr(C)` 手写、迁移只留最近两版、失败丢条；验收 = 布局测试 + 3 份 dump + oracle modversion 对照；产出 = 夹具 + 结构 + 迁移 + dump 工具。

#### A5 验收对照工具（oracle）
1. **目标**：一条命令完成「取官方包→隔离→渲染→比对」，且可离线复跑。
2. **范围**：`Scripts/oracle.sh`、`dt-cli` 的 `cmp` 子命令、`oracle.lock`、缓存目录约定、`fixtures/xmp/*`。不做：GUI 自动化。
3. **输入**：`CORE-DESIGN.md` §4 与 `decode-oracle-evidence/`（URL、sha、CMDS、RESULTS、cmp16.py）。
4. **产出**：缓存 + 校验 + 挂载 + 隔离 + 渲染 + 比对；噪声底自检；`--module <op> --fixture <xmp>` 的单模块模式。
5. **验收**：`Scripts/oracle.sh selftest` 复现噪声底（重复轮逐位相同；CPU 自身 in_tol ≥ 0.99999994；跨后端 mean ≈0.014）；`oracle.lock` 的 sha 校验失败时拒绝运行；用户 `defaults export org.darktable` 前后逐字节相同。
6. **对照**：dp 官方包自身（self-test）。
7. **回退**：脚本与 lock 新增；缓存目录可删。
8. **估时**：2 lane × 2.5 h（估算）。
9. **风险**：5.7.0 无 macOS dmg → 降级 5.6.2 + 先跑 tag 差异报告（§1.2 第 10 条）；**需要用户裁决？否**（按预案执行并把结果写进 issue）。
10. **任务书草案**：输入 = §4 配方 + 证据目录的 URL/sha/脚本；变换规则 = 缓存优先、sha 必验、HOME 双隔离、16 位 PNG、全分辨率；验收 = self-test 三数 + 偏好未变；产出 = 一条命令 + lock 文件。

#### A6 Apple 模块边界
1. **目标**：Apple 能力只存在于 `dt-apple`，非 macOS 构建编成空壳，界面只读能力表。
2. **范围**：`dt-apple`（CIRAW/ColorSync/Vision/ImageIO/Metal 的骨架）、`dt-app::capabilities()`、feature/cfg 门控、符号门测试。不做：任何像素实现（CIRAW 排 C）。
3. **输入**：`SPIKE-RUST-APPLE.md`（四项能力已跑通的最小调用）、`VERIFY.md` §1；`CORE-DESIGN.md` §6 的门控修正。
4. **产出**：空壳 crate + 能力表 + 三条机检 + 一份「能力在不在」的说明文档。
5. **验收**：§2.7 的三条机检全绿；`cargo build -p dt-cli --no-default-features` 在 Apple 缺失时通过；`dt-apple` 的空壳在 `--target` 非 macOS 时零符号（用 `cargo check` 的依赖树 + `nm` 间接验证）。
6. **对照**：`SPIKE-RUST-APPLE` 的证据（四项能力的输出逐字节）——本波只验边界，不重跑能力。
7. **回退**：crate 删除；能力表退化为空。
8. **估时**：1 lane × 2 h（估算）。
9. **风险**：`dt-apple` 恒为成员会把 objc2 拖进 `cargo build --workspace`（非 macOS 时）→ 依赖放 target 表，A6 用 `cargo tree -e normal` 验证；**否**。
10. **任务书草案**：输入 = spike 的最小调用与门控修正；变换规则 = 只做边界与能力表、不写解码；验收 = 三条机检；产出 = 空壳 + 能力表。

#### A7a 核心↔界面接口
1. **目标**：`dt-api` 的三件套 + `CoreHandle` 定型，headless 可测。
2. **范围**：`dt-api`（Command/Query/Event/CoreHandle/PresentSink trait）、`dt-app` 的装配、一个内存 `PresentSink`。不做：真实渲染（B1 起）。
3. **输入**：§2.5；`CORE-DESIGN.md` §1；#28 的「latest-wins」教训。
4. **产出**：类型 + 通道 + 超时 + 事件代际 + 背压（同一输出面只留最新）+ 5 条 headless 测试（命令顺序、查询一致性、事件不丢、latest-wins、取消）。
5. **验收**：`cargo test -p dt-api` 绿；一条 `dt-cli` 的 `--headless` 命令能走完 OpenImage→RenderReady→Export 的空实现；`rg 'metal|objc|CoreImage' crates/dt-api` = 0。
6. **对照**：无（接口面）。
7. **回退**：新增 crate。
8. **估时**：2 lane × 2.5 h（估算）。
9. **风险**：查询同步 RPC 与 UI 主线程互锁 → 查询走独立线程 + 超时，A7a 用「主线程阻塞 100 ms 时查询仍返回」的测试钉住；**否**。
10. **任务书草案**：输入 = §2.5 + #28 的 latest-wins；变换规则 = 命令单向、查询 RPC、事件广播、代际合并；验收 = 5 条测试 + headless 闭环；产出 = 类型 + 实现 + 测试。

#### A7b 视口与输入
1. **目标**：在 gpui-fast 窗口里放一个自建 Metal 视口，**实测**输入归属并定案。
2. **范围**：`dt-gpui` 的最小窗口（左视口/右面板）、`dt-apple` 的 `PresentSink`（CAMetalLayer）、`on_input` 转发、键盘窗口绑定。不做：真实像素（只画测试图）。
3. **输入**：`gpui-viewport/SPIKE-VIEWPORT.md` 与 `src/`（244 KB 全量源码，可直接搬）；`gpui-fast-scout/R2-CAPABILITIES.md` §1。
4. **产出**：可跑的窗口 + 视口（16F + EDR 标记）+ 输入事件日志（指针 down/move/up/scroll 到核心事件）+ 一份输入归属结论（`on_input` 可用/不可用）。
5. **验收**：`cargo run -p dt-gpui -- --viewport-probe`：① 视口占满布局区（几何四值一致）；② 指针事件全部到达核心（合成 20 步，到达 ≥19）；③ 面板重绘时视口不卡（11 s 探针，视口变化帧 ≥ 450；spike 实测 514，≈46.7/s）；④ `on_input` 不可用时自动落到 NSView 子类（探针脚本两条路都跑，报告写哪条过）。
6. **对照**：`SPIKE-VIEWPORT` 的 V1/V3 数字（几何一致、514 帧/11 s）。
7. **回退**：`dt-gpui` 是新增；gpui 版本锁死，失败就停在 spike 版本。
8. **估时**：2 lane × 3 h（估算；首构建 5.5 min + 增量 40–100 s）。
9. **风险**：`on_input` 未实测、浮层点击穿透未验证 → 本波就是为它设的；若两条路都不可用，退到 `deferred` 浮层 + 全局快捷键（视口不做局部交互），并把结论上报；**需要用户裁决？仅当两条路都不成立**。
10. **任务书草案**：输入 = SPIKE-VIEWPORT 源码与 V1/V3 读数；变换规则 = 原生表面 + 自建层、`on_input` 优先、NSView 子类兜底、独立 16 ms 循环；验收 = 四条探针；产出 = 窗口 + 结论。

### 阶段 B — 第 0 期（20 波，76 lane）

> 里程碑：B11 后 CLI 能逐模块过 golden；B16 后无界面全链闭环；**B20 后第一个能日常修图的版本**。
> 每个模块波的「对照」默认 = `Scripts/oracle.sh compare --module <op> --fixture fixtures/xmp/<op>-default.xmp --image <CC0 A7R5>`；「回退」默认 = 单模块目录删除 + `fixtures` 还原（每模块独立目录，互不牵连），下面不再重复。

#### B1 管线内核
1. **目标**：`dt-core` 的 Frame/Roi/tiling/缓存/13 步调度可跑，四个管线实例（FULL/EXPORT/THUMBNAIL/PREVIEW）同构不同配额。
2. **范围**：`dt-core`；`dt-iop-traits` 的 `IopModule`；一个 `identity` 测试模块。不做：任何真实模块、色彩变换、蒙版。
3. **输入**：`CORE-DESIGN.md` §1 的 13 步与 T1 的回调映射；`dt-master` 的 `pixelpipe_hb.c`（只读）。
4. **产出**：roi 前推/反推、格式协商、tiling 决策、缓存键（参数 hash ⊕ 输入代际）、行级 rayon、错误路径。
5. **验收**：`cargo test -p dt-core`：① roi 链 8 例（含 crop/scale 的 round-trip）；② tiling overlap 与 dt 的 `TilingReq` 一致；③ 缓存键负测（改一个参数只失效该节点及下游）；④ 双跑逐位；⑤ 全链 61MP 空转 < 200 ms。
6. **对照**：无像素对照；tiling 数字对 dt 的 `tiling_callback` 语义。
7. **回退**：新增 crate。
8. **估时**：3 lane × 3 h（估算）。
9. **风险**：缓存键设计错 → 每次编辑全链重算（编辑等待爆炸）；B1 就用「改 exposure 只重算 exposure 之后」的测试钉住；**否**。
10. **任务书草案**：输入 = 13 步 + T1 + `pixelpipe_hb.c`；变换规则 = 同步 trait、管线持有缓存/tiling、模块内 rayon；验收 = 五条测试 + 61MP 空转；产出 = core + trait + identity 模块。

#### B2 rawspeed 解码
1. **目标**：ARW/RAF/NEF 解成「马赛克 + 黑/白电平 + WB + 矩阵 + 裁剪框」，坏文件不 abort。
2. **范围**：`dt-decode` 的 C ABI shim、`CameraMetaData` 单例、栅格解码（JPEG/TIFF/PNG）。不做：去马赛克、CIRAW。
3. **输入**：`SPIKE-RUST-APPLE` 的 shim（165 行 + 68 行头）；`rawspeed-backend/SPIKE.md` 的 34–57 ms 读数；`cameras.xml` 随包分发。
4. **产出**：`rs_*` API、Rust 安全包装、错误码、元数据、`dt-cli decode --dump`。
5. **验收**：① 三个 CC0 样张（ARW/RAF/NEF）解出的宽高/黑电平/白点/WB 与 rawspeed 的 dump 逐值相等；② 坏文件返回错误码且进程存活（`SIGABRT` 不出现）；③ 同文件两次解码逐位相同；④ 单文件解码 ≤ 80 ms（A7R5，冷）。
6. **对照**：rawspeed 自己的 dump；CIRAW 只作旁证（不设门）。
7. **回退**：`dt-decode` 新增；shim 独立。
8. **估时**：2 lane × 3 h（估算）。
9. **风险**：rawspeed 的 cmake 构建与 `cameras.xml` 路径 → 用固定 cmake 配方 + 资源随包（dt 同款）；**否**。
10. **任务书草案**：输入 = shim + 三个样张 + `cameras.xml`；变换规则 = C ABI 薄封装、单例 meta、错误码不 abort；验收 = 四条；产出 = 解码 crate + dump 命令。

#### B3 raw 头段四件（rawprepare / hotpixels / temperature / highlights）
1. **目标**：黑电平/白点、坏点、白平衡、高光重建四件与 dt 逐像素一致；**这四件是 RAW 默认启用的**，必须在第一次 demosaic 对照之前就位。
2. **范围**：`dt-iop-raw` 的 rawprepare/hotpixels/highlights、`dt-iop-color` 的 temperature。不做：demosaic、rawdenoise、rawoverexposed。
3. **输入**：T7 的第 1/3/5/2 行；`release-5.7.0` 的四个 `.c`；T5 的 params 版本（temperature v4/20B、highlights v4/48B）。
4. **产出**：四个模块 + 各自单测 + 四个单模块 XMP 夹具（highlights 4 种模式各一份）。
5. **验收**：四个 `oracle compare --module` 过门；四个 params 布局测试过；temperature 的 CCT↔xy 与 dt 的 lcms2 结果差 < 1e-4；highlights 的 4 种模式各自过门。
6. **对照**：oracle（单模块 XMP）。
7. **回退**：四个目录删除。
8. **估时**：6 lane × 2 h（估算；highlights 2 lane）。
9. **风险**：temperature 的 as-shot WB 来源（rawspeed vs dt 的 `reload_defaults`）→ 用 oracle 的 XMP 读回值做真值；highlights 的小波重建是隐藏复杂度 → 若超 3 h，只做 opposed+clip 两种模式并告知；**否**。
10. **任务书草案**：输入 = 四个源文件 + T5 行 + 四份 XMP；变换规则 = 逐行转写、lcms2 只用于 CCT 数学、highlights 模式枚举全保留；验收 = 四个 oracle + 布局 + 四模式；产出 = 四模块。

#### B4 demosaic（RCD + passthrough）
1. **目标**：RCD 与 dt 的默认算法逐像素一致；passthrough 供调试；X-Trans 明确回退。
2. **范围**：`dt-iop-raw` 的 demosaic；`data/kernels/demosaic_rcd.cl` 的算法与 `demosaic.c` 的调度/回退语义。不做：AMaZE/PPG/VNG/Markesteijn/LMMSE、GPU、捕获锐化。
3. **输入**：T7 第 6 行；`demosaic.c` + `demosaic_rcd.cl`；`CORE-DESIGN-TABLES.md` 的 T3 计时表（MHC 43.4 ms 为量级参考；注意与本文件 PLAN-TABLES 的 T3=描述字段 同名不同物）。
4. **产出**：RCD（绿地插值 + 色差 + 方向判决的完整移植）+ passthrough + 边界/裁剪（dt 的 4 像素边框）+ X-Trans 检测与警告。
5. **验收**：`oracle compare --module demosaic`（RCD 默认）过门；A7R5 全分辨率 RCD 单次 ≤ 120 ms（10 核）；passthrough 与输入马赛克逐位相同；X-Trans 文件走 passthrough 且日志有 warning；边界 8 例（奇偶宽高/裁剪框）无越界。
6. **对照**：oracle 的 RCD 输出；另外用 dt 的 `--conf plugins/darkroom/demosaic/quality=...` 不设门（只记录）。
7. **回退**：demosaic 目录删除，管线退 passthrough。
8. **估时**：4 lane × 3 h（估算；RCD 是本阶段最大的单点）。
9. **风险**：RCD 的方向判决与 dt 的 `RCD_GRAD_PERCENTILE` 等常数错一个就过不了门 → 逐常数对照 + 中间量（绿面插值）分步 golden；**需要用户裁决？仅在 120 ms 目标达不到时**（放门到 200 ms 由用户定）。
10. **任务书草案**：输入 = `demosaic.c` + `demosaic_rcd.cl` + 三张样张；变换规则 = 只 RCD + passthrough、保留 dt 的边界语义、常数逐字；验收 = oracle + 计时 + 边界；产出 = 模块 + 分步 golden 日志。

#### B5 色彩三段（colorin / colorout / gamma）
1. **目标**：相机矩阵→工作空间→显示/输出的色彩链与 dt 一致，输出 8/16 位 gamma。
2. **范围**：`dt-iop-color` 的 colorin/colorout、`dt-iop-display` 的 gamma、`dt-color` 的 lcms2 腿。不做：软打样、DRT、HDR 输出。
3. **输入**：T7 第 13/18/21 行；`colorin.c`/`colorout.c`/`gamma.c`；`colorspaces.c` 的矩阵；T5 的 v7/1044B。
4. **产出**：三个模块 + ICC 路径（内嵌/标准）+ 工作空间 = linear Rec2020 + sRGB 输出 + 16 位 PNG/TIFF 写出。
5. **验收**：三个 `oracle compare` 过门（colorin/colorout 用含内嵌 ICC 的样张；gamma 单独）；输出 PNG 的 IHDR 位深 = 16；sRGB 输出的色度与 dt 差 < 1e-3（用 ColorSync 读回）；无 ICC 的样张走标准矩阵且过门。
6. **对照**：oracle；`colorin` 另加「同一 RAW 在 dt 与我们的 colorout 之后逐通道均值差 < 1 LSB8」。
7. **回退**：三目录删除；`dt-color` 保留（后续模块用）。
8. **估时**：5 lane × 3 h（估算）。
9. **风险**：lcms2 的 intent/black point 语义与 dt 的封装不同 → 只走 dt 的调用参数（perceptual + 无 BPC），B5 会逐行读 `colorspaces.c`；**否**。
10. **任务书草案**：输入 = 三个源文件 + `colorspaces.c` + 样张；变换规则 = 工作空间 linear Rec2020、输出按 params 的 ICC、gamma 只在显示链；验收 = 三个 oracle + 位深 + 色度；产出 = 三模块 + 输出编码。

#### B6 尾段三件（finalscale / dither / overexposed）
1. **目标**：缩放、抖动、过曝标注三件与 dt 一致。
2. **范围**：`dt-iop-display` 的 finalscale/dither/overexposed（overexposed 只做像素标注，不做 cairo 叠加）。不做：rawoverexposed、scopes。
3. **输入**：T7 第 17/19/20 行；三个源文件。
4. **产出**：三模块 + 单测。
5. **验收**：三个 oracle 过门；dither 的两种模式在同一输入下与 dt 逐位相同（固定种子）；overexposed 的阈值写进 XMP 后被 oracle 读回且渲染过门（参数面只暴露阈值）。
6. **对照**：oracle。
7. **回退**：三目录删除。
8. **估时**：3 lane × 2 h（估算）。
9. **风险**：overexposed 在 dt 是 HIDDEN 显示辅助、无 params → 我们只做像素标注 + 一个阈值参数，历史面不写它；**否**。
10. **任务书草案**：输入 = 三个源文件；变换规则 = finalscale 用公共缩放、dither 固定种子、overexposed 只标注；验收 = 三个 oracle + 位深；产出 = 三模块。

#### B7 两级色差校正（cacorrect / cacorrectrgb）
1. **目标**：前后两级 CA 校正与 dt 一致。
2. **范围**：`dt-iop-geom` 的 cacorrect/cacorrectrgb。不做：rawdenoise、rawoverexposed、colorreconstruct。
3. **输入**：T7 第 4/8 行；两个源文件 + `cacorrect.cl`/`cacorrectrgb.cl` 的算法。
4. **产出**：两模块 + 单模块 XMP。
5. **验收**：两个 oracle 过门；`iterations`/阈值字段与 5.7.0 布局夹具逐值相等、且写进 XMP 后被 oracle 读回；性能（61MP）单模块 ≤ 300 ms。
6. **对照**：oracle。
7. **回退**：两目录删除。
8. **估时**：4 lane × 2.5 h（估算）。
9. **风险**：cacorrect 的寻边迭代在 CPU 上慢 → 若超 300 ms，按 dt 的分块/提前退出优化；**否**。
10. **任务书草案**：输入 = 两源文件 + 两个 `.cl`；变换规则 = 逐行、参数枚举全保留；验收 = 两 oracle + 性能；产出 = 两模块。

#### B8 曝光与镜头（exposure / lens）
1. **目标**：曝光的三种模式与镜头的畸变/TCA/暗角与 dt 一致。
2. **范围**：`dt-iop-display` 的 exposure、`dt-iop-geom` 的 lens（lensfun 数据 + 三校正）。不做：ashift、裁剪、去畸变的交互工具。
3. **输入**：T7 第 11/7 行；`exposure.c`/`lens.cc`；lensfun 数据库（钉版本）。
4. **产出**：两模块 + lensfun 数据随包（独立许可文件）+ 单模块 XMP。
5. **验收**：两个 oracle 过门；lens 的三种校正各一例（畸变/TCA/暗角）都过；相机+镜头匹配失败时退化为恒等且有日志；lensfun 数据版本写进 NOTICE。
6. **对照**：oracle（含 profile 的样张）。
7. **回退**：两目录删除；lensfun 数据保留在资源目录（不影响其它）。
8. **估时**：4 lane × 3 h（估算）。
9. **风险**：lensfun 的 C++ API 与数据格式 → 用 `lensfun` 的 C API（`lf_db`/`lfModifier`），不引 C++ 绑定；**否**。
10. **任务书草案**：输入 = 两源文件 + lensfun 数据；变换规则 = 只做三校正、自动镜头匹配用 EXIF；验收 = 两 oracle + 三校正；产出 = 两模块 + 数据。

#### B9 方向与裁剪（flip / crop）
1. **目标**：方向与裁剪的 ROI 语义与 dt 一致。
2. **范围**：`dt-iop-geom` 的 flip/crop。不做：clipping（deprecated）、rotatepixels/scalepixels。
3. **输入**：T7 第 10/12 行；`flip.c`/`crop.c`。
4. **产出**：两模块 + ROI 测试（crop 的 `cx/cy/cw/ch` 与 aspect）。
5. **验收**：两个 oracle 过门；crop 的 ROI 前推/反推 8 例；flip 的 8 种方向逐位；crop 之后的下游模块看到的 ROI 与 dt 同（用 identity 模块记录）。
6. **对照**：oracle + dt 的 ROI 日志。
7. **回退**：两目录删除。
8. **估时**：3 lane × 2 h（估算）。
9. **风险**：crop 是「最后才生效」的模块（顺序 24.5），ROI 语义容易反 → B1 的 roi 测试先覆盖；**否**。
10. **任务书草案**：输入 = 两源文件 + B1 的 roi 接口；变换规则 = crop 只在输出 ROI 生效、flip 改方向位；验收 = 两 oracle + roi 8 例；产出 = 两模块。

#### B10 透视（ashift）
1. **目标**：ashift 的手动参数（旋转/透视/镜头位移）与 dt 一致。
2. **范围**：`dt-iop-geom` 的 ashift；求解器（`ashift_lsd`/`ashift_nmsimplex`）**不移植**。不做：自动校正、交互取点。
3. **输入**：T7 第 9 行；`ashift.c` 的手动路径与 `get_homography`；T5 的 892B。
4. **产出**：ashift（手动）+ ROI/几何变换 + 单模块 XMP。
5. **验收**：`oracle compare --module ashift`（手动参数）过门，几何允许 ±1 px 搜索；自动求解器在 UI 不存在（描述里无 auto 控件，`xtask check-panels` 断言）；手动参数往返 XMP 逐字节。
6. **对照**：oracle。
7. **回退**：目录删除。
8. **估时**：3 lane × 3 h（估算）。
9. **风险**：ashift 的裁剪/自动缩放语义（`crop_mode`）→ 只做 `largest_area` 之外的默认手动路径，参数面保留但自动项禁用；**否**。
10. **任务书草案**：输入 = `ashift.c` 的手动路径；变换规则 = 只移植单应矩阵与重采样、不移植求解器；验收 = oracle + ±1px；产出 = 模块。

#### B11 曲线三件（rgbcurve / rgblevels / tonecurve）
1. **目标**：三条曲线与 dt 逐像素一致（含单调 Hermite 与三通道）。
2. **范围**：`dt-iop-display` 的三模块。不做：basecurve/filmic（C/D）。
3. **输入**：T7 第 14/15/16 行；三个源文件；T5 的 516B/44B/520B。
4. **产出**：三模块 + 曲线求值器（共享）+ 单模块 XMP（各 2 组）。
5. **验收**：六个 oracle 过门（每模块 2 组）；tonecurve 的 3 通道 + 单色模式各一例；rgbcurve 的 6 种插值各一例；数值边界（0/1 节点、重复 x）不 panic。
6. **对照**：oracle。
7. **回退**：三目录删除。
8. **估时**：6 lane × 2 h（估算；两条并行 lane 一批）。
9. **风险**：dt 的 `tonecurve` 有 LUT 化路径（commit 预计算），必须同样 LUT 化否则性能与数值都不对；**否**。
10. **任务书草案**：输入 = 三源文件 + T5 字节；变换规则 = 曲线求值逐行、LUT 化保留；验收 = 六 oracle + 边界；产出 = 三模块 + 求值器。

#### B12 历史读（XMP → 栈）
1. **目标**：打开一张 dt 修过的图，模块栈、顺序、多实例、blend/蒙版记录、`history_end` 全部就位。
2. **范围**：`dt-history` 的 XMP 读取器（A4a 选定的库）+ 栈构建 + `dt-cli open --print-stack`。不做：写 XMP（B13）、渲染（B13 之后接管线）。
3. **输入**：A4b 的布局/迁移；A4a 的库；`HISTORY-COMPAT.md` §1/§2/§6；3 份真 XMP（含多实例）。
4. **产出**：读取器 + 栈 + 未知项语义（保留/跳过/告警）+ dump 命令。
5. **验收**：3 份真 XMP 的 dump 与期望 JSON 相等；未知 op 保留、`modversion` 超前用默认并告警、迁移失败丢条（三负测）；`iop_order_version` 4/5 都接受；无 XML 注释的 XMP 读成功、有前导注释的 XMP 复现 dt 的读失败（`probe-comment.xmp`）。
6. **对照**：dt 的 XMP 语义（`HISTORY-COMPAT` §6 的表）。
7. **回退**：读取器是新增模块。
8. **估时**：3 lane × 3 h（估算）。
9. **风险**：dt 的 `history_end` 语义（position < end）与多实例 `multi_priority` 的键控 → 用 3 份含多实例的 XMP 钉住；**否**。
10. **任务书草案**：输入 = 3 份真 XMP + `HISTORY-COMPAT` §1/2/6；变换规则 = 读 XMP→内存栈、未知项按 dt 语义；验收 = dump 相等 + 三负测；产出 = 读取器 + dump。

#### B13 历史写与图库数据库
1. **目标**：我们自己的修改两处存：本地 SQLite + 原图 XMP 的自有命名空间；dt 的内容一项不少。
2. **范围**：`dt-library`（schema、history/masks/order 表）、`dt-history` 的写回、XMP 自有命名空间、2 s debounce + 原子写。不做：dt 数据库互通、dt 格式的历史写回（无限延后）。
3. **输入**：B12；`HISTORY-COMPAT.md` §9 的 DB 口径；A4a 的写回测试。
4. **产出**：schema v1 DDL、写回器、`dt-cli save/load` 往返、sidecar 写回。
5. **验收**：`dt-cli save` 后 `dt-cli load` 的栈逐字段相等；写回后再让 oracle 写一次，我们的命名空间仍在、dt 的历史条目逐字节不变（A4a 测试 2/3 产品化）；崩溃注入（写一半）不产生半个文件；写回耗时 ≤ 50 ms（单图）。
6. **对照**：oracle 的 dt 重写。
7. **回退**：DB 是新增文件；XMP 写回有备份（写前 copy）。
8. **估时**：3 lane × 3 h（估算）。
9. **风险**：XMP 写回的原子性与 dt 的并发写（用户同时开 dt）→ 写前读 mtime，变了就重读合并；**否**。
10. **任务书草案**：输入 = B12 + A4a；变换规则 = 本地库 + 自有命名空间、dt 内容只读保留；验收 = 往返 + dt 重写 + 崩溃注入；产出 = schema + 写回 + 命令。

#### B14 蒙版与混合基础
1. **目标**：每模块自带蒙版与不透明度（dt 的 blend 语义），带蒙版的 dt 图观感一致。
2. **范围**：`dt-blend`（drawn brush/ellipse/gradient、parametric 亮度/色彩、组合、normal 混合、mask 变形）、`dt-core` 的 S6/S12 接通。不做：mask manager 面板、path 蒙版、从模块取栅格、羽化/精修（C）。
3. **输入**：`HISTORY-COMPAT.md` §5；`blend.c`/`blend.h`；`develop/masks/` 的 brush/ellipse/gradient；`CORE-DESIGN.md` §1 的 S6/S12。
4. **产出**：蒙版栅格化 + 组合 + 混合 + 参数读回（blend v15 整块保留）+ 缓存键含蒙版身份。
5. **验收**：`oracle compare`（带蒙版的 XMP）过门；模块 A 的蒙版不影响模块 B（测试）；蒙版编辑只失效受影响节点（缓存键测试）；blend v15 读回逐字节；几何模块后的蒙版随几何变形（1 例）。
6. **对照**：oracle（蒙版 XMP）。
7. **回退**：`dt-blend` 新增；S6/S12 的接通用 feature flag 关回短路。
8. **估时**：5 lane × 3 h（估算）。
9. **风险**：dt 的蒙版坐标是内容锚定（`masks_history`），与 ROI/几何耦合 → B14 先做无几何模块的 3 例，再补几何 1 例；**否**。
10. **任务书草案**：输入 = `blend.c/h` + `develop/masks/` + 蒙版 XMP；变换规则 = 先栅格化再混合、参数整块保留；验收 = oracle + 三测试；产出 = 蒙版/混合 crate。

#### B15 导入、图库、缩略图
1. **目标**：导入一个文件夹→灯箱网格有缩略图→评分/色标；10 万张仍可滚。
2. **范围**：`dt-library`（images/collection 表、导入器、EXIF 读）、缩略图（内嵌 JPEG 快路径 + 管线生成）、`dt-gpui` 的灯箱网格（B17 之前先用 `dt-cli` 验证数据面）。不做：层级标签/IPTC（C）、AI 分析（C）。
3. **输入**：#28 的缩略图失效教训；`GUI-darktable.md` 的 80 ms/张；`HISTORY-COMPAT` 的 EXIF 面。
4. **产出**：导入器 + 库 + 缩略图缓存（磁盘 LRU）+ 评分/色标字段 + 10 万行的虚拟列表数据接口。
5. **验收**：导入 101 张 ≤ 4 s（DB 完成）；缩略图 ≥ 15 张/s（并行）；改一张的评分后只有该缩略图失效（测试）；10 万行的查询/滚动数据接口 p95 < 16 ms（`dt-cli bench --library 100k`）。
6. **对照**：dt 的 101 张 <4.7 s、80 ms/张。
7. **回退**：库是新增文件；导入器可禁用。
8. **估时**：4 lane × 3 h（估算）。
9. **风险**：缩略图的 mip 策略（内嵌 JPEG 够不够大）→ 先内嵌 JPEG，再管线；不做 mip-from-mip（C）；**否**。
10. **任务书草案**：输入 = #28 教训 + dt 数字；变换规则 = 内嵌 JPEG 优先、后台管线补、评分/色标入 DB；验收 = 四条；产出 = 库 + 导入 + 缩略图。

#### B16 导出
1. **目标**：JPEG/PNG/TIFF（8/16 位）+ 尺寸/命名/元数据基本项，产物与 dt 同观感。
2. **范围**：`dt-export`（编码器、尺寸解析、命名、队列）。不做：HEIC/AVIF/WebP/JXL/PDF/XCF、ICC 剥离、yiyin。
3. **输入**：`FEATURE-SCOPE.md` §1 的导出流程；dt 5.7.0 的尺寸字段 `max_width/max_height`（`dt_imageio_module_data_t`）与 `src/libs/export.c` 的装配；`decode-oracle-evidence/RESULTS.md` 的 16 位 PNG。
4. **产出**：三编码器 + 尺寸（fit/longEdge/原始）+ 命名模板（`$(FILE_NAME)` 等 dt 的 token）+ 队列（最新胜出）+ 进度事件。
5. **验收**：`dt-cli export` 与 `oracle` 的 PNG16 逐像素过门；JPEG 的质量映射与 dt 同（同 quality 的 SSIM > 0.999 或字节数 ±2%）；命名模板 6 例；队列取消/重试；导出 61MP ≤ 3 s（单张，CPU）。
6. **对照**：oracle 的导出（同格式同参数）。
7. **回退**：`dt-export` 新增。
8. **估时**：3 lane × 3 h（估算）。
9. **风险**：JPEG 编码器的色度下采样与 dt 不同 → 以 SSIM/字节数双指标，不追字节相同；**否**。
10. **任务书草案**：输入 = 导出流程 + 尺寸规则；变换规则 = 三格式纯 Rust、命名按 dt token；验收 = oracle + 模板 + 性能；产出 = 导出 crate。

#### B17 界面壳与面板生成
1. **目标**：darktable 三区布局 + 从模块描述生成的面板 + 控件词汇（拖/双击复位/右键/行内数值）。
2. **范围**：`dt-gpui` 的窗口/主题/控件/面板 chrome/模块列表/参数编辑（走命令）。不做：视口像素（B18）、灯箱交互（B19）、预设/样式（C）。
3. **输入**：`gpui-spike/REPORT.md` §1/§2（7/12 交互一致）、`appkit-migration/INVENTORY.md` Q2/Q4、`gpui-fast-scout/R2-CAPABILITIES.md` §3/§4。
4. **产出**：控件库（fill-bar slider/combobox/toggle/section/curve）+ 面板容器 + 从 `ModuleDesc.panel` 生成 + 主题 token。
5. **验收**：`dt-gpui --panels-probe`：① 21 个模块面板全部由描述生成（改描述即改 UI，无硬编码 switch）；② #27 的 12 条交互清单逐条脚本化（每条一个命令或 AX 断言），至少 10 条绿；③ 30 模块面板滚动 ≥ 45 fps（密集网格）；④ IME：向搜索框合成输入「你好」并断言查询串回读一致；⑤ 与 dt 同模块展开的截图做三项像素断言（行高 ±2 px、标签左对齐 x、数值右对齐 x），并附并排图；⑥ `xtask check-i18n` 绿。
6. **对照**：dt 5.6.2 的暗房面板截图（同模块展开）。
7. **回退**：`dt-gpui` 是新增；控件库独立。
8. **估时**：5 lane × 3 h（估算）。
9. **风险**：gpui-kit 的滑杆是 thumb 不是 fill-bar（需自绘）；Enter 不进 `on_key_down`（需 key binding）；popover 需 `.occlude()`；**否**。
10. **任务书草案**：输入 = 原型报告 + 控件清单 + 描述；变换规则 = 自绘 darktable 控件、面板只读描述；验收 = 五条探针；产出 = 控件 + 面板 + 主题。

#### B18 视口与暗房布局
1. **目标**：真实像素进视口（缩放/平移/100% ROI），暗房三区可交互。
2. **范围**：`dt-gpui` 的视口 + 暗房布局 + `dt-apple` 的 `PresentSink` 真实实现 + `dt-core` 的 ROI 渲染。不做：scopes/histogram（C）、软打样/DRT（C）。
3. **输入**：A7b 的结论；B1/B2/B5 的管线；`#28` 的 latest-wins。
4. **产出**：视口（fit/100%/拖拽/滚轮）+ 暗房布局 + 渲染代际 + 进度。
5. **验收**：① 打开一张图 → 视口出现（首图 ≤ 1.2 s，fitted 2560）；② 拖动一张 61MP 图平移 ≥ 45 fps（密集探针；gpui 调研的 60 fps 只证 UI 层、无像素管线，不能当门）；③ 改曝光 → 预览更新 ≤ 200 ms p50（10 次中位）；④ 100% ROI 只渲可见区（日志断言渲染高度 < 视口高度 × 1.2）；⑤ 30 分钟连续编辑后 `/usr/bin/time -l` 的 ru_maxrss ≤ 起始 + 200 MB，关窗后回落 ≥ 80%。
6. **对照**：#26 的 dt 数字（1.79 s 首图、0.680 s 编辑）。
7. **回退**：视口用 feature flag 关回静态图。
8. **估时**：4 lane × 3 h（估算）。
9. **风险**：`PresentSink` 的零拷贝（IOSurface）在 gpui 层是否被覆盖；渲染代际抖动；**否**。
10. **任务书草案**：输入 = A7b + B1/B2/B5 + #28；变换规则 = 视口独立循环、ROI 渲染、代际合并；验收 = 五条；产出 = 视口 + 布局。

#### B19 灯箱、胶片条、快捷键与菜单
1. **目标**：灯箱网格/胶片条/评分色标/菜单快捷键可用。
2. **范围**：`dt-gpui` 的灯箱、胶片条、菜单、快捷键表、导入对话框、导出对话框。不做：集合/标签过滤（C）、打印/联机（D）。
3. **输入**：`appkit-migration/INVENTORY.md` Q2/Q4；dt 的快捷键（`data/darktableconfig.xml.in` 的 `accels` 键与 `src/gui/accelerators.c`）；GitHub `kamasylvia/Lightamer` 的 #27 交互清单。
4. **产出**：灯箱（虚拟列表）+ 胶片条 + 菜单 + 快捷键（可读 dt 的 `darktablerc`？不，第一版只内置）+ 两个对话框。
5. **验收**：10 万行灯箱滚动 ≥ 50 fps；评分/色标写库并反映在网格（查库断言）；快捷键 20 条与 dt 的 `accels` 逐条脚本比对；导入 101 张从菜单走通（DB 计数）；IME 在搜索框输入「你好」后查询结果含该串。
6. **对照**：dt 的同页截图 + 快捷键表。
7. **回退**：页面用 feature flag 关。
8. **估时**：4 lane × 3 h（估算）。
9. **风险**：虚拟列表的行级分层（gpui-fast 的 list layers）与选中态；**否**。
10. **任务书草案**：输入 = INVENTORY Q2/Q4 + dt 快捷键表；变换规则 = 自绘网格/胶片条、命令走 `dt-api`；验收 = 五条；产出 = 灯箱/胶片条/菜单/对话框。

#### B20 闭环验收（首个可用版）
1. **目标**：从卡到成品走通，21 个模块逐条过 golden，性能与 dt 同档，出验收报告。
2. **范围**：端到端脚本、性能脚本、验收清单、issue 收口。不做：新功能。
3. **输入**：B1–B19。
4. **产出**：`Scripts/e2e.sh`（导入→灯箱→暗房改 5 个模块→导出）、`Scripts/perf.sh`（M1/M2/批量/缩略图）、验收报告。
5. **验收**：① 21 个模块的 oracle 门全绿（一条命令汇总）；② 打开 dt 修过的 3 张图（不同模块组合）观感过门；③ 性能四项（T11）达标；④ 连续 30 分钟编辑无崩溃/无 RSS 增长 > 20%；⑤ 三个产物用 `sips -g pixelWidth -g pixelHeight` 读出正确尺寸、`qlmanage -t` 生成缩略图成功（脚本）。
6. **对照**：dt 官方二进制（全链）；`#26` 的基线。
7. **回退**：验收脚本独立；不达标项写 issue 并标「未完成」，不带病发布。
8. **估时**：2 lane × 3 h（估算）。
9. **风险**：性能不达标（尤其编辑等待）→ 按 #28 的定位法（先测再改），不在本波盲改；**需要用户裁决？是**——若编辑等待 > 300 ms，是否接受发布（用户定）。
10. **任务书草案**：输入 = 前 19 波；变换规则 = 只跑不改（发现缺陷另开波）；验收 = 五条；产出 = 三个脚本 + 报告。

---

## §4 阶段 C 与阶段 D（清单，不展开）

### §4.1 阶段 C — 第 1 期（≈22 波，≈130 lane）

- **C-1 调色全量（≈18 波）**：50 个模块（T10 的 C 行），按域分波：色彩平衡（colorbalance/colorbalancergb/colorzones/colorequal/colorharmonizer/colorcontrast/primaries/velvia/vibrance）、通道与 LUT（channelmixer/channelmixerrgb/lut3d/colorchecker/colormapping/colortransfer）、影调（filmicrgb/sigmoid/agx/levels/shadhi/toneequal/equalizer）、细节（denoiseprofile/nlmeans/bilateral/atrous/sharpen/diffuse/defringe/hazeremoval/blurs/lowpass/highpass）、修饰（retouch/spots/liquify）、几何补充（rotatepixels/scalepixels/rawdenoise/rawoverexposed/colorreconstruct）、创意（monochrome/colorize/splittoning/bloom/grain/vignette/soften）、darktamer（borders/watermark）。基线之外的 `satcurvergb`/`demosaicscale`/`contrastntexture` 同批从 master 取源。
- **C-2 胶片**：`spektrafilm`（dt 模块 + 其 profile 数据；不用 SpektraLab 资产）。**它不在 5.7.0 发布版**：源从 master 取并钉提交，验收无官方 oracle（参数往返 + 目视 + 与 darktamer 成片比对）。如果届时官方已发含它的版本，改用官方 oracle 并重新基线。
- **C-3 HDR 视口与软打样**：EDR 输出链、软打样 ICC、直方图/示波器（scopes）、HDR 验收（需 EDR 屏）。
- **C-4 图库检索与标签**：层级标签、IPTC 关键词、集合/过滤、搜索语法。
- **C-5 批量导出**：命名模板全量、元数据策略、ICC 剥离、批量队列、HEIC/AVIF/WebP/JXL/PDF/XCF 编码器。
- **C-6 完整蒙版**：mask manager 面板、path 蒙版、从模块取栅格、羽化/精修、参数化全参。
- **C-7 Lightamer 独有（合成）**：全景拼接、焦点合成、HDR 合成（对齐/去鬼影）。
- **C-8 Lightamer 独有（显示与版本）**：节点式 DRT（Develop→Color Grade×N→Display Transform）、版本分支、快照。
- **C-9 Lightamer 独有（AI 与接口）**：AI 标签/评分、MCP 面回归（34 工具契约）、Apple 模块的 Vision 能力（分割/人脸）。
- **不排期**：人像三件 #35/#36/#37（skinsmooth/skinmask/reshape）——上游未完成，等 darktamer。

### §4.2 阶段 D — 第 2 期（≈10 波，≈60 lane）

- **D-1 打印**（dt `views/print` + `libs/print*`）。
- **D-2 联机拍摄**（`views/tethering` + `common/tethering`）。
- **D-3 地图/geotag**（`views/map` + `libs/geotagging`）。
- **D-4 幻灯片**（`views/slideshow`）。
- **D-5 Lua**（或 Rust 插件替代；先做兼容层评估）。
- **D-6 长尾模块 I（影调/显示）**：invert, tonemap, graduatednd, profile_gamma, basecurve, filmic, negadoctor, zonesystem, globaltonemap, relight, colisa, bilat。
- **D-7 长尾模块 II（色彩/创意）**：colorcorrection, basicadj, lowlight, clahe, censorize, colorize（若 C 未做）, contrastntexture, neutral。
- **D-8 长尾模块 III（画布/输入）**：enlargecanvas, overlay, rasterfile。
- **D-9 主题/快捷键编辑器**（用户可编辑的键位/主题）。
- **D-10 Windows/Linux 构建**（可选；gpui-fast 的非 macOS 合成未验证，EDR 语义不同）。

---

## §5 质量门与检查点

### §5.1 每波必过（机检）

| 门 | 命令 | 失败处置 |
|---|---|---|
| 格式/静态 | `cargo fmt --check`；`cargo clippy --workspace -- -D warnings` | 修到绿 |
| 测试 | `cargo test -p <touched>`（模块波：该模块 + `dt-core` + `dt-history`） | 修到绿 |
| 像素对照 | 触碰像素：`Scripts/oracle.sh compare --module <op>`，mean<1 LSB16 且 in_tol>0.9999 | 不过门不得进下一波 |
| 确定性 | 同输入同参数双跑，输出逐位相同（或平面 hash 相同） | 查线程/浮点顺序 |
| 性能 | 触碰渲染：`Scripts/perf.sh --quick`（编辑等待、首图），对 T11 | 记录，不 block；超 2× 才 block |
| 内存 | 61MP 全链峰值 < 5 GB（`/usr/bin/time -l` 的 ru_maxrss，与 #26 同口径），swap 增长 < 500 MB（`vm_stat` 前后差） | 降到分块/释放缓存 |
| 机器 | `Scripts/guard.sh` PASS；一次一个重活；`target/` 共享 + `flock` | 等或串行 |
| 依赖 | 新增依赖在 A1 表内 + `NOTICE` 更新 | 补表或不用 |
| 边界 | `rg 'objc2|metal::|CoreImage' crates --glob '!crates/dt-apple/**'` = 0；核心零 op 名 | 移回 `dt-apple`/描述 |
| 本地化 | 新用户可见字符串在中英两份表内（`xtask check-i18n`） | 补键 |

### §5.2 计时与稳定性纪律（继承 #26 与既有教训）

- 计时前先跑 launch control（`fontd` 首次字体查找会加 ~2 s，用户拒绝重启 `fontd`）。
- 一次一个重活；GUI lane 在 4 GB swap 或 20% 空闲内存处熔断；大文件最后测。
- 探针必须用密集网格（480×400）自检；细于 18 pt 的特征用稀疏网格会漏（`REPORT-BISECT` 教训）。gpui 的最小程序在同网格上是 30–37/40（`gpui-fast-scout/T1-BENCH.md` §0 第 1 行），UI 波的帧率门以它为下限参考，不以 60 fps 的合成指标为门。
- 不 `killall cfprefsd`；darktable 的域先 `defaults export`。
- 用户照片库只读、永不入 git、永不进证据目录。

### §5.3 检查点

- **阶段 A：每一波之后停**（A1–A7b，9 次）。汇报：本波产出、验收命令与结果、下一波摘要、需用户裁决项（几乎没有）。
- **阶段 B：每一波之后停**（B1–B20，20 次）。模块波汇报 oracle 的门数与失败项；UI 波附截图。
- **阶段 C 起：连跑**，每完成一波在 issue 记一行，每周一次汇总；只在「需用户裁决」（EDR 验收、性能门是否放宽、范围变更）时停。

### §5.4 存量 Metal 着色器的用法（73 个，逐名见 T9）

- **19 个 P0 直接参考**：exposure/temperature/lens/flip/ashift/tonecurve/levels/white-black/blend/蒙版四件/histogram/scope/blur/Lab/Cat02WB。用途是**交叉核对** Rust CPU 实现的公式与 uniform 布局，不是移植源（真源是 dt 的 `.c`/`.cl`）。
- **35 个 P1 参考**：dt 全量调色与细节模块的自研移植版；可看结构，常数不可照抄（它们按旧管线的参数范围调过）。
- **10 个独有功能参考**：只服务保留的 Lightamer 独有功能（节点 DRT/版本）；**`SpectralFilm*` 不是 `spektrafilm` 的源**。
- **9 个用不上**：旧视口 blit、测试脚手架、人像三件（不排期）、不在保留清单的 ColorMatch、印框文字层（borders/watermark 以 darktamer 的 `borders.c` 为源）。

---

## §6 风险与没查到的

### §6.1 风险（按影响排序）

| # | 风险 | 证据/来源 | 缓解 | 触发后的处置 |
|---|---|---|---|---|
| R1 | **参数布局钉错版本** | T5：4 处 T2 字节数是 master 值；temperature v4/v5、colorin v7/v8 已实证 | A4b 夹具来自 `release-5.7.0` + oracle 的 modversion 回读；禁止 master/二进制混用 | 重生成夹具，重跑 21 模块 oracle |
| R2 | **模块移植量**（P0 38 lane，C 还有 50 个模块 + 基线外 1 个） | T7/T8 | 单模块独立目录 + 单模块 XMP；demosaic/lens/ashift 单独设风险波 | 拆波或降级（如 highlights 只做 2 模式）由用户确认 |
| R3 | **UI 底座未定型** | gpui-fast 0.1.x、无 issue tracker、周更；`on_input` 未实测；EDR 无屏 | 版本锁死；A7b 先测输入；视口与 gpui 解耦 | 输入两条路都不成立 → 视口只做只读 + 全局快捷键；上报用户 |
| R4 | **RCD 达不到 120 ms 或过不了门** | T3 只有 MHC 43.4 ms 的量级参考，RCD 是估算 | B4 分步 golden（绿面→色差→方向）；常数逐字 | 放宽到 200 ms 或只做 2 方向近似，由用户定 |
| R5 | **蒙版观感不一致** | dt 的蒙版坐标内容锚定 + 几何耦合 | B14 先无几何 3 例；几何 1 例 | 把几何+蒙版组合标为已知缺口，C 补 |
| R6 | **XMP 库选型失败** | T6 三候选都有未知 | A4a 三测；兜底 XML 直改 | 自研成本上升，A4b 加 1 lane |
| R7 | **16 GB 机器 + 构建/测试** | #26 的 swap 熔断；gpui 首构建 5.5 min、target 3.8 GB | 共享 target + flock；预算脚本；一次一个重活 | 清理 target，拆 crate |
| R8 | **HDR 验收无屏** | `SPIKE-VIEWPORT`：本机 headroom 1.000 | 程序侧只做数值断言（16F + EDR 标记 + >1.0 回读）；屏幕验收挂 C-3 | 等 EDR 屏，不伪造验收 |
| R9 | **dt 版本漂移** | `git describe` = 5.7.0+2234 | 钉 tag；`oracle.lock`；升级 = 一次重新基线 | 重新基线一轮（A5 的成本） |
| R10 | **GPL 合规** | rawspeed 许可两说；lensfun 数据 CC BY-SA | A1 逐项核实；数据独立分发 | 法务问题停波，不改许可 |
| R11 | **spektrafilm 无官方 oracle** | 5.7.0 发布版没有该模块（§1.3）；用户又指定用它 | C-2 从 master 取源并钉提交；验收降为往返 + 目视 + 与 darktamer 成片比对 | 等官方发含它的版本再升级为 oracle；或用户接受"目视验收" |

### §6.2 没查到的（本计划不作假设）

- rawspeed 的实际 LICENSE 文本（子模块未 checkout）；LGPL-2.1 与 3.0 的最终结论。
- `xmp_toolkit` 在 macOS 27 的 cmake 构建可行性；`xmpkit` 的 unknown-key 行为。
- `release-5.7.0` 是否有官方 macOS dmg；5.6.2 与 5.7.0 的 21 模块 params 差异全表（只抽了 6 个）。
- gpui-fast 的 `on_input` 实际行为、浮层点击穿透、live resize（A7b 实测）。
- gpui 族的 EDR 在真实 EDR 屏上的表现（无屏）。
- RCD 的真实耗时与画质（只有 MHC 的量级参考）。
- dt 的 21 模块在 5.7.0 上的完整 `sizeof`（手算了 7 个，4 个与 T2 不符）。
- 50 个 C 期模块的移植难度分档（只按行数与依赖粗分）。
- 打印/联机/地图/幻灯片/Lua 的移植可行性与工作量（P2，未调研）。
- 10 万张灯箱在 gpui-fast 下的真实帧率（只测了 10 万行虚拟列表，非图片网格）。

### §6.3 与调研的数字不一致处（已按证据更正）

- T2 的 params 字节：4 处（temperature/demosaic/highlights/colorin）见 T5。
- `HISTORY-COMPAT` 的 9 个 modversion：2 处（temperature/colorin）见 §1.3。
- `CORE-DESIGN` §9 的 rawspeed 许可：待 A1。
- 其余数字（解码 34–57 ms、RCD 量级、oracle 噪声底、gpui 帧率、dt 的 M1/M2）与 `VERIFY.md` 的更正一致，照用。
- **调研原文不回改**：本 lane 只允许写 `PLAN.md`/`PLAN-TABLES.md`/`plan-review.log`/`omp-plan-summary.md` 四个文件；§1.3 的修订以本计划为准，调研文件的下一轮更新另开 lane。

---

## §7 修订记录（自审 + 独立复审）

### §7.1 自审发现并已修正（本 lane 自己核出来的）

| # | 问题 | 证据 | 修法 |
|---|---|---|---|
| S1 | v50 的模块数写成 97/98 | `git show release-5.7.0:src/common/iop_order.c` 的 v50 表 = 94 行（93 具名 + 哨兵）；98 是 fork HEAD 计数 | T4/T5/T10/§0/§4/§6 全部改为 93（基线），并加「5.7.0 之后新增 4 个」的说明 |
| S2 | C/D 的模块划分含 4 个 5.7.0 没有的模块 | 逐名 diff：contrastntexture/demosaicscale/satcurvergb/spektrafilm 只在工作树 | C 50、D 20、clipping/useless 不实现、mask_manager 占位；基线外 5 个单列 |
| S3 | `spektrafilm` 被当成 5.7.0 模块 | `git show release-5.7.0:src/iop/spektrafilm.c` 不存在 | §1.3 与 C-2 写明「无官方 oracle」，验收降级；新增 R11 |
| S4 | B4（demosaic）的 oracle 会含 dt 默认启用的 highlights，而 highlights 排在 B7 | dt 的 RAW 默认启用链 | B3 扩为 raw 头段四件（含 highlights，6 lane），B7 收为两级 CA（4 lane）；lane 总数不变 |
| S5 | A4b 的验收依赖 A5 的 oracle（前向依赖） | A4b 卡片原第 5 条 | 改为「官方 cli 手工渲染一份 XMP（同 A5 配方，手工跑）」，A5 就绪后自动复跑 |
| S6 | T2 的 params 字节与 5.7.0 不符 | temperature v4/20B、highlights v4/48B、demosaic 48B、colorin 1044B（`git show release-5.7.0:...` 手算） | §1.3 与 T5 列为「已知不符」，夹具为唯一真值 |
| S7 | `v50` 与 `v50_jpg` 的差异只写了「优先级不同」 | 按行解析：93 名同集、24 个优先级不同（denoiseprofile 9.0→28.0、lens 13.0→28.0、finalscale 69.4→69.5 等） | T3 与 T5 给出 24 这个数与生成命令 |

### §7.2 独立复审

- 复审实例 1：`omp -p --auto-approve --thinking max`（2026-11-26 00:43 起，900 s 上限）。**未产出结论**：`plan-review.log` 仅 `Working...`，外层 `timeout` 记 `EXIT=124`，omp 自报 `[Stopped by SIGTERM]`。
- 复审实例 2：同参数、缩小读取面（≤3 个文件）、1200 s 上限，结果见 `plan-review.log` / 本 lane 末尾。
- 复审实例 3：同参数、只查结构四项（10 字段/ lane 加总/ 依赖/ 16 条裁决）、420 s 上限，结果并入 `plan-review.log`。
- 另有一个 `reviewer` 子代理并行做同一清单的只读复审（结果若在交付前返回，同样并入 `plan-review.log`）。

> 诚实标注：本 lane 的复审**未能全部按时完成**（实例 1 超时无输出）。已完成的复审结论与逐条处置见下；未完成的项在交付说明里列为缺口，不用自审冒充独立复审。

### §7.3 独立复审结论与逐条处置

结论头（实例 2，`PASS / 6 error + 12 minor`）与全文见 `plan-review.log`。

| 发现 | 事实 | 处置 |
|---|---|---|
| E1 | T5 的 jpg 列 5 处错（lens 13.0→28.0、cacorrectrgb 13.5→28.0、exposure 21.0→28.0、crop 24.5→28.0、finalscale 69.4→69.5） | 已逐行改；表头「已复核」现在成立（生成命令在 T3/T5） |
| E2 | 28.5 组是 6 个模块（不含 contrastntexture，后者是 master-only） | §1.2 第 8 条与 T5 改为 6，并列出六个名字 |
| E3 | 墙钟 26/114/140/168 h 与卡片 2–3 h/lane 不符 | 改为 43.5 / 208 / 251.5 h（×1.2 = 302 h ≈ 38 个 8h 日）；T8 的校准口径同步改 |
| E4 | A2 写 16 个 crate（实列 19，含新增 `dt-registry`）；`dt-cli` 无建波；A3 的 crate 名不一致 | A2 改 19 并明确 `dt-cli` 等空壳一起建；`dt-registry` 写进 T2；所有 `-p dt-iop-order` 改 `-p dt-registry` |
| E5 | 第 14 条（Swift 冻结）无实落点 | §2.8 新增「旧 Swift 树冻结」段：不读 `.lra`/`.lalb`/UserDefaults/MCP 契约，验收只对 dt |
| E6 | A3 验收写「97 条逐位」 | 改 93（与 T5 夹具一致） |
| m1 | i18n 门无产出波次 | A2 产出加 `xtask check-i18n` 骨架；B17 验收第 ⑥ 条强制 |
| m2 | B16 输入引用旧的「M2-9 尺寸规则」 | 改为 dt 5.7.0 的 `max_width/max_height` 与 `src/libs/export.c` |
| m3 | 裸 issue 号 | §1.1 开头声明均为 GitHub `kamasylvia/Lightamer` 的 issue |
| m4 | `darktable-config/accels` 不可解析 | 改为 `data/darktableconfig.xml.in` 的 `accels` 键 + `src/gui/accelerators.c` |
| m5 | 「同目录 gpui-spike/」路径错 | 文件头改为「上一级 `.work/gsd/phases/`，与本目录平级」 |
| m6 | 「T3 的计时」与 PLAN-TABLES 的 T3（描述字段）同名冲突 | 改为 `CORE-DESIGN-TABLES.md` 的 T3 并注明同名不同物 |
| m7 | 误称 A4b 已读 `colorspaces.c` | 改为「B5 会逐行读」 |
| m8/m9 | A4a 测试 3 依赖 A5（前向） | 改为「官方 dt 手工重写一次（只读挂载 + `--configdir`）」，A5 就绪后产品化 |
| m10 | 调研原文未回改；§0「两处冲突」漏计 S6/S12、DB 互通、XMP 库、crate 名 | 本 lane 不许改调研文件；§0 改为「不止两处，全表见 §1.3」并补 S6/S12 与 `dt-blend` 命名；DB/XMP 库本就在 §1.2 与 A4a |
| m11 | `CORE-DESIGN` 的 P0 52 lane 与本计划 B 76 lane 未对账 | T8 加一段对账：差额 24 = UI 15 + 历史 6 + 蒙版上调 3 |
| m12 | 30–37/40 无落点；A7b 36 fps 与 B18 60 fps 口径不一 | §5.2 加 gpui 最小程序 30–37/40 的下限参考；A7b 改 ≥450 帧/11 s；B18 改 ≥45 fps 并注明「60 fps 只证 UI 层」 |

**复审未覆盖的部分（诚实标注）**：实例 2 未逐条比对 `FEATURE-SCOPE` 的行数与依赖面，也未验证 C 期 50 个模块的划分合理性（只核了 5.7.0 名集与 P0 21）。C/D 的划分是设计取舍，不是可机检事实。
