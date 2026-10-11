---
phase: M5-1
slug: track-color-transfer
status: validated
nyquist_compliant: true
created: 2026-10-13
validated: 2026-10-13
---

# Phase M5-1 — Validation（TRACK 追色族：统计 + 三档求解 + colormatch op + 面板 + MCP `match_color`）

> 体例对齐 `phases/m2-11-performance/M2-11-VALIDATION.md`（M4-1 同款）。**双重验收
> （config `dual_acceptance`）三波双路全 PASS 后成文**：01/02/03 各持 zcode 独立
> 验收 + omp 串行二次验收（`M5-1-01/02/03-ACCEPTANCE.md` +
> `M5-1-01/02/03-ACCEPTANCE-OMP.md`；02 波 = 双重验收制度第二例
> **FAIL→fix→复验闭环**，omp 复验 PASS 节随 OMP 报告在案）。
> **翻账只认证据**：SC 三列对账正本 = `M5-1-GATE-LEDGER.md`（五门收口台账）+
> 三波双路 ACCEPTANCE + REQUIREMENTS V2 TRACK 节交付注记（T4 批已带门锚与
> TRACK-03 偏差注记，终态 Delivered 由本 VALIDATION 盖验）；charter 验收形态
> 五件 = OQ 清零 ✓（OQ-M5-1-1..8 全按推荐 2026-10-11 用户回批，CONTEXT 裁决
> 记录）+ golden parity 门 ✓ + 确定性门 ✓ + GUI 走查 ✓（行 1-4 实机走通 +
> Manual-Only 行显式移交）+ MCP 端到端 parity ✓（G4 byte-identical）。
> **SC 数字对账基线 = 全套 `--all` 终验 `TOTAL|3477/21/0|` 亲证值**
> （2026-10-12 收口批准轮，GATE-LEDGER §6；**分割重跑拼表**——首轮 Library
> bundle 宿主 SIGSEGV〔混态产物，L075 扩展〕中止 → 四 scheme 重建后分割重跑，
> 七 bundle 双保险全过零 MEMFAIL；omp-03 minor-1 表头措辞分歧如实登记）。
> 对账链 **3335 + 32 + 38 + 47 + 1 + 24 = 3477 逐位闭合**（App = 725 + 24 =
> 749）。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest（unit / golden / parity / 直启宿主 / GUI 实测轨 / MCP stdio e2e） |
| **Quick run** | `Scripts/test-direct.sh`（`--bundle`/`--all`；MEMFAIL / ru_maxrss 机检兜底） |
| **Full suite（phase 终轮）** | `caffeinate -dis Scripts/test-direct.sh --all` = **3477 tests / 21 skip / 0 fail**（2026-10-12 收口批准轮；分割重跑拼表——首轮 Library 混态产物 SIGSEGV〔.ips 实证保全 `evidence/m5-1-03-acceptance/ips-0-*`〕→ 四 scheme `build-for-testing` 重建 → IOP/IOPParity/Layers 三 bundle 取本轮有效值；七 bundle 逐行 = IOP 563/1/0〔7806MB〕/ IOPParity 444/3/0〔**8107MB**，8G 门余量 ~1%，贴线轮间漂移族零 MEMFAIL〕/ Layers 466/4/0 / Library 626/4/0 / Sessions 279/4/0 / Export 350/1/0 / App 749/4/0；L055 双保险全过） |
| **基线演变** | 3335（M4-2 末基线）→ +32（M4-3 批）= 3367 → +38（M5-1-01 P1：Oklab 7 / Stats 10 / SolverGolden 10 / Module 7 / KernelParity 2 / Identity 2 + V50OrderTests +1）→ +47（M5-1-02 P2：CDFSolver 8 / Pooling 6 / BakeGolden 6+probe / CubeAsset 8 / Module +5 / Identity +1 / Service 7 / Panel 6）→ +1（E-omp1 修复批 add-row gate 法）→ +24（M5-1-03 P3：ToolsetTests 21 + ParityTests 3）= **3477 精确**（GATE-LEDGER §6.1 两式互证） |
| **skip 16→21 身份表** | zcode-03 逐个验身份 = **12 env 探针/基准**（显式 env 门，M2-5 惯例默认 skip）+ **6 模型/资产包缺席**（entitlement/下载面）+ **3 fixture 缺席**（合成面扛门/无断言物）——零静默跳过；批内新增可考 = testBakeTimeBudget（M5-1-02 PERF_PROBE 门）；M4-3 估 16 = 估算非实测锚（GATE-LEDGER §6 注记诚实改口径） |
| **GUI 证据** | `.work/gui-acceptance/m5-1/` MANIFEST（证据域不入 git，L073）：九行配方 + E-omp1 修复批 m5fix-* 九件（实机全链路：添加→面板四件→参考 1.00→追色恰一 item→强度拖拽动像素 L1 20.3M→⌘Z 一次回 0→sidecar colormatch 持久化）+ omp-02 二验 41 张（E-omp1 发现轮）+ omp-02 复验 20 张（行 1-4 走通 + solveHash 14288275262918843225 与 m5fix-08 逐位互证）+ omp-03 75 张（含 headless stdio JSON-RPC 三连：tools/list 20 工具 + 五参 schema + typed 错误四连） |
| **zh 对账** | 01 批 xcstrings 零改动（1617/1855）→ 02 批 +20 键尾块纯插入（1637/1875）→ E-omp1 修复批 +1 `editor_stack_add_module`（1637/1876）→ 03 批 +1 `mcp_tool_desc_match_color`（1638/1877）——zh-audit `--check` 四轮全 PASS，删改行全程 0 |
| **在 flake/环境事件** | 首轮 `--all` Library SIGSEGV = 混态产物（tuist generate 后旧 xctest 配新框架，L075 扩展：generate 后全部 scheme 须重建）——非产线缺陷；App bundle 全量轮当晚被 §7 film-leg 竞态概率性阻断（zcode-03 三试未达全绿，**已由 `7bc6365` fix(film-leg) 结构性根除**）；M4-1 挂账 #6 孤儿 `.lra` 本 phase 期间第五度预防/第三、四度发作——**已由同批收口**（写腿 tmp 域 + 双前清 + 读方前清，`FILM-LEG-FIX.md` §4） |

## TRACK-01..05 + MCP-09 对照表（三列对账；正本 = REQUIREMENTS V2 TRACK 节 + GATE-LEDGER）

| SC | 判据 | 终态 |
|---|---|---|
| **TRACK-01** | 追色统计算法（参考图特征提取 + 变换求解，输出 3D LUT 或等效参数组） | **Delivered**：三档全交付（OQ-1 裁决「择型交付」）——S1 Gaussian OT 闭式三明治〔Float64 约束 M·Σs·Mᵀ=Σt 实测 1.08e-12，门 1e-10；numpy 双路独立复算 9.05e-15/4.86e-15 同带〕+ S2 per-channel CDF 256 梯〔整数交叉相乘分位对齐，Fraction 双路复算零失配〕+ S3 Reinhard 对角〔= S1 关协方差特例，对角归约 7.1e-15〕；统计域 Oklab（M1C/M1C⁻¹ 常数独立推导 6.8e-12/2.1e-11 吻合）；65³ `.cube` 派生 LUT〔体素门 vs 理想连续模型 7.6e-8，全晶格独立复算 5.96e-8 同带〕；锚 = `ColorMatchSolverGoldenTests` / `ColorMatchCDFSolverTests` / `ColorMatchBakeGoldenTests` |
| **TRACK-02** | 多参考统计聚合，权重可调 | **Delivered**：统计级加权矩池化（OQ-5 裁决）——二阶矩混合公式 Fraction 精确复算全六槽命中 + statsHash 升序序规范化（6 排列逐字节同池化）+ 直方图取整回整数秩（2.5→3/22.5→23 钉测）+ N=1 verbatim 恒等 + support 逐分量并集 + 权重比不变；GUI 参考列表权重滑杆；锚 = `ColorMatchPoolingTests` |
| **TRACK-03** | 非破坏落位（`colormatch` iop + sidecar 持久化 + cache 语义） | **Delivered**：独立 op 36.5（V50Order add-only 106→107，lut3d 36.0 与 dt verbatim colortransfer 37.0 之间）+ Params 直存 + `.cube` 派生资产（**裁决偏差注记**：原文「内嵌 LUT」→ 生效值 = `.cube` 派生资产，OQ-3 用户回批；params 存 `{assetRef, assetHash}` 引用 + paramsData <8KB 上界专测钉死 LUT 字节不进 sidecar）+ tetrahedral 插值经共享 `lut3d_tetrahedral` 函数（Lut3dKernels.metal 零 diff 硬门）+ solve-twice 幂等零新 history item + 全链真解位精确（persisted asset == in-memory bake 全表位型）；锚 = `ColorMatchServiceTests:testSolveTwiceLandsByteIdenticalParams/testAttachLandsOneHistoryItemWithParams` |
| **TRACK-04** | 交互（参考选择 → 自动求解预览 + 强度 + before/after） | **Delivered**：ColorMatch 面板（solver picker 三段 + 参考列表权重滑杆 + strength 拖拽 + readout 统计哈希/支撑域）+ LUT 页 add 行（E-omp1 修复 `3ae3daf`——鸡生蛋闭环根除：base scope gate + templateInstance→addModuleToBaseChain 与 Solve 同缝）+ D-H1 拖拽三件套（单测恰一 commit 绿；GUI 面 undo 粒度 obs 见挂账）+ 实机走查行 1-4 双路走通（solveHash 跨会话逐位互证）；Manual-Only 行（自然样张目测/before-after 目测）显式移交 M5-4 |
| **TRACK-05** | 质量门（golden parity + 裁剪策略明确 + 确定性） | **Delivered**：五门全绿（OQ-8 裁决；正本 = `M5-1-GATE-LEDGER.md`，15+3 锚全部 grep 实证在位）——详见下节；裁剪策略 = 1%/99% 整数秩截尾支撑域 + 线性延拓平台面（OQ-4）+ 矩阵臂全定义域 |
| **MCP-09 研究项 C** | `match_color` 编排工具位 | **Delivered**（M5-1-03）：最小面五参（OQ-6 裁决字面）——reference（库内 id/路径双形态）+ targets 批量 fan-out 逐目标独立求解（帽 30，GPU 前置 fail-fast）+ strength 0...1 + solver kebab 三档 + attach 自动落位/参数组双态；solveHash 确定性披露（双调用同哈希钉死）；事后微调/验收/元数据走既有 apply_params/render_preview/list_iops 零新增面（机检：`"match_` 工具名仅 MatchColorToolset 一文件）；快照族 19→20（frozen verbatim descriptor + schema 三方字节比对一致 + destructive 集 8→9）；两段流机制发现（seed ABSENT 密封下 apply_params 无法 CREATE——attach=true 建实例后回灌，doc 已写明非缺陷）；锚 = `McpMatchColorToolsetTests` 21/0/0 + `McpMatchColorParityTests` 3/0/0 |

## 五门台账（TRACK-05 验收正本 = `M5-1-GATE-LEDGER.md`，此处终态索引）

| 门 | 判据 | 终态（实测带/锚） |
|---|---|---|
| **G1 求解确定性** | 同输入统计 → bit-identical | ✅ 双跑位型 + 退化回落确定（秩亏 S3 回落 + 零迹恒等+offset 双臂）+ 缓存透明 LRU + 键折叠序字面钉死〔`gaussianOT(0,0)=2495982924697081349` / `reinhard(0,0)=3458577883779271296` / `cdf(0,0)=3429970360978670064`——zcode/omp 双路独立 FNV 复算逐位命中〕+ 池化 6 排列同字节 + bake 双跑位型 + solve-twice 全链含持久资产逐字节 |
| **G2 kernel parity** | GPU vs Float64 CPU 参考 | ✅ **双面门**（非降级交付）：良态子集（全 \|lms\|>1e-3）scale-aware p99.9 ≤1e-5〔实测 ~1e-5 带，abs 3.4e-5 @ 输出>10 ≈ 3e-6 相对〕+ 全网格 abs p99.9 **2.95e-3** / max **3.68e-2**（门 4e-3/5e-2，实测钉）——**机制注记**：Oklab cbrt 在 LMS≈0 交越导数无界，1e-5 单一目标在交越像素数学不可达（f64 同点同敏感）；挂账面见下 |
| **G3 语义 golden** | 合成参考对恢复已知变换 | ✅ commuting 族矩精确 ~1e-7（≤1e-3；构造约束正本 P1 DECISIONS §4：OT 只恢复 OT 映射）+ 采样臂 1.73e-2（≤0.06，trim shuffle 机制带）+ S3 对角恢复；**自然样张目测 = Manual-Only 行挂 M5-4**（台账未代跑，诚实） |
| **G4 MCP 端到端 parity** | match_color→apply_params→render_preview vs 本地 | ✅ **byte-identical**（SC#3 同型零容差带未放宽）——strength 0.7 真实微调闭环 + 批量双目标 ×2 + 双调用同 solveHash；3/0/0 双路亲跑（zcode 独立重建 8 scheme 后亲跑 + omp App 定向轮亲跑） |
| **G5 恒等回归** | 缺席/禁用/strength=0 逐字节直通 | ✅ 缺席（seed ABSENT 双面结构断言）+ 禁用（commit 面零 uniform）+ strength=0/unsolved（routed-blit byte-exact，L031）+ LUT 臂恒等态（assetRef nil/资产 degrade 双态 byte-exact）+ 反空转（solved strength-1 实动像素） |

## 双重验收记录（三波双路 + 分歧点全录）

| 波 | zcode 首验 | omp 二验 | 分歧与消解 |
|---|---|---|---|
| **01** | **PASS / 0 error + 3 minor（全已修 `d134ad4`）**——S1 数学审计 numpy 独立路全 PASS + Oklab 常数独立推导吻合 + App 首轮 1 fail 因果闭环（挂账 #6，删孤儿净树 711/4/0） | **PASS / 0 error + 0 minor** | **零分歧**（本 phase 唯一双路零分歧波）；omp 首版脚本自摆乌龙（③ 期望误写方差比得 3.088）即时发现修正——与执行批 T4「S3 漏开方」同类错误同构，佐证修复必要性 |
| **02** | **PASS / 0 error + 3 minor（m-a 已修 `cbd1afa`，m-b/m-c 账面注记）**——S2 数学审计（Fraction 精确路 + 20 万组随机对）全 PASS + LUT 臂三臂状态机/E5/E6/.cube 审计 PASS | **FAIL / 1 error + 2 minor** → **修复批 `3ae3daf` → omp 复验 PASS** | **分歧成立且消解**：E-omp1 = gate-false 默认编辑器面 colormatch **不可达**（鸡生蛋闭环：无实例不渲染行 → 实例需 add 菜单或 Solve → Solve 需面板 → 面板需实例；legacy 菜单结构不可达）——首验自动化面全覆盖但未做 computer-use 故漏检，omp 实机 MANIFEST 行 1 即阻塞 + sidecar 双实证；min_votes 按程序 FAIL 优先 → 修复（LUT 页 add 行，base-scope-only gate，四路同一 attach 缝）→ 复验实机全链路走通 + App 725/4/0 全绿。m-omp2 = 首验「uniform 96B」算术错（3+6+9+9=27 标量×4 = **108B**）账面勘误，字段镜像结论不受扰；m-omp1 = MANIFEST 配方-产品面不符（随修复批重写关闭） |
| **03** | **PASS（本批范围全部 AC 亲证）**——独立重建 + 六 bundle 全套轮逐位命中 + 批内定向七轮全绿（含 G4）+ skip 21 身份表 + 五门台账 15 锚逐位对上 + §7 附带登记 P1 潜伏缺陷（film-leg 竞态，非本批引入，零 diff 铁证） | **PASS / 0 error + 2 minor**——App 定向 749/4/0 亲跑全绿 + 实机 stdio 三连 + G4 源码全文亲读 + §6.1 **独立复现 film-leg 同签名 crash 反向佐证** + §6.2 Tooltip SIGBUS（L057-B 族新实例） | **无 error 级分歧**（五参/fan-out/attach 双态/render gate/快照 all20/G4 byte-identical/红线零 diff 逐项互证一致）。minor-1 = GATE-LEDGER §6 表头「全套终验」措辞易误读为单命令一次通过（实际分割重跑拼表，正文诚实披露在案——本 VALIDATION 已按实情呈现）；minor-2 = App 4 skip 身份采信首验未逐条重枚举（覆盖度差异诚实标定，非产物分歧） |

**omp 计数/字面勘误登记**（沿 M4-1 VALIDATION omp-minor-1 字面登记体例）：①02 波
m-omp2 uniform 96B→108B（ omp 路算术更正在案，首验账面勘误）；②03 波 minor-1
GATE-LEDGER 表头措辞（本件已按「分割重跑拼表」口径呈现）；③01 波零勘误。
**三波 omp 面 minor/obs 对产物正确性零否决——六路结论收敛 = phase 可签核。**

## Per-Plan Map（M5-1-01..03 + fix(film-leg)）

| Plan | 交付 | 终态 commits | 验收 |
|---|---|---|---|
| M5-1-01 P1 | Oklab 统计域 + S1/S3 求解器 + 求解缓存 + colormatch op 核心（36.5 落位 / seed ABSENT / 显式 null）+ linear kernel + G1/G2/G3/G5 四门落位 | 8 commits `47a27be..b83db8f` + 验收批 `d134ad4` | zcode PASS + omp PASS |
| M5-1-02 P2 | S2 CDF 求解器 + 多参考加权池化 + 65³ bake + `.cube` 派生资产 + LUT 臂（共享 tetrahedral / 三臂状态机 / E5 armed tap）+ ColorMatchService（E6 headless 提取 / attach 投影缝）+ 面板 + G1 全链补腿 | 7 commits `14d032d..4cc1c52` + T9 `abc46c0` + 补 `9c61c48` + 验收 `cbd1afa` + **fix `3ae3daf`（E-omp1）** + 账面 `3be69ee` | zcode PASS + omp FAIL→fix→复验 PASS |
| M5-1-03 P3 | `match_color` MCP 最小面 + 快照族 19→20 + G4 byte-identical + GATE-LEDGER 五门收口 + 全套终验 | 4 commits `e13d750..2002779` | zcode PASS + omp PASS |
| fix(film-leg) | M3-3 Film leg 竞态结构性根除（静态槽删除 → 显式传参；A/B 压力探针 decisive）+ **M4-1 挂账 #6 收口** | `7bc6365`（批外修复批，正本 = `FILM-LEG-FIX.md`） | 复现载体 FilmPanelTests 3/3 崩→×3 全绿 + 域回归三轮 |

零红线域终态（phase 全窗 `git diff dcd02a8..2002779` 六路验收机检互证）：V50Order
add-only（36.5 单行 + 注记，107 法断言绿）；零新 SPM（Project.swift diff 仅测试
编列）；`.metal` 新增面 = `ColorMatchKernels.metal` 一文件一 kernel（P2/P3 批零
diff）；Lut3d 密封面 / Film 域 / Sidecar schema / History / PipeCacheKey /
PipelineDocument / NodeGraphCommand 全程零 diff；`runModal` 0 命中；
`String.LocalizationValue("prefix_…")` 禁形 0 命中；LumaRescue 文本零搬（工具
doc 全自写）；darktable colortransfer/colormapping GPL 只读零复制。film-leg
修复批触 Core 三文件 = 批外 P1 缺陷修复（显式申报，非 M5-1 三 plan 窗产物）。

## 挂账总汇编（单一移交清单）

- **批内收口确认（翻账性质）**：
  - **M4-1 挂账 #6 修复批已收口**——`7bc6365` fix(film-leg) 顺手收口：写方
    tmp 域拷贝（`Tests/Fixtures/` 永不再生成 `.lra`）+ 双前清 + 读方入口前清；
    孤儿清查零命中 + Export 全量轮后复扫零命中——五波发作史（M4-1 起）终 closed
    （正本 = `FILM-LEG-FIX.md` §4）。**M3-3 Film leg P1 竞态同批结构性根除**
    （静态槽 → box 实例携带；A/B decisive；阻断全 App bundle 轮的面解除）。
- **移交 M5-4 VALIDATION（人工/后续轮）**：
  - **Manual-Only 目测行**：G3 自然样张目测（MANIFEST 九行 human rows）+
    before-after 目测 + bake 生产耗时实测（Release 产物 WebP 嵌入怪癖未追，
    M5-1-02 §3 遗留）——本自动化批不代跑，正本 = `.work/gui-acceptance/m5-1/MANIFEST.md`。
  - **修复后全套 `--all` 全绿轮**（film-leg 修复 + #6 收口后 3477 对账亲证闭环）
    = 后续轮（修复批按派发令未跑全套；本 VALIDATION 基线 = 收口批准轮拼表）。
- **V2 / 观察项（带锚，需求/风险驱动）**：
  - **G2 双面门交越界**：全网格交越界 2.95e-3/3.68e-2 实测钉门——cbrt LMS≈0
    交越导数无界为 Oklab f32 固有数学面（非缺陷非降级）；渲染观感 = 交越像素
    亚毫级偏差（GUI 走查观察项挂 Manual-Only）；若未来换统计域/精度路线须重验。
  - **o-2（om-2）收紧候选**：`ColormatchResolverBox.shared` =
    `nonisolated(unsafe)` 裸静态（写一次性/低频，风险低）——V2 若有多会话热
    切换收紧为 NSLock holder（`LutLibraryStore.shared` 体例）。
  - **omp-03 §3.1 面板追色点击无响应观察项**（P2 面回归嫌疑：omp-03 走查轮
    强度/readout 视觉缺失 + 双 slider 同位重叠；MCP 求解链自动化 24 法覆盖
    不受扰，本批 diff 零触 ColorMatchPanel）——建议 GUI 专项排查，复现配方 =
    omp-03 报告 §3；**omp-02 复验同面走通**（m5fix 链 + solveHash 互证）=
    概率性/环境敏感，不阻塞签核。
  - **omp-03 §6.2 Tooltip SIGBUS crash**（L057-B 族新实例——hover tooltip
    主线程栈边界）→ 并入 L057-B 专项，不另立项。
  - **omp-02 复验 obs**：o-ompre1 filmstrip 行点击不换图（探针多图会话末图
    锁定，M2-2 面）/ o-ompre3 菜单撤销一次回退两级（D-H1 GUI 面 undo 粒度待
    确认——单测恰一 commit 已绿，E-omp1 已关闭不阻塞）；omp-02 首验 obs：
    o-omp1 Mask 页层行点击内容区空白（M2-7 面）。
  - **MCP 多参考 V1 缺口**（单 reference/调用——多参考走 GUI 面板，v1 裁决
    字面）+ **preset 化**（OQ-6 备选 A——求解结果存 LUT 库条目，需求驱动挂 V2）。
  - **lut3d LUT 页无实例 add 行同族缺口**（E-omp1 修复面仅 colormatch；
    lut3d = 既有产品形状，挂账不改）。
  - **McpServerController 头注「frozen 19-tool set」陈旧**（files_modified
    纪律保留；后续 plan 顺手面）。

## nyquist 覆盖判断

- **判定：`nyquist_compliant: true`**。TRACK-01..05 + MCP-09 每条 Delivered 均
  ≥1 机器锚（五门 18 锚 grep 全部命中实文件 + 分域专测）+ ≥1 数字/实证背书
  （终验 3477 亲跑对账链闭合 + 实测带三路独立复算同带 + 双路 solveHash 逐位
  互证 + G4 byte-identical）。
- 采样密度：三波 +38/+47+1/+24 法全部 AC 逐条机检；六路验收（3 zcode + 3 omp）
  独立亲跑对表 + 独立数学复算（numpy / Fraction / Float32 逐运算仿真，零共享
  脚本）+ skip 21 逐个验身份 + GUI 实机走查三轮（omp-02 发现轮 / 修复复验轮 /
  omp-03 轮）；「无证据 ✅」零项——Manual-Only 行显式登记移交非静默豁免。
- 补偿面：03 波 zcode 全套轮 App bundle 未达全绿 = §7 film-leg 阻断（非本批
  缺陷，零 diff 铁证 + omp 独立佐证 + 后续修复批 A/B decisive 根除），批内面
  定向亲跑 + worker 日志五字段逐份重析三重互证替代——证据链完整可回溯。

## 特殊事项入册（phase 级事件台账）

1. **E-omp1 与双重验收制度判例**：omp computer-use 亲证 GUI 面可达性缺口
   （首验自动化面全覆盖仍漏检）——制度价值的实证；修复缝选 base chain
   （colormatch base-resident 设计面）+ base-scope-only gate 防重复实例；
   min_votes 分歧按 FAIL 优先程序消解（M3-4-01 先例第二例）。
2. **film-leg P1 潜伏竞态**（M3-3 时代即存在）：进程级静态槽跨 await 悬挂窗
   两腿互踩 payloads——zcode-03 三份 .ips 同签名 + omp-03 独立复现同签名；
   `7bc6365` 显式传参结构性根除 + A/B 压力探针 decisive（stash 修复一击复现）。
   教训面：「single writer」静态槽在并发模型下名不副实——实例态零并发假设
   优先于 task-local 传播规则。
3. **全套终验轮混态产物事故（L075 扩展）**：tuist generate 后未重建 scheme 配
   新框架 = SIGSEGV（ABI 混态特征）——四 scheme 重建后分割重跑；zcode-03 以
   generate 后全部 8 scheme 重建为执行样板；GATE-LEDGER §6 诚实记录 + omp-03
   表头措辞 minor 在案。
4. **skip 口径修正**：M4-3「估 16」为估算非实测锚 → 实测 21（12 env + 6 资产 +
   3 fixture），台账诚实改口径；对账以 tests 总数为准。
5. **apply_params 无法 CREATE colormatch**（seed ABSENT 密封必然）：两段流
   （attach=true 建实例 → attach=false 参数组 apply_params 回灌）= 工具面设计
   语义非缺陷；与 E-omp1 同族（可达性面），工具 doc 已写明。

## 授权记录（C 档第 3 停夜间签核）

- **授权先例**：D-07-3-T5-1——用户显式继续指令 = 终签核授权（M2-8/9/10、M4-1、
  M4-3 VALIDATION 同款沿用；晨审可推翻）。
- **本次授权**：夜间全自动批在案（M5-1 三 plan 执行批「开跑，不要停」+ 双重
  验收批 + 本 doc-only 成文批同链）。依授权，本 VALIDATION 由 doc-only executor
  落盘签核（`[gsd] paused/auto` 开关未动；三波 C 档第 2 停的 plan 闭环汇报与
  签核在 GOAL-STATE 续接点逐波在案，本批 = 第 3 停 VALIDATION 面）。
- **doc-only 零源码 diff**：本批 `git status` 申报集全 docs（VALIDATION 本件 +
  五正本翻账 + 三份 OMP 验收报告入库〔此前 untracked/modified 未提交〕）。
- **呈报裁决点（禁静默）**：①Manual-Only 目测行 + bake 生产耗时的 M5-4 人工
  执行安排；②omp-03 §3.1 面板追色观察项是否立 GUI 专项排查批；③film-leg 修复
  后全套 `--all` 复跑轮时机；④M5 milestone 不随本批收口（M5-2/M5-3 pending）。

## 翻账与移交（本批同 commit）

- REQUIREMENTS：TRACK 节头注「终态 Delivered 由 VALIDATION 批盖」→ 本批盖验
  落签（TRACK-01..05 五行 + MCP-09 研究项 C 注记维持，`grep "^- \[ \] \*\*TRACK"` = 0）。
- ROADMAP：M5-1 行 ✅ 闭环（终态 3477/21skip/0fail）。
- STATE：M5-1 complete（M5 Ledger 行翻账 + m5_phases_complete 2/5 + plans
  148→151）+ current_phase = M5-2 next。
- TODO：M5-1 三 plan 条目落账（[x]）+ M5-2 next。
- GOAL-STATE：续接点翻新 = **M5-1 closed → M5-2 Mertens 曝光融合**（IOP-HDR-06；
  Lumen 借鉴②，`lumen/merge.py` MIT 参考正本）。
- 未 push；本批 doc-only 零进程（GUI app / 测试宿主零启动）。

## 签核

- TRACK-01..05 + MCP-09 研究项 C 全项 Delivered（三列证据齐；数字对账 = 终验
  `TOTAL|3477/21/0|` 亲证基线 + GATE-LEDGER 五门全表 + 六路验收互证）。
- `status: validated` + `nyquist_compliant: true`。
- **M5-1 phase closed**：三 plan + 批外 fix(film-leg) 全闭环；对账链
  3367 + 110 = 3477 精确；挂账单一清单移交（批内收口确认二项 + M5-4 二项 +
  V2/观察项九项）。
- **M5 milestone 尚未收口**：M5-2 Mertens / M5-3 PANO / M5-4 VALIDATION+手术
  第二次 pending——本件不兼 milestone closeout（`milestone_closeout` 字段空缺
  = 有意为之，M5-4 承接）。
- 晨审裁决项：四呈报裁决点 + 签核推翻窗（原话授权在案）。
- **C 档第 3 停 = 夜间授权先例落签，晨审可推翻。**
