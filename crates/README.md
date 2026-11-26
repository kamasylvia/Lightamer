# crates/ — Rust 工作区 crate 地图（A3 已填发现层）

> 规格正本：`.work/gsd/phases/rust-core/PLAN.md`（§2 架构基线、§3 逐波计划）
> 与 `PLAN-TABLES.md` T2（布局与预算）。本文件只是一张索引，不复述规格。

| crate | 用途（一行） | 首填波次 |
|---|---|---|
| `dt-api` | 命令/查询/事件 + CoreHandle，UI 唯一入口 | A7a |
| `dt-app` | 装配：按 target 与能力表选腿 | A7a |
| `dt-apple` | 仅 macOS：CIRAW/ColorSync/Vision/ImageIO/Metal（门控 A6 做，本波是普通空 crate） | A6 |
| `dt-blend` | 蒙版栅格化 + 混合 | B14 |
| `dt-cli` | 命令行 + oracle 对照工具 + perf 探针 | A4b（`history dump`）/ A5（`cmp`） |
| `dt-color` | lcms2 腿 + 矩阵数学 | B3（temperature 首用） |
| `dt-core` | Frame/Roi/tiling/缓存/调度/PipeError | B1 |
| `dt-decode` | rawspeed C ABI shim + 栅格解码 | B2 |
| `dt-export` | 编码器与导出队列 | B16 |
| `dt-history` | XMP 读写 + 参数布局 + 迁移 + 历史栈 | A4b |
| `dt-iop-traits` | ModuleDesc/OrderKeys/ModuleGroup/ParamsDesc（自有设置模型）/ModuleFlags/ColorSpace/Control/HistoryKeys | A3 已填 |
| `dt-registry` | 描述聚合 + 按标识查找 + raw/jpg 默认顺序链（`(prio,tie)` 排序）；夹具 `dt-registry/fixtures/dt-order-*.json` | A3 已填 |
| `dt-iop-raw` | raw 段模块桩 8 个（rawprepare/demosaic/…；`build.rs` 扫 `src/modules/*/mod.rs` 自动发现） | A3 桩 / B3 起填像素 |
| `dt-iop-geom` | 几何模块桩 21 个（lens/crop/…） | A3 桩 / B7 起填像素 |
| `dt-iop-color` | 颜色模块桩 22 个（temperature/colorin/colorout/…） | A3 桩 / B3 起填像素 |
| `dt-iop-display` | 显示段模块桩 46 个（exposure/曲线/finalscale/gamma/…） | A3 桩 / B3 起填像素（highlights 首用） |
| `dt-library` | SQLite 图库 + 导入 + 缩略图 | B13 |
| `dt-lightamer` | 独有功能：全景/焦点/HDR 合成、节点 DRT、版本分支、AI | C 期 |
| `dt-gpui` | 界面（gpui 族）——**本波不建，A7b 建** | A7b |
| `xtask` | 仓库维护任务：`check-i18n`（骨架，B17 启用）；`gen-iop-stubs`（解析上游 `iop_order.c` 生成夹具+桩）/`check-order-sync`（上游×夹具×桩三方比对）/`check-no-iop-names`（核心零 op 名机检） | A2 骨架 / A3 三子命令 / B17 |

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
