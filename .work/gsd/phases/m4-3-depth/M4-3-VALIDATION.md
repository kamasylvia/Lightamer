---
phase: M4-3
slug: depth-mask
status: validated
nyquist_compliant: true
created: 2026-10-11
validated: 2026-10-11
milestone_closeout: M4
---

# Phase M4-3 — Validation（IOP-MASK-07 Depth 蒙版；**兼 Milestone 4 收口正本**）

> 体例对齐 `phases/m2-11-performance/M2-11-VALIDATION.md`（M4-1 同款）。**双重验收
> （config `dual_acceptance = true`）双路 PASS 后成文**：单 plan 批（M4-3-01）持
> zcode / omp 两路独立验收记录（`M4-3-01-ACCEPTANCE.md` +
> `M4-3-01-ACCEPTANCE-OMP.md`）。**翻账只认证据**：SC 三列对账正本 = 两路
> ACCEPTANCE + 双路定向终值亲跑数字；验收形态三件 = Depth 蒙版生成 ✓ +
> Phase 6 蒙版集成 ✓ + 资产分发链走查 ✓（ROADMAP §M4-3 行）。
> **SC 数字对账基线 = 双路定向轮亲证值**：Layers **411/3/0** + Library
> **626/4/0** + App **711/4/0**〔模型缺席态〕/ **711/2/0**〔装包态，golden 3/3
> 真跑全绿〕——三 bundle 合计 **1748/11/0**（基线 1717 → +31 =
> 8+9+3+3+7+1 精确对账；zcode 与 omp 两路独立复跑逐位命中）；全套 `--all`
> 推算 3366/16/0（3335 + 31）**未跑**——本批零 IOP/渲染管线触碰，定向三
> bundle 即终验口径（plan 边界亲证，orchestrator 批准轮不适用）。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit / golden / 直启宿主 / 独立数学复算轨 / 真网资产链走查 / perf 探针） |
| **Quick run** | `Scripts/test-direct.sh --bundle <Layers\|Library\|App>`（MEMFAIL 机检兜底；本批零 MEMFAIL，峰值 RSS 最高 2832MB 远离 8G 门） |
| **Full suite（phase 终轮）** | **定向三 bundle = 1748/11/0**（Layers 411/3/0〔167s/180s 两路〕+ Library 626/4/0〔75s/79s 两路〕+ App 711/4/0 缺席态 / 711/2/0 装包态〔359s/372s〕）；skip 全基线身份（3/4 skip = golden 资产门随模型在场与否翻转 + probe env 门 + absent-assets 门，双路取证）；`--all` 未申请（零 IOP 触碰） |
| **基线演变** | 3335/16/0（M4-1 终值；M4-2 删除批回落同基线逐位验证）→ 定向三 bundle 基线 1717 → **1748 精确**（+31：DepthMaskPipelineTests 8 + DepthMaskEditingTests 9 + DepthWorkerLegTests 3 + DepthGoldenTests 3 + Catalog/Store 7 + DepthPerfProbeTests 1）；Layers/Library 增量 `grep -c "func test"` 双路亲数 |
| **SC 数字面** | 精度门 abs-rel 实测 **0.0023 / 0.0029 / 0.0036**（门 0.01，≈3× 余量于 Apple 自报 0.0089）+ max-abs 0.0117（门 0.02）；确定性 = 同包同 units 双跑**逐字节**（6.9s 双跑 golden）；四段管线 numpy 锚 **10/10**（zcode 独立复算）+ **8/8 Swift 原文探针容差内**（omp；q95 锚 1-ulp 跨域差 9.54e-07 = o-2 注记）；perf forward 中位 **all 45.0 / cpuAndGPU 55.8 / cpuOnly 67.0 ms**（zcode 亲跑 40.8/55.6/67.7 同带）+ 端到端 **231.3 ms**（zcode 234.1）——`.all` 显著快于 `.cpuOnly` = ANE 在档，无 >10× 超带项；digest `3824a48c…d9da` / **45,759,882 B** 三源互证（本地 zip / 在库 sentinel / 远端 Release）——正本 = `perf.md` + 两路 ACCEPTANCE |
| **zh 对账** | +7 键（depth 族，xcstrings 尾块纯插入 `grep -c '^-[^-]'` = 0 双路亲证）；`zh-audit --check` **PASS**（1855 catalog = 1848 + 7） |
| **在案事件（本 phase）** | ①跨 bundle fixture 污染事故（本批引入→tempFixtureCopy 修复自证→**LESSONS L074**；执行批误记 L072 撞号→验收批 `57596d3` 重编号）；②golden 三假说两证伪一真因（参考块错索引→referenceOrder 单源；session 输出与 coremltools CPU predict 逐位一致）；③挂账 #6（M4-1 孤儿 `.lra` debounce 形态）验收轮发作一次→删孤儿单类 7/0/0 因果闭环→净树终值轮 711/2/0——非本批缺陷；④392 非 396 spike 勘误（D-4 亲核，全链按 392） |
| **GUI 证据** | `.work/gui-acceptance/m4-3/MANIFEST.md` = **Manual-Only**（三电路激活环境级全惰先例 M3-4 在案）；omp 路以代码面读码代证（四态 gate/入口 id/commit 缝），实机走查留用户侧（挂账） |

---

## SC 三列对照（ROADMAP §M4-3 验收形态逐件对表）

| SC | 判据（charter 正本） | 终态 |
|---|---|---|
| **SC#1** | Depth 蒙版生成 ✓（四段管线 + golden 三件套） | **Delivered**：`DepthMaskPipeline` 四段纯函数（percentile [10,95] → 归一 → (r−0.48)/0.22 窗 → smoothstep）与 Lumen `selection.py:71-74` 逐行同构（numpy 12 锚 zcode 独立复算 10/10 + omp Swift 原文探针 8/8 容差内；两级靶近区 10.25% 过 m6 ≥10% 门；斜坡 golden 带内全软/带外饱和/全程单调）；golden 三件套全绿——精度门（abs-rel ≤ 0.01 实测 0.0023-0.0036 + max-abs ≤ 0.02 实测 0.0117；两排除件 = 域/余量裁定非调门凑数）+ 确定性门（双跑逐字节）+ worker 端到端 round-trip；守卫 (a) 真负测门 + 守卫 (b) = NaN backstop only（数学不可达论证双路独立复核成立，coverageFloor 参数缝在册） |
| **SC#2** | Phase 6 蒙版集成 ✓（raster 通道 + worker 三腿 + crash-safe） | **Delivered**：产物走 IOP-MASK-03 raster 通道零改动（16-bit PNG + StableHash + `RasterMaskRef.invert` 近/远糖）+ `commitRasterMask` 唯一缝（竞态守卫 commit 缝）；worker 第三腿——`ModelAssetManifest.family` 派生单源判别式（clip 先判优先序）+ 六 profile 穷举测试 + `AIWorkerMain` 三臂分派 + crash hook 在资产解析之前（depth 免费生效零改动）+ CompatRecord 注入链 respawn 降档 + `runDepth` 降档链 + `floatPlane` half/F32 双格式 isfinite → `nonFiniteOutput` typed；**`AIWorkerProtocol.swift` 全批零 diff 亲跑**（PATH 通道复用，envelope 测试钉死 payload 键集恰 {inPath, outPath}）；HEADLESS import 白名单四项 + App target 产线 `MLModel(` 构造点 grep 门（仅 worker 两文件，CLIP 经 Core 封装） |
| **SC#3** | 资产分发链走查 ✓（Release 分发 + 许可/完整性 fail-closed 全链） | **Delivered**：digest `3824a48c…` / 45,759,882 B **三源互证**（本地 zip 亲算 == 在库 `ModelAssetDigests.generated.swift` sentinel == 远端 Release 亲下载复证〔zcode〕/ gh size 交叉〔omp〕）；确定性打包（fixed mtime + `zip -X` + 排序条目，两次完整构建逐字节一致申报 + 本地==远端旁证）；MANIFEST.sha256 解包后 **5/5 OK** 双路亲算；Apache-2.0 全链（zip 内 LICENSE 全文 + NOTICE 三行署名〔Depth Anything authors HKU+TikTok / Apple Inc. / 两 HF URL〕+ manifest `licenseName` CatalogTests 钉死）；digest fail-closed 全链（其余 profile digest 恒 nil + `.digestUnpublished` 拒下载 + promotes/fail-closed/checksum-mismatch 三 Store 测试）；**真下载端到端走查**（删安装位 → 真网 `ModelAssetStore.download` → notInstalled→installed → ditto 解包 → DepthSession 生成一轮 812,232 B header 518×392 → SHA 逐位一致，DECISIONS §8）；零模型字节入仓（`git ls-files` 机检双路零命中 + 零新 SPM） |

## 七项生效值对照（`M4-3-CONTEXT.md` 裁决记录 2026-10-10 OQ-1..7 全 A + D-1..D-5 低分叉五项 → 落点终态）

| # | 生效值（OQ 裁决） | plan 承载 | 终态 |
|---|---|---|---|
| 1 | OQ-1：DA V2 Small Apple 官方 CoreML F16 直采（零转换） | T1 | **落地**：第六 profile `depthAnythingV2SmallF16`（HF revision `cfef6f6f2a` 锁定）；F32 官方件同形直用为精度门参考（无自转） |
| 2 | OQ-2：GitHub Release 分发（不内置） | T1/T6 + §8 ops | **落地**：`ai-models-v1` 追加资产 + 下载态/置灰门既有链；bundled 档留演进口未预付 |
| 3 | OQ-3：M2AI-10 worker 进程隔离（第三推理腿） | T3 | **落地**：family 三腿分派 + crash-safe 隔离（crash-safe 对 depth 免费生效亲证）；协议零 diff |
| 4 | OQ-4：单「深度」入口 + Lumen 固定参数（0.48/0.22 窗 + 10/95 分位）；近/远 = invert 糖 | T4/T5 | **落地**：MaskToolbarView Depth 组单入口四态（entry/download/progress/retry）+ 参数 v1 常量 + 远景 = invert 既有位（零新代码） |
| 5 | OQ-5：v1 双线性 + 既有羽化（guided filter 挂 V2） | T2/T4 | **落地**：AIMaskResample 既有通道 + 羽化收尾；guided filter 走查观察项挂 V2（见挂账 #4） |
| 6 | OQ-6：golden 三件套（abs-rel ≤0.01 + 逐字节确定性 + 合成靶语义） | T6 | **落地**：门值三在门 + 双排除件卫生裁定 + referenceOrder 错索引修复后全绿（特殊事项 #2） |
| 7 | OQ-7：additive optional `inputShortEdge`（非正方形 typed 承载） | T1/T3/T4 | **落地**：五旧 profile 零漂移负测钉死 + (518, 392) 消费 DepthSession init 与 service 调用点同源（m2 全链；392 勘误兑现） |
| — | D-1..D-5 低分叉（生成器不占 iop 槽位 / typed error 严格 / 四段纯函数 Core 级 / 静态形状预处理亲核 / 构建期工具链零运行时依赖） | 全批 | **落地**：V50Order/pixelpipe 零触碰（红线清单亲跑）；`noDepthStructure`/`inferenceFailed`/`modelNotReady` typed 面；`DepthMaskPipeline.swift` Core 级纯函数；D-4 spike 亲核预处理已烘焙（臂 a，无 CPU 侧归一化代码）；运行时零新依赖（Project.swift 依赖面零 diff） |

## 双重验收记录（dual_acceptance 双路，串行）

| 路 | 结论 | 要点 | 与另一路分歧 |
|---|---|---|---|
| **第一路：zcode subagent**（`M4-3-01-ACCEPTANCE.md`） | **PASS / 0 error + 2 minor** | 亲跑四轮对表（Layers/Library/App 缺席/App 装包净树终值逐位）+ 四段管线 numpy 12 锚独立复算 10/10 + worker 三腿/crash-safe/协议零 diff 亲读 + 资产链亲算亲下载复证（digest/MANIFEST 5/5/Apache 全链/fail-closed）+ 红线 T8 清单机检亲跑全零 + m1..m7 抽验 4 项 + 十提交边界逐 commit 核 | **m-a** LESSONS 撞号 L072→**L074**（已修 `57596d3`，四处引用同批同步）；**m-b** 终验 App 711/4/0 实为模型缺席态、skip 身份旁注错位（XCTest Executed 含 skip 两态同形）——账面口径勘误，SUMMARY §3 验收批已补注；挂账 #6 发作一次因果闭环归 M4-1 |
| **第二路：omp**（`M4-3-01-ACCEPTANCE-OMP.md`） | **PASS / 0 error + 2 minor** | 定向复跑 Layers/Library 逐位（180s/79s 零 MEMFAIL）+ numpy 8/8 + **Swift 原文探针独立复算** + 守卫 (b) 严格论证加强（舍入 1-ulp 不动批量覆盖）+ digest 亲算/MANIFEST 5/5/远端 size 交叉 + 读码抽查（family 单源/三腿/isfinite/可容性/提交边界）+ zh `--check` PASS 复证 | **无实质分歧**；**o-1** 沿用 m-b 勘误认可；**o-2**（本验新增，测试口径）`[1..10] q95` 锚 Swift f32 lerp vs numpy f64 差 9.54e-07、对 1e-6 门余量仅 4.6%——跨域 1-ulp 巧合门值，建议改显式 ulp 语义容差或 L048 `Double(Float(x))` 纪律，不阻塞；「逐位命中」措辞勘误 = 门内通过（实质成立） |

两路全部 PASS、零 error、零未订正 minor（m-a 已修闭环；m-b 账面勘误随验收批落账；o-2 注记不阻塞）。

## Per-Plan Map（M4-3-01）

| Plan | 交付 | 终态 commits | 验收 |
|---|---|---|---|
| M4-3-01 Depth 蒙版批 | ①资产链（第六 profile + `inputShortEdge`/family 判别式 + 确定性打包脚本 + digest 真值）②worker 第三腿（DepthSession 臂 a + isfinite + 三腿分派 + runDepth 降档）③四段 Core 纯函数管线（Lumen 同参 + 守卫 (b) NaN backstop 事实）④App 编排（DepthMaskService 四态 gate + ditto resolver + toolbar 入口 + xcstrings 七键 + commitRasterMask 唯一缝）⑤golden 三件套 + perf 探针 + Release ops + 真下载走查 | `814fc97`/`b7f2598`/`22872ea`/`97e2d67`/`98de649`/`ec4894f`/`b615636`/`dda9433`+`bfdeff9`（fix test 污染）+`0355e65`（SHA 勘误）+ 验收批 `57596d3`（L074 重编号）+ 落账 `d053a60` | 双路 PASS / 0E（m-a 已修；m-b 勘误在案；o-2 注记） |

零红线域终态：`git diff d2e234a..0355e65` 双路亲跑零命中集 = Sidecar/、Aces2Kernels.metal、MaskEdgeKernels.metal、DrtRecord、HistoryStack、HistoryHash、LayerEditingState、NodeGraphCommand、**AIWorkerProtocol**、V50Order、Registry（LightamerIOP）、Export/（六格式矩阵全目录）；全 `.metal` 零新增零 diff；Project.swift 依赖面零 diff（零新 SPM）；仓内零模型字节；IOP/IOPParity 零触碰（零渲染管线面，零漂移天然成立）。GPL（Lumen MIT 只读借鉴公式语义、代码不复制）/Apache 资产链合规（NOTICE 随包）；`.xmp` 零读写删。

---

## 挂账总汇编（M4-3 单一移交清单，与 M4-1 六项合并为 M4 收口移交面）

1. **m-b 口径勘误（已修，账面注记）**：终验 App 711/4/0 = 模型**缺席态**轮（4 skip = 3 golden absent + 1 probe）；装包态 = **711/2/0**（skip = probe + absent-assets）。XCTest `Executed` 计数含 skip 致两态同形——SUMMARY §3 验收批已补注 + zcode ACCEPTANCE §8 在案；交付面无缺陷（golden 门值 T6 真跑 + 验收装包复跑 3/3 全绿双证）。
2. **o-2 复算余量（测试口径，omp 新增）**：numpy 锚 `[1..10] q95` 一锚 Swift 侧差 9.54e-07、对 1e-6 容差余量仅 4.6%（f32 lerp vs f64 跨域 1-ulp）——门值是巧合值非推导值；后续改显式 f32-ulp 语义容差或 L048 `Double(Float(x))` 比较纪律；不阻塞交付（纯测试面）。
3. **enhancement 族 resolver 顺延（observation）**：release 档「zip→可用包」一跳仅 depth 腿补齐；enhancement 族待其 digest 发布批处置（DECISIONS §2/§4；hfFallback.file 对既有族语义不变）。
4. **guided filter 深边界糊观察项（OQ-5）**：GUI 走查 Manual-Only 行（`.work/gui-acceptance/m4-3/MANIFEST.md`）留用户侧实机走查；「糊可见」证据驱动挂 V2（Follow Edges 熔断先例同款实证纪律）。
5. **M4-1 挂账 #6 孤儿 fixture 形态延续（carried）**：Layers 基线族 debounce 写入泄漏（DECISIONS §7 遗留段）——验收轮发作一次 + 因果闭环（删孤儿 7/0/0）；untracked 不入 git 不阻塞；修复批归属随 M4-1 挂账 #6 原账。
6. **远景第二入口（零成本后补糖）**：invert 位已承载「远景」；如走查反馈需要独立入口再补（DECISIONS 注记，无当前用户面）。

## nyquist 覆盖判断

- **判定：`nyquist_compliant: true`**。SC#1/SC#2/SC#3 每条均有 ≥1 机器锚
  （DepthMaskPipelineTests 8 + DepthGoldenTests 3〔精度/确定性/端到端〕/
  DepthMaskEditingTests 9 + DepthWorkerLegTests 3 + ModelAssetCatalog/Store 7 +
  DepthPerfProbeTests 1 + AIWorkerProtocol 零 diff 机检 + `git ls-files` 零模型字节机检）
  + ≥1 数字/实证背书（双路定向终值逐位亲跑 + numpy/Swift 探针独立复算 + digest 三源
  互证 + 真网下载端到端走查 + perf 四档实测落带）。
- 采样密度：单 plan AC 13 条逐条核验（AC#1-#12 双路抽查面成立 + AC#13 定向轮双路
  逐位全绿零 MEMFAIL）+ **两路独立验收**（zcode 亲跑四轮 + omp 定向双 bundle + 独立
  复算双工具）+ checker FAIL→PASS 处方批（m1..m7 全 ✅ 回勾 DECISIONS §9）先审后放；
  「无证据 ✅」零项。
- 数字对账：三 bundle 增量 1717→1748 = +31 精确（8+9+3+3+7+1 逐文件 `grep -c` 双路
  亲数）+ 两路独立复跑逐位命中 + App 两态机检（缺席 711/4/0 / 装包 711/2/0 skip 身份
  逐字吻合）——三源互证。

## 特殊事项入册（phase 级事件台账）

1. **跨 bundle fixture 污染事故（本批引入→修复自证→LESSONS L074）**：T4 commit 直驱
   测试直 load 共享 fixture → masks/sidecar 落 fixture 旁 → RasterEditFaceTests 竞态
   3/5 挂；修复 = tempFixtureCopy + 残留清除 + 三向对照实验存档；教训 = 「直驱 commit
   类测试的图片锚必须 temp 化」（执行批误记 L072 撞号 → 验收批 `57596d3` 重编号 L074）。
2. **golden 三假说两证伪一真因**：ICC 缺失分歧证伪（byte-diff=0）、ANE/CPU 设备分叉
   证伪（与 coremltools CPU predict 逐位一致 max-diff=0.000000）、真因 = 测试参考块
   错索引（gate 序 ≠ 生成器序）→ referenceOrder 单源修复；教训候选 = 「golden 对照
   先证参考侧对位，再疑产线」。
3. **D-4 spike 勘误（392 非 396）**：plan 从 HF 卡转抄 518×396，亲核实件
   imageConstraint = 518×392——全链按 (long=518, short=392) 落地 + m2 单源（manifest）
   承载（「预处理接线不凭文档转抄、plan spike 亲核」裁决的兑现样例）。
4. **守卫 (b) 数学不可达（plan KD-4 字面修正）**：过守卫 (a) 的平面
   P(v≥p95)≥~5% → 默认参数下 (b) = NaN backstop only（Lumen 可达因 refine 在计数前 +
   非深度腿不走 percentile 窗化）；代码照原样保留（parity + backstop + coverageFloor
   参数缝），双路独立复核成立（omp 加强为严格论证）。
5. **挂账 #6 发作与因果闭环（验收轮，非本批缺陷）**：孤儿 `srgb-matrix-8.tif.lra`
   （Layers 基线族 debounce 写入）在位致 App 首轮 711/2/1 → 删孤儿单类 7/0/0（8s）
   → 净树终值 711/2/0——M4-1 挂账 #6 已知形态的第三次亲证，归 M4-1 账。

## 授权记录（C 档第 3 停 VALIDATION 落签 + M4 收口）

- **授权先例**：D-07-3-T5-1——用户显式继续指令 = 终签核授权（M2-8/9/10/11 + M3 全系 +
  M4-1 VALIDATION 同款沿用；晨审可推翻）。
- **本次授权原话（夜间全自动批在案）**：「开跑，不要停」（M4-3 执行 + 双验收编排 +
  本 VALIDATION 收口同一授权链）。
- 依授权，本 VALIDATION 由 VALIDATION 成文 executor 落盘签核（`[gsd] paused=false /
  auto=true` 全程未动）；用户晨审可推翻本签核（推翻 = M4-3 签核作废回退，已交付面与
  双路执行/验收证据不受影响；翻账批同批执行，推翻时五正本翻账随 revert）。
- 签核 executor：ZCode VALIDATION executor（2026-10-10/11 夜间批）；**doc-only——零源码
  diff**（本批全 docs + omp 验收报告入库）。
- **呈报裁决点（禁静默）**：①o-2 测试容差纪律修订（显式 ulp 语义 or L048）归属；②
  guided filter 观察项实机走查安排（用户侧）；③enhancement resolver 顺延批立项时机。

## M4 milestone 收口（本件兼收口正本，单文档收口——不另跑 gsd-complete-milestone，避免双状态源）

- **M4（栅格与蒙版·收窄版）closed 2026-10-11**：M4-0..M4-3 全闭环——M4-0 charter ✅ /
  M4-1 TIFF 栅格开发链 ✅（VALIDATION signed 2026-10-10，终态 3335/16/0）/
  M4-2 Follow Edges V2 ⛔ 删除挂待定 closed-parked（2026-10-10 用户终裁，V2 代码面全撤
  回落 M4-1 基线逐位验证；IOP-MASK-06 parked，重启条件 = 可靠开源参考实现）/
  M4-3 Depth 蒙版 ✅（本件，定向终值 1748/11/0 双路亲证）。**M4 Ledger 4/4**（STATE）。
- **M4 数字对账链**：3174（M3 终值）→ 3335（M4-1 全套 VALIDATION 亲证）→ M4-2 删除批
  回落 3335 逐位验证 → +31（M4-3 定向三 bundle）→ 全套推算 **3366/16/0**（未跑 `--all`
  = 零 IOP 触碰，登记口径以定向亲证值为准）。skip 恒 16 零新增（三 bundle 11 skip 全
  基线身份双路取证）。
- **挂账移交（M4 收口单一清单）**= M4-1 六项（`M4-1-VALIDATION.md` 挂账总汇编：深影
  中性化 / HDR LUT 臂面 / CMYK·16-bit gray UX / 16-bit gray 补腿 / RGC 恒关晨审可翻 /
  omp-minor-1 测试卫生修复批）+ M4-3 六项（本件挂账总汇编）+ parked 行（IOP-MASK-06
  重启条件在 REQUIREMENTS）。
- **下一步 = 触发「全史瘦身手术」**：按 `research/HISTORY-SLIM-SURGERY-SPEC.md`，
  **主会话执行**（本 executor 无权动 git 史）——触发确认态随本批写入 GOAL-STATE 续接
  点；执行前须重算 strip 集（M3 收官预检曾证伪为 0；其后 M4-0 证据分仓已迁 2.2GB 大
  对象出仓 + M4-1/M4-3 批新增大对象历史版本，strip 集非空才动手；L070 家族坑 =
  filter-repo 后重 add remotes；push 收敛主会话）。

## 翻账与移交（本批同 commit）

- REQUIREMENTS：IOP-MASK-07 **Delivered 终态**注记（单目深度模型形态落地全账）。
- ROADMAP：M4-3 行 ✅ 闭环 + §Milestone 4 块收口头（M4 milestone closed）+ 文头站态行。
- STATE：M4-3 complete + **milestone M4 closed** + M4 Ledger 4/4 + plans 计数 148/148。
- TODO：M4-3 条目落账（[x] 补验收/VALIDATION 终态）+ M4 收官行。
- GOAL-STATE：续接点翻新 = **M4 closed → 触发瘦身手术（主会话执行，触发确认移交）**。
- 未 push；GUI app / 测试宿主进程零残留。

## 签核

- SC#1/SC#2/SC#3 + 七项生效值全项 **Delivered**（三列证据齐；数字对账 = 双路定向终值
  亲证基线 1748/11/0，全套推算 3366/16/0 未跑口径如实登记）。
- `status: validated` + `nyquist_compliant: true` + `milestone_closeout: M4`。
- **M4-3（IOP-MASK-07 Depth 蒙版）closed + M4 milestone closed**：单 plan 双重验收
  PASS / 0 error，挂账单一清单六项（m-b 已修注记 / o-2 容差口径 / enhancement 顺延 /
  guided filter 观察 / 挂账 #6 carried / 远景第二入口）+ M4-1 六项合并移交。
- 晨审裁决项：o-2 纪律归属 + guided filter 走查安排 + enhancement 批时机 + 签核推翻窗
  （原话授权在案）。
- **C 档第 3 停 = 夜间授权先例落签，晨审可推翻。**
