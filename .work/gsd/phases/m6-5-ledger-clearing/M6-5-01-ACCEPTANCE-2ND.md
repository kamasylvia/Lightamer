# M6-5-01 ACCEPTANCE-2ND（第二路独立验收，2026-10-15）

> 验收身份 = zcode 第二路独立 subagent（零共享上下文，替代 omp 制度位；
> 不轻信第一路，逐条独立实测）。输入 = 修订版 PLAN + CONTEXT + CHECKER +
> SUMMARY + DECISIONS + 第一路 ACCEPTANCE + 执行链 `c749ee00..7c0d2bbb`
>（8 commits）。夜间全自动授权链（D-07-3-T5-1），晨审可推翻。
>
> **结论头：PASS / 0 error + 1 minor（minor-1 = 第一路 I-1 残留项维持，
> 位置勘误：DECISIONS 残留仅 1 处非「两处」）+ 新观察两项（N-1/N-2，
> 均非本批引入不阻塞）+ 继承观察复核（O-1..O-3 成立）。**
>
> 全套独立复跑 **TOTAL 3848/24/0**（exit 0 + 0 MEMFAIL + 七 bundle 全 8G
> 门内，2096s）与执行方/第一路申报逐值一致；六清偿项独立亲测全过；40 项
> 终局表错开抽样（V2 九项全抽 + Manual-Only 19 行全对）闭合；I-1 链条亲证
>（第一路 minor-1 成立，位点清单订正）。

---

## 一、全套独立复跑（亲跑，非转抄）

**构建新鲜度先行（I-1 教训兑现）**：`caffeinate -dis xcodebuild
build-for-testing -workspace Lightamer.xcworkspace -scheme Lightamer
-destination 'platform=macOS'` → **exit 0 + TEST BUILD SUCCEEDED +
0 warning/error**（log = /tmp/m6-5-2nd/build.log）。产物考古：七 .xctest
mtime = 执行方 I-1 后重建批（04:04）、宿主与资源 = 第一路 build 批
（05:04）、本次构建增量 up-to-date 判定 = 产物与 HEAD（`7c0d2bbb`）源树
一致。O-3 式资源抽验：构建产物 en/zh `Localizable.strings`（plutil 提取）
含 T6 三键裸键 + `%@` 变体全六形态——第一路 O-3 描述的资源时效缝在我方
构建后不存在。

```
BUNDLE|IOP|686/1/0|peakRSS=7511MB|424s|sampling=time
BUNDLE|IOPParity|460/3/0|peakRSS=6784MB|769s|sampling=time
BUNDLE|Layers|494/4/0|peakRSS=1174MB|166s|sampling=time
BUNDLE|Library|729/4/0|peakRSS=622MB|76s|sampling=time
BUNDLE|Sessions|284/4/0|peakRSS=1628MB|71s|sampling=time
BUNDLE|Export|379/4/0|peakRSS=6379MB|204s|sampling=time
BUNDLE|App|816/4/0|peakRSS=2832MB|386s|sampling=time
TOTAL|3848/24/0|2096s   OK (direct launch, no testmanagerd)  exit 0
```

- **对账**：3848 = 3841（M6-4 实测）+ 2（M6-4 修批）+ 5（本批 T2 +4 /
  T4 +1）精确；和式手核 686+460+494+729+284+379+816 = 3848、skip
  1+3+4+4+4+4+4 = 24。执行链上游亲验：M6-4-02 双路 ACCEPTANCE 3841/24/0
  各自亲跑在案、M6-4-VALIDATION 修批算术链（3815→+2→3817→+24→3841→+2→
  3843 推算）逐环在档。异常形态（ΔN=0）未出现。
- 七 bundle 计数与执行方 T9 轮、第一路轮**逐值一致**；峰值 RSS 全 <8192MB
  （贴线族 IOP 7511 / IOPParity 6784，±3% 方差带内）；0 MEMFAIL；运行中
  监视采样多次（宿主最高 7511MB 贴线段，无 >8G、无压力转红）。
- L055 双保险：七 bundle 末条 Executed 行逐条亲读（686/460/494/729/284/
  379/816，全 0 failures）；脚本 no-total-line verdict（L055 修）未触发。
- **轮毕孤儿复扫（sleep 4s 过 debounce 窗）**：`find Tests/Fixtures -name
  "*.lra"` **零命中** + `git status` Tests/Fixtures 零 untracked——**T1
  根治在我方独立轮上终证**。
- 新测试真跑亲证（我方轮逐 bundle 日志）：T2 四新法 4/4 passed
  （Sessions log）、T1 双写腿法 2/2 passed（App log）、T4 新法 1/1 passed
  （Export log）。

## 二、五面独立审计

### 面 1 — T1/T2 修法面（数据保真视角）

- **T1**（`c749ee00` diff 全读）：`tempFixtureCopy` = `copyItem` 字节拷贝
  到 UUID tempDirectory（setUp 建/tearDown 清，DepthMaskEditingTests
  verbatim 同款）；restore 法 repo 侧防御 removeItem + 入口前清/defer 改
  指 tmp sidecarURL；undo 法 `tempFixtureCopy` + `loadRaster(at:)` URL
  孪生（与 name 形逐行对照 = decode+load 直通，仅 URL 来源不同；断言面
  carrier-only 与路径无关——CHECKER 2.1 判定独立复证）。写腿全集独立
  复扫：全 Tests 域 recordDrtChange/flush 写腿仅此两法。
- **T2**（`bd81f859` diff 全读）：`CarriedDocumentState` 12 字段捕获 +
  构造点 12 参显式传入；**独立对表 `LightamerSidecar` 全字段面 = 9 结构性
  （:250-288）+ 12 optional（五元数据 :293-309 + 七 additive :317-365）+
  process（:377），无第十三字段**（layerStack :288 = paste 语义所有物，
  `PasteSemantics.paste` 自有——独立复证 CHECKER 2.2）。四新法亲读：
  12 字段正测走盘上 decode 真路径（writeTwelveFieldSidecar encode→write→
  compose 内 `Data(contentsOf:)`+decode）、pristine 负测、rating=3 保真 +
  typed-nil、层级 keywords 逐元素。
- **D-2 线格式申报源码亲证**：`LightamerSidecar.encode` 五元数据 = if-let
  `encode`/else `encodeNil` **恒写形**（nil → 显式 null 键），七 additive =
  `encodeIfPresent`（nil → 键缺席）——plan「nil 档不落键」对五元数据确实
  不可达，typed 层断言是诚实形。
- **字节面抽验（任务书指定一项）**：pristine 臂 `carried = nil` → 12 参
  全走 init 缺省 `= nil`（init :422-429 亲读）→ 构造文档逐字段同旧形 →
  encode 字节面恒同；Sessions bundle 的 Sidecar 字节 golden 族
  （SidecarV7Tests byte-exact 往返 + V5/V8/V10/MetadataV3 等 13 文件）
  我方轮全绿 = 字节零漂移运行时背书。

### 面 2 — T6 V16 面（独立读码）

- **self-test 非永真（任务书疑点证伪）**：`run_selftest` 的 BAD fixture
  以 `selftest_novariant`（目录无变体）真实驱动红例——断言 5 若空转，
  「A5 interp key w/o catalog variant flagged」检查即 FAIL；红绿双例 +
  `audit()`/`scan_source()` 与产线同一函数 + allowlist/合计口径检查在册。
  **非永真**。
- **提取器状态机独立读码——两形态盲区（树内活体扫描定性）**：
  1. **`String(` 与 `localized: "K \(` 跨行形态**（`String(\n localized:
     "K \(x)")`）——同行 regex 要求 `String(localized:` 同行、PENDING 要求
     上行以 `localized:` 结尾、LEAD 要求键行以引号开头，三 regex 全不
     命中。**树内活体 3 处**（LCRSettingsModel.swift :177-178/:215-216/
     :225-226，`settings_lcr_probe_worker_unavailable/download_failed/
     remove_failed`）——**变体恰在册 + 编译产物亲验含 `K %@`**，运行时
     无缺陷，门盲区为潜伏态。
  2. **SwiftUI `Text("K \(x)")` 族**（LocalizedStringKey 插值，构建期
     提取键同为 `K <spec>` 变体）——不在断言 5 门内（INTERP_PREFIX_RE 只
     喂断言 2 族覆盖）。树内 11 处，其中 3 处真 ABSENT 活体（见 §三 N-1）。
  - KEY_SHAPE 小写偏置（CHECKER R-3）与 V15 同盲区，维持观察口径。

### 面 3 — 40 项终局表（错开抽样：V2 九项全抽 + Manual-Only 全对）

- **V2 §七 九项全抽**（一级标题/来源锚/触发条件/规模/一句话结构齐；
  措辞与 CONTEXT §5 逐项对上）：#1 TRACK-MULTIREF / #2 RELEASE-DIRECT-
  INJECT / #3 PANO-V2（五件齐）/ #4 SESSION-LEGACY-READONLY / #5
  PROCESS-WIRING / #6 ULTRAHDR-EXIF / #7 STACKS-SEMANTICS / #8 SAM-COREML
  / #9 PATCH-LIVEPLANE。**C1 触发条款同文机检亲跑**：grep「首个真实 iop
  语义分叉/bump 批触发时四件同批」双侧（M6-2-VALIDATION :104 vs V2 §七
  #5）各 1 命中；四件套 ①..④ 与 M6-2-01-DECISIONS §6 逐条镜像含②完整形
  `RenderProcess.resolving(piece.renderProcess)`。「登记 ≠ 立项」头注在册。
- **Manual-Only 19 行逐行可对**：18 GUI 行 + 1 perf 行（P1 bake）；
  11 分类项→行映射（A3→#1 / A6→#2 / A8→#3 / A10→#4 / A14→#5-7 /
  A17→#8-11 / B1→#12 / D5→#13-14 / E2→#15-16 / E3→#17 / rider→#18 /
  A4→P1）逐行亲对；每行配方指针 + 前置供件 + 预期观测齐备；「本批不执行」
  头注 + L057-B 纪律注记（A9 落位）在册。
- **销账/留置抽验**（与第一路全核错开）：A19（m5-3 perf.md :76/:86
  +388MB/band 行亲见）/ A12（CONTEXT §7 边界维持）/ A16（AGENTS ±3% 口径
  行）/ A20（范围外指针）/ A9（MANIFEST 执行纪律注记）；销账抽 C4
  （M6-2-VALIDATION :127 第二路证伪留痕原文）/ D3（M6-3-VALIDATION :117
  + :235 DPI 登记零动作）——证据链亲见成立。
- 结构亲数：40 项 + rider = 清偿 6 任务 + 转 V2 9 + Manual-Only 11→19 行
  + 销账 7 + 留置 5，闭合无孤儿。

### 面 4 — I-1 链条（第一路 minor-1 独立复核）

- **`bd81f859` message 亲读**：Verified 行 = 「targeted Sessions
  SessionBatchApplierTests **13/0/0 (9 existing incl. the three-state
  process test + 4 new)**」——commit 时刻 03:56:42 早于重建（04:04 产物
  mtime），该数只可能出自陈旧首轮。「9 existing + 4 new」= 13 拆解两头
  皆错（真旧集 13、fresh 总数 17）。**第一路 minor-1 实质成立（亲证）**。
- **残留位点全数（任务书问「有无第三处」）**：
  1. `bd81f859` commit message Verified 行——不可变历史，勘误正本落
     VALIDATION（不 rebase 重写：8-commit 链重写代价与收益倒挂，账面
     订正是对衡，且有 M6-3 第二路 minor-1 由闭环批逐行改数清偿的先例——
     **修法妥当**）。
  2. `M6-5-01-DECISIONS.md` :89「Sessions 17/0/0（9 旧+4 新）」——
     **全仓 grep 证实仅此 1 处**（第一路「两处」为计数滑差，其引文即同
     一行）。
  3. `DECISIONS` :82「Sessions 13/0/0」= I-1 §3「经过」段对首轮假绿事实
     的诚实记录，**应保留非残留**；SUMMARY §二「13 旧 + 4 新」为正确形；
     AGENTS/TODO/GOAL-STATE/evidence log 零残留命中。**无第三处**。
- 附注（第一路 O-2 复核成立）：`c749ee00` message Verified 行 7/0/0 出自
  陈旧首轮但值恰同 fresh（T1 零新增），provenance 注记级。
- **第一路修复清单（ACCEPTANCE §四）可执行性**：方向正确、落点
  （M6-5-VALIDATION 勘误正本节）在途可行；执行时按本节订正——「两处」
  改「一处（DECISIONS :89）」，勿把滑差复制进 VALIDATION。

### 面 5 — 偏差六项独立复核（DECISIONS §4）

| # | 偏差 | 我方独立复核 | 裁决 |
|---|---|---|---|
| 1 | T2 typed-nil 断言 | encode 面恒写 null 源码亲证（面 1） | ACCEPT |
| 2 | T4 取向执行期定格 | plan T4 action 2 明文授权「断言形式执行时择稳」亲见；四重断言本体亲读（①GainMapMin/Max ±0.4 取向无关锚 ②top-down 带均值 <64/>192 ③带差 >128 ④锚映射语义增益 ±0.45），反置面 ①..④ 全数触红推演成立 + log2(HDR/base) 增益数学亲验——门语义不损 | ACCEPT |
| 3 | T6 裸键值即格式串 | 目录三裸键值含 %@ 亲验（D-4 描述属实）；清偿路线 = plan 指定变体键路线未变 | ACCEPT |
| 4 | T8 换行断裂 amend | 终 commit `9bdeb467` 同文机检双侧 1:1 我方亲跑 | ACCEPT |
| 5 | I-1 | 实质 ACCEPT + minor-1 维持（面 4，位置清单订正） | ACCEPT+订正 |
| 6 | T7 18+1 vs ~17 | 19 行逐行可对（面 3） | ACCEPT |

结构性偏差：零（执行链 18 文件与 plan files_modified 逐一对照零越界，
`git diff --name-only c749ee00^..7c0d2bbb` 亲列）。

## 三、独立发现（与第一路分歧 + 新观察）

- **N-1（新观察，存量缺陷非本批回归）**：`McpLauncherPanelView.swift`
  :225/:242/:246 三处 `Text("mcp_launcher_status_running \(pid)")` /
  `Text("mcp_launcher_done_writes \(writes)")` /
  `Text("mcp_launcher_exit_code \(code)")` ——LocalizedStringKey 插值
  运行时查表键 = `K %lld` 变体，目录与编译产物（en/zh `Localizable.strings`
  plutil 亲验）**只有裸键**（值本身即格式串，en/zh 双语在册）→ zh 运行时
  回退裸键观感（M2-9 F-2 家族活体）。同族正面样本
  `settings_catalogs_rebuild_progress %lld %lld` 在册恰证惯例是登变体、
  三键为漏登。批前既有溯源：调用点 = 14-4 时代 `3578a415`、键在
  `0ebdd3c1^` 已在册——**非本批引入、非 40 项盘点范围**。建议挂账：三键
  补 `%lld` 变体（S，T6 同款清偿路线）。
- **N-2（门覆盖声明限定）**：AGENTS M6-5 节「后续批红线电池引用 =
  `zh-audit --check` ABSENT 零命中」——该门只覆盖 `String(localized:`
  同行 + 1c 续行两形态；**Text 族与 `String(` 跨行族不设防**（N-1 即
  漏网活体）。V16 交付符合 plan（E-3 把门语义刻为 localized 插值键分诊），
  但红线引用句应加限定语，门扩展（Text 族 + 跨行族提取）列为机检硬化
  候选。LCR 三跨行键变体恰在册（潜伏非活体）。
- **与第一路分歧（唯一）**：minor-1 修复清单「DECISIONS §3 两处『9 旧』」
  —— 实为 1 处（:89）。第一路实质判定不受影响。
- **第一路观察项复核**：O-1（TODO 规划批段 R-2 妆饰滑差旧计数与 SUMMARY
  终局口径并存）成立 / O-2（c749ee00 Verified 行 provenance）成立 /
  O-3（资源时效）成立且已被我方新鲜构建覆盖消除。

## 四、红线族亲跑（全绿）

`LightamerIOP/` 全域 / 全部 `*.metal` / `LightamerSidecar.swift` /
`Pipe/History/` + `PipeCacheKey.swift` / Export 六格式矩阵三文件 /
`Project.swift`（零新 SPM + 零新测试文件）——`git diff c749ee00^..7c0d2bbb`
逐项空输出亲跑。`xcstrings` 51+/0-（恰 T6 三键尾块）；`\.runModal(` 批内
diff + 全 App/Sources 双零；`String.LocalizationValue("` 插值禁形零命中
（:2061 = 注释行、:433 = `+` 拼接既有代码非插值形，本批未触）；UserDefaults
零新键。zh-audit `--self-test` PASS + `--check` PASS（1682/1926/30 interp
键全 variant-PRESENT）+ fresh `--report` 与 evidence transcript **逐字节
一致**（我方 diff）。AGENTS M6-5 节 + TODO M6-5 [x] + GOAL-STATE 续接点
翻账落位亲见。

## 五、commit 清单（8 commits，逐一 diff 审过）

| commit | 任务 | 边界判定 |
|---|---|---|
| `c749ee00` | T1 双写腿 temp 化 | ✅ 单文件 additive+改法 |
| `bd81f859` | T2 12 字段 + 4 法 + M6-2 补记 | ✅ 三文件（message 含 minor-1 残留） |
| `71dbd371` | T3 头注 20-tool | ✅ 三文件纯注释 |
| `76729922` | T4 行序断言 | ✅ 测试单文件 +1 法 |
| `c651bb51` | T5 门③注记 | ✅ 两文件纯注释 |
| `0ebdd3c1` | T6 V16 + 三键 + AGENTS | ✅ 三文件；xcstrings 51+/0- |
| `9bdeb467` | T8 V2 九项 | ✅ 单文件纯追加节 |
| `7c0d2bbb` | T9 收口 | ✅ SUMMARY/DECISIONS/AGENTS/TODO/GOAL-STATE |

T7 MANIFEST local-only 不入 git（L073 口径）正确；工作树 untracked 仅
三件批前既有 `.work` 面 + 第一路 ACCEPTANCE 本身（零源码越界）。

## 六、结论

**PASS / 0 error + 1 minor（minor-1 维持：I-1「假绿未入任何 commit」申报
不实 + DECISIONS :89 残留；第一路修复清单计数滑差「两处→一处」以本报告
面 4 为订正正本）+ 新观察两项（N-1 mcp_launcher 三键 zh 回退活体〔存量，
建议挂账〕/ N-2 V16 门覆盖限定〔Text 族 + 跨行族〕）。**

九任务全交付 / 全套独立复跑 3848/24/0 逐值一致 / 六清偿亲测全过 / 40 项
终局错开抽验闭合 / 红线族全绿 / commit 边界零越界。N-1/N-2 不阻塞签核；
建议 VALIDATION 签核时：①落 minor-1 勘误正本（按面 4 订正清单）②N-1
挂账 + N-2 红线句限定语随签核批落账。
