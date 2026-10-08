---
phase: m3-4
plan: "M3-4-01"
title: "FSIM-02 宽容度面板代码波——A filmPlacement 精确锚替换（t = a ∓ N 精确落点 + descriptor C 面 + 有效域规则三条 + Params v2 resolved knees，obs-6 硬序第一）+ B descriptor 运行时臂（中性 ramp 过真链 probe + ISO 6846 归约 + pair 键缓存）+ C 宽容度面板（场景直方图 + 容纳范围双虚线 + 低于/内/高于占比 + 教导两条 + 置位编辑面/Fit/readouts）+ D Film 页走查补课（click-dead 旁路入口）"
wave: 1
depends_on: ["M3-3-03"]
autonomous: true
requirements: ["FSIM-02", "FSIM-01b（精确锚语义收口）"]
estimated_tests: "+16..26"
test_bundles: [IOPParity, Layers, App]
files_modified:
  - LightamerIOP/Sources/FilmPlacement/FilmPlacementModule.swift      # 修改：精确落点语义（t = a ∓ N）+ 锚注入 + 有效域 typed 拒绝 + Params v2 resolved knees（additive decode）+ commitParams 直包 uniforms（solve 移出 GPU commit 路径）
  - Tests/LightamerTests/FilmGoldenTests.swift                        # 修改：门 3 重钉——RFC-023 §6.4 四行 8 参考值向量 + 联合 K_s<K_h 排序门（构造注释恢复）+ 有效域拒绝门 + resolved-face 逐像素；实测值走 XCTAttachment（obs-5）
  - LightamerCore/Sources/Film/FilmDescriptor.swift                   # 新建：ProfileLatitudeDescriptor 值类型（evMin/evMax/usefulShadowEV/usefulHighlightEV/referenceEV/response/slope/pairHash）+ ISO 6846 归约纯函数 + pairHash 键缓存
  - LightamerCore/Sources/Pipe/Film/FilmDescriptorProbe.swift         # 新建：中性 ramp 过真链 probe（复用 FilmMethodBox + film 腿 payload 组装；L014 fence 读回；probe 配置常量 tag）
  - LightamerCore/Sources/Pipe/PixelPipe.swift                        # 修改（声明外扩·结构必经）：film 腿 payload 组装抽 internal factory 供 probe 复用——零行为 diff（私有腿改调 factory，film 腿既有测试零改全绿为门）
  - Tests/LightamerTests/FilmDescriptorTests.swift                    # 新建（LAYERS）：probe T(E) 单调 + portra×endura 端到端带宽 sanity 带 + reference_ev ≈ 0 标定带 + bit-identical 确定性 + ISO 归约手算向量
  - App/Sources/Lightamer/UI/Shell/FilmPanelModel.swift               # 修改：宽容度节读面（stats 快照 + descriptor）+ 置位节解析写路径（solveKnee 消费 + 有效性规则单源）+ Fit 默认策略
  - App/Sources/Lightamer/UI/Shell/FilmPanelView.swift                # 修改：宽容度节（EV 轴直方图 + 双虚线 + 占比读数 + 教导两条）+ 置位节（N_h/N_s 动态最小值滑杆 + m + Fit + §9.2 三 readouts + 越界点名呈现）
  - App/Sources/Lightamer/State/PipeCoordinator.swift                 # 修改：additive 只读面（film stats 快照 + descriptor 缓存消费面——面板唯一数据源，零第二真相）
  - App/Sources/Lightamer/UI/Shell/Nodes/EditorNodesPanelView.swift   # 如需：Film 卡入口并存确认（click-dead 本体不动；旁路入口另落）
  - App/Sources/Lightamer/App menus 所在文件（read_first 7 亲核实位后实名）  # 修改：View 菜单「显示胶片面板」命令（click-dead 旁路入口，静态键）
  - Resources/Localizable.xcstrings                                   # 修改：latitude_* 键块 append 尾部（既有键字节与顺序零触碰；F-2 插值禁令）
  - Tests/LightamerTests/FilmLatitudePanelTests.swift                 # 新建（APP）：宽容度节投影/占比手算/Fit 策略/有效性呈现/置位 commit 面/教导键静态性
  - Project.swift                                                     # 修改：测试登记（L041 批尾 generate；登记随文件同 commit——minor-2 教训）
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt        # 修改：增行登记（E2）
  - AGENTS.md                                                         # 修改：「M3-4 架构增量」节（descriptor 形态 / Params v2 迁移 / 有效性规则单源 / 封存面清单）
  - .work/gsd/phases/m3-4-latitude/M3-4-01-SUMMARY.md                 # 新建（含 P1 增量对账 + P2 交接面）
  - .work/gsd/phases/m3-4-latitude/M3-4-01-DECISIONS.md               # 新建（KD-1 数学推导正本 + 标定值）
  - .work/GOAL-STATE.md                                               # 修改：P1 续接点（→P2 VALIDATION）
  - .work/TODO.md                                                     # 修改：M3-4 P1 清账
  - .work/LESSONS.md                                                  # 如踩坑
  - .work/gui-acceptance/m3-4/                                        # 新建：走查证据（§3.2 截图纪律）
---

# Plan M3-4-01 — FSIM-02 宽容度面板代码波（wave 1）

> **性质**：M3-4 两波之首（代码波）。四根柱，**硬序 A → B → C**（obs-6 立账：
> 精确锚替换先于 filmPlacement 编辑面交付——占位态是唯一安全态，锚不换编辑面
> 不开工），D 走查补课随 C。E（M3 VALIDATION 收口）= P2（`M3-4-02`），本波不跑
> 全套 `--all`（终验轮在 P2 报备批）。
> **基线**：3152/16/0（M3-3-03 验收亲跑终值）。本波终值 = 3152 + P1 登记增量
> （定向 bundle 轮逐 bundle 对表），P2 全套轮对账。
> **SC 数字门（ROADMAP「plan 期定」兑现）**：AC7——定向轮 0 fail + 登记
> 三方对表两式互证 + golden 反向钉死（错根 = 本波最大风险，见 KD-1/风险节）。

## 已定裁决（生效值，硬约束，不得重开）

1. **硬序（obs-6，M3-3-03-ACCEPTANCE §十.6）**：T1（A 精确锚）→ T2（B
   descriptor）→ T3（C 编辑面）。C 的置位滑杆在 T1+T2 落地前不写一行；T1/T2
   各自独立可验收（T1 落地后 m≥2 深根缺陷即消解，占位态继续安全）。
2. **m≥2 求根形态（KD-1 数学裁决，推导正本见 §A 节）**：**保留 m=1 闭式 +
   m≥2 有界二分 + safeguarded Newton**（上游 RFC-023 §9.2 钦定形：「bracketed
   bisection cannot fail… seeded from the m=1 closed form, Newton converges in
   two or three steps」）；「m≥2 解析求根替换二分」**数学不可达**（m=2 四次式
   多根/切点谷、m≥3 Abel-Ruffini，推导与数值证据 = §A）——缺陷根因不在求解器
   在**落点语义**：t = C ∓ N（简化臂）换 t = a ∓ N（精确形）+ 实测锚，切点
   不可达与深根随换锚消解（本波数值复验：同锚集 exact 形根条件良好，
   F'(K*) ∈ [0.05..0.34] 有正下界）。
3. **锚源（RFC-023 §9.2/§8.3 语义）**：a_h/a_s = film stats 直方图 P99.9/P0.1
   （**整数秩**，`FilmRuntimeSolve.percentileBin` 单源；bin→EV 换算 =
   `log2(((bin+0.5)/256)/0.184)`，与 `contentAdaptiveShift.channelEV` 同式）；
   C_h/C_s = descriptor `usefulHighlightEV/usefulShadowEV`（KD-2）。**降级面**：
   film 未启用/统计未到 → a 用既有 `sceneTopEV/sceneBottomEV`、C 用既有
   `mediumTopEV/mediumBottomEV` 常数（M3-3 常数**降格为 no-film fallback 注记**，
   非 删除）；降级态在面板呈现 fallback 注记。
4. **wire = resolved K/H（RFC-023 §8.3 结构强制）**：Params v2 = 既有三字段
   （pull-backs/rolloff，UI 态语义）+ **additive resolved knees**（kShadow/
   hShadow/kHighlight/hHighlight optional）；渲染/持久化/paramsHash 消费
   resolved 值（换纸不静默改既有编辑）。v1 档（nil knees）decode：pull-backs
   全零 → inactive knees（逐字节保现状）；**非零 v1 → typed degrade 到默认
   identity**（真实面为零——M3-3 编辑面缺位，非零档只存在于测试；DECISIONS
   登记）。`FilmMethodBox.Params`（record + solved pack 同体）为结构先例。
5. **有效性规则三条进 UI 不进钳制（RFC-023 §9.2 validity rules）**：
   ①每侧 `N ≥ (a − C) + margin`（滑杆**动态最小值**，随纸/锚移动；margin 默认
   0.25 stop = §9.3 Fit 政策值）②`K_s < K_h` 违反 = **typed 拒绝并点名该回退
   的滑杆**（禁静默钳制——§6.4 第五行即此形态）③`H ≥ H_min`（曲率顶棚；H_min
   默认 3.0 stop，标定依据 = §7.3 `max|f''| = 0.8587/H`，取 mapper 峰值 ≈ 胶片
   自身峰值 0.28 stop⁻² 同量级——执行期 DECISIONS 记终值）。高 m（≥4）窄介质下
   规则②拒绝 = **预期物理行为非缺陷**（本波数值复验：Fit 边距下 m=4 已交叉，
   §6.4 同型）；m 值域 [1,8] 不收窄。
6. **descriptor = 真链 probe，绝不并行第二套数学（RFC-023 §8.1 repo 纪律）**：
   1024×1 中性 ramp（`2^E · 0.184`，E 均匀网格 [−12,+12]）过 `FilmMethodBox`
   真子运行（neutral pack、零 shift、strength 1、**gain = 1 = auto exposure
   off**、record exposureEv 0），L014 fence 读回 Y → ISO 6846 归约。缓存键 =
   `materialPairHash`（probe 配置常量 tag 折入键——配置变更即翻键）。
7. **教导语义（SPEKTRALAB-NOTES 可借鉴#2 原文两条）**：「场景置位在胶片前、
   显影曝光在胶片后，两者不可互替」「EDR 在输出侧，不能找回输入端已丢高光」
   ——面板静态文案（info 区/首次展开 toast 级），zh 静态键。
8. **pristine 直通 + 密封红线**：无 FilmRecord 文档 + placement inactive =
   渲染链逐位现状（T1 负测钉）；`PipelineDocument`/`NodeGraphCommand`/
   `TerminalTailPolicy`/DrtPanel 族/六格式导出矩阵/sidecar schema 零 diff；
   placement 添加走**既有命令面**（零新命令）。`PixelPipe.swift` 唯一允许增量 =
   payload 组装抽 factory（KD-2 结构必经，零行为 diff 门）。
9. **全套 `--all` 不在本波**：验证 = 定向 bundle 轮（IOPP/LAYERS/APP）+ 登记
   对账；全套报备终轮 = P2（orchestrator 批准 + 运行监视，AGENTS 资源监控节）。

## 关键设计决策（planner 裁决，执行中不重开）

### KD-1 A：filmPlacement 精确锚替换（T1，硬序第一）

**§A 数学推导（DECISIONS 转录正本；planner 已数值复验，执行期独立复算钉门）**

落点方程（highlights 侧；shadows 镜像 `f = K − g(K−a; K−C)`）：

```
f(K) = K + g_m(a−K; C−K) = t,   g_m(Δ,H) = Δ·(1+(Δ/H)^m)^(−1/m) = (Δ^−m + H^−m)^(−1/m)
精确形：t = a − N（N = 高光 pull-back，有效域 N ≥ a − C ⟹ t ≤ C）
简化臂（废）：t = C − N
```

- **m=1 闭式**：通分展开 `K² − 2tK + t(a+c) − ac = 0` → `K = t ± √((t−a)(t−c))`
  ——**有效根选择**：物理域要求 room `H = C − K > 0`，故 highlights 取
  `K = t − √`、shadows 取 `K = t + √`；被拒根实证 `H < 0`（本波复验：
  a=8/C=4.2/N=4.05 时 rejected 根 H=−0.756）。`9f4a649` 的符号修复在此框架下
  逐字成立（闭式与落点语义无关，t 换源即可）。
- **m≥2 多项式归约**：代换 `v = C−K`（`u = a−K = v+d`，`t−K = v+s`，
  `d = a−C`，`s = t−C ≤ 0`）得 `(v+d)^−m + v^−m = (v+s)^−m`，通分去负幂：
  `v^m(v+s)^m + (v+d)^m(v+s)^m − v^m(v+d)^m = 0`——**2m 次多项式**。m=2 为
  四次式；m≥3 时阶 ≥6，**Abel-Ruffini ⟹ 一般根式解不存在**。
- **m=2 也不走解析**（双杀）：四次式在物理根邻域呈**多根/切点谷**——本波
  数值复验（a=8/C=4.2/N=4.05/m=2）：真根 `v*=2.9687`（fq(v*)≈0）但
  `fq(0)=+0.90`、`fq(2)<0`、`fq(50)>0`——区间 (0,2) 另有增外根、真根附近
  不保号，**对多项式套 bracketing 必错根**（DECISIONS §5「切点深谷多根」的
  精确机理）；Ferrari 根式在近重根处灾难性相消。**落点函数 F(K) 本身**则
  严格递增（`F'(K) = 1 − (1+w)^−(m+1)/m·(1+w^((m+1)/m)) > 0`，w∈(0,∞) 内部
  严格）且在有效域根处 `F'(K*)` 有正下界（复验 m=1/2/4/8 → 0.34/0.18/0.09/
  0.05）——**对 F 二分必收敛、条件良好**。此即「保留二分」的数学正本。
- **换锚消解实证**：旧简化臂（t=C−N）同锚集复现深根 K_h=−5.73（与验收
  Python 复算逐位一致）；exact 形 + 有效性规则下根条件良好，且联合双侧
  `K_s < K_h` 恢复（m=2 Fit 边距复验 K_h=+1.231 / K_s=−1.783 / core 3.015）。

**落地动作**：
1. `solveKnee` 语义换 exact 形（`t = negativeSide ? a + pullBack : a −
   pullBack`）+ 锚改为**注入参**（现状场景/介质常数不再内嵌于求解调用——
   resolver 传入；常数保留为 fallback 消费点）；域守卫：`t > C − roomFloor`
   （highlights）/`t < C + roomFloor`（shadows）→ 返回 typed
   `.invalidDemand`（或 optional 化——执行期按调用面最小扰动选型，DECISIONS
   记录）；safeguarded Newton 体（bracket + fixed iterations）原样保留。
2. Params v2（裁决 4）：resolved knees additive；`commitParams` 直包 uniforms
   （**solveKnee 移出 GPU commit 路径**——解析发生在 App resolver 提交时，
   与 `FilmMethodBox` solved-pack 同构）；`placementGain`（CPU 参考孪生）加
   resolved-face 入口（golden 双驱）。identityJSON 恒等点零移（inactive
   knees = 既有早退）。
3. **golden 钉锚更新清单（T1 同批）**：
   - 门 3 重构：m=1 双侧闭式（exact t 语义）+ m≥2 vs 独立二分（独立复算
     按新 t）+ 单调/渐近线（保）；
   - **新增公开参考值向量**：RFC-023 §6.4 表四行八值（a_h=+8/C_h=+4.2/
     a_s=−7/C_s=−4.3/m=2；N=(3.90,2.80)→(K_h,K_s)=(+2.278,−2.703)；
     (4.05,2.95)→(+1.231,−1.783)；(4.50,2.95)→(−1.011,−1.783)；
     (4.05,3.40)→(+1.231,+0.266)）——**planner 已数值复验逐位命中**（3 位
     小数），公开参考值口径（RESEARCH §6-1）；
   - **联合排序门（反向钉死）**：有效 N 对 → `K_s < K_h` 断言（kernel
     「K_s < K_h by construction」注释恢复为真并测试钉死）+ §6.4 第五行
     交叉对 → typed 拒绝（负测）；
   - resolved-face 逐像素 golden（placementGain 双入口同值）；
   - 实测值通道改 `XCTAttachment`/落盘（obs-5：直启宿主吞 print）；
   - 哨兵 `filmRampPlaneHash` 预期**不翻**（placement 不在哨兵链——执行期
     亲证；若翻 = 按 M3-3-03 §2 重钉流程：DECISIONS 登记变更 → 重算 → 同
     commit 重钉）。
4. 既有测试零改面：确定性门 suite（键折叠/整数秩/跨 ROI）不动——本波不改
   stats 腿与 solve cache 语义（descriptor 另立键域，见 KD-2）。

### KD-2 B：descriptor 运行时臂（T2）

- **值类型（Core `Film/FilmDescriptor.swift`）**：`ProfileLatitudeDescriptor {
  evMin/evMax, usefulShadowEV, usefulHighlightEV, referenceEV, response[N],
  slope[N], materialPairHash }`（RFC-023 §8.3 字段面；`response/slope` = 诊断
  用 T(E) 及其导数）。**ISO 6846 归约 = 纯函数**（LAYERS 可测）：`Y_white =
  plateau max`、`Y_black = plateau min`；`useful_highlight_ev` = 首个
  `Y ≥ Y_black + 0.9·(Y_white−Y_black)` 的 E；`useful_shadow_ev` = 首个
  `D(E) ≤ D_black + 0.04` 的 E（`D = −log10(Y/Y_white)`，ε 钳）；`reference_ev`
  = 中点密度对应 E（执行期对齐 `FilmPrintBake.solveExposureCalibration` 的
  mid 锚，sanity 带 |reference_ev| ≤ 0.5）。
- **probe（Core `Pipe/Film/FilmDescriptorProbe.swift`）**：1024×1 float32
  ramp 程序化生成 → film 腿 payload 组装（**复用既有组装**——`PixelPipe`
  私有腿抽 internal factory，probe 与真链同一构造路径，§8.1「same code path
  as the picture」；PixelPipe 增量 = 抽 factory 零行为 diff，film 腿既有测试
  零改全绿为门）→ `film_subrun` 派发 → fence 读回（L014）→ 归约。probe 配置
  （ramp 长度/E 网格/record 形态）= 编译期常量 + tag 折入缓存键。
- **缓存**：pairHash 键（01 的 `FilmMaterialStore.materialPairHash` 单源——
  profile 字节已覆盖）；NSLock + LRU 4（`FilmSolveCache` 同构；值域无关不共
  cache——descriptor 与 solve 分键域）。会话级重算入口 = pair 变更事件。
- **golden（T2 同批，RESEARCH §6-4 口径）**：T(E) 单调非降；portra_400 ×
  portra_endura 端到端宽度 sanity 带（上游实测 ≈8.5 stop → 带
  [6.5, 10.5] 执行期实测定值收窄 + DECISIONS 记依据）；`reference_ev ≈ 0`
  标定带；确定性 = 同 pair 双 probe bit-identical + 跨 fresh payload 实例
  相等；ISO 归约手算向量（合成 T(E) 折线 → 边界 EV 手算对表）。

### KD-3 C：FSIM-02 宽容度面板 + 置位编辑面（T3，硬序 A/B 后）

- **宽容度节（filmPageActive 列内新 section）**：
  - 直方图：film stats 快照（`FilmStatsSeam.PlaneHistogram` 经 coordinator
    additive 只读面；luma 通道）绘 EV 轴（bin→EV 换算同裁决 3；轴窗
    [−12,+12] 与 probe 域一致；stats 未到 = 占位态）；canvas/SwiftUI shapes
    纯绘制，零新 kernel。
  - 双虚线：descriptor `usefulShadowEV/usefulHighlightEV` 两线（film off 或
    descriptor 未到 = 虚线缺席 + 注记，不造假数据）。
  - 占比读数：低于/内/高于三值 = 直方图计数对 EV 阈值的精确分箱和
    （`v_edge = 0.184·2^E` 线性阈；跨界 bin 归入内侧 + ≤1 bin 容差注记
    DECISIONS 登记）；手算向量测试（合成直方图）。
  - 教导两条（裁决 7）+ fallback/占位注记文案。
- **置位编辑面（同节下半；T1+T2 落地后开工）**：
  - 无 filmPlacement 实例 → 「添加场景置位」入口（**既有 add 命令面**，
    NodeGraphCommand 零 diff）；有实例 → 参数编辑。
  - N_h/N_s 滑杆：域 = `[max(0,(a−C)+margin), 上限]` **动态最小值**（裁决
    5①；fallback 锚时随 fallback 值）；D-H1 三件（拖动 live 零 item、松手
    一 commit——commit 内容 = resolver 以当前锚+descriptor 解出的 resolved
    knees + pull-backs 一次写入，M2-5 per-op provider 形态）。
  - m 步进器（[1,8]，0.5 步进；不变更 V50/params 键族）。
  - **有效性呈现**：规则②违反 = typed 错误行**点名滑杆**（「高光回退不足/
    阴影回退不足」），拒绝写入（滑杆回弹到上次有效值）；禁静默钳制。
  - **Fit 按钮（§9.3 默认政策）**：`N = (a−C) + 0.25` 每侧；膝点交叉 →
    不足额按两侧溢出比例分摊并报告；某侧 `a ≤ C` → 该侧 off（滑杆归零，
    §9.3 简并态）。Fit = 一次 discrete commit。
  - **§9.2 三 readouts**：identity core 宽度（K_h−K_s）/ 双侧落点 EV /
    双侧端点斜率 `f'(a∓)`（g'_Δ 域公式）——只读行 + Solve 式刷新。
  - resolver 输入锚 = live stats + descriptor 缓存；两者缺任一 = fallback
    常数锚 + 面板注记（裁决 3）。
- **zh**：`latitude_*` 键族 append 尾部（含两条教导文案、 Fit/拒绝/readout
  标签、占位注记；全部静态键——F-2 插值禁令；材料名/技术专名不翻译口径同
  M3-3-03）；`zh-audit --check` PASS 门（键清单并集口径，SUMMARY 报实数）。
- 测试（APP）：宽容度节投影（有/无 stats、有/无 descriptor 四态）、占比
  手算、Fit 三政策分支、拒绝呈现与回弹、置位 commit 单漏斗、教导键静态性、
  fallback 注记态。

### KD-4 D：Film 页走查补课（T4，随 T3 证据同批）

- **click-dead 旁路**：现状 Film 页唯一入口 = 画布卡 tap
  （`EditorNodesPanelView.swift:532` `openFilmPage`）——合成事件环境不可达
  （M3-3-03 §6 登记）。旁路 = App 菜单命令「显示胶片面板」（View 菜单，
  静态键；菜单 commands 所在文件 read_first 7 亲核实位后实名——预判
  `LightamerApp` 组装根或 App/Shell 菜单文件）。卡 tap 原样保留（双入口并
  存）；click-dead 本体维持「登记 + 人工真机复核」处置不变（合成事件限制
  非本波修复面，VALIDATION 挂账单 carry）。
- **走查单**（证据落 `.work/gui-acceptance/m3-4/` MANIFEST，§3.2 视口关键区
  截图纪律）：旁路入口开页 → Film 页挂载/材料切换重渲/Y·M·强度·曝光滑杆
  D-H1/宽容度节双虚线与占比随图变化/置位滑杆动态最小值与拒绝呈现/Fit 一次
  commit/readouts 数值/教导文案呈现/zh 全键呈现/pristine 面（无 record 文档
  逐字节现状）/undo 一次回退全节。合成输入不可达项如实记 Manual-Only 行 +
  配方。

### KD-5 P1 收口（T5）

- 定向轮：IOPP + LAYERS + APP 三 bundle 绿（0 fail）；登记三方对表
  （BUNDLE-MAP 增行实数 × Project.swift × 文件 `func test` 实数——L041 批尾
  generate，登记随文件同 commit）。
- AGENTS「M3-4 架构增量」节：descriptor 形态与键域 / Params v2 迁移与 v1
  degrade / 有效性规则单源（resolver）/ 封存面清单与 PixelPipe factory 扩面
  申报 / fallback 锚降格注记。
- SUMMARY：P1 增量对账（3152 + 登记增量，逐 bundle）+ P2 交接面（终验轮
  基线、走查 Manual-Only 行、挂账 carry 清单）；DECISIONS = §A 推导转录 +
  标定值（H_min/margin/sanity 带/占比容差）+ 哨兵核验记录。
- GOAL-STATE 续接点 → P2（M3-4-02 VALIDATION）；TODO 清账。

## read_first

1. `.work/gsd/phases/m3-3-fsim/M3-3-03-ACCEPTANCE.md`（§三 独立推导 + §十
   obs-5/obs-6 硬序正本）+ `M3-3-03-DECISIONS.md` §5/§7（m≥2 根深登记 + 扩面
   申报口径）+ `M3-3-03-SUMMARY.md` §八（交接四条）。
2. `/Volumes/UNITEK/Documents/Development/SpektraLab/rfc/RFC-023-scene-latitude-mapping.md`
   §5.4/§6.1/§6.4/§7.3/§8/§9（GPL 只读，公式级转录零复制纪律——§6.4 表 =
   golden 向量源、§9.2 = 求解形与 validity rules、§8 = descriptor 方法与
   ISO 6846、§9.3 = Fit 政策）。
3. `LightamerIOP/Sources/FilmPlacement/FilmPlacementModule.swift`（solveKnee/
   anchors/commitParams/placementGain 全文——T1 改造对象）+
   `LightamerCore/Sources/Pipe/Film/FilmTailPolicy.swift`（FilmStatsSeam/
   percentileBin/exposureGain/FilmMethodBox.Params 先例/FilmGPUPayloads/
   FilmSolveCache 键域）。
4. `Tests/LightamerTests/FilmGoldenTests.swift`（门 3 现状与比较空间纪律
   L048——重钉对表基面）+ `FilmDeterminismTests.swift`（键折叠精确值/哨兵
   重钉流程）+ `.work/gsd/phases/m3-3-fsim/M3-3-03-DECISIONS.md` §1/§2（门
   结构与标定口径）。
5. `App/Sources/Lightamer/UI/Shell/FilmPanelModel.swift` / `FilmPanelView.swift`
   （三级读/单 commit/D-H1 既有面——扩节基底）+
   `App/Sources/Lightamer/State/PipeCoordinator.swift`（只读三面先例——stats/
   descriptor 面 additive 仿形）+ `InspectorState.swift`（filmPageActive）。
6. `LightamerCore/Sources/Pipe/PixelPipe.swift` `runFilmLeg`（:1038 起——
   payload 组装内位与 factory 抽取面）+
   `LightamerIOP/Sources/Common/ScopeReduce.swift`（直方图 shape 契约）。
7. App 菜单 commands 实位亲核（`grep -rn "CommandMenu" App/Sources`——旁路
   入口落点实名，front-matter 预判触点兑现或 C 档回注）+ M2-5 per-op
   provider 先例（`GradeCatalog` 件族面板 provider 文件——置位参数写路径
   仿形，grep `FilmPlacementModule` 消费点）。
8. `.work/gsd/phases/m3-2-fsim-research/RESEARCH-NOTES.md` §1.2/§4.2/§6-4 +
   `M3-2-CONTEXT.md` 裁决记录（OQ-M3-2-2③/④/⑦ 生效值）+
   `.work/gsd/research/SPEKTRALAB-NOTES.md`（宽容度面板语义与教导两条原文）。
9. `Resources/Localizable.xcstrings` 尾部追加纪律 + `Scripts/zh-audit.py
   --check` + `.work/gsd/phases/m2-9-export/M2-9-05-SUMMARY.md` F-2 禁令。
10. `.work/LESSONS.md` L014（fence）/L041（批尾 generate + 登记随文件同
    commit）/L048（比较空间）/L055（直启 verdict）+ AGENTS 资源监控节
    （定向轮口径）。

## 纪律（强制）

1. **封存面清单**：`DrtPanelModel/DrtPanelView/DrtRecord`、`TerminalTailPolicy
   /DrtTailAssembly`、`Lut3dKernels.metal`、`FilmSubRunKernels.metal`（零新
   kernel——直方图/双虚线/占比全 App/Core 侧纯计算）、`DrtEotf`、
   `ExportQueueContract`、六格式导出矩阵、`NodeGraphCommand.swift`、
   `PipelineDocument.swift`（Core）、sidecar schema（v9 零触）、`V50Order`/
   `GradeCatalog`（零 catalog 行变更）、`HistoryStack/HistoryHash`（placement
   参数走既有 grade 参数持久化面，零新 history 键族）。`PixelPipe.swift` 唯一
   增量 = factory 抽取（预申报，零行为 diff 门）。
2. **硬序检查**（checker 条目）：T3 diff 中不得出现置位编辑面代码早于 T1/T2
   commit 的痕迹（commit 序即证据）；T1 落地前 golden 门 3 不得放宽任何断言
   （重钉 = 换语义等强度替换，非放松）。
3. **错根防护**：任何 solveKnee 行为变更必须先落 §6.4 向量测试再动产线
   （测试先行同批）；solver 改动后 §6.4 四行 8 值 + m=1 双侧精确 +
   排序门全绿才可继续 T2。
4. **测试登记**（E2/L041）：三新测试文件同 commit 登记（FilmDescriptorTests
   = LAYERS；FilmLatitudePanelTests = APP；resolver/golden 重钉入既有
   FilmGoldenTests = IOPP 行内实数修订）；generate 恒批尾。
5. **既有测试零改**为门：确定性门 suite 五法、NodeGraphCommandTests、
   DrtPanelModelTests、film 腿既有测试（PixelPipe factory 抽取的零行为门）
   零 diff 全绿；任何需改 = 停下上报。
6. **checker 四条**：①真链（descriptor probe 走真 film 子运行 + fence 读
   回；禁任何「并行实现第二套数学」的 descriptor 捷径）；②登记闭环（三方
   对表 + 终值 = 3152 + P1 增量对账链）；③语义断言（§6.4 向量 + 排序门 +
   拒绝门 = 错根反向钉死；golden 参考函数测试文件内自包含不复用产线
   solver）；④边界核对（封存面零命中 + 硬序 commit 序 + zh 键清单并集）。

## Tasks

### T1 A：精确锚替换 + Params v2 + golden 重钉（KD-1，硬序第一）

- **action**：`FilmPlacementModule` 精确落点语义 + 锚注入 + typed 域守卫 +
  Params v2（resolved knees additive + v1 degrade）+ commitParams 直包
  uniforms + placementGain resolved-face；`FilmGoldenTests` 门 3 重构 + §6.4
  向量 + 排序门 + 拒绝门 + XCTAttachment 通道；哨兵亲证。
- **验收标准**
  - [ ] IOPP 定向轮绿；§6.4 四行 8 值 golden 全中；K_s<K_h 排序门 +
        交叉拒绝负测在册；v1 decode（全零/非零两态）负测钉死；确定性门
        suite 零改全绿；哨兵核验记录入 DECISIONS。

### T2 B：descriptor 运行时（KD-2）

- **action**：`FilmDescriptor` 值类型 + ISO 6846 归约 + 缓存；
  `FilmDescriptorProbe` 真链 probe + `PixelPipe` factory 抽取（零行为 diff）；
  `FilmDescriptorTests`（LAYERS）。
- **验收标准**
  - [ ] LAYERS 定向轮绿；T(E) 单调 + portra 带宽 sanity 带 + reference_ev
        标定带 + bit-identical + 手算向量全绿；film 腿既有测试零改全绿
        （factory 零行为门）。

### T3 C：宽容度面板 + 置位编辑面（KD-3）

- **action**：FilmPanelModel/View 扩节（直方图/双虚线/占比/教导/置位
  N·m·Fit/readouts/有效性呈现）+ PipeCoordinator additive 读面 + per-op
  provider 写路径 + `latitude_*` 键块 + `FilmLatitudePanelTests`（APP）+
  登记同 commit。
- **验收标准**
  - [ ] APP 定向轮绿；占比手算向量 + Fit 三分支 + 拒绝回弹 + 四态投影
        全绿；`zh-audit --check` PASS（实数入 SUMMARY）；DrtPanel 族零 diff。

### T4 D：走查补课（KD-4）

- **action**：菜单旁路入口（read_first 7 实名）+ 走查单全项 +
  `.work/gui-acceptance/m3-4/` MANIFEST（Manual-Only 行如实）。
- **验收标准**
  - [ ] 证据落盘；旁路入口可达 Film 页；卡 tap 双入口并存；
        click-dead 维持登记态（挂账 carry 行写入 SUMMARY）。

### T5 P1 收口（KD-5）

- **action**：定向三轮 + 登记三方对表 + AGENTS 增量节 + SUMMARY/DECISIONS/
  GOAL-STATE/TODO。
- **验收标准**
  - [ ] IOPP/LAYERS/APP 三轮 0 fail；终值 = 3152 + P1 增量两式互证
        （登记面 + Executed 面）；AGENTS 四件齐（形态/迁移/规则单源/封存
        面 + 扩面申报）。

## 验收标准（AC 总表）

| # | AC | 机检方式 |
|---|---|---|
| 1 | 精确锚替换落地：exact 落点 + 锚注入 + typed 域守卫 + Params v2 迁移；§6.4 向量 golden + 排序门 + 拒绝门全绿（错根反向钉死） | T1 测试 |
| 2 | descriptor 运行时：真链 probe + ISO 6846 归约 + pairHash 缓存；单调/带宽/标定/确定性四门全绿；零并行数学 | T2 测试 + 读码 |
| 3 | 宽容度面板：直方图 + 双虚线 + 占比读数 + 教导两条；置位编辑面（动态最小值/拒绝点名/Fit/三 readouts）；D-H1 单 commit | T3 测试 + 走查 |
| 4 | Film 页走查补课：旁路入口 + 走查单全项证据；click-dead 登记态 carry | T4 证据 |
| 5 | pristine 直通 + 密封面零命中（PixelPipe factory 唯一申报增量，零行为门） | 负测 + diff 机检 |
| 6 | 登记闭环（E2/L041，登记随文件同 commit）+ zh 键清单 PASS | 三方对表 + zh-audit |
| 7 | **SC 门**：IOPP/LAYERS/APP 定向轮 0 fail；终值 = 3152 + P1 登记增量（两式互证）；golden 门 3/确定性门 suite 在定向轮覆盖 | T5 日志 + SUMMARY |

## 风险与边界

- **错根 = 本波最大风险**：对策 = 纪律 3（测试先行 + §6.4 向量 + 排序门 +
  拒绝门三重反向钉死）；任何向量失配 = 停下排查，**禁反向改参考迁就产线**
  （参考 = 独立真相）。
- **高 m 交叉物理性**：m≥4 窄介质 Fit 边距下规则②拒绝 = 预期（复验在案，
  DECISIONS 登记 §6.4 第五行同型语义）；面板不得「修好」它（禁静默钳制）。
- **PixelPipe factory 抽取**：结构必经预申报；若执行期发现组装面超出私有腿
  （如需触 GPU payload 类型公共面），停下按 C 档回注，禁静默扩公共 API。
- **统计量化容差**：256 bin 线性域在深阴影的 EV 分辨率 ~0.3-0.6 stop/ bin
  （锚与占比的量化界，DECISIONS 登记公式）；EV 域分箱升级 = 未来项不入
  本波（确定性机器已钉 256-bin 语义）。
- **哨兵翻转**：placement 不在哨兵链的预判若被推翻，按重钉流程同 commit
  处理，禁跨 commit 漂移。
- **v1 非零档 degrade**：真实面为零的断言若被现场数据推翻（发现真实非零
  placement 档）= 停下上报（迁移语义重裁）。

## 提交约定

- T1 `fix(iop): exact landing semantics with resolved knees for film placement`
- T2 `feat(core): film latitude descriptor runtime probe`
- T3 `feat(app): film latitude panel with placement editing`
- T4+T5 `docs(m3-4): p1 wave closeout with walkthrough evidence and ledgers`
- 全英文 Conventional Commits；不 push；登记随文件同 commit（minor-2 教训）。
