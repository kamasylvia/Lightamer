# crates/ — Rust 工作区 crate 地图（A3R 已重排成分层布局）

> 规格正本：`.work/gsd/phases/rust-core/PLAN.md`（§2 架构基线、§3 逐波计划）
> 与 `PLAN-TABLES.md` T2（布局与预算）；分层正本：`FRAMEWORK.md` §1 与
> `FRAMEWORK-TABLES.md` T-F9。本文件只是一张索引，不复述规格。
> 依赖方向由 `cargo xtask layers` 强制（`crates/xtask/src/layers.rs`）：
> 严格向下，同层只许走登记的链（L0 `[dt-geom, dt-color-math, dt-raster]`、
> L1 `[dt-meta, dt-decode]`、L2 `[dt-registry, dt-history, dt-pipeline]`），
> 界面 crate 只许在 L5，`dt-testkit` 只许作开发依赖。

28 个包（`apps/dt-cli` 另计在 `apps/`；`dt-gpui` 到 A7b 才建，检查表里已登记）：

| 层 | crate | 用途（一行） | 首填波次 |
|---|---|---|---|
| L0 | `dt-geom` | 几何原语：roi、矩阵、裁剪适配 | B1 |
| L0 | `dt-raster` | 管线共用的 float 像素缓冲 | B1 |
| L0 | `dt-color-math` | 颜色矩阵数学与曲线 helper，无 profile 状态 | B3 |
| L0 | `dt-iop-traits` | ModuleDesc/OrderKeys/ModuleGroup/ParamsDesc（自有设置模型）/ModuleFlags/ColorSpace/Control/HistoryKeys | A3 已填 |
| L0 | `dt-sysmem` | 内存压力钩子：把空闲页还给 OS | A7a |
| L1 | `dt-iop-raw` | raw 段模块桩 8 个（rawprepare/demosaic/…；`build.rs` 扫 `src/modules/*/mod.rs` 自动发现） | A3 桩 / B3 起填像素 |
| L1 | `dt-iop-geom` | 几何模块桩 21 个（lens/crop/…） | A3 桩 / B7 起填像素 |
| L1 | `dt-iop-color` | 颜色模块桩 22 个（temperature/colorin/colorout/…） | A3 桩 / B3 起填像素 |
| L1 | `dt-iop-display` | 显示段模块桩 46 个（exposure/曲线/finalscale/gamma/…） | A3 桩 / B3 起填像素（highlights 首用） |
| L1 | `dt-meta` | 内嵌元数据解码与 sidecar helper | B2 |
| L1 | `dt-color` | lcms2 腿 + 矩阵数学 | B3（temperature 首用） |
| L1 | `dt-blend` | 蒙版栅格化 + 混合 | B14 |
| L1 | `dt-decode` | rawspeed C ABI shim + 栅格解码 | B2 |
| L1 | `dt-scenes` | 成像测试共用的确定性测试场景 | A5 |
| L2 | `dt-registry` | 描述聚合 + 按标识查找 + raw/jpg 默认顺序链（`(prio,tie)` 排序）；夹具 `dt-registry/fixtures/dt-order-*.json` | A3 已填 |
| L2 | `dt-history` | 自有历史模型：历史栈 + 处理版本号 + 参数布局 | A4b |
| L2 | `dt-pipeline` | Frame/Roi/tiling/缓存/调度/PipeError（A3R 由 `dt-core` 改名） | B1 |
| L3 | `dt-catalog` | 会话库 + 导入 + 缩略图（A3R 由 `dt-library` 改名） | B12′ |
| L3 | `dt-preview` | 预览缓存：内存 LRU + 磁盘缩略图 + 预取 | B15 |
| L3 | `dt-apple` | 仅 macOS：CIRAW/ColorSync/Vision/ImageIO/Metal（门控 A6 做，本波是普通空 crate） | A6 |
| L3 | `dt-gpu` | CPU 管线的 GPU 孪生，C 期占位 | C 期 |
| L3 | `dt-merge` | 独有合成（全景/焦点/HDR），C 期占位 | C 期 |
| L3 | `dt-lightamer` | 独有功能：全景/焦点/HDR 合成、节点 DRT、版本分支、AI | C 期 |
| L4 | `dt-engine` | 会话命令、历史应用、作业、导出、导入（A3R 承接已退役的 `dt-api`/`dt-app`/`dt-export`） | A7a |
| L5 | `dt-mcp` | 基于引擎命令的 MCP 服务器，C 期占位 | C 期 |
| L5 | `dt-gpui` | 界面（gpui 族）——**本波不建，A7b 建，检查表已登记** | A7b |
| testkit | `dt-testkit` | 测试套件：skip 宏 + JSONL 记录，只许开发依赖 | A3R 已填 |
| exempt | `dt-cli` | 命令行 + oracle 对照工具 + perf 探针（A3R 挪到 `apps/dt-cli`） | A4b（`history dump`）/ A5（`cmp`） |
| exempt | `xtask` | 仓库维护任务：`check-i18n`（骨架，B17 启用）；`gen-iop-stubs`（解析上游 `iop_order.c` 生成夹具+桩）/`check-order-sync`（上游×夹具×桩三方比对）/`check-no-iop-names`（核心零 op 名机检）/`layers`（分层检查，A3R 加） | A2 骨架 / A3 三子命令 / A3R layers / B17 |

退役（A3R 删空壳，职责并进 `dt-engine`）：`dt-api`、`dt-app`、`dt-export`。

## A3：模块发现与分域规则

基线 = darktable 上游 `master` 提交 `679d594f5d`（`v50_order` + `v50_jpg_order`），
具名模块 97 个（哨兵不计）。`cargo run -p xtask -- gen-iop-stubs` 从上游
`src/common/iop_order.c` 解析两张表，生成夹具与全部桩；分域规则（按序，
`crates/xtask/src/gen_stubs.rs` 的 `assign`）：

1. T2 点过名的冻结指派（raw 7 / geom 9 / color 10 / display 9，共 35 个）；
2. raw 优先级 `< 9.0` 的进 raw（raw 管线头部）；
3. `operation_tags()` 含 `DECORATION` 的进 display；
4. tags 含 `DISTORT`/`CROPPING`/`GEOMETRY` 的进 geom；
5. `default_group()` 主标签：`COLOR`→color，`TONE`/`EFFECT`→display，
   `CORRECT`→geom，`BASIC`→display，纯 `EFFECTS`→display；
6. 无源码/无分组信息的回落 display（基线里 2 个：`mask_manager` 无分组函数，
   `colorreconstruct` 的源文件名是 `colorreconstruction.c`；结论与规则一致）。

分错的以后挪一个目录就行，发现机制不在乎目录位置。
当前分布：raw=8 geom=21 color=22 display=46（`gen-iop-stubs` 打印为准）。

纪律（PLAN §3.0）：不改封存面；新增依赖先过 A1（本波零依赖）；
核心代码零 dt op 名（机检在 A3 落）。
