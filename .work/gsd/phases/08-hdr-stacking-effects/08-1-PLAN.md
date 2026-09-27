---
phase: 8
plan: "08-1"
title: "堆栈簇底座 + HDR merge（W1，堆栈簇依赖根）：StackMergeService actor（独立低优先级队列 + cancel epoch + 进度/失败分型）+ MTB 对齐（8 级金字塔 + EXIF 预检 + 降级）+ Robertson 线性加权合并（双门高斯权 + HOLE/weight-map + 行带流式两遍 + float TIFF 分行写）+ ghost mask（残差拒绝 → RasterMaskRef PNG + Ghost Suppression 层）+ 产物落位（会话根 + ExportNamer 防撞 + App 编排入口）+ sidecar v4 provenance（漂移标脏 + 重合并重放）+ HDR-04 验证矩阵基座"
wave: 1
depends_on: []
autonomous: true
requirements: [IOP-HDR-01, IOP-HDR-04]
files_modified:
  - LightamerCore/Sources/Stack/StackMergeService.swift        # 新建：actor 服务——独立低优先级 MTLCommandQueue（Phase 11 export queue 惯例）+ cancel epoch + (done,total) progressHook + 显式 retry + 失败分型（解码/写盘硬失败，对齐降级续跑）
  - LightamerCore/Sources/Stack/MTBAlign.swift                 # 新建：8 级金字塔 median-threshold 位图 + packed UInt64 XOR/popcount 粗到细搜索 + (dx,dy) 收缩比较窗 + 失败判定（XOR/px>0.25 或命中搜索界 → 降级）
  - LightamerCore/Sources/Stack/ExifPrecheck.swift             # 新建：机身/镜头/焦距/光圈/ISO 严格预检 + 快门必须不同 + ΔEV 合成 + 光圈/ISO override 放行 + 运行时曝光比例自检（>5% 降级）
  - LightamerCore/Sources/Stack/HDRMergeMath.swift             # 新建：Robertson 权重终形（clip 0.995/floor 0.001 双门 + gaussian σ=0.2 参数化 + weightNoiseFloor additive 默认关）+ L̂ 合并 + HOLE/weight-map + ghost 残差拒绝数学（CPU 纯函数，golden 正本）
  - LightamerCore/Sources/Stack/BandStreamer.swift             # 新建：行带流式两遍合并遍（TilingPlan 几何生成 256 行带网格，不引入 in-pipe tile driver）+ CGImageDestination 分行 append float TIFF 写（EXP-01 面）
  - LightamerCore/Sources/Stack/GhostMaskWriter.swift          # 新建：残差位图 3×3 膨胀 2 轮 → 16-bit PNG 落 <base>_hdr.tif.lra.masks/<maskID>.png（RasterMaskRef 形态 + StableHash over PNG 字节）
  - LightamerCore/Sources/Sidecar/LightamerSidecar.swift       # schemaVersionCurrent 3→4 additive：optional provenance 字段（kind/algorithm/sources/alignment/exposureRatioVerified/holeFraction/createdAt/appVersion；UInt64String 纪律）
  - LightamerCore/Sources/Stack/ProvenanceReplay.swift         # 新建：载入产物 sources[].stableHash 重算比对 → 标脏 + 重合并入口（provenance 重放）
  - App/Sources/Lightamer/UI/SessionBrowserView.swift     # 多选 context menu「HDR 合并…」→ 参数确认（deGhost toggle）→ StackMergeService 入队 + 进度 toast + 完成产物入 grid（最小编排入口）
  - Tests/LightamerTests/StackMergeServiceTests.swift          # 新建：服务骨架/cancel/progress/失败分型/互斥只读
  - Tests/LightamerTests/MTBAlignTests.swift                   # 新建：合成 bracket 位移精确命中/收缩窗越界/失败降级/EXIF 预检矩阵
  - Tests/LightamerTests/HDRMergeMathTests.swift               # 新建：§1.4 golden——L̂ <1% / HOLE wsum==0 / ghost k=3 拒绝 <0.02 / 权重双门边界
  - Tests/LightamerTests/ProvenanceV4Tests.swift               # 新建：v4 round-trip 逐字节向后兼容/漂移标脏/重合并重放/防撞递增
  - Tests/LightamerTests/HDRPipelineMatrixTests.swift          # 新建：HDR-04 矩阵基座（torture 全链 parity + 已知值 patch；lut3d 列留 08-5）
  - .work/gsd/phases/08-hdr-stacking-effects/perf.md           # 新建：CIRAW 100MP 解码首测 + 全程秒表（<60s 参考基准）+ 各段 vs research §0 表对账
  - .work/gsd/phases/08-hdr-stacking-effects/08-1-SUMMARY.md
  - .work/gsd/phases/08-hdr-stacking-effects/08-1-DECISIONS.md
  - Resources/Localizable.xcstrings  # L025 zh/en 同批
  - TODO.md                                                    # Phase 8（HDR/Stacking & Effects）节开账 + 08-1 勾选
  - LESSONS.md                                                 # 如踩坑
---

# Plan 08-1 — 堆栈簇底座 + HDR merge（W1，堆栈簇依赖根）

> 背景：多源合并/堆栈是**文档级服务，不是 in-pipe iop**（D-08-CONTEXT-1/11）——pixelpipe 一切身份
> 机制（PipeCacheKey/history/paramsHash/四管线生命周期）都是 per-image 单文档语义，多源没有可挂的
> 缝。正确形状 = `StackMergeService`（读 N 源 → 对齐 → 加权合并 → 落一个新 float32 文档 + provenance
> sidecar），产物从落盘那一刻起就是普通单文档走既有全链。本 plan 交付服务骨架 + HDR merge 全链
> （MTB 对齐 → Robertson 线性加权 → ghost mask → 落位/provenance），08-3 复用骨架只换末段。
> 内部任务序刚性：T1 服务骨架 → T2 对齐/预检 → T3 合并数学+流式 → T4 ghost → T5 落位/入口 E2E →
> T6 provenance v4 → T7 矩阵基座 → T8 收口（前者是后者的编译/数据依赖序）。

## read_first

1. `.work/gsd/phases/08-hdr-stacking-effects/08-RESEARCH.md` 全文——§0 探针五项全绿结果表、§1（权重
   终形 + 响应函数操作性消解 + HOLE 语义 + §1.4 golden 设计）、§2（MTB 参数定表 + 性能终数 + 失败
   降级 + EXIF 预检表）、§3（落位推演表 + ExportNamer 防撞 + provenance 字段终表 + 编辑链零改）、
   §4（ghost mask 四步闭环）、§6（行带流式两遍终形 + TilingPlan 复用边界）、§12（服务形态/失败分型/
   互斥 + 100MP 预算表）、§13（HDR-04 验证矩阵——本 plan 建基、lut3d 列留 08-5）、§16 风险表 R2/R3/
   R6/R7/R8
2. `.work/gsd/phases/08-hdr-stacking-effects/08-CONTEXT.md`——D-08-CONTEXT-1（Robertson+MTB+共识
   ghost；Mertens 否决）、D-08-CONTEXT-3（三模式同骨架——本 plan 只交付 HDR 末段）、D-08-CONTEXT-11
   （产物 = 会话内新文档 + provenance；源永不可变）、继承定案节（one-way 格式锁/StableHash L013/
   L014 fence/golden 纪律/非破坏性）、验证与红线节（合并数值 golden 禁「看起来对」+ provenance 专项）
3. `LightamerCore/Sources/Export/ExportQueue.swift:43-115`——actor + cancel epoch + (done,total)
   progressHook + 无自动重试/显式 retry 的形状正本（StackMergeService 逐段对位）
4. `LightamerCore/Sources/Decode/RAWDecoder.swift:158-175`——float TIFF/EXR 保深读直通（RAW-03；
   产物载入与源解码两用）+ `LightamerCore/Sources/Pipe/PipeResolution.swift:10-27`（四管线生命周期
   ——产物走常规链的「零新机制」依据）
5. `LightamerCore/Sources/Export/ExportNamer.swift:53,82-83`——`<stem>[_<tag>].<ext>` + `-1/-2/-3`
   冲突递增（产物命名防撞正本；时间戳否决）
6. `LightamerCore/Sources/Sidecar/LightamerSidecar.swift:113`——`schemaVersionCurrent = 3`（v4 升级
   位）+ SidecarStore per-image actor 2s debounce 写惯例（产物 .lra 挂接）
7. `LightamerCore/Sources/Layers/Masks/RasterMaskRef.swift:13-17`——`{fileName, maskHash, invert}` +
   `.lra.masks/<maskID>.png` 旁挂约定（ghost mask 落盘形态正本）
8. `App/Sources/Lightamer/Session/SessionTreeScanner.swift:98-105` + `SessionLayout.swift:40-44`——
   排除语义（会话根落位 → grid 可见的判定依据；`.lra` 排除 + `.tif` rasterExtensions）
9. `LightamerCore/Sources/Pipe/Tiling/TilingPlan.swift`——纯 tile 几何（行带 = tile 高 = band 特例；
   只用其几何函数生成行带网格，不引入 in-pipe tile driver——合并**不走** PixelPipe）
10. `LESSONS.md` L009（fixture 禁 UNITEK / 同目录 tmp 晋升）/ L013（哈希 decimal String）/ L014
    （GPU 读回 fence drain()）/ L020（内容级断言）/ L031（唯一路由获取点）+ `AGENTS.md`（Phase 执行
    模型 + 暂停机制）+ `.work/GOAL-STATE.md`（Phase 8 续接点）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 本任务申报文件）；`caffeinate -dis` 包裹一切构建
  （`xcodebuild build-for-testing` 先行——test-direct 前提）。
- **单测命令** = `Scripts/test-direct.sh '<Class>'`；**判据 = Executed 计数行 + failures 行**，
  Executed 0 = 判据失败（防空转假绿）。
- **每任务边界检查 `.work/config.toml [gsd]` 开关（`auto`/`paused`）**——commit 后、下一任务前：
  `paused=true` 全链路停；`auto=false` 完成当前任务后停等「继续」。
- **不 push**（本 Phase 全部 plan 同此）；**构建勿加 `-derivedDataPath`**（SPM submodule 坑）；
  **T1 新建 `LightamerCore/Sources/Stack/` 目录后、此后每新建源/测试文件后跑 `tuist generate`**（11-03
  教训）。
- **回归基线 = 1636/10skip/0fail**（13-3 后基线）；每任务全套 suite 绿；本 plan 收尾轮 = 1553 + 新增，
  0 fail。**在案 flake 归因条款**：`LayerE2ERoundTripTests` / `ToneEqualPerf` 两个负载型 flake 若现，
  隔离 ×3 归因单列入 SUMMARY，不计违约。
- **L031 路由红线（本 plan Metal 面适用）**：一切模块内 GPU 提交（合并 kernel/读回 fence/identity
  快速路径）必须走 `MetalContext.makeRoutedCommandBuffer()`（`MetalContext.swift:524`）唯一路由获取
  点，禁自建 MTLCommandBuffer/硬编 queue；`StackMergeService` 专属低优先级队列为服务自包含域
  （producer/consumer 同队列），**队内读回守 L014 fence（drain()）**，服务队列不得与 editor/export
  队列交叉提交共享平面。
- **perf 口径 = 只记不设门**（与 Phase 12 先例一致）：research §0/§12 实测数字（MTB 3.8s、合并
  1.1s、全程 <60s @100MP×3 等）作为**参考基准**落 perf.md 对账；偏差 >2× 归因注记，不设硬门、
  不得为凑数字调口径（L020 同源纪律）。
- **fixture 禁 UNITEK 盘**（L009）——合成 bracket fixture/合并产物测试落本地盘临时目录（/tmp 即弃
  或 Session 测试沙盒），禁入工作区/入仓；真 RAW bracket 灰卡两点标定 = Manual-Only 单次确认项
  （research §1.2），不阻塞、入 SUMMARY 登记。
- **源永不可变**（CONVENTIONS 非破坏性红线）：合并服务对源文件只读；一切产物是新文件；重复合并
  = ExportNamer 递增出新文件，禁覆盖。
- **one-way 格式锁 + UInt64String**：sidecar v4 additive 升级；一切入盘 UInt64 哈希 decimal String
  （L013）；旧 v3 文档读取零害断言必做。
- RESEARCH/CONTEXT 未覆盖细节（进度 toast 形态、dialog 字段、行带宽 256 以外参数微调、ghost σ̂
  拍噪声模型系数）标注**执行期决策**入 `08-1-DECISIONS.md`，不臆造。

## Tasks

### T1 StackMergeService actor 骨架 + CIRAW 解码耗时首测

- **action**
  1. 新建 `LightamerCore/Sources/Stack/StackMergeService.swift`（actor）。接口 =
     `merge(kind:sources:params:progress:)->URL`（**N 源 → 1 float32 文档**，D-08-CONTEXT-1
     Reversibility 的抽象位：Mertens/深度图后端只是末段替换，v1 只实现 hdr-merge 分派）。
  2. **专属低优先级 `MTLCommandQueue`**（Phase 11 export queue 惯例；服务自包含域——见纪律节 L031
     条）。进度/取消面复用 ExportQueue 形状：cancel epoch + `(done,total)` progressHook + 无自动
     重试/显式 `retry`。
  3. **失败分型**（research §12）：解码失败 = 硬失败（typed error + retry 入口）；对齐失败 = 降级
     续跑 + provenance 标注；写盘失败 = 硬失败（retry）。源图只读解码，与 pixelpipe 缓存面零共享
     （唯一耦合 = 内存压力，enforceBudget 60s sweep 既有兜底，零新代码）。
  4. **解码两遍流式形状**落位：对齐遍（逐源解码 → 逐级下采样只留位图 → 释放像素面）+ 合并遍
     （逐行带解码/累积）——3-bracket = ×6 次 CIRAW。
  5. `SessionBrowserView` 多选 context menu「HDR 合并…」挂最小入口（menu → 确认 dialog：deGhost
     toggle → 入队 → 进度 toast）；T1 阶段 service 末段返回 typed `.notImplemented`，入口链路先通。
  6. **CIRAW 100MP 单张解码耗时首测**（真实解码链，任意会话 RAW fixture）——预算表主导段钉数入
     perf.md（research §12 估 2-5s/张，R7 消解）。
- **证据**：`StackMergeServiceTests`——cancel epoch 三 gate/progress 序列/三失败分型/源只读（源文件
  mtime+字节前后断言）/menu 入口到 service 的 App 层接线走查；perf.md 开账（解码首测行）。

### T2 MTB 对齐 + EXIF 一致性预检 + 曝光比例自检

- **action**
  1. 新建 `LightamerCore/Sources/Stack/MTBAlign.swift`——research §2.1 参数定表逐项落：
     8 级金字塔（100MP → 91×68 底层）；RGB→luma（0.2126/0.7152/0.0722）线性域直接；256-bin 直方图
     中位数阈值（位图 1bit/px）；搜索逐级 ±1px 粗到细（底层独立 ±1，每升一级 ×2 后再 ±1 → 全res
     覆盖 ±128px）；packed UInt64 XOR + popcount，**重叠窗按 (dx,dy) 收缩**（P1 首版越界教训钉进
     实现）。参考数：ref 塔 0.45s + 每对 1.65s ≈ 3.8s/3-bracket 单线程 CPU（perf.md 对账）。
  2. **失败判定与降级**（§2.3）：最优 XOR 距离/像素 > 0.25 或命中位移 = 搜索界 → 不对齐直合并 +
     警告 + provenance `alignment: "skipped-low-texture" | "degraded"`；解错 ≠ 硬失败（三脚架位移
     ≈0 惯例）。**倾转 = v1 平移 only**（±1° 搜索作 additive 旋钮位保留，不进默认路径——research
     §17.2 降级裁决）。
  3. 新建 `LightamerCore/Sources/Stack/ExifPrecheck.swift`——§2.4 表逐行：机身/镜头/焦距/光圈/ISO
     严格相同；快门必须不同（bracket 本体）；ΔEV = `log2(t_ref/t_i) + log2(ISO_i/ISO_ref)`；光圈/
     ISO 不同 = 默认拒绝 + 用户 override 放行 + 警告（override 后 ΔEV 只算快门/ISO，光圈差进比例
     自检兜底）。
  4. **运行时曝光比例自检**（§1.2，R2 消解）：合并前在双方均未裁剪的重叠亮度带取中位像素，
     `median(pᵢ)/median(p_ref)` vs EXIF 预期 `2^ΔEV`；偏差 >5% → 警告 + `exposureRatioVerified=false`
     降级合并（权重照常）。
- **证据**：`MTBAlignTests`——合成 fixture 已知位移（(17,-11)/(-9,23) 同款）**精确命中**断言（含
  4×/0.25× 曝光差）；大位移收缩窗越界回归；失败降级 provenance 标注；EXIF 预检矩阵（同机同焦距
  同光圈同 ISO 异快门 PASS / 异光圈拒绝 / override 放行 / 异机身拒绝）；比例自检 >5% 降级。

### T3 Robertson 合并数学 + 行带流式 + HOLE/weight-map + float TIFF 写

- **action**
  1. 新建 `LightamerCore/Sources/Stack/HDRMergeMath.swift`（CPU 纯函数，golden 正本）——§1.1 权重
     终形：`w(p)=0 若 p≥0.995 或 p≤0.001；否则 exp(−(p−0.5)²/(2σ²))，σ 默认 0.2 参数化`；
     `weightNoiseFloor` additive 参数位默认关（§17.4 裁决）；`L̂ = Σwᵢ·(pᵢ/tᵢ)/Σwᵢ`。
  2. **HOLE 语义**（§1.3）：Σw=0 像素输出 0.0（黑）+ 同 Pass 产出 weight-map（单通道 float 临时
     面）；weight-map 零区 = HOLE/ghost 候选区；合并完成 toast 报 `holeFraction` 百分比。
  3. 新建 `LightamerCore/Sources/Stack/BandStreamer.swift`——**行带流式两遍**（§6 终形，R3 硬约束）：
     对齐遍只留位图（≈17MB/源全塔）；合并遍逐 256 行带解码/累积 `Σw` 与 `Σw·p/tᵢ`（float32 累积面
     ≈2.0-2.4GB 全图驻留唯一大头 + 行带缓冲 179MB）；`TilingPlan` 几何函数生成行带网格（tile 高 =
     band，不引入 in-pipe tile driver）。
  4. **float TIFF 分行 append 写**：`CGImageDestination` 逐带 append（EXP-01 既有写面；EXR 写出被
     零依赖红线封死不碰）。参考数：合并内循环 11.2ns/px → 100MP×3 ≈1.1s 单线程（perf.md 对账）。
  5. **§1.4 数值 golden**：合成 fixture 已知 L 集 × {1/4,1,4} 快门 → `|L̂−L|/L < 1%`（1% 噪声注入）；
     全源裁剪 patch → wsum==0（HOLE 检出）；ghost fixture → 单源 0.8/0.5 非裁剪偏离，k=3 残差拒绝
     后 `|L̂−clean| < 0.02`。
- **证据**：`HDRMergeMathTests` 全绿（上述四断言 + 权重双门边界值 0.995/0.001/σ 参数化恒等性）；
  内存常量断言（行带流式 footprint 增量 ≈ 常量——累积面 + 行带缓冲上界，防全驻回归）。

### T4 ghost mask：残差拒绝 + 膨胀 + RasterMaskRef 落盘 + Ghost Suppression 层

- **action**
  1. **残差拒绝数学**（§4.1，进 HDRMergeMath.swift）：线性亮度域归一化残差
     `rᵢ = |pᵢ/tᵢ − L̂| / max(L̂, ε)`；`rᵢ > k·σ̂`（k=3，σ̂ = 5% 噪声地板 + 拍噪声模型——模型系数
     执行期决策）→ 该源该像素权零化。**噪声域而非权重域**（帽沿梯度大阈值不平稳——research 定死）。
  2. 新建 `LightamerCore/Sources/Stack/GhostMaskWriter.swift`：偏离像素位图 → 3×3 膨胀 2 轮 →
     16-bit PNG 落 `<base>_hdr.tif.lra.masks/<maskID>.png`（`RasterMaskRef` 既有文件约定，
     maskHash = StableHash over PNG 字节——L013 decimal String）。
  3. **编辑闭环**：合并文档 `.lra` 初始 `layerStack` 带「Ghost Suppression」调整层，其 mask = 上述
     `RasterMaskRef`（Phase 6 层栈/蒙版面零新机制消费——反选/羽化/组合用户自理）。
  4. **de-ghost 关闭档**：`deGhost: false` → 跳过残差统计与 mask 生成（零 IO 零开销），层栈不含
     该层。N=3 统计弱局限写入 UI 文案 + provenance 注记（R6）。
- **证据**：`HDRMergeMathTests` 扩段——ghost 拒绝后 `|L̂−clean| < 0.02`（T3 golden 同源）；膨胀形态
  golden（单像素偏离 → 3×3 膨胀 2 轮形状）；PNG 落盘 + maskHash round-trip；`deGhost:false` 零
  mask 文件断言 + 层栈零 Ghost Suppression 层断言。

### T5 产物落位 + ExportNamer 防撞 + App 编排入口 + E2E

- **action**
  1. **落位 = 会话根**（research §3.2 采纳默认）：`<base>_hdr.tif` 落源文件同目录（会话根）；
     `Stacks/` 非保留子目录变体记 DECISIONS 观感位不采纳（语义零差）。
  2. **命名防撞**：复用 ExportNamer 惯例 `<stem>[_<tag>].<ext>` + 冲突 `-1/-2/-3` 递增
     （`ExportNamer.swift:53,82-83`）→ `<base>_hdr.tif` / `<base>_hdr-1.tif`；时间戳否决。
  3. **grid 可见性对位断言**（§3.1/§3.2）：会话根产物可浏览（`isExcludedDirectory` 根级非保留不
     命中）+ `.lra` 一律排除 + `.tif` 在 `rasterExtensions` 可浏览。
  4. **App 编排入口补全**（T1 骨架 → 全链打通）：多选 menu → dialog（deGhost/模式）→ service 入队
     → 进度 toast（holeFraction 完成回报）→ 产物入 grid；取消/重试面走 T1 actor 面。
  5. **E2E（编辑链零改验证**，§3.5）：产物进 grid → 打开 → RAWDecoder 保深读 → 常规
     preview/thumbnail/full/export 四管线 → 调整/history/sidecar 全可用——「合并后可继续在 linear
     Rec2020 中调整」（IOP-HDR-04 字面）零新机制成立。
- **证据**：`ProvenanceV4Tests` 落位/防撞段（同名递增 + 大小写不敏感惯例对位）+ E2E 走查用例
  （产物→grid→编辑→history 项存在→sidecar 写出）；SessionTreeScanner 对位单测三行。

### T6 sidecar v4 provenance + 源漂移检测 + 重合并重放

- **action**
  1. `LightamerSidecar.swift` `schemaVersionCurrent` 3→4：新增 **optional** `provenance` 字段
     （nil = 普通文档，round-trip 完全向后兼容）——research §3.4 终表逐字段：`kind`（hdr-merge |
     focus-stack | stack-average | stack-median | stack-sigma）/`algorithm{name,implementationVersion,
     params}`/`sources[]{relPath, stableHash, exposureEV}`/`alignment`/`exposureRatioVerified`/
     `holeFraction`/`createdAt`/`appVersion`。
  2. **格式纪律**：`stableHash` UInt64String decimal（L013，FNV-1a over 文件字节）；`relPath` 相对
     会话根（跨机/跨卷可迁）；`paramsData` base64 惯例不动；one-way 锁（旧读新 = 忽略未知字段，
     新读旧 = provenance nil）。
  3. 新建 `LightamerCore/Sources/Stack/ProvenanceReplay.swift`：载入产物时对 `sources[].stableHash`
     重算比对 → 不符 → 「源已变更」标脏 + 重合并入口（service 直取 provenance 重放同参）。
  4. **幂等语义**（§3.4）：重跑同源同参 = ExportNamer 递增新文件（不覆盖）；provenance hash 可检测
     「已有等价产物」并提示复用（检测面入 service，UI 提示形态执行期决策）。
- **证据**：`ProvenanceV4Tests`——v4 round-trip 逐字节（含 provenance 写读等价）/v3 旧文档读取零害
  /漂移标脏（改源一字节 → 检测命中）/重合并重放同参等价产物/provenance hash 等价检测/UInt64String
  decimal 序列化断言。

### T7 HDR-04 验证矩阵基座 + perf.md 首账

- **action**
  1. 新建 `Tests/LightamerTests/HDRPipelineMatrixTests.swift`——research §13 矩阵前两行（第三行真
     产物 preview 内存行 + lut3d 列留 08-5 T3 收口）：
     - HDR stack torture 图（ROADMAP:60 既有 golden harness）→ exposure → filmicrgb → sigmoid →
       toneequal 全链，数值 parity = float32 CPU 参考实现逐点容差（Phase 3 golden 形状）；
     - 合成 float32 文档已知值 patch（0.001/0.5/1.0/4.0/16.0/65504 通道灰阶 + RGB 彩条）→ 同上
       全链（lut3d 列本 plan 留空位，08-5 补）。
  2. **preview float32 预算基座**：真合并产物（T3 fixture 32F TIFF）流经 preview 管线，平面内存
     实测（参考 2560px ≈70MB/平面，`PipeResolution.swift:36-39` 注记）——实测数入 perf.md，预期
     合并不进 preview 缓存面新类（enforceBudget 五档零改前提复核，正式结论 08-5 收口）。
  3. **perf.md 首账**：CIRAW 解码首测（T1）+ MTB 3.8s + 合并 1.1s + 全程秒表（预算 ≈15-40s，
     **<60s 参考基准**只记不设门）+ 各段 vs research §0/§12 表对账列（偏差 >2× 归因注记）。
- **证据**：`HDRPipelineMatrixTests` 两行矩阵绿；perf.md 全表落档（对账列 + 归因注记如有）。

### T8 全量回归 + SUMMARY + DECISIONS

- **action**：全 suite 终轮（基线 **1636/10skip/0fail** + 本 plan 新增，0 fail；flake 归因条款见纪律
  节）；Resources/Localizable.xcstrings  # L025 zh/en 同批
  - TODO.md 开 Phase 8（HDR/Stacking & Effects）节 + 08-1 勾选；`08-1-SUMMARY.md`（任务表/
  commit 表/证据/perf.md 指针/灰卡两点 Manual-Only 登记位）；`08-1-DECISIONS.md`（σ̂ 拍噪声模型
  系数、dialog 字段集、toast 形态、Stacks/ 变体不采纳依据复核、行带参数微调、其余执行期决策）；
  新教训候选评估入 LESSONS。
- **证据**：测试计数（1553 → N，0 fail）；SUMMARY + DECISIONS 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| 服务骨架 | cancel/progress/失败分型/源只读/低优先级队列自包含 | `Scripts/test-direct.sh 'StackMergeServiceTests'` |
| 对齐/预检 | 位移精确命中（含曝光差）/收缩窗/降级标注/EXIF 矩阵/比例自检 | `Scripts/test-direct.sh 'MTBAlignTests'` |
| 合并数学 | L̂<1% / HOLE wsum==0 / ghost<0.02 / 双门边界 / 内存常量 | `Scripts/test-direct.sh 'HDRMergeMathTests'` |
| ghost mask | 膨胀形状/PNG 落盘 maskHash/deGhost 零开销档 | `Scripts/test-direct.sh 'HDRMergeMathTests'`（Ghost 段） |
| 落位/E2E | 防撞递增/grid 可见性三行/产物全链可编辑 | `Scripts/test-direct.sh 'ProvenanceV4Tests'`（落位段） |
| provenance | v4 round-trip/v3 零害/漂移标脏/重放幂等 | `Scripts/test-direct.sh 'ProvenanceV4Tests'` |
| HDR-04 基座 | torture 全链 parity + 已知值 patch | `Scripts/test-direct.sh 'HDRPipelineMatrixTests'` |
| perf | 解码首测 + 全程秒表 + 各段对账入 perf.md | 查 `.work/gsd/phases/08-hdr-stacking-effects/perf.md` |
| 回归 | 全 suite 0 fail（基线 1553+新增） | `caffeinate -dis Scripts/test-direct.sh`（全套） |

## 验收标准（Acceptance）

- [ ] `StackMergeService`：actor + 专属低优先级队列（自包含域，L031 红线节措辞遵守）+ cancel
      epoch/progressHook/显式 retry + 三失败分型（解码/写盘硬失败，对齐降级续跑）+ 源只读断言
- [ ] MTB 对齐：8 级金字塔参数定表逐项 + 合成 bracket 已知位移**精确命中**（含 4×/0.25× 曝光差）+
      收缩比较窗 + 失败降级 provenance 标注 + 倾转旋钮位（v1 平移 only）
- [ ] EXIF 预检矩阵全表（严格/必须不同/override 放行）+ 运行时曝光比例自检（>5% 降级 +
      exposureRatioVerified=false）
- [ ] Robertson 合并：双门高斯权终形（σ=0.2 参数化 + weightNoiseFloor 默认关）+ HOLE 黑输出 +
      weight-map + holeFraction toast + **行带流式两遍**（内存常量断言，累积面上界）+ float TIFF
      分行写
- [ ] ghost mask：残差拒绝 k=3 → |L̂−clean|<0.02 + 3×3 膨胀 2 轮 PNG 落 `RasterMaskRef` 形态 +
      Ghost Suppression 层挂接 + `deGhost:false` 零开销档
- [ ] 产物落位：会话根 `<base>_hdr.tif` + ExportNamer 防撞递增 + grid 可见性三行对位 + **E2E 产物
      进 grid 全链可编辑**（IOP-HDR-04 字面零新机制成立）+ App 编排入口（menu/dialog/进度/取消）
- [ ] sidecar v4：provenance optional 字段终表 + round-trip 向后兼容 + 漂移标脏 + 重合并重放 +
      UInt64String/relPath 纪律
- [ ] HDR-04 矩阵基座：torture 全链 parity + 已知值 patch 两行绿（lut3d 列留 08-5）
- [ ] perf.md：解码首测 + 全程 <60s 参考基准 + 各段 vs research 对账（只记不设门）
- [ ] 全 suite 0 fail（1553+新增）；每任务独立提交 + 边界查 config 开关；不 push；fixture 禁
      UNITEK；SUMMARY + DECISIONS 落盘
