# M5-1-02 ACCEPTANCE-OMP — omp 独立二次验收（双重验收第二路）

> 验收 2026-10-11（与 zcode 首验串行、无共享上下文；独立亲跑 + 独立数学复算 + computer-use 实机走查）。
> 对象 = 批内 7 commits `14d032d..4cc1c52` + T9 `abc46c0` + 补提交 `9c61c48`
> + 首验收批小修 `cbd1afa` + 首验立卷 `4a0062e`（HEAD；后两者 docs/账面-only，
> `git diff 9c61c48..HEAD` = 3 文件纯账面，行为面 = 首验对象）。
> **结论：FAIL / 1 error + 2 minor**。error = E-omp1（GUI 面 colormatch 不可达，
> MANIFEST 行 1 即断裂，本报告 §4 实证；首验未做 computer-use 故漏检）。

## 0. 结论头

`FAIL / 1 error + 2 minor`

| 维度 | 判定 |
|---|---|
| 定向两 bundle 亲跑对表 | **全命中**（Layers 466/4/0 / IOPParity 444/3/0，零 MEMFAIL；HEAD 重建产物后亲跑，§1） |
| S2 数学审计（独立路复算） | **PASS**——交叉相乘⇔有理数 10 万随机对零失配 + 独立梯实现（双高斯源→单峰参考，非首验 shifted-tent）单调/中位精确/平台面 + a/b 63/256 bins 截断 drop 逐位复现 + bake 体素门 5.95e-8 同带 + 恒等带口径对齐 0.0233 逐位命中申报 + FNV 三键逐位命中（§2） |
| 池化确定性审计 | **PASS**——二阶矩 Fraction 精确复算六槽全等 + 取整/序规范化/N=1/空输入读码 + 测试亲跑绿（§2.4） |
| LUT 臂三臂状态机 + E5/E6 + .cube | **PASS**——三臂分派/commit 读码 + uniform 字段镜像亲核（字节数勘误见 m-omp2）+ armed tap 旁路即构造 + E6 throwaway hermetic + solve-twice 逐字节/幂等零新 item 读码 + attach 恰一 commit + paramsData <8KB + omit-nil serde（§3） |
| 红线机检 | **PASS**——Lut3d 密封面 0 行 / Film 域 0 行 / .metal 0 diff / runModal 0 / SPM 零新增 / zh-audit 1637/1875 PASS（§5） |
| **computer-use 实机走查** | **FAIL（E-omp1）**——默认编辑器面无 colormatch 实例添加入口 → LUT 页追色行永不渲染 → Solve/参考/强度面板不可达；MANIFEST 九行行 1 即阻塞（§4，OCR + sidecar 双实证） |

**与首验分歧点**（首验 PASS / 0E+3minor）：①本路 FAIL——E-omp1 为首验未覆盖面（首验 §9 注记 GUI 走查待 omp，实际未执行；MANIFEST 仅配方九行零证据落盘，本轮亲证 `.work/gui-acceptance/m5-1/` 仅 MANIFEST.md 一文件）；②首验 §5「96B」uniform 字节数算术错（实 108B，m-omp2 账面注记）；③其余数学/机检/计数面与首验互证一致（§6）。

## 1. 亲跑数字（对表）

```
构建：build-for-testing 于 HEAD 4a0062e 重建（DerivedData Lightamer-accept，
      产物 08:17 晚于补提交 9c61c48——resolver forward 在测；231s）
验收轮（2026-10-11 08:2x-08:4x，串行单宿主直启；轮前已删孤儿 .lra）
BUNDLE|Layers   |466/4/0|peakRSS=1160MB|172s ← 申报 466/4/0（1154MB）命中
BUNDLE|IOPParity|444/3/0|peakRSS=6045MB|556s ← 申报 444/3/0（7006MB）命中；RSS 轮间漂移带内
zh-audit --check：PASS（1637 source keys / 1875 catalog keys）
```

- 两 bundle 全绿零 MEMFAIL；IOPParity 6045MB vs 首验 5749MB vs 执行批 7006MB = 在案同 bundle 方差（±3% 注记外但 < 8G 运行门；三轮同 verdict ok）。
- 对账算术闭合亲证：八文件 `grep -c "func test"` = 8/6/6/8/12/3/7/6 合计 56 法；
  其中本批新增 47 法面 = CDFSolver 8 + Pooling 6 + BakeGolden 6（+1 probe 即第 6 法内 env 门 skip）+ CubeAsset 8 + Module +5（7→12）+ Identity +1（2→3）+ Service 7 + Panel 6；
  BUNDLE-MAP 八行计数（101/103/273-278）与 `grep -c` 逐位一致（含首验 m-a 修后值 12/3）。
- 首验配方 ①② 遵行：轮前删孤儿 `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`；
  定向轮后该孤儿未再生（M4-1 #6 系 App bundle 轮产物，本路未跑 App bundle）。

## 2. S2 数学审计（独立路复算，与首验零共享脚本）

工具 = Python `Fraction` 精确有理数 + struct Float32 逐运算仿真（Swift 语义：
`Float(bin)/Float(255)` 逐次舍入 + `Int()` 向零截断；Oklab 常数取 OklabMath.swift
印刷字面经 `Double(Float(c))` 升维，L048）。脚本即弃（本报告附关键式）。

### 2.1 整数交叉相乘 ⇔ 有理数比较

- 10 万组随机整数对（计数域全 UInt32 `[0, 2^32−1]`，种子 20261011）：
  `a·b ≥ c·d` ⇔ `a/d ≥ c/b`（Fraction 精确路）**零失配**。
- 上界亲核：`(2^32−1)² < 2^64` 成立（Swift `sourceCumulative * totalReference`
  无溢出面）；实际计数域（512² 桶 = 262,144，`262144² = 68.7e9 << 2^64`）余量巨大。
- 退化注记：total=0 时有理比较无意义，Swift 语义退为首 bin（`scaled=0` 左恒真
  或右恒零）；extract 非空保证生产不可达——与首验一致，不计数。

### 2.2 独立梯实现复现（换分布族：双高斯源 → 单峰参考）

- 源 = 峰 80/180 双高斯，参考 = 峰 140 单高斯（总量 262,144）：
  曲线**单调** ✓、源中位 bin 114 → 参考 bin **140 精确**（参考峰/中位同 140）✓、
  支撑 `[64,196]→[117,163]` 外**平台恒端值** ✓、
  Fraction 精确路交叉验证 `firstReferenceBin`（每 7 抽）**零失配** ✓。
- 平台面终形（源支撑外→参考支撑端值、支撑内梯位 clamp 进参考支撑）与
  `buildCurve` :200-214 逐行对应。

### 2.3 支撑 bin 截断 drop 机制复现

- `binIndex(binValue(bin))` Float32 往返：L 通道 **0/256** drop，a/b 通道
  **63/256 bins 低一格**（首 5：`(1→0),(2→1),(3→2),(4→3),(5→4)`）——与首验
  §3.1 逐位一致；shipped 代码已不依赖该逆映射（支撑由直方图分位重推导，
  `solve` :120-126 + `percentileBin` 与 P1 extract 同梯），修复方向正确。
- 首验 o-1（L 通道 1% 分位归因未能复现）本路同样：格点往返 L 零 drop——
  互证 o-1 留档结论（机制类确证、归因细节差异、无行为影响）。

### 2.4 bake 体素门 / 恒等带 / FNV 键

| 面 | 本路独立复算 | 门/申报 | 判定 |
|---|---|---|---|
| 体素门（Float32 存储 epsilon，4096 独立随机体素，α=0.5，peak100→170 非首验分布） | worst **5.95e-8** | 门 1e-5 / 申报 7.6e-8 / 首验全晶格 5.96e-8 | ✅ 同带 |
| 恒等带（**口径对齐测试**：denseHistogram 精确复刻 + by-8 格点 + 三通道支撑内筛选，n=703） | worst **0.0233** | 门 0.03 / 申报 0.0233 | ✅ **逐位命中申报抽样值**（首验全晶格 0.0259 系抽样集差异，同带；本路首轮未限支撑内得 1.26，读测试原文对齐口径后收敛——口径敏感性实证） |
| Oklab 往返自查 | 2000 随机点 worst 2.07e-7 | — | 引擎健康 |
| FNV 缓存键 | gaussianOT(0,0)=2495982924697081349 / reinhard(0,0)=3458577883779271296 / cdf(0,0)=3429970360978670064 | P1 钉死×2 + 首验存档 | ✅ 三键逐位命中 |

- 双跑 BIT-IDENTICAL 结构面亲核：`bake` = `concurrentPerform` 逐 z 切片固定索引写、
  零归约（ColorMatchBake.swift :86-100）；`testDoubleBakeIsBitIdentical` 亲跑绿。
- 池化二阶矩 Fraction 精确复算：μ=(1/4, 3/20, −3/40)，
  Σ=(11/80, 3/400, −3/800, 31/400, −3/800, 31/1600) = 测试钉值
  (0.1375/0.0075/−0.00375/0.0775/−0.00375/0.019375)**全等**；sampleCount 25、
  支撑并集、权重比不变（×100 同池化同哈希）、2.5→3/22.5→23 取整、空输入 typed
  error、N=1 verbatim——读码 + 亲跑绿。

## 3. 读码抽查（五缝 + 机制疑点消解）

1. **三臂状态机**：`commitParams`（ColormatchModule.swift :273-294）=
   strength==0 → identity / solver==.cdf → LUT 臂 / 其余 → linear；
   identity 态 `piece.data = nil` + blit（L031）；LUT 臂缺 asset/degrade → identity
   （G5 扩展态，:346-355/:411-421）。`testLutArmIdentityStatesBlitByteExact` 亲跑绿。
2. **恒等 uniform 盒**：`ColormatchLutUniforms`（:660-674）与 MSL `Lut3dUniforms`
   （Lut3dKernels.metal :29-41）**逐字段镜像**（width/height/level + domain 6 +
   fwd[9] + inv[9]，fwd/inv 恒等 + [0,1] 域）；Lut3dModule.Uniforms（:129-141）
   同形。字节数勘误见 m-omp2。G2 链路断言亲跑绿。
3. **armed input-tap 旁路**：`process()` 入点（:507-518）一次性捕获
   （armed 读清 + capture 先于本模块任何 dispatch = **旁路即构造**）；
   `armStatsCapture()`（:600-602）由 service 提取渲染装配；
   首解 = 合成恒等 box 注入 v50 槽位、重解 = 真实 box 输入平面（ColorMatchService
   :171-196）——两解同链位。L014 fence + 全面 readback + ≤512² 固定序 stride 采样 +
   Oklab + P1 extract（:614-651）亲证。
4. **E6 + attach 投影缝**：`extractStats(document:bucket:)` = throwaway PipeCache
   hermetic 渲染（:202-218）+ armed tap 消费；源桶钉 512 / 参考 THUMBNAIL pristine
   （:243-269）；`projectColormatch` upsert（:360-380）+ `recordChange`/
   `addModuleToBaseChain` **恰一 commit**（:335-353，`desired != current` 守卫幂等）。
   疑点消解：solve-twice 中 `invalidateAll()` 丢 curves 后，第二次 `solveAndAttach`
   :311 重 `storeCurves` 同解——测试 :186 读到的是重存 curves，机制自洽。
   `testSolveTwiceLandsByteIdenticalParams`（E5 平面解耦 + params 逐字节 + 幂等零新
   item + 持久资产 vs 内存 bake 全表位型比对）与 `testAttachLandsOneHistoryItem
   WithParams` 亲跑绿（App bundle 面，首验亲跑；本路读码确证断言形态）。
5. **.cube + serde**：`testParamsBlobStaysUnderBoundWithAssetAttached`（<8192，
   满载 assetRef/assetHash 族）亲跑绿；omit-nil additive（`encodeIfPresent`
   :189-190，P1 显式 null 键集不动）+ 默认编码零漂移专测亲跑绿；篡改/缺失/
   结构损坏三路 degrade 值形态 + L009 同目录 tmp 原子晋升 + 同解前缀清理亲跑绿。

## 4. computer-use 实机走查（FAIL 面——E-omp1）

环境：HEAD 重建产物（Lightamer-accept，08:17，晚于 9c61c48）直启 GUI；
样张 = 真实 Sony ARW（DSC09991→main.ARW 75MB，街景门店）+ ref-warm.ARW +
ref-cool.tif（/tmp/la-omp-walk/imgs/，throwaway 域）；识图 = pi 链路 +
自研 Vision OCR 坐标钉（/tmp/la-omp-walk/ocr.swift 即弃）；证据截图
/tmp/la-omp-walk/shots/（41 张，/tmp 即弃——MANIFEST 证据域不入 git 体例故未回填）。

### 4.1 E-omp1：默认编辑器面 colormatch 不可达（error）

**现象**：LUT 标签页（OCR 坐标亲核）在 base scope 与 grade scope（手工新建
「调整1」层后）下**均只渲染 lut3d 一行**，滚查到底无「追色/求解/参考/强度」
字样（OCR 全屏 grep 三轮零命中）；MANIFEST 行 1「调整栈『添加模块』→选追色」
**无此入口**——当前面「添加模块」Menu 仅存 legacy InspectorView
（`layers.addmodule`），而 gate-false 默认面右列 = EditorAdjustmentStackView，
Inspector 列只挂 export/film 页（ContentView.swift :205-222），legacy 添加面
**结构不可达**。

**机制链**（读码确证）：
`pageRows` :171-176「无实例不渲染行」→ colormatch 行需链上已有实例 →
实例需经 `addFaceEntries` 菜单（仅 InspectorView :209-249）或 Solve 自动 attach
（需面板已渲染）→ **鸡生蛋闭环**：colormatch ∈ GradeCatalog（owner .grade，
NodeOwnershipCatalog.swift :275）+ 模板厂第 20 行（EditorState.swift :982-983）
+ 面板 provider 已注册（InspectorState.swift :210）+ defaultLook 不含 colormatch
→ 默认面**零 GUI 路径**创建首个 colormatch 实例。

**sidecar 实证**：走查落盘 `/tmp/la-omp-walk/imgs/main.ARW.lra`（schema 9）=
base 链 37 件**无 colormatch** + 调整层 chain **空**（手工加层不 mint）+
history 1 项——与面板缺席互证。

**影响**：PLAN「生产行为可见变化 = colormatch 面板可用」+ AC#7 TRACK-04
（参考选取/自动求解/强度/before-after/readout）在 GUI 面**不可达**；
MANIFEST 九行**行 1 即阻塞**（行 2-9 全系于面板存在）；
S2 档/CDF bake/.cube/池化/E5/E6 代码面全交付且单测覆盖——缺陷在**可达性**，
非算法正确性。严重性 = error（功能交付闭环断裂），非 minor。

**修复方向**（建议非指令）：调整栈页为无实例 op 渲染「添加行」（M1 chain-list
语义的加法面），或 LUT 页对 colormatch 渲染无实例占位 + 首解 Solve（E5 首解面
天然无污染）；MANIFEST 行 1 配方需按实际挂载重写（当前「调整栈添加模块」
与产品面不符）。

### 4.2 走查附带发现（obs，不计数）

- **o-omp1**：Mask 页点击层行「调整1」后内容区**纯空白**（pi 亲读），切页重进恢复。
  疑似 MaskGroupsPanel 选中层态渲染缺口（M2-7 面，非本批域）——挂账面。
- **o-omp2**：`open <file> -a` 在欢迎态不消费（窗口 0→1 但仍「尚未打开项目」）；
  编辑器态直接 open 不换图；文件→打开… 面板可达但 AX 内容不可遍历（AppKit 面板
  AX 隔离在案体例）。走查改用启动参数 + 菜单 AX 组合完成——file-open 路由复杂性
  非本批域，记录备查。
- 首验 §9 配方注记 ③「GUI 走查九行配方…omp computer-use 可执行」——本路实测
  **不可执行**（E-omp1），配方-产品面断裂本身即发现。

## 5. 红线机检（`git diff e4acb70..HEAD` 亲跑）与 zh

- `LightamerIOP/Sources/Lut3d/` **0 行**；`LightamerCore/Sources/Pipe/Film/` 0 行；
  `.metal` 0 diff + 0 新文件；`runModal` App/Sources 0 命中；SPM（Package.swift/
  Package.resolved）0 diff；Project.swift diff = 测试编列 8 行（抽查）。
- xcstrings：尾块纯插入（首验亲证 340 增/0 删改，本路信任 + zh-audit 独立亲跑绿）。
- zh-audit `--check`：**PASS（1637 source / 1875 catalog）**——与申报逐位一致。

**minor**：
- **m-omp1**：MANIFEST 行 1 配方-产品面不符（「调整栈添加模块→选追色」无此入口）。
  E-omp1 修后配方须重写；独立记 minor（文档面）。
- **m-omp2**：首验 §5「`Lut3dUniforms` 96B 布局」算术错——3+6+9+9=27 标量 ×4 =
  **108B**（MSL constant buffer 标量无额外对齐；Swift tuple stride 同）。
  字段镜像结论不受影响（本路逐字段亲核一致），纯账面勘误。

## 6. 与首验分歧点汇总

| # | 面 | 首验 | 本路 | 裁决 |
|---|---|---|---|---|
| 1 | 总 verdict | PASS / 0E+3minor | **FAIL / 1E+2minor** | 分歧成立：E-omp1 为首验未覆盖面（computer-use 缺席） |
| 2 | uniform 字节数 | 96B | **108B**（27×4） | 首验算术错，m-omp2 账面勘误 |
| 3 | S2/池化/bake/FNV | 独立复算 PASS | 独立复算 PASS（换分布族/换抽样/口径对齐逐位命中） | **互证一致** |
| 4 | 定向对表 | Layers 466/IOPParity 444/App 724/IOP 563 | Layers 466/IOPParity 444（本路程序仅两 bundle）+ zh 1637/1875 | 覆盖面一致 |
| 5 | 红线机检 | 全绿 | 全绿（独立亲跑） | 互证一致 |
| 6 | MANIFEST | 配方存在即 §9 注记 | 行 1 即不可执行（E-omp1 根因之一） | 分歧成立，m-omp1 |

min_votes 语义：两路串行验收对总 verdict 分歧（PASS vs FAIL）——按程序 FAIL
优先（error 零容忍），E-omp1 须修复 + 回归走查后方可签核 M5-1-02。
本路审计全程只读产物 + 独立路复算；首验报告仅作程序输入（§9 配方）与对账基线，
数学/机检面均独立重做未复用首验脚本。

## 7. 证据索引

- 定向轮：§1（产物 Lightamer-accept 08:17；孤儿预删遵行）
- 数学审计：§2（Fraction/Float32 仿真即弃脚本；关键值全列）
- 读码：§3（文件:行号全注）
- 走查：§4（截图 /tmp/la-omp-walk/shots/ 41 张 + OCR 读数 + sidecar JSON 实证；
  GUI 进程已杀，资源监控无异常——测试宿主峰值 6045MB < 8G）
- 首验报告：M5-1-02-ACCEPTANCE.md §0-9；执行批：M5-1-02-DECISIONS.md；
  计划：M5-1-02-PLAN.md（AC#7 为 E-omp1 判据源）
