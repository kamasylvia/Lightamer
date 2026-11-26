# crates/ — Rust 工作区 crate 地图（A2 骨架）

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
| `dt-iop-traits` | ModuleDesc/IopModule/Params/Piece/ModuleFlags/Cst | A3 |
| `dt-registry` | 顺序计算（raw/jpg 两链）+ 描述聚合 | A3 |
| `dt-iop-raw` | raw 段模块（rawprepare/hotpixels/demosaic/…） | B3 |
| `dt-iop-geom` | 几何模块（lens/cacorrect/ashift/flip/crop/…） | B7 |
| `dt-iop-color` | 颜色模块（temperature/colorin/colorout/…） | B3 |
| `dt-iop-display` | 显示段模块（exposure/曲线/finalscale/gamma/…） | B3（highlights 首用） |
| `dt-library` | SQLite 图库 + 导入 + 缩略图 | B13 |
| `dt-lightamer` | 独有功能：全景/焦点/HDR 合成、节点 DRT、版本分支、AI | C 期 |
| `dt-gpui` | 界面（gpui 族）——**本波不建，A7b 建** | A7b |
| `xtask` | 仓库维护任务：`check-i18n`（骨架，B17 启用） | A2 骨架 / B17 |

纪律（PLAN §3.0）：不改封存面；新增依赖先过 A1（本波零依赖）；
核心代码零 dt op 名（机检在 A3 落）。
