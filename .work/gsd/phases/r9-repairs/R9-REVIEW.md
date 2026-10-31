# R9 REVIEW（zcode 独立复审；omp 执行 lane 产出）

> 复审:zcode(R9 review lane)。审期:2026-10-31 13:0x 起。对象 = HEAD `3d1fc76a`、
> R9 交付 commit `cc00b623`、正本 `R9-{SUMMARY,DECISIONS}.md` + `omp-evidence/`(30 件)、
> 对照 R8-ACCEPTANCE-OMP §二(M-1 原文)。
> 方法:推翻证据强度逐要素核(读码 + 截图证据链 + 时长维评估)→ L014 fence diff 审 →
> C200 定罪读码复核 → ΔN 对账 + 封存面机检 + issue 核 → 全套独立复跑(guard G4 越门自查
> + `--monitor 21600` 伴跑,4054s)→ stash@{0} 全文读 + 与在册拷贝逐字节比对。

## 结论头

**PASS / 0 error + 1 minor + 2 obs**(R9 交付签核成立;推翻成立、L014 修复成立、
C200 定罪方向成立、零产线改动亲证;全套独立复跑见 §六)

| # | 职责 | 判定 |
|---|---|---|
| 1 | R8 M-1 推翻证据强度 | **成立**(§一;时长维缺口记 obs,见 RO-1) |
| 2 | L014 fence 修复 | **成立**(§二;rawBytes 先例逐字形同构 + 18/0/0 在档) |
| 3 | C200 定罪 + 路由安全 | **成立(条件性)**(§三;严格因果归 M8-3+,与 R9 自label一致) |
| 4 | ΔN +5 对账 + 全套复跑 | **成立**(§四/§六;复跑 4443/34/0 逐值一致) |
| 5 | 封存面/红线机检 | **成立**(§五;17 件 + 产品目录零 diff;issue #17 CLOSED) |
| 6 | stash@{0} 裁决建议 | **建议弃**(§七;同 blob 拷贝已在册,恢复成本 > 增量价值) |

---

## 一、推翻证据强度 — 成立

R8 M-1 原文三要素(R8-ACCEPTANCE-OMP §二)逐项对照 R9 反证:

| R8 断言 | R8 观测条件 | R9 反证 | 强度判定 |
|---|---|---|---|
| 视口全黑 35s+ | `32b`(走查截图)+ undo 后 `36b`(20s+) | R8 自家 `32b` sat 2.9% posterize(R8 截图证伪 R8 措辞)+ R9 `32c` vpmean 221.8(渲染帧)/`33` vpmean 172.8(占位帧)实测 | **强**:文件级 + 像素统计级双源 |
| 胶片卡三值 NaN | `34b` | R9 对**同一 R8 截图**放大重读 = `M 18.3 · Y 16.7 · ×1.00`,与 R9 `34-history` 同值 | **最强**:同物证重读,R8 系误读 |
| 持久坏态(重开不渲染) | direct-load 3 分钟+ `isDecoding=true`(`37c`),终态 `texture=present` 后探针自 terminate | 重开 direct-load `texture=present`(`probeF2-stderr.log` + `oslog-render-lines.txt` 2 hits/15 misses)+ 冷 build 窗机理(portra 269s / C200 278s 探针,`spectral-tcfit.sample.txt` LM 栈) | **成立**:R8 终态本就观测到 `texture=present`;「持久」系观测窗(35s/3min)短于 build 窗(4-5min)的归因错误 |

**时长维缺口(任务书明示审查点)——记 RO-1**:R9 复现链未实测「占位→渲染」的
精确恢复时刻(`32c` 09:47:49 / `33` 09:50:23 系截图 mtime,非渲染完成戳——SUMMARY
已自降断言「时序未精确计时」);undo 腿(R8 `36b` undo 后 20s+ 黑)未重走(R9 m-6①
已挂账)。静态 pointwise 契约对拍本身不含时间维,**不能单独**证伪「持久坏态」;
但持久坏态的证伪另有独立直接证据(重开 `texture=present` + oslog 渲染行),时长维
缺口因此降为机理补强项而非推翻成立性缺口。R8「35s 不恢复」与 build 窗 4-5min 的
量级自洽(portra 269s/C200 278s 双探针)足以覆盖原观测条件。

**seed 无帧形维——读码亲核成立**:`FilmTailPolicy.swift:152-164`(`seedFolding`)
四项折叠 = recordHash ⊕ tag ⊕ solvedPackHash ⊕ upstream,无 width/height/orientation
任何帧形维;两个公开入口(legacy/process-aware)仅 tag 值不同,折叠序同一。
D-R9-2 候选排除①成立。附带亲核:solve 缓存键(`ColorMatchSolveCache.swift:9`,
fnv(sourceStatsHash ⊕ referenceStatsHash ⊕ solverTag))基于 256-bin **计数**直方图,
转置不改变像素多重集 → 键转置不变——与 `layers-fenced-green.log:46-47` 的
R9PROBE ref/out statsHash 逐位同值(`14269763105167916199`)互证,排除②成立。

## 二、L014 fence 修复 — 成立

- **形态对齐**:`expandToFloats`(LayerCompositeTests.swift:946-973 区段)与
  `rawBytes` 先例(:96-110)逐字形同构——`makeCommandBuffer → commit →
  waitUntilCompleted` 后 `getBytes`,fence 内聚在 helper 内,全部调用点读回已沉降平面。
- **m-5 回注亲核**:bgra8 `precondition` 在位(浮点尾平面不再静默流入字节路径);
  通道序 `floats[R,G,B] = bytes[2,1,0]` bgra→RGBA 展开正确。
- **18/0/0 复跑在档**:`layers-fenced-green.log`(10:40 轮,18 tests 0 failures)。
- **「fence 掩盖真缺陷」排除论证采信**:同二进制同测绿↔红翻转(`layers-matrix.log`
  绿 vs `layers-composite-red-repro.log` 红 Δ0.7254902)+ 跨腿传染(film-off 腿亦曾红
  Δ1.0)——确定性产品缺陷应稳定复现,翻转/传染是读回竞态签名;fence 后多轮全绿
  (fenced 18/0/0 + 5leg 18/0/0 268s + 双臂 pass2 11/0/0)。L014 违反 → 读未定平面
  在 M2-5 已有先例教训,机理闭合。
- 注:红线「`readEdgeMap`/产线 L014 面」未触——本修复纯测试基建,产线零 diff(§五)。

## 三、C200 定罪 + 路由安全 — 成立(条件性)

- **读码亲核**:`SpectralBuildEngine.swift:730`(`var m = 50.0, y = 50.0` seed)、
  `:732`(32 轮)、`:745-746`(`min(max(·, 0.0), 250.0)` 双 dial 钳制)——申报
  「730-747,32 轮 seed 50,50,域 [0,250]」逐项吻合。
- **定罪值在档**:`probe-verdict.txt` C200 `solvedPrintCC=(0, 108.3, 250.0=CLAMPED)`,
  midgrayPrintRaw `(0.983, 0.988, 1.030)`(灰误差 ~3%);portra `(0, 33.1, 26.8)` 精确
  中性。同二进制同链(c200build.swift/portrabuild.swift 探针源在 evidence)。
- **实测锚佐证成立**:C200 实测锚 [0, 85.9, 108.3] 的 Y 分量 ~2× portra
  [0, 51.6, 52.5]——自近似 dichroic 下自求解需走更远,Y 撞 250 上限的机制量级自洽。
- **路由安全论断采信**:几何面脱罪由 §二机检矩阵独立承载(路径正确性与材料无关);
  爆色先于几何(R8 `31-film-enabled.png`,CW90 前)切断「几何诱发」因果。Y 钳制
  独立成缺,M8-3+ 修复不与几何面耦合——成立。C200 默认对 = 首排序对中奖
  (`FilmMaterialStore.swift:104-115`)加重优先级的论证采信。
- **条件性(m-3 三条如实入账,复核确认)**:①「3% 灰误差 → posterize(solarization
  级)」的机制链(scan 表退化/LUT 级联)未补像素值证据——R9 自己 label 为「相关非
  因果」,定罪方向可信(钳制事实 + 偏色工作点构建 + 默认对中奖)但严格因果留 M8-3+;
  ②solved-M 108.3 与实测锚 Y 108.32 四位巧合待 verdict 复核(疑 M/Y 误标);③真照片
  portra 对照腿缺失(绿轮全在合成 fixture)。三条均已在 D-R9-8 m-3 如实登记 ✓。
- RO-2:C200 × 几何的 pointwise 契约腿未实测(5 腿全 portra 对)——外推依赖路径
  正确性机检 + R8-31 引证,逻辑充分;M8-3+ 修 C200 后补 C200 契约腿顺路闭合。

## 四、ΔN +5 对账 — 成立

- `cc00b623` 亲数:5 个测试函数(flat-film-off / composite-film-off / empty-stack
  film-on / layered film-on v1 / layered film-on v3)+ `expandToFloats` helper,
  +393 行全加法,单文件 `Tests/LightamerTests/LayerCompositeTests.swift`。
- 算术:4443 = 4438(R8 基线)+ 5 ✓;34 skip 逐 bundle 对账(IOP 1 / IOPParity 10 /
  Layers 5 / Library 4 / Sessions 4 / Export 4 / App 6)与 r9-all.log BUNDLE 行一致 ✓。
- 落域:LayerCompositeTests = Layers 域既有登记文件(Project.swift:626 /
  BUNDLE-MAP:304,selfreview F 节亲核),零登记变更正确;`zh-audit` 不适用
  (文件零 `String(localized:)`,机检亲证)。
- 测试质量细读:三处 `FilmSolveCache.shared.invalidateAll()` 限 film 腿(order-isolation,
  BW golden setUp 先例);`inputXY` 后向映射 + ref/out 各按己方 dims 索引,手算 CW90
  逆映射闭合;容差 0.02 ≈ 5 LSB(8-bit 尾面),对原红 Δ0.73/0.86 有 36× 裕量;
  v3 腿 4-5min 光谱冷 build 成本注释在案(BWSpectralGolden 先例)。

## 五、封存面/红线机检 — 成立

- **17 件封存面**:DrtRecord/TerminalTailPolicy/DrtTailAssembly/PixelPipe/
  Lut3dKernels.metal/DrtEotf/ExportQueueContract/六格式导出矩阵三件/NodeGraphCommand/
  sidecar(LightamerSidecar)/HistoryStack/HistoryHash/PipelineDocument/V50Order/
  GradeCatalog(NodeOwnershipCatalog)——`git diff 5a1729b6..HEAD` 逐名 grep 零命中。
- **产品目录**:`App/ LightamerCore/ LightamerIOP/ Scripts/ Resources/ Project.swift`
  numstat 全空;R9 全范围唯一代码 diff = 测试文件 +393。
- **BUNDLE-MAP/Project.swift 零变更** ✓(numstat 无此二文件)。
- **issue #17**:CLOSED(2026-10-31T04:58:09Z),标题含 C200 Y-clamp 定罪,`fixes #17`
  在 commit body ✓。
- 工作区脏文件:`omp-r9-exec.log`(+35 行 omp lane 收口结论)未提交——随本 review
  commit 一并入库(账本面,免关联)。

## 六、全套独立复跑 — **4443/34/0 全绿(4054s),与申报逐值一致**

- guard:G4 BLOCK 越门(Data 18.3GB < 25GB)——按 D-R9-7 先例自查:free 72% 无 swap
  压力、G1 heavy=0(起跑前 ps 亲证)、增量构建(R9 轮容器复用)、SPM 离线;
  `--monitor 21600` 伴跑零 RSS-KILL,跑毕即停。越门记录于本节,交 orchestrator 追认。
- 日志:`all-runs/r9rev-{all,monitor}.log`。逐 bundle 对账(13:06→14:13,4054s):

| Bundle | R9 申报 | 本轮复跑 | 判定 |
|---|---|---|---|
| IOP | 814/1/0(6130MB) | 814/1/0(5819MB) | ✓ |
| IOPParity | 565/10/0(5830MB) | 565/10/0(4839MB) | ✓ |
| Layers | 536/5/0(1095MB) | 536/5/0(1169MB) | ✓(含 +5) |
| Library | 785/4/0(749MB) | 785/4/0(749MB) | ✓ |
| Sessions | 285/4/0(1208MB) | 285/4/0(1209MB) | ✓ |
| Export | 385/4/0(5248MB) | 385/4/0(5229MB) | ✓ |
| App | 1073/6/0(2832MB) | 1073/6/0(2832MB) | ✓ |
| **TOTAL** | **4443/34/0**(4068s) | **4443/34/0**(4054s) | **✓ 零 MEMFAIL** |

## 七、stash@{0} 裁决建议 — 建议弃(留档皆无损)

**内容**:`FilmDeterminismTests.swift` +337 行(`FilmLegM1DissectTests` 两测试:
leg-by-leg 重演 A/L/T2/T + black-box control)。被终止的并行 zcode lane 产物。

**关键事实(本轮亲证)**:
1. **stash 内容与 `foreign-determinism3-diff-1123.log` 同 blob**——两侧 diff 头
   `index e58639c7..25785962` 逐字节一致,blob `25785962` 双侧亲证。内容已有完整
   在册拷贝,弃 stash **零信息损失**。
2. **近似副本已在 HEAD**:`probe/m1-dissect-probe.swift`(337 行,canonical master)
   与 stash 仅 2 处差异——且是 **stash 版对、probe 版错**:`LayerStack.
   baseLayerSentinelID` 无此符号(真身 = `PipeCacheKey.baseLayerSentinelID`,
   `PipeCacheKey.swift:66` internal;LayerStack.swift 无转发,grep 亲证)。probe
   文件不入 target 零编译影响,但其自称 restore-safe master,恢复即编译错 →
   **记 RM-1(minor)**:修 2 行或加注记。
3. **evidentiary value 已被 R9 吸收**:D-R9-6 引用其三轮 dissect 绿
   (`layers-foreign-dissect*.log`,A/L/T2/T maxΔ=0.0)作为几何脱罪第三方佐证;
   本 review §一、§三的结论已再次消费该证据。
4. **恢复成本为负收益**:readFloats 形态为全局 drain 一次(非 per-readback fence,
   不合新惯例需改造);FilmDeterminism bundle 每轮 +~9-10min(2 测试 × 光谱冷 build,
   stash 注释自记 276s);断言面与已入册 5 腿重叠(black-box = LayerCompositeDriver
   全等价;dissect T 腿 = layered-film-on 同面),增量 = 诊断可读性(per-leg 平面)
   而非回归覆盖。

**建议**:`git stash drop`(或原样留存,皆无损);账本登记一行指向
`foreign-determinism3-diff-1123.log`。若 M8-3+ 调查需要 dissect 诊断面,从 1123 log
重放(API 名以 stash/1123 版 `PipeCacheKey.baseLayerSentinelID` 为准),勿从 probe
正本直接重放(2 坏名)。

## 八、Minor / Obs 清单

- **RM-1(minor)**:`probe/m1-dissect-probe.swift` 2 处 `LayerStack.baseLayerSentinelID`
  坏名(§七.2)。修法:改 `PipeCacheKey.baseLayerSentinelID` 或头部加「重放以 1123
  log 为准」注记。零产线影响(不入 target)。
- **RO-1(obs)**:推翻的时长维缺口——「占位→渲染」精确恢复时刻未实测(mtime 非渲染
  戳)、undo 腿未重走(m-6①挂账);持久坏态证伪不依赖此缺口(重开直接证据在),
  机理补强随 M8-3+。
- **RO-2(obs)**:C200 × 几何 pointwise 契约腿未实测(5 腿全 portra);M8-3+ 修
  C200 后顺路补。

## 九、签核意见

R9 三项结论(翻案 / L014 竞态 / C200 定罪)证据链经独立复核全部成立;推翻证据对
R8 三要素各自有独立承载(NaN = 同物证重读、黑 = R8 自家截图 + R9 像素统计、持久 =
重开直接证据),时长维缺口已如实入账不伤成立性;交付 = 纯测试 +5 腿 + 基建 fence,
封存面/产品面零 diff 亲证;域内自审 6 minor 回注真实性逐条核销(m-1/m-2/m-4/m-5 ✓,
m-3 如实留 M8-3+,m-6 挂账如实)。R9 交付签核 **PASS**;C200 Y 钳制本体路由 M8-3+
维持;stash 建议弃(§七)。
