# M3-4-01-SUMMARY — FSIM-02 宽容度面板代码波（wave 1）

> 执行：2026-10-09/10 夜间 executor subagent worker（「开跑，不要停」在案）。
> 五任务硬序 T1→T2→T3→T4→T5 全闭环；六个 commit 未 push：
> `a3a34af` fix(iop) → `383d829` feat(core) → T3 feat(app) → T4 feat(app) →
> 本 docs。**对账基线 3152/16/0；本波定向轮终值 = IOPParity 408/3/0 + Layers
> 378/3/0 + App 686/0/0（其余四 bundle 未触，全套终验轮 = P2 M3-4-02）。**

## 一、交付面

### T1 精确锚替换 + Params v2（KD-1，obs-6 硬序第一）`a3a34af`
- `solveKnee` exact 落点（t = a∓N）+ 锚注入（M3-3 常数降格 no-film fallback）
  + typed 域守卫（optional 化，nil = invalidDemand）+ m≥2 深膝 bracket 确定性
  几何扩张（高 m 根深超出朴素界：m=8/N=8 根 ≈−60）。
- Params v2：resolved knees additive optionals（k/h × shadow/highlight）；
  v1 零档字节零漂移、非零档 typed degrade 到默认 identity（裁决 4）。
- `commitParams` 直包 uniforms（solve 移出 GPU commit 路径）；`clamped()` 膝点
  穿透；`placementGain` resolved-face；`validateCoreOrder` 联合规则②单源。
- golden 门 3 重钉（12→16 法）：**§6.4 四行 8 值公开参考向量**（文件内独立
  solver，worst 残差走 XCTAttachment）+ 联合 K_s<K_h 排序门 + 第五行交叉拒绝
  负测 + 域守卫负测 + resolved-face 逐像素（in-file 参考 knees 双驱）+ v1
  degrade 负测；m=1 双侧闭式 + 渐近线 + 单调全保。**§6.4 向量独立复算全命中
  （±5e-4）；F'(K*) 0.3188/0.1672/0.0869/0.0447（highlights m=1/2/4/8）、
  0.3493/0.1873（shadows）逐位亲证（checker m1）**。

### T2 descriptor 运行时（KD-2）`383d829`
- `ProfileLatitudeDescriptor` + ISO 6846 归约纯函数（E1 修正判据式：阴影端 =
  升序最后一个 `D ≥ 0.9·D_black`）+ `FilmDescriptorCache`（fnv(pair⊕tag)，
  LRU 4）。
- `FilmDescriptorProbe` 真链 probe：1024×1 中性 ramp 过 `PixelPipe.
  assembleFilmLeg`（产线 factory，本次抽取，**film 腿测试零改全绿 = 零行为门**）
  + FilmMethodBox runContext 缝派发 + L014 fence 读回；响应列 = **print
  reflectance 面**（链输出 10^e 经链自身前向 `systemDensity` 回映射——scan
  seam，DECISIONS §2；scene 面直接归约与上游实测表全盘失配，唯一正解）。
- 实测：**useful pair [−1.4663, +4.4485] = 5.9148 stop**（带 [4.0,7.5] 内，
  上游 ISO 锚 5.66 对照）；**reference_ev = +0.068**（mid 锚读法，|·|≤0.5 带）；
  bit-identical 双 probe；T(E) 单调（lattice 带 2e-3 + plateau 面豁免，边界
  语义不变）。
- FilmDescriptorTests（LAYERS，7 法）全绿；确定性门 suite 五法零改全绿
  （**哨兵未翻 = placement 不在哨兵链预判成立**）。

### T3 宽容度面板 + 置位编辑面（KD-3）
- `PlacementResolver`（有效性单源）：anchors（stats P99.9/P0.1 整数秩 +
  descriptor useful 对；缺任一 → fallback 常数 + 注记）/ 动态最小值（①侧别
  显式式）/ resolve（②typed 拒绝）/ Fit（§9.3：0.25 margin、a≤C 侧 off、
  m≥3 交叉 λ 比例分摊（落点=双侧 off 简并，m=3 例 −0.602/−0.293 亲证）、
  H_min=3.0 建议面守卫）/ 端点斜率（§6.4 发布值 0.0648/0.0820 逐位）。
- FilmPanelModel/View 扩节：宽容度节（EV 轴直方图 [−6.5578,+2.4394] 原生跨度
  + 双虚线 + 低于/容纳/高于占比（整 bin 分类 ≤1 bin 容差）+ 教导两条 +
  fallback/缺席注记）+ 置位节（N_h/N_s 动态最小值滑杆 + m 步进 + Fit +
  三 readouts + 拒绝红行点名滑杆 + 回弹）。stats 投递 = m5 机制 (b)(c)
  （Registry LastValue 槽 + coordinator 镜像）；descriptor cache-first。
- 写路径 = M2-5 per-op provider 形态（宿主层路由；add = addAdjustmentLayer +
  addModuleToLayer 既有命令面，零新命令）。
- `latitude_*` 25 键 + `history_film_placement` 静态键尾部追加（原序零触碰）；
  zh-audit --check PASS（**1584/1822**，含 T4 menu 键）。
- FilmLatitudePanelTests（APP，**11 法**——MAP 初记 9 已勘误）：E3 门（§6.4
  四行在有效性面全部可写入 + 第五行拒绝 + 逐侧 demand 拒绝）+ Fit 三分支 +
  占比手算两形 + 锚三态 + 端点斜率 + session 提交/回弹 + 教导键静态。

### T4 走查补课（KD-4）
- View 菜单「显示胶片面板」无门静态旁路（三电路零触，WorkspaceRoutingTests
  11/0/0）+ 卡 tap 双入口并存。
- **两项结构发现（已修/已立）**：①胶片页默认面结构不可达（InspectorView 宿主
  只挂于 export-armed `.inspector`——binding 扩 `exportPageActive||
  filmPageActive`，present 侧 no-op 防回声盖写）；②DEBUG 探针缝 `-la_film_probe`
  （合成输入环境下菜单/画布全惰的走查通道）。
- 实机证据链（`.work/gui-acceptance/m3-4/` MANIFEST 十项）：挂载（pristine +
  教导两条）→ 启用（默认对 + Solve 读数 M 18.3·Y 16.7·×1.00）→ **双黄虚线 +
  占比读数实机落地** → 置位节（滑杆/m/Fit/readouts）→ **N_h 拖拽 2.12 EV
  （落点 +0.32 = a−N 精确、核宽 0.27、斜率 0.435 实时）** → ⌘Z 恰一回退 →
  Fit 落地 N_s=5.15 + 高光侧 §9.3 简并关闭 → **typed 拒绝行实机红字 + 真相
  回弹**。Manual-Only 四行（菜单合成激活/m 步进/材料切换/占比随图）配方在册。

### T5 收口（本批）
- 终态定向三轮：IOPParity **408/3/0**（471s）+ Layers **378/3/0**（162s）+
  App **686/0/0**（348s）——0 fail、零 MEMFAIL、verdict ok（L055 双保险末行
  OK direct launch）。
- 登记三方对表两式互证：BUNDLE-MAP（IOPP FilmGoldenTests 16 / LAYERS
  FilmDescriptorTests 7 / APP FilmLatitudePanelTests 11【9→11 勘误当场改】）
  × Project.swift 三处 × 文件 `func test` 实数（16/7/11）；执行面增量
  IOPP 404→408（+4）/ Layers 371→378（+7）/ App 675→686（+11）= **+22**；
  账面 3152 + 22 = **3174**（P2 全套轮对表基线）。
- AGENTS「M3-4 架构增量」节 + GOAL-STATE 续接点 + TODO 清账（本批）。

## 二、AC 总表核验

| # | AC | 判定 |
|---|---|---|
| 1 | 精确锚替换 + Params v2 + §6.4 向量/排序/拒绝门 | ✅ T1（IOPP 408/3/0） |
| 2 | descriptor 运行时（真链 probe + ISO 判据 + pairHash 缓存；零并行数学） | ✅ T2（LAYERS 378/3/0） |
| 3 | 宽容度面板（原生轴窗 + 双虚线 + 占比 + 教导；置位面动态最小值/拒绝点名/H_min 建议面/Fit/三 readouts；§6.4 四行可写入；D-H1 单 commit） | ✅ T3（App 686/0/0） |
| 4 | 走查补课（旁路入口 + 证据链 + click-dead carry） | ✅ T4（MANIFEST 十项 + Manual-Only 四行） |
| 5 | pristine 直通 + 密封面零命中 | ✅ sealed-face diff 机检（T3/T4 两批亲跑零命中；PixelPipe 唯一增量 = factory 预申报） |
| 6 | 登记闭环 + zh PASS | ✅ 三方对表（含 9→11 勘误）+ zh-audit 1584/1822 PASS |
| 7 | SC 门：定向轮 0 fail + 两式互证 + golden/确定性门覆盖 | ✅ 三轮 0 fail；+22 两式互证；golden 16 法于 IOPP、确定性 5 法于 LAYERS 亲跑 |

## 三、偏差与执行期发现（全登记，DECISIONS 正本）

1. clamped() 丢 knees（T1 首轮 3 红根因）——修 + 测试覆盖。
2. F 单调方向注释勘误（简化臂病理措辞残留）——exact 形改正。
3. 深膝 bracket 扩张（m=8/N=8 根 ≈−60）——确定性几何扩张，参考 solver 同形。
4. scan seam（descriptor 域裁定）——见 DECISIONS §2。
5. T(E) lattice 单调带 2e-3 + plateau 豁免——门语义保持，DECISIONS §2。
6. 胶片页默认面不可达（M3-3-03 遗留集成缺陷）——binding 修复 + 实机证据链。
7. DEBUG 探针缝 `-la_film_probe`——合成输入环境的走查通道（#if DEBUG）。
8. FilmPlacementTests/FilmPlacementKernelTests 等强度重钉——front-matter 外
   申报（语义孪生，不修必红）。
9. BUNDLE-MAP FilmLatitudePanelTests 9→11 勘误（初记漏计，当场改）。
10. 合成激活环境限制（菜单/画布/步进器全域）——Manual-Only 四行 + 对照实验
   （既有命令同惰）在册。

## 四、P2 交接面（M3-4-02 VALIDATION）

- **全套 `--all` 终验轮**：对账基线 = **3174/16/0**（3152 + 22）；运行门
  8G + orchestrator 批准 + 运行监视（AGENTS 资源监控节）；L055 判读双保险。
- **挂账 carry**：
  - Film 页 click-dead 本体（画布卡合成点击）——登记态维持，人工真机复核
    （本波旁路入口 + 探针缝已使页面可达性不再依赖它）。
  - 走查 Manual-Only 四行（菜单命令真机激活/m 步进人工驱动/材料切换重渲/
    占比随图）——配方在 MANIFEST。
  - descriptor sanity 带收窄（5.9148 单对证据；多对采样后收窄）。
  - m≥3 Fit 分摊的 λ→0 双侧 off 简并——如需「可行推荐」语义再立项。
  - Fit H_min 在 §6.1 型场景恒拒——如需「放宽建议」语义再立项（§7.3 原义
    保持）。
- **REQUIREMENTS 翻账**：FSIM-02 Delivered + FSIM-01b（精确锚语义收口）
  Delivered——统一在 P2 签核批。

## 五、副作用与卫生

- 走查实例 quit；throwaway 项目（/tmp editor-probe-*.lalb 含 WAL/SHM）清零；
  defaults 零触碰；AI 弹窗「暂不」关闭；/tmp/lat-walk 驱动脚本域（即弃）。
- 未 push（全数本地 commit）。
