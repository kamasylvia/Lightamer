# omp-core-summary — Lightamer 非 UI 核心盘点（lane 交付摘要）

> 时间：2026-11-25。范围：`LightamerCore/Sources` + `LightamerIOP/Sources` + `App/Sources/Lightamer/{AI,Export,Library,MCP,Session,State,Yiyin}` + `Tests/`。只读；产品树零改动；零 commit/push；未构建、未跑测试、未开 GUI；未读用户照片库。
> 正本：`CORE-INVENTORY.md`（§0–§7）、`CORE-INVENTORY-TABLES.md`（§A–§K）、`core-review.log`（独立 omp 复审）。

## 交付物

| 文件 | 内容 |
|---|---|
| `CORE-INVENTORY.md` | 一页纸 + 六问正文 + 未查到 |
| `CORE-INVENTORY-TABLES.md` | Core/IOP 目录表、Apple 依赖逐文件表、73 shader 表、UserDefaults、MCP 34 工具、.lalb 表、测试明细、逐模块难度表、复现命令 |
| `core-review.log` | 独立 `omp -p --auto-approve --thinking max` 复审输出 |
| `omp-core-summary.md` | 本文件 |

## 关键数字

| 项 | 数 | 口径 |
|---|---:|---|
| Swift 总量 | 156,048 行 / 431 文件 | `wc -l`；Core 80,887/232、IOP 36,719/105、App 非 UI 38,442/94 |
| Metal | 73 文件 / 13,317 行 / 186 kernels | `find` + `grep 'kernel void'` |
| 纯逻辑 | 59,720 行 / 197 文件 | 文件级主导依赖启发式 |
| 着色器宿主 | 43,225 行 / 118 文件 | 含 105 IOP Swift；MSL 13.3k 行原样保留 |
| Apple 适配 | 31,221 行 / 66 文件 | CI/ImageIO/Vision/CoreML/CoreText/CGColorSpace |
| UI 耦合 | 21,884 行 / 50 文件 | SwiftUI/AppKit 视图 + `@Observable`，需拆 |
| 测试 | 530 文件 / 4,623 方法 | 7 单测 target + 3 未映射；UI suite 另 1 文件/3 方法 |
| 可直接对照 | 400 文件 / 3,455 方法 | 非 APP target、无 SwiftUI/AppKit；非 Metal 233/2,121 |
| Golden/Parity | 61 文件 / 429 方法 | 60 测试文件 + `ParityGate` helper |
| 范围外邻近 | +2,124 行 / 8 文件 | Catalog 1,229、Settings 非 UI 818、Root 扩展 77；纳入后 439/158,174 |

## 六问速答

1. **模块地图**：Core 16 目录（AI/Catalog/ColorMatch/Decode/Export/Film/Foundation/Graph/Layers/Library/Metal/Pipe/Presets/Session/Sidecar/Stack），IOP 54 目录 / 56 opName，App 非 UI 7 目录。`State/` 非 UI 绑定 1,604 行（7 文件）；`@Observable` 状态 9,352 行（17 文件），`PipeCoordinator` 3,293 行最大。
2. **Apple 依赖**：RAW `CIRAWFilter` 5/18；`CIContext` 21/64、`CIImage` 13/84；`CGColorSpace` 40/221、`CGColorConversion` 2/10（ColorSync C API 0）；Vision 4/28（7 import）；ImageIO 读 18/95、写 17/71；Metal 102/1,485；CoreML 3/28（7 import）；CoreText 4/38；UTType 9/13；SQLite 6/117；`CVPixelBuffer` 45/3；FileProvider 0。候选边界：RawDecoder / RasterDecoder / ColorEngine / VisionService / MlEngine / Encoder / GpuDevice / MetadataIo / TextRasterizer / Sqlite。
3. **着色器**：73 文件逐行/kernel/宿主见 TABLES §E；约定 = texture 0/1、.rgba32Float 工作、.bgra8Unorm 显示、.rgba16Float EDR、默认 8×8 纹理/16×16 buffer、64×1 归约、uniform 16 字节 stride + `piece.data`、4 文件函数常量；原子 5 文件、texture3d 2、texture1d 1、uint 1、sample 2、实际 read_write 1（literal 提及 11）。
4. **必须不变**：`.lra` v13 / 22 顶层键；`.lalb` user_version 6 / 13 实体表 + 2 FTS5 + 6 触发器；FNV-1a 64 + decimal string + sortedKeys params；37 UserDefaults 键 + 2 前缀（7 目录范围）；MCP 34 工具 / 14 需控制权；导出 6 元数据开关 + ICC/DRT 输出约定。逐项正本见 TABLES §F–§H。
5. **测试**：IOPP 84/587、IOP 100/843、LAYERS 67/576、LIB 83/802、SESS 26/289、EXPORT 40/391、APP 127/1,135；UI 1/3。IOP/Layers/Library/Session/Export 可直接作 Rust 对照；APP 多数不能；具体排除见 TABLES §I.4。
6. **难度**：纯 59,720 / 着色器宿主 43,225 / Apple 适配 31,221 / UI 21,884。逐模块主导档与混合行数见 TABLES §J。估 ±10–15%；着色器宿主主要成本是 PSO/纹理/uniform 绑定，Apple 适配主要成本是行为对齐。

## 复审与修订

- 复审实例：独立 `omp -p --auto-approve --thinking max`，只读，重跑数字 + 抽查 10 个 shader / 5 个依赖文件 / 契约 / §0 行数。
- 结论：`FAIL / 2 error + 8 minor`（原始输出见 `core-review.log`）。
- 修订：2 error + 8 minor 已全部回注（MCP 13→14；App 范围 addendum；IOP 测试归属 84/587、100/843；530 文件列和；read_write 口径；CoreML 口径；§K 排除 `.work`；UserDefaults 邻近键；Parity 名单；Metal 词界口径）。逐条修订见 `CORE-INVENTORY.md` §8。
- 残余：复审未逐文件重跑四档、未逐列核 `.lalb` DDL、未逐字节核 34 MCP schema；本 lane 未做第二轮独立复审。

## 未完成 / 风险

- 未逐行审计 156k 行业务语义；职责来自文件头与公开类型。
- Q6 四档是文件级启发式；`MetalContext`/`PixelPipe`/`PipeCoordinator` 有跨档成分。
- Q2 “处”是正则符号命中，不是运行期调用次数。
- Q3 线程组只统计 host 的字面 `MTLSize`；动态尺寸未逐 shader 还原。
- MCP 参数表只列主参数；逐字 JSON Schema 以 `McpFinalSnapshotTests.swift` 为正本。
- 未测性能/内存；未验证 Rust 侧可行性 spike（本 lane 只盘点）。
