# M3-2 二次验收报告（omp 回溯，独立二次验收）

> 对象：M3-2「FSIM research + spike」——research 环（两段式胶片模拟阶段模型 + 配光自动求解设计定稿；OQ-M3-2-1..7 裁决面；M7 RAF 双峰 spike 顺带）。
> 方法：零共享上下文亲测——正本全读 + 日志数字独立复算（Python 直算）+ 上游 JSON 独立重算 + 代码接缝亲核。禁跑测试，无产线测试可跑；只读验收，仅写本报告。
> 正本：`.work/gsd/phases/m3-2-fsim-research/M3-2-CONTEXT.md` / `RESEARCH-NOTES.md` / `evidence/` / `perf.md §O-1` / ROADMAP M3-2 行 / `M3-4-CHECKER.md`。

## 结论头

`PASS / 0 error + 3 minor`

OQ 七条实质全清零（推荐 + RESEARCH § 支撑 + 用户回批 + 下游兑现俱全）；spike 证据在案、关键数字逐值命中；设计评审三接缝与代码现状对表成立；M3-4-CHECKER 七项引用零漂移。3 minor 均为转录精度/编号形式面，无一动摇结论。

## 一、OQ 清零（逐条编号对表）

| OQ | CONTEXT 决议 | RESEARCH § 支撑 | 用户裁决（CONTEXT L162-164） | 下游生效引用 | 判定 |
|---|---|---|---|---|---|
| OQ-1 阶段承载 | D-M3-2-1（L16-26）：③ FilmRecord + sub-run | §3（L191-235 对比表 + 推荐③） | ①按推荐 | M3-3-01-PLAN L72-74（document 级 FilmRecord 单例 + 置位不进 record）；`FilmRecord.swift:47` 落地 | ✅ |
| OQ-2 配光自动化 | D-M3-2-3（L36-48）：两段式 + ③ | §4（L266-290：bake 期/运行期/确定性门 + 缓存键 `fnv(材料对Hash ⊕ 统计Hash ⊕ 模式tag)`） | ②按推荐 | M3-3-01-PLAN L75-81（bake 期闭式解 + sanity 带 + 统计分量归 02） | ✅ |
| OQ-3 资产三态 | D-M3-2-5 01d 行（L69-71）+ D-M3-2-8 许可五件套（L85-90）+ D-M3-2-4（L50-56） | §1.5（L104-122 密度域同构）+ §5（L307-328 三态表，倾向 c） | ③按推荐 | M3-3-01-PLAN L62-71（c 混合态五件套逐字落地） | ✅ |
| OQ-4 宽容度面板归属 | ⚠️ 无独立 D-M3-2-N 条（见 minor-1）；OQ 节自带推荐①（L129-136，引 §6-4 descriptor） | §6（L347-350 descriptor/宽容度读数 golden）+ §1.2（L57-62 双虚线/placed_fractions） | ④按推荐 | M3-3-03-PLAN L39/L63-64（FSIM-02 不在本批，M3-4）；M3-4-01-PLAN L378-380 read_first 点名④生效值 | ✅ 实质 |
| OQ-5 golden 基线 | D-M3-2-5 01c 行（L66-68） | §6（L332-350：①数学复算主门 + ③渲染仅本地目测不入仓） | ⑤按推荐 | M3-3-03-PLAN L175-177（§6 golden 策略四条 + ⑤形态措辞）；M3-4-CHECKER L178-180 ⑤口径 | ✅ |
| OQ-6 spike 本环执行 | D-M3-2-7（L79-83）：方法定稿 + ② | §8（L368-388：signpost/IOReport/二分设计 + L382-388 执行结果补批） | ⑥按推荐 | perf.md §O-1（L304-384 根因判定）；evidence/ 8 文件在案；ROADMAP M3-2 行 ✅ 闭环 | ✅ |
| OQ-7 filmPlacement op | D-M3-2-1 L21-22（置位 = grade 域独立 op，可蒙版） | §1.2（L35-62 RFC-023 曲线族/恒等核）+ §3（L210-214 置位落位） | ⑦按推荐 | M3-4-01-PLAN L378-380（⑦生效值）；op 落地（M3-3-02 filmPlacement，M3-4-CHECKER L6 亲核在案） | ✅ |

下游一致性抽查（≥3 处，实做 5 处）：M3-3-01-PLAN L60-85 六条已定裁决块（①②③④⑤+pristine+OQ-1..7 按推荐裁）✓；M3-3-02-PLAN L49/L436（FSIM-03 不立项 = D-M3-2-6 注记即止）✓；M3-3-03-PLAN L175-177（§6 + ⑤）✓；M3-4-01-PLAN L378-380（OQ-M3-2-2③/④/⑦ 生效值）✓；M3-4-CHECKER L178-185（七项生效值零动摇）✓。全部与 D 条/OQ 推荐同向，无漂移。

## 二、spike 证据真实性（日志直算复核）

证据包 8 文件齐（README 文件索引表 L30-34 与目录实况逐项命中；另有两轮被覆盖转写摘录，README L36-41 已声明，未谎称存档）。

### 2.1 bench 跨进程复跑 run4..7（≥3 处量化，实做全表）

日志 `PERF|` 行与 perf.md L355-358 表**逐值命中**（含 cold + warm×3 + 中位 + ARW 全列）：

- run4：RAF cold 2.5 / warm 82.1/57.5/51.7 → 57.5；ARW 13.6/15.6/14.5 → 14.5 ✓
- run5：RAF cold 223.4 / warm 44.7/81.1/37.1 → 44.7；ARW 13.5/12.3/12.8 → 12.8 ✓
- run6：RAF cold 746.4 / warm 15.0/50.2/46.5 → 46.5；ARW 13.4/13.1/13.2 → 13.2 ✓
- run7：RAF cold 759.9 / warm 14.7/50.6/92.6 → 50.6；ARW 13.3/13.3/13.7 → 13.3 ✓
- 「RAF 单帧跨 14.7-92.6；ARW 四轮 12.3-15.6 全稳」（perf.md L360-361）✓（12.3 = run5 ARW w2 最小值，亲核）

### 2.2 探针六相位统计（独立复算 vs perf.md L318-327 表）

直算（raffirst.log，`PROBE| <label> i=.. ms=..` 全量提取排序）：

- RAF/base：n=40，i0-i3 = 21.39/34.75/80.95/49.83，README 称 21.4/34.8/81.0/49.8 ✓（舍入）；i≥5 稳态带 max 24.47（= i7），perf.md 称 max 24.5 ✓
- RAF/same：0.03/0.04/0.11 ✓ 逐值（地板 0.03ms 断言成立）
- RAF/fresh：min 15.69 / max 25.09 ✓；中位直算 **17.58** vs perf.md 称 17.4（Δ0.18，见 minor-2）
- RAF/gap：min 16.64 / max 28.79 ✓；中位直算 **21.99** vs 称 22.0 ✓
- ARW/gap：中位直算 **21.17** vs 称 20.7（Δ0.47，见 minor-2）；双格式同现衰减方向成立
- RAF/sdr 中位直算 16.25 vs 称 16.0；RAF/clr 中位直算 16.66 vs 称 16.2（见 minor-2）；max 26.81/25.15 vs 称 26.8/25.2 ✓
- ARW/base：13.66/15.07/18.66 vs 称 13.7/15.0/18.7 ✓
- 列序反转（4tests.log）：ARW-first base i0-i5 = 18.34/18.67/53.34/80.00/46.32/27.58 vs perf.md L330 称 18.3/18.7/53.3/80.0/46.3/27.6 ✓
- GRIND（除 i0 冷帧）：n=119，min 13.58 / med 15.16 / p90 18.65 / max 45.04 ✓ **四值逐位**；帧 5-7 = 27.59/45.04/28.34 vs 称 27.6/45.0/28.3 ✓；其后 113 帧零自发翻态（max 45.04 即帧 6）✓
- BENCH 复刻 RAF round0：cold 750.4 / warms 15.0/14.2/49.5 ✓ 逐值；round1-5 cold 14.1-15.5、warms 13.9-15.6 ✓
- 开图 fp 增幅：RAF 5127→6402MB（= 5.1→6.4GB ✓，perf.md L373）；ARW 2510→3928MB（= 2.5→3.9GB ✓）
- decode 腿：RAF warm 实测带 74.1-83.2（含 raffirst 83.2 一帧）vs 称 74-81；ARW 实测 109.9-118.1（含 raffirst 118.1/114.3/114.8）vs 称 110-112（见 minor-2；「候选排除」结论不动）
- 协变量日志 1015 行，含 `Renderer Utilization %` / `memory free percentage ≥80%` / swap 零活动采样 ✓；系统态排除（perf.md L338-339）有源

### 2.3 探针源码与日志类名一致性

- `RAFWarmBimodalProbeTests.swift.txt`：类名 `RAFWarmBimodalProbeTests`（L31）+ 四测试 `testProbeRAFFirst/testProbeARWFirst/testProbeRAFGrind/testProbeBenchShapeReplica`（L238/L257/L276/L304）——4tests.log 实测集合 = 同四名 ✓
- 源码相位结构（base 40/same 12/fresh 25/gap 15/sdr 20/clr 15，L204-234）与日志各相位 n（40/12/25/15/20/15）✓ 逐项
- 源码 `BENCH|` 格式（L348-350）与日志 12 行 BENCH 复刻行 ✓；`PROBE|` 格式（L151-154）与日志 268+656 行 ✓
- 零产线 diff：`git ls-files` 全仓仅命中证据快照 `.txt`，工作树探针 `.swift` 未入 git ✓（与 README L8-12「未入 git、收尾还原」一致）；spike 收口 commit `c8ddc57` 在案

## 三、设计评审面（接缝声明 vs 代码亲核，抽 3 处）

1. **`DrtTailAssembly.seed(upstream:)` 签名零改**（D-M3-2-1 L20 + RESEARCH §3 L198-201 + §9 L399-400）：`LightamerCore/Sources/Pipe/PixelPipe.swift:1553` `public static func seed(upstream:params:)` 在位 ✓；调用点 `:959` 传 `upstreamSeed` ✓；film 交接注释 `:162-163`（upstreamSeed = film 输出 hash）与 `:973-975`（keeps exact signature, only VALUE changed）✓；`FilmTailPolicy.swift:23-25` 同款签名不变声明 ✓。注：RESEARCH §3 引用的旧行号（:1244-1267/:1276-1310）已随代码增长漂移，符号缝本身成立——属研究文档行号自然陈旧，非设计失实。
2. **节点图 M2-4 语义零改动**（D-M3-2-1 L23-24 + RESEARCH §3 L216-218 投影卡）：`LightamerCore/Sources/Graph/PipelineDocument.swift:44-47` `NodeKind` 仍三 case（develop/grade/displayTransform），无 film case ✓；Film 只读卡走 App 侧投影（AGENTS M3-3 增量节 `filmCardID` 编译期常量 + `NodeKind 零新增` 在案）✓。另 RESEARCH §3 L163-166 引 `PipelineDocument.swift:44-47` 链序——行号至今逐位有效 ✓。
3. **pristine = 缺键逐位直通**（D-M3-2-1 L24 + RESEARCH §3 L205-208 + §9 L415-416）：`App/Sources/Lightamer/State/PipeCoordinator.swift:777-780` `filmTailPolicy(for:)` —— 非 thumbnail + `hasFilmRecord` 缺键即 `nil`（DRT 同款门）✓；`LightamerCore/Sources/Graph/FilmRecord.swift:141-143` `isFilmRecordDefault` ✓；`FilmRecord` 本体 `:47` document 级 record 落地 ✓。

## 四、M3-4-CHECKER 七项引用对表（vs CONTEXT D 条）

CHECKER L178-181 七项（①FilmRecord 承载 / ②配光自动③案 / ③资产 c 混合 / ④宽容度面板 M3-4 / ⑤golden 数学复算主门 + 公开参考值口径 / ⑥spike / ⑦独立 filmPlacement op）逐项对表：①=D-M3-2-1③案 ✓；②=D-M3-2-3 + OQ-2 rec③ ✓；③=D-M3-2-5 01d + D-M3-2-8 + OQ-3 rec c ✓；④=OQ-4 rec① + 裁决④ ✓；⑤=OQ-5 rec① + RESEARCH L336「公开标准部分用公开参考值」（CHECKER 引 `:336`，亲核逐字 ✓）✓；⑥=D-M3-2-7 + OQ-6 rec② ✓；⑦=OQ-7 rec① + D-M3-2-1 L21-22 ✓。**无漂移**。

## 五、minor 清单（3 项，无 error）

- **minor-1（D 编号形式缺口）**：OQ-M3-2-4（宽容度面板归属）无独立 D-M3-2-N 决议条——推荐①仅载于 OQ 节（CONTEXT L129-136，带 RESEARCH §6-4 引用）+ 裁决记录④。实质链完整（推荐 + § 支撑 + 回批 + 下游 M3-4 交付），CONTEXT 自检口径（L94「全部有推荐项」）亦满足；仅 D 条编号覆盖 6/7。不判 FAIL。
- **minor-2（perf.md §O-1 转录精度）**：若干中位/带宽小数与日志直算差 0.2-0.5ms——fresh 中位 17.4 vs 17.58、sdr 16.0 vs 16.25、clr 16.2 vs 16.66、ARW gap 20.7 vs 21.17；decode 带 RAF 74-81 vs 实测 max 83.2、ARW 110-112 vs 实测 max 118.1；另「+50-100%」小标题 vs 中位比（RAF 22.0/17 = +29%、ARW 20.7/15 = +38%）口径偏峰值帧。全为 min/max 逐值命中下的中位小数或带宽收窄，根因判定（采样窗伪影 + 空闲衰减 + 稳态确定性）方向全不受影响。
- **minor-3（RESEARCH §1.3 上游值域误载，下游已纠正）**：§1.3 L72-73 称中性包「值域 [C=0, M≈57-79, Y≈63-79] 点」——本验独立重算上游 `neutral_print_filters.json`：160 组合，C≡0，**M∈[28.4,92.1] / Y∈[24.6,116.0]**，33/160 出 [40,90] 带（≈1/5）。下游 M3-3-01-PLAN L64-66 已回注亲核纠正（sanity 带只对具名组合断言），纠正值与本验复算逐值一致；§1.3 结构结论（离线查表 + 在线曝光归一）不受影响。M3-2 正文误载本身记 minor。

## 六、与首验/申报分歧点

- 目录内无既有 M3-2 首验报告件（仅 CONTEXT + RESEARCH-NOTES + evidence/），本验为首次验收——无首验分歧可列。
- 与申报（ROADMAP M3-2 行「OQ 清零 ✓ + 设计评审/用户过目裁决 ✓ + spike 结论入 perf.md ✓」）核对：三项俱实。另 M3-3-CHECKER m6 曾挂「spike 未结案前 M3-2 不应翻 ✅」——现 spike 补批（`c8ddc57`）+ perf.md §O-1 + ROADMAP ✅ 闭环已兑现，该保留条件已消解。

## 七、会话卫生

- 只读验收：除本报告文件外零写入；未改源码与既有文档；未 push；未跑测试（research/spike 面纪律）。
- 复算工具：Python 标准库直读日志/上游 JSON，无外部依赖；工作区 git 状态除本报告新文件外无新增修改（预存 `M3-1-ACCEPTANCE-OMP.md` 等 untracked 系他批产物，未触）。

OMP-VERDICT: PASS
