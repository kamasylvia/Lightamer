# M3-2 二次验收报告（PI 路，回溯双路并发批）

> 验收员身份：PI（独立回溯二次验收员，零共享上下文）｜日期：2026-10-10｜HEAD：`d57488ec`
> 方法一句话：正本全读（RESEARCH-NOTES / M3-2-CONTEXT / evidence/ 8 件 / perf.md §O-1 / ROADMAP M3-2 行 / AGENTS M3-3 增量节）+ 提炼上一轮 OMP 报告抽查点后逐项独立取证（Python 直算日志、grep/ls 读码、上游 JSON 独立复算），只读验收、未跑测试、除本报告零写入。

## 结论头

`PASS / 0 error + 5 minor`

OQ-M3-2-1..7 实质全清零（推荐 + RESEARCH § 支撑 + 用户回批 CONTEXT:162-164 + M3-3/M3-4 兑现俱全）；spike 证据在档、关键数字独立复算逐值命中（含 OMP R1 标记的 4 处转录偏差复认）；设计三接缝与代码现状对表成立（行号漂移均标「后演进，不记账」）；研究结论→交付兑现映射（光谱不可达/资产五件套/K 标定/session 反演）四点全核。5 minor 无一动摇结论，其中 1 项为上一轮漏检（见分歧项）。

## 一、抽查点独立取证（自上一轮报告提炼 ≥4 项，实做 9 项）

### 1.1 bench 跨进程复跑 run4-7 PERF 行 vs perf.md §O-1 表（全 4 轮亲读）

`grep 'PERF|' m3-2-spike-bench-run{4..7}.log`：run4 RAF cold 2.5 / warm 82.1/57.5/51.7→57.5、ARW 13.6/15.6/14.5→14.5；run5 223.4 / 44.7/81.1/37.1→44.7、13.5/12.3/12.8→12.8；run6 746.4 / 15.0/50.2/46.5→46.5、13.4/13.1/13.2→13.2；run7 759.9 / 14.7/50.6/92.6→50.6、13.3/13.3/13.7→13.3——与 perf.md §O-1 跨进程表**逐值一致**；「单帧跨 14.7-92.6 / ARW 12.3-15.6」成立（12.3 = run5 ARW w2 亲核）。✅

### 1.2 探针六相位统计独立复算（raffirst.log，Python 全量提取）

RAF/base n=40 i0-i3 = 21.39/34.75/80.95/49.83（README 21.4/34.8/81.0/49.8 ✓ 舍入）、i≥5 max **24.47@i7**（perf.md 24.5 ✓）；fresh med **17.58** vs perf.md 17.4、gap med 21.99 vs 22.0、sdr med 16.25 vs 16.0、clr med 16.66 vs 16.2、ARW gap med **21.17** vs 20.7（四处偏差 = OMP minor-2 独立复认）；same 地板 0.03/0.04 ✓；ARW/base 13.66/15.07/18.66 ✓；相位帧数结构 40/12/25/15/20/15 与探针源码逐一 ✓；PROBE 行数 268/656 ✓。✅（偏差记账见 minor-2）

### 1.3 4tests.log 三组关键数（列序反转 / GRIND / BENCH 复刻）

ARW-first base i0-i5 = **18.34/18.67/53.34/80.00/46.32/27.58**（log L11-16 逐位，瞬态非 RAF 专属成立）；GRIND 除 i0 冷帧 748.0：n=119 min 13.58 / med 15.16 / p90 18.65 / max 45.04@帧6、帧5-7 = 27.59/45.04/28.34、帧≥8 n=112 max 24.36（零自发翻态成立）；BENCH 复刻 RAF round0 cold 750.4 → warms 15.0/14.2/49.5、round1-5 cold 14.1-15.5 / warms 13.9-15.6 ✓ 逐值；fp 增幅 RAF 5127→6402 / ARW 2510→3928 MB ✓（`col=ARW` 后首行 2510）。✅

### 1.4 上一轮 minor-3 独立复算（上游 JSON 值域）

对 `Resources/FilmProfiles/neutral_print_filters.json` 与上游 `SpektraLab/engine/resources/neutral_print_filters.json` 双文件独立复算：**160 组合，C≡{0.0}，M∈[28.4, 92.1]，Y∈[24.6, 116.0]，33/160 出 [40,90] 带**；两文件样本值逐位相同（原样拷贝佐证）。RESEARCH §1.3 「[C=0, M≈57-79, Y≈63-79]」确为误载 → OMP minor-3 **成立**；下游 M3-3-01-PLAN 已回注纠正。记账 minor-3。✅

### 1.5 设计接缝 vs 代码现状（三缝亲核，行号漂移标后演进）

①`DrtTailAssembly.seed(upstream:params:)` 现位于 `PixelPipe.swift:1684`（签名 `public static func seed(upstream: UInt64, params: DrtTailParams)` 不变；调用点 `:1084/:1115/:1118` 传 upstreamSeed，film 交接注释 `:163`）——OMP 引 :1553 为后演进漂移，缝成立；②`PipelineDocument.swift` `NodeKind` 仍三 case（develop/grade/displayTransform）无 film ✓（行号 ~44-47 仍有效）；③`filmTailPolicy(for:)` 现位于 `PipeCoordinator.swift:804`：guard thumbnail/`hasFilmRecord` 缺键/`isFilmRecordDefault` → `nil`（pristine 零动作 + thumbnail 恒 legacy）✓——OMP 引 :777-780 为后演进漂移；`FilmRecord.swift:47`（document 级 record）+ `:141 isFilmRecordDefault` 行号至今逐位有效 ✓。✅

### 1.6 OQ 清零与 M3-4-CHECKER 七项对表

CONTEXT 裁决记录 `:162-164`「OQ-M3-2-1..7 全部按推荐采纳」在案；D-M3-2-1..8 逐条与 RESEARCH § 对应亲读成立；`M3-4-CHECKER.md:178-181` 七项生效值（①FilmRecord 承载/②配光自动③案/③资产 c 混合/④宽容度面板 M3-4/⑤golden 数学复算主门+公开参考值口径/⑥spike/⑦独立 filmPlacement op）与 CONTEXT D 条/OQ 推荐逐项同向零漂移；其引 `RESEARCH-NOTES:336`「公开标准部分用公开参考值」逐字亲核命中。✅（OQ-4 无独立 D 条 = OMP minor-1 复认，记账 minor-4）

### 1.7 研究结论→M3-3/M3-4 交付兑现映射（对象卡指定抽核）

①光谱不可达：RESEARCH §2 边界声明 → AGENTS M3-3 增量「光谱不可达架构注记（用户可见措辞=物理流程建模，非光谱重放）」兑现 ✓；②资产五件套：RESEARCH §5 操作面清单 + D-M3-2-8 → `Resources/FilmProfiles/` 实测 = LICENSE（CC BY-SA 4.0 全文）+ NOTICE（Andrea Volpato/spektrafilm 署名）+ CHANGELOG + `profiles/` 28 件 + neutral_print_filters.json，与 `Resources/LUTs/`（MIT）物理隔离 ✓；③K 标定：RESEARCH §4.1「k = CC 点 × 换算系数，plan 期标定」→ `Film/FilmFilterPackSolver.swift:70/74`（0.0085/0.017，2:1 dichroic 注记在文件头 :22）✓；④session 系统反演：RESEARCH §4.1 伪代码「胶片中性曲线反转（RFC-028 灰阶误差恰 0）」+ §1.4 → `FilmPrintBake.swift:26`（"FILM-CHANNEL INVERSION (RFC-028's gray-error-exactly-0"）+ `:235 systemDensity` ✓；⑤`FilmRecord` 字段（filmStock/paperStock/y+mFilterShift/strength，RFC-025 强度混入语义注释）= D-M3-2-1 ③形态 ✓。✅

### 1.8 spike 卫生面

`git ls-files | grep -i RAFWarmBimodal` 零命中（探针未入 git，产线 diff=0 ✓）；探针源码类名/四测试名（`RAFWarmBimodalProbeTests.swift.txt:31/238/257/276/304`）与 4tests.log Test Case 行逐一命中 ✓；README 对两轮被覆盖轮次的转写摘录有诚实声明 ✓。✅

### 1.9 ROADMAP M3-2 行申报核对

ROADMAP.md:21 ✅ 闭环行：research 定稿 `b4049b8` + OQ 回批 `e02dcc7` + spike 补批（根因入 perf.md §O-1、证据包指针、零产线 diff、晨审可推翻注记）——与本验全部取证一致；三项验收形态（OQ 清零/设计评审/spike 入 perf.md）俱实。✅

## 二、分歧项（与上一轮 OMP 报告的判定差异）

1. **OMP R1 §2.2「memory free percentage ≥80% … ✓」判定不成立（上一轮漏检/误判）**：归档 `m3-2-spike-covariates-1s.log`（1015 行）独立解析——`System-wide memory free percentage` **≥80% 仅见于前 159 行（09:58:34-10:01:27）预跑段；全程 min 23%**（@10:13:18），856/1015 行 <80%；对应归档 4tests 探针窗（时间轴换算 UTC，与其 18:08 CST 开跑对齐）内 min **24%**。perf.md §O-1:338「全程 …系统空闲 ≥80%」同样与归档证据不符。**结论不被推翻**（同窗 swap used 恒 3277.12M 零活动 ✓、Renderer Utilization 均值 1.95%/探针窗 max 0 ✓——「排除系统热节流/内存压力」由 swap 恒定 + GPU util 低两条腿独立支撑；free% 走低系探针宿主自身 GB 级占用，非外部压力），但该数字面失实，OMP R1 对该子项标「✓」属误判（疑仅核了日志头部）。记账 minor-1（可修性：小修——perf.md 该行改述为「swap 零活动 + GPU util 均值 ≤10%」或补注 free% 口径）。
2. 其余抽查点（run4-7、六相位统计、4tests 三组、值域复算、三接缝、七项对表）**无判定分歧**：全部独立复认上一轮结论；其 minor-1/2/3 三项均独立复算成立（分记 minor-2/3/4）。

## 三、minor 清单（5 项，无 error）

- **minor-1**：perf.md §O-1:338「系统空闲 ≥80%」与归档协变量日志不符（全程 min 23-24%，≥80% 仅预跑 159 行）+ OMP R1 该子项误判（分歧项 1）。根因判定不动摇。小修。
- **minor-2**：perf.md §O-1 若干中位/带宽小数转录偏差（fresh 17.4 vs 直算 17.58、sdr 16.0 vs 16.25、clr 16.2 vs 16.66、ARW gap 20.7 vs 21.17；decode 带 RAF 74-81 vs 实测 max 83.2、ARW 110-112 vs 118.1）。方向与结论全不受影响（OMP minor-2 复认）。
- **minor-3**：RESEARCH §1.3 中性包值域误载（实为 M∈[28.4,92.1]/Y∈[24.6,116.0]，33/160 出 [40,90]）；下游 M3-3-01-PLAN 已回注纠正，本 phase 正文误载记账（OMP minor-3 复认，本验双文件独立复算）。
- **minor-4**：OQ-M3-2-4（宽容度面板归属）无独立 D-M3-2-N 决议条——推荐①仅载于 OQ 节 + 裁决记录④；实质链完整（下游 M3-4-01 交付即其兑现），仅 D 条编号覆盖 6/7（OMP minor-1 复认）。
- **minor-5**（本验新发现）：协变量日志覆盖窗不含 raffirst 再捕轮——日志止于 10:16:14（UTC 换算）而 raffirst suite 18:16:46 CST 才开跑（其前 32s 已停采样）；README「全程 1s 外部协变量」措辞对再捕轮过宽，且日志时间轴为 UTC、与探针日志 CST 相差 8h 无口径注记（对齐依据 = 4tests 18:08 CST 开跑与日志 10:08 段 free% 骤降逐秒吻合 + 日志终点与证据包落盘时刻衔接，判 near-certain；free% <80 事实本身不依赖时区解读）。观察项，不改结论。

## 四、会话卫生

只读验收：除本报告外零写入、未改任何仓库文件、未跑测试、未发起网络动作、未动 GUI；复算工具 = python3 标准库 + grep/sed/ls（日志与 JSON 均本地归档件）。

PI-VERDICT: PASS
