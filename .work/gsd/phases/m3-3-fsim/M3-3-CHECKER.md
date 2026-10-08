# M3-3 Checker — FSIM-01 三 plan 执行前质量门（2026-10-08）

> 审查对象 = `M3-3-01/02/03-PLAN.md`（`c546b31`）。方法 = 七项裁决逐条对 AC + 源码
> 亲核（PixelPipe/LayerCompositeDriver/LightamerSidecar/HistoryStack/HistoryHash/
> V50Order/NodeOwnershipCatalog/Registry/PipeCoordinator/EditorState/ExportQueue/
> ExportRenderer/ExportState/Lut3dModule/ScopeReduce/Project.swift/BUNDLE-MAP）+
> SpektraLab 仓实盘（28 profile schema / neutral_print_filters.json 全 160 组合 /
> printing.cpp）+ LESSONS/M3-1-01 验收先例对表。

## 结论

**FAIL / 5 error + 9 minor**

源码锚点面总体扎实：sidecar `schemaVersionCurrent`=8（:192）、drtRecord :665-735/
:952、HistoryItem.drtRecord :114-167 / commitDrt :249-270 / effectiveDrtRecord
:466-471、HistoryHash drtRecord 末位折叠（HistoryStack.swift:490 扩展区）、
`DrtTailAssembly.seed(upstream:params:)` :1257（fold 序 = recordHash ⊕ tag ⊕
postSet ⊕ upstream）、V50Order acesccIn 20.5 / exposure 21.0 / acesccOut 69.9 /
skinSmooth 66.5、GradeCatalog 18 行断言（GradeCatalogTests:36）、ACESccEnvelope
needsEnvelope（catalog op 包夹自动生效）、ExportRenderer :487/:496 调用点、
ExportState `assembled.drtOutput` :494、PipeCoordinator 四件套 :577/:598/:656/:677、
EditorState :250、测试基线 **3029 = 3024 + `571c3c0` +5（SidecarSeedTopUpTests，
BUNDLE-MAP +1 行亲核）**、SpektraLab 28 profile（film 20 + paper 8 亲核）与
`metadata.version`=0.3.2、neutral 表 portra_400×portra_endura / ektar_100×
ultra_endura 两 sanity 组合在册——全部与 plan 记载一致。

error 集中在：导出 per-job 载体漏登记 ExportQueue.swift（E1）、base_density 数据
契约与资产实盘矛盾（E2）、品红滤色增益向量物理错（E3）、尾段交互矩阵不完备（E4）、
golden 容差锚与本仓实测先例矛盾（E5）。修复后复查（预计纯 plan 文本修订，无产线
面返工）即可转 PASS。

---

## Error（必修，修复处方逐条给出）

### E1（M3-3-02 KD-7 / front-matter files_modified）导出 filmTail per-job 载体缺 ExportQueue.swift，按 plan 现文无法闭环

`$jobFilmTail` TaskLocal 在 detached 渲染腿**不自动继承**——`ExportQueue.swift`
:408-413 注释原文即「the detached task inherits no TaskLocals, the wrapper sits
inside」；M2-9 的 `$jobDrtTail` 同款先例实际落了三处 ExportQueue.swift 编辑：
`ExportJob.drtTail` 字段（:60）、`enqueue(drtTails:)` per-image 索引参数 + precondition
（:197/:203）、腿内 `$jobDrtTail.withValue(queued.drtTail)` 包装（:417）。
plan 02 的 files_modified **未列 `LightamerCore/Sources/Export/ExportQueue.swift`**，
KD-7 也未写这三处编辑——「enqueueExportM2 恒装配 filmTail」到渲染腿之间的值传递链
断裂；executor 要么无法交付，要么产生未申报文件 diff（T7 机检撞墙）。

**处方**：files_modified 增列 ExportQueue.swift（additive 载体面）；KD-7 补三编辑点
（Job 字段 + enqueue `filmTails:` 参数 + :417 包装链嵌套一层）+ T6 测试补
per-image fan-out 断言（两图不同 carrier 各达渲染）。`ExportQueueContract.swift`
零 diff 红线不变（Contract 与 Queue 是两个文件，M2-9 在案）。

### E2（M3-3-01 KD-3/KD-5；波及 M3-3-02 KD-1 kernel）base_density 数据契约与资产实盘矛盾——「光谱字段零消费」纪律自相矛盾

实盘亲核（`kodak_portra_400.json`）：`base_density` = **81 波长谱域数组**（61/81
非 None，None 前导 4 点），**每波长一个标量**，并非「film 侧橙罩常数半」的 RGB
常数/三元组；相纸侧（portra_endura）= 81/81 非 None（~0.09，谱域 Dmin）。且
density_curves 趾部 ≈ 0（基底相对存储）——研究 §1.5 自己就把 base_density 归入
「81 点光谱域——不消费，随文件携带」行；plan 01 却同时（a）宣布「光谱字段零消费」
（b）把 base_density 列入消费集 `data.{log_exposure, density_curves, base_density}`
（c）KD-5 消费「+ base_density 偏移」产出密度三元组。RGB 域 per-channel 底色常数
在文件里**不存在**，须经一个未定义的谱→RGB 投影推导；KD-3 的形状校验只查
density_curves×log_exposure，base_density 走错数据不会被发现。风险节「执行期实盘
核对 nullable 形态」只覆盖 None 形态，不覆盖「谱域 vs 常数」这一语义错位。此为
01 求解器（T5）与 02 负片段 kernel（T2）共用的数据锚，必须在 plan 期裁决。

**处方**（二选一，落 KD-3/KD-5 + DECISIONS）：
1. **定义文档化投影**：如 `base_R/G/B := base_density(λ≈650/550/450nm)` 三点采样
   （橙罩谱形在三原色波长的取样，确定性、可写进 golden 复算），或可见光非 None 段
   均值；同时把「光谱字段零消费」措辞修订为「光谱**重放**不消费；base_density 谱
   数组仅经 DECISIONS 登记的标定投影为 RGB 常数」；
2. **弃用 base**：负片段只用 density_curves（基底相对曲线本身承载通道失衡），中性
   包解与 sanity 带按无底色模型重标定——需复核与 neutral 表实测 (M0,Y0) 的偏离是否
   仍在宽容带内。
另：KD-4 materialPairHash 的消费集随裁决同步（弃用则移除 base_density）。

### E3（M3-3-01 KD-5 + M3-3-02 KD-1；承 RESEARCH §4.1 勘误）品红滤色增益向量物理错误

两 plan 均写 `gain = k_y·[0,0,1] + k_m·[0,1,1] + k_c·[1,0,0]`。RGB 密度域 dichroic
物理：Y 吸蓝 = [0,0,1] ✓、C 吸红 = [1,0,0] ✓，**M 吸绿 = [0,1,0]**——[0,1,1] 会
同时加蓝密度，等制品红+黄混色。RESEARCH §4.1 自身散文（「M 滤色吸绿」）与公式互相
矛盾，plan 照抄了公式侧。sanity 带 [40,90] 宽（50 CC 点），错向量大概率**测不出来**
（两具名组合的表值 51/52、71/2/55 附近两种向量都可能落带内）——不能指望 T5 兜底。
解方程结构不受影响（M=[0,1,0] 时 R 通道恒无滤色作锚，G 对 M、B 对 Y 各自单调，
顺序二分更干净）。

**处方**：01 KD-5 / 02 KD-1 改 `k_m·[0,1,0]`；RESEARCH §4.1 落勘误行；T5 执行期
按修正向量复核两组合解值并写 DECISIONS。

### E4（M3-3-02 KD-1）显示尾段 × film 交互矩阵不完备——legacy+film 的印框去向与 EDR+film 臂均未定义

KD-1 只给两种尾段形态：「legacy 重放 colorout+gamma」/「.drt 尾链」，降出触发
`displayTailDemoted = terminalTail 活 || filmTail != nil`。缺口两处：
1. **legacy(.sdrGamma)+film 时 borders 76 / watermark 77 的归属**：现文只降
   colorout/gamma（「显示三件（colorout 70.0/gamma 78.0）」连件数都对不上）——若
   印框/水印留在主链则被 film 模拟调色，违反 M2-6 E2「印框永不进 tone mapping」
   纪律；正确形态 = 与 .drt 同法降出**整个终端驻留集**（colorout/borders/watermark/
   gamma），film 后按 v50 序重放 colorout → borders → watermark → gamma。
2. **.edrLinear（手动 EDR）+ film**：EDR 档现状只降 gamma、colorout 在主链——film
   激活则消费到 **post-colorout** 平面，破坏「film 消费 pre-colorout float32」物理
   不变量；且 KD-1 的重放分类没有 EDR 臂（重放 gamma 会错钳 SDR）。需定义：colorout
   由 film 臂降出、film 后重放 colorout、gamma 维持 EDR 档降出不重放、终平面保持
   float32 linear。

**处方**：KD-1 补 3×2 矩阵（三档 terminalTail × film off/on）逐格写降出集 + 重放链
+ 终平面格式；T1 测试补两组合：film+yiyin 边框（边框平面在 film 后）、film+EDR
（输出 linear、无 gamma 重放）；DrtTailTests 零改门保持。

### E5（M3-3-03 KD-1 门 1）golden 逐像素容差锚与本仓实测先例矛盾——M3-1-01 §4 已裁决的同类门结构被重蹈

KD-1 门 1 锚「float32 管线 vs Float64 参考 = 每通道 ≤2e-6 相对（LUT 插值段
≤1e-5）」。但 fused kernel 输出包含 **65³ 印相 LUT 四面体插值**，M3-1-01-ACCEPTANCE
§五/DECISIONS §4 已实测裁决：65³ 复合晶格对胶片曲线在线性 working 域的插值地板
**~8e-3（1e-3..1e-2）**，「GPU==理想 Float64 ±1e-5 在任何 65³ 晶格下数学不可达」，
门结构因此收窄为「voxel 级烘焙门（≤1e-5，Float64 vs Float64 可达）+ 忠实渲染门
（同表插值口径）」。plan 03 的 ≤1e-5 锚比实测地板低 2-3 个量级；「执行期按实测标定
写死」的对冲能防假失败，但等于把已裁决过的结构问题留给执行轮再裁一次。另 L048
教训（比较空间选型：对数腿零点斜率放大 f32 epsilon 750×；Float64 参考常数须
`Double(Float(x))` 出厂值升维）未被 read_first 引用。

**处方**：KD-1 预声明 M3-1-01 §4 同款两级分解——① kernel vs **同表 CPU 四面体采样
双写**（float 类容差，~1e-6 可达，验证 kernel 实现正确性）；② 烘焙表 vs 理想连续
模型（独立复算，容差按插值地板标定写死 + DECISIONS 记依据）；③ 比较一律 decode 回
linear working 域、参考常数用 f32 出厂值升 Double（L048②）；中性闭合门 ≤1e-3 与
bake 体素级门保留。read_first 补 `M3-1-01-DECISIONS.md` §4 + LESSONS L048。

---

## Minor（修复建议，不阻断派发；m1/m2/m4/m8 建议随 error 同批修订 plan 文本）

- **m1**（01 front-matter）files_modified 首行「FilmRecord + **四枚举** + stableHash…」
  与 KD-1「**枚举不设**（开放字符串 id）」直接矛盾（DrtRecord 四枚举是模板遗产）。
  删「四枚举」字样。
- **m2**（01 已定裁决①/KD-2）neutral_print_filters 值域记载「M≈49-79 / Y≈48-79
  亲核实值」**与实盘不符**：全文件 160 组合实测 M∈[28.4, 92.1] / Y∈[24.6, 116.0]，
  **30/160 组合落在 [40,90] sanity 带外**（含常见 stills 组合 pro_400h×portra_endura
  M33.5/Y24.6、vision3 系×endura 全系）。两具名测试组合在带内、测试可立，但登记值
  必须改正，且 sanity 带须显式限定「仅两具名组合」防后续扩组合假失败。
- **m3**（01 批注/KD-3）「256×3，status M 打印密度域」对相纸不成立：portra_endura
  `info.densitometer = status_A`（film 侧才是 status_M）。M/A 两种密度计量域在同一条
  加性密度链混用属风格化近似边界，须 DECISIONS 登记口径（不改资产）。
- **m4**（02 KD-5/T4 × 03 已定裁决④）filmPlacement 面板可达性两 plan 互相矛盾：
  面板机制为 **per-op 手写 provider**（IOPPanelProvider 按 opName 派发 + 
  GradeScalarPanels 逐 op 薄面板，无 panelExposures 驱动的通用面板）——02「本批无
  面板」+「add face 可枚举到」+ Registry 默认面启用 = 用户可加一个**无任何编辑面**的
  恒等 op；03「参数经 grade add face 已可达」高估。处方二选一：02 T4 顺手注册一个
  三滑杆 GradeScalarPanels 薄面板（机制现成，~40 行，同时消除 03 措辞矛盾）；或
  保持无面板但 03 措辞改为「M3-4 前为可加不可编的恒等占位」+ DECISIONS 注记。
- **m5**（03 front-matter）「`App/Sources/Lightamer/UI/Shell/Nodes/…（投影卡触点）`
  通配条目」重蹈 M3-1-03 验收 obs-1 明令纠正的反模式（路由缝/结构必经文件须入申报
  集）。至少把预判触点（NodesPanelModel / NodeCanvas 视图层 / PipelineDocument 投影
  构建点）写实名，保 C 档回注对冲。
- **m6**（编排层，非 plan 文本）台账滞后：ROADMAP M3-2 行仍「▶ next」、GOAL-STATE
  无 M3-2 收口/M3-3 规划续接点（裁决 `e02dcc7` 与 plan 批 `c546b31` 均未回写）；且
  **M3-2 裁⑥「spike 同批」（RAF 100MP 双峰 signpost 二分 → perf.md O-1 +
  `phases/m3-2-fsim-research/evidence/`）未执行**——perf.md O-1 仍为 M2-11 旧文。
  M3-2 验收形态（spike 结论入 perf.md）未满足前 M3-2 不应翻 ✅。派发 M3-3 前由
  orchestrator 补：spike 执行或显式改裁、ROADMAP/GOAL-STATE 翻账。
- **m7**（02 KD-1「序」）「`run()` 内 `runDrtTailLeg` 调用点（:864）」行号张冠李戴：
  :864 属 `runSub()`，`run()` 的调用点是 :723。T1 action「两处调用点接线」实质已
  覆盖，改正标注即可。
- **m8**（02 T4/KD-5）「GradeCatalogTests 计数断言 18→19」实为**多点修订**：
  :36 count、:46 unique ids、:51 grade-owner 计数 14→15、:91/:129 唯一 op 计数
  17→18、文件头注释——plan 应列全，防 executor 按「既有断言需改 = 停下上报」红线
  误停。
- **m9**（02 体量）T1-T7 七任务横跨 sub-run/kernel+统计/bake/op/coordinator/export
  四高风险面，≈ M2-6-1 + M2-6-3 + M2-9-02 合体。建议预授权断点：若 T1/T2 超支，
  T4（filmPlacement 全套，catalog 行随行）+ T6（导出递缝）可切后续 plan 04 独立
  交付，01→02→03 链不断（03 的 golden/面板不依赖 T4/T6 的孤儿面小）。

## 已核对无异议面（抽样）

- 七项裁决落点：①FilmRecord+sub-run+filmPlacement（01 KD-1/02 KD-1+KD-5）②闭式解
  +曝光归一+内容偏移默认关+Y/M 手动恒在（01 KD-1 字段/02 KD-2 终式/03 KD-3 面板）
  ③资产 c 混合五件套（01 KD-2，MANIFEST 对账机制可机检）④宽容度面板 M3-4 三 plan
  一致让出 ⑤golden 形态+SpektraLab 渲染不入仓（03 KD-1/纪律 2）⑥spike = M3-2 面
  （见 m6）⑦独立置位 op（02 KD-5）。V50 20.8 介于 acesccIn 20.5/exposure 21.0、在
  [20.5,69.9] envelope 包裹内、ACESccEnvelope.needsEnvelope 按目录 op 自动包夹——
  亲核成立。
- 持久化三件：HistoryHash 第 5 参默认 nil 尾位折叠（film 排 drt 后）全既有调用点
  零改动编译 ✓；v8 零漂移负测有 SidecarV7Tests「one-digit rewind」字节形先例 ✓；
  `.lalb` PRAGMA user_version 与 sidecar 版本线分离 ✓。
- 求解锚：mid-gray = log10(0.184) 与 printing.cpp `kMidgray = 0.184`（:9）一致 ✓；
  曝光归一 = 几何均值→亮度单值、`gain × 2^exposureEv`、缓存键
  `fnv(材料对⊕统计⊕模式)` 与 printing.cpp:147-165 语义同构 ✓；统计整数秩 + 全幅
  禁逐 ROI（跨 ROI 同解测试钉死）✓。
- 导出/工程面：Contract 零 diff 可机检（git diff 面名单在纪律节）✓；测试基线
  3029 = 3024 + `571c3c0` +5 亲核 ✓；+90..114 增量算术 ✓；test_bundles 名与
  BUNDLE-MAP 七 bundle 名对表 ✓（FilmGolden→IOPP 契合 Golden* 惯例）；报备终轮
  批准制表述与 AGENTS 资源监控节一致 ✓；公开仓 CC BY-SA 合规声明落在 01 KD-2
  NOTICE + 03 KD-5 AGENTS 节（SA 传染边界）✓。

**处置**：E1-E5 + m1/m2/m4/m8 为 plan 文本修订批（建议单笔 docs commit，不触产线）；
m6 上报 orchestrator 派发前处置；m3/m5/m7/m9 随批修订或 DECISIONS 首条登记。修订后
checker 复查一轮即可转 PASS 派发。
