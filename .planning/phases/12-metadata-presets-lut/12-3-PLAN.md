---
phase: 12
plan: "12-3"
title: "XMP 同步面：XMPWriter 薄封装（CGImageMetadataCreateXMPData 序列化端探针已过，F1——百行级，原「手写 XML 模板」分支作废）+ per-format 容器注入缝（JPEG APP1/PNG iTXt 低风险先行 + TIFF tag 700 唯一中风险裁定位）+ ExportEncoder 后置挂载六格式矩阵（HEIC/AVIF/WebP 反向锚）+ 第三方 .xmp 只读导入"
wave: 2
depends_on: ["12-1"]
autonomous: true
requirements: [META-04, META-03]
files_modified:
  - LightamerCore/Sources/Export/XMPWriter.swift                   # 新建：fields → Data 薄封装（Bag 构造纪律 + namespace 注册 + 空 fields nil）
  - LightamerCore/Sources/Export/XMPContainerInjector.swift        # 新建：JPEG APP1 / PNG iTXt / TIFF tag 700 注入 + 64KB 上限 typed 保护
  - LightamerCore/Sources/Export/ExportChainBuilder.swift          # 编码后注入缝挂载（ExportEncoder 产物 Data → XMP → 落盘）
  - LightamerCore/Sources/Session/XMPImport.swift                  # 新建：第三方 .xmp 只读解析（rating/label/keywords → sidecar 字段面）
  - App/Sources/Lightamer/UI/ContentView.swift                     # 「导入 XMP…」菜单入口 + 对话框宿主
  - Tests/LightamerTests/XMPWriterTests.swift                      # 新建：golden 字节 + round-trip 双向
  - Tests/LightamerTests/XMPContainerInjectorTests.swift           # 新建：三格式正锚 + 三格式反向锚 + 上限保护
  - Tests/LightamerTests/XMPExportMatrixTests.swift                # 新建：六格式×XMP 矩阵（经 ExportChainBuilder）
  - Tests/LightamerTests/XMPImportTests.swift                      # 新建：lr:hierarchicalSubject/仅 dc:subject 降级/round-trip
  - .planning/phases/12-metadata-presets-lut/12-3-SUMMARY.md
  - .planning/phases/12-metadata-presets-lut/12-3-DECISIONS.md
  - TODO.md                                                        # 12-3 勾选
  - LESSONS.md                                                     # 如踩坑
---

# Plan 12-3 — XMP 同步面（W2，与 12-2 并行，零交集；依赖 12-1 字段面）

> 背景：META-04 = 红线语义澄清后的「自建写入路径 + 只读导入」（D-12-CONTEXT-2/10）。
> **形态修正（F1/F2，按 RESEARCH 为准）**：`CGImageMetadataCreateXMPData` 本机实测可用
> （831 字节合法 packet + round-trip 全对）——XMPWriter = ImageIO **薄封装**（约百行级），
> CONTEXT D-2 案 A 的「优先验证」分支成立、「手写 XMP writer」分支死、CONTEXT specifics
> 「不可用则自写 XML 模板（+1 天）」预案作废；11-02 D3 宿主事实**修正表述**：死的是
> 「ImageIO 写端（properties dict → 文件字节）」，**序列化端活着**。实现重心全部落在
> per-format 容器注入缝 + golden。兜底矩阵（D-12-CONTEXT-10）：JPEG/TIFF/PNG 内嵌；
> HEIF/HEIC、AVIF、WebP = 文档化例外（反向锚防宿主漂移）；原片旁 `.xmp` 附件永不读写删
> （Phase 9 红线不动）。**TIFF tag 700 = 唯一中风险**（IFD 重排）——JPEG/PNG 已保 SC#1
> 底线，TIFF 超预算 = 文档化降级不阻塞（风险预案写死在 T3）。

## read_first

1. `.planning/phases/12-metadata-presets-lut/12-RESEARCH.md` §1（序列化探针 + API 面表——**不存在的 API 清单以本表为准**）、§7 T1、§8.2（12-3 验收草案 + 注入复杂度排序）、§8.3 风险表
2. `.planning/phases/12-metadata-presets-lut/12-CONTEXT.md` D-12-CONTEXT-2（案 A 裁决 + reject=-1 惯例）、D-10（兜底矩阵）、Phase Boundary「Phase 12 不做」节（原片旁 .xmp 永不）
3. `.planning/phases/11-export-pipeline/11-DISCUSSION-LOG.md` 移交清单第 3/5 条（XMP rating/flag API 位 + EXIF properties dict 汇合点）+ `11-02-DECISIONS.md` D3（写端五途径字节级验证——硬事实底座）
4. `LightamerCore/Sources/Export/ExportChainBuilder.swift` + `ExportEncoder.swift` + `ImageIOEncoders.swift`（注入缝挂点：编码产物 Data → 注入 → 落盘的现有链序）
5. `LightamerCore/Sources/Sidecar/LightamerSidecar.swift`（12-1 后的五字段面——XMPWriter 字段源；reject=-1 映射）
6. `LightamerCore/Sources/Session/MetadataService.swift`（导入写入的唯一入口——只读导入经它落 sidecar）
7. SDK header `CGImageMetadata.h`（`CGImageMetadataCreateXMPData` :616 / `CGImageMetadataRegisterNamespaceForPrefix` / `CGImageMetadataTagCreate` type `.arrayUnordered`=Bag）
8. `LESSONS.md` L019b（test-direct）/L020（内容级断言）/L013（无哈希字段）
9. `AGENTS.md`（Phase 执行模型 + 暂停机制）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 本任务申报文件）；`caffeinate -dis` 包裹一切构建；单测 = `Scripts/test-direct.sh '<Class>'`（**判据 = Executed 行 + failures 行，非宿主退出态**；Executed 0 = 失败防空转假绿）。
- **每任务边界检查 `.work/config.toml [gsd]` 开关（`auto`/`paused`）**——commit 后、下一任务前：`paused=true` 全链路停；`auto=false` 完成当前任务后停等「继续」。
- **不 push**；零新 SPM 依赖（XMP 序列化/注入全自建——继承定案）；无 /tmp 产物入工作区；fixture 禁 UNITEK 盘（L009）。
- **红线（零例外）**：原片同目录 `.xmp` 附件永不读写删；本 plan 一切写入只针对**导出产物**与**用户显式导入**路径。
- **T5 对话框为 GUI 任务：需解锁控制台（Manual-Only 候补）**。
- **TIFF 风险预案（写死）**：T3 若超执行预算（以 golden 断言全绿为完成判据）→ TIFF 降级为文档化例外（例外集 +1 入 DECISIONS + 12-VALIDATION 注记），**不阻塞收口**；JPEG/PNG 已保 SC#1「三格式内嵌」底线。
- RESEARCH 未覆盖细节（label 色名映射表拼写/APP1 段对齐/TIFF byte-vs-ASCII 类型选择）标注**执行期决策**入 `12-3-DECISIONS.md`。

## Tasks

### T1 XMPWriter 薄封装（fields → Data，golden 双向）

- **action**
  1. `XMPWriter.swift`（新建，Core/Export）：`write(fields:) -> Data?`——字段面（RESEARCH §1.4 verbatim）：`rating: Int?`（0-5；reject = **-1** 惯例映射由调用方传入）、`label: String?`（colorLabel Int → 色名映射表，拼写执行期决策 golden 锁）、`hierarchicalSubject: [String]`（`|` path 全量）、`subject: [String]`（叶子扁平去重）。全空字段 → 返回 **nil**（合法：无字段不产 packet——探针实测行为，注入方跳过）。
  2. API 纪律（F2 两条，探针实测钉死）：自定义 `lr` namespace 必须先 `CGImageMetadataRegisterNamespaceForPrefix` 再 SetTagWithPath（不注册 set 返回 false）；`dc:subject` 数组必须 `CGImageMetadataTagCreate` + `.arrayUnordered` 才得 rdf:**Bag**——**直塞 CFArray 产 Seq，禁止**。
  3. golden 双向：输出字节 golden fixture（rating/label/双 keywords 字段共存 packet）+ `CGImageMetadataCreateFromXMPData` round-trip 值断言（全字段逐一）。
- **证据**：`XMPWriterTests`——字节 golden（锁 x:xmpmeta/rdf:RDF/Bag 结构与键序）+ round-trip 全对 + 全空 nil + Bag-vs-Seq 反例断言（直塞 CFArray 的错误形态注释钉死）。

### T2 容器注入缝：JPEG APP1 + PNG iTXt（append 级，低风险先行）

- **action**
  1. `XMPContainerInjector.swift`（新建，Core/Export）：`inject(xmp:into:format:) -> Data`（typed throw）。
  2. JPEG APP1：SOI 后追加 `FFE1` 段 = 长度(u16 BE) + `"http://ns.adobe.com/xap/1.0\0"` 段头 + packet 逐字节；packet + 段头超 64KB 段上限 → **typed 错误降级不注入**（RESEARCH 风险表「超长 keywords」保护——不做多段扩展，文档化）。
  3. PNG iTXt：keyword `"XML:com.adobe.xmp"` chunk，IEND 前插入，CRC 重算；现有 chunk 集不动。
  4. 正锚 golden：JPEG（marker `FFE1` + 段头 + packet 逐字节）与 PNG（chunk 结构 + keyword + CRC 校验）字节断言；注入后文件经 `CGImageSource` 重读元数据值断言（宿主可解析性）。
- **证据**：`XMPContainerInjectorTests`（JPEG/PNG 段）——正锚字节 golden + CGImageSource 重读 round-trip + 64KB 上限 typed 错误 + 非 JPEG/PNG 输入误用 typed 错误。

### T3 TIFF tag 700 注入（唯一中风险，裁定位）

- **action**
  1. TIFF XMP = tag 700（BYTE 数组）注入：IFD 重组（新 tag 排序插入 + 后续数据区 offset 平移 + 下一 IFD 链保持）——**完成后判据 = T2 同款正锚字节 golden + CGImageSource/TIFF 反序列化重读值断言**。
  2. **风险预案（编排纪律钉死）**： golden 断言无法全绿或工时超执行预算 → **文档化降级**：TIFF 加入 XMP 例外集（`inject` 对 tiff 返回 typed「不支持」→ 导出继续零 XMP），例外集 +1 入 DECISIONS + 12-VALIDATION 注记，**不阻塞 12-5 收口**（SC#1 底线已由 T2 JPEG/PNG 保住）。
- **证据**：`XMPContainerInjectorTests`（TIFF 段）——tag 700 存在 + 值匹配 + 既有 tag 值逐字节不变 + IFD 链完好；若走降级：DECISIONS 记录降级原因与证据。

### T4 ExportEncoder 后置挂载 + 六格式矩阵

- **action**
  1. `ExportChainBuilder.swift` 挂载：编码产物 Data → `inject` → 落盘（导出图脱离会话真身链——D-2 裁决理由面）；XMP fields 从导出源的 sidecar 五字段投影（rating/label/keywords 全量；**reject → `xmp:Rating = -1`**；**pick 无 XMP 正位，仅 sidecar/DB 本地维度——文档化**）。
  2. 六格式矩阵测试（经 ExportChainBuilder 真链）：JPEG/TIFF/PNG 产物含 `x:xmpmeta`（或 `XML:com.adobe.xmp`）正向锚 + 值 round-trip；**HEIC/AVIF/WebP 产物 byte-scan 无 `x:xmpmeta`/`XML:com.adobe.xmp` 反向锚**（11-02 同款防宿主漂移——宿主行为变化即红）。
  3. EXIF properties dict 既有路不动（11 移交⑤：五格式全通照旧）；XMP 注入失败（typed 错误）= 导出继续 + 产物无 XMP + 失败计数（导出不因 XMP 硬失败）。
- **证据**：`XMPExportMatrixTests`——六格式矩阵全绿（三正锚 + 三反锚）+ reject=-1 映射断言 + 注入失败降级不阻塞导出。

### T5 第三方 .xmp 只读导入（Core 解析 + GUI 对话框，需解锁控制台（Manual-Only 候补））

- **action**
  1. `XMPImport.swift`（新建，Core/Session）：`CGImageMetadataCreateFromXMPData`（+ 文件直读路径）→ rating/label（色名反查映射表）/`lr:hierarchicalSubject` Bag → path 数组直存；**仅 `dc:subject` 的第三方文件 → 叶子升单级 path 直存（无祖先信息，诚实降级）**（RESEARCH §3.3）。
  2. 写入唯一入口 = `MetadataService`（12-1 依赖面）：导入 = 用户显式动作（`ContentView.swift`「导入 XMP…」菜单 → NSOpenPanel 选 `.xmp` → 目标 = 当前选中图）；解析失败/字段空 = typed 错误 + 用户可见提示；**不触碰原 `.xmp` 文件（只读）**。
  3. zh catalog 同批（L025）。
- **证据**：`XMPImportTests`——lr:hierarchicalSubject 全量/仅 dc:subject 降级/round-trip 值断言/坏文件 typed 错误；GUI 走查记录（导入对话框 → 选中图 sidecar 字段更新 → grid overlay 即时可见）；Manual-Only 未尽项登记。

### T6 全量回归 + SUMMARY + DECISIONS

- **action**：全 suite 终轮（基线 **1260/6skip/0fail** + 本 plan 新增，0 fail）；TODO.md 12-3 勾选；`12-3-SUMMARY.md` + `12-3-DECISIONS.md`（label 映射表拼写/APP1 长度口径/TIFF 裁定结果[注入或降级]/空 fields nil 语义）；新教训候选评估入 LESSONS。
- **证据**：测试计数（0 fail）；SUMMARY + DECISIONS 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| XMPWriter | 字节 golden + round-trip 双向 + Bag 纪律 | `Scripts/test-direct.sh 'XMPWriterTests'` |
| 注入缝 | JPEG/PNG 正锚 + 上限保护（+TIFF 正锚或文档化降级） | `Scripts/test-direct.sh 'XMPContainerInjectorTests'` |
| 导出矩阵 | 六格式三正锚 + 三反锚 + reject=-1 | `Scripts/test-direct.sh 'XMPExportMatrixTests'` |
| 只读导入 | 层级/降级/坏文件向量 + GUI 走查 | `Scripts/test-direct.sh 'XMPImportTests'` + 走查记录 |
| 回归 | 全 suite 0 fail（基线 1260+新增） | `Scripts/test-direct.sh`（全套） |

## 验收标准（Acceptance）

- [ ] XMPWriter 薄封装（F1 形态）：四字段面 + Bag 构造纪律（`.arrayUnordered`，CFArray 直塞禁止）+ lr namespace 注册前置 + 全空 nil；字节 golden + round-trip 双向全绿
- [ ] 注入缝：JPEG APP1/PNG iTXt 正锚字节 golden + 64KB 上限 typed 降级；TIFF tag 700 正锚全绿**或**文档化降级（例外集 +1 入 DECISIONS + VALIDATION 注记）——二选一落账，零静默
- [ ] 六格式矩阵：JPEG/TIFF/PNG 正锚 + HEIC/AVIF/WebP byte-scan 反锚（防宿主漂移）；reject → Rating -1；pick 无正位文档化；XMP 失败不阻塞导出
- [ ] 只读导入：lr:hierarchicalSubject 全量 / 仅 dc:subject 升单级诚实降级；写入经 `MetadataService` 唯一入口；原 `.xmp` 只读零触碰；GUI 对话框走查（Manual-Only 未尽项登记）
- [ ] 红线零触碰：原片旁 `.xmp` 永不读写删（无任何写路径存在）
- [ ] 全 suite 0 fail；每任务独立提交 + 边界查 config 开关；不 push；无 /tmp 产物入工作区；SUMMARY + DECISIONS 落盘
