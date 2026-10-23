---
phase: lumen-culling
plan: "LUMEN-B"
title: "plan B — 缓存底座 + 选片视图（LU4+LU3）：T1 SmartPreviewStore LPV1 形 pack/unpack float16 round-trip golden / T2 缓存键（含 process version 维）+ index SQLite + LRU trim + in-flight 去重 / T3 解码出口消费方接线（编辑工作平面零触）/ T4 CullFace 第三 face + CullViewLoader（档位/预读/生产门）/ T5 键位评级写腿（G/D 钉死）/ T6 对比 Pane + 组跳 + 提示条 / T7 Settings 容量键 + 收口"
wave: 2
depends_on: ["LUMEN-A"]
autonomous: true
requirements: ["research 正本 = phases/lumen-culling/RESEARCH.md（ee73da34）§UQ-LU4/§UQ-LU3", "OQ 裁决正本 = 同目录 CONTEXT.md（D-LU-1/3/6 + X6/X7 设计承接 + hazards H-LU3 + 红线 17 条）", "上游 = LUMEN-A 闭环（schema v6 分析产物 + BurstAnnotator 注记——提示条/组跳/分析插队消费面）", "基线 4112/40/0 + LUMEN-A 终态（4124..4127）；本 plan 分账 +14..18", "C 档停位 = 本 plan 执行+验收闭环后停汇报；确认后 LUMEN-C 起跑（C 可换序——D-LU-9）"]
success_criteria: "SC 全可机检——T1：SmartPreviewStore pack/unpack（magic+头长+JSON 头+working-space 线性 float16 量化+字节平面重排+zlib level 1）round-trip golden（逐位一致 + 相对误差 <0.05% 断言）+ quantize 一致性规则专测（新解码也过 round-trip → 命中/未命中同源同值——H-LU3 消解）+ MIT/出处注记；T2：键 = sourcePath|size|mtime|process version|格式版本 → sha1（process 维钉死——mtime/size 变更即失效 + RenderProcess bump 失效测试）+ index SQLite WAL（entries 表形）+ LRU trim 90%（每 16 写一巡）+ in-flight 同 key 合并 + 损坏重建降级直解码（永不阻塞）+ 同目录 tmp 原子晋升（L009）；T3：消费方四门接线（PipeCoordinator 载入腿预览档平面/图库档B RenderLeg/LU3 回落腿/MCP decodeImage 缝）+ 编辑管线全分辨率工作平面零触断言（PixelPipe 零 diff + 编辑解码腿零路由）+ 默认中性 golden（无缓存 = 现状逐字节）；T4：WorkspaceHostView cullFace 第三 face（libraryFace :432-449 同机制）+ CullViewLoader actor（显示档 2560 内嵌直读 + LRU 12-16 + 全尺寸内存 LRU cap 2 + ±3 低优先级预读 + ThumbnailProductionGate 形 cap 2）+ full_size 判定（内嵌 ≥50% sensor px）+ 无合格内嵌回落 RAW 解码腿（走缓存）；T5：键位 G=回图库 / D=进编辑器 / 0-5 星 / P / X / U / 6-9 色标 / A 评级后前进 / F 人脸框（评级写腿 = LibraryStore.setMetadataMarks :455 + 胶片条 96px 复用）+ xcstrings cull_* 尾块 + zh-audit 双 PASS；T6：C 并排对比（左选定右候选 + ←→换候选 + Tab 切侧 + ↑ 晋升 + 缩放位置同步）+ legacy CullingView 纪律继承（paneCap 2 + 错峰解码 + pair-identity task + 平面释放——CullingView 本体零触）+ 连拍组跳（↑↓ + 3/7 序号 + best 标记）+ 提示条（sharpness/eyes_closed/blurry 注记 + 分析插队 ±窗 first=True 缝）+ 分析插队经 LibraryAnalysisService 优先缝"
estimated_tests: "+14..18（T1 +3..4 / T2 +3 / T3 +2 / T4 +3..4 / T5 +2 / T6 +1..2 / T7 0..1；越带申报理由）"
test_bundles: [IOP, APP]
baseline: "4112/40/0 + LUMEN-A 终态（4124..4127——A 收口 SUMMARY 权威数）"
expected_all: "LUMEN-A 终态 + ΔN（本 plan 终态带 4138..4145；--all 归 orchestrator 批准制——本 plan 验收 = 构建 + `--bundle IOP` + `--bundle App` 定向，全套归 Plan C 收口轮统一对账）"
red_lines:
  - "共用红线正本 = CONTEXT §三 plan 红线 front-matter 17 条（FIX2③〔本 plan McpServerController 零 diff——decodeImage 缝 = 既有 seam 消费，零新缝〕/ 封存面〔PixelPipe/HistoryStack/LightamerSidecar 零 diff——缓存只服务预览/选片/重开档位，编辑工作平面零触〕/ xcstrings 尾块 / LocalizationValue 禁形 / L041 tuist 末位 / 机器级单重活 / L013〔sha1 hex index 键面〕/ L009 同目录 tmp 原子晋升 / 默认中性零行为 / UserDefaults 恰一键 previews.cacheMB / --all 批准制 / C 档门控 / probe fence〔重开 ≤100ms 探针〕/ L057 缝 / 测试落域 IOP+APP / commit 纪律 lumenb 前缀）。"
  - "H-LU3 双臂：量化一致性规则（新解码也过 float16 round-trip）+ 编辑管线全分辨率工作平面零触——PixelPipe/RAWDecoder 本体签名零 diff（SmartPreviewStore = 出口包装层）。"
  - "legacy CullingView（App/Sources/Lightamer/UI/CullingView.swift）与 SessionThumbnailProvider（720 档）零 diff——纪律继承非收编；Session 域 1480px/720px 常量零触碰。"
  - "McpServerController 零 diff：MCP decodeImage 消费 = CullingToolset 既有 seam（:68 defaultDecodeImage）内部换 SmartPreviewStore 路由——若实现证明需触 McpServerController = 停手上报（FIX2③ 修订属 orchestrator 权）。"
  - "选片视图不进 MCP 面（RESEARCH §UQ-LU3——MCP 不新增选片工具；refine_masks 归 Plan C）。"
files_modified:
  - LightamerCore/Sources/Decode/SmartPreviewStore.swift      # T1/T2：新建——LPV1 形 pack/unpack + 键/index/LRU/in-flight（MIT·Lumen 出处注记）
  - LightamerCore/Sources/Decode/RAWDecoder.swift             # T3：出口包装层消费点（decode 之上零签名改——核实最小触点）
  - App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift    # T4：cullFace 第三 face + 路由缝
  - App/Sources/Lightamer/Library/CullViewLoader.swift        # T4：新建——actor 档位/LRU/预读/生产门/full_size 判定
  - App/Sources/Lightamer/Library/CullFaceModel.swift         # T4/T5/T6：新建——选片面状态模型（键位/评级/对比/组跳/提示条）
  - App/Sources/Lightamer/Library/Views/CullFaceView.swift    # T4/T5/T6：新建——头栏/主 Pane/胶片条/键位帮助行
  - App/Sources/Lightamer/Library/LibraryThumbnailBridge.swift # T3/T4：RenderLeg 生产侧 + 96px 胶片条复用缝（零触既有 gate 语义）
  - App/Sources/Lightamer/MCP/Tools/CullingToolset.swift      # T3：defaultDecodeImage 内部路由 SmartPreviewStore（seam 签名零改——核实最小触点；禁触工具面）
  - App/Sources/Lightamer/Settings/（容量键设置行落点文件）     # T7：previews.cacheMB 设置行（实际 Settings 文件 execute 期核实）
  - Resources/Localizable.xcstrings                           # T5/T6：cull_* 键族尾块纯插入
  - Tests/LightamerTestsIOP/SmartPreviewStoreTests.swift      # T1/T2：新建（IOP bundle——Decode 域）
  - Tests/LightamerTestsApp/CullFaceModelTests.swift          # T4/T5/T6：新建（APP bundle）
  - Project.swift                                             # T7：两个新测试文件入对应 bundle 显式数组
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt # T7：两行登记
  - .work/gsd/phases/lumen-culling/LUMEN-B-SUMMARY.md         # T7：执行摘要（逐任务记账 + ΔN 终账 + 探针指针）
  - .work/gsd/phases/lumen-culling/LUMEN-B-DECISIONS.md       # T7：裁定记录（消费方接线终形 + 各偏差 + 键登记）
---

# Plan LUMEN-B — 缓存底座 + 选片视图（LU4 + LU3）

> **裁决正本** = `CONTEXT.md`（D-LU-1/3/6 + X6/X7；晨审可推翻）；规格
> 正本 = `RESEARCH.md`（§UQ-LU4 / §UQ-LU3 / §依赖与切分 B 行；planner
> 抽核吻合 + 勘误见 CONTEXT）。本 plan = Decode 域新层 + App 选片面新
> face；**PixelPipe/RAWDecoder 签名零 diff**（SmartPreviewStore = 出口包
> 装层）、**legacy CullingView 零触**（纪律继承非收编）、**MCP 工具面零
> 新增**。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（T1-T7 形态 = CONTEXT D-LU
> 落定值）。执行中如触「必须扩面」（编辑工作平面路由 / MCP 选片工具 /
> 独立窗形态 / 封存面触碰 / CullingToolset 工具面改动）= 停手上报。
>
> **执行序**：T1 → T2 → T3 → T4 → T5 → T6 → T7。每任务独立 commit；
> 重活起跑前过 `Scripts/machine-guard.sh`；开工前核 `.work/config.toml
> [gsd]` paused/auto。
>
> **C 档停**：T7 闭环后**停汇报**；确认后 LUMEN-C 起跑（C 可换序——
> D-LU-9，若用户裁决 C 提前则本 plan 停位后换序）。
>
> **基线**：LUMEN-A 终态（4124..4127，A 收口 SUMMARY 权威数；原基线
> 4112/40/0）。全套预期 = A 终态 + ΔN（本 plan 分账 +14..18 → 终态带
> 4138..4145）。

## ΔN 预算表（逐任务，本 plan 分账带 +14..18；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 pack/unpack | **+3..4** | round-trip golden（逐位 + <0.05%）+ quantize 一致性 + 平面重排压缩率 smoke | IOP（SmartPreviewStoreTests） |
| T2 键/index/LRU | **+3** | 键失效（mtime/size/process bump）+ trim 逐出序 + in-flight 合并 + 损坏重建 | IOP |
| T3 消费方接线 | **+2** | 四门路由 + 编辑工作平面零触断言 + 默认中性 golden | IOP |
| T4 CullFace 窗体 | **+3..4** | loader 档位/预读序/生产门 cap/full_size 判定/回落腿 | APP（CullFaceModelTests） |
| T5 键位评级 | **+2** | 键位映射表驱动 + 评级写腿 + 评级后前进 + 胶片条供给 | APP |
| T6 对比/组跳/提示条 | **+1..2** | 对比状态机 + 缩放同步模型 + 组跳序 + 提示条注记映射 + 插队缝 | APP |
| T7 收口 | **0..1** | Settings 键行 + docs + 数组 + BUNDLE-MAP + tuist generate | — |
| **合计** | **+14..18** | A 终态 → 本 plan 终态带 4138..4145 | 两新测试文件 |

## 已定裁决（生效值，硬约束，不得重开）

1. **窗体 = 主窗第三 face**（D-LU-1）——独立 NSWindow / 全屏 presentation
   不采纳；Esc/G 回图库。
2. **缓存落点 = `~/Library/Caches/Lightamer/smart-previews/`**（D-LU-3）
   ——键含 process version 维；不进 .lalb 包。
3. **全尺寸内存 LRU cap 2**（D-LU-6）——150-200MB/张 × 2 峰值可控。
4. **量化一致性 = 新解码也过 float16 round-trip**（X6/H-LU3）——命中与
   未命中逐位一致；**编辑管线全分辨率工作平面零触**（缓存档位 = 预览/
   选片/重开；DRT/film 尾平面不缓存）。
5. **G/D 键位钉死**（X7）——G = 回图库（Lumen Esc-G 映射）、D = 进编辑
   器（Lumen Enter 显影映射）；0-5/P/X/U/6-9/A/C/F 沿 Lumen 词汇。
6. **MCP 零新增选片工具**（红线 5）——选片是 GUI 面；MCP decodeImage 消
   费 = 既有 seam 内部路由。
7. **legacy CullingView / SessionThumbnailProvider 零触**（红线 3）——
   纪律继承（paneCap 2/错峰解码/pair-identity task/平面释放），不收编不
   复用 720 档。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/lumen-culling/CONTEXT.md`（D-LU-1/3/6 + X6/X7 +
  hazards H-LU3 + 红线 17 条 + 勘误）
- `.work/gsd/phases/lumen-culling/RESEARCH.md` §UQ-LU4/§UQ-LU3/§风险 6-8
- LUMEN-A 收口产物（LUMEN-A-SUMMARY/DECISIONS——注记面/服务缝消费契约）
- Lumen 直译源（只读，`git show v2.0.1:`——**禁触其工作区**）：
  `lumen/preview_cache.py`（441 行全读——LPV1/stamp/pack-unpack/LRU trim/
  in-flight/prefetch/降级直解码）；`lumen/previews.py:182,244-303`
  （VIEW_EDGE/full_size 判定/embedded_view）；`lumen/cull_view.py:32-37,
  67-132,251-578`（窗体/ViewLoader/键位/对比/组跳/分析插队）
- `.work/config.toml [gsd]` paused/auto + `.work/LESSONS.md` L041（两个
  新测试文件必触发）/ L014（重开命中探针 fence）/ L009（tmp 原子晋升）
- AGENTS.md M2-3 节（档A/档B 层级判定——SmartPreviewStore = 解码级缓存
  非显示代理）+ M6-2（process version 读点）+ M2-4-0 E2（落域）

---

## T1 — SmartPreviewStore：LPV1 形 pack/unpack + round-trip golden（X6，H-LU3 消解）

> Lumen `preview_cache.py:41-49,69-114` 直译域；我方平面 = working-space
> 线性 float16 量化平面（管线 float32 RGBA premultiplied 读回合成）。

**read_first**：CONTEXT §X6 + §Hazards H-LU3；Lumen `preview_cache.py`
（pack/unpack :96-114 / quantize :79-81 / LPV1 头 :41-49）；RESEARCH
§UQ-LU4 格式段 + §风险 6；`RAWDecoder.swift:120`（decode 出口——包装层
插点参照，本体零改）。

- **action**：
  1. 新建 `LightamerCore/Sources/Decode/SmartPreviewStore.swift`（本任务
     只落格式层）：`pack(plane: 线性 float32 RGBA, meta: JSON) -> Data`
     = magic（LPV1 形我方拼写——`LAPV1` 类）+ 头长 + JSON 头（尺寸/
     平面描述/格式版本）+ **float16 量化 + 字节平面重排（低/高字节分平
     面）+ zlib level 1**；`unpack(data) -> (plane: float32 RGBA, meta)`
     读回升 float32。
  2. **量化一致性规则**：`quantize()` 公开函数——新解码路径同过 float16
     round-trip（T3 消费方接线统一应用）；命中/未命中同源同值前提。
  3. 出处注记（文件头：格式形态源自 LUMEN RAW preview_cache——MIT 出处
     注记；T3 NOTICE 条目复核覆盖，格式层非算法件、注记级别）。
  4. 测试（IOP）：round-trip golden（随机平面 + 实拍导出平面双源——
     pack→unpack 逐位一致 + float16 相对误差 <0.05% 断言）+ quantize
     一致性专测（raw 平面 vs quantize 后平面经 pack/unpack 恒等）+ 平面
     重排压缩率 smoke（重排 vs 不重排字节数单调——直译动机验证）+ 畸形
     头容错（magic/头长不符 = typed 失败不 crash）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰一新产线文件。
  - round-trip golden 在册（逐位断言 + 误差断言双写留档 evidence）；
    畸形输入容错例在册。
  - `--bundle IOP` 定向零回归。
- **commit**: `feat(lumenb): add smart preview pack format with float16 planes`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（纯新件）；偏差（
  magic 拼写/JSON 头字段）= DECISIONS 申报；**禁改量化规则**（新解码也
  过 round-trip = 命中一致性前提，H-LU3）；**禁 zlib 高级别**（level 1
  = Lumen 标定——读 ~40ms 口径前提）。

## T2 — 缓存键（process 维）+ index SQLite + LRU + in-flight（X6，D-LU-3）

**read_first**：CONTEXT §X6 + §D-LU-3；Lumen `preview_cache.py:69-76`
（stamp）/:117-227（index/trim）/:307-365（in-flight/降级）；
`LibraryThumbnailBridge.swift:38-80`（gate actor 先例——in-flight 合并
同形）；AGENTS M6-2（RenderProcess 单源——process version 读点核实）；
L009（LESSONS）。

- **action**：
  1. 键 = `sourcePath|size|mtime|process version|缓存格式版本` → sha1
     （hex string 入 index——L013 邻域）；process version 读点 = RenderProcess
     单源（注入式读缝——测试可钉 bump 失效）。
  2. 存储 = `~/Library/Caches/Lightamer/smart-previews/`：index SQLite
     WAL（entries(key,kind,bytes,used) 表形直译）+ 平面文件（key 命名，
     同目录 tmp + 原子晋升——L009）。
  3. LRU = 默认 4GB（UserDefaults `previews.cacheMB` typed 读 + 注入式
     ——红线 11；0 = 关）；trim 到 90% 按最旧 used 逐出；每 16 写一巡。
  4. 内存层 = 解码平面 LRU 6 张 float32 + in-flight 同 key 合并（gate
     actor 先例同形）+ 缓存不可读写降级直解码（权限/盘满永不阻塞）+
     损坏即删重建。
  5. 测试（IOP）：键失效三例（mtime/size 变更 + process version bump——
     注入读缝钉）+ trim 逐出序（used 单调）+ in-flight 并发合并（同 key
     双请求单解码——并发测试）+ 损坏 index/文件重建 + 降级直解码（目录
     不可写注入）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰一产线文件（SmartPreviewStore.swift 续
    任务域）。
  - grep：键格式串含 `process` 维拼写恰一处；`previews.cacheMB` 全仓恰
    一处（键单源）；`os.replace`/rename 原子晋升在 SmartPreviewStore
    域内（同目录）。
  - 五类测试在册（失效/trim/合并/重建/降级）。
  - `--bundle IOP` 定向零回归。
- **commit**: `feat(lumenb): add smart preview cache index lru and inflight merge`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（T1 格式层保留独立可
  revert）；偏差（WAL pragma 细节/内存 LRU 容量）= DECISIONS 申报；
  **禁 /tmp 跨卷**（L009）；**禁缓存写阻塞主路径**（降级直解码语义——
  永不阻塞打开）；**禁 process 维缺席**（D-LU-3 钉死项）。

## T3 — 解码出口消费方接线（X6 四门 + 编辑工作平面零触）

**read_first**：CONTEXT §X6 红线臂 + 红线 4；`RAWDecoder.swift:110-130`
（decode 入口——包装层插点）；`CullingToolset.swift:60-110`（decodeImage
seam + defaultDecodeImage——内部路由点）；`LibraryThumbnailBridge.swift`
（RenderLeg 生产侧注记 :5-31）；AGENTS M2-6（尾平面格式纪律——DRT/film
尾平面不缓存依据）。

- **action**：
  1. 消费方四门接线（各恰最小触点）：①PipeCoordinator 载入腿**预览档
     平面**读经 SmartPreviewStore（命中直读、未命中解码后回填）；②图库
     档B RenderLeg 生产侧同缝；③选片回落腿（T4 消费——本任务先落缝）；
     ④MCP `decodeImage` = CullingToolset `defaultDecodeImage` **内部**
     换路由（seam 签名零改；`McpServerController` 零 diff 核实——若证
     明必须触 = 停手上报，红线 4）。
  2. **量化一致性应用**：四门新解码统一过 `quantize()`（T1 规则）——
     命中/未命中同源同值。
  3. **编辑管线全分辨率工作平面零触断言**：编辑解码腿零路由（grep +
     结构断言——SmartPreviewStore 消费点清单 = 四门，编辑腿不在册）；
     PixelPipe/RAWDecoder 签名零 diff。
  4. 测试（IOP）：四门命中/回填路由 + 默认中性 golden（缓存目录缺席 =
     现状解码逐字节）+ 编辑腿零路由断言（消费点清单负测）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` = 消费方最小触点文件（预期 ≤3：RAWDecoder
    包装层调用点 + CullingToolset 内部路由 + PipeCoordinator/bridge 预
    览档缝——实际清单 DECISIONS 申报）；PixelPipe 零 diff。
  - grep：SmartPreviewStore 消费点 = 四门清单（负测钉死——编辑工作平面
    路由零命中）；`McpServerController.swift` 零 diff（`git diff` 面核）。
  - 默认中性 golden 在册；`--bundle IOP` + `--bundle App` 定向零回归。
- **commit**: `feat(lumenb): route preview decodes through smart preview store`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（消费方回落直解码——
  缓存闲置无行为差）；偏差（实际消费点清单/触点文件数）= DECISIONS 申
  报；**禁触编辑工作平面路由**（红线 4/H-LU3——发现「必须」即停手上
  报）；**禁改 seam 签名**（CullingToolset decodeImage :68 类型零改）；
  **禁缓存 DRT/film 尾平面**（显示格式重算成本低——X6 红线臂）。

## T4 — CullFace 第三 face + CullViewLoader（X7，D-LU-1/6）

**read_first**：CONTEXT §X7 + §D-LU-1/6；`WorkspaceHostView.swift:420-470`
（libraryFace 装配 + onOpen 路由——第三 face 同机制）；Lumen
`previews.py:244-303`（embedded_view/full_size 判定）+ `cull_view.py:
32-37,411-430`（VIEWS/AHEAD/ViewLoader 双线程）；`LibraryThumbnailBridge
.swift:38-80`（ThumbnailProductionGate 形——cap 2 复用）；T3 回落腿缝。

- **action**：
  1. `WorkspaceHostView` 加 `cullFace` 第三 face（libraryFace :432-449
     同机制——左主 Pane + 头栏 + 底胶片条；路由 = 图库 onCull 缝 → face
     切换；Esc/G 回图库）。
  2. 新建 `App/Sources/Lightamer/Library/CullViewLoader.swift`（actor）：
     显示档 = `CGImageSourceCreateThumbnailAtIndex` max pixel **2560**
     内嵌直读（Lumen VIEW_EDGE 直译——零 RAW 解码）；LRU 视图 12-16 张；
     全尺寸内存 LRU **cap 2**（D-LU-6）；±3 预读（低优先级尾插——
     prioritize 反向同形）；生产门 cap 2（ThumbnailProductionGate 形复
     用/同构）；`full_size` 判定（内嵌 ≥50% sensor px——
     CGImageSourceCopyPropertiesAtIndex EXIF 尺寸比对）→ 100% 腿优先全
     尺寸内嵌 JPEG，无合格内嵌回落 RAWDecoder 解码腿（走 T3 缓存）。
  3. 新建 `CullFaceModel`/`CullFaceView`（App Library 域）：头栏（文件
     名/序号/EXIF 行/提示条占位/评级后前进开关/对比钮）+ 主 Pane（单/
     双）+ 底部胶片条（96px 复用 LibraryThumbnailBridge）+ 键位帮助行。
  4. 测试（APP）：loader 档位/预读序（±3 窗）/生产门 cap/full_size 判
     定表驱动（合成 properties）+ 回落腿切换 + face 路由状态机。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` = WorkspaceHostView + 两新文件（+T3 已落
    缝文件零再触申报）。
  - grep：`2560` 档常量恰一处（CullViewLoader 域）；`720` 零命中（该域
    ——SessionThumbnailProvider 零触核）；cap 2 两处（生产门 + 全尺寸
    LRU）各恰一常量。
  - `CullingView.swift` 零 diff（`git diff` 面核）。
  - `--bundle App` 定向零回归。
- **commit**: `feat(lumenb): add cull face with embedded preview loader`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（第三 face additive，
  既有两 face 零行为差）；偏差（LRU 容量终值/胶片条档位）= DECISIONS
  申报；**禁触 legacy CullingView**（红线 3）；**禁新 NSWindow**（D-LU-1
  ——face 路由钉死）；**禁在 body 求值路径解码**（loader actor 异步缝
  ——body 纯函数纪律）。

## T5 — 键位 + 评级写腿 + 胶片条（X7，G/D 钉死）

**read_first**：CONTEXT §X7 键位表；Lumen `cull_view.py:529-578`（键位
全表——映射参照）；`LibraryStore.swift:455`（setMetadataMarks——评级写
腿）；T4 面板骨架。

- **action**：
  1. 键位落地（CullFaceModel 键位映射表——表驱动可测）：`G` 回图库 /
     `D` 进编辑器 / `0-5` 星级 / `P` 留用 / `X` 排除 / `U` 取消 / `6-9`
     色标 / `A` 评级后前进（开关联动头部开关）/ `F` 人脸框显隐（T4 产
     物 face_boxes）。
  2. 评级写腿 = `LibraryStore.setMetadataMarks`（:455——单批写）；评级
     后前进（A 开关 on = 写完自动 next）。
  3. 胶片条 = LibraryThumbnailBridge 96px 档复用 + 当前位高亮 + 连拍组
     折叠视觉（T6 组跳联动）。
  4. xcstrings `cull_*` 键族尾块纯插入（帮助行/头栏/开关文案）；
     zh-audit 双 PASS。
  5. 测试（APP）：键位映射表驱动（键 → 动作全案）+ 评级写腿调用断言
     （合成 store）+ 评级后前进序 + 色标映射。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` 恰两产线文件（CullFaceModel/CullFaceView
    续域）+ xcstrings。
  - grep：键位映射表含 `G`/`D`/`P`/`X`/`U`/`A`/`C`/`F` 全案（表驱动
    断言面）；xcstrings 尾块 diff = 纯插入。
  - zh-audit 双 PASS 输出留档；`--bundle App` 定向零回归。
- **commit**: `feat(lumenb): add cull face keybindings and rating flow`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（键位冲突微调
  ——与系统快捷键撞车时）= DECISIONS 申报（G/D 钉死项不动，冲突键可换
  位申报）；**禁改 setMetadataMarks 签名**（既有写腿消费）；**禁键位散
  落视图层**（映射表单源）。

## T6 — 对比 Pane + 连拍组跳 + 提示条 + 分析插队（X7）

**read_first**：CONTEXT §X7 纪律继承臂；`CullingView.swift:30-37,91-120`
（paneCap 2/错峰解码/pair-identity task/平面释放——纪律正本，本体零触）；
Lumen `cull_view.py:451-504`（对比/缩放同步/组跳）+:426-429（分析插队）；
LUMEN-A 产物（BurstAnnotator 注记 + LibraryAnalysisService 优先缝——消
费契约）。

- **action**：
  1. C 并排对比：左 = 选定右 = 候选；`←→` 换候选 / `Tab` 切评级侧 /
     `↑` 候选晋升；**缩放与位置同步**（共享 zoom state——sync_zoom 直
     译）；Pane 装配继承 legacy 纪律（cap 2 + 错峰解码 + pair-identity
     `.task(id:)` + 旧平面释放——CullingView :91-120 同构新写）。
  2. 连拍组跳：组内「3/7」序号 + best 标记 + `↑↓` 组间跳（T6 注记消
     费——BurstAnnotator 查询期注记经 CullFaceModel 投影）。
  3. 提示条：sharpness 分 + 可能模糊（<22 或组相对 >14）/ 可能闭眼 /
     连拍序号（LUMEN-A 注记面）；`blurry` 组相对部分 = 注记层消费（X5
     裁定——SQL 面无此条件）。
  4. 分析插队：当前 ±(−2..+6) 窗未分析行经 LibraryAnalysisService 优先
     缝插队（`first=True` 语义——优先队列头插；Lumen :426-429 直译）。
  5. 测试（APP）：对比状态机（换候选/切侧/晋升）+ 缩放同步模型 + 组跳
     序（跨组边界 clamp）+ 提示条注记映射表驱动 + 插队缝调用断言（合
     成 service）。
- **验收标准（机检）**：
  - 构建绿；`git diff --stat` = CullFaceModel/CullFaceView 续域（+
    LibraryAnalysisService 优先缝 additive——如需）。
  - 对比状态机/组跳/提示条测试在册；`CullingView.swift` 零 diff 面核。
  - `--bundle App` 定向零回归。
- **commit**: `feat(lumenb): add compare panes burst jumps and hint bar`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；偏差（插队窗参数/
  提示条分项）= DECISIONS 申报；**禁把对比 Pane 写进 legacy CullingView**
  （新写同构——红线 3）；**禁同步阻塞分析趟**（插队 = 优先缝非抢占——
  H-LU1 语义延续）。

## T7 — Settings 容量键 + 收口（红线 11）

- **action**：
  1. Settings 页 `previews.cacheMB` 容量行（默认 4096，0 = 关——typed
     读 + 注入式 defaults；`App/Sources/Lightamer/Settings/` 实际文件
     execute 期核实落点）。
  2. `Project.swift` 两个新测试文件入数组（SmartPreviewStoreTests →
     LightamerTestsIOP；CullFaceModelTests → LightamerTestsApp）+
     BUNDLE-MAP 两行。
  3. `tuist generate` = 本批最后一个动作（L041）。
  4. `--bundle IOP` + `--bundle App` 定向全绿；ΔN 实数对账（预算
     +14..18）。
  5. LUMEN-B-SUMMARY（逐任务记账 + ΔN 终账 + 重开命中探针指针）+
     LUMEN-B-DECISIONS（消费点清单 + 各偏差 + 键登记）落盘。
  6. 汇报 + **C 档停**。
- **验收标准（机检）**：定向 bundle 全绿零回归；Project.swift diff =
  恰两行数组插入；BUNDLE-MAP 两行在库；SUMMARY/DECISIONS 在库；重开命
  中探针（LIGHTAMER_PERF_PROBE + fence——≤100ms 级）结果落 SUMMARY（skip
  族申报）。
- **commit**: `test(lumenb): register cull view suites and close out plan b`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；ΔN 越带 = SUMMARY
  申报理由；禁漏 tuist generate。

---

## 风险与回退

- **float16 视觉回归**（RESEARCH §风险 6 / H-LU3）：quantize 一致性规则
  （T1/T3）为结构性消解；golden 失配 = 停手定位（round-trip 数学面，
  非参数题）。
- **100% 内嵌 JPEG 可用性**（§风险 7）：full_size 判定不合格 = 回落 RAW
  解码腿（缓存命中则快）；Canon PQ 档内嵌可读性 = execute 期抽验（样张
  落 evidence）。
- **缓存磁盘占用**（§风险 8）：默认 4GB（0 = 关）；trim 90% + 每 16 写
  一巡；DerivedData 巡检告警不受扰（目录独立）。
- **消费方接线扩散**：四门触点若超预期（PipeCoordinator 腿结构复杂）=
  停手申报最小触点清单（红线 4 精神——FIX2③/封存面优先）。
- **键位与系统冲突**：G/D 与 Spotlight/输入法候选撞车 = DECISIONS 申报
  换位（G/D 语义不动，物理键可调——钉死的是语义对）。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：RESEARCH §UQ-LU4 缝位 ↔ T1/T2/T3；§UQ-LU3 缝位 ↔
   T4/T5/T6；H-LU3 ↔ T1/T3 双臂。
2. **OQ 兑现核**：D-LU-1（T4 face 非 window）/ D-LU-3（T2 目录 + process
   键维）/ D-LU-6（T4 cap 2）/ G-D 键位（T5 映射表）。
3. **红线核**：PixelPipe/RAWDecoder 签名/CullingView/SessionThumbnailProvider
   /McpServerController 零 diff；编辑工作平面零路由负测；L009 原子晋升；
   xcstrings 尾块；tuist generate 末位。
4. **SC 可机检性**：每条 SC 有命令级判据；ΔN 对账式非死数；消费点清单
   负测可执行。
