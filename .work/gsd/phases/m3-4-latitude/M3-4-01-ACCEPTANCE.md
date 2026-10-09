# M3-4-01-ACCEPTANCE — FSIM-02 宽容度面板代码波（wave 1）独立验收

> 验收方：zcode 独立验收 subagent（零共享上下文，实测核验不轻信；2026-10-10）。
> 对象：五提交 `a3a34af` → `383d829` → `9dc64ba` → `2d580d8` → `ad6c560`（未 push）。
> 前波基线：3152/16/0（M3-3-03 验收亲跑终值）。

## 结论

**PASS / 0 error + 0 minor + 3 obs**（obs 全部登记不修，见 §八；双重验收衔接 = 本 PASS 后 orchestrator 按 `dual_acceptance = true` 另行编排 omp 二次验收，严格串行——本验收未派 omp）。

## 一、定向亲跑（三 bundle，本机直启，L055 双保险）

| bundle | 申报 | 亲跑 | peakRSS | 时长 | 判定 |
|---|---|---|---|---|---|
| IOPParity | 408/3/0 | **408/3/0** | 5344MB | 469s | ✅ 逐位 |
| Layers | 378/3/0 | **378/3/0** | 1148MB | 165s | ✅ 逐位 |
| App | 686/0/0 | **686/0/0** | 2831MB | 350s | ✅ 逐位 |

- 三轮 verdict OK（direct launch，no testmanagerd）、零 MEMFAIL、RSS < 8G 运行门。
- 增量对账两式互证亲算：IOPP 404+4（golden 门 3 12→16）/ Layers 371+7（FilmDescriptorTests）/ App 675+11（FilmLatitudePanelTests）= **+22**；账面 3152+22 = **3174**（P2 全套轮对表基线）。
- 三方对表亲核：BUNDLE-MAP（16/7/11）× Project.swift（:312/:485/:804）× 文件 `func test` 实数（16/7/11）✅。
- zh-audit --check 亲跑 PASS：**1584/1822**（与 SUMMARY 一致）。

## 二、精确锚数学审计（灵魂，独立复算）

### §6.4 参考向量独立复算（uv/Python 全精度二分，独立于产线与测试的第三实现）

| 行 | N=(n_h,n_s) | 我算 K_h / K_s | RFC §6.4 published | 最大偏差 |
|---|---|---|---|---|
| 1 | (3.90, 2.80) | +2.278316 / −2.703316 | +2.278 / −2.703 | 3.2e-4 |
| 2 | (4.05, 2.95) | +1.231272 / −1.783254 | +1.231 / −1.783 | 2.7e-4 |
| 3 | (4.50, 2.95) | −1.011068 / −1.783254 | −1.011 / −1.783 | 2.5e-4 |
| 4 | (4.05, 3.40) | +1.231272 / +0.266124 | +1.231 / +0.266 | 2.7e-4 |
| 5（交叉） | (4.50, 3.40) | K_s=+0.266 > K_h=−1.011 | — invalid | — |

全部 ≤3.2e-4（published 3 位小数 ≤5e-4 门）✅；第五行交叉形态亲证 ✅。落点残差 ≤8.9e-16（t = a∓N 精确）✅。

### F'(K*) 逐位复算（公式 `F'(K) = 1 − (1+w)^−(m+1)/m·(1+w^((m+1)/m))`，w=((a−K)/(C−K))^m）

- highlights m=1/2/4/8 = **0.318808 / 0.167156 / 0.086878 / 0.044667**（DECISIONS：0.3188/0.1672/0.0869/0.0447）✅ 逐位
- shadows m=1/2 = **0.349270 / 0.187345**（0.3493/0.1873）✅ 逐位
- 端点斜率 f'(a∓) = (1+w)^−(m+1)/m：**0.064799 / 0.082035**（§6.4 发布 0.0648/0.0820）✅

### 派生复算

- m=3 Fit-margin 交叉：K_h=−0.602111 / K_s=−0.293292（DECISIONS m6：−0.602/−0.293）✅ 交叉成立、λ 分摊全域无解 ⇒ 双侧 off 简并的数学前提成立。
- m=8/N=8 深膝：根 = **−64.889**（DECISIONS「≈−60」量级内；朴素 bracket −29.2 不含根 ⇒ bracket 确定性扩张必要性实证）✅。

### 产线读码（FilmPlacementModule.swift）

- exact 落点 `t = negativeSide ? a + pullBack : a − pullBack`（:191）+ 锚注入参（:184，M3-3 常数降格 fallback 注记 :127-138）✅
- typed 域守卫 → nil（:194-195，landingRoomFloor 1e-3）✅；m=1 闭式侧别符号（:203-204）✅；m≥2 二分 40 + safeguarded Newton 4（bracket 内接受）✅（RFC §9.2 钦定形）
- bracket 确定性扩张（:221-229，`max(16,|lo|/2)` 纯函数）✅
- `validateCoreOrder` 联合规则②单源（:267）✅
- `clamped()` 8 字段穿透（knees = wire state，:118-125）✅
- `commitParams` 直包 uniforms（solve 移出 GPU commit 路径）+ v1 非零 degrade = `piece.data = nil`（:365-374）✅
- `placementGain` resolved-face（nil knees → 恒等，:314-321）✅

### golden 三负测 + wire 门（FilmGoldenTests.swift 读码）

- 文件内参考 solver `refSolveKnee`（200 步二分 + 同形扩张）**不触产线 solver**（checker ③）✅
- `testPlacementReferenceVectorRFC023Section64`：published ±5e-4 + 产线 ≤1e-8 + landing = a∓N @1e-8 + XCTAttachment（obs-5 通道）✅
- `testPlacementOrderingGateAndCrossRejection`：四行 valid + 第五行 `.kneeOrderViolation` ✅
- `testPlacementDomainGuardRejectsBeyondBoundary`：双侧 0.5/1.5/2.5/2.999 → nil；3.01 → 边缘 valid；N=0 → inactive 非 nil ✅
- Params v2 迁移真实性：v1 零档 wire byte 门（`testV1ParamsTypedDegradeToIdentity` 断言 JSON 不含 k_shadow/k_highlight——Swift 合成 Codable 对 Optional = encodeIfPresent/decodeIfPresent，ParamsCoding.sortedKeys 面单独立亲读）+ 非零 v1 → commit 无 uniforms + twin 恒等 ✅
- 哨兵：`testFilmOutputPlaneHashMatchesTheGoldenSentinel` 于 Layers 亲跑轮绿（14_365_179_805_968_017_957 未翻）；哨兵链 = makeFilmTail 纯模型链（无 grade envelope ⇒ placement 结构性不在链内）——预判成立 ✅

## 三、scan seam 审计（KD-2）

- **E1 修正判据式**（FilmDescriptor.swift:109-144）：useful_highlight = 首个 `Y ≥ Y_black + 0.9·(Y_white−Y_black)`；useful_shadow = 升序**最后一个** `D ≥ 0.9·D_black`（D = −log10(clamp(Y/Y_white, ε))，ε=1e-6）——与 checker E1 处方逐字一致；旧「D ≤ D_black+0.04」常函数退化判据无残留 ✅
- 手算折线向量独立验算：T=[1e-5,1e-5,1e-4,1e-3,1e-2,1e-1,0.5,1,1] → D_black=5、0.9·D_black=4.5 → shadow E=1.0；高光穿越 6.800002 ✅（测试向量正确）
- **scan seam 域裁定**（FilmDescriptorProbe.swift:111-158）：film 腿输出 = scene-referred 10^e（白端携带全程肩部，非介质属性）→ `R = 10^(−systemDensity(log10 out))`，session 项（base 投影/逐通道 Dmin/K 标定/中性包）与 bake 同函数单源（FilmPrintBake.systemDensity）= 「inverse∘forward 于产线函数」，零第二套链 ✅；reference_ev = paperMidDensityLinear mid 锚读法（:169-172，(dmin_g+dmax_g)/2 → 10^(−D)）与 checker E2 处方一致 ✅
- 实测值：useful pair [−1.4663, +4.4485] = **5.9148 stop**（带 [4.0,7.5] 内，上游 ISO 锚 5.66 对照）/ reference_ev **+0.0676**（|·|≤0.5 带）——测试钉死（FilmDescriptorTests 7 法，LAYERS 亲跑绿）✅
- 缓存：key = fnv(pairHash ⊕ probeTag)（exact-FNV 测试钉）+ NSLock + LRU 4 + 分键域 ✅
- probe 真链纪律：`PixelPipe.assembleFilmLeg` factory（产线腿与 probe 同一构造路径）+ FilmMethodBox.runContext 缝 + L014 fence 读回 + nil histogram = gain 恰 1 ✅；factory 抽取 diff 亲读 = 纯搬运（histogram 取数留 call site、solve/assemble 逻辑逐句等价）零行为 ✅

## 四、面板实机抽测（AX 驱动，`-la_film_probe` 会话，MANIFEST 抽二）

会话：Debug 产物 + throwaway 项目（DSC09991.ARW link 导入）+ openFilmPage stay-alive。

### 抽测①：直方图占比读数 verbatim（启用默认材料对 Fujifilm C200 × Crystal Archive Type II 后）

- `film.latitude.share.below` = **「低于 5%」**
- `film.latitude.share.inside` = **「容纳 95%」**
- `film.latitude.share.above` = **「高于 0%」**
- 求解读数 = **「M 18.3 · Y 16.7 · ×1.00」**（与 MANIFEST w2 一致）；教导两条 zh verbatim 在屏（「场景置位作用于胶片模拟之前，显影曝光作用于其后——两者不可互替。」「EDR 位于输出侧，无法找回输入端已损失的高光。」）
- 证据：`.work/gui-acceptance/m3-4/acceptance-shares-reject-crop.png`

### 抽测②：typed 拒绝红行 + 真相回弹复测

- 驱动序列：`film.placement.add`（AXPress）→ N_h 拖至 1.57 EV（CGEvent drag，写入有效）→ N_h 拖至 1.75 EV → N_s 拖向高位 → **`film.placement.reject.knee` 红行实机上屏：verbatim「膝点交叉——恒等核塌缩：请减小高光回退或阴影回退。」**
- **真相回弹双证据**：N_s readout 保持 **0.00 EV**（拒绝 tick 未写真相）+ N_h 保持上次有效值 **1.75 EV**（未被污染）
- readouts 实时自证 exact 语义：落点 readout = **a_h − N_h 精确**（+0.68 = 2.44−1.76）/ 核宽 / 端点斜率随 tick 刷新
- ⌘Z 一次回退复测：**1.75 → 1.57**（恰一 history item = 首个 drag commit），readouts 同步还原（核宽 2.19/落点 +0.87）——D-H1 单漏斗 undo 面复现 ✅
- 证据：`.work/gui-acceptance/m3-4/acceptance-red-row.png` + `acceptance-shares-reject-crop.png`
- 动态最小值实机形态：N_s 滑杆下限 AXValue = **5.1538187…** = (C_s−a_s)+0.25（与 Fit 政策同源式，live stats 锚 a_s=−6.56/binEV 端点自洽）✅

### 实机环境注记

- AI 分析模态弹窗拦截 CGEvent（本轮复现 DECISIONS §5 同款）——AXPress 内容面按钮/命令有效、CGEvent 对模态 sheet 自身有效、对被 sheet 覆盖的主窗口惰；与 MANIFEST「合成输入环境限制」登记同族，处置 = 先关弹窗再驱动。

## 五、mount 修复审计（T4 结构发现 A）

- 根因读码属实：InspectorView（film 分支宿主）在 gate-false 默认面只挂于 `.inspector(isPresented: exportPageActive)`——filmPageActive 翻真无呈现宿主（编辑器右列 = 调整栈）。
- 修复 diff 亲读（ContentView.swift）：binding get 扩 `exportPageActive || filmPageActive`；**present 侧 no-op**（SwiftUI 呈现回声不得盖写活动页——防 export 页被误武装）；dismiss 侧双 close 幂等。export 页行为面零变化（openExportPage 仍由原路径武装；present 回声 no-op 不触达 export 内容）。
- 旁路命令（LightamerApp.swift:1461-1470）：静态无门 Button（menu_show_sidebar 先例）、零 MenuCommandID、零 keyboardShortcut、`accessibilityIdentifier("menu.show_film_panel")`——MenuCommandSet/AppPreferences/WorkspaceRoutingTests 三电路零触（WorkspaceRoutingTests 于 App 轮亲跑绿）。
- 本轮实机即 mount 修复的直接受益者：probe 流 openFilmPage → film 页默认面呈现（pristine 教导面 + 启用入口 + 宽容度节 + 置位节全件 AX 可达）——修复有效性实证。

## 六、逐 commit 边界对照

| commit | 范围 | front-matter/申报面 | 判定 |
|---|---|---|---|
| a3a34af | FilmPlacementModule + FilmGoldenTests + BUNDLE-MAP + **FilmPlacementTests/FilmPlacementKernelTests 等强度重钉** | 重钉 = DECISIONS §5.1 申报（旧语义夹具换 valid demands，断言精度 1e-12 保留——抽查亲读非放松） | ✅ |
| 383d829 | FilmDescriptor + FilmDescriptorProbe + PixelPipe factory + FilmDescriptorTests + Project.swift + BUNDLE-MAP | 全在预申报（factory = PixelPipe 唯一增量） | ✅ |
| 9dc64ba | PipeCoordinator + FilmPanelModel/View + **Registry**（m5 机制 b LastValue 槽）+ 测试 + xcstrings + Project.swift + BUNDLE-MAP | Registry = checker m5 补列文件 ✅ | ✅ |
| 2d580d8 | ContentView（§5.2 申报）+ WorkspaceHostView DEBUG 缝（§5.3）+ LightamerApp 菜单 + xcstrings + 证据 | 全在申报面 | ✅ |
| ad6c560 | 纯 docs（SUMMARY/DECISIONS/AGENTS/GOAL-STATE/TODO/BUNDLE-MAP 勘误） | — | ✅ |

- 硬序 T1→T2→T3→T4→T5 commit 序亲核 ✅（T3 diff 无置位面早于 T1/T2 痕迹——FilmPanelModel/View 均首现于 9dc64ba）。
- 硬序纪律 2 亲读：T1 golden 重钉 = 换语义等强度（published 向量 + 1e-8 产线门），无断言放宽 ✅。
- 密封面：NodeGraphCommand/PipelineDocument/DrtPanel 族/六格式导出/V50Order/GradeCatalog/sidecar/HistoryStack 五提交 diff 零命中（`git diff a2d3c0a..HEAD --` 亲跑）✅；latitude_* = 25 键 + history_film_placement + menu_show_film_panel 尾部追加（原键序零触碰）亲核 ✅。

## 七、会话卫生

probe 实例已 quit；throwaway 项目 /tmp/editor-probe-*.lalb（含 WAL/SHM）与素材 /tmp/acc-m34-src 清零；defaults 零触碰。未 push（本验收 commit 亦不 push）。

## 八、发现项（全部登记不修）

- **obs-1（readouts 核宽 nil-face）**：`placementReadouts` 的核宽 = `(kHighlight ?? 0) − (kShadow ?? 0)`——单侧 off 时把缺失膝当 0（本轮实机：N_h=1.75/N_s off 时核宽显 1.53，真核 = K_h − a_s ≈ 8.3）；双侧 off 显示 0.00。只读行、单侧 off 语境误导、非阻断。建议 P2（nil 侧显「—」或以 inactive knee=a 参与差值）。
- **obs-2（测试注释笔误）**：FilmLatitudePanelTests `testLatitudeSharesHandComputedVector` 注释「v_high = 0.184·2^4.4485 ≈ 4.46」——实为 ≈4.02（2^4.4485≈21.85）；断言（above = 0，阈 >1）语义正确不受影响。
- **obs-3（环境）**：AI 分析模态弹窗拦截 CGEvent 主窗口事件、其「暂不」按钮不在 AXWindows 树（CGEvent 坐标点击有效）——DECISIONS §5/MANIFEST 合成限制登记的同族环境项，非本批缺陷。

## 九、AC 总表复核

| # | AC | 判定 |
|---|---|---|
| 1 | 精确锚 + Params v2 + §6.4/排序/拒绝门 | ✅ §二（复算 + 读码 + IOPP 亲跑） |
| 2 | descriptor 运行时（真链 probe + ISO 判据 + 缓存；零并行数学） | ✅ §三 |
| 3 | 宽容度面板（原生轴 + 双虚线 + 占比 + 教导 + 置位面 + §6.4 四行可写入 + D-H1） | ✅ §四实机 + FilmLatitudePanelTests 11 法亲跑 |
| 4 | 走查补课（旁路 + 证据 + click-dead carry） | ✅ §五 + MANIFEST 十项 + Manual-Only 四行如实 |
| 5 | pristine 直通 + 密封面零命中 | ✅ §六 diff 机检 + 哨兵亲跑绿 |
| 6 | 登记闭环 + zh PASS | ✅ §一三方对表 + zh-audit 亲跑 |
| 7 | SC 门：定向 0 fail + 两式互证 + golden/确定性覆盖 | ✅ §一（408/378/686 + 3174 对账链） |
