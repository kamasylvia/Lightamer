# M6-4-02 SUMMARY — AI 分割蒙版原生集成 spike（面 B 全量批）执行收口

> 执行 = 夜间全自动授权（先例 D-07-3-T5-1；`paused=false` / `auto=true`
> 开工确认）。plan 正本 = 同目录 `M6-4-02-PLAN.md`（修订版，HEAD `984e0256`
> 面）；裁决正本 = `M6-4-CONTEXT.md`（七 OQ 全 A）；偏差登记正本 =
> `M6-4-02-DECISIONS.md`（D-01..D-13）。**ACCEPTANCE 未写**（双重验收归
> 验收批：zcode subagent 独立验收 PASS 后串行 omp 二次验收，严禁并发）。
> **翻账零**（闭环批统一；D-12 编号申报）。
>
> **验收修复批增补（2026-10-15，N-1 实修）**：双重验收 PASS 后按
> ACCEPTANCE-2ND §5.2 升格建议实修 livePlane 切层/切图释放（D-13）——
> AIMaskPatchFlowTests +2 法（App bundle 预期 814→**816**），全英
> commit `fix(m6-4-02)`；全套预期中心随之 **3841→3843/24/0**。

## 任务序与 commit 链（每任务独立提交，全英文 Conventional Commits）

| 任务 | commit | 内容 | 定向轮 |
|---|---|---|---|
| T1 | `86a0b292` | AIPatchAssembly（Planner 三 skip 门 + Composer 接缝 ramp/≤4 FIFO/双分辨率吸收）+ 9 法（KD-1） | AIPatchAssemblyTests 9/0/0 + Layers 全量 483/4/0 |
| T2 | `87efa887` | segmentPatch 薄包装（零第二条装配）+ AIMaskFeather（sigma 映射 + logit-gain 负腿，D-01）+ 6 法 | AIMaskFeatherTests 6/0/0 + Layers 全量 489/4/0 |
| T3 | `444f4047` | personInstanceMasks 全脸（标签合成提取腿 E2 + `.person` 源族 + 菜单项/picker 复用 + xcstrings 5 键）+ 5 法 | PersonInstanceMaskTests 7→5 法收敛后 5/0/0 + Layers 494/4/0 + App 810/4/0 |
| T4 | `fbbcf449` | commit 缝羽化接线（双羽化钉死）+ livePlane 捕获 + 1s debounce + runPatchRefine + toolbar 羽化节 + 4 法 | AIMaskPatchFlowTests 4/0/0 + App 全量 814/4/0 |
| T5 | （无 commit——MANIFEST 为 gitignored 本地证据，D-10） | `.work/gui-acceptance/m6-4/MANIFEST.md`（Manual-Only 降级 + 现场记录） | — |
| T6 | `74a4709d` | KD-4 行 2 数值门（0.6× 过渡宽 + ≤1px 缝错位）落断言 + 红线机检电池（本文件） | Layers 全量 494/4/0 复跑 |
| T7 | （本文件 + DECISIONS） | 收口 | — |

## 定向轮终值（SC 分账对表）

- **Layers bundle（收口轮，全量）**：`494/4skip/0`，exit 0，零 MEMFAIL，
  peakRSS 1023MB（8G 门内），155s。
- **App bundle（收口轮，全量）**：`814/4skip/0`，exit 0，384s。
- **SC 分账**：LAYERS +20（三新文件 9+6+5，BUNDLE-MAP 三行与实测逐一相符）
  / APP +4（一新文件）= 计划 24 ∈ 带 21..25 ✓（D-08：KD-4 行 2 判据并入
  ⑤，方法计数不带新）。
- **验收修复批增补**（D-13，2026-10-15）：AIMaskPatchFlowTests +2 法
  （切图 livePlane 释放 + 切层旧 pass 不落地）→ **APP 814→816/4/0 预期**；
  单类轮 6/0/0 亲跑（含负验证：撤守卫恰两新法红）。
- **实际收口 TOTAL（闭环批 S8 对账基线申报值）**：
  **`TOTAL|3843/24/0|`（推算）= plan 01 实际收口 3817/24/0 + 本批 +24
  + 修复批 +2**，
  落预期带 **3840..3844** ✓。全套 `--all` 本 plan 未跑（批准制）——验收
  批准轮实跑时以 3843 为预期中心、3840..3844 为对账带。
- zh-audit `--check`：**PASS**（1682 source keys / 1923 catalog keys /
  zh complete / locale {en, zh}）——5 新键全数入册，MISSING = 0。

## 红线自检（基线 `984e0256..HEAD` 机检电池，T6 实测）

- **`.metal` 零 diff**（全仓 glob）：0 命中——正腿走既有 bake featherRadius
  GPU 缝、负收缩走 CPU logit gain，零新 kernel 传承兑现。
- **`generateScaledMask` 新增调用点**：0（新增 diff 恰 2 处 `+` 命中皆为
  E2 禁用注记的注释文字）——标签合成默认腿机检面 ✓。
- **scribble 缝零扰**：diff 零命中 ✓（OQ-6 兑现）。
- **封存/冻结面**：`LightamerSidecar.swift` / `RasterMaskStore.swift` /
  `MaskCombiner.swift` / MCP 快照族（PhotoProjection/McpServerController）/
  V50Order / NodeOwnershipCatalog 全零 diff ✓（checker 关注点 1 的正腿
  复用面整文件零 diff 兑现）。
- **Project.swift dependencies 块零 diff**（零新 SPM）✓。
- **UserDefaults 零新键** ✓；**runModal** 新增 0 ✓；**LocalizationValue
  插值键形态**新增 0 ✓。
- **xcstrings 5 键尾块纯插入**：diff `-` 行 0（除头）、`+` 86 行 ✓ +
  zh-audit PASS（上表）。
- **featherRadius 唯一非零源 grep 申报**：`AIMaskEditing.swift:197`
  （bakeRadius 穿线 = 正腿唯一）+ `MaskCombiner.swift:628`（parametric
  存量面，非 AI 路径）——四既有 commitRasterMask 调用点缺省 0 零漂移。
- **typed noSubject 纪律**：personInstanceMasks 零观察 / 空选中、
  runPatchRefine skip 门与 catch 臂全部 typed/原平面保全，零 all-ones
  兜底构造（新增路径扫描）✓。
- L041：三新测试文件随各自任务 commit 登记 Project.swift（LAYERS/APP
  数组显式清单）+ BUNDLE-MAP 四行 + `tuist generate` 每批末位；L070 零
  push；M2-7-3 parentage 口径（杀进程仅限本会话自跑测试宿主，一次 wedge
  清理，D-11）。

## §spike 结论落档（KD-4 五行判定表）

| # | 能力 | 判据 | 判定 | 证据 |
|---|---|---|---|---|
| 1 | 点击精修 | 07-3 已交付面回归绿（AIMask 既有套件零编辑全绿） | **达标** | Layers 494/4/0 + App 814/4/0；AIMask 既有六套件零编辑（diff 无既有测试文件改动） |
| 2 | hi-res patch | 0.6× 边缘宽 / ≤1px 缝 / ≤4 帽 / skip 门 + debounce 单调度 | **达标（机检轨全绿）** | `74a4709d` 双数值门 + T1 ②③④⑧ skip/帽门 + T4① debounce 合并；GUI 轨 = M-1（Manual-Only 待复验） |
| 3 | Edge 羽化 | golden 表 + 0 恒等双保险 + 单调性 + 负值收缩参照 + 正腿 GPU 缝穿线参数面 + 双羽化钉死 | **达标** | AIMaskFeatherTests 6 法 + AIMaskPatchFlowTests ②（wire 双写：正腿 == bake(σ)、负腿 == bake(CPU 面, 0)）；GUI 轨 = M-4 |
| 4 | 人物实例 | 请求组装 typed 面 + 标签合成提取 helper（合成 label-buffer fixture）+ GUI 真机轮 | **单测轨达标；GUI 轨待复验** | PersonInstanceMaskTests 5 法（四 fixture + 真模型 black 场 noSubject）+ M-2/M-3（Manual-Only） |
| 5 | Describe | 原生不可达收口 + V2 挂账入档 | **收口** | RESEARCH B2 swiftinterface 全文 grep 实测（零文本提示分割 API；`VNStatefulRequest` = macOS 11 视频跟踪基类无关）+ 本表 + REQUIREMENTS 注记（翻账批） |

**「达标即收」结案语**：原生零模型成本路的三件 native 组装（点击精修 =
既有面回归 + hi-res patch + Edge 羽化参数化）+ 人物实例入口全部落地，
机检判据全绿；唯一不可达件 Describe 按裁决⑦以「原生不可达」收口。spike
**达标**——SAM CoreML 大件不启动（V2 另裁）。

**V2 挂账清单**：①Describe 文本选择（SAM CoreML 大件：3.4GB Meta License
永不入仓 + ViT/DETR/CLIP 全族自转换；ModelAssetStore 安装链 +
AIWorkerProtocol 第四腿已备）②scribble 激活（typed 拒缝保持）③重载后
羽化编辑（平面已弃只有 PNG——重开需重生成或 logits 快照先例再评）
④livePlane 降档（quality-tier 分辨率驻留 + patch 后一次性上采样，若实测
驻留成痛点）⑤负腿 GPU 迁移（若 CPU 双趟越秒级痛点）。

## livePlane 内存姿态申报（M6 + 验收修复批 D-13 修订）

`SegmentSession.livePlane` = decode-frame 分辨率 float32 单通道平面，首次
`.segment` 生成成功起持至会话拆（释放点 = 模式退出 / armSegmentSession
替换 / 新 seed / 新生成覆写 / **切层·切图身份比对失配（D-13——schedule
stamp vs fire/下次 commit 缝的当下身份，失配即 releaseLivePatchState）**）。
accurate 档 100MP ≈ **400MB 量级会话期驻留**——与 AGENTS 资源监控 GUI
app >3G 触发线同域（巡检口径内）；**D-13 残差**：末次 pass 完成后切图且
无 pending debounce 时驻留至上述其余释放点（窄面，DECISIONS §D-13 申报）。
patch 列表另持 ≤4 份 ROI 平面（帽 4 上限界定量级；D-13 起随身份失配一并
清空）。瞬时峰值 = runPatchRefine 的 compose 中间面（每次 pass 一份，
pass 后释放）。V2 降档挂账见上。

## 挂账申报（DECISIONS 详目）

| # | 项 | 归宿 |
|---|---|---|
| D-01 | 羽化负腿公式换锚 logit gain（1−blur(1−x) 线性退化证伪 + LightCraft 原文） | DECISIONS §D-01 |
| D-02 | patch 调度缝 = commit 缝捕获（host 零触兑现） | §D-02 |
| D-03 | labelComposite 形参 = CVReadOnlyPixelBuffer（swiftinterface 事实） | §D-03 |
| D-04 | 32F/'L00f' 常量别名 → maskPlane 32F 臂不可达（存量） | §D-04 |
| D-05 | person 检测复用 AIInstanceCatalog（零新类型） | §D-05 |
| D-06 | black 场分类腿 fixture（灰/白幻觉探针）+ person 标签域实测待 GUI 轮 | §D-06 |
| D-07 | layer B ROI 分辨率未实测（组装面分辨率无关已钉） | §D-07 |
| D-08 | KD-4 行 2 数值判据并入 ⑤（SC 带机械闭合） | §D-08 |
| D-09 | 羽化 wire 契约（percent≠0 会话值权威）+ 非零调用点 grep 申报 | §D-09 |
| D-10 | T5 Manual-Only 降级 + MANIFEST gitignored（T5 commit 空转） | §D-10 |
| D-11 | 环境事件两笔（worker 测试一次性挂起 + 死代理 L080） | §D-11 |
| D-12 | 翻账推迟编号（闭环批统一） | §D-12 |
| D-13 | N-1 实修：livePlane 切层/切图身份比对释放（验收修复批，+2 法） | §D-13 |

## 翻账建议（闭环批统一做，本批零翻账）

AGENTS.md（M6-4 架构增量节面 B 段）/ ROADMAP（M6-4 行 ✅）/
REQUIREMENTS（M6INT-03 终态注记，含 Describe 收口）/ GOAL-STATE（续接点
→ phase 收口态 + 全套终验待办）/ TODO（M6-4 条目）。素材 = DECISIONS
全文 + 本文件 §spike 与「实际收口 TOTAL」节。

## 待复验项（VALIDATION 落签前置）

1. **全套 `--all` 终验**（orchestrator 批准轮）：预期中心 **3843/24/0**
   （修复批 +2 后），对账带 **3840..3844**；运行门 8G + MEMFAIL 机检 +
   运行中监视照册。
2. **GUI 轮 M-1..M-4**（`.work/gui-acceptance/m6-4/MANIFEST.md` 四行）：
   验收批（omp computer-use）或人工；layer B 资产引导下载为前置。
3. D-07/D-06 两实测申报随 M-1/M-2 补录。
4. **ACCEPTANCE 双重验收**（zcode subagent 独立验收 → 串行 omp 二次验收）
   未启动——本 SUMMARY/DECISIONS 为其输入。
