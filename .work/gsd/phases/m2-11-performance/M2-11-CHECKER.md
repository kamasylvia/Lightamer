# M2-11 Checker — plan 集执行前质量门（2026-10-06）

> Checker subagent（goal-backward 从严口径；M2-2..M2-10 前序 checker 抓 40+ 计划级错误同款纪律）。
> 输入 = 五 plan + CONTEXT（文末裁决记录八项生效值）+ RESEARCH-NOTES + 交叉锚
> （ROADMAP/REQUIREMENTS、各 phase perf.md、test-direct.sh 现状、M2-4-0 SPIKE、
> M2-10-07-SUMMARY 交接节、D-05-08-T6-1）+ 源码亲核（下述每条均实测，非誊录 plan 文本）。

## 结论

**FAIL / 5 error + 7 minor**

五 error 全部有明确修复处方且不触碰裁决本体（OQ-1..8 全 A 生效值不动）；修复后可进执行。
E1/E4 落在 M2-11-02（唯一改码 plan 的改码半径定位），E2/E3 落在 M2-11-05/02 的终验对账
算术与翻账 scope——这四件若带病执行，会在执行中后段以「diff 边界冲突 / 终轮 AC 必失败 /
M2 closed 推不出」的形态爆雷，回修成本远高于现在改 plan。

---

## Error（必修）

### E1 — M2-11-02：nlmeans 降载杠杆定位错文件，改码半径与 diff 边界申报不可满足

- **事实**（源码亲核）：降载档位真身在 `LightamerIOP/Sources/NLMeans/NLMeansModule.swift`——
  `searchRadius(roiScale:iscale:pipeType:)` K clamp `min(3, k)`（:113-120）、
  `decimates(pipeType:)`（:121-122）、`offsets(K:decimate:)`（:139）；window 半径 =
  `denoise(radius: 2, …)` 实参。`PixelPipe.swift:800` 只是 **pipeType stamp 供数点**
  （注释自述 "the nlmeans preview-downgrade lever reads it"）——不是档位判定本身。
- **plan 矛盾**：front-matter `files_modified` 产线只报 `PixelPipe.swift`；KD-3 半径、
  纪律 1「产线 diff 只许 PixelPipe.swift 一处」、T7「PixelPipe hunk ≤ 降载档位段」、
  AC#8 同源。按真杠杆执行必然触碰 NLMeansModule.swift → 要么违规越界、要么被迫在
  PixelPipe 造档位表再让 NLMeansModule 消费（跨两文件的更大改动，与申报冲突）。
- **连带缺口**：档位一变，`NLMeansParityTests.testPreviewDowngradeDerivations`
  （K=3+decimate 派生 pin，PreviewChainPerfTests :211 注记指名）必红；KD-3 虽有
  「parity 面需重钉 = DECISIONS 登记」但 `files_modified` 未申报该测试文件——落地档
  分支下 AC#8「diff == 申报集」自相矛盾。
- **处方**：files_modified 增 `LightamerIOP/Sources/NLMeans/NLMeansModule.swift`
  （条件项：仅落地档分支）+ `Tests/LightamerTests/NLMeansParityTests.swift`（条件项：
  重钉）；纪律 1 / T7 / AC#8 改写为「产线 diff = NLMeansModule 降载档段（revert 分支
  则零产线 diff）；PixelPipe stamp 点零触碰；parity 重钉须 DECISIONS 签注」。

### E2 — M2-11-05：「M2 族 uncheck 残留 = 零（除 M2PERF 两行）」与实况不符，M2 closed 推不出

- **事实**（`grep "^- \[ \]" .work/gsd/REQUIREMENTS.md` M2 段全量枚举）：M2 段
  （:8..:101）当前 uncheck = **4 行**——M2NODE-03（:41）、M2DRT-06（:61）、
  M2PERF-01/02（:99-100）。
- **两件遗留的处置证据均在案**：M2DRT-06 行内注记自载「M2-6-3 终验 Delivered
  （method 收口）+ 验收 PASS」——翻勾逾期，纯记账件；M2NODE-03 行内注记「严格面激活
  （18 目录收窄）归 M2-5」，且 `.work/TODO.md:353` 载 M2-5-2 交付含「add 面严格化」、
  「REQUIREMENTS M2GRADE-01..07 全 Delivered」——翻勾逾期，带指针件。
- **plan 矛盾**：05 KD-1.3「各族已翻账 Delivered 只做存在性核」前提失实；翻账批
  （KD-4.3/T5）scope 只列 M2PERF-01/02 → AC#4「翻账后 M2 段 uncheck = 零」**必失败**，
  「M2 closed」结论推不出（带日期历史行纪律也不允许把这两行静默留白签核）。
- **处方**：05 翻账批 scope 增两件——M2DRT-06、M2NODE-03 翻勾 + Delivered 终态注记
  （证据指针：`m2-6-drt/M2-6-3-ACCEPTANCE.md` / `TODO.md:353` M2-5-2 批）；KD-1.3
  措辞同步为「uncheck 残留 = 四行（两遗留 + M2PERF 两行），翻账批一并关闭」。若
  orchestrator 对 M2NODE-03 另有裁决（如严格面语义收窄未满），则在 INPUT 显式呈报
  用户裁——不许静默带 [] 收口。

### E3 — M2-11-02/04/05：skip 基线算术错，终轮判定式 `TOTAL|<2955+Δ>/16/0|` 会被自己打破

- **事实**：`QuickLookPerfProbeTests` 现仅 **1 个** env 门控 func
  （`testQLRenderLatencyGrid`，LA_QL_PERF=1 才跑；默认轮贡献 skip 16 之一——BUNDLE-MAP
  :216 EXPORT 1 文件）。skip 计数是**每 test func** 计（BUNDLE 行 skipped = `' skipped`
  行计数），不是每文件。
- **plan 矛盾**：02 T4「探针新增端到端分项」按 XCTest 惯例落新 func（env 门控）→
  默认套件 skip 16→16+Δs；02 纪律 3「新增用例属同文件 family，不新增 skip 行」
  不成立；05 KD-1.1/AC#2 硬编码 `/16/` 同错；04 T3 重述批「终验基线 2955/16/0」注记
  同错。终轮按 AC 机检将出现 `2955+Δ/17/0` 对不上判定式的窘境（诱发改数凑门的反向
  激励）。
- **处方**（二选一，写死进 plan）：(a) 02 KD-4 明示探针分项**并入现有单 func**
  `testQLRenderLatencyGrid` 内部分段（零 skip 增量，判定式不动）；或 (b) 允许新 func，
  02 纪律 3 / 05 判定式 / 04 基线注记统一改 `<2955+Δ>/<16+Δs>/0`（Δs 在 INPUT 逐项
  对账）。

### E4 — M2-11-02 KD-3：降载尝试序②的档位方向反了

- **事实**：57 = 降载档**趟数**（`offsets(K:3, decimate:true).count = 14` →
  `14×4+1 = 57`，05 perf.md SC#4 同口径）；decimate **更深 = 趟数更少**（<57）。
  KD-3「decimate 57→更深（如 65/73）」的 65/73 是**更浅档**（>57，朝满血 481 方向）——
  与「更深」自相矛盾，且 65/73 无自然档位对应（K=2 → 29 趟；K=4 → ~89 趟）。
- **风险**：这是全 phase 唯一产线改码尝试的尝试序，方向错会烧执行轮次/误导落地档选择。
- **处方**：改为「②decimate 加深（drop 间隔加大，趟数 <57）」；示例值删 65/73 或改
  为趟数口径（如「57 → ~37 → ~29」梯度）；「取达 ≤16.6ms 的**最浅档**」语义保持
  （最浅 = 趟数最多仍达线的档，观感代价最小——与 OQ-7-A 一致）。

### E5 — M2-11-02：样张口径与 OQ-5-A/AC 字面矛盾（「100MP 真样张」vs 60.2MP fixture）

- **事实**：OQ-5-A 生效值与 02 AC#1 写「100MP（级）真样张 preview-2560」；KD-1 样张 =
  `input/RAW/DSC00012.ARW`（60.2MP A7R V）。「在库 **tracked**」失实——
  `.gitignore:19 input/*`，`git ls-files input/RAW/` 为空（本地 fixture，skip 门覆盖；
  DefaultLookTests/GUI22 同款相对路径引用属实）。
- **影响**：AC#1 按「100MP 级」字面不可真满足（执行要么换 fixture 不申报、要么措辞
  放水）。PREVIEW 桶管线工作量与源 MP 基本无关（桶位 2560 主导），差在 decode 腿
  （60 vs 100MP）——语义上可解，但要写明。
- **处方**：02 KD-1 增 `Fixtures.raf100MP`（`Fujifilm-GFX100S-14bits-uncompress-4_3.RAF`，
  Tests/Fixtures.swift:77 既有 fixture 约定）列——60MP/100MP 双列各出 cold/warm；或
  AC#1/KD-1 措辞统一为「60.2MP 真样张（decode 腿口径注明；preview-2560 管线腿与源
  MP 无关）+ 100MP 列若 fixture 在场」。「tracked」改「在库本地 fixture（skip 门控，
  不入 git）」。plan 03 的 FULL 对标不受影响（60MP > 45MP 更严口径成立，其「若有
  tracked fixture 则加列」措辞同样按本地 fixture 改）。

---

## Minor（建议修，不阻塞）

### m1 — M2-11-01 KD-2.3：「:165 已兼容零触碰」表述失准

`:165` summary_fail 外层 `^Executed [0-9]+ tests` 与 :162 同为复数限定——单数轮
summary_fail 恒 0（失败计数走 `' failed (` 行仍正确，无正确性洞，AC#3 仍可过），
但「零触碰」结论不成立。处方：单数修覆盖 :162 与 :165 外层同一 regex 两处。

### m2 — M2-11-02 KD-4 / 04 KD-3.2 / 05 KD-5：OQ-6-A「缩略/fit 桶 ≤500ms」双桶门含已知不达臂且无退出语义

fit(2560) 桶 warm 在案 **2.08s**（13 perf :18，超门 4×）——OQ-6-A 原文「缩略/fit 桶
首帧 ≤500ms」若按双桶读，= 自带缺口签核（02 KD-1 自己对 16.6ms 硬线禁的形态）；
且 OQ-6-A 无「若不达」臂，05 KD-5 已知预挂面（denoise/FULL/hitch）未列此项。
处方：04 重述批明确门对象 = **缩略桶（512）首帧 ≤500ms**；fit(2560) 桶 = 记录档 +
2.08s 现状注记 + 显式归类（观察项或挂账）；05 KD-5 预挂面补该项。此为裁决文本的
歧义消解（非重开裁决——证据 512 桶即 OQ-6-A 立论依据）。

### m3 — M2-11-02 front-matter：test_bundles 缺 SESS

T5 档 B Release 复核跑 `SessionThumbnailProviderTests.testThumbnailThroughputBaselineTierAAndTierB`
（:1039，SESS bundle）。处方：`test_bundles: [IOP, EXPORT, SESS]`（或注记 T5 走 SESS）。

### m4 — M2-11-01 KD-1：parse_bundle_log 职责面自相矛盾

「BUNDLE 行组装」列入抽取段，但 stdout 定义为 executed/skipped/failed/verdict 四字段；
且 MEMFAIL 判定依赖 log 内 `maximum resident set size`（ru_maxrss）解析——该解析归
parse 还是留 run_bundle 未言明。处方：明确 parse 输出面（建议五字段：+peak/sampling，
MEMFAIL/ANE-DEGRADED 判定全在 parse 内；「BUNDLE 行组装」留 run_bundle 拼装），selftest
断言随之对齐。

### m5 — M2-11-02/03：IOP 贴线 bundle 增重的峰值观测义务未注记

新增 IOP 重测增量峰值预估 2.5-3.5GB（60MP FULL = decode ~1GB + 512MB 窗口默认
（PixelPipe:192 maxTileWorkingBytes）+ FULL 输出面 ~1GB）< 既有主导峰 7865MB
（TilingOverlap，SPIKE :59）——IOP bundle 峰值预计不变，终轮 MEMFAIL 风险低；但按
M2-4-0 贴线纪律（±3% 方差注记）应观测。处方：02/03 perf.md 增行记录新 bench 自身
增量峰值；若 IOP 连续 MEMFAIL 先查新 bench（SPIKE 处置序）。

### m6 — M2-11-05 D-6：红线域扫描窗口语义可更纯

`c573087..HEAD` 含 M2-10-06/07 已验段（M2-10-07 已核 c573087..9586c1b 零命中）——
零命中结论仍成立（更强命题），但 M2-11 归因纯净窗口 = `9586c1b..HEAD`。处方（可选）：
INPUT 机检节双窗口并报，或径改 9586c1b 起算。

### m7 — M2-11-01 KD-1：LA_SELFTEST 守卫的 return 语义

被执行（非 source）路径下 zsh top-level `return` 报错。处方（可选）：守卫写
`return 0 2>/dev/null || exit 0` 形态，或守卫段注释限定「仅 source 消费」。

---

## 通过面（七维核验记要）

1. **裁决一致性**：OQ-1（04 三分法三层齐：①GUI profile+断言两层互证——footprint 主判据
   + enforceBudget(now:keeping:) 注入面实测存在 PipeCache.swift:210；②FULL 负证
   （MemoryBudgetTests 既有在册）；③8G 零触碰 `RSS_LIMIT_MB=8192` 实测在位 :59）/
   OQ-2（03 两硬门 + KD-4 退出路径「谁裁（DECISIONS+orchestrator+用户 C3 签核）/什么
   证据（分解表）」可执行，AC#1 无第三态）/ OQ-3（01 三修两观测与裁决逐件对齐，禁 B 案
   写明）/ OQ-4（零触碰）/ OQ-5（E5 样张口径外全对齐：makeDefaultChain 存在
   ChainBuilderHelpers:27、defaultLook = +1.5EV/+15/1.3 实测 NodeOwnershipCatalog:272）/
   OQ-6（m2 歧义外结构齐）/ OQ-7（E1/E4 外 bounded 语义齐：revert 为默认退出、二选一
   留痕可机检）/ OQ-8（E2/E3 外单一正本结构齐）。nlmeans revert 挂账为默认的退出语义
   可机检（git diff 空 + perf.md 挂账行）。
2. **计量学**：L014 fence 落 02 纪律 2 / 03 KD-1/KD-2（bench 面 hitch 走 signpost 时戳
   差非 GPU 读回，fence 不适用——口径自洽）；warm/cold 定义（首渲 vs 进程内二次）单测
   可复现；hitch Manual-Only 判定线（锁屏/无控制台即登记，不阻塞收口；05 KD-2.2 可达
   则补）成立。
3. **编译/脚本完整性**：:162 单数 regex 缺口属实（grep 现状亲核）；L055 崩溃签名形态
   （`time: command terminated abnormally` + 类 suite Executed 末条）与 LESSONS :522
   一致；过滤轮豁免（filter 非空跳过 no-total-line）覆盖旧式类过滤扫全 bundle 形态；
   三 fixture 三断言自证闭环成立；`前红即停`（ANY_FAIL break）在执行环不在 parse，
   抽取不涉。m1/m4 两处表述修正后可执行。
4. **波次依赖**：01(无依赖)→02(dep 01)→03(dep 02，链构造复用 02 T1 产物成立)→
   04(dep 02+03 终值——依赖原因 KD-3 明示)→05(dep 01..04) 链成立可执行；05 全 `--all`
   批准制与 AGENTS.md 资源监控节逐点一致（orchestrator 批准+运行监视+MEMFAIL 8G+贴线
   方差注记），定向轮常跑口径一致。
5. **零源码红线**：01/03/04/05 负证 AC（`git diff --stat/--name-only` 面）可机检；
   02 唯一例外半径见 E1。c573087 实证为 M2-10-06 typed 门 commit，窗口语义见 m6。
6. **对账**：2955/16/0 基线实证（M2-10-07-SUMMARY :12 `TOTAL|2955/16/0|1019s`）；
   estimated_tests 合计 8..14 与任务书 +8..13 相符（01 可选 +1）；PERF-07 复核口径
   （0.490s 带内即过 + 终轮随跑 + 测试名/bundle 实证 Perf07MassApplyTests:147 SESS）
   成立——skip 口径修正见 E3。
7. **goal-backward**：M2PERF-01 七门逐条有任务集（PERF-01→02 T1/T2/T3；PERF-02→04；
   PERF-03→02 T6；PERF-04→02 T6+05 补；PERF-05→02 T4；PERF-06→02 T5+05 KD-2.2；
   PERF-07→05 T2）；M2PERF-02 → 05 全链（终验+机械扫+挂账汇编+INPUT→C3 停→翻账五处
   +VALIDATION）。E2 修复后「M2 closed」可推出；翻账五文件均存在（STATE/TODO/
   GOAL-STATE/REQUIREMENTS/ROADMAP 实测在位）。

## 数字锚点亲核记录（誊录无误项）

4.8ms/85.7ms/57 趟（05 perf SC#4 :20-21）、cold 117/warm 85（M2-6-3-SUMMARY :49-51）、
0.11s/2.62s/0.166s/2.08s（13 perf :10/:16/:18/:28）、tier A 10.6ms / tier B 2.87s /
PERF-07 0.490s（09 perf :67/:103/:135）、SPIKE 7865/5913/4589/8G（M2-4-0-SPIKE
:22/:59/:60/:62/:114）、D-05-08-T6-1（05-08-DECISIONS :101）、TerminalTailPolicy
（PixelPipe :1187）、LayerCompositeDriver terminalTail 传点（:204）、DrtTailTests 两命中
场景（:304/:318，misses==2/hits==1 与 KD-2 引用逐字一致）、enforceBudget 阈值注入面
（PipeCache :210-215）、testPhase5DragGateTwoChains / testNLMeansPreviewDowngradeTiers /
testFullToneEqualMemoryBudget / testPreviewFullChainFrameTime（PreviewChainPerfTests
:410/:213/:178/:76）——各 plan 规格锚点与实况一致。
