# M8-3+ 双路验收 — 第一路（zcode lane 1）

**PASS / 1 error + 1 minor + 4 obs**（双路汇总裁决前，本路裁定单路属实的 error 1 条：allocator 生产零接线——修复或 DECISIONS 申报后可闭环）

> 验收对象：七 commits `0b9f480d`..`17ce3d6a`（omp 执行 + 域内自审 PASS/3E+12m 收敛）。
> 方法：AC 逐条 file:line 独立核对 + D1-D13 质询 + 封存面/红线机检 + 全套独立复跑
> + 反自取消双探针（主树掏空还原法）+ 自审真实性抽核。工作树探针后零残留
>（`git diff --stat` 空）。
> 审期：2026-11-01 01:40 → 03:40。

## 一、全套独立复跑（锚亲核）

`Scripts/machine-guard.sh` PASS（heavy=0 / free=50%；G4 disk=? = 透明越门先例）
+ ps 清零亲核 + `machine-guard.sh --monitor 21600 &` 全程伴跑（零触发）+
`caffeinate -dis test-direct.sh --all`（02:03:15 → 03:19:39，4195s）：

| bundle | 本轮实测 | executor 锚 | 判 |
|---|---|---|---|
| IOP | 836/1/0 | 836/1/0 | 逐位一致 |
| IOPParity | 578/10/0 | 578/10/0 | 逐位一致 |
| Layers | 540/5/0 | 540/5/0 | 逐位一致 |
| Library | 788/4/0 | 788/4/0 | 逐位一致 |
| App | 1102/6/0 | 1102/6/0 | 逐位一致 |
| Sessions | 285/4/0 | 沿收口轮 | 与 M9-2 同值 |
| Export | 385/4/0 | 沿收口轮 | 与 M9-2 同值 |
| **TOTAL** | **4514/34/0** | 预期 4513/34/0 | **差 1 = 上游账面勘误（见 obs-o1）** |

零 MEMFAIL；peakRSS 峰值 IOP 5777MB < 8G 运行门。ΔN 重数：`git diff` 新增
`func test` = 52 / 删除 = 0 —— ΔN=+52 精确。

## 二、AC 逐条对账（file:line 亲核）

### T1 求解加固 — 7/7（A2 降级 = D1 申报）

- A1 ✓ `SpectralNeutralSolveTests:104-161`（160 triplets + 反转四项 50 + 缺席
  nil 三腿）；锚表 `NeutralPrintAnchorTable.swift`（M/Y 键序映射 :42 正确、
  typed fail-closed、会话 memo）。
- A2 ✓（降级形）`:165-205` 1e-9 带（worst 1231 ULPs ≈ 8.7e-12 CC）；K1 停手
  触发器解释性裁决见 D1 质询——判据隔离三数量级，裁定合理。
- A3 ✓（proxy 腿）`:209-250` 七 seed M 1e-7 / Y 1e-6 / res 1e-9 带；true-build
  clamped=true 腿走 T2（ClampedGolden `:135` 亲核在案）。注意 REPLAY proxy
  （regex 抽取+null-aware 投影+非归一曲线）与单测 proxy（FilmMaterialStore
  projected faces）是两条标定——前者触墙 250 / 后者墙内 197.5，D2 的本质
  即此标定差。
- A4 ✓（分布形）安全档 false `:200-202` + C200 true-build true（T2 腿）+
  pinned 分支不入 solve（`:254-268` 结构性钉）。
- A5 ✓ REPLAY-RECORD 12/12（本审复跑复现，RECORD 复原）。
- A6 ✓ `SpectralNeutralSolve.swift:30-31` dialLo=0/dialHi=250 + 测试 `:263-264`。
- A7 ✓ FilmSubRunKernels.metal 零 diff + filmRampPlaneHash `14_365_179_805_968_
  017_957` 在位且 FilmDeterminismTests 零 diff + M8-2 哨兵三件套亲核
  （ramp512/fixture/closure 三值全中）。

solve 抽取体（Newton 梯 :118-136）与引擎旧体同序同断点；黄金分割更新式两分支
区间收缩**手工验算正确**（c_new/d_new 复位代数逐项核实，40 轮收敛 ~5e-7 CC）。

### T2 守恒回退 + 反转路由 — 7/7（A1/A4 门弱化 = D4；A3 修前半缺 = D11）

- A1 ✓（弱化形）`SpectralConservationFallbackTests:97-157` 终值不爬升；
  搜索域含钳制点（域心 = 钳制点自由坐标）数学核实。
- A2 ✓ `:157-228` 灰误差 <0.5% + gain==ones 逐位 + 零漂移；gain 式
  `gain[c]=gm/raw[c]`（SpectralNeutralSolve.swift:287-293）**Π gain=1 几何均值
  归一手工验算成立**；sf_log2f(1.0) 精确归零验算（q=0 → Horner 链坍缩 →
  fma(·,0,0)=0）背书 ones=+0 恒等。
- A3 ✓（修后半）SpectralClampedGoldenTests `:135-145` clamped=true / Y=250 钉墙
  / 灰误差 <0.005 + 蓝切片 hash + 断层计数；修前钉值缺 = D11。
- A4 ✓（弱化形）`ConservationFallback:268-300` +1.0 band；directPositive solve
  （SpectralNeutralSolve:311-397 scan 腿目标）+ 双钳制 caption + 未知串
  tolerant（FilmRecord.swift:138-139 归一 nil）。
- A5 ✓（E2 修复后）`FilmPanelView.swift:271-278` 反转 film → picker 绑
  `convergedPaperStocks`（incumbent+2383/2393），else 分支保持 paperStocks。
- A6 ✓ disclosed amber 行（`FilmPanelView.swift:324+` readout 透出 clamped）+
  xcstrings 12 键尾块纯插入。
- A7 ✓ 断层计数（ClampedGolden `:102-121`）+ portra 对照走查配方（MANIFEST#4）。

**DELTA 记录（申报面）**：PLAN action 1 字面处方 = host 侧 print 表构造域乘
gain；交付 = kernel 侧 log-add（u[36..38]，`SpectralFilmKernels.metal:642-652`）
+ PCHIP 表零动。SUMMARY 已申报（"PCHIP 表零动——bake 键诚实"）。数学面：两种
形态在 PCHIP 分段非线性下**不严格逐位等价**（LUT 节点整体平移 vs 插值后仿射，
高阶差分不同），但交付形态自洽（测量面 `midgrayPrintRawD` 与 kernel 消费一致，
engine :819-823 注释申明 by-construction）——obs-o5 记录，不判错。

### T3 空间载体 — 5/5

- A1 ✓ 五字段三面（`FilmRecord.swift:93-111/158-165/185-194` + hash 面；
  nil 缺席恒等 `FilmRecordSpatialTests:36-40`）。
- A2 ✓ sidecar v13（`LightamerSidecar.swift:269` + bump 注释链 :257-268；
  **例外①单 hunk 亲核：注释 + digit 12→13，纯净**；SidecarV13Tests 三面）。
- A3 ✓ seed 自动折（FilmTailPolicy `:57` recordHash = record.stableHash() +
  `:156` 折序；**5 腿全翻转** `FilmRecordSpatialTests:96-142`——m4 补齐亲核）。
- A4 ✓（census 形 = D6）bake 不折 `:175-207`（3 foldTag census + 无 spatial
  tag）；行为腿缺（同 D6）。优先级负测 `:147-171` 钉 record 面前提，消费层
  family-first 门在 `SpectralPayloads.swift:1181-1189`（orphan 腿）。
- A5 ✓ pristine/面板 off 默认。

### T4 grain 接谱 — 7/7（A1 主门降级 = D5；probe 未更新 = D8）

- A1 ✓（降级形）ramp512 hash 哨兵 `3613671270926763817`（与 M8-2 STATE 亲核
  一致）+ B1/B2 逐行 verbatim（自审对拍 + 本审 kernel 抽样背书）+ 28 对
  finite。**逐位主门厚度 = 1/28**（D5 挂账考古）。
- A2 ✓（E1 修复后）`SpectralGrainSublayer.referenceUm = 10.0`（:36）——上游
  `4d1fb6a95b:src/common/spektra_core.h:326 = #define SF_GRAIN_REF_UM 10.0f`
  本审独立对拍亲核；单测单源 + 钉值断言（SpectralGrainDeriveTests:119-126）。
- A3/A4/A5 ✓ Poisson 统计门 / CPU-GPU bit-exact / Teschner 稳定（全套绿 +
  kernel 抽样：hash 常量 0x7feb352d/0x846ca68b、Teschner 三素数
  73856093/19349663/83492791、Knuth 精确分支 λ<12、plain sqrt 纪律——
  与上游 grain.h **逐行 verbatim 本审亲核**）。
- A6 ✓ amount 0 恒等（`:734` 双跳过）+ 量纲桥。
- A7 ✓ 未触发（主线 b 一次过哨兵）。

### T5 宽模糊 + 腿 + 分配器 — 8/10（A6 = D9+本审 m-A；A10 = 本审 error）

- A1 ✓ plan 对表：k/ox/oy/lw/lh 逐字 + inv 表逐字 + minSigma fail-closed；
  σ_low TRUE-σ 偏离 = R-M83P-5② 授权（头注申报亲核）。
- A2 ✓ 方差扣减 box (k²−1)/12 + 插值 k²/6 两项，`_yvv_ref_variance` 不移植。
- A3/A4/A5 ✓ 拆双 kernel 等价 / 网格锚定 / CPU vs Metal 逐位（全套绿）。
- A6 ✗ 阈值重标探针未跑（D9 pending 申报）+ **跨臂端到端 golden 缺失**
  （本审 m-A：PLAN A6 要"两侧双臂各一 golden"，交付 = 单元级 trio golden
  （`SpectralWideBlurGoldenTests:169` 明注不测阈值面）；分发面
  `blurPlane` 零 hash 监控——探针②实证）。
- A7 ✓ halation still 基线 verbatim（strength 0.05/0.015/0.0、σ 65µm、
  core 2.2/2.0/1.6、tail 9.3/9.7/9.1——上游 spektra_sim.c:100-122 亲核）+
  三 bounce σ√k + decay (1/0.5/0.25)/1.75。
- A8 ✓（半交 = D8）taking diffusion 腿 + bank ≤11 分量 + 矩匹配；print
  座位零腿（B2 钩恒 0 off-identity 结构安全）。
- A9 ✓ 腿 off 恒等（nil/0 三面 + orphan 优先级）。
- A10 ✗ **本审 error**：SpectralScratchAllocator 生产零接线（详见 §四 E-acc1）。

### T6 写腿 + 探针 — 4/4（A2/A3 leg-2 PENDING = 挂批准轮，非缺）

- A1 ✓ 单 hunk（`PipeCoordinator.swift` scheduleSidecarWrite 前移；t6_probe
  三门 PASS 本审复跑复现：order/scope/siblings）。
- A2 ✓ leg-1 静态三门 + leg-2 配方 PENDING（MANIFEST#6——probe-gated 授权形态）。
- A3 ✓ m-6① 配方 PENDING（同上）。
- A4 ✓ B-1 注记 + v4 预留（DECISIONS 终式节两句话在位）。

### T7 收口 — 5/5（A2 带式差 1 = 上游账面勘误 obs-o1）

- A1 ✓ 冒烟 2 法（all-off finite 四对 + 三腿 armed 确定性）+ ΔN +52 越带
  申报（D10）。
- A2 ✓ 五 bundle 全绿（本审逐位复跑）+ 带式表达式申报（差 1 见 obs-o1）。
- A3 ✓ 红线机检全 PASS（本审复检：封存面 17 件仅 Sidecar 例外① + PixelPipe
  例外②单 hunk；双臂冻结；RenderProcess 零 diff + current=3 `:92`；FilmSubRun
  零 diff；GrainModule 零 diff；UserDefaults 零新键；kernel 16 = D7 申报）。
- A4 ✓ zh-audit 双 PASS（本审复跑：--check 1795/2128 + --self-test V17）。
- A5 ✓ MANIFEST 六配方（走查执行归批准轮）。

## 三、偏差 D1-D13 质询表

| # | 质询结论 |
|---|---|
| D1 | **接受**。K1 停手触发器字面（"任一安全档被 seed 移动收敛值"）的解释性裁决合理：K1 立意 = 多盆地真分叉，ULP 路径依赖（8.7e-12 CC）同盆地，1e-9 判据隔离三数量级。抽取零漂移主证形态由 build 级哨兵（ramp512 逐位）承载，链路完整。申报如实（message + 注释 + 测试改名）。 |
| D2 | **接受，定性 = 定标漂移，非功能风险**。推翻面：Evidence C triple（106.3/197.5/0%→108.3327/250墙/1.58e-2）+ §1.3 C200 Ymax 行。依据：REPLAY verbatim 重放 7 seed 同值 + **T2 真 build 独立实测 clamped=true/Y=250**（本审亲核 ClampedGolden 钉值）——双独立路径指向同一结论。C 位（单盆地）双标定下均成立。晨审可翻项：若 research proxy 标定才是真链头则 C200 或不触墙——但真 build 一手实测优先于静态 proxy；且 clamped 旗是运行时判定，无 research 印值依赖面。 |
| D3 | **接受**。PLAN T1 action 5 预设分支（<12 降 16，否则维持），反转档烧满 32 = 分支执行结果非偏离，登记合规（轮数门单测 `:304-316` 钉 trip wire + HOLD）。 |
| D4 | **接受**。A1 弱化理由（1D 墙约束解不可能胜 2D 无约束解——m10 数学正确）；A4 弱化理由（跨 target 残差不可比——PLAN 门本身错）。执行比 PLAN 更诚实，注释如实。 |
| D5 | **有保留接受（挂账须追踪）**。逐位主门 1/28 是实质证明缺口；缓解在位（B1/B2 verbatim 对拍 + fma 钉死 + fma 同源论证）。考古可行性已核：fused 28 对 hash 在 M8-2 时点**从未逐对存档**（当时只交三件套哨兵）——考古 = 历史 checkout + 构建轮，成本中等。挂账应有时限，建议 orchestrator 立项或限期。 |
| D6 | **接受挂账**（与 D5 同族：行为证明降级为源码 census）。census 本审复检在位（3 foldTag + 无 spatial tag）。 |
| D7 | **接受**。K7 预授权路径（扩预算申报），8 调用面全消费（自审 grep + 本审 kernel 抽样无死 kernel）。 |
| D8 | **接受挂账**。print-diffusion B2 座位半交（taking 有腿/print 零腿，off-identity 结构安全 + 注释诚实）；probe 沿旧测点（debug 通道语义未变）。挂账应入 GOAL-STATE 追踪。 |
| D9 | **接受 + 隐藏连锁补记**。100 起步值维持 + 三处注释诚实化亲核（WideBlurPlan:27-28 / Payloads:1256-1257/1715-1716）。**D9 申报未覆盖：PLAN A6"两侧双臂各一 golden"实为半交付**（跨臂端到端 golden 缺，本审探针②实证）——见 m-A。 |
| D10 | **接受**。ΔN=+52 本审 `git diff` 重数精确（52 增/0 删）；m11 逐文件对账吻合；honest over-delivery（T3/T4/T5 覆盖性超交），无注水证据。 |
| D11 | **接受挂账**。修后半钉值在案（clamped/Y=250/灰误差/蓝切片 hash/断层计数）；修前钉值无考古（posterize 修前形态）。影响 = 改善幅度不可量化，修后态功能正确不受扰。 |
| D12 | **接受**。B-1 注记 + v4 预留两句话 DECISIONS 在位。 |
| D13 | **接受**。E2 picker 绑定 + E3 RMS tag 接线修复本审亲核（含 1000 占位退役 grep 零残留）。 |

**质询总结**：13 条申报全部如实、影响面评估无夸大无缩水、无隐藏连锁——
除 D9 隐藏的 A6 端到端 golden 缺（m-A）外。**但 D 列表整体漏了最大的偏差**：
allocator 生产零接线（§四 E-acc1）——执行与自审双双未察。

## 四、独立发现（本审新发现，非自审 3E+12m 之一）

### E-acc1（error）：SpectralScratchAllocator 生产零接线 — R-M83P-6 红线"不得自裁换形态"违反 + 申报缺失

- 证据链：①全仓 grep（LightamerCore+App 排除 Tests 与 allocator 自身文件）
  `ScratchAllocator|\.borrow\(|slot.release` **零命中**——生产 dispatch 全部
  独立分配（`dispatchGrainGroup` rawBuffer/accBuffer/grainBuffer 三独立
  makeBuffer `:815-821`；`dispatchTakingDiffusion` acc/tmp/comp 三独立
  makeReadWriteTexture `:1212-1217`；wide staging float4Buffer 独立
  `:1288-1302`；B1 cmyPlane 独立 `:730`）。②唯一消费 = 测试
  （`SpectralWideBlurTests:103-135`：Slot 独立实例语义 + capacityPlan 纸面值）。
  ③纹理 = rgba32Float 16B/px（`makeReadWriteTexture:1745`）。
- 红线：OQ-M83-9 终式"串行复用槽"；R-M83P-6"分配器是本批唯一新内存纪律件
  ——执行中触『独立分配更易实现』= 不得自裁换形态"。实态 = 语义件交付
  （Slot typed 借还完整）+ capacityPlan 证明面在位 + **生产路径整段绕过**。
- 申报面缺陷：DECISIONS"分配器峰值：100MP 全开 3.2GB（2 rgba32F 平面）
  ≤ 3.5GB 门（串行复用峰值 = max 非 sum）"读作已接线形态的峰值声明——实为
  capacityPlan 纯函数纸面输出（其 max 口径只对接线后串行复用成立；实态独立
  分配 = sum 形态，capacityPlan 从未建模）。SUMMARY"分配器（100MP 全开 3.2GB
  ≤ 3.5GB 门）"同病。台账诚实性受损。
- 风险量化（粗算，100MP 全开三算子 on）：taking diffusion 单腿内同时活
  acc+tmp+comp（3×1.6GB）+ wide staging src/dst（2×1.6GB）+ rows/low 低分辨率
  ≈ **8.1GB 级**，可能超 8G 运行门（RSS 口径下 shared buffer 记账有不确定
  性，需实测裁定）。缓解：默认全 off（三算子 nil 零分配）→ 默认用户零暴露；
  on 档 golden 全部小 fixture。100MP on 档实跑从未发生（探针是纸面）。
- 处置建议（二选一，归 orchestrator 裁决）：①接线——生产三段 dispatch 走
  Slot 借还（R-M83P-6 终式本意）；②DECISIONS 补申报"分配器语义件交付、
  接线挂账 + 峰值声明改纸面口径 + 100MP on 档实测挂账"并接受形态偏离。

### m-A（minor）：抽稀跨臂端到端 golden 缺失（D9 申报面不完整）

- 探针②实证：分发掏空（恒 exact）与降阈（恒 wide）双探针下
  SpectralSpatialLegTests 6/0/0 + SpectralWideBlurGoldenTests 1/0/0 全绿——
  测试 fixture σ 全 <16px（plan minSigma fail-closed 回 exact），且分发面/
  跨臂组合零 hash 监控（grep 测试目录 blurPlane/dispatchSpatialPreLeg/
  wideEffectThreshold 零引用）。真实大图（diffusion σ>100px）走 wide 臂的
  渲染面无任何测试锚。两臂算术各自有单元级逐位保护（trio golden + CPU
  twins），缺的是组合面。建议补一条超阈端到端 golden（阈值置低 + armed 腿
  hash 钉值）。

### obs（不计数）

- **o1**：全套 4514 vs 预期 4513 的差 1 = **mcp-uq 上游账面勘误**，非本批缺陷。
  mcp-uq-FIX-VERIFICATION.md:101 一手记录 App 修复轮实测 **1092/6/0**
  （"+1 = 新增直测"），MCP-UQ-SUMMARY 沿用 review 轮 1091 → 基线账面 4461
  少记 1，真基线 4462 ⊕ ΔN+52 = 4514 自洽。建议 STATE/勘误记录一行修正
  （orchestrator 面）。本批 SUMMARY 诚实引用上游账面，无责任。
- **o2**：探针①实测推翻任务书预期（"锚 seed 掏空 → C200 回归真红"）：掏空
  后 SpectralClampedGoldenTests 2/0/0 + SpectralNeutralSolveTests 5/0/0 全绿
  ——C 位（单盆地 seed 不敏感）被**行为级独立实证**（锚 seed = 纯轮数加速器，
  行为零变 by design 宣称成立）。副发现：consult 接线面无直接测试监控（轮数
  收益无守护）——与"行为零变"设计一致，obs 级。
- **o3**：nil publishedRms 的 grain degrade 形态 = sig→0 → aGrain 走 1e-4 floor
  → npart = 100/1e-4 = 1e6（粒子极细 → grain 视觉近似消失）。typed degrade
  设计选择、注释诚实（"the sampler still runs"），但 28 stock 是否全有 RMS
  未核——若某 on 档 stock 缺 RMS，grain 静默无效果且无披露。建议挂 obs 追踪
  （RMS 覆盖面 census）。
- **o4**：T2 gain 消费形态 DELTA（host 表内乘 → kernel log-add）在 PCHIP
  非线性下与 PLAN 字面形态不严格逐位等价（高阶差分异），交付自洽且
  bake 键诚实收益真实——记录在案，晨审若翻按 PLAN 字面重做即回 host 乘。
- **o5**（补充 o4 之外）：m1 检查中 BuildEngine:118 残留 "bit-identical" 系
  T2 gain==ones 面注释（非 seed 面），语义成立（sf_log2f(1.0) 精确归零
  本审核算）——非 m1 残留。

## 五、封存面/红线机检（本审复检）

- 封存面 17 件：`git diff --name-only 0b9f480d^..HEAD`（57 文件）命中仅
  `LightamerSidecar.swift`（例外①单 hunk：v13 注释 + digit，纯净亲核）+
  `PixelPipe.swift`（例外②单 hunk：E3 RMS tag additive 1 hunk，
  `publishedRms: Int? = nil` 默认参亲核——nil tag = 旧路，行为零变申报成立）。
  其余 15 件零 diff。编码器三件（ExportFormatSpec/ImageIOEncoders/
  WebPEncoder）零命中。
- 双臂冻结：FilmSubRunKernels.metal 零 diff；RenderProcess.swift 零 diff +
  current=3（`:92`）；v4 未 mint（预留仅 DECISIONS 登记）。
- 哨兵三件套 + ramp512/fixture/closure 三值亲核全中；FilmDeterminismTests
  零 diff。
- GrainModule 零 diff（57 文件清单无命中）；CC 资产 MANIFEST 未触碰。
- UserDefaults 零新键（diff grep 空）；`runModal(` 0 命中；
  `LocalizationValue("prefix_` 0 命中；kernel 16 = D7 申报数。
- zh-audit 双 PASS（本审复跑：--check 1795 源键/2128 目录键 + --self-test
  V17）；xcstrings 2116→2128 纯插入（T2 6 + T4 2 + T5 4 = 12）。

## 六、反自取消双探针（主树掏空还原法，探针后零残留）

| 探针 | 掏空点 | 复跑 | 结果 | 定性 |
|---|---|---|---|---|
| ① 锚 seed | `FilmPrintBake.swift:628` 递入注 false | SpectralNeutralSolveTests 5/0/0 + SpectralClampedGoldenTests 2/0/0（C200×crystal 真 build 292s 重腿） | **零红** | C 位行为级实证（o2）；任务书预期不成立 |
| ② 抽稀分发 | `SpectralPayloads.swift:1262` 门注 false（+对照：阈 1734 钉 0 恒 wide） | SpectralWideBlurGoldenTests 1/0/0 + SpectralSpatialLegTests 6/0/0 | **双探针零红** | fixture σ<16px 全落 exact 臂 + 分发面无监控（→ m-A） |

两探针还原 `git diff --stat` 空；还原后无需重跑全套（源码 = HEAD）。

## 七、域内自审审计（SELF-REVIEW 3E+12m 真实性抽核）

- **3E 全部真实、修复全部完整**：
  - E1：上游 `SF_GRAIN_REF_UM 10.0f` 本审独立对拍（47 确为转录错）；
    修复 = 值改 + 单测单源（expected 从常量推导）+ 钉值断言 :126。✓
  - E2：修复前形态（View 零引用 convergedPaperStocks）与修复后
    （`FilmPanelView:271-278` 条件绑定）本审亲核。✓
  - E3：npart 反演接线（`sublayerRowsForGrain:996-1005`）+ 1000 占位退役
    （grep 仅注释命中）+ RMS tag runtime-only 不折键（FilmPrintBake 注释 +
    census 测试背书）。✓
- **4m 抽核（m1/m2/m4/m9）全部如实修复**：m1 测试改名 BandIdentity + seed 面
  注释零残留（BuildEngine:118 为 T2 gain 面另一语义，见 o5）；m2 三处注释
  诚实化亲核；m4 5 腿全翻转亲核；m9 heuristic 注释在位（SpectralNeutralSolve
  :333-337）。m3/m5/m6/m7/m8/m10/m11 = DECISIONS cure（D5/D6/D7/D8/D4/D10
  对应质询见 §三）。
- **自审漏检**：E-acc1（allocator 零接线）为自审 3E+12m+7obs 之外的本审
  独立发现——自审维度 1/2（封存面/冻结）未含"新纪律件是否实际接线"切口，
  属流程盲区非个例失误；m-A 同根（覆盖面切口未展开到组合面）。建议
  LESSONS 记一条：内存纪律件验收加"grep 生产消费"机检步。

## 八、结论

- **全套 4514/34/0 全绿**（七 bundle；五 bundle 与 executor 锚逐位一致；
  零 MEMFAIL；guard + monitor 纪律全程）。
- **AC 38/40 全核通过**（2 条挂账形态：T5 A6 = D9+m-A、T5 A10 = E-acc1；
  T6 leg-2/m-6① 为 probe-gated 授权 pending，不计缺口）。
- **D1-D13 申报纪律良好**（全部如实），但漏报最大偏差（E-acc1）。
- **自审 3E+12m 真实且修复完整**；漏检 2 条（E-acc1/m-A）已由本审补位。
- **建议裁决路径**（归 orchestrator）：E-acc1 二选一处置后，本批可收口；
  D5/D6/D8/D9/D11 挂账入 GOAL-STATE 追踪；o1 勘误行修正上游账面；
  m-6①/三戳 leg-2 + 走查 MANIFEST 六配方归批准轮执行。

## 复现命令摘要

- 全套：`Scripts/machine-guard.sh && nohup Scripts/machine-guard.sh --monitor
  21600 & nohup caffeinate -dis Scripts/test-direct.sh --all`（日志
  `all-runs/acc1-all.log`）
- 探针①：sed 628 行递入注 false → `test-direct.sh --bundle IOPParity
  SpectralClampedGoldenTests` → 还原
- 探针②：sed 1262 行门注 false / 1734 行 get{0.0} → `test-direct.sh
  --bundle IOPParity SpectralSpatialLegTests` → 还原
- 机检：`git diff --name-only 0b9f480d^..HEAD` + 哨兵 grep + zh-audit 双跑
  + `python3 evidence/{static_replay,t6_probe}.py`（RECORD 复原）
