# M3-4 Checker — FSIM-02 宽容度面板 + 精确锚替换 + M3 收口 plan 执行前质量门（2026-10-07）

> 审查对象 = `M3-4-01-PLAN.md` + `M3-4-02-PLAN.md`（`92a6b12`）。方法 = 数学独立
> 复算（uv/Python 200 步有界二分独立实现，非产线 solver 路径）+ RFC-023 §2.11/
> §5.4/§6.1/§6.4/§7.3/§8/§9 逐节核对（GPL 只读）+ 源码亲核（FilmPlacementModule
> 全文 / FilmTailPolicy / FilmPrintBake / PixelPipe.runFilmLeg :1038 / ScopeReduce
> .histogram / Registry.swift :81 / LightamerApp 菜单 :1456 / EditorNodesPanelView
> :532 / InspectorState / MenuCommandSet 电路 / PipeCoordinator 只读面）+ M3-2
> 裁决与 M3-3-03 验收/DECISIONS 对表 + HISTORY-SLIM-SURGERY-SPEC 触发条件核对。

## 结论

**FAIL / 3 error + 8 minor**

**错误集中在 KD-2 descriptor 归约面（本 plan 自称「错根 = 最大风险」的对面——
golden 反向钉死的参考值本身两处错账）与裁决 5③ 处置缺位（H_min=3.0 与 §6.4
golden 四行全面碰撞）**。三 error 均为 plan 文本级修订（无产线面返工），修复后
复查即可转 PASS。

**数学主干的独立复算结论（先给正面，这是本波的立身之本）**：

- **§6.4 四行八值逐位复现确证**：exact 落点 t = a ∓ N、m=2、独立二分（±400 EV
  括弧 200 步）复算 K_h/K_s = (+2.2783, −2.7033 / +1.2313, −1.7833 / −1.0111,
  −1.7833 / +1.2313, +0.2661)，与 plan 抄录的 RFC-023 §6.4 表四行八值全部
  |Δ| < 5×10⁻⁴（3 位小数逐位命中）；room 1.922/2.969/5.211/2.517/4.566 与 RFC
  §6.1/§6.4 表一致；第五行交叉对 (4.50, 3.40) 复算 core = −1.28 与 RFC 原文
  逐字一致；规则①下限 N_h ≥ 3.80 / N_s ≥ 2.70 = a−C / C−a 复算吻合。planner
  「已数值复验逐位命中」的申报**属实**。
- **m=1 闭式与 `9f4a649` 框架一致性确证**：独立推导通分展开得
  K² − 2tK + t(a+c) − ac = 0 → K = t ± √((t−a)(t−c))，与 plan §A 及 M3-3-03
  验收推导一致；有效根选择（highlights t−√ / shadows t+√）独立验证——闭式与
  独立二分偏差 1e-15；**被拒根 room = −0.7562 与 plan「H=−0.756」逐字命中**
  （a=8/C=4.2/N=4.05，exact 形 t=3.95）；闭式与落点语义无关（t 换源即用）——
  「9f4a649 的符号修复在此框架下逐字成立」成立。
- **m≥2 解析不可达论证成立**：代换 v=C−K 后 (v+d)^−m + v^−m = (v+s)^−m 通分得
  fq(v) = v^m(v+s)^m + (v+d)^m(v+s)^m − v^m(v+d)^m = 0，首项系数 1+1−1=1 ≠ 0，
  确为 2m 次多项式；m≥3 阶 ≥6，Abel-Ruffini 论证适用。m=2 数值面全部复现：
  **fq(0)=+0.9025 / fq(2)=−19.29 / fq(50)>0 / 真根 v*=2.9687（K*=+1.2313，
  与 §6.4 第二行逐位同）**；(0,2) 内增外根证实 = **v=0.1250**（F(K)−t 残差
  +0.25 ≠ 0——偶数 m 负幂取等翻转 |v+s|=g 引入，非原方程根）；自然域 [0,50]
  端点同号（+0.90 / +6.1×10⁶）bracketing 无法起步、含 (0.125) 的括弧先收敛于
  增根——「对多项式套 bracketing 必错根」结论成立。
- **二分保留的数学正本成立**：F'(K) = 1 − (1+w)^−(m+1)/m·(1+w^((m+1)/m))
  由 (1+w)^p ≥ 1+w^p（p=(m+1)/m ≥ 1 的超加性）⟹ F 严格递增、二分必收敛；
  独立复算 F'(K*) 全正。
- **旧简化臂缺陷复现确证**：t=C−N（a=7/C=4/N=2/m=2）独立复现深根
  **K_h = −5.7317**，与 M3-3-03 验收 Python 复算逐位一致。
- ** Fit 边距恒等 §6.1 旗舰映射**：N=(a−C)+0.25 = 4.05/2.95 恰为 §6.4 第二行，
  复算 core = 3.0146 ≈ plan「3.015」✓。

error 修复处方见下；全部为 KD-2/裁决 5 的 plan 文本与派发 prompt 修订，预计
零产线返工，修后复查转 PASS。

---

## Error（必修，处方逐条给出）

### E1（M3-4-01 KD-2）ISO 6846 阴影侧判据错账——`D(E) ≤ D_black + 0.04` 恒真，归约退化为常函数

KD-2 原文：`useful_shadow_ev` = 首个 `D(E) ≤ D_black + 0.04` 的 E（D =
−log10(Y/Y_white)，Y_black = plateau min）。因 D(E) ≤ D_black 对一切 E 成立
（黑 plateau 即最大密度），该谓词**恒真**——首个 E 恒等于 evMin，归约输出与
材料无关。手算向量测试若照此实现，会把错误判据钉成 golden（错根防护纪律 3
反向失守）。

RFC-023 正本两面核对：
- **§15.2 实测表**（`ISO 6846 (Dmin+0.04 … 0.90·Dmax) = [−3.18, +2.49]`）：
  阴影端判据 = **D ≥ 0.9·D_black**。独立复算：D_black = 2.2019，0.9·D_black =
  1.9817，穿越点 E ≈ −3.28（两点插值），与实测 −3.18 一致；而 D_black − 0.04
  读法预测 ≈ −4.33，与实测表矛盾。
- **§8.2 行文**（"rises to the equivalent of Dmin+0.04 above black"）字面读法
  = D ≤ D_black − 0.04，与 §15.2 实测实现不符（RFC 自身两处以 §15.2 表头 +
  实测值为准）。

对照面：高光侧判据 `Y ≥ Y_black + 0.9·(Y_white−Y_black)` 抄录正确（独立代入
§15.2 探针数据复算穿越点 E ≈ +2.49~2.50，与实测 +2.49 命中）。

**处方**：派发 prompt + KD-2 改为——`useful_shadow_ev` =（E 升序）首个满足
`Y ≥ Y_white · 10^(−0.9·D_black)` 的 E（等价：最后一个 D ≥ 0.9·D_black 的 E）；
DECISIONS 登记判据式 + 上游实测窗 [−3.18, +2.49]/5.66 stop 作对照锚；手算向量
按该判据重写。

### E2（M3-4-01 KD-2 golden）sanity 带锚错位——8.5 stop 是 slope-30% 判据值，非 ISO 判据值

KD-2 golden：「portra_400 × portra_endura 端到端宽度 sanity 带（上游实测
≈8.5 stop → 带 [6.5, 10.5]…）」。RFC-023 §15.2 表四判据并排：ISO 6846 =
**5.66** / slope≥30% = **8.50** / slope≥20% = 13.06 / slope≥50% = 3.99。descriptor
的 useful 对按 E1 修正后走 ISO 判据 ⟹ 上游对应值 5.66；若 [6.5, 10.5] 带套在
usefulHighlight−usefulShadow 上，真值 ~5.66（本仓染料近似引擎预期更低）必落带外
——红或 executor 反向放带（纪律 3「禁反向改参考迁就产线」被 plan 自己触发）。

**处方**（二选一，派发 prompt 写明）：
- (a) 带套 useful（ISO）对：锚 5.66 → 初带 [4.0, 7.5]，执行期按本仓引擎实测
  收窄 + DECISIONS 记依据；或
- (b) 带 [6.5, 10.5] 显式套 slope≥30% 诊断宽度（`slope[]` 诊断面），useful 对
  另立判据一致带。
同批：`reference_ev` 公式在 DECISIONS 显式定形（「中点密度对应 E」的密度中点
读法在上游数据算得 ≈ −1.1，会破 |reference_ev| ≤ 0.5 带；按 plan 已有的
「对齐 solveExposureCalibration mid 锚」读法 = 输入 0.184 印在纸中密度 ⟹ ≈0
满足带——公式须写死为后者，防 executor 取错读法）。

### E3（M3-4-01 裁决 5③）H_min=3.0 若按 ②同款 typed 拒绝实现，§6.4 golden 四行全被产线有效性拒绝——plan 自相矛盾

裁决 5③「H ≥ H_min（曲率顶棚；默认 3.0 stop…）」进 UI，但**处置缺位**（① =
滑杆动态最小值、② = typed 拒绝点名，③ 无 disposition）。独立复算 §6.4 四行
rooms：row1 (1.922, 1.597)、row2 (2.969, 2.517)、row3 (5.211, 2.517)、row4
(2.969, 4.566)——**每行至少一侧 < 3.0，row1 两侧全违**；row2 H_h=2.969 即
§6.1 旗舰映射。若 ③ 实现为 typed 拒绝，golden 参考向量全体被产线判非法——
AC1 的「§6.4 向量 golden 全中」与 AC3 的有效性呈现互斥。RFC 原文语义 = §7.3
"lets the **Fit** refuse"——是 Fit 建议面守卫，非 solver/UI 硬拒绝；§6.4 表本身
就把 row1（最宽 core）标为合法行。标定依据亦须修正：0.8587/3.0 = 0.286 是
**mapper 峰值**量级锚（§6.1 mapper 峰 0.289），「≈ 胶片自身峰值 0.28」表述
不准（§7.3 表胶片自身峰 0.195~0.284，portra G = 0.199）。

**处方**：裁决 5③ 补 disposition，三选一并 DECISIONS 记终值与依据——
(i) Fit 建议面拒绝/advisory（RFC §7.3 原义，手动 N 不受钳）【推荐】；
(ii) H_min 终值 ≤ 1.59（保四行全过）并重记标定；
(iii) 逐行豁免声明（不推荐——脆）。验收门补一条：修正后 §6.4 四行在 T3 有效性
面下全部可写入。

---

## Minor（8，修复处方从简）

1. **F'(K*) 复验值两位小数不可复现**：plan §A「复验 m=1/2/4/8 → 0.34/0.18/
   0.09/0.05」；独立复算（exact 形根、同锚）= 0.3188 / 0.1672 / 0.0869 /
   0.0447（highlights），阴影侧 m=1/2 = 0.3493 / 0.1873——任何单一口径均凑不出
   plan 四值。载荷性结论（正下界 ≈0.045~0.05、二分条件良好）**成立**。处方：
   DECISIONS §A 按独立复算值钉入并注明侧别与公式；执行期「独立复算钉门」以
   数值吻合为准，不照抄 plan 两位值。
2. **「真根附近不保号」措辞失准**：复算 fq(2.90)=−3.2 / fq(3.00)=+1.6——真根
   两侧**变号**。真实机理 = 自然域端点同号（bracketing 无法起步）+ (0,2) 增外根
   v=0.1250 截胡。处方：DECISIONS 转录按此机理措辞，防测试注释写入假命题。
3. **规则①「每侧 N ≥ (a−C)+margin」符号面**：highlights 形（a>C）；阴影侧
   字面代入 a−C=−2.7 ⟹ 滑杆最小值 max(0,−2.7+0.25)=0，而真下限 = C−a =
   2.70（RFC §9.2①）——字面实现造出「UI 接受 → solver typed 拒绝」churn。
   处方：DECISIONS/面板实现写侧别显式式：highlights N ≥ (a−C)+margin、
   shadows N ≥ (C−a)+margin。
4. **面板直方图轴窗「[−12,+12] 与 probe 域一致」不可实现**：film stats 直方图
   = 256 bins × [0,1] 线性域（ScopeReduce 契约），bin→EV 实际可绘跨度 =
   [log2(0.5/256/0.184), log2(255.5/256/0.184)] ≈ **[−6.56, +2.44]**；[−12,+12]
   是 descriptor ramp 域，两者不得混称（≤−6.56 段恒空、≥+2.44 恒钳 bin 255）。
   处方：轴按直方图原生跨度绘制（或 [−12,+12] + 钳段注记），与 plan 风险节
   「量化容差」注记同批落 DECISIONS。
5. **stats 快照投递路径未申报**：直方图在 `PixelPipe.runFilmLeg`（:1052）内
   算即用、零保留；coordinator 只读面取数只有三路——(a) PixelPipe 侧保留/访问
   器（超出纪律 1「唯一允许增量 = factory 抽取」）；(b) IOP `Registry.swift:81`
   adapter 内保留副作用（文件未列 front-matter）；(c) coordinator 按需调
   FilmStatsSeam + statsHash 记忆（需顶面访问面，亦未申报）。按现文执行必在中途
   撞 undeclared 扩面。处方：KD-3 点名机制与实名文件（推荐 (b)/(c)）；凡触
   PixelPipe 即 C 档回注，禁静默扩。
6. **Fit 边距交叉阈值实为 m≥3 非 m≥4**：独立复算 m=3 已交叉（K_h=−0.602 <
   K_s=−0.293；m=4/5/8 = −2.48/+1.22、−4.37/+2.75、−10.09/+7.37 单调深化）。
   处置（规则②拒绝 = 预期、禁静默钳制）不受影响，但 Fit「膝点交叉按溢出比例
   分摊」自 m≥3 起即承重——Fit 分摊测试最小交叉例应取 m=3；DECISIONS 如实记。
7. **M3-4-02 SC 表缺 M3-0 行**：ROADMAP :19 / STATE 均有 M3-0（charter & 站
   规格，✅ 闭环）行；KD-2「M3 全 phase SC 三列对账」表无 M3-0 行亦无「无独立
   SC」注记，与「全 phase」声称不符。处方：补 M3-0 行（判定 = 立项批已随 M3-1
   签核清偿 + 指针索引）或显式 no-SC 注记行。
8. **菜单旁路命令的 MenuCommandSet 电路陷阱**：menu IA = `MenuCommandID`
   纯函数电路（LightamerApp :393 `visibleMenuCommands`；WorkspaceRoutingTests
   :225/:240/:254 对 allCases 穷举断言）。旁路命令若做成**无门控、无快捷键**的
   静态项（同 menu_show_sidebar :1457 先例）则零 MenuCommandSet/AppPreferences
   diff；一旦加 gate 或 keyboardShortcut 即牵动 MenuCommandSet.swift +
   AppPreferences(DefaultKeymap) + WorkspaceRoutingTests 三件未申报面。处方：
   KD-4 写明旁路命令 = 无门控静态项（零新 MenuCommandID、零快捷键）；越出即
   C 档回注申报三件。

---

## 审查维度逐项

**1. 数学审计**：主干全过（见结论头独立复算）；error E1/E2 + minor 1/2/5 均
落在本面。golden 反向钉死结构（§6.4 向量 + K_s<K_h 排序门 + 第五行交叉对
typed 拒绝负测 + 禁反向改参考）设计正确，**前提是 E1/E2 修正后参考面本身
可信**。高 m 拒绝处置（规则②点名、禁「修好」）符合 RFC §9.2②。

**2. 裁决一致**：M3-2 七项生效值（①FilmRecord 承载/②配光自动③案/③资产 c
混合/④宽容度面板 M3-4/⑤golden 数学复算主门+公开参考值口径（RESEARCH-NOTES
:336「公开标准部分用公开参考值」在案）/⑥spike/⑦独立 filmPlacement op）零动摇
——本波 ④ 的交付体、⑦ 的 op 载体、② 的 solve cache 语义（「本波不改 stats
腿与 solve cache 语义」+ descriptor 另立键域）均守。教导两条 = SPEKTRALAB-NOTES
#2 原文逐字（:10 亲核），落 AC3 + T4 走查单 ✓。「场景置位在胶片前、显影曝光在
胶片后」分离教导与 placement@20.8（主链 grade 域）+ film sub-run（主链后）的
架构事实自洽 ✓。

**3. 编译/结构**：B 臂 wire = resolved knees（RFC §8.3 结构强制原文亲核：
"changing the paper would silently change every existing edit"）+ Params v2
additive（encodeIfPresent/decodeIfPresent 惯例、v1 nil = 逐字节保现状、非零 v1
typed degrade + 真实面为零断言 + 被推翻即停——链路完整）；`FilmMethodBox.Params`
（record + solved pack 同体，FilmTailPolicy :198 亲核）先例引用属实。C 臂恒等面：
identityJSON 早退（commitParams armed 门 :266-273）+ blit 恒等 + placement 不在
哨兵链（执行期亲证 + 重钉流程兜底）——零破坏路径成立。D 臂旁路真实性：View
menu = LightamerApp.swift:1456 亲核、`openFilmPage` = InspectorState:80、卡 tap
= EditorNodesPanelView:532 逐字命中——plan 预判「:532」与「menu 组装根」全部
属实（minor 8 的电路陷阱除外）。

**4. 收口完整性（P2）**：M3-4-02 零源码红线 + 单笔 docs commit + 三态判据 +
历史行只追加 + C 档第 3 停授权原话要求——全部对表 m2-11 体例（VALIDATION 正本
亲核在位）与 AGENTS C 档门控。瘦身手术：三前置断言与 SPEC 步骤 1 逐字吻合
（perl 零中文基线 / git status 无在飞产物 / release 分支未检出）；「触发确认在
本批 + 手术本体留主会话」与 SPEC 红线「push 收敛主会话」及 GOAL-STATE :12 用户令
「M3 收官后自动执行」一致——分工声明已在 KD-4/KD-3 续接点成形，合规。终验
对账链 2962→3024→3081/3125→3152→+P1 与 GOAL-STATE 历史续接点逐项吻合。SC 表
覆盖缺 M3-0 行 = minor 7。

**5. 测试对账**：基线 3152/16/0 与 M3-3-03 验收亲跑终值一致（七 bundle 和
483+404+371+598+279+342+675 = 3152 复核）；+16..26 与三测试文件分解
（FilmGoldenTests 增补 ~6-9 / FilmDescriptorTests ~5-6 / FilmLatitudePanelTests
~7-9）相容。golden 归属 = IOPP 行内实数修订 + 两新文件 LAYERS/APP 增行，与
BUNDLE-MAP 现行登记（FilmGoldenTests 12 @IOPP / FilmPanelTests 6 @APP）接续
正确；L041 批尾 generate + 登记随文件同 commit（minor-2 教训）在册。定向轮
IOPP/LAYERS/APP + 全套 `--all` 留 P2 报备批——与 AGENTS 资源监控节口径一致。

**6. goal-backward**：FSIM-02 = REQUIREMENTS :385 原文（直方图 + 双虚线 + 占比
+ 两条教导）与 KD-3 面板三件套逐项对位；置位编辑面（动态最小值/拒绝点名/Fit/
三 readouts）= RFC §9.2/§9.3 全量转录 ✓。obs-6 硬序兑现路径真实：T1→T2→T3
波内硬序 + 「C 置位滑杆 T1+T2 前不写一行」+ checker 条目「T3 diff commit 序即
证据」+ T1 落地即消解 m≥2 深根（复算确证 exact 形 + 有效性规则下根条件良好）
——占位态安全论证成立。M3 VALIDATION 输入齐备（m2-11 体例 + M3-1-VALIDATION
先例 + 挂账底册七项 + M3-3 三波登记）。

---

## 修复后预期

E1/E2/E3 全部为 plan/派发 prompt 文本修订（KD-2 两式 + 裁决 5③ disposition +
sanity 带重锚），预计半小时级；minor 1-8 中 3/4/5/8 建议随同批修入 plan 文本
（1/2/6 落 DECISIONS 执行期转录、7 落 M3-4-02 KD-2 表）。修后本 checker 复查
范围 = 仅修订处，预期转 **PASS**。
