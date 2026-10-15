# V2M-01 ACCEPTANCE（波 1 缺陷修复批——第一路独立验收，2026-10-16）

> 验收方：第一路独立验收 subagent（不轻信执行方报告，逐条实测；夜间全自动授权链）。
> 对象：执行链 `54124c7e..bb16f8c4`（6 commits），基线 `7b252db1`，HEAD = `bb16f8c4`。
> 结论：**PASS / 0 error + 0 minor**——五缺陷代码面逐项亲验成立、全套对账精确闭合、
> 红线族全零；一项**条件通过注记**（GUI 屏面证据四项 Blocked-Env 挂 V2M-02 T2 复走，
> 见 §七）+ 两条**验收注记**（N-A 供件级回归钉的措辞精度 / N-B plan files_modified
> 清单不全，均非缺陷）。

## 一、全套独立复跑（本路亲跑，非转抄）

`caffeinate -dis xcodebuild build-for-testing`（exit 0，新鲜构建）→
`caffeinate -dis Scripts/test-direct.sh --all` →

```
BUNDLE|IOP|687/5/0|peakRSS=7526MB|417s
BUNDLE|IOPParity|460/3/0|peakRSS=7966MB|759s
BUNDLE|Layers|494/5/0|peakRSS=807MB|165s
BUNDLE|Library|729/4/0|peakRSS=621MB|78s
BUNDLE|Sessions|284/9/0|peakRSS=1626MB|62s
BUNDLE|Export|379/5/0|peakRSS=6463MB|203s
BUNDLE|App|818/4/0|peakRSS=2832MB|361s
TOTAL|3851/35/0|2045s   exit 0
```

- **对账精确**：3848（M6-6 基线三路同值）+ ΔN₁ 3 = **3851**；executed 段和
  687+460+494+729+284+379+818 = 3851 ✓。**与执行方申报逐位一致**（2045s vs 2047s）。
- ΔN₁ 分解亲证：IOP +1（`testAutomaticDecodeStaysChannelNeutralInTheWorkingSpace`）
  + App +2（`testSnapshotRefreshFollowsTheCommittedRecord` /
  `testLiveWindowOverridesTheSnapshotUntilCommit`）= **+3 精确**；ΔN 逐位与
  SUMMARY §一记账一致，段和闭合。
- 0 fail / 0 MEMFAIL / 七 bundle 全 8G 门内（IOPParity 7966MB 贴线，±3% 方差带内
  ——M6-5 参照 7242，SPIKE 注记顺序漂移带）。
- GrainTests flake 独立复核：本路全套净轮 Grain 族全绿（0 fail），执行方单 flake
  归因（GPU 状态序漂移，M2-7-3 先例族）成立。

## 二、D-1 修法深审（最重项）——成立

- **实现亲读**（`54124c7e` diff + HEAD 全文件）：`snapshotParams`/`snapshotRecord`
  存储属性 + `updateInstance` 兑现 :54 doc comment 缺席许诺；四刷新点（init /
  view `.onChange(of: instance)` / solve 回填 `refreshSnapshotFromChain` /
  `commitStrengthDrag` 尾 live 值臂）齐备。
- **机检 AC 亲跑**：`pipeCoordinator` 全部触达点 = :126（refreshSnapshotFromChain，
  action 上下文）/ :135（hasImage，plan 免除面）/ :187-:231（solve 动作上下文）——
  **params（:142-149）与 currentRecord getter 函数体零 coordinator 触达** ✓。
- **五路径覆盖亲核**（不轻信 CHECKER，独立走链）：
  ①实例切换 = `InspectorView.swift:336-341` `editableInstances` 直读
  `editorState.instances`（@Observable）→ `panelView(for: effective)` 携新值 →
  onChange 触发；②commit 尾 = `endEditing → commitContinuousEdit` 落 instances →
  body 重渲；③MCP `apply_params` = SessionBatchApplier 直改 instances 同②；
  ④undo-redo/版本 swap = `rebuildInstances`（EditorState.swift:448 doc comment
  明文）同②；⑤初值 = onAppear init（`refreshSnapshot(from: instance)`）。
  猎残：值不变的 committed 写（编辑其它 op）onChange 不触发但快照无漂移——正确
  不触发；藏面板 = view 重建走 init①闭合。**无第六漏路径**。
- **C-1/C-2 落实亲验**：onChange 挂 `content(_ model:)` 非 nil 作用域（双参
  macOS 14+ 正形）；commit 尾择 live 值臂（竞争窗读面连续 + onChange 终态兜底，
  论证自洽）。
- **两新测试在册且真实执行**（App bundle 818 executed 含 +2，非 skip）；
  D-H1 既有法不红（套件全绿）。
- **Film/Drt 三分「健康」独立复核**：`effectiveFilm/DrtRecord`（HistoryStack.swift
  :521-536）= 已物化 items[0...position] 尾扫，零 JSONDecoder；carrier 字典查零
  解码——与 ColorMatch「每读 instances 线性扫 + 每读 JSONDecoder」不同构，
  「无实测证据不预防性重写」裁定合规，两文件零 diff ✓。
  注记：执行方「sample 84/84 无 Film/Drt 叶子」论断无 first-hand transcript 可
  复核（sample 输出未入库），本路裁定以读码证据独立成立，sample 论断降为佐证。

## 三、D-2 bisect 链条复核——成立（关键实验亲跑复现）

- **TRANSCRIPT 数字亲核**：探针输出文件与 TRANSCRIPT 逐位一致——unmanaged
  v9 means R41.09/G44.41/B40.78 vs v8 R40.91/G44.05/B41.03（近同平衡，H-Aa
  原形证伪）；WS 腿 v9 linMeans 0.0393/0.1522/0.1026（G/R=3.87 毒）vs v8
  0.1611/0.1716/0.1615（G/R=1.065 净）；spread 修前 (0.1522−0.0393)/0.1522=
  0.742 > 0.5 断言界（应红）/ 修后 0.0612 ≈ 0.062（绿）。
- **关键步重跑（本路亲跑）**：以修后 RAWDecoder.swift 原文 swiftc 直编探针
  （/tmp/v2m-acc-probe，M2-7 方法论）复跑 GREENCAST-7RM5.ARW：
  - `automatic` → used=**v8**，WS 0.1611/0.1716/0.1615 = 与修前 v8 腿**逐位一致**
    （修法生效 + 净）；
  - `forceV9` → used=**v9**，WS 0.0393/0.1522/0.1026 = 修前 v9 腿**逐位重演**
    （G/R=3.87 仍毒）——「forceV9 显式档仍毒」遗留面申报**亲证**；
  - `forceV8` → v8 净 ✓。
  毒化腿 = CI 色管理转换 × v9 CoreML 输出（非解码/非文件/P3 标签本身）的机制
  结论可复现性闭合。
- **三选裁定理由复核**：automatic 收紧 = 纯函数缝零红线、白名单不可建立
  （机制全 v9 文件同构 + beta 名单逐季扩张）、健全性门无法区分夜景绿树——
  弃二选一的理由为机制性论证非事后包装，成立。
- **回归钉在册性亲验**：`testAutomaticDecodeStaysChannelNeutralInTheWorkingSpace`
  （供件级，spread<0.5 界，正例对照 0.742 应红/0.062 绿）+ resolve 矩阵更新
  （automatic 三臂全 v8）+ `testRAW9OptIn` 重钉（默认 v8 + 显式 forceV9 仍达 v9）
  三面在册；**本路全套轮该法 executed 非 skip**（GREENCAST-7RM5.ARW untracked
  供件在盘，回归钉真实执行，与探针复跑数字互证）。重入口条件登记于 TRANSCRIPT
  「重启条件节」，完备。
- **屏面证据亲验**（本路识图）：step1-editor-A.png（修前 21:41 build）全画面
  绿染（树冠饱和绿/白墙发绿）vs walk-0-grid.png（修后 22:27 build）同文件自然
  色彩——**V2M-D2-02 修后复验 PASS 亲证**；Preview.app 证人
  （step7-preview-witness.png）在案。
- 供件替代合规：原两缺陷文件不在盘（mdfind/find 申报），同机身 ILCE-7RM5
  （omp-g6-proj/session2/A.ARW）替代 = plan 供件门明许形态。

## 四、D-3 / D-4 / D-5 逐项——成立

- **D-3**（`83f48bbb` 亲读）：两腿（grid onChange / filmstrip onOpen）收敛
  `switchCurrent(to:)`（editor-phase guard + `openCurrent` + 单 phase 写，幂等）；
  `loadCurrentImage` 唯一 pre-write await（`defaultLookPending`）后补
  `Task.isCancelled` dead-drop（:202），检查点到状态写为同步段无 suspension
  point——**竞态封闭论证独立成立**；尾 `clearDefaultLookPending` await 后无
  状态写 ✓。A/B 字节相同副本假象论证（cmp 亲证申报）与 omp-02「末图锁定」
  先例对照在案。ΔN=0 记账合规（视图级 seam 不可纯函数化，DECISIONS 申报）。
- **D-4**（`e74be37b` 亲读）：三计数对话框（focus_stack/stack_denoise/hdr_merge）
  改 `.sheet(item:)` + `MergeDialogCount(count:)` **arm 点构造**（局部
  `targets.count` 快照随 item 进闭包）；动作面零改（pendingTargets + start
  按钮字节同前）；Mertens/pano 静态体保持 isPresented（申报一致）。grep 亲跑：
  `pendingTargets.count` 文件内零命中、三标题行读 `dialog.count` ✓。两候选下
  都鲁棒形 + 仍 0 则「快照上移」返工预案自报（诚实面完整）。
- **D-5**（`8133726e` 亲读）：`Int((holeFraction * 100).rounded())` 对齐在册
  `%lld` 变体（HEAD :2027 亲读）；xcstrings 零改动；`zh-audit --check` PASS
  亲跑（1682/1929/30 全 variant-PRESENT，与 SUMMARY 申报一致）；半分界
  away-from-zero 一句已记 DECISIONS。V17 绿例措辞（函数参数 + Int 包装推导）
  三处对齐在案。

## 五、skip 漂移 +11 独立核实——申报精确证实（非本批静默跳过）

- **机制**：`Fixtures.arw`（7RM5-LosslessCompressedLarge.ARW）/
  `Fixtures.dng`（5G4A DNG）缺席——TestRAW 内部盘镜像现仅 4 文件
  （CR3/NEF/RAF/RAF100MP），`.work/plans/01-05/samples` 缺席，
  `LIGHTAMER_RAW_SAMPLES_DIR` 未指 → 三级搜索序全 miss → XCTSkip。
- **时点（先于本批）**：TestRAW 目录 mtime = **10-15 15:44:46** < V2M planner
  docs 20:40-20:54 < T1 执行 21:20——漂移在批开工前 5.5h 发生；T2 批首探针
  即申报「原两缺陷文件不在盘（mdfind/find 全域无 5G4A）」互证。
- **身份（逐法差分，本路全套日志亲提）**：基线恒有族 24
  （SkinRegion 1 / ColorChecker×2+ManualProbe 3 / AIMask×2+Bake+GradePerf 4 /
  Library Benchmark×2+ThumbObs+GPS 4 / CatalogBench×3+Perf07 4 /
  PerfProbe×4 4 / Depth×4 4）+ 漂移 11 = IOP RAWDecoderTests×4
  （testDecodeARW / testDecodeDNG / testDecodeIsCancellable〔:221 arw 段〕/
  testRAW9OptIn）+ Sessions SessionThumbnailProviderTests×5 + Layers
  `testRealRAWRoundTripThroughHistoryAndSidecar` + Export
  `testRealRAWWalkFillsSixFieldsAgreeingWithImageIO`——**11/11 全部真 RAW
  样张域**，逐 bundle 差分 IOP+4/Sessions+5/Layers+1/Export+1 与 SUMMARY
  申报逐族一致；11 法全部先于本批存在（非本批新法）。
- **反向证明（非静默跳过）**：本批唯一供件级新法
  `testAutomaticDecodeStaysChannelNeutralInTheWorkingSpace` **未出现在 skip
  列表**（executed 真跑）——本批未引入任何静默 skip，且新供件域
  （input/RAW/GREENCAST-7RM5.ARW，gitignore 在册）反而部分回填了真 RAW 测试面。

## 六、红线族亲跑（全部 PASS）

- `git diff 7b252db1..HEAD` = 11 文件（9 代码/测试 + 2 T6 文档）；fix 链
  `7b252db1..8133726e` = **9 文件 337+/75-** 与 SUMMARY §五逐字一致。
- `LightamerIOP/` 零 diff ✓；全部 `*.metal` 零 diff ✓（D-2 修订口未行使）；
  `Project.swift` 零 diff ✓（零新 SPM/零新测试文件/tuist generate 未触）；
  `*.xcstrings` 零 diff ✓；封存面（Pipe/History、Sidecar、DrtRecord、
  GradeCatalog、Registry、V50Order、六格式矩阵）零 diff ✓。
- `\.runModal(` App/Sources 零命中 ✓；`String.LocalizationValue("…\(x)…")`
  插值禁形代码行零命中 ✓；UserDefaults 零新键（diff 新增行 grep 空）✓；
  `zh-audit --check` PASS ✓；工作树零新增 untracked 源文件 ✓（现存 3 项
  untracked 全在 .work/ 文档域，mtime 均先于本批）。
- 构建 `caffeinate -dis` 包裹、单测走 test-direct（零 xcodebuild test）✓。

## 七、偏差四项裁决（全部合规）+ 条件通过注记

1. **T2 步⑥⑦替代 = 合规**：步⑥为条件步（「解码净而编辑器绿时」才走），
   ④已坐实毒化在转换腿，尾段双臂前提不成立；步⑦ Alcedo→Preview.app 证人
   替换证明力不降反升（Preview 与缺陷链同 Apple RAW 栈，Alcedo 自养解码器
   异栈证明力更弱），TRANSCRIPT 已申报。
2. **RAWDecoderTests 两法改语义 = 合规（附 N-B 注记）**：automatic 收紧后
   `testRAW9OptIn` 旧断言必红，同缝重钉必要；plan files_modified 清单遗漏
   该文件属 plan 侧不全（N-B），零 Project.swift 触碰，DECISIONS 已申报。
3. **GUI Blocked-Env 四项 = 合规（不硬造裁定成立，附条件通过注记）**：
   通道堵点有具体诊断证据（walk-15 AXPress err=0 不触发 + hasImage nil
   面板级异常 + walk-19/21b cmd+click 旗标失效 + 项目重开 menu-item 合成
   点击被吞——L057 形态先例），机检/单测面全部闭合，与 CONTEXT OQ-VM-5
   「供件缺席行如实记 Blocked 保持，不硬造判定」先例同款。
4. **GrainTests 单 flake = 合规**：同码全绿 + 单类复测 8/0/0 + diff 窗口不含
   grain 面 + 本路全套净轮复证——GPU 状态序漂移归因成立（M2-7-3 先例族）。

**条件通过注记（唯一非全绿面）**：GUI 屏面证据四项（D-1 三零消除点击 /
D-3 加固循环 / D-4 标题计数 / D-5 toast zh 文案）本批未取得，挂 V2M-02 T2
Manual-Only 走查批复走——**波 2 验收时此四项为硬义务**；D-4 若复验仍见 0
按 DECISIONS 自报「快照上移」预案返工。批外疑点两笔（项目面 colormatch
hasImage=nil / 导入进度停滞 Registered-obs + import-stall-sample.txt 1.8MB
在案）原样上报未动手，登记质量合格（hasImage 疑点不触 D-1 修法正确性——
params/currentRecord getter 零该读法，本路机检亲证）。

**验收注记**：
- N-A：`testAutomaticDecodeStaysChannelNeutralInTheWorkingSpace` doc comment
  「UNCONVERTED channels near-balanced (asserted first from the unmanaged
  render)」措辞读似测试内先断言，实际 unmanaged 平衡断言只存在于 bisect 探针；
  固定供件（夜景近中性）下无假阳风险，纯措辞精度，不构成缺陷。
- N-B：plan `files_modified` 未列 `RAWDecoderTests.swift`（执行批同缝修正已
  申报）——后续 plan 修订时同类语义重钉文件宜预列。

## 八、commit 清单（6 commits 逐一亲验 diff 窗口）

| commit | 内容 | 文件 | 验收判定 |
|---|---|---|---|
| `54124c7e` | T1 D-1 快照去热读 | 3 文件（Model/View/Tests） | 成立（§二） |
| `5567b56c` | T2 D-2 automatic 收紧 | 3 文件（RAWDecoder/Tests×2） | 成立（§三） |
| `83f48bbb` | T3 D-3 换图钉序 | 1 文件（EditorWorkspaceShellView） | 成立（§四） |
| `e74be37b` | T4 D-4 sheet(item:) payload | 1 文件（SessionBrowserView） | 成立（§四） |
| `8133726e` | T5 D-5 toast Int 化 | 1 文件（LightamerApp） | 成立（§四） |
| `bb16f8c4` | T6 收口文档 | 2 文件（SUMMARY/DECISIONS） | 与实测逐位一致 |

## 九、结论

**PASS / 0 error + 0 minor（+1 条件通过注记 + 2 验收注记）**。五缺陷修法
逐项亲验成立，全套 3851/35/0 本路独立复跑逐位闭合，ΔN₁=+3 精确，skip +11
漂移独立核实确系环境先于本批（非静默跳过），红线族全零，偏差四项全部合规，
执行方报告无虚报。**放行**：账面翻新（TODO/GOAL-STATE/AGENTS）交闭环批统一
执行；GUI 屏面四项证据义务随 V2M-02 T2 走查批硬性跟踪。不 push（按派发令）。
