# AR-02 SUMMARY — plan B(M2 39 面板 stored-params codemod)执行摘要

> 执行批 = audit-repair plan B(AR-02),2026-10-18,单 executor。
> 正本 = `AR-02-PLAN.md` + `AUDIT-REPAIR-CONTEXT.md`(D-M7-AR-5/6 +
> 2026-10-18 用户裁决补记:D-6 相对门 = 双构建差分 ≤1.9% 即 PASS)。
> 环境 = worktree `/tmp/la-ar-bc-wt`(branch `audit-repair-bc`,自
> `e9034d5e`),主树只读。

## 任务清单与 commits

| 任务 | commit | 内容 | 判定 |
|---|---|---|---|
| T1 codemod | `fbbdef31` | 40 文件 46 处:39 直读面板(44 处 computed)+ HighpassSoftenPanelView(2 处 helper)→ stored `private let params` + 同签名 custom init;binding 闭包捕获 stored;调用点零改 | PASS(机检闭环,DECISIONS D-AR2-1..4) |
| T2 探针 | `71e39a70` | PanelParamsDecodeProbeTests 两法(env 门默认 skip)+ Project.swift 恰 +1 行 + BUNDLE-MAP 恰 +1 行 + tuist generate 末位(L041) | PASS(PERF 行落档,DECISIONS D-AR2-5) |
| T3 验收 | 本 commit | 定向净轮 921/16/0 + PERF 探针轮 2/0/0 + D-6 探针相对门双构建四轮 + 文档收口 | PASS(DECISIONS D-AR2-6/7) |

## 机检终值

- codemod 后 grep:`private var params:` UI/Inspector/ **零命中**;
  `params\(of:` 域内 48 = 44 init + 2 init(HighpassSoften)+ 2
  provider(注释 + helper 本体)——≤ codemod 前 48,恒等闭合。
- 红线四文件零 diff:ModuleInstance / IOPPanelProvider(helper 签名 +
  AnyView 注册缝)/ LibraryProjectController(FIX2③)/ LightamerSlider
  (并行纪律锚);xcstrings 零 diff;封存面全域零 diff;UserDefaults
  零新键。
- 定向净轮:`--bundle App` **921/16/0**(326s,peakRSS 2832MB,8G 门内)。
- ΔN(pass)对账:**本批 +0**(探针两法默认 skip;plan 带 +0..1 的 +0
  臂)。skip 差分:**探针族 +2**(逐族申报——DECISIONS D-AR2-6)。
- 全套对账:基线 3963 → A 批兑现 3967 → B 批 +0 = **3967**(带
  3964..3972 内;C 批终账在 AR-03 SUMMARY)。

## D-6 探针相对门(用户裁决 2026-10-18 行使)

双构建(HEAD `71e39a70` vs 基线 `8e3bd59d`)同协议四轮:
空载 −1.6%/−0.1%(带内);编辑器归因轮 −0.75%(带内)+ 首轮 −4.55%
(改善方向散布,因果 = 本修砍除每 tick ~24×8µs 解码)。**判定 PASS**
——细节 = DECISIONS D-AR2-7。

## 偏差清单(逐项申报)

1. **HighpassSoftenPanelView +1 文件**(plan SC ε 臂)——helper 式双
   computed 同病同修,实改 40 文件(D-AR2-2)。
2. **YiyinPanelView 挂账**(plan 头注二选一行使)——sibling 读取经活
   会话 class 引用,零 stale 论据不覆盖;零代码动作(D-AR2-3)。
3. **首轮定向轮 1 fail 归因 = AI 供件缺失**(`Resources/AIModels/`
   194MB 不入 git,worktree 无;主树拷入后净轮全绿)——环境供件面,
   零测试/产线改动(D-AR2-6)。
4. **探针首轮(head)菜单 AX 组合错误** → AX 树亲列修正后重跑
   (head2 有效;head 的空载面采样保留为独立证据)——D-AR2-8。
5. 首轮探针揭示 `run-arm.sh` 的菜单点击组合(zh「文件」× verbatim
   「Open Recent Project」)已钉进 MANIFEST 配方(验收批复跑避坑)。
6. dead-proxy env(127.0.0.1:10809 daemon 未起)阻塞 SPM resolve →
   干净 env 起 xray daemon 后通过(SPM 拉 GitHub 依赖是 worktree 一次性
   面污染;后续 AR-03 批同 worktree 不再触发)。

## 面板走查(MANIFEST 配方,实机归验收批/用户)

ChannelMixerRGB 代表 + HighpassSoften(helper 式代表)拖动 60Hz +
readout 零漂移 + normalize discrete binding 行为零差——配方与判据 =
`.work/gui-acceptance/audit-repair-bc/MANIFEST.md`(local-only,
gitignore 面;执行批已产 D-6 机检证据 + 编辑器面截图在
`/tmp/ar02-d6-probe/`)。
