# V2M-01 ACCEPTANCE-2ND（波 1 缺陷修复批——第二路独立验收，2026-10-16）

> 验收方：第二路独立验收 subagent（零共享第一路上下文；不轻信执行方报告与
> 第一路 ACCEPTANCE，逐项实测；夜间全自动授权链）。制度位 = dual_acceptance
> 第二眼（本批以 subagent 替代 omp 位——omp computer-use 走查批挂 V2M-02 T2）。
> 对象：执行链 `54124c7e..bb16f8c4`（6 commits），基线 `7b252db1`，HEAD =
> `bb16f8c4`（工作树亲证一致；untracked 仅 4 项全 `.work/` 文档域且先于本批）。
> **结论：PASS / 0 error + 0 minor**——与第一路 PASS 结论一致，无分歧。
> 附 1 条**条件通过注记**（同第一路：GUI 屏面证据四项挂 V2M-02 T2 硬义务）
> + 2 条验收注记（N-A/N-B 恰当性复核成立）+ 4 条第二路自产**执行注记**
> （E2-1..E2-4，均非缺陷，见 §五）。

## 一、全套独立复跑（本路亲跑，非转抄；新鲜构建）

`caffeinate -dis xcodebuild build-for-testing`（exit 0，增量新鲜构建）→
`caffeinate -dis Scripts/test-direct.sh --all` →

```
BUNDLE|IOP|687/5/0|peakRSS=7254MB|425s|sampling=time
BUNDLE|IOPParity|460/3/0|peakRSS=7727MB|760s|sampling=time
BUNDLE|Layers|494/5/0|peakRSS=806MB|159s|sampling=time
BUNDLE|Library|729/4/0|peakRSS=622MB|78s|sampling=time
BUNDLE|Sessions|284/9/0|peakRSS=1627MB|61s|sampling=time
BUNDLE|Export|379/5/0|peakRSS=6104MB|202s|sampling=time
BUNDLE|App|818/4/0|peakRSS=2832MB|368s|sampling=time
TOTAL|3851/35/0|2053s   exit 0（OK direct launch, no testmanagerd）
```

- **对账精确**：executed 段和 687+460+494+729+284+379+818 = **3851** =
  3848（M6-5 基线）+ ΔN₁ 3 ✓。**与执行方申报（3851/35/0/2047s）及第一路
  亲跑（3851/35/0/2045s）三路同值**——executed/skip/failed 逐位一致。
- 0 fail / 0 MEMFAIL / 无 crash、无 no-total-line（L055 签名零命中）、无
  ANE-DEGRADED 注记；七 bundle 全 8G 门内（峰值 IOPParity 7727MB，贴线带内：
  第一路 7966 / 执行方 7546 / 本路 7727，±3% 方差带注记适用）。
- **ΔN₁ 分解本路日志亲证**：App +2 =
  `testSnapshotRefreshFollowsTheCommittedRecord` +
  `testLiveWindowOverridesTheSnapshotUntilCommit`（两法 passed，非 skip）；
  IOP +1 = `testAutomaticDecodeStaysChannelNeutralInTheWorkingSpace`
  （passed 0.888s——**供件级回归钉本路真跑**，GREENCAST-7RM5.ARW 在盘 +
  gitignore 在册亲证）。
- **skip 35 身份本路逐族差分**：基线恒有 24 + 漂移 11 全部真 RAW 样张域
  （IOP RAWDecoderTests×4〔testDecodeARW/testDecodeDNG/testDecodeIsCancellable/
  testRAW9OptIn〕+ Sessions SessionThumbnailProvider×5 + Layers
  testRealRAWRoundTrip×1 + Export testRealRAWWalk×1），与 SUMMARY §三申报
  逐族一致；本批新法零静默 skip。
- GrainTests flake 独立复核：本路全套 IOP 轮 Grain 族 9 法全绿——执行方
  单 flake（GPU 状态序漂移，M2-7-3 先例族）归因成立，未复现。

## 二、五面独立审计（自选切入，逐面结论）

### 面 1（T1 内存/性能面）——修法成立，陈旧窗口有界

- **快照 vs live 分叉时长分析**：committed 写 → 快照刷新的三类时延——
  ①拖动 commit 尾 = **同步 live 值臂**（`commitStrengthDrag` 置 nil 前采纳
  末次 live 值 + `setParams` 同步重座 record）——分叉窗 = 0；
  ②solve 回填 = 动作上下文同步 `refreshSnapshotFromChain`——分叉窗 = 0；
  ③外部写（实例切换/commit 重渲/MCP 活图写/undo-redo+版本 swap rebuild）=
  观察驱动 `.onChange(of: instance)` seam——分叉窗 = **一次视图更新周期
  （≤1 帧）**，滑杆位置至多陈旧一帧后自愈，无累积漂移（值相等则 onChange
  不触发 = 快照本就无漂移，正确不触发）。
- **实例切换瞬间**：`ModuleInstance` 为 Equatable 值类型（亲验在位）；
  面板宿主若随实例重建走 init 刷新点①、原地更新走 onChange——两臂均闭合
  （first-path §二 同判，本路独立走链成立）。
- **并发 MCP 写**：活图 MCP 写腿实走 `pasteLive` → EditorState
  （LightamerApp.swift :2307-2311 亲读）——写域 = editorState（MainActor），
  模型 `@MainActor @Observable`（:32-34 亲读），快照存储属性无跨线程竞态；
  `SessionBatchApplier` 直写的是**离线图 sidecar**（不开面板，seam 无义务）。
- **机检断言非永真性**：①grep 结构机检 = 形态级（getter 体零 coordinator
  触达——本路亲跑，触达点 :126/:135/:187/:203/:221/:231 全在动作/豁免
  上下文，与 first-path 引用逐点一致）；②两新测试**判别力亲证**：若
  `updateInstance` 内 `refreshSnapshot` 缺席，快照停 0.2 而 third-level
  序不接（snapshot 非 nil 压住 instance 层）→ 断言 0.7 红；若 commit 尾
  live 值臂缺席，commit 后回落 init 快照 0.2 ≠ 0.6 红——两法均非永真；
  ③装配 helper 真实（真 EditorState+PipeCoordinator+MetalContext+Registry，
  非桩）；④solve 落 history 有服务级法（testSolveTwiceLandsByteIdenticalParams）
  覆盖。**三零消除的屏面（进度态/sidecar 落盘）= GUI 域**，XCT 不可达
  （测试性边界已如实登记），挂条件通过注记。
- 小缺口（注记级）：solve 回填刷新（`refreshSnapshotFromChain`）无直接
  单测；缺席时 seam 一帧后兜底，无用户可见面——E2-4。

### 面 2（T2 修法面）——automatic 收紧成立，两钉独立，前向安全

- **实现形态**：`resolveDecoderVersion` switch 的是**自家 `DecoderRequest`
  三 case**（非 `CIRAWDecoderVersion` 穷举）——未来 RAW 10（version10 入
  `supported` 数组）零编译破缺、零行为意外：automatic 恒 v8（与新 v9 同
  政策延续）、forceV9 腿 `.contains(.version9)` 判定不变。`:183` 请求点
  `requested == .version9` 一致；`used` 从 resolved 推导，readback 面
  自洽。
- **两回归钉独立性亲核**：规则钉 `testResolveDecoderVersionMatrix` = 合成
  7 断言（三 automatic 臂全 v8 + forceV8 + forceV9 三臂含正例 v9），
  **零供件依赖、恒执行**——供件缺席时 automatic 再投毒的静默回退由矩阵
  红屏守岗 ✓；供件钉 = 端到端（真实 WS 转换 + spread<0.5 + used==.v8
  双断言），能抓**绕过 resolve 的硬编码 v9**（矩阵抓不到的面）——两层
  正交非冗余 ✓。本环境 `testRAW9OptIn` 因 Fixtures.arw 缺席 skip，其
  「默认 v8 + forceV9 达 v9」两断言在本机由矩阵 + 供件钉同事实覆盖，
  样张域回填后自动归队（E2-3）。
- **v8/v9 语义边界（收紧的隐性代价，登记级）**：automatic 恒 v8 使
  X-Trans/Quad-Bayer 机身失去 RAW 9 融合 demosaic+denoise 的质量面
  （STACK.md：X-Trans 恰是 RAW 9 ML 引擎收益最大处），且 forceV9 在
  v9 能力机身上经 WS 转换仍产出毒化平面（TRANSCRIPT 遗留面亲证）——
  即富士机身当前实际**无可用 v9 路径**。DECISIONS 已记 forceV9 遗留 +
  重入口条件，但 X-Trans 质量代价未显式点名——建议闭环批 AGENTS 增量
  节补一句（E2-2，非缺陷：毒化下收紧是正确权衡，UI 零改）。
- 证据链亲核：探针输出文件（step4-decode-probe-A/-control.txt）与
  TRANSCRIPT 数字**逐位一致**（unmanaged v9 R41.09/G44.41/B40.78 ≈ v8
  R40.91/G44.05/B41.03；WS v9 G/R=3.87 毒 vs v8 1.065 净；对照文件中性
  spread 修前 0.742 / 修后 0.062）；2×2 判别结构（同文件同转换唯解码
  版本异 + 同解码异转换 + 异文件对照 + Preview 证人）机制结论成立。
  本路未重跑探针——供件级回归钉在全套轮真跑即端到端活体复证（优于
  一次性探针）。

### 面 3（T3 竞态面）——检查点唯一性论证独立复核成立

- **逐 await 清点**（HEAD `loadCurrentImage` 全函数亲读）：`await #1`
  （`defaultLookPending` 库读）→ 检查点 `if Task.isCancelled { return }`
  → 两状态写（`versionCoordinator.projection` + `editorState.load`），
  检查点到写为**同步段无 suspension point**；`await #2`
  （`clearDefaultLookPending`）= **终态 await，其后零状态写**——且取消
  传入时 `try?` 吞 CancellationError → marker 不清 = 良性（mint 分支
  重探 .lra 事实，注释明示幂等）。**无第二 pre-write await 漏防**。
- **检查点作用域细节**：检查点位于 `if let store` 块内——store 为 nil
  （Sessions 模式）时 await #1 整块跳过 = 写前无 suspension = 无竞态面，
  作用域恰覆盖唯一 suspension 路径 ✓。
- **cooperative cancellation 真达**：`.task(id: currentImageID)` 的
  SwiftUI 语义 = id 变更先取消旧任务再起新任务；旧任务无论被取消于
  await 中途还是恢复后，`Task.isCancelled` 在恢复点必真——被超替任务
  死于状态写之前，陈旧 projection/load 竞态类**结构性封闭**。
- **switchCurrent 收敛**：两腿（grid onChange / filmstrip onOpen）同入
  单 mutation（phase guard + openCurrent + 单 phase 写）；同 id 幂等
  no-op；双触发（同一点击 onChange+onOpen）第二次被 id guard 挡。旧形态
  onOpen 腿**缺 openCurrent 收敛**（只写 phase）——修后消除双真相序。
- A/B 字节相同副本「未换」观感假象解释（cmp 亲证申报）与真 stuck 类
  （竞态）分层清晰，`loadedImageURL` 守卫对异路径同像素副本放行 = 与
  假象解释自洽。

### 面 4（波间衔接）——义务链实质完备，枚举精度交由派发

- **四行 Blocked-Env 登记完备性**：V2M-T1-02 / V2M-D3-01 / V2M-D4-01 /
  V2M-D5-01 四行在 `.work/gui-acceptance/v2m/MANIFEST.md` 逐行有终态 +
  通道堵点诊断证据（AXPress err=0 不触发 + cmd+click 旗标失效 + 项目重开
  menu-item 吞点击）+ 代码面机检替代证据；「判据剩余面」节显式指 V2M-02
  T2；committed 面 = V2M-01-SUMMARY §四/§六（bb16f8c4 在库）。
- **缺口注记（E2-1，非缺陷）**：V2M-02 plan T2 的可达行集枚举以
  m6-closeout 行 id 为键（03/05/08 复查条款），四个 V2M 专属行 id 未入
  plan 文本——义务实质三处登记（v2m MANIFEST / SUMMARY §四 / 第一路
  ACCEPTANCE §七）不失，但严格按 plan 文本执行的走查 executor 可能漏看
  v2m 专属行。**处置 = V2M-02 T2 派发令显式列出四行 id + D-4 返工触发**
  （本文件即为派发令可引用正本）。
- **D-4 返工预案触发条件明确性**：DECISIONS §D-4 明文「走查批复验仍见 0
  → 按风险节『快照上移』预案返工（一轮损失，不产假交付）」——触发条件
  （复验仍 0）、动作（快照上移）、损失界（一轮）三要素齐备 ✓。
  `.sheet(item:)` 形态在 M-1 两候选下均鲁棒的论证独立复核成立（item 值
  即呈现触发本体；arm 点同闭包构造 `targets.count`，七 arm 点全数带
  payload 亲验，Mertens/pano 静态体零计数读）。

### 面 5（偏差与疑点）——四偏差全部合规，两批外疑点证据链合格

1. **T1 onChange 双参形**（`{ _, newInstance in }`，macOS 14+ 正形 +
   C-1 非 nil 作用域）：diff 亲读成立，语义等价申报准确。
2. **T2 步⑥替代**：步⑥前提「解码净而编辑器绿 → 管线双臂」在④坐实
   「毒化在解码→WS 转换腿（iop 尾段上游）」后，尾段双臂比较无分析价值
   （两臂同承毒化输入平面）——替代 = 计划内升级非规避，TRANSCRIPT 申报。
3. **T2 步⑦证人替换**（Alcedo→Preview.app）：Preview 与缺陷链同 Apple
   RAW 栈，「文件无恙 + Apple 栈可正确渲」的证明力对本假说链**更强**
   （Alcedo 自养解码器异栈，异常时反而无法归因我方 vs 文件）；成本论证
   （深 GUI 导入）成立。
4. **RAWDecoderTests 同缝改**（plan files_modified 未列）：automatic
   收紧后 `testRAW9OptIn` 旧断言必红，重钉必要；零 Project.swift 触碰
   亲证；即第一路 N-B，定级「plan 侧不全注记」恰当。
5. **批外疑点①hasImage=nil**：证据链 = walk-15 AXEnabled=true 而视觉
   disabled + 读法定位（`pipeCoordinator.liveImageURL`）——**与 D-1 修法
   正确性隔离亲证**（params/currentRecord getter 体零该读法，本路 grep
   亲跑），登记质量合格，独立排查建议恰当。
6. **批外疑点②导入停滞**：import-stall-sample.txt（1.8MB sample 亲验
   在案，主线程 display-cycle layout churn 特征）+ Registered-obs 定级 +
   M2-9 F-1 家族疑似的谱系标注——登记质量合格。
7. **GrainTests 单 flake**：本路全套净轮未复现（9 法全绿），同码同环境
   下归因 GPU 状态序漂移成立。

## 三、红线族亲跑（全部 PASS，独立重跑非转抄）

- `git diff 7b252db1..HEAD` = 11 文件（9 代码/测试 + 2 T6 文档），
  563+/75-；fix 链五 commit 窗口与 files_modified 申报一致（RAWDecoderTests
  同缝追加 = N-B）。
- `LightamerIOP/` 零 diff ✓；全部 `*.metal` 零 diff ✓（D-2 修订口未行使）；
  `Project.swift` 零 diff ✓（零新 SPM/零新测试文件）；`*.xcstrings` 零
  diff ✓；封存面（Pipe/History、Sidecar、Graph/DrtRecord、GradeCatalog、
  Registry）零 diff ✓。
- `\.runModal(` App/Sources 零命中 ✓；`String.LocalizationValue("…\(x)…")`
  插值禁形代码行零命中（唯一命中 = LightamerApp.swift:2069 **doc comment**
  注记字面——T5 commit +8 行致 plan 锚 :2061 平移，注释免疫豁免不变；
  拼接形豁免锚 ExportInspectorView.swift:433 原位未触）✓。
- UserDefaults 零新键（diff 新增行 grep 空）✓；`zh-audit --check` PASS
  亲跑（1682 source / 1929 catalog / 30 interp 全 variant-PRESENT）✓；
  工作树零新增 untracked 源文件（4 项全 .work/ 文档域）✓。
- 四对话框/toast 键目录亲查：`*_dialog_title %lld` ×3 + `toast_hdr_merge_done
  %lld` 全部在册且 en/zh 整数语义（T4 标题读 `dialog.count` Int + T5
  Int 化——查表键逐位吻合，CHECKER 关注点 #6 复核成立）。

## 四、第一路结论复核

- **条件通过注记（GUI 四项挂 V2M-02 T2）**：定级恰当——通道堵点有具体
  诊断证据、机检/单测面全闭合、CONTEXT OQ-VM-5「不硬造判定」先例适用；
  本路维持同一条件（四行清单见 §五 E2-1）。
- **N-A（供件钉 doc comment 措辞）**：亲读测试代码证实——unmanaged 平衡
  断言只在 bisect 探针、不在测试体内；固定 gitignored 供件（夜景近中性）
  下无假阳风险，定级「措辞精度非缺陷」恰当。维持不改（可选改进 = 测试内
  补 unmanaged 断言，非义务）。
- **N-B（plan files_modified 漏列 RAWDecoderTests）**：定级恰当，DECISIONS
  偏差 4 已申报。
- 第一路 §二..§六各实测断言与本路独立结果**逐项无矛盾**；其 D-2 探针
  复跑（/tmp/v2m-acc-probe）本路未重复——本路以全套轮供件钉真跑 +
  证据包数字亲核替代，结论互证。

## 五、第二路独立发现（执行注记，均非缺陷、零再修）

- **E2-1（V2M-02 T2 派发精度）**：派发令须显式列四行 id（V2M-T1-02 /
  V2M-D3-01 / V2M-D4-01 / V2M-D5-01）+ D-4 返工触发 + 「omp computer-use
  通道」建议——plan 文本行集枚举为 m6-closeout 键，v2m 专属行靠
  SUMMARY §四 + 本文件承载。
- **E2-2（D-2 收紧质量代价显式化）**：闭环批 AGENTS「V2-Maintenance 架构
  增量」节登记 RAW 9 automatic 收紧语义时，建议补一句「X-Trans/Quad-Bayer
  机身的 v9 demosaic+denoise 质量面随收紧一并退场，重入口条件见
  TRANSCRIPT 重启条件节」。
- **E2-3（testRAW9OptIn 本机 skip 态）**：该法重钉断言当前由矩阵 +
  供件钉同事实覆盖；真 RAW 样张域备料（+11 skip 收敛）后自动归队，
  无需动作。
- **E2-4（solve 回填刷新无直接单测）**：seam 一帧兜底无用户可见面；
  后续如动 solve 路径可顺带补一法，非本批义务。

## 六、commit 清单（6 commits，diff 窗口逐一亲验）

| commit | 内容 | 文件 | 第二路判定 |
|---|---|---|---|
| `54124c7e` | T1 D-1 快照去热读 | 3 文件（Model/View/Tests） | 成立（§二面 1） |
| `5567b56c` | T2 D-2 automatic 收紧 | 3 文件（RAWDecoder/Tests×2） | 成立（§二面 2） |
| `83f48bbb` | T3 D-3 换图钉序 | 1 文件（EditorWorkspaceShellView） | 成立（§二面 3） |
| `e74be37b` | T4 D-4 sheet(item:) payload | 1 文件（SessionBrowserView） | 成立（§二面 4） |
| `8133726e` | T5 D-5 toast Int 化 | 1 文件（LightamerApp） | 成立（§三键目录亲查） |
| `bb16f8c4` | T6 收口文档 | 2 文件（SUMMARY/DECISIONS） | 与实测逐位一致 |

## 七、结论

**PASS / 0 error + 0 minor（双验收第二路，与第一路 PASS 一致）**。五缺陷
修法五面独立审计全部成立；全套 3851/35/0 本路独立复跑逐位闭合（三路同
值），ΔN₁=+3 精确且两新法 + 供件钉本路日志亲证真跑；skip +11 漂移逐族
差分确证环境先于本批；红线族独立重跑全零；四偏差合规；两批外疑点登记
质量合格且与修法正确性隔离亲证。**放行**：账面翻新交闭环批统一执行；
GUI 屏面四项证据 = V2M-02 T2 硬义务（E2-1 派发精度注记随行）；不 push
（按派发令）。
