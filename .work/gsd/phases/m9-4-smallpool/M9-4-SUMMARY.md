# M9-4 SUMMARY — 小件池执行摘要(2026-10-29,T1..T5)

> 执行正本 = `M9-4-PLAN.md`(v2,checker 放行)+ `CONTEXT.md`;裁定记录 =
> `M9-4-DECISIONS.md`(§1 穿线终态 / §2 thumbnail guard 修订 / §3 封存面
> 例外终态 / §4 v3 kernel 标量分支形 / §5 拟合残差实测 / §6 T1 落域偏差 /
> §7 marker 定形 / §8 菜单定位 / §9 XPan 值 / §10 bump 连带测试对齐 /
> §11 偏差挂账 / §12 lessons 候选)。HEAD 起点 = `7f089c9d`(M9-3 收口)。

## Phase Goal 达成

ColorWheels v1 公式 → **v2 LGG+Offset 影调域语义**(真 parity gap 修复)
+ process **v3 bump 五件套** + **PipeCache 折键**(H-SP1 消解,负测三件
硬门)+ 迁移 UX 泛化(gate 二源/marker 二形/copy 中性化/双面板挂点)+
尾件四件(LUT 10 行 + 7 曲线 + 6 gamut / Filmstrip stars / Show in
Finder 三门 / XPan 三行)。零新 SPM、零新 iop(V50Order 零新增)、零
sidecar schema bump(v11 保持)、UserDefaults 零新键。

## 逐任务记账

| 任务 | 战果 | commit |
|---|---|---|
| **T1** v3 数学面 | ColorWheelsLegacyConvert 新建(lift→offset 精确 + Gauss-Newton 拟合,GPL 头)+ Params.offset additive optional(encodeIfPresent 字节零漂,hash 11640277816793824460 钉死)+ 14-float 预解 + referenceV3 Float64 镜 + params 镜像(NSLock)+ grade_color_wheels_v3 kernel(申报面唯一;冻结体 md5 同值 8943b9a4)+ golden 三面(kernel-vs-ref 参数点族含超域 / 上游解析锚全套移植 / 转换锚双带)+ NOTICE T 条目 | `feat(m94): ColorWheels v3 tone-wheel math face…` |
| **T2** bump+fork+折键+迁移+面板 | 五件套(current 2→3 + 账本行)+ process fork(exhaustive switch,.v1/.v2 逐字节)+ ModuleBoxing.processForkHash(default nil)+ prepareChain 折一处(resolved-arm discriminator)+ 负测三件(fork tag hash 905990834909371860 钉死)+ 穿线 9 点全穿 + thumbnail guard 修订(M-1①)+ 豁免面未穿(m-3)+ 迁移泛化(gate 二源/marker 二形/copy 中性 5 键/双面板挂点)+ 面板双形 fork(v3 四轮 stops + effective 投影首编辑物化)+ bump 连带既有测试对齐(target 3)| `feat(m94): process v3 bump + ColorWheels fork + cache fold…` |
| **T3** LUT 表扩 | 10 行(id 拼写照上游 c740f7b)+ 7 曲线(OCIO 2.5.1 LogCamera 参 verbatim + clog2 CSC 形 + gamma26)+ 6 gamut(primaries/white 逐值照上游,矩阵仍计算式)+ add-only 钉死(旧 17 行 + 9 gamut 前缀恒等)+ peakNits 逐行照上游(P3 行 48,勘误④)+ NOTICE U 条目(OCIO BSD) | `feat(m94): LUT encoding catalog expansion…` |
| **T4** 尾件三件 | Filmstrip stars 行(rating 直读勘误①,ratingStars model 缝)+ 双态轻臂保留 + Show in Finder 三门(grid/filmstrip contextMenu + Image 菜单,reveal 先例形 + 存在性前置)+ XPan 三行(65:24 / 2.75:1 / 6:17,dn + bits 双向,零 schema)+ xcstrings 5 键 | `feat(m94): tail items…` |
| **T5** 收口 | zh-audit 双 PASS(film_migrate 留册 5 键入 allowlist——D-M9SP-7③ 留册停引用的 audit 对齐)+ BUNDLE-MAP 六行 + 全套 --all 带式对账(下行)+ SUMMARY/DECISIONS/MANIFEST(走查配方 m9-4) + AGENTS 键族/约定节回写 | 本 commit |

## ΔN 终账(对账锚亲核)

- 基线链亲核:M9-1 = **4328/33/0**(M9-1-SUMMARY 夜间授权轮)→ M9-2 =
  **4363/34/0**(+35 越带,M9-2-SUMMARY:135)→ M9-3 修复轮 =
  **4391/34/0**(M9-3-SUMMARY +5 App)——任务书基线 4391/34/0 ✓。
- 本批新测试文件六件 +35 法:IOPParity 11(T1 golden)+ 4(T2 折键)、
  IOP 6(T1 转换)+ 6(T3 LUT)、App 4(T2 gate)+ 4(T4 尾件)= 35;
  既有测试零删并(bump/扩表对齐 4 文件改断言值不增减法数)。
- **全套终值 = 4426/34/0**——executed 4426 = 4391 ⊕ +35 **精确落点**
  (ΔN 终账闭合;plan 带 4402..4406 是「ΔN +11..15」的估带,实际 ΔN
  +35 越带,下条申报);skip 34 持平(逐族零新增);fail 0(修复笔
  1..4 全闭环)。
- **ΔN = +35,越 plan 带 +11..15 上沿 +20**——越带申报:H-SP1/H-SP2/
  H-SP3 三主风险的 golden/负测组完整清单一一对应验收形态(转换锚双带
  双断言 / 解析锚 9 法 / 折键三件 + 账本表 / gate 五态 + marker 双形 +
  fork 投影 / stars 全表 / XPan 全臂),M9-2 越带同款「一法多断言未压
  缩」形态;DECISIONS 留晨审。

## 全套终值(七 bundle,--all 带式对账)

<!-- ALL-RESULTS 占位:T5 全套轮完成后回填 -->

### 全套轮跑史(bump 字面钉的暴露序列,修复笔随轮 commit)

- **第一轮**(11:46):IOP 813/1/0 绿 → IOPParity 3 红(Lut3dEncodingTests
  钉 17/9/100-1000 未对齐 + LutEncodingExpansion gamma26 自逆断言笔
  误)→ verdict fail 停。修复笔 1 = `fix(m94): align the LUT catalog
  count pins…`(两文件)。
- **第二轮**(12:36):IOP 绿 + IOPParity **565/10/0 绿** → Layers 3 红
  (RenderProcessLedgerTests 账本表/clamp/mint 钉)。修复笔 2 =
  `fix(m94): retarget the Core ledger tests…`。
- **第三轮**(13:40):IOP/IOPParity/Layers 全绿 → Library 2 红
  (SidecarV10Tests 钉)。修复笔 3 = `fix(m94): retarget the
  Library-domain sidecar ledger pins…`(其余 process 断言已动态
  current,扫尾确认)。
- **第四轮**(14:43)= **终值轮**:七 bundle 全跑,
  **TOTAL 4426/34/1**——App 1 红 = LutEncodingPanelTests 钉 17/11/6
  (最后一个字面钉,修复笔 4 = `fix(m94): retarget the App-domain LUT
  panel count pins…`,定向绿)。**终值 = 4426/34/0**(executed Δ =
  +35 精确 = 4391 + 35;skip 34 持平)。
- 教训(L0xx-k 第三笔呼应):bump 的字面钉面 grep 不可穷尽——「钉死
  current 值」的测试散在七 bundle,应随 bump 任务清单跑
  `grep -rn "current.rawValue, 2\|all, \[.v1, .v2\]"`。
- 修复轮 discipline:每笔修复 = 修复类定向绿 + 随轮 commit(refs #14)。

### 七 bundle 分值(第四轮终值轮;App 修复类定向绿并入)

| bundle | executed/skip/fail | peakRSS | 时长 |
|---|---|---|---|
| IOP | 813/1/0 | 6777MB | 935s |
| IOPParity | 565/10/0 | 6364MB | 1581s |
| Layers | 528/5/0 | 1182MB | 448s |
| Library | 785/4/0 | 744MB | 168s |
| Sessions | 285/4/0 | 1221MB | 61s |
| Export | 385/4/0 | 5003MB | 198s |
| App | 1065/6/0 | 2832MB | 625s |
| **TOTAL** | **4426/34/0** | — | 4016s |
- 教训(L0xx-k 第三笔呼应):bump 的字面钉面 grep 不可穷尽——「钉死
  current 值」的测试散在七 bundle,应随 bump 任务清单跑
  `grep -rn "current.rawValue, 2\|all, \[.v1, .v2\]"`。
- 修复轮 discipline:每笔修复 = 修复类定向绿 + 随轮 commit(refs #14)。

## 验收机检终态

- T1:kernel v3 在册 ≥1 + 冻结体 md5 同值 + 新两文件全绿 ✓;NOTICE
  Alcedo 条目在册 ✓;runModal grep 零命中 ✓。
- T2:all == [.v1,.v2,.v3] + current == 3 单测 ✓;PixelPipe 2 hunks
  逐 hunk 申报(§3);负测三件全绿 + fork tag 钉死 ✓;面板 fork 读面
  grep 在册 ✓;panel_film_migrate 引用归零(注释键史提及除外)✓;
  GradeCatalog/HistoryStack/LightamerSidecar/NodeOwnershipCatalog 零
  diff ✓;定向 IOP+App 全绿 ✓。
- T3:all.count == 27 + gamuts.count == 15 单测 ✓;Lut3d 件纯 append
  ✓;曲线 golden/对拍在册 ✓;IOP 全量 813/1/0 ✓。
- T4:crop 三键 case+dn 在册 ✓;旧 7 档 dn 回归 ✓;AX 三 id 注册断言
  ✓(AX 树走查归 MANIFEST);SmallPoolUITests 4/0/0 ✓。
- T5:zh-audit --check PASS + --self-test PASS ✓;BUNDLE-MAP 六行与
  Project.swift 数组一致 ✓;tuist generate 末位纪律 ✓(L041);G4 贴线
  透明越门(M9-3 §9 先例形,free 77% 无 swap 压力,monitor 伴跑)。

## 偏差申报(汇总,细节见 DECISIONS)

1. 越带 +35(上行;验收形态一一对应,无凑数法)。
2. PixelPipe 2 hunks(prepareChain 例外 + film-leg switch 编译器补腿)。
3. ColorWheelsToneWheelGoldenTests 落 IOPParity(BUNDLE-MAP 域模式优先,
   plan「IOP」家族口径)。
4. thumbnail guard 修订(M8-3 设计决定修订,M-1①;豁免面两件未穿)。
5. v3 kernel 标量分支形(vector select 实机不可靠,五探针轮,DECISIONS §4)。
6. 拟合残差断言带:常见 0.035(实测 0.0308)/ 极端 0.145(实测 0.143)。
7. zh-audit allowlist +5(film_migrate 留册键——D-M9SP-7③ 的 audit 面)。
8. G4 贴线越门(M9-3 §9 先例,清缓存后仍差 92MB,free 77%)。

## 封存面声明

17 件零 diff 亲证(git diff 空输出);例外申报恰形:**PixelPipe
prepareChain 一 hunk(计划内豁免)+ film-leg/policyTag exhaustive
switch 编译器补腿两处(bump 连带,M8-2 同族)+ ColorWheels.metal
append(纪律面登记)**——plan「恰两处」字面外的两处 switch 补腿属
红线 1「case 追加编译器逐点指向」的本体义务,非扩面;详见 DECISIONS §3。

## C 档停

T5 闭环 = M9-4 全批闭环(M9 末站);phase VALIDATION 与 M9 站收口另批。

## 修复轮(2026-10-29,验收第二路 B-1 blocking + M-1 + m-1 回注)

> 输入正本 = `M9-4-ACCEPTANCE-2ND.md`;裁定与对照表 = DECISIONS §13
> (B-1 机制/两案裁决/重钉对照表/负向探针)+ §5 修订注记(m-1)+
> §11 补申报(M-1)。HEAD 起点 = `b6ba12fc`(第二路验收)。

- **B-1(gamma 倒数语义错配,blocking)**:拟合 target 换 `1/legacy
Gamma`(对齐我方冻结 v1 渲染语义——采验收案 (a),保「迁移 ≈ 保观
  感」;案 (b) 接受翻转否决,理由 §13);转换锚 goldens 重钉(带数值
  经产线路径重测维持:common 0.0313 ≤ 0.035 / extreme 0.1317 ≤
  0.145);语义判别回归新法(γ_s=1.2/0.9/1.1+0.95 三场景方向保持 +
  幅值带,负向探针 15 failures 真红证实设防);迁移文案 en/zh 如实
  改写。commit `861af688`。
- **M-1(Finder 两法断言力虚置)**:`FinderReveal` 产线缝(三 AX id
  常量单源 + 存在性 guard/reveal 决策路径注入 seam)+ 三挂点消费 +
  两测试改真耦合;「三门 AX 可达」归走查配方(§11 合并申报)。方法
  数不变。commit `b649de7f`。
- **m-1(残差带域限定)**:随 B-1 重测消解——新 target 下 γ_s 偏离
  1 达 0.2 实测 0.0253(原 0.081 测于旧 target 上游自洽域),0.035 带
  在语义域成立;§5 修订注记接管叙事。
- **封存面**:17 件零 diff 维持(修复轮触碰面 = ColorWheelsLegacy
Convert/ConvertTests/FilmPanelView/xcstrings/FinderReveal(新)/三挂
  点视图/SmallPoolUITests——无一在封存清单);v3 kernel/折键负测面
  零回归(定向轮亲证)。
- **全套终值 = 4427/34/0**(4426 ⊕ +1 语义回归法,预批精确闭合;skip
  34 持平、fail 0)。对账轮:第一遍全套(20:29)六 bundle 逐绿后在
  App 起跑点被**外部 SIGKILL**(exit 137,monitor 零 kill 非 guard、
  非执行者——事件注记待晨审);六 bundle 值取该轮,App 取补跑轮
  (23:1x,1065/6/0 与定向轮逐位同)。

### 七 bundle 分值(修复轮终值;六 bundle = 22:16 轮,App = 补跑轮)

| bundle | executed/skip/fail | peakRSS | 时长 |
|---|---|---|---|
| IOP | 814/1/0 | 5781MB | 945s |
| IOPParity | 565/10/0 | 5126MB | 1569s |
| Layers | 528/5/0 | 914MB | 437s |
| Library | 785/4/0 | 664MB | 174s |
| Sessions | 285/4/0 | 1090MB | 70s |
| Export | 385/4/0 | 4085MB | 203s |
| App | 1065/6/0 | 2832MB | 627s |
| **TOTAL** | **4427/34/0** | — | — |
- executed Δ = +1(语义回归法,ColorWheelsLegacyConvertTests 7 法 =
  6 ⊕ 1);skip 34 持平零新增族;IOP 814 = 813 ⊕ 1 精确。
- 修复轮三 commits:`861af688`(B-1)+ `b649de7f`(M-1)+
  `ac7b633a`(Export 环境型脆断言区域化,范围外收口最小修复——取证
  链见 DECISIONS §13 Export 段)。
- monitor 伴跑(21600s × 2 窗)零 RSS-KILL;G4 透明越门(Data 卷
  23114MB<25GB,§9 先例,追记如仪)。

## M-1′ 修复轮(2026-10-30,omp 终审 major 回注)

> 输入正本 = `M9-4-ACCEPTANCE-OMP.md` §四;裁定与教训 = DECISIONS §14。
> HEAD 起点 = `46a01e07`(修复轮收口)。

- **M-1′(Show in Finder 三门相对路径静默失效)**:三门消费
  `images.image_path` 原始列未过 resolve——kind2 真定位、kind0/1
  按 CWD 解析静默 no-op(omp 实机三档矩阵亲证)。修法 = `FinderReveal`
  增 URL 门 + row 门(组合单源,resolve 失败 = 静默 no-op 维持)+
  `LibraryThumbnailBridge.sourceURLResolver(projectDirectory:)`
  factory(host 内联闭包逐句上提,行为同构)+ 三挂点改走 resolve
  (grid/filmstrip 走 `bridge?.sourceResolver`,menu 走既有
  `workspace.editorURLResolver`)。AX id/文案/UserDefaults/xcstrings
  零新增,存在性 guard 语义不变。
- **回归**:新法三 kind 直测(真 fixture + 真产线组合 + 注入缝断言
  resolve 后 URL 恰达 Finder)+ stale 零 reveal;SmallPoolUITests
  **5/0/0**,全 App bundle **1066/6/0**(= 1065 ⊕ 1,全套对账态
  4428/34/0,六 bundle 未跑——触面全在 App target;LIB 顺跑
  **785/4/0** = 修复轮基线逐位同,bridge additive 零扰实证)。
  教训:record probe 须按 URL 区分(同串 = 判同卷,首跑 3 fail);
  第二遍全量遇 AIWorkerClientTests timeout-kill 测试一次性挂起
  (与本批零关联,单类复测 9/0/0 后第三遍干净终值)——事故注记
  DECISIONS §14。
- **封存面**:17 件零 diff 维持;guard G4 贴线透明越门(23775MB,
  §9 先例,monitor 零 kill);无 GUI 走查(omp 已终审 UI/AX 面)。
- commit:`fix(m94): resolve image paths before revealing in Finder
  (refs #14)`。
