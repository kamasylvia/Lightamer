# M6-3-CHECKER — M6-3-01 plan 修订版独立反向核报告（2026-10-13）

> Checker = 独立目标反向核（fixer 修订批 `56ea8461` 之后、以放行为目的的
> 第二顶帽子；与 fixer 共 worker 但本节按「只信源码与 CONTEXT/RESEARCH、
> 不信 fixer 自述」纪律执行——全部结论附 file:line 或 grep 证据）。对象 =
> 修订版 `M6-3-01-PLAN.md`（HEAD `56ea8461`）+ `M6-3-CONTEXT.md`（含增补
> 节 D-M6-3-7）+ `RESEARCH.md` + 源码亲核。评审正本 =
> `M6-3-01-PLAN-REVIEW.md`（其「定向复核 E1/E2/M1 四节」要求由本文 §二
> 兜住，另加全量 goal-backward）。

## 结论

**放行执行（C-1..C-5 五条微修已并入本批同 commit；无 error 级残留）**

- 五处修订（E1/E2/M1/M2/M4）+ S1-S4 全部落位且自我一致（§二逐项证据）；
  六项 OQ 生效值零改动亲核（§四.1）。
- 独立猎残抓到 **2 条机制缺口（C-2/C-3，minor）+ 3 条文本/账面（C-1/C-4/
  C-5）**——全部为修订引入或修订未闭合的缝隙，无一是原始 OQ/交付面缺陷；
  均已在本次 checker 批对 plan 原位修正（见 §三逐条「处置」），修正后
  重扫零残留。
- Phase goal 达成性：**成立**（§一）。SC 八条 → T1..T5 映射无缺口（§四.2）。

---

## 一、Goal-backward：修订版能否达成 phase goal

**Goal（CONTEXT Phase Goal 节）**：SDR base + HDR 增益层 JPEG 导出（ISO
21496-1 gain map）；验收形态 = spike 结论落档 ✓（已交付）+ 导出链集成
（六格式矩阵零改动红线）+ DRT-HDR/EDR 源图端到端。

1. **导出链集成**：variant 一字段 + validate 门 + encodeStage 一分支 +
   新文件 `ExportGainMapEncoder`（CONTEXT「范围与红线预告」正本）——修订版
   KD-1/KD-5/KD-4 恰为此形；四文件红线 + S3 五文件 + ExportICCStrip 本体 +
   ExportQueueContract 零 diff 机检族（纪律节 + AC#7）保证「零改动」可证。
2. **「DRT-HDR/EDR 源图端到端」读法勘定（门⑤ 语义自洽性）**：该句指**源侧**
   HDR 内容（线性面高光 >1.0）经 gain map 档端到端出片——capture 点在
   EOTF-box 前，线性面携带 >1.0 值与所选 encoding EOTF 无关，SDR encoding
   EOTF（sdrPiecewise/BT.1886 等）下端到端成立；门⑤收窄的是**输出编码维**
   （PQ/HLG base 容器 = M4 ALCE-02 DRT-HDR 面的领地，非 UltraHDR JPEG）。
   判：goal 不受阻，门⑤与 goal 语义自洽（CONTEXT 增补节「base 侧复现」
   理由与之一致）。
3. **零回归**：结构性（缺省参数/缺省 nil/additive 字段逐处「既有路径字节
   零变化」申报）+ 机检（git diff 文件级/hunk 清单级 + 非 gain-map 负测 +
   既有套件原样绿）双层，覆盖面完整（§四.3）。
4. **ALCE-03 解冻**：REQUIREMENTS 注记 + ROADMAP ✅ 在 T5 收口清单在位。

## 二、五处修订的自我一致性复验（含评审要求的 E1/E2/M1 定向复核）

### 2.1 门数 4→6 全文一致

- 证据：`grep -c "六门"` = 12 处（title/front-matter ExportRecipe 行/红线
  节/KD-1 标题与正文/KD-5 M4 句/KD-7 validate 组/T1 任务与验收/AC#1/checker
  关注点 7 等全部为「六门」口径）；`grep "四门"` 仅余 3 处**历史勘误注记**
  （E2 修订引文「原单调用位申报失实」语境、M1「token 复用作废」语境、
  M4 修订句已更正为「六门全过」）——无一处活口径残留。
- 门⑤/门⑥各有负测：KD-7 validate 组 6 法（门⑤ encoding 拒、门⑥ yiyin
  拒各一法）↔ AC#1 提及双门负测 ↔ T1 验收「validate 6」三角一致。
- plan 增补裁决节 ↔ CONTEXT「裁决增补（夜间授权批）」节交叉引用一致
  （门⑤ = D-M6-3-7，晨审可推翻 + 撤门三处回退路径双处同文）。

### 2.2 E2：9 hunk 清单 ↔ T1 验收 ↔ 机检口径一致

- 清单本体（KD-2）= 红线节 = front-matter（PixelPipe 行 7 hunk +
  LayerCompositeDriver 行 2 hunk 分列）= T1 验收「9 hunk 清单逐 hunk
  对照（PixelPipe 7 + LayerCompositeDriver 2）」= 纪律节零 diff 自证 =
  AC#7 = checker 关注点 3——七处同口径。
- **物理锚点逐个亲核**（本轮 HEAD 源码）：PixelPipe.swift `:155`
  （`tailFormatFloatOverride` 属性同位）/:2081/:2095（process 参数+赋值）/
  :2143/:2155（processComposite 参数+传递）/:1100（runDrtTailLeg tailPipe
  继承同位）/:1423-1596（processRec 走查体，upstream 解析先于 box 派发——
  cache 命中/未命中两臂皆可达）/:1756（EotfBox 全仓唯一构造点
  `DrtTailAssembly.instances` 内）；LayerCompositeDriver.swift `:205`
  （composite 参数同位）/:553-559（terminalPipe 装配窗，含「this pipe is
  built INSIDE the driver…the layered document's 常态」同缝注记原文）。
  **9/9 锚点命中**。
- 评审「~5 hunk 全在 PixelPipe.swift 内」与本清单 9 hunk 的 delta 已在
  KD-2 注记显式申报（composite 腿物理必需——layered 文档常态否则 capture
  静默失活，M4 guard 会把它变 fail-loud 但功能仍坏）；checker 判：按代码
  事实申报正确，delta 记录诚实。

### 2.3 M1：KD-3 新清理路径 ↔ ExportQueue actor 语义相容

- 源码事实复核：retry `:320-341` 确为 `seqCounter += 1; job.seq =
  seqCounter`（fresh seq 新 key，旧 seq 残面无覆盖语义）——KD-3 改写前提
  成立；`finish` :521 / `finishCancelled` :547 / `cancelAll` :280（generation
  换代）/ `execute` 门 :394（stale 出口）均为 actor 隔离方法，可同步触达
  actor 实例属性——「box 以实例属性持有 + 按 queued.seq 清理」与 actor
  语义相容（box 本体 final class + NSLock 非隔离载体，双腿闭包由
  `productionLegs` :581-638 静态装配共享同一实例，init :172 装配窗注入
  可执行）。
- 泄漏负测语义闭合：render 腿 stash 后 encode 腿 throw 的路径残面确在
  box（consume+clear 未达），finish/finishCancelled 清理路径恰好覆盖；
  retry 入队前清旧 seq 为幂等兜底（finish 已清则为 no-op）。

### 2.4 M4：fail-loud guard 一致

- KD-5 guard 表达式 ↔ KD-7 后处理门组 4 法（含 `gainMapHDR ∧
  hdrGainPlane=nil → typed 拒` 负测）↔ T2 验收 13 法（4+2+1+4+2）↔
  front-matter ExportRenderer 行——四处一致。机制前提亲证：capture 装配
  条件读 `drtTail`（TaskLocal 载体）而 validate 门② 读 `variant.drtOutput`，
  双写同源仅在 M2 页 `enqueueExportM2`（ExportState.swift:526-528）强制，
  直接构造 Request 路径确可分裂——guard 必要性成立。

### 2.5 M2 + 门⑤ UI：五维谓词 = validate 六门的 UI 子集（C-2/C-3 修正后）

- 逐门对表：门①format→维1 ✓ 门②drtOutput→维2（readout 在册）✓
  门③peak→维3 ✓ 门⑤encoding→维4 ✓ 门④embedICC→维5（C-3 补）✓
  门⑥yiyin→validate-only 显式注记（M2 页不可达）✓——「UI 可用但
  validate 拒」逐门排除。
- 复位触发 = 页内转态（embedICC/format/peak/encoding 门位）+ run-face
  复核兜底（C-2 补，覆盖 DRT 面板非页内变化）——矛盾态双入口全闭。

## 三、独立猎残（发现 → 处置）

| # | 级别 | 发现 | 证据 | 处置 |
|---|---|---|---|---|
| C-1 | 文本 | T1 验收「**前** 9 法」隐含文件内排列序，与 KD-7 分组序不符（box 泄漏组列于质量组之后，「前 9」按序会划进容器组） | KD-7 分组序 vs T1 原文 | 已修：改「validate 6 + capture 2 + box 泄漏 1 **共** 9 法（分组序见 KD-7，不依文件内排列序）」 |
| C-2 | minor 机制 | M2 复位规则原文「三处门位 setter」**漏非页内变化**——peak/encoding 由 DRT 面板改，Export 页无 setter 可挂；旗标残留 → run 时整批 typed 拒 = 规则自称闭环却未闭。orchestrator 指令原文明确含「peak 降档同复位」 | ExportInspectorView 无 peak setter（DRT 面板所有）；KD-6 原文 | 已修：KD-6 补 **run-face 复核兜底**——`makeRunAssembly` 装配前重算五维门，任一破坏 → 复位 + toast（即评审 M2 备选「run-gate 拦截」作为背书臂并入）；AC#5 同步 |
| C-3 | minor 机制 | **enable-under-broken-gate**：embedICC 原不在可用门谓词内——embedICC=false 时 checkbox 四维全过仍可**开启**（非转态，复位规则不触发）→ 门④ violated 状态直接成立 = M2 要排的矛盾态换了个入口复活 | KD-6 原谓词四维 vs validate 门④ | 已修：可用门补**第五维 `embedICC == true`**（禁用态复用 hint 文案，不新增键）；负测同法兼断禁用态；五维口径同步五处（front-matter×2/KD-7/T3/AC#5/checker 关注点 7） |
| C-4 | 账面 | plan 头锚点注记止于「HEAD `55eb8f3c` 亲核」，修订批新增锚点（productionLegs/retry fresh-seq/LayerCompositeDriver/processRec）的复核 HEAD 无登记 | plan 性质节 | 已修：补「修订批同日于 HEAD `56ea8461` 复核全部新增/改写锚点」 |
| C-5 | cosmetic | front-matter App 测试行复位负测括注「embedICC off / peak 降档」可读作两法，与 8 法计数（单一复位法）不符 | front-matter vs KD-7 | 已修：括注对齐「embedICC off → 旗标复位断言」 |

修正后重扫：`grep "四维|三处门位"` 零命中；测试计数 25+8=33 与
`estimated_tests "+28..34"`、全套 3753..3759（3725+33=3758 在带内）三角
一致；`grep "六门"` 无活口径漂移。

## 四、全量核对（goal-backward 余项）

### 4.1 OQ 生效值零改动亲核

CONTEXT 裁决记录 D-M6-3-1..6 六条原文与 plan「已定裁决」1..6 逐条对读：
生效值文本一致；增补节仅**追加**（D-M6-3-7 + 随录），无既有条目改写
（`git diff 207dcc58..56ea8461 -- M6-3-CONTEXT.md` 亲核：裁决记录节尾部
纯插入 + 状态节一行追加）。

### 4.2 SC 逐条 → 任务映射（八条 AC，无缺口）

AC#1 capture 点+门⑤⑥【T1/T3/T4】/ AC#2 EXIF probe 双态【T2】/ AC#3 hdrgm
+F5 门【T2】/ AC#4 单通道 aux【T2】/ AC#5 五维门 8 法【T3】/ AC#6 无新 tag
【T3/T4】/ AC#7 零回归机检族【T2/T4】/ AC#8 SC 数字【T5】——每条有落点
任务 + 可机检断言面；RESEARCH §7 六 OQ 在 plan 已定裁决节全数承载。

### 4.3 验收可机检性与依赖序

- AC 逐条机检形态：AC#1 grep（无第二渲染链）+ 负测 / AC#3 字节扫 / AC#4
  aux dict 断言 + `hdrGainMapAsRGB` grep / AC#6 grep + 既有 Namer 测试 /
  AC#7 git diff 文件级+hunk 级——无「不可机检却写成机检」项；UI 面
  （AC#5）走面板测试模型态断言（KD-6 机检缝）。
- 任务依赖：T1（variant/门/capture/box）→ T2（编码腿消费 T1 载体）→
  T3（UI，读 T1 variant 面）→ T4（全链 golden + 机检）→ T5（收口）——
  无环、无前向引用；App bundle 轮孤儿 fixture 预清理、`--all` 批准制、
  parentage 检查等纪律项在位。
- 遗留观察（不阻断）：①T3 与 T4 对 ExportState 零命中双断言 = 无害双
  保险；②`+28..34` 上限对 33 实际值余量 1——如执行中测试再分裂超 34，
  属 SC 偏差须 T5 对账登记（既有对账链兜住）。

### 4.4 与评审处置摘要的对账

评审三条处置：①一个修订批（E1/E2/M1/M2/M4/S1-S4）→ 全部落实（§二/§三）；
②M3 单独确认 → orchestrator 夜间授权批裁准 + CONTEXT D-M6-3-7 增补节
（非静默）→ 落实；③其余维持（CI 全服务路/box 交接/四文件红线/T1..T5/
SC 数字面/测试钉法主体）→ 修订批未触碰（diff 亲核仅动申报文本、门集、
生命周期、数字面与机检族）。

## 五、放行条件核验

- 两 commit 分立：`56ea8461`（plan 修订 + CONTEXT 增补）+ 本 commit
  （CHECKER + C-1..C-5 原位微修）——fixer/checker 产物可分辨。
- 不 push（L070）；ACCEPTANCE/SUMMARY 未创建（T5 产物，未越权）。
- 执行入口就绪：T1 read_first 2/4/5/6 锚点全亲核命中，可开工。
