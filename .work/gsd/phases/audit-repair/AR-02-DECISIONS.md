# AR-02 DECISIONS — plan B(M2 39 面板 stored-params codemod)裁定记录

> 执行批 = plan B(AR-02),单 executor,worktree `/tmp/la-ar-bc-wt`
> (branch `audit-repair-bc`,自 HEAD `e9034d5e` 长出——主树只读纪律)。
> commits:`fbbdef31`(T1 codemod)+ `71e39a70`(T2 探针)。

## D-AR2-1 codemod 对账清单(机检闭环)

**codemod 前**(HEAD `e9034d5e`,grep 域 = `App/Sources/Lightamer/UI/Inspector/`):

- 直读式 `private var params: X.Params {`:**44 处 / 39 文件**——与 plan
  review F-4 勘误逐字吻合(GradeScalarPanels.swift 一文件 6 struct 各 1 处
  = 6 处;其余 38 文件各 1 处)。
- `params(of:` 域内全量 = **48 命中**,分账:44(直读 computed 体内)+
  2(HighpassSoftenPanelView helper 式 computed :23/:28)+
  2(IOPPanelProvider.swift :27 注释 + :196 helper 本体体内)。
  Plan 恒等式「44 + helper 1 + 其余 3 = 48」的实仓形:helper 本体**签名**
  `static func params<M>(of...)` 不匹配 `params\(of:` grep,匹配到的是
  本体体内 `try? instance.params(of: type)` 1 处 + :27 注释 1 处 +
  HighpassSoften 2 处——合计恒等闭合(48 = 48),口径差 = grep 形态注记,
  非面数出入。

**codemod 后**:

- `private var params:` 在 UI/Inspector/ **零命中** ✓。
- `params(of:` 域内 = **48 命中**,分账:44(init 各一次解码)+ 2
  (HighpassSoften init 内两行)+ 2(provider 注释 + helper 本体体内,
  零 diff)= ≤ codemod 前 48 ✓。
- ModuleInstance.swift / IOPPanelProvider.swift / LibraryProjectController.swift
  / LightamerSlider.swift **四文件零 diff** ✓;`panel(for:) -> AnyView`
  注册缝零 diff ✓;xcstrings 零 diff ✓;封存面全域零 diff ✓;
  `git diff --stat` = **恰 40 文件**(+271/−124)。

## D-AR2-2 HighpassSoftenPanelView 并入(+1 文件,plan ε 申报)

plan SC「`git diff --stat` 恰 39±ε 文件(ε = helper 式清单出入)」的 ε
行使:HighpassSoftenPanelView.swift = 双 helper 式 computed
(`highpassParams`/`softenParams`,同 helper 同 ModuleInstance 解码底座)
→ 同款 stored 化(两个 `private let` + 同签名 custom init)。
39 直读清单(rg `private var params`)不含它(它的 computed 挂
helper 式),同病同修,+1 文件并入——**实改 40 文件 46 处**
(44 直读 + 2 helper)。

## D-AR2-3 YiyinPanelView 挂账(裁定 = plan 头注二选一的「挂账注明」臂)

`YiyinPanelView.swift` 的 `params`/`bordersParams`(:59-60/:65)表面同病,
但深读后**不满足零 stale 论据前提**:

- 39 面板的论据:`instance` 是面板 View 的 `let` 值捕获——computed 与
  Binding 闭包读的是**同一份字节**,stored 化纯语义等价。
- Yiyin 形:`watermarkInstance`/`bordersInstance` computed 经
  `edit.siblingInstance(opName:)`(`InspectorEditSession`,class 引用,
  weak coordinator)读**活会话的当前 sibling 记录**——sibling 的
  params 字节可在面板存活期间变化(编辑另一段时),不保证经「父链重估
  → 面板重建」刷新。stored 化会把 sibling 记读成 init 时刻快照 =
  **行为面 stale 风险,非语义等价**。
- 裁定:挂账(plan 头注明示二选一;「+1 并入」臂要求同语义等价前提,
  不成立)。复活条件 = sibling 读取的失效链改造立项(越本 plan
  「纯机械批」scope——发现行为面需顺手改即停手的红线在此行使)。
  本 plan 对 Yiyin 面零代码动作。

## D-AR2-4 语义等价论据正式登记(checker 关注点 2)

- `instance` = 各面板 View 的 `let` 值捕获(ChannelMixerRGBPanelView
  样板 :23);记录变更恒经 `edit.update` → 父链重估 → 面板以新
  instance 重建 → init 重解码(plan 头注论据,执行批源码级复核成立)。
- Binding 闭包捕获 stored 值:Swift 值捕获语义下闭包读 init 时刻字节;
  改造前闭包读 computed(每次解码**同一份** instance 字节)——逐位等价。
  discreteBinding 样板面(ChannelMixerRGBPanelView)改造后 diff 面核:
  闭包体零改动(仍写 `params[keyPath: keyPath]`,只是 `params` 由
  computed 变 stored let)。
- provider 调用点(memberwise `View(instance:edit:)`)与 custom init
  同签名零改——40 文件调用点 diff 全零(grep 亲核)。

## D-AR2-5 T2 探针裁定与 PERF 基线(留档)

- 裁定:做探针(plan 内裁量,+0..1 带的 +1 臂)。M2-5 惯例形:
  `LIGHTAMER_PERF_PROBE=1` + `XCTSkipUnless`,两法默认 skip。
- PERF 轮实测(env=1,`--bundle App 'PanelParamsDecodeProbeTests'`,
  2/0/0,3s):

  | Params 族 | iters | median µs | min µs | p95 µs |
  |---|---|---|---|---|
  | ChannelMixerRGB.Params | 2000 | **7.99** | 6.91 | 8.94 |
  | Exposure.Params | 2000 | **2.03** | 0.95 | 2.98 |
  | FilmicRGB.Params | 2000 | **6.08** | 4.89 | 7.03 |

- 读法:ChannelMixerRGB 面板改前单 body tick ≈ 24+ 次解码 ≈ ~192µs
  纯解码开销(7.99 × 24);改后 = init 一次 7.99µs——**每 tick
  ~184µs 解码浪费消灭**,与 RESEARCH §5「N→1 机械可证」一致。文档面
  非门,不设预算断言。

## D-AR2-6 ΔN 记账与 skip 差分申报

- 定向净轮(--bundle App,补供件后):**921/16/0**,326s,peakRSS 2832MB。
- 对账:M7-6 基线 App bundle 子集 917 法 → AR-01 兑现 +2(全批 3963→3967)
  → 本批探针 +2 法(默认全 skip)= 921 法。**skip 差分逐族申报**:
  基线 skip 35(全套口径)→ 本批探针族 +2(PanelParamsDecodeProbeTests
  两法,默认环境 skip)——全套终值口径 skip = 35 + 2 = 37(A 批
  零新 skip;C 批预期零新 skip——收尾净轮终账闭合)。
- **ΔN 对账(executed 口径,终账修订)**:探针**两法** = executed
  **+2**——plan 预算表「+0..1(PERF 腿 1,skip 腿不计)」与 action 1
  「两法(skip 腿 = 环境门断言本身即测试法)」存在内在张力:skip 腿
  落地为独立测试法即计入 executed。执行按「两法」字面 → **本批
  executed ΔN = +2,越本 plan 预算带上界(+1)+1,显式申报**(全批终值
  带 3964..3972 仍闭合——3963 + A 4 + B 2 + C 0 = 3969)。默认环境
  下两法 skip(不产 pass;PERF 轮 env=1 下 2/0/0)。
- 环境供件申报:首轮定向轮 **921/18/1**(LCRSettingsTests
  testRefreshBuildsSixRowsWithFailClosedReleaseFaces fail:
  `("download") is not equal to ("builtIn")`)——归因 = **AI 模型供件
  缺失**:`Resources/AIModels/`(194MB)不入 git(untracked 本机生成物,
  build_default_bundle.sh 产物),worktree checkout 无此目录 → 测试
  host bundle 的 bundled-profile 探测落 `.download` 缺省 face。主树拷入
  194MB 供件后**重建 + 重跑 = 921/16/0 全绿**——环境供件面,非产线
  缺陷,零测试改动(同「RAW 供件漂移」类 skip/fail 漂移先例,plan T3
  归因窗口条款行使)。

## D-AR2-7 D-6 探针相对门复测记录(用户裁决 2026-10-18 相对门行使)

协议 = AR-01 D-AR1-10 钉死形(真实 UI 驱动 + 30s 窗 6 采样中位 +
sample 栈旁证);判定 = **同协议双构建差分 ≤1.9% 噪声带即 PASS**
(D-AR1-10 门值修订,用户已裁)。HEAD 臂 = 本批 `71e39a70` 构建
(DerivedData 容器 `Lightamer-dkzhl...`);基线臂 = `8e3bd59d`
(A 批验收态,plan 指定基线锚)。

| 面 | 基线 `8e3bd59d` | 本批 `71e39a70` | Δ |
|---|---|---|---|
| 空载无项目面(60s settle,30s 窗中位) | **32.25%**(r1) | **30.65%**(head2 轮;head 轮独立复测 32.15%) | −1.6% / −0.1%(双证据带内) |
| 编辑器静置 r1(6 图项目重开 → ⌘E → 60s settle,30s 窗中位) | **91.2%** | **86.65%** | −4.55%(方向 = 改善,归因轮复核) |
| 编辑器静置 r2(独立归因轮) | **89.4%** | **88.65%** | **−0.75%(带内)** |

- HEAD 臂三份证据:head 轮空载 32.15%(首轮)+ head2 轮空载 30.65% +
  head2 轮编辑器 86.65%——空载面双轮独立复测(30.65/32.15,域内散布
  ~1.5%)与 AR-01 基线树空载 31.4/31.9 同域;编辑器 86.65% 与 AR-01
  60s settle 形「195→90 衰减」尾态同域。
- drive 记录 = `/tmp/ar02-d6-probe/`(samples-head/head2.txt +
  drive-head2.txt + sample-stack-head2.txt + 截图,即弃域)。
- 栈旁证(sample-stack-head2.txt):主线程 SwiftUICore
  ViewGraphRootValueUpdater.updateGraph 帧族主导——与 AR-01/FIX2 侦查的
  layout-churn 既有域一致,零 Lightamer 业务帧挂环。
- 判定:**PASS**(相对门兑现)——①空载面双证据带内(−1.6% / −0.1%);
  ②编辑器面归因轮(双臂各第二轮)−0.75% 带内;③首轮 −4.55% 超带但方向为
  **降**(改善方向:静置 churn 的每次 body 重估省 ~24 次 × 8µs 解码——与本
  修的机械因果一致,非随机噪声亦非回归);④双臂四轮零一轮显示 HEAD > 基线
  超带。相对门保护对象 = 树形改动引入 churn 恶化——零证据。

## D-AR2-8 环境与编排注记(非缺陷面)

- shell 继承 dead-proxy env(`127.0.0.1:10809`,daemon 未起)→
  tuist generate 的 SPM resolve 失败;干净 env 起 xray daemon 后 resolve
  通过(GitHub 可达)。任务尾部 `px --stop` 归位。
- DerivedData 双容器(worktree 路径 → 独立 hash 容器,主树容器零触碰)
  ——`test-direct.sh` 的 mtime-glob 定位在「构建后立即跑轮」时序下
  恒取 worktree 容器(本批三轮亲核,日志路径佐证)。
- 全程无 `--all` 轮(批准制未行使),锁 `/tmp/la-audit-repair-all.lock`
  空闲未占用;无并行残窗(A 批已闭环)。
- C 路并入条款复核(开工前):C 路合并 MANIFEST 仍未落盘
  (`find .work -iname "*manifest*"` + LANEC/lane-c 键 grep 零命中)——
  静态基线形态执行,条款保持活线(同 AR-01 D-AR1-1 结论)。
- 首轮探针(head 轮)菜单点击 AX 组合错误(菜单 bar item zh「文件」×
  子菜单 verbatim「Open Recent Project」组合未猜中)→ 轮次作废,
  AX 树亲列后修正组合重跑(head2 轮有效)——head 轮的空载面采样
  独立有效保留为证据。
