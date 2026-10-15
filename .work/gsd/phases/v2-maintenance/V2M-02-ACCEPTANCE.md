# V2M-02 ACCEPTANCE(波 2 清算批——第一路独立验收,2026-10-16)

> 验收方:第一路独立验收 subagent(不轻信执行方报告,逐条实测;夜间全自动授权链)。
> 对象:执行链 `2ba1d1fe..08f9ebc4`(5 commits),基线 = 波 1 终值(HEAD `bb16f8c4`,
> 3851/35/0 两路亲跑同值),HEAD = `08f9ebc4`。
> **结论:PASS / 0 error + 0 minor(+1 条件性全套轮注记 + 4 条验收注记,均非缺陷)**。
> T1/T3/T5 深审逐项成立、T4 亲证成立、T2 通道受阻登记质量合格、对账 3857/35/0
> 合并亲证闭合、红线族两波合并全零;D-6 error 级候选定级**表态成立**;D-4「返工
> 不触发」裁决**追认成立**。波 1 屏面证据四项义务**延续**(本批通道受阻未清偿,
> 转 D-6 修复后走查批硬义务)。

## 一、全套独立复跑(本路亲跑,非转抄)

`caffeinate -dis xcodebuild build-for-testing`(exit 0,新鲜构建)→
`caffeinate -dis Scripts/test-direct.sh --all` →

```
BUNDLE|IOP|687/5/0|peakRSS=7881MB|433s|sampling=time
BUNDLE|IOPParity|460/3/0|peakRSS=7728MB|757s|sampling=time
BUNDLE|Layers|494/5/0|peakRSS=808MB|165s|sampling=time
BUNDLE|Library|729/4/0|peakRSS=625MB|78s|sampling=time
BUNDLE|Sessions|284/9/0|peakRSS=1628MB|61s|sampling=time
BUNDLE|Export|379/5/0|peakRSS=6459MB|203s|sampling=time
BUNDLE|App|0/0/0|peakRSS=2832MB|336s|sampling=time      ← L055 crash 签名,计数置零
TOTAL|3033/31/0|2033s(App crash,见下)
```

- **App bundle crash + 复现性归因(条件性注记,归因后不构成缺陷)**:全套轮
  App 宿主在**窗外既有测试** `ProcessVersionCarrierTests.
  testUndoToTopAndVersionSwapLeaveTheValueUntouched`(最后修改 `a33a6afd`,
  M5 process carrier 批,远早于本批)内异常退出(host exit=133),L055 机制
  正确置零计数(**非假绿**——机制工作正常)。日志前段 `AGX: Texture
  read/write assertion failed` = GPU 驱动层环境签名。**单独重跑
  `--bundle App` → 824/4/0 全绿不复现**;且 crash 轮内本批 +6 新法
  (AIMaskPatchFlowTests 两法〔mid-flight 8.8s 真跑〕+ ExportPresetTests
  四法)**已全部 executed + passed**——crash 与本批 Δfiles 无关,M2-7-3
  先例族(GPU 状态序漂移环境型 flake)同款归因(波 1 GrainTests 单 flake
  同判先例)。
- **对账(合并亲证)**:六 bundle 逐位与申报一致 + App 单独轮 824/4/0
  = 段和 687+460+494+729+284+379+824 = **3857** = 3851(波 1 终值)+
  ΔN₂ 6 **精确**;skip 31(六 bundle)+ 4(App 单独轮)= **35** = 波 1
  同值(本批零新 skip)。**3857/35/0 与执行方申报逐位闭合**。
- ΔN₂ 分解本路日志亲证:App 818→824(+6 = T3 +2 / T5 +4),其余六 bundle
  逐值与波 1 终值相同;0 MEMFAIL,七 bundle 全 8G 门内(IOPParity 7728MB
  居多轮历史带 7242..8111 中央;IOP 7881MB)。
- 包装命令退出码注记:本路复跑包装 `| tail` 吞了脚本非零退出码
  (ALL_EXIT=0 显示的是 tail 的),不影响判定——判定以 BUNDLE/TOTAL 行与
  App FAILED 注记为准(已按判据行裁定)。

## 二、T1 V17 深审——成立

- **门实现 bug 修复亲核**:SPEC_RE 终形 = `%(?:@|[a-zA-Z]+)`——`@` 显式位
  在案(`%[a-zA-Z]+` 首跑幻红形态 → `('%@',)` 空序列假 MISMATCH;修复
  正确性由活树 `edr_headroom_label` / `settings_lcr_size_mb` 两 String-arg
  键全绿佐证)。
- **八例 golden 亲跑**:`--self-test` PASS(exit 0)。红绿真实性亲读:红例
  断言 `any(e.startswith(...) for e in interp_spec_mismatch)` /
  `in interp_missing_variant`(检出才过),绿例断言 not-in——**非永真**。
- **逐参有序比对端到端亲测(独立 fixture,不依赖 self-test 内部断言)**:
  `--root/--catalog` 自建 fixture 三键——`p1_position`〔String,Int〕vs
  `%lld %lld` → **MISMATCH 红**(集合交集形会放行的位置洞被关闭,亲证);
  `p2_ordered`〔Int,Int〕vs `%lld %lld` → 绿;`p3_int32`(Int32)→ 绿
  (全 Int 族映射锚活体端到端)。
- **多参键活体实况(plan 预想 vs 实测)**:三多参活体
  (`settings_catalogs_rebuild_progress` 双调用点 / `session_counts` /
  `toast_import_partial`)在活树上**全部 EXEMPT**(成员链实参,禁误报纪律
  下不判)——逐参有序比对在活树上的 derivable 多参实例为零(38 键中
  derivable 8 键全部单参),位置洞防护实际由 golden g5 合成例 + 本路独立
  fixture 承担。**合规**(EXEMPT 是设计行为非放水),如实记录。
- **活体清偿键**:`catalog_session_remove_confirm_body %@` 尾块 :32420 纯
  插入 17 行(diff 全 `+`,JSON 无重排),裸静态键 :2072 原样,调用点
  SidebarView.swift:262 **零 diff** 亲证;措辞与相邻
  `catalog_session_remove_confirm_*` 键族对齐。
- **C-3 预言亲核**:McpLauncher 三键(pid/code/writes)**全部 EXEMPT 非绿、
  断言 5 层 PRESENT 过**——CHECKER C-3 预言精确命中。
- **D-5 绿例**:`toast_hdr_merge_done`(函数参数 `holeFraction: Float` →
  `Int(…rounded())` 包装形 → `%lld`)在 derivable 8 键中亲证绿(不 EXEMPT、
  不 mismatch)——E-2 供给面修订失守哨兵未触发。
- **首跑分诊 transcript 在案**(`evidence/v2m-02-t1/`):红面 = 恰 1 ABSENT
  (清偿键)+ 0 MISMATCH + EXEMPT 30 + FAIL(1)。EXEMPT 30→31 口径自洽
  (清偿键清偿前进 ABSENT 短路跳过深检,清偿后进深检 +1 EXEMPT)。
- **活树 --check 亲跑 PASS**:1688 source / 1936 catalog / 38 interp 全
  variant-PRESENT + spec-matched。

## 三、T3 PATCH-LIVEPLANE 深审——成立

- **余量盘点诚实性亲证**:E5 两残差原文(`M6-4-VALIDATION.md` :146)对照
  `b49215bb` 主修面(stamp + fire 身份比对 + schedule 缝前置)——残差①
  「末次 pass 后无 pending debounce 时平面驻留」(主修无释放点)与残差②
  「confirm 在飞中切图 = stamp 被写成交换后 URL」(主修的 fire 比对防
  「stamp 旧/消费新」,不防「stamp 被污染为新」)确实 open。销账臂不成立
  的裁定有据。
- **污染路径封闭性独立走查**:
  - eager 释放双点 = `LayerEditingState.select`(异值才释放,同值 no-op)+
    `EditorAreaView.onChange(of: loadedImageURL)`;`releaseLivePatchState`
    释放面 = livePlane/patches/patchState/debounceTask(对空 face no-op);
    残留 stamp 由既有 N-1 `releaseIfIdentityChanged` 消费点比对消化——
    语义正确。
  - 在飞竞态三件:`armedImageURL` 函数头捕获(任何 await 前)→ 装载门
    `guard live==armed ∧ selected==layerID else return ref`(门到 stamp 写
    之间同步段无 suspension point,D-3 检查点模式同构)→ stamp 恒取 armed
    (`releaseIfIdentityChanged(imageURL: armedImageURL)` +
    `patchImageURL = armedImageURL`)。三面合围,陈旧平面无法以新身份装载、
    新平面无法以旧身份 stamp。
  - mask 腿落点:`commitLayerEdit` stack guard 亲读(旧 layer 不在新 stack
    → no-op;`projectWriteSuppressed` 先行)——mid-flight 落空亲证。
- **两新测试判别力亲证**:①`testLayerSelectReleasesHeldPatchFace`——无
  eager 释放则 livePlane 断言红;同值 re-select 保 face 断言防过度释放。
  ②`testMidFlightImageSwitchLeavesNoSessionFace`——6000² 放宽 bake 窗
  (D-V2M2-3 申报的测试专用构造,零产线注入缝);无装载门/无 armed 捕获则
  livePlane/patchImageURL 断言红;任何切换时点(50ms 前/后)装载门均以
  live-vs-armed 比对捕获——判别力真实。潜在假红方向(bake <50ms 超快机器)
  只产 flake 不造假绿,可接受。

## 四、T5 EXPORT-PRESET-01 深审——成立

- **新文件接缝亲核**:`ExportPresetStore.swift` 独立文件(ExportState.swift
  **零 diff** 亲证)——NamingTemplateStore 同级先例成立;`validPattern`
  走 `ExportNamingEditor.parseFeedback`(页面 parse gate **复用引用**)、
  回落 = `NamingTemplateStore.builtIns[0].pattern`(**引用非复制字面量**,
  亲读)。
- **collisionPolicy 不捕获钉(编译期)**:`ExportPresetPanelFace` 字段面
  不含 collisionPolicy/gainMapHDR——投影不可能触达面外字段;测试②显式
  断言(先设 `.fail` + gainMap=true,apply 后断言原值)——**M-5 pin
  测试化亲证**。
- **typed degrade 双臂测试化**:悬挂模板 → builtIns[0].pattern 回落(有效
  腿照落);variant validate 失败 → 整 face 回 defaultFace(禁半落地);
  坏 JSON → 空库;built-in remove no-op + rename/remove 亲测。四法与 plan
  单测面逐项对应(ΔN +4 = 带上界)。
- **注入式 defaults + 键纪律**:`init(defaults:)`(KD-4 范式,body 零直读);
  `storageKey = "export.presets"` 唯一拼写,写点唯一(:306);既有
  `export.*` 六键零引用零 diff 亲证;AGENTS :490 登记在位(键形与实现
  双向一致)。Project.swift 恰一行登记 + BUNDLE-MAP 同批(APP 4)亲证;
  七新键(`export_preset_*`)尾块纯插入在 119 行 T5 xcstrings 批内。

## 五、T4 RELEASE-DIRECT-INJECT——亲证成立

- probe transcript 硬证据(`evidence/v2m-02-t4/`):「embedded 0 framework(s)」
  + LightamerCore **webp undefined syms = 0**(静态内联亲证)+ codesign
  verify ok + **PROBE PASS(pid=57377 alive, windows=1, rc=0)**——余量盘点
  「当前债形态已消」亲证;防御脚本形态(`Scripts/
  make-release-direct-launchable.sh`,110 行,零产线 diff)合规,D-V2M2-4
  「SPM/Tuist 链接代际回摆自愈通道」定位合理;make-dmg embed 缺口翻账建议
  在案。

## 六、T2 通道阻断证据质量 + D-6 定级表态

- **三条通道阻断可复核性亲核**:D-6 = t2-spin.sample.txt(10842 行正本,
  pid 42410,2026-10-16 02:13 执行时窗内)——3s 采样主线程 **1094/1094
  全在** NSHostingView.beginTransaction → ViewGraphRootValueUpdater.
  updateGraph → AG::Subgraph::update → SystemSplitView/SplitViewCoordinator.
  formCurrentItems(AttributeGraph update 循环,与 MANIFEST 记述精确一致);
  diag-a-editor.png 本路识图亲证症状(filmstrip 6 图带缩略图 + 视口中央
  legacy Session 空态卡「选择文件夹以创建会话」+ 右栏「未选择图像」——
  带图空态不一致态)。D-7/D-8 截图证据在案(D-7 复用波 1 1.8MB sample 正本
  同族)。
- **D-6 定级(error 级候选)独立性表态:成立**。①用户面:重开项目(常规
  工作流)编辑器完全不可用;②机检证据硬(sample 全帧 AG spin + CPU 99.9%
  + 屏面截图);③**与波 1 修法隔离**——D-6 栈在 SystemSplitView/
  SplitViewCoordinator(ShellView 布局面),波 1 D-1 修法触
  ColorMatchPanelModel params 面(两路验收证封闭),互不相交;④对照组在案
  (波 1 同会话新建路径 walk-8-editor.png 健康 → 非 GUI 环境全局劣化,
  特定于「重开」路径)。登记面完整(复现配方/影响面/sample/截图/资源处置
  全在);「登记不修」纪律合规。
- **T2 收兵裁定复核**:「不硬造判定」纪律适用(OQ-VM-5 先例);C 类硬锁行
  (24/25/27/28/29)确实未混入;26/39 Blocked-Env(供件族)与通道阻断
  分账诚实;harness 通道健康性论证(menu AX 修复波 1 堵点)有正向证据
  (项目重开/New Project/Import Folder 机检可达)。

## 七、D-4 裁决追认——成立

- **追认**:「通道不可达 ≠ 复验见 0」的区分逻辑成立。E2-1 返工触发条件
  =「走查批复验仍见 0 张」,语义前提 = merge 对话框实际呈现;本批 D-6/D-7/D-8
  阻断下对话框**从未呈现**(多选门 targets<2 不可达 + legacy 会话建立不可达
  + 导入停滞)——触发条件未被行使,不构成反证。波 1 代码面证据链
  (`.sheet(item:)` payload + arm 点 `targets.count` 构造 + 标题读
  `dialog.count` + Sessions 284/9/0 本路全套轮再证)无任何反证动摇。
- **义务链处置**:波 1 屏面证据四项(V2M-T1-02/D3-01/D4-01/D5-01)本批
  Blocked-Channel 保持 = **义务延续非销账**——D-6 修复后随走查批复走,
  派发令引用正本 = V2M-01-ACCEPTANCE-2ND §五 E2-1 + 本文件 §六。

## 八、偏差四项裁决(全部合规)+ 验收自产注记

| # | 偏差 | 裁决 |
|---|---|---|
| 1 | T5 实触 `ExportPresetStore.swift` 新文件替代 plan 的 ExportState.swift 行 | 合规——plan 侧预测不全(N-B 同族),DECISIONS 偏差 1 已申报,ExportState 零 diff 亲证 |
| 2 | ΔN₂ = +6 = 带 +2..6 上界 | 合规——T5 +4(波尾固定带上界)+ T3 +2(带内),逐任务如实记账 |
| 3 | T2 可达行集缩水为零(通道变体) | 合规——plan 风险节「缩水合法」的通道变体,逐行终态 + 诊断证据在 MANIFEST |
| 4 | T2 harness 修复波 1 menu-item 堵点 | 合规——正向偏差,改良证据在 MANIFEST(项目重开/面板腿全可达) |

**验收自产注记(非缺陷,零再修)**:

- **N1(T3 文件落位偏差未申报)**:plan files_modified 列 EditorState.swift +
  LayerEditingState.swift;实触 AIMaskEditing.swift + LayerEditingState.swift +
  EditorAreaView.swift(EditorState 零 diff——eager 释放挂 view onChange 而非
  EditorState 内部,语义形态选择)。DECISIONS 偏差表未含此项(T5 同类偏差
  有申报)。定级:plan 侧预测不全 + 申报面小缺口(修复语义与 E5 正本对齐,
  零行为疑点)。
- **N2(EXEMPT 计数口径)**:D-V2M2-1.3「30/38 site EXEMPT」为清偿前口径;
  清偿后实测 **31**(清偿键进深检)——记账精度,DECISIONS 未回填。
- **N3(幻红分诊面无 transcript)**:DECISIONS D-V2M2-1.1 所述 `%@` 字符类
  bug 的两例幻红(edr_headroom_label/settings_lcr_size_mb)修复前红面无
  transcript 留证(仅终形分诊红面在案);修复正确性由活树全绿独立佐证。
  过程证据缺口,注记级。
- **N4(位置洞防护的活体覆盖落空)**:plan 设想「多参活体
  settings_catalogs_rebuild_progress 等即门上线就要面对的形态」——实测三
  多参活体全 EXEMPT,逐参有序比对活体覆盖 = 0;防护由 golden g5 + 本路
  独立 fixture 亲证承担。设计行为(EXEMPT 禁误报优先),非放水;后续若
  derivable 多参键入树,门自动覆盖。

## 九、红线族两波合并总核对(亲跑,`git diff 7b252db1..08f9ebc4`)

- 全部 `*.metal` 零 diff ✓;`LightamerIOP/` 全域零 diff ✓;
  `LightamerSidecar.swift` 零 diff ✓;封存面(DrtRecord/GradeCatalog/
  Registry/HistoryStack/V50Order/ExportFormatSpec/ImageIOEncoders/
  WebPEncoder/ExportQueueContract)**全零 diff** ✓。
- `Project.swift` 全窗 = 恰一行(`ExportPresetTests.swift` 登记;
  dependencies 块零 diff、零新 SPM)✓;BUNDLE-MAP +6 行(T5 增行记录 +
  APP 4 行)✓。
- `*.xcstrings` 全窗 **136+/0-** 纯插入(T1 17 行 + T5 119 行;零删除行
  = 无重排)✓;`zh-audit --check`(V17 新门)PASS + `--self-test` PASS
  本路亲跑 ✓。
- UserDefaults:全窗唯一新写入键 = `export.presets`(ExportPresetStore:306
  唯一写点;其余 grep 命中为 accessibilityIdentifier 字符串误报,已甄别)
  ✓;AGENTS :490 登记在位 ✓。
- `\.runModal(` App/Sources 零命中 ✓;`String.LocalizationValue("` 插值禁形
  代码行零命中(唯一命中 = LightamerApp.swift:2069 **doc comment** 注记
  字面,注释免疫豁免锚,与 SUMMARY 申报一致)✓。
- 工作树 untracked 5 项全 `.work/` 文档域(含波 1 两路 ACCEPTANCE——
  验收文档 local-only 惯例)✓;构建 `caffeinate -dis` 包裹、单测走
  test-direct(零 xcodebuild test)✓;T2 走查批零 commit 零源码 diff ✓。

## 十、commit 清单(5 commits,diff 窗口逐一亲验)

| commit | 内容 | 文件 | 验收判定 |
|---|---|---|---|
| `2ba1d1fe` | T1 V17 门扩展 + 活体清偿 | zh-audit.py + xcstrings 17 行 + AGENTS 4 行 | 成立(§二) |
| `4914619c` | T3 PATCH-LIVEPLANE | AIMaskEditing/LayerEditingState/EditorAreaView + AIMaskPatchFlowTests +2 | 成立(§三) |
| `4ca893cb` | T4 RELEASE-DIRECT-INJECT | Scripts/make-release-direct-launchable.sh(110 行) | 成立(§五) |
| `de786663` | T5 EXPORT-PRESET-01 | ExportPresetStore 新文件 + ExportInspectorView + Tests +4 + Project.swift 一行 + BUNDLE-MAP + xcstrings 119 行 | 成立(§四) |
| `08f9ebc4` | T6 收口文档 | SUMMARY/DECISIONS + AGENTS 终值行 | 与实测逐位一致 |

## 十一、结论

**PASS / 0 error + 0 minor(+1 条件性全套轮注记 + 4 验收注记)**。T1/T3/T5
深审逐项成立(门语义亲测含独立 fixture 位置错配红、E5 残差封闭、M-5 pin
编译期钉死 + 测试化),T4 亲证成立,T2 通道受阻登记质量合格且 D-6 error 级
候选定级表态成立,D-4「返工不触发」裁决追认成立;对账 3857/35/0 合并亲证
闭合(六 bundle 逐位一致 + App 单独轮 824/4/0;全套轮 App crash = 窗外既有
测试环境型 flake,单轮不复现,L055 机制正确置零非假绿);红线族两波合并
全零;执行方报告无虚报。**放行**:账面翻新(TODO/GOAL-STATE)交闭环批统一
执行;D-6/D-7/D-8 转修复批入口(登记不修);波 1 屏面证据四项义务延续至
D-6 修复后走查批。不 push(按派发令)。
