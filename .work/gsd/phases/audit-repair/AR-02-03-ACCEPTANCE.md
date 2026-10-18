# AR-02 + AR-03 验收报告 — plan B(M2 codemod)+ plan C(机械小件批)第一路独立验收

> 验收批 = audit-repair AR-02(AR-02-PLAN.md)+ AR-03(AR-03-PLAN.md)第一路
> 独立验收(重派轮;前一轮验收 lane 实为存活并于并行作业,经 orchestrator
> 裁决收编为正式第二路,双路设计恢复)。对象 = 主树 HEAD `0a79685e`
> (执行链 `4452e10c..0a79685e` 8 commits,与申报逐 SHA 一致)。
> 零源码改动;本报告为唯一落盘产物(不 commit)。
> 验收方法 = plan 忠实路线:静态机检亲跑 + 探针 env 门双轮亲跑 + 定向
> App/Library bundle 亲跑 + 全套 --all 持锁独立复跑 + D-6 相对门双构建
> GUI 独立复测(worktree 隔离 + 自建 DerivedData 容器 + nohup 脱离 +
> parentage 纪律全程)。

# PASS / 0 blocking + 0 major + 0 minor + 6 obs

全部机检面与申报逐值一致;全套净轮 `TOTAL|3969/37/0|` 独立复现(逐
bundle executed/skip/fail 逐值精确);D-6 相对门双构建差分带内 PASS;
偏差①-⑧逐条判定等价终形成立。零产线缺陷发现。

## 1 逐任务判定表

| # | 验收项 | 申报 | 验收实测 | 判定 |
|---|---|---|---|---|
| B-1 | codemod 面 | 40 文件 46 处 stored 化 | `private var params:` UI/Inspector/ 零命中;40 文件逐一有 stored `private let params`(GradeScalarPanels 6 struct=6 处,44 处)+ HighpassSoften 双 `private let highpassParams/softenParams`(2 处);40/40 文件带同签名 `init(instance:edit:)`(anomaly 扫描零异常) | PASS |
| B-2 | 恒等式 48=48 | codemod 后 `params(of:` 域内 48 | 亲跑 = 48(38 文件×1 + HighpassSoften 2 + GradeScalarPanels 6 + provider 注释 1 + helper 本体体内 1),与 codemod 前 48 恒等 | PASS |
| B-3 | 闭包捕获 stored | binding 闭包捕获 stored 值 | ChannelMixerRGB 样板 discreteBinding(HEAD vs `e9034d5e`)逐字节同;codemod diff 该文件恰 10 行(仅 property→let+init 面);6 面板抽查(Exposure/FilmicRGB/Lut/ToneCurve/NLMeans/HighpassSoften)捕获面零 var 捕获 | PASS |
| B-4 | Core/helper 零改 | 四文件零 diff + AnyView 缝零 diff | `e9034d5e..HEAD` diff:ModuleInstance / IOPPanelProvider(helper 签名+注册缝)/ LibraryProjectController / LightamerSlider / 封存面全域(IOP/*.metal/Sidecar/DrtRecord/TerminalTailPolicy/PixelPipe/Lut3dKernels.metal)**空 diff**;xcstrings 零 diff;UserDefaults 零新键(diff 面亲扫) | PASS |
| B-5 | T2 探针 | env 门两法 + 登记 +1 行 | 默认轮 `2/2/0`(两法全 skip)+ `LIGHTAMER_PERF_PROBE=1` 轮 `2/0/0` + PERF 行落档(ChannelMixerRGB 7.99µs / Exposure 2.03µs / FilmicRGB 6.91µs);Project.swift 恰 +1 行、BUNDLE-MAP 恰 +1 行(APP 2)、tuist generate 末位(commit 序面核 99394fc3) | PASS |
| C-1 | 五族 grep 清零 | App/Sources 零命中 | showsIndicators: / .foregroundColor( / .menuStyle(.borderlessButton) / .cornerRadius( / onChange 旧形 五族亲跑全零;onCommit 残留 = EditorAreaView/CropOverlayHost/CropOverlayView/LiquifyOverlayHost 自有回调面(误报清单,零 diff);禁形机检两零命中(LocalizationValue 插值唯一命中为注释行;.runModal 零) | PASS |
| C-2 | 43 处逐处对账 | 尾闭包形/换形落位 | 亲核 12+ 处:overlay 6(SessionBrowser :596 / CatalogBrowser :336 / SoftProof :101 / EDR :82 / EditorNodes :612 / CurveEditor :104)+ background 6(FilterBar :114/:218 / SessionBrowser :649 / CatalogFilterBar :198 / Sidebar :417 / CatalogBrowser :380)+ LightamerApp :552(WindowCapture)+ LayersPanel :602 + EditorNodes :611 全尾闭包形;menuStyle ×5 `.menuStyle(.button)`+`.buttonStyle(.borderless)`(两 capsule 处 `.menuIndicator(.hidden)` 原位保留);cornerRadius 14 = clipShape 14(MaskToolbar 11+Segment 1+InstancePicker 2);onChange 双参形 :285 | PASS |
| C-3 | dropDestination | DropSession Void 让渡 | SidebarView :709/:809 guard→no-op 形亲读,move guard 链逐字保留(D-AR3-3 申报形);coordinateSpace `.named(Self.canvasSpace)` factory(:273,与既有 :255/:381 同形) | PASS |
| C-4 | minor 五件 | m1/m4/m5/m7/m8 | m1:EditorAdjustmentStackView AnyView 零命中、row(for:)→`InspectorRowView?`(:445);m4:McpLauncherPanelView ObservableObject/@Published/@StateObject/objectWillChange/`$`投影全零命中、`@Observable @MainActor final class` 六属性在位、:175 `@State`;m5:`@State private var preset` :80 在位;m7:`.task { await model.refresh() }` :376、loaded 旗标零命中;m8:`private static let dateSpellingFormatter` :506 在位(dateFormat 保守口径维持) | PASS |
| C-5 | Yiyin 挂账论据 | siblingInstance class 引用 | 源码亲读:`params`/`bordersParams` 经 `edit.siblingInstance(opName:)` → `coordinator?.instanceRecord`(InspectorEditSession=final class :54)——活会话读,零 stale 论据不成立,D-AR2-3 挂账成立,本批零代码动作 | PASS |
| C-6 | note 族/o6 零触 | 冻结口径 | Font/.system( 35=35、Stepper 2=2、GeometryProxy 0=0(codemod 前后计数同);LutPanelView `.id(libraryRevision)` 零 diff(该文件 diff 仅 params codemod 面) | PASS |
| C-7 | 挂账 3/销账 8 | DECISIONS 登记 | D-AR3-6/-7 在库,各附豁免正本引语;LANEA side-note 两行在库 | PASS |

## 2 测试亲跑终值

| 轮 | 申报 | 验收实测 | 判定 |
|---|---|---|---|
| 探针默认轮 | skip 断言 | `App 2/2/0`(两法 skip,无 PERF 行) | PASS |
| 探针 PERF 轮(env=1) | 2/0/0 + PERF 行 | `2/0/0` + PERF 行 7.99/2.03/6.91µs | PASS(obs 2:FilmicRGB 6.08→6.91µs 计时散布,文档面非门) |
| 定向 App | 921/16/0,326s,2832MB | **921/6/0**,348s,peakRSS 2832MB | PASS(obs 3:skip 16 vs 6,executed 恒 921) |
| 定向 Library | (--all 行 738/4) | **738/4/0**,82s,616MB | PASS |
| **全套 --all(持锁独立复跑)** | **TOTAL\|3969/37/0\|** | **TOTAL\|3969/37/0\|**(2024s,exit 0,零 MEMFAIL) | **PASS** |

全套逐 bundle(验收轮 vs 申报逐值):IOP 687/5/0(7794MB)= 687/5/0 ✓;
IOPParity 460/3/0(7170MB)= 460/3/0 ✓;Layers 494/5/0(723MB)✓;
Library 738/4/0(615MB)✓;Sessions 284/9/0(1621MB)✓;Export 385/5/0
(6420MB)✓;App 921/6/0(2832MB)✓。executed 687+460+494+738+284+385+921
= **3969**、skip 5+3+5+4+9+5+6 = **37**、fail 0 —— 逐值精确闭合;峰值
RSS 全部 8G 机检门内(IOP 7794 最高,SPIKE 贴线族域内波动)。
供件面:worktree 拷入 `input/`(312MB)+ `Resources/AIModels`(194MB)
后净轮,与执行批偏差③配方一致。

## 3 D-6 相对门独立复测(双构建 GUI 差分)

协议 = AR-01 D-AR1-10 钉死形 + M7-1 可见窗门控(frontmost 先行;
遮挡态读数 ~0% 形态在本轮亲证并规避);判定 = 双构建差分 ≤1.9% 噪声带
(2026-10-18 用户裁决相对门)。

| 面(60s settle,30s 窗 6 采样中位) | 基线 `8e3bd59d` 自建构建 | HEAD `0a79685e` 自建构建 | Δ | 判定 |
|---|---|---|---|---|
| 空载无项目面 | 30.15%(29.9/30.4/30.7/30.6/29.1/27.3) | 31.15%(31.0/31.0/31.3/32.9/30.3/31.7) | **+1.00%** | 带内 |
| 编辑器面(开项目→双击首图载入→60s settle) | 94.50%(94.9/97.5/95.1/93.7/94.1/93.3) | 96.35%(97.6/98.9/94.7/99.7/95.1/94.8) | **+1.85%** | 带内 |

- **判定:PASS(相对门兑现)**——双面差分全带内,四轮零一轮越 1.9%。
- 面形等价性:双臂编辑器面截图逐布局一致(同图载入、同 zoom 100% fit、
  同 overlay handles/面板/6504K,`/tmp/la-acc2-d6/head-edit3-loaded.png`
  vs `base-edit-loaded.png`);双臂空载面同形。
- 栈旁证(sample 3,双臂四面):主导帧族 = SwiftUICore
  `ViewGraphRootValueUpdater.updateGraph/_updateViewGraph`(编辑器臂
  HEAD 1051/1044 vs BASE 950/936;空载臂 104/99 vs 98/92)——与
  AR-01/FIX2/D-AR2-7 的既有 churn 域同族;**零 `params(of:`/JSONDecoder
  业务帧**(stored 化未向 churn 路径引入解码工作,与 N→1 论据一致)。
- parentage:四轮宿主均为自出 PID(launch 时 ppid=验收 shell,采样后
  同 call 内 kill,亲核 process gone)。
- obs 5(绝对值注记):本轮编辑器面绝对值带(94.50/96.35)高于执行批/
  AR-01 带(86.65..90.4)——面态差(本轮 = 载入图 + overlay handles 的
  100% fit 面;执行批面态定义未钉死)+ 机器态漂移;相对门只消费双臂
  同面差分,判定不受扰。后续轮建议把编辑器面定义钉死到截图形。

## 4 偏差①-⑧复核(逐条判等价终形)

| # | 偏差 | 申报处 | 复核判定 |
|---|---|---|---|
| ① | B 探针 ΔN executed +2 越预算带上界 +1 | D-AR2-6 终账修订 | **成立**——plan action 字面「两法(skip 腿=环境门断言即测试法)」与预算表「+0..1(PERF 腿 1)」内在张力,执行按「两法」字面显式申报;全批带 3964..3972 仍闭合(3969≤3972),恒等式与全套轮双证 |
| ② | dropDestination Bool→Void 让渡 | D-AR3-3 | **成立**——源码亲核 guard→no-op、move guard 链逐字保留;MANIFEST 观察行在册(C2-W3) |
| ③ | borderlessButton 3+2 分账 | D-AR3-5 | **成立**——3/5 逐像素亲证在案,2/5(FilterBar/CatalogFilterBar)legacy face 配方让渡 MANIFEST;本轮未重跑该两处截图(配方域非本轮 SC;图标 label+fixedSize 低风险论据在案)→ 残留清单呈报 |
| ④ | 清单外残余 ~40 处冻结 | D-AR3-8 | **成立**——抽查 WorkspaceHostView :497/:685、EditorWorkspaceShellView :62/:82 旧 View 实参形确在;不扩面纪律兑现,现成清单在库 |
| ⑤ | HighpassSoften +1 文件(plan ε) | D-AR2-2 | **成立**——双 helper 式 computed 同病同修,diff 面 = 双 let + 同签名 init + 双 init 解码,与 39 直读同构;40 文件 = 39+ε 闭合 |
| ⑥ | YiyinPanelView 挂账(二选一行使) | D-AR2-3 | **成立**——siblingInstance class 引用论据源码亲读成立(见 C-5);零代码动作 |
| ⑦ | AI 供件缺失炸定向轮 | D-AR2-6 | **成立**——`Resources/AIModels` 194MB 不入 git,worktree 缺失即 fail(.download 缺省 face);拷入后净轮亲证(本轮定向+全套全绿);环境供件面非产线缺陷 |
| ⑧ | coordinateSpace fixup(+1 commit) | D-AR3-2 | **成立**——plan 字面形不编译(missing argument label 'name:'),SDK swiftinterface 对表 `.named(_:)` factory 落地,与同文件 :255/:381 既有 `.named` 用法同形,命名空间字符串 verbatim |

## 5 残留清单(呈报,零阻断)

1. **borderlessButton ④⑤ 实机补判**(FilterBarView filter.add /
   CatalogFilterBarView catalog.filter.add)——legacy Session face
   (`LIGHTAMER_LEGACY_LIBRARY=1`)导航链,MANIFEST 配方在册;本轮时间
   盒内未重跑;观感差超预期 = 该处回退评估(plan 红线既有条款)。
2. **Manual-Only 走查行**(MANIFEST 全部 Manual-Only 行:B1 面板拖动
   60Hz/readout 零漂移、C2 机械等价面抽查、C3 m9 readout 复核)——配方
   域,归实机走查批/用户。
3. **软废弃清单外残余 ~40 处**(D-AR3-8 现成清单)——后续卫生批立项面。
4. **挂账 3**(m10 复数/o4 翻译注释/o6 LutPanelView `.id` → D-6 专项
   卷)——OQ-8/D-6 专项卷裁决面,零代码。
5. **obs 1(D-AR3-9 台账滞留)**:AR-03-DECISIONS.md D-AR3-9 仍写
   「AR-02 +0 = 3967」——与收口对账正本(AR-02-DECISIONS D-AR2-6
   终账修订 + AR-02/AR-03 双 SUMMARY「+2 = 3969/37/0」+ 0a79685e
   commit message)矛盾;0a79685e 修了 SUMMARY 未回写 DECISIONS 该行。
   纯文档面,唯一权威终账 = 3969/37/0(本轮全套独立复现)。建议下批
   顺手勘误。
6. **obs 6(DECISIONS 头注 pre-rebase SHA)**:AR-02/03-DECISIONS 头注
   commit SHA(fbbdef31/71e39a70/7640ed2e/8c0514a9/af4581c7/5d522e88)
   = rebase 前形态,主树链 = 4452e10c/99394fc3/3fa89a40/e22fa21a/
   2ab27a40/896576dd/3bcb5b83(内容逐 commit 面核等价,文件数/主题
   一一对应);任务书即携 rebase 后 SHA,无歧义。

## 6 流程注记(验收过程事故链,orchestrator 已裁)

1. **全套首轮 IOP crash = 环境事故**(21:00,`AgentControlCoordinator`
   environmentObject fatal,verdict=crash 0/0/0)——碰撞窗口与第二路
   20:57-20:59 GUI 臂活动精确吻合(同 bundle-id 双实例干扰);同树
   执行批 IOP 净轮 687/5 在案。orchestrator 裁「环境事故非产线缺陷
   成立采信,不计扣分」。净轮以安静窗口第二轮为准(TOTAL|3969/37/0|,
   2024s)。
2. **双 lane 并行编排**:第二路(重启后 harness 复活)在
   `/tmp/la-ar2-acc2/` 自成体系作业,未取 `/tmp/la-audit-repair-all.lock`;
   其 --all 净轮亦收 `TOTAL|3969/37/0|`(2037s,其产物经 mtime-glob
   实际取到我方容器——容器溯源降级为注记,orchestrator 已裁无需重跑)。
   LESSONS 候选(orchestrator 已记):并行 lane 应各自指定独立
   DerivedData 路径;复活 lane 的进程/文件活动判活优先于产物缺席。
3. **可见窗门控亲证**:D-6 首轮空载面 0.0% 全采样 = M7-1 遮挡态形态
   (frontmost 未设);改 frontmost 先行后读数回 30-31% 带——M7-1 探针
   协议①条在本轮再证,后续 GUI 探针轮 frontmost 步骤不可省。
4. **editor_probe 缝行为注记**:`-la_editor_probe` 六行 probe 后自
   terminate(cmyk 行 rendered=NO 触发 direct-load 重试路径拖长);
   ⌘E 无选图 = no-op(编辑器面须先选行/双击开图)——MANIFEST 配方的
   「⌘E」步隐含「已选中」前提,本轮以双击首图显式化。

## 7 结论

- **PASS / 0 blocking + 0 major + 0 minor + 6 obs**。
- 全套净轮 `TOTAL|3969/37/0|`(2024s,零 fail 零 MEMFAIL,八G 门内)
  独立复现,与申报及第二路轮三值同;ΔN 对账 3963 + A 4 + B 2 + C 0
  = 3969 闭合,skip 37 = 基线 35 + 探针族 2 闭合。
- B codemod 语义等价性全套机检闭环;C 机械批五族清零 + 43 处落位 +
  minor 五件 + 挂账/销账登记全兑现;偏差①-⑧等价终形成立;D-6 相对门
  带内 PASS。
- 工作树还原干净(两验收 worktree + 自建容器已除;第二路 worktree 与
  其 GUI 实例未触碰)、宿主杀净(自出 PID 全清,亲核)、锁已释放。

—— 第一路独立验收(AR-02-03),2026-10-18。
