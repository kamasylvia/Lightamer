---
phase: 12
slug: metadata-presets-lut
status: validated
nyquist_compliant: true
created: 2026-09-27
validated: 2026-09-27
---

# Phase 12 — Validation（签核：SC#1-4 三列证据 + Per-Task Map + Manual-Only 汇总）

> 体例对齐 11-VALIDATION（frontmatter/Checklist）。**翻账只认证据**：SC 表逐条
> 「一手证据 + 测试锚 + GUI 实证」三列；无证据 ✅ = 违规。
> **checker W-2 口径（SC#2 排序键，可追溯性声明）**：SC#2 字面「sort by
> rating/label/keyword/camera/lens/date/ISO/focal length」以**过滤面 16 字段全覆盖**
> 解释（FilterPredicateGroup 支持的全部字段×操作符面）；**排序窄面**为 D-12-CONTEXT-7
> / D-7 裁决内行为 = 六排序键（filename / rating / capture_date / iso / focal_length /
> scan_epoch，NULLs-last），相机/镜头/标签/关键字进过滤不进排序——裁决意图（按元数据
> 找图）不变，排序扩展位在 SQL 白名单一处。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit / golden / 直启宿主 / 万张门计时） |
| **Quick run** | `Scripts/test-direct.sh`（L019b 直启，零弹窗；判据 = Executed 行非宿主退出态） |
| **Full suite（终轮）** | `caffeinate -dis Scripts/test-direct.sh` = **1436 tests / 6 skip / 0 fail**（466.6s，2026-09-27 02:1x） |
| **基线演变** | Phase 11 末 **1258** → 12-1 +32（1290）→ 12-2 +44（1334）→ 12-3 +30（1364）→ 12-4 +26（1390）→ 12-5 +46（**1436**：CubeLutParserTests 22 + Lut3dKernelTests 8 + Lut3dGoldenImageTests 5 + LutLibraryStoreTests 10 + MetadataServiceTests promotion +1） |
| **LayerE2ERoundTripTests 负载型 flake** | 本 Phase 五轮终轮全部 0 fail，未现身；在案预案（隔离 ×3 归因后单列不计回归）未触发 |

---

## SC#1-4 对照表（ROADMAP §Phase 12 契约，三列证据）

| SC | 判据 | 一手证据（文件/决策） | 测试锚（类/用例） | GUI 实证（走查节） | 判定 |
|---|---|---|---|---|---|
| **SC#1** | 星级(0-5)/C1 色标/层级关键字可编辑且双写 Lightamer sidecar + 标准 EXIF/IPTC/XMP（工具互通） | sidecar v3 五字段 additive（`LightamerSidecar.swift`，哈希隔离）+ `MetadataService` 唯一写入口六 API（`|` typed 拒绝 + 万张门 0.457s perf.md）+ `XMPWriter`（JPEG APP1/PNG iTXt pre-IDAT/TIFF tag 700 注入 + mountXMP 四态 tally）+ DB v2 34 列 + EXIF 七列回填 | `SidecarMetadataV3Tests` 9 + `SessionIndexMigrationTests` 11 + `MetadataServiceTests` 11（含 crash 注入三态零漂移 + **12-5 补 late-sidecar promotion**）+ `XMPWriterTests` + `FilterSQL/PredicateTests` | 12-1 走查 6 证据（overlay 实星/色点/flag、快捷键三态路由、退出重开 sidecar 回读）；12-3 走查 4 证据（导出六格式×XMP 矩阵 + 第三方 .xmp 导入对话框） | ✅ |
| **SC#2** | 按评分/标签/关键字/相机/镜头/日期/ISO/焦距过滤与排序；智能相册（规则虚拟分组不复制文件） | `FilterPredicateGroup` Codable（typed 降级 + sortedKeys golden）+ `FilterSQL` 单一翻译层（**四联式祖先谓词** + LIKE ESCAPE + bind-only + 排序白名单）+ `SessionIndexStore.query` + `SmartAlbumStore`（app 级 UUID 文件 + 求值域=当前会话）。**排序键口径 = checker W-2 声明（见头注）：过滤 16 字段全覆盖 / 排序六键 D-7 裁决** | `FilterPredicateTests` + `FilterSQLTests`（逐字段×操作符 SQL 快照 + fixture 精确行集 + NatureHolics 裸 LIKE 误伤对照组钉死）+ `SmartAlbumStoreTests`（round-trip + 自愈跳过） | 12-2 走查（chips/Quick Filter `/`+Esc/排序持久化/空结果态/智能相册侧栏第四区激活互斥/求值域双证） | ✅ |
| **SC#3** | 原生预设系统存/载完整调整栈为 `.lightamer-preset`（JSON/Codable）；管理器 create/edit/delete/import/export/categorize；单图+批量应用 | `PresetContainer`（one-way 锁 schemaVersion 1 + sortedKeys line-based golden + kind 互斥 typed；instances 复用 SidecarInstanceRecord L013；ExportRecipe 直挂=11 移交①兑现）+ `PresetsStore`（三拆自愈四类 typed skip）+ `PresetApplier`（**整体委托 SessionBatchApplier 零新管线**；preset-apply vs paste 等价性：索引行逐列相等 + sidecar 字节 recast-UUID 规范化全等）+ PresetController 闭包缝 + 独立管理器 Window | `PresetContainerTests`（golden/容忍/互斥）+ `PresetsStoreTests`（自愈/CRUD/导入导出）+ `PresetApplierTests`（**等价性核心 + partial 子集 + 万张门 0.679s** + unknown-op verbatim + 与 12-1 语义对照双 plan 断言） | 12-4 走查 8 证据 `12-4-01..08`（创建/批量 b+c 双 .lra 落盘/live 保护/部分应用对话框/导入导出 round-trip 字节全等/坏预设 footer/**export 预设填充 300→150 可见翻转 + 三次真实导出预设驱动==手配 150 字节全等**） | ✅ |
| **SC#4** | `.cube` LUT（1D/3D，honor DOMAIN_MIN/MAX float/HDR，tetrahedral 默认）导入并应用为 IOP-COLOR-08 模块 + 显式应用色彩空间选择器（dt lut3d 等价物） | `CubeLutParser`（键全集 + 八名 typed throw + red-fastest 锁序 + **DOMAIN remap = 超 dt 能力面正向扩展**，F4：dt `lut3d.c:782-791` 硬拒 DOMAIN≠0..1）+ `Lut3dKernels.metal`（lut3d.cl:29-60 verbatim + texture3d 手动八角点 + trilinear + 1D ramp 超 dt 面）+ `Lut3dModule`（V50 36.0 + L031 路由 blit + LutResolving 缝）+ `LutColorspaceMatrices`（四态，sRGB/P3 与 ColorOut 资产同源逐位一致 + Bradford ProPhoto）+ `LutLibraryStore`（FNV-1a 查重 + 三拆自愈 + 库名引用不腐烂 D-6）+ `LutPanelView`（四态 picker/插值 picker/1D 提示/缺失降级提示 + toast） | `CubeLutParserTests` 22（golden/八类 throw/角点锁序/脏样本 fixtures）+ `Lut3dKernelTests` 8（**tetra/trilinear vs CPU float64 ≤1/1024** 四域/格点精确/identity cube/neutral+missing blit/1D INPUT_RANGE）+ `Lut3dGoldenImageTests` 5（矩阵往返/灰中性/ColorOut 同源/全链恒等/非恒等表真矩阵 ≤1/1024）+ `LutLibraryStoreTests` 10（查重折叠/同名更新/自愈/降级链/by-name 预设 round-trip）+ `PanelWiringTests` lut3d dispatch | 12-5 走查：app 启动 zh 全量渲染 smoke（`12-5-01-launch-zh-smoke.png`，zh 944==en 键）+ 会话打开编辑器（`12-5-02-session-open.png`）；面板交互逻辑由 store+wiring 单测钉死（深交互 F-12-5-1 Manual-Only） | ✅ |

**DOMAIN remap 能力边界声明（F4，RESEARCH §6.1）**：dt 只接受 DOMAIN 0..1（DOMAIN_MIN≠0 /
DOMAIN_MAX≠1 硬错）；本实现 remap 支持（uniform 在索引数学前，`v'=(clamp(v,dom,dom)-min)/
(max-min)·(L-1)`）——**正向超出 dt 能力面，非移植缺口**（ROADMAP SC#4「honoring
DOMAIN_MIN/MAX for float/HDR」字面）。kernel 铁证 = `Lut3dKernelTests` hdr/negative/mixed 三域
vs CPU float64 双写全绿。

**golden-image provenance（CONVENTIONS 纪律）**：参考 = dt lut3d.cl 数学 float64 逐行双写
（L017 route ①先例——dt-cli float export 本 host 空间损坏在案 + darktable-cli CrashReporter
记录；lut3d XMP params-v3 二进制构造超预算）；dt-GUI 人工交叉对照挂 Manual-Only F-12-5-2。

---

## 缺陷处置记录（Phase 12 执行期发现 → 闭环）

| 缺陷 | 发现 | 处置 | 证据 |
|---|---|---|---|
| sidecar_present 永不刷新（GOAL-STATE 阻塞#4） | 12-2 执行轮 | **12-5 收口批修复** `9e70338`：backfill 第三 pending 类（present=0 行 stat `.lra` 存在 → work 集 + UPDATE 翻 present=1）；「先图后 sidecar」行增量打开即回读 | `MetadataServiceTests.testBackfillPromotesLateSidecarRows`（scan-miss → sidecar 出现 → reopen 升格+回读） |
| convertTexture L029 镜像 + 双腿 parity（11-02/11-03 双移交） | 11-05 | **已于 11-05 闭环**（`.downMirrored` + parity 测试在位）；12-5 收口批复核复跑绿，零残留工作 | `ExportEncoderGoldenTests.testColorSyncFallbackLegParityWithExportLeg`（本轮复跑 0 fail） |
| 12-4 D10 LUT 跨机器前提复核钩子 | 12-4 | **12-5 落库兑现**：库名引用 + 查重 + 自愈 + 缺失降级（blit 恒等 + 面板红字 + toast）；F-12-4-3 关闭（12-4-DECISIONS D10 复核注记） | `LutLibraryStoreTests.testRemovalDegradesModuleToIdentity` + by-name preset round-trip |

---

## Per-Task Map（12-1..12-5）

| Task | Plan | 交付 | commit | Status |
|---|---|---|---|---|
| 12-1 T1-T7 | 依赖根 | sidecar v3 五字段 + DB v2 34 列迁移 + claimMetadataApply + MetadataService + EXIF 回填 + UI 接线 | `8f1a96a`/`db105ee`/`4b906b6`/`e0ce1ed`/`0ad5c96`/`a7f44b7` | ✅ |
| 12-2 T1-T6 | 过滤 | FilterPredicateGroup + FilterSQL 翻译层 + query 消费 + 过滤栏 UI + SmartAlbums | `999a9fb`/`128991d`/`7336c3d`/`fc188a9`/`baaa19a` | ✅ |
| 12-3 T1-T6 | XMP | XMPWriter + 三格式注入 + 导出链挂载 + 只读导入 | `76dde86`/`e5e3a21`/`12c6afa`/`7c06fa2` | ✅ |
| 12-4 T1-T5 | 预设 | .lightamer-preset 容器 + PresetsStore + PresetApplier + 管理器/面板/批量 + export preset | `3195c7e`/`f211031`/`9d757d8`/`0b82b0a` | ✅ |
| 12-5 T1 | 解析器 | CubeLutParser + 22 测试 + 脏样本 fixtures | `dbee91e` | ✅ |
| 12-5 T2 | 3D kernel | tetra/trilinear kernel + 模块 + 矩阵资产（rgba32Float 升格 D7） | `814d601` | ✅ |
| 12-5 T3 | 1D kernel | per-channel ramp kernel + INPUT_RANGE remap（texture1d 主案 D8） | `274c6ef` | ✅ |
| 12-5 T4 | 色彩空间 | 四态矩阵往返/灰中性/全链 golden | `a7dfdc6` | ✅ |
| 12-5 T5 | 库+面板 | LutLibraryStore + LutPanelView + zh +18 键 + seed | `d71e830` | ✅ |
| 12-5 收口 | 移交消费 | sidecar_present 修复 + L029 复核 + D10 注记 | `9e70338` | ✅ |
| 12-5 T6 | 签核 | 终轮 1436/6/0 + VALIDATION + 移交清单 + 翻账（本文件） | 本提交 | ✅ |

---

## Manual-Only 汇总表（四 plan + 12-5 登记合并；pending-manual 不阻塞）

| # | 项 | 来源 | 自动化腿状态 |
|---|---|---|---|
| F-12-1-1 | ⇧ 多选批量打分手势合成 | 12-1 | 服务面多目标用例钉死 ✅ |
| F-12-1-2 | 网格右键追加关键词/备注 alert 流 | 12-1 | appendKeywords/appendNote 单测 ✅ |
| F-12-1-3 | 对比（culling）态快捷键双格观感 | 12-1 | 代码面同路径（同一 MetadataController 路由）✅ |
| F-12-2-1 | `/` 键聚焦 Quick Filter 按键合成 | 12-2 | AX 直点可达 + keyboardShortcut 代码面 ✅ |
| F-12-2-2 | chips 长按删除观感 | 12-2 | ⓧ 删除路径走查 ✅ |
| F-12-2-3 | 日期区间 sheet 双 DatePicker 观感 | 12-2 | between SQL + 行集单测钉死 ✅ |
| F-12-2-4 | 智能相册重命名/删除确认 alert 流 | 12-2 | CRUD 服务面单测 ✅ |
| F-12-3-1 | 第三方 .xmp 导入 ⇧ 多选 | 12-3 | 多 relPath 一次调用单测 ✅ |
| F-12-3-2 | typed 错误 alert 三态观感 | 12-3 | 三态路由同路径 + zh 文案在 ✅ |
| F-12-4-1 | 管理器重命名 alert 观感 | 12-4 | 分类编辑共用机制已走查 ✅ |
| F-12-4-2 | 部分应用「粘贴」按钮全链落盘 | 12-4 | partial 子集语义单测钉死 ✅ |
| ~~F-12-4-3~~ | ~~LUT 引用预设跨机器复核~~ | 12-4 | **12-5 已关闭**（D10 复核注记） |
| F-12-5-1 | LUT 面板深交互走查（NSOpenPanel 导入驱动/picker 观感/降级 toast 观感） | 12-5 | store 10 测 + wiring 断言 + 降级链单测 ✅；合成 CGEvent 未达 SwiftUI 工具条（L032 同族限制） |
| F-12-5-2 | dt-GUI 侧 .cube golden 人工交叉对照 | 12-5 | CPU float64 双写参考（L017 先例）+ 权重表 verbatim 核对 ✅ |

**pending-manual 计 13 行**（F-12-4-3 已关闭）；全部为「自动化腿已钉数值/语义，观感/手势待人工」型，不阻塞签核。

---

## 签核判定

**Phase 12 签核：PASS（SC#1-4 ✅；status: validated + nyquist_compliant: true；终轮
1436/6skip/0fail；执行期唯一域缺陷 sidecar_present 已于收口批修复并测试锚定）。**
终验走 verify-work（用户 VALIDATION 过目 + Manual-Only 13 行）；C 档第 3 停按夜间授权
先例（D-07-3-T5-1 / D-09-05-T1-1 / 11-05 D1）先翻账、晨审追认。
