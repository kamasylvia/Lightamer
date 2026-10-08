# M3-3-03-ACCEPTANCE — FSIM golden 与收口批（wave 3）独立验收

> **结论头：PASS / 0 error + 2 minor（验收现场已修）+ 6 obs（非阻塞）**
> 验收：2026-10-09/10 夜间独立验收 subagent（零共享上下文，实测核验不轻信；
> 夜间全自动授权在案）。验收对象 = `2fee806..c5f5dce` 六提交（`9f4a649` fix →
> `6c83505` golden → `b10df2c` determinism → `94168f8` panel → `5a8a2f8` card →
> `c5f5dce` docs）。验收方式：**全套七 bundle 独立复跑**（独立
> `xcodebuild build-for-testing` RC=0 先行 + `caffeinate -dis
> Scripts/test-direct.sh --all` 亲跑）+ golden 四门/确定性门/生产修复逐门读码 +
> **独立数学推导与数值复算**（符号修复推导 + m≥2 根深缺陷 Python 独立复算）+
> `git diff` 密封面机检亲跑（真路径制）。未 push。

## 一、全套独立复跑（对账，亲跑）

| bundle | 亲跑 | 亲跑 peakRSS | 申报 | 判定 |
|---|---|---|---|---|
| IOP | **483/1/0**（157s） | 7207MB | 483/1/0 | ✅ 逐位一致 |
| IOPParity | **404/3/0**（453s） | 6002MB | 404/3/0（5999MB） | ✅ 计数逐位；RSS ±3% 带内 |
| Layers | **371/3/0**（156s） | 1149MB | 371/3/0 | ✅ 逐位一致 |
| Library | **598/4/0**（79s） | 614MB | 598/4/0 | ✅ 逐位一致 |
| Sessions | **279/4/0**（71s） | 1624MB | 279/4/0 | ✅ 逐位一致 |
| Export | **342/1/0**（197s） | 6436MB | 342/1/0 | ✅ 逐位一致 |
| App | **675/0/0**（355s） | 2832MB | 675/0/0 | ✅ 逐位一致 |
| **TOTAL** | **3152/16/0**（1468s） | — | 3152/16/0（1482s） | ✅ |

- **L055 双保险亲证**：末行 `OK (direct launch, no testmanagerd)` = 脚本 verdict
  ok（含 no-total-line/crash 签名机检全过）；零 MEMFAIL（峰值 max IOP 7207MB <
  8192 运行门）；skip 16 = 基线 16（零新增 skip）。
- **+27 两式互证亲算**：登记面 = BUNDLE-MAP 四行（IOPP 12 / LAYERS 5 / APP 6+4
  = 27，行内数与四文件 `func test` 实数一致——本波计数全对，wave-2 错账未重演）；
  运行面 = 逐 bundle Executed 增量（IOPP 392→404 = +12、Layers 366→371 = +5、
  App 665→675 = +10）= 27。两式吻合。
- golden/确定性/pristine 门全在终轮覆盖（FilmGolden 12 法于 IOPParity 轮、
  FilmDeterminism 5 法于 Layers 轮亲跑全绿）。

## 二、golden 门审计（本波灵魂，逐门）

**四门结构、钉值、活性断言、L048 纪律全部读码亲证**：

| 门 | 钉值（读码亲证） | 申报实测 | 审计判定 |
|---|---|---|---|
| 1a kernel vs 同表 CPU 采样 | 1e-4 相对（含 `measuredMax > 0` 活性断言） | 8.7e-5 | ✅ 门语义完好（见 obs-4） |
| 1b 烘焙表 vs 理想模型 | **凸性门**（≤1.5× 单元值域，400 探针）+ flat-cell 2e-2 + `flatProbes > 0` | 凸性零违例 / 6.2e-3 | ✅ 6.2e-3 落 M3-1-01 先例带（1e-3..1e-2）中值，互证成立 |
| 2 bake 体素级 | 1e-5 相对（LCG 常量种子 60×3） | ≤1e-5 | ✅ Float64 双侧、f32 存储拓宽唯一残差 |
| 3 置位曲线 | m=1 双侧闭式 1e-9 + m≥2 vs 独立二分 1e-8 + 单调/单侧臂渐近线 + 逐像素（core bit-exact / branch 2e-5 linear） | 全绿 | ✅ 联合双臂降单侧 = DECISIONS §5 缺陷适配（obs-6 独立复算确证非放水） |
| 4 中性闭合 | 通道散 2e-3 + 中灰量级面（0.1..0.3） | 1.4e-3 | ✅ 钉 = 实测 ×1.42，DECISIONS 登记口径一致 |

- **平滑域三重筛读码亲证**：邻域 LUT（clamp 平台面 + >4× 局部对比度 cell + 3×3×3
  邻域）/探针内带着陆（0.35 stop）/\|d\|≤0.25 插值域——rtne 外推（d ∈ [−0.5,
  0.5] 含负臂）对连续理想模型无界的机理成立，筛后地板才可测。
- **L048 落实**：门 1a/1b/4 比较全在 linear 域（placement 门 decode 回 linear）；
  f32 常数升维亲证（`Float(Self.sM)` 载体面 + `Double(u.*)` 参考面）。
- **复算独立性亲证**：ref* 全测试文件内自包含（曲线插值/三点投影/中性包/K 标定/
  SysC 反演/域界/ACEScc 传递逐一双写）；与产线公式同构但**迭代数与结构不同**
  （产线 60 步/共享 solver vs 参考 80/100 步/文件内闭包）= 独立双写非复制；
  常量单源一致亲核（sM=0.0085 / sY=0.017 / midGray=0.184，测试字面 = 产线
  `FilmFilterPackSolver` 常量）。零图像资产入库（受控输入程序化生成亲证）。
- **实测值捕获注记（obs-5）**：直启宿主吞 Swift `print`（`[FilmGolden]` 打印
  不达重定向 stdout）——验收亲跑可复核的是**钉值强制 + 活性断言**
  （1a/1b/4 门实测值无法从直启日志提取，本表实测列 = executor 申报值如实收录；
  门 1a 另做单测定向亲跑复绿 54.4s）。

## 三、生产修复 `9f4a649` 审计（本波灵魂之二）

- **数学论证独立推导确证**：m=1 着陆方程 K ∓ g(K−a; K−C) = t 通分展开得
  **K² − 2tK + t(a+c) − ac = 0 → K = t ± √((t−a)(t−c))**（我推导与 commit
  message 代数一致）；阴影侧有效根 = **t + √**（K > C 保 room 正）。数值复核：
  a=−7.5/C=−4.5/N=0.5 → 旧符号 K=−5.323（room 负、落点 −5.92 vs 目标 −4.0 =
  **1.92 stop 偏离**，与 commit body 探针数逐位一致）；修复后 K=−2.677、落点恰
  −4.0 精确。
- **红转绿**：回归钉 `testPlacementM1ShadowClosedFormLandsExactly`（6c83505）——
  旧符号下 knee 偏 2√((t−a)(t−c)) ≈ 2.65 ≫ 1e-9、着陆偏差 1.92 stop ≫ 1e-9，
  **倒置推演必红**（修复在前、测试在后同批，结构保证）。
- **零波及亲证**：①默认面 = Params() 0/0/2 早退 inactive（符号行不可达）；
  ②seeded rolloff 2 走 m≥2 臂，knee 被二分结果整体覆写（闭式仅赋值后被覆盖，
  注记「Newton seed」与实际不符 = 注释过声明，非行为面）；③既有测试零 diff 亲跑
  + `testM1ClosedFormLandsExactly` 只钉高光侧（sceneTopEV）、
  `testShadowSideSolvesSymmetrically` 只钉 m=2——「零 churn」申报成立；
  ④IOPP 404/3/0 全套亲跑复绿。

## 四、确定性门审计

- **键折叠精确值**：产线 `cacheKey` = `StableHash.fnvOffsetBasis` → pair 字节
  （withUnsafeBytes = 小端内存序）→ stats 字节 → modeTag UTF-8，`StableHash.combine`
  = canonical FNV-1a 亲读；测试独立双写同式，**精确值断言**（非判别）亲跑绿。
- **solve bit-identity**：双调 + 跨 fresh store 实例 bitPattern 全等断言在案亲跑绿。
- **跨 ROI 端到端**：周期夹具（48=4 周期）FULL vs A/B 两窗——缓存一条目记账断言
  （before+1 / +1 / +0）+ 三渲重叠列逐字节相等，全部亲跑绿；「stats=原始计数、
  解值比例不变」双面语义 DECISIONS §2 登记在案。
- **整数秩**：手算对表亲核（uniform 4/bin：total 1024 → P50 target 512 首达
  bin 127 / P25 256→63 / P75 768→191；`max(target,1)` 边界 quirk 与实现一致）。
- **哨兵**：`14_365_179_805_968_017_957` 于**本机亲跑精确命中**（管线渲染平面
  FNV 重算 = 常量）；重钉流程（DECISIONS 登记 → 重算 → 同 commit 重钉）入册。

## 五、Film 面板 + 只读卡审计

- **面板事务面**：三级读（live → history → carrier）单点 `record` 投影、
  `commit` 单漏斗（幂等点击零 item）、D-H1（`beginDrag/setLive/commitDrag`，
  Slider `onEditingChanged` 接线亲读）、面板侧钳制（CC 0-100 / 0-1 / ±3EV，Core
  不钳）——6 测亲跑全绿。
- **22 静态键 zh**（申报「26」系错账，minor-1）：film_* 15 + history_film_* 4 +
  editor_node_film* 3 = **22**，逐键 zh 值在册亲提取；`zh-audit --check` 亲跑
  **PASS（1557 source / 1795 catalog / zh complete）**；F-2 插值键禁令零命中亲跑。
- **注入式 optional 教训落地亲证**：`NodesPanelModel`/卡片 init 注入 weak optional
  （nil = no-op），`EditorToolRailView` 实传；DECISIONS §4 首版 crash 教训登记在案。
- **只读卡**：`filmCardID` 编译期常量 + `layout(includesFilmCard:)` additive 默认参
  （默认调用零改，FilmCardTests 钉死）；**NodeKind 零新增**（PipelineDocument.swift
  密封面 0 diff 亲证 + 卡 id 不在 document.nodes 断言）；卡点击 = openFilmPage
  导航非 select（选择空间零触）；NodeGraphCommandTests 零改全绿（App 675/0/0 内）。

## 六、走查受阻判定（click-dead）

- **既有性亲证**：既有卡点击处理 `.onTapGesture { model.select(node.id) }` 基线
  :266 → 本批 :293 **原位零触**；本批 tap 仅 additive（`openFilmPage` 一行）；
  画布交互面 = M2-4 代码，本批 diff 的删除行全部为 ForEach 重构伴生。
- **证据充分性**：截图亲阅（`m33-nodes-canvas-film-card.png`）——节点画布四卡链
  在册（胶片模拟卡可见，inactive 面），AI 弹窗遮挡画布与 MANIFEST 申报一致；
  grade 卡同样 click-dead 的佐证记录在 MANIFEST。合成事件限制 vs 真实 hit-test
  缺陷不可区分的判定诚实，**挂 M3-4 人工复核处置合理**（面板事务面 6 测机检
  覆盖，非本批 AC 门）。

## 七、提交边界与密封面

- **六提交对表**：9f4a649（Module 单文件）/ 6c83505（golden+Project.swift）/
  b10df2c（determinism+Project.swift）/ 94168f8（面板九文件）/
  5a8a2f8（卡五文件）/ c5f5dce（docs 八文件）——stat 亲跑与申报一致；全英文
  Conventional Commits；未 push。
- **声明外扩四件亲核**：PipeCoordinator 只读三面（`filmMaterialStore/
  currentFilmRecord/hasFilmRecord`——纯 additive 读面）/ InspectorView
  `else if filmPageActive` 分支（inactive 逐字节现状）/ EditorToolRailView 传参
  / FilmTailPolicy.invalidateAll（8 行锁内清空）——结构必经论证成立，§7 申报在案。
- **密封面零 diff 真路径亲跑**：DrtPanelModel/DrtPanelView/DrtRecord/
  Lut3dKernels.metal/DrtEotf/ExportQueueContract/ExportRecipe(ExportFormatSpec)/
  ImageIOEncoders/WebPEncoder/NodeGraphCommand/LightamerSidecar/HistoryStack/
  HistoryHash/PixelPipe(TerminalTailPolicy/DrtTailAssembly)/PipelineDocument/
  V50Order/NodeOwnershipCatalog(GradeCatalog)/ModuleRegistry/ModuleInstance =
  **21 实体全 0 行 diff**；name-only 兜底扫描零命中；`Resources/` 仅 xcstrings
  （资产与 LUTs 零触碰）。
- **登记闭环**：BUNDLE-MAP 四行实数（12/5/6/4）× Project.swift 四处 × 文件实数
  三方一致。

## 八、偏差与发现处置（对表 SUMMARY §六）

| # | 项 | 验收判定 |
|---|---|---|
| 1 | m=1 符号修复（生产） | §三独立确证 ✅ |
| 2 | m≥2 根深登记不修 | **独立 Python 复算确证**（N=2/m=2：K_h=−5.73 落点恰 t、K_s=+5.23，K_s>K_h；近膝根为切点 F'→0 无符号变化 = 二分原理性不可达，DECISIONS「切点深谷多根」分析准确）；零可见面（add-only 恒等占位 + 默认 0/0/2）机制亲证 ✅ |
| 3 | 走查受阻挂 M3-4 | §六判定合理 ✅ |
| 4 | rtne 外推 + 平台面筛选 | 机理读码成立，筛结构三重亲证 ✅ |
| 5 | 声明外扩四件 | §七亲核 ✅ |
| 6 | App 首轮 crash → 注入式 optional | §五亲证 + 教训在案 ✅ |

## 九、minor（2，验收现场已修）

1. **静态键计数错账（26 → 实数 22）**：SUMMARY §一「film_* 19 键 + history 4 +
   node 3」把 history 双计入 19（隐含 26）；AGENTS 键族行与 MANIFEST #2 同族。
   实数 = 15+4+3 = **22**（zh-audit PASS 亲跑复核）。三处已按实数改正。
2. **`94168f8` 提交级构建断裂**：Project.swift 在 94168f8 登记
   FilmCardTests.swift，文件本体在 5a8a2f8——该提交树 tuist generate/build 必败
   （登记应随文件同提交）。批级登记闭环不受影响；不重写历史，登记为流程教训
   （L041 批尾 generate 惯例掩盖了提交级完整性）。

## 十、obs（6，非阻塞）

1. NodeCanvasGeometry dropIndex 文档注释两行并一行（注释面损伤）——验收现场已修。
2. AGENTS「M3-3 架构增量」缺 plan KD-5 清单三件（封存面清单 / film thumbnail 恒
   legacy / 导出 $jobFilmTail 恒装配）——T5 AC「三节齐」缺口，验收现场已补
   （封存面弹，21 实体清单 + 两恒态）。
3. SUMMARY §一 EditorToolRailView commit 归属「94168f8 / 5a8a2f8」——实际仅
   5a8a2f8（已顺手改正）。
4. E5 门 1a 预声明 ~1e-6 vs 实测 8.7e-5（87×）：偏差已登记机理（rtne 外推放大
   f32 坐标噪声），机理读码成立、筛后地板解释自洽；门分辨力保留（真实缺陷
   ≥1e-2 = 钉值 100×）。plan 风险条款的「停下排查」以机理分析落 DECISIONS 的
   形态兑现——接受，但「E5 预声明可达」的判断本身被实测推翻一事应在后续
   容差预声明时引以为鉴（两级分解预声明已是正确形态）。
5. 直启宿主吞 `print`：golden 实测值无法从直启日志提取（钉值 + 活性断言可机检）；
   后续 golden 域若需实测值对账，改用 `XCTAttachment`/文件落盘通道。
6. m≥2 深根使「联合双臂」参数下面片分支重叠（K_s > K_h）——M3-4 descriptor 臂
   换锚前，**filmPlacement 编辑面不得先行交付**（现 add-only 占位恰好安全）；
   M3-4 plan 应把「精确锚替换先于编辑面」立为硬序。

## 十一、验收批变更（本 commit）

- minor-1/2 + obs-1/2/3 现场修复（AGENTS 补封存面弹 + 三处键数 + 注释行 +
  SUMMARY 归属）。
- 本 ACCEPTANCE 落盘 + GOAL-STATE 验收续接点增量。
- **M3-3 phase 终态意见**：三 plan 执行+验收全闭环（01 PASS 0e / 02 PASS 0e+1m
  / 03 PASS 0e+2m），FSIM-01a..d 验收锚全绿 + SC 门 3152/16/0 两式互证——
  **同意 M3-3 按 SUMMARY §七 状态表进入 M3-4**（VALIDATION/REQUIREMENTS 翻账
  统一在 M3-4 签核批；FSIM-02 宽容度面板 + descriptor 运行时 + 精确锚替换 +
  Film 页实机走查补课四项交接面与 obs-6 硬序已登记）。
