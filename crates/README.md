# crates/ — Rust 工作区 crate 地图（A3R 已重排成分层布局）

> 规格正本：`.work/gsd/phases/rust-core/PLAN.md`（§2 架构基线、§3 逐波计划）
> 与 `PLAN-TABLES.md` T2（布局与预算）；分层正本：`FRAMEWORK.md` §1 与
> `FRAMEWORK-TABLES.md` T-F9。本文件只是一张索引，不复述规格。
> 依赖方向由 `cargo xtask layers` 强制（`crates/xtask/src/layers.rs`）：
> 严格向下，同层只许走登记的链（L0 `[dt-geom, dt-color-math, dt-raster]`、
> L1 `[dt-meta, dt-decode]`、L2 `[dt-registry, dt-history, dt-pipeline]`），
> 界面 crate 只许在 L5，`dt-testkit` 只许作开发依赖。

29 个包（`apps/dt-cli` 另计在 `apps/`；`dt-gpui` A7b 已建）：

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
| L2 | `dt-history` | 照片设置（宽容 serde + 规范 JSON + FNV 缓存键）+ 快照历史栈 + 处理版本号（`HISTORY_LIMIT` 200） | A4b 已填 |
| L2 | `dt-pipeline` | Frame/Roi/tiling/缓存/调度/PipeError（A3R 由 `dt-core` 改名） | B1 |
| L3 | `dt-catalog` | 会话库 + 导入 + 缩略图（A3R 由 `dt-library` 改名） | B12′ |
| L3 | `dt-preview` | 预览缓存：内存 LRU + 磁盘缩略图 + 预取 | B15 |
| L3 | `dt-apple` | Apple 边界：macOS 探针/空后端双实现 + 能力表（A6 已填；唯一可碰 Apple 绑定的 crate）+ 原生视口缝（A7b：一整数句柄 + 矩形/几何/输入纯数据类型，macOS 在 `macos.rs` 内实现，空后端报不支持） | A6 已填 / A7b 视口 |
| L3 | `dt-gpu` | CPU 管线的 GPU 孪生，C 期占位 | C 期 |
| L3 | `dt-merge` | 独有合成（全景/焦点/HDR），C 期占位 | C 期 |
| L3 | `dt-lightamer` | 独有功能：全景/焦点/HDR 合成、节点 DRT、版本分支、AI | C 期 |
| L4 | `dt-engine` | 命令分发口（A7a 已填：`execute` 唯一入口 + 13 条编辑/历史/作业命令 + 草稿会话 + 作业池 + 事件；会话/导出/导入命令 B12′ 起逐条加） | A7a 已填 |
| L5 | `dt-mcp` | 基于引擎命令的 MCP 服务器，C 期占位 | C 期 |
| L5 | `dt-gpui` | 界面（gpui-kit 0.11.0 + gpui-fast 特性）：原生视口画布 + 右侧滑杆面板；双输入路径（框架回调/原生子类）→ 自有 `ViewportInput` 纯数据；只走 `execute` 与快照（A7b 已填） | A7b 已填 |
| testkit | `dt-testkit` | 测试套件：skip 宏 + JSONL 记录，只许开发依赖 | A3R 已填 |
| exempt | `dt-cli` | 命令行 + oracle 对照工具（A5 已填：`fetch`/`render`/`cmp`/`emit-xmp`/`selftest`；A6 加 `capabilities` + `apple` 默认 feature 关断 Apple 链接；A7a 加 `commands`/`run`（JSONL 喂引擎草稿会话）；入口 `Scripts/oracle.sh`，钉点 `Scripts/oracle.lock`）+ perf 探针（A3R 挪到 `apps/dt-cli`） | A4b（`history dump`）/ A5 已填 / A6 已填 / A7a 已填 |
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
