# M8-3+ 修复轮独立 review（zcode lane，新阵容第二轮）

**FAIL / 1 error + 1 minor + 5 obs** —— 三 finding（E-acc1/m-A/o1）本体修复全数兑现且质量良好，但 E-acc1 修复 commit（`8fb4291e`）夹带**未申报的测试脱落**：`SpectralGrainGoldenTests` 4 法被移出 IOPParity target（E-fix-1），全套账本算术自相矛盾为旁证。

> Review 对象：四 commits `ef3e4aff`（o1 勘误）→ `8fb4291e`（E-acc1 接线）→
> `6be1e538`（m-A 跨臂 golden）→ `b8bbe9e5`（收口账本）。
> 正本 = `m83p-fix-retry-prompt.md` + `m83p-fix-lane-prompt.md` +
> `M8-3+-ACCEPTANCE.md`（E-acc1/m-A/o1 三 finding）+ SUMMARY §八 / DECISIONS
> 修复轮节。审期 2026-11-01。方法 = diff 逐 hunk + file:line 亲核 + 定向复跑
> 实测 + 封存面机检 + 暗面扫描（借用/归还非对称、异常路径、GPU in-flight、
> 并行串扰）。

## 一、E-acc1 接线核 —— 本体 ✓（八借点全接 + 复用断言测试在位且全绿）

### 1.1 接线面逐点（file:line 亲核，`SpectralPayloads.swift` @ HEAD）

验收报告四处分配面 → 交付为**八借点**（四处面拆得更细，覆盖完整）：

| # | 借点 | borrow | release | 腿 | 池键 |
|---|---|---|---|---|---|
| 1 | B1 CMY 平面（dispatchStageB） | `:747` borrowPlanes 1 面 | `:779`（尾 release，**无 defer**→见 obs-1） | `.stageB2` | rgba32F W×H |
| 2 | grain 工作集 raw/acc/grain 三 buffer | `:862` borrowBuffers 3 长 | `:892` defer | `.stageB2` | 字节长 |
| 3 | grain clump-blur 对 blurTmp/usmOrig | `:999` borrowPlanes 2 面 | `:1024` defer | `.stageB2` | rgba32F W×H |
| 4 | separable-blur r32 staging 对 | `:1135` borrowPlanes 2 面 r32 | `:1165` defer | `.stageB2` | r32 W×H |
| 5 | diffusion 三元 acc/tmp/comp | `:1348` borrowPlanes 3 面 | `:1377` defer | `.spatialPre` | rgba32F W×H |
| 6 | wide 五 staging src/rows/low/lowBlur/dst | `:1465` borrowBuffers 5 长 | `:1501` defer | `.spatialPre` | 字节长 |
| 7 | halation 四元 tmp/core/tail/comp | `:1742` borrowPlanes 4 面 | `:1775` defer | `.spatialPre` | rgba32F W×H |
| 8 | halation bounce 面（四元活时 top-up） | `:1857` borrowPlanes 1 面 | `:1878` defer | `.spatialPre` | rgba32F W×H |

- Slot mint 缝：`dispatchFilmChain` 入口 `:603` `scratch ?? Slot()`（注入可测，
  默认自建，调用点零改）；FilmMethodBox 注入面 `FilmTailPolicy.swift:349-357`
  （`runScratch` additive，init `scratch: Slot? = nil`）+ `:404-409` 穿
  dispatchSpectralFilmLeg。default-nil legacy 面保持 ✓。
- **生产逻辑零变化核 ✓**：nil-scratch 分支 = 原分配代码逐字节保持（八处
  else 臂与 `ac0157b1` 对照亲核）；池面几何逐字节等价（rgba32F 16B/px +
  `.shaderRead/.shaderWrite` + `.shared`，`makePlane` vs
  `makeReadWriteTexture:2000-2009` 同 descriptor；buffer 同
  `.storageModeShared`；byteLengths 表达式与原 `count*4*stride` 同值）。
  kernel dispatch 序零改。
- 微面直分纪律如实（param/curve/roi/weights ≤256 float 逐 kernel 直分，
  DECISIONS 修复轮节申报亲核）。

### 1.2 分配复用断言测试（`SpectralScratchWiringTests.swift`，4 法，IOPP 实跑 4/0/0）

- 法 1 pool 面（`:109-147`）：borrow/release 计数精确断言（3/0/wm3 →
  8/4/wm4）+ 异腿 typed refusal（`BorrowError.alreadyBorrowed(holder:
  requester:)` 枚举级断言）+ partial return 保 holder + 全还清 holder。
- 法 2 buffer 键面（`:149-167`）：按字节长键 + 4 borrow/2 hit。
- 法 3 单腿复用（`:171-201`）：fresh 3 → rehit 3、watermark 不涨、holder 清。
- 法 4 全链跨段（`:205-261`）：三腿 armed 注入 slot；hits>0 跨段复用、
  bufferBorrows>0、run 间 hits 增 watermark 恒、holder 终态 nil、
  textureWatermark ≤5（halation 四元+bounce = 峰）。
- 同尺寸复用命中 ✓ + borrow/release 计数 ✓ —— 任务书两条回归要求全兑现。

### 1.3 E-fix-1（**error**，本审独立发现）：`SpectralGrainGoldenTests` 静默脱落 IOPParity target

- **证据链**：
  1. `git diff ac0157b1..8fb4291e -- Project.swift`：`-SpectralGrainGoldenTests.swift`
     → `+SpectralScratchWiringTests.swift`（+2/-2，注释行夹中间）——**删旧文件行
     非加新行**。HEAD Project.swift grep `SpectralGrainGoldenTests` 零命中。
  2. 文件在盘且内容零 diff（`Tests/LightamerTests/SpectralGrainGoldenTests.swift`
     11317B，4 法，`ac0157b1..HEAD` 零 diff）。
  3. BUNDLE-MAP `:965` 仍登记 `IOPP 4 SpectralGrainGoldenTests.swift`（diff 未触该行）。
  4. **实测**：`test-direct.sh --bundle IOPParity 'SpectralGrainGoldenTests'` →
     **0/0/0**（脱落实锤；对照 WiringTests 同法 4/0/0）。
- **丢失覆盖面**（T4 grain spectral 接谱的测试锚）：①nil 面双臂哨兵逐位钉
  （`rampSentinel = 3613671270926763817` = M8-2 哨兵值，`SpectralGrainGolden
  Tests.swift:35,170`）——验收报告 T4 A1 的唯一逐位主门（D5 已挂"厚度 1/28"，
  脱落后**零逐位主门在跑**）；②28 配对 finite 广度（`:176`）；③on 分叉 +
  确定性（`:207`）；④amount-0 恒等（`:243`）。
- **账本算术自证**：SUMMARY §八写「全套终值 4516/34/0（基线 4514 ⊕ ΔN+6）」
  ——4514+6=4520≠4516；IOPParity 578→580 仅 +2，而新测试 4+2=6 法。
  唯一自洽式：4514 + 6 − 4（脱落）= 4516。executor 记账时未察觉自相矛盾。
- **定性**：修复轮纪律「生产代码改动仅限分配点接线」违反 + 申报缺失（同
  E-acc1 的病根：台账诚实性）。GrainGolden 行删除对 E-acc1 修复**无必要**
  （新测试直接加行即可）——疑似编辑事故，但无申报 + 账本矛盾使其升级为
  error 级。fix-all.log 的 4516/34/0 数字本身真实（脱落已反映），错的是
  ΔN 解释与 "封存面/覆盖无变化" 的隐含申报。
- **处置建议**（归 orchestrator）：①Project.swift `:347` 区加回
  `SpectralGrainGoldenTests.swift` + `tuist generate` + 重跑该类 4 法；
  ②SUMMARY §八 ΔN 表勘误（+4+2−4）与全套预期 4520 修正；③低成本，
  不动其它。

## 二、m-A golden 核 —— 本体部分兑现（矩阵 ✓ + 替身 ✓；无钉值 → m-fix-1）

- **矩阵覆盖 ✓**：两法四格——法 1（1024×768 非转置）wide-on（阈 16px）+
  off（阈 +∞ 全 exact）孪生 + wide 重渲 bit-identical；法 2（768×1024 转置）
  同构（partial wide，σpx 15–92 straddle 断言）。「转置/非转置 × wide on/off
  最少两法」字面满足。
- **阈值替身 16px 机制 ✓**：`SpectralGPUPayloads.wideEffectThreshold` =
  既有 lock-box（`SpectralPayloads.swift:1975-1997`，NSLock 包装 static，
  Swift 6 禁 static mutable globals 的合规形）；测试 defer 还原
  （`SpectralCrossArmGoldenTests.swift:190-191,243-244`）；直启宿主 xctest
  串行（test-direct.sh 无并行测试），无并行串扰面。生产门值（100 起步）
  零改 ✓。
- **σ 分裂派生 ✓**：`splitSigmaPx` 由 `bank()/pixelUm` 推导（`:138-153`），
  不断言硬值；`above>0 && below>0` 断言双臂同时在案。
- **m-fix-1（minor）**：**无 pinned hash 常量**。断言面 = finite 抽样 +
  wide≠exact 分叉 + wide 自洽确定性（`:213-215,258-260`）——分发面
  "活性" 有锚，但 **wide 臂算术漂移仍无端到端检测**（等变式改动双探针
  全绿）。仓内 Golden 两形态（GrainGolden 钉 `rampSentinel` 常量 /
  WideBlurGolden CPU-twin bit-identical `fma-pinned`）本测试皆无；验收
  m-A 建议原文「armed 腿 hash 钉值」未兑现；类名/域模式借 "Golden*" 名
  不符实。commit message 声称 "finally has hash monitoring" ——是
  determinism monitoring 非 golden monitoring，声明面过强。
- 缓释：单元级 trio golden（WideBlurGolden CPU twins 逐位）+ T5 A3/A4/A5
  仍在跑（本审 WideBlurGolden 1/0/0 复跑绿），wide 算术有逐位对拍锚；
  缺口只在**分发组合面**的漂移检测。钉值可后补（RECORD 轮或固定 seed
  录 hash）。
- **时长 obs**：CrossArm 两法 272s（exact 臂 1024×768 r≈370 直接卷积）
  ——IOPParity bundle +90s/轮量级，全套时长成本登记在案。

## 三、o1 勘误核 —— ✓

`MCP-UQ-SUMMARY.md` 一行改（全套 4461→4462 / App 1091→1092）+ 勘误注一行
（注明正本 FIX-VERIFICATION.md:101 + 一手实测）。正本 `:101` "1092/6/0，
+1 = 新增直测" 亲核一致。ΔN 语义（+0 测试）正确。单 commit `ef3e4aff`
免关联符合内部账本规则。

## 四、封存面机检 —— ✓

- `git diff --name-only ac0157b1..HEAD` = 12 文件（2 账本 md + 2 log +
  MCP-UQ-SUMMARY + FilmTailPolicy + SpectralPayloads + SpectralScratch
  Allocator + Project.swift + 2 新测试 + BUNDLE-MAP）；17 件封存面
  （DrtRecord/TerminalTailPolicy/DrtTailAssembly/PixelPipe/Lut3dKernels.metal/
  DrtEotf/ExportQueueContract/ExportFormatSpec/ImageIOEncoders/WebPEncoder/
  NodeGraphCommand/LightamerSidecar/HistoryStack/HistoryHash/PipelineDocument/
  V50Order/NodeOwnershipCatalog）**交集零**——验收轮两例外（Sidecar ①/
  PixelPipe ②）修复轮也未触 ✓。
- 双臂冻结：FilmSubRunKernels.metal / FilmDeterminismTests.swift /
  RenderProcess.swift 零 diff；`current = 3`（`:92`）未变；三个 .metal
  零触（kernel 数不变）。
- 默认全 off 维持：`runScratch` default nil + pristine record 全 off；
  off 档 B1 CMY 走池但同几何同格式行为等价（且默认链不入 spectral 路径，
  零接触）。
- zh-audit `--check` 本审复跑 PASS（1795 源键/2128 目录键）——修复轮
  零 UI 键，与账本申报一致。

## 五、回归复跑 —— ✓（定向；全套沿修复轮 fix-all.log）

| 类（IOPParity） | 本审实测 | 判 |
|---|---|---|
| SpectralScratchWiringTests | **4/0/0**（256s） | 新测试绿 |
| SpectralCrossArmGoldenTests | **2/0/0**（272s） | 新测试绿 |
| SpectralSpatialLegTests | **6/0/0**（288s） | 触面绿 |
| SpectralWideBlurGoldenTests | **1/0/0** | 触面绿 |
| SpectralLegForkTests | **6/0/0**（310s） | 触面绿 |
| SpectralGrainGoldenTests | **0/0/0** | **脱落实锤（E-fix-1）** |

全套沿修复轮 `fix-all.log`（4516/34/0，七 bundle；IOP/Layers/Library/
Sessions/Export 五 bundle 与验收锚逐位一致——修复轮未触其面，无需复跑）。
机器 guard PASS 本审亲跑；测试全程机器单重活纪律（串行直启）。

## 六、暗面扫描（omp 自审之外切口）

- **obs-1（低，卫生）**：八借点中唯 B1 CMY 用 `do{}`+尾 release（`:760-779`）
  **无 defer**——stageB1/grain/B2 抛错时 CMY 面不还池 + holder 不清。兜底 =
  Slot per-run（run 失败整 Slot 释放，无跨 run 泄漏、无资源外泄）；但同 run
  内若未来加错误恢复路径会踩异腿 refusal。建议 defer 化对齐其余七点。
- **obs-2（中低，口径）**：`Accounting.peakBytes` = **live 水位**（借出中），
  **不含池内 parked 驻留**——池面 parked 到 Slot 释放才还给系统；多几何 run
  （r32 staging、low-res buffers 不同长）的进程 RSS 峰值 = live + parked >
  peakBytes。48×32 实测全同几何巧合相等（水位 5 面 = 池 5 面）；
  DECISIONS「实测 peak 159744B」是 live 口径非 RSS 口径，登记措辞宜注明。
  另：capacityPlan 冻结纸面（max 口径）与 live 水位（实测口径）均非
  「进程 RSS 峰值」——E-acc1 原文要的「接线前后 RSS/分配峰值对比」实交为
  48×32 缩比池水位；**100MP on 档真跑仍未发生**，验收 §四 的 ≈8.1GB 风险
  只有结构面缓解（串行复用）无实测消解——归批准轮走查/实测挂账。
- **obs-3（低）**：`Accounting` 无 live 终态面（借出不还在计数上不可见，
  仅 watermark 峰值）——泄漏观察依赖 `holderForTesting`；WiringTests 每法
  已断言 holder 终态 nil，缓释在位。
- **obs-4（低）**：`releasePlanes/releaseBuffers` 不校验面归属 +
  `max(live−1, 0)` clamp 掩盖非对称归还（外来纹理可被池收养：几何匹配但
  usage/storageMode 未经本池 descriptor）。当前八借点逐点核过只归还自借面
  （defer 捕获的是 borrow 返回数组），无实际触发；纪律件宽容面，登记在案。
- **obs-5 ✓（正面）**：GPU in-flight 同步纪律核过——八借点 release 全部
  发生在最后使用 pass `await completed` 之后（grain usm `:1053`、wide up
  pass、separable/textureBlur 尾部逐函数抽验）；且 MTLCommandBuffer 自动
  retain 引用资源，Slot dealloc 兜底——回池无数据竞争、无 use-after-free。
- **obs-6 ✓（正面）**：`borrowPlanes` 分配失败路径（`makePlane` nil）先
  `releasePlanes(out)` 归还已借面再返 nil——同段已借面不泄漏；holder 由
  release 链清（live 归零）或保留（同段尚有活面）——语义正确。
- **并行串扰 ✓**：test-direct.sh 直启宿主（XCTestConfigurationFilePath 旧式
  单进程串行）+ bundle 串行——CrossArm 写静态阈值（lock-box）无并行污染面；
  defer 还原双保险（`:190-191,243-244`）。

## 七、结论与处置

- **修复轮三 finding 本体**：E-acc1 接线 ✓（R-M83P-6 兑现，八借点全接、
  复用断言测试真实且全绿）、m-A 矩阵 ✓（钉值缺 → m-fix-1 minor）、o1 ✓。
- **封存面/冻结/off/回归**：全绿全过。
- **新发现**：E-fix-1（error，GrainGolden 静默脱落 target + ΔN 账本矛盾）
  ——修复轮收口 commit 的「4516/34/0 + 账本」须勘误后方可视为干净收口。
- **裁决建议**（归 orchestrator）：
  1. E-fix-1 修复批：Project.swift 加回一行 + `tuist generate` +
     重跑 `SpectralGrainGoldenTests`（预期 4/0/0）+ SUMMARY §八 ΔN 勘误 +
     全套预期改 4520（加 4514⊕6 或记 4516⊕+4 两种口径择一并注明脱落史）。
  2. m-fix-1：CrossArm 补钉值（非转置 wide 面 pinned hash，RECORD 或
     常量转录）或 DECISIONS 申报「确定性+分叉为终态，钉值挂账」二选一。
  3. obs-1 defer 化 + obs-2 措辞注明（低优先，可并入 E-fix-1 修复批）。
  4. 100MP on 档实测维持挂账（批准轮走查面）。

## 复现命令摘要

- 脱落实锤：`Scripts/test-direct.sh --bundle IOPParity 'SpectralGrainGoldenTests'`
  → 0/0/0；`grep -n SpectralGrainGoldenTests Project.swift` 零命中。
- 定向回归：`machine-guard.sh` + `test-direct.sh --bundle IOPParity
  '<ClassName>'`（上表五类）。
- 机检：`git diff --name-only ac0157b1..HEAD` × 17 件封存面交集；
  `git diff ac0157b1..HEAD -- FilmSubRunKernels.metal RenderProcess.swift
  FilmDeterminismTests.swift` 空；zh-audit `--check` PASS。
