# M6-5-01 SUMMARY（挂账清算批执行摘要，2026-10-16）

> 执行批 = ZCode executor（夜间全自动授权链 D-07-3-T5-1，晨审可推翻）。
> plan = 修订版 `M6-5-01-PLAN.md`（起跑 HEAD = `62a7ca30`，含 `2f88907a`）。
> 裁定与事故正本 = `M6-5-01-DECISIONS.md`（本文件只留指针）。

## 一、结论头

**九任务全交付 / 全套确认轮 TOTAL = 3848/24/0（exit 0 + 0 MEMFAIL + 七
bundle 全 8G 门内，2099s）= 对账式 3841（M6-4 实测）+ 2（M6-4 修批）+
5（本批）精确命中；轮毕孤儿复扫零命中（T1 终证）。**

## 二、逐任务记账（commit 链 + ΔN）

| 任务 | commit | 交付面 | 定向轮 | ΔN |
|---|---|---|---|---|
| T1 孤儿 fixture 根治 | `c749ee00` | RasterEditFaceTests restore+undo 双写腿 `tempFixtureCopy` 化 + `loadRaster(at:)` 孪生 + 头注 #6 终局注记（E-1 归因勘误落位） | App `RasterEditFaceTests` **7/0/0** + Export `RasterRoundTripTests` **3/0/0** + 轮毕 `find Tests/Fixtures -name "*.lra"` 零命中 + Fixtures 零新增 untracked | 0 |
| T2 12 字段携带 | `bd81f859` | `SessionBatchApplier` 既有档臂 `CarriedDocumentState` 12 字段捕获 + 构造点 12 参（process 盖章纪律零触）+ 4 回归法 + M6-2 VALIDATION 挂账 #2 对表补记（纯追加） | Sessions `SessionBatchApplierTests` **17/0/0**（13 旧 + 4 新） | **+4** |
| T3 头注 19→20 | `71dbd371` | McpServerController 两处 20-tool + 6 editing 算术 + 两测试文件同族注释；机检 = `19-tool` 全仓零命中 / `5 editing` 零命中 / 纯注释 diff | （零测试面） | 0 |
| T4 行序方向断言 | `76729922` | ExportGainMapTests +1 法（非均匀增益 × 非对称 base；四重方向断言，D-3） | Export `ExportGainMapTests` **26/0/0**（25 旧 + 1 新；M-2 订正计数亲证） | **+1** |
| T5 门③注记 | `c651bb51` | ExportRecipe 门③ + ExportRenderer 装配点 API-consumer 契约注记（纯注释，编译 exit 0） | （零测试面） | 0 |
| T6 V16 + 三键 | `0ebdd3c1` | zh-audit V16 断言 5（同行 + 1c 续行提取 / 报告 [5] 节 / self-test golden 红绿负测）+ 三格式变体键尾块纯插入（51/0）+ AGENTS M6-5 节登记 | `--self-test` PASS；`--check` PASS（1926 键 / 30 interp 键全 PRESENT / ABSENT 零命中） | 0 |
| T7 Manual-Only 汇编 | （不入 git，L073 口径） | `.work/gui-acceptance/m6-5/MANIFEST.md`——18 GUI 行 + 1 perf 观察行（P1 bake 生产耗时），逐行来源指针 + 供件 + 观测；「本批不执行」头注 | （零执行申报） | 0 |
| T8 V2 九项登记 | `9bdeb467` | V2-PROPOSAL「七、」九项（各带一级标题 + 来源锚 + 触发条件 + 规模 + 一句话；C1 触发条款与 M6-2 VALIDATION :104 同文〔grep 双侧 1:1〕+ DECISIONS §6 四件套镜像含 ② 完整形；登记 ≠ 立项头注） | （纯 doc） | 0 |
| T9 确认轮 + 收口 | （本 commit） | 全套 `--all` + SUMMARY/DECISIONS/AGENTS 终值/TODO/GOAL-STATE | **TOTAL 3848/24/0**（见 §三） | — |

**ΔN 合计 = +5（T2 +4 / T4 +1）**；`tuist generate` 未需（零新测试文件，
Project.swift 全零 diff——T9 action 1 判定落位）。

## 三、T9 全套确认轮（批准 = orchestrator 本 prompt；8G 门监视在案）

```
BUNDLE|IOP|686/1/0|peakRSS=7560MB|435s
BUNDLE|IOPParity|460/3/0|peakRSS=7242MB|760s
BUNDLE|Layers|494/4/0|peakRSS=1164MB|158s
BUNDLE|Library|729/4/0|peakRSS=624MB|78s
BUNDLE|Sessions|284/4/0|peakRSS=1403MB|71s
BUNDLE|Export|379/4/0|peakRSS=5340MB|204s
BUNDLE|App|816/4/0|peakRSS=2832MB|393s
TOTAL|3848/24/0|2099s    exit 0 / MEMFAIL 0
```

- **对账**：3848 = 3841（M6-4 实测）+ 2（M6-4 修批）+ 5（本批）**精确**；
  核销带 3843〔推算〕+ ΔN 5 同值。异常形态（ΔN=0）未出现。
- 7 bundle 峰值 RSS 全 <8192MB（贴线族 IOP 7560 / IOPParity 7242，均在
  ±3% 方差注记带内）；MEMFAIL 机检零命中；运行中监视采样 7 次（宿主
  286MB..3317MB 区间，无 >8G / 无压力转红）。
- **轮毕孤儿复扫**：`find Tests/Fixtures -name "*.lra"` 零命中 + Fixtures
  零 untracked（T1 根治终证；全套轮后复扫 = I-1 处置后二进制真跑）。
- transcript 正本 = `evidence/t9-all-run.log`。

## 四、T6 分诊 transcript（V16 首跑重建，30 调用点 / 30 独立键）

- **清偿前**：27 PRESENT + **3 ABSENT**（`edr_headroom_label`
  〔EDRControlView.swift:46〕/ `settings_displays_overridden`
  〔SettingsPages.swift:1191〕/ `softproof_active_label`
  〔SoftProofControlView.swift:82〕）——与 fixer 预扫逐键一致；实况 =
  裸键值内含 `%@` 格式串、变体键缺席（D-4）。
- **清偿后**：30/30 全 PRESENT，`--check` PASS（1926 键）。
- 1c 续行面三键（`toast_import_partial` / `toast_hdr_merge_failed` /
  `toast_hdr_merge_done`，LightamerApp.swift:943/:1103/:2019）全 PRESENT。
- 存档 = `evidence/t6-v16-postclearing-report.txt`（逐键 PRESENT/ABSENT +
  路径）。**后续批红线电池引用 = `zh-audit --check` 断言 5 ABSENT 零命中。**

## 五、挂账闭合对表（CONTEXT §1 盘点 40 项 → 终局态）

> 四态词表：**清偿**（本批修，机检在案）/ **转V2**（V2-PROPOSAL §七 登记，
> `9bdeb467`）/ **Manual-Only**（m6-5 MANIFEST 汇编行，行号 = 汇编表 #）/
> **销账**（证据在案零动作）/ **留置**（归他站在案零动作）。

| 项 | 终局态 | 证据指针 |
|---|---|---|
| A1 孤儿 fixture（M4-1 #6 延续） | **清偿 T1** ✅ | `c749ee00` + T9 复扫零命中 |
| A2 film-leg P1 竞态 | **销账**（维持） | `7bc6365` + 后继五轮全套绿（本批 T9 第六轮绿佐证） |
| A3 G3 自然样张目测 | **Manual-Only** | 汇编行 #1 |
| A4 bake 生产耗时 | **Manual-Only**（perf 观察行） | 汇编行 P1 |
| A5 修复后全套复跑轮 | **销账**（维持） | M5-3..M6-4 五轮全套绿 + 本批 3848 第六轮 |
| A6 G2 双面门交越界 | **Manual-Only**（观察行） | 汇编行 #2 |
| A7 o-2 Colormatch 收窄 | **销账**（维持） | M6-1 `5ff6ff48`（本批复核维持） |
| A8 omp-03 §3.1 追色点击 | **Manual-Only**（排查行） | 汇编行 #3 |
| A9 Tooltip SIGBUS | **留置**（L057-B） | AGENTS L057 节 + 汇编执行纪律注记 |
| A10 三观察行 | **Manual-Only** | 汇编行 #4 |
| A11 MCP 多参考 + preset | **转V2** | V2 §七 #1 TRACK-MULTIREF |
| A12 lut3d add 行 | **留置**（维持 M5-1 原判） | CONTEXT §7 边界 |
| A13 头注 19→20 | **清偿 T3** ✅ | `71dbd371` + 机检零命中 |
| A14 G6 余行 1/3/4 | **Manual-Only** | 汇编行 #5/#6/#7 |
| A15 Release 直启注入链 | **转V2** | V2 §七 #2 RELEASE-DIRECT-INJECT |
| A16 贴线族 RSS 观察 | **留置**（AGENTS 口径） | T9 实测 7560/7242 门内佐证 |
| A17 G6 余行 2/3/5 + 行 4 屏面 | **Manual-Only** | 汇编行 #8/#9/#10/#11 |
| A18 全景 V2 五件 | **转V2** | V2 §七 #3 PANO-V2 |
| A19 pano perf 观察 | **留置**（perf.md） | M5-3 perf.md 在案 |
| A20 瘦身手术二次触发 | **留置**（主会话专属） | 范围外指针维持 |
| B1 M6-1 C 行终端目测 | **Manual-Only** | 汇编行 #12 |
| B2 孤儿 fixture（M6-1 版） | **清偿 T1**（同条） ✅ | 同 A1 |
| B3 legacy 只读回退面 | **转V2** | V2 §七 #4 SESSION-LEGACY-READONLY |
| B4 move TOCTOU | **销账**（原裁零动作终局） | M6-1 原裁 + `908526fe` 在案 |
| C1 coordinator 接线四件 | **转V2**（触发条件档） | V2 §七 #5 PROCESS-WIRING（触发条款同文机检过） |
| C2 batch apply 字段丢弃 | **清偿 T2** ✅ | `bd81f859`（12 字段全带 = E-2 扩面终局）+ M6-2 VALIDATION 对表补记 |
| C3 孤儿 fixture（M6-2 版） | **清偿 T1**（同条） ✅ | 同 A1 |
| C4 skip-quirk 销账留痕 | **销账**（留痕维持不复活） | M6-2 §4 + 本批复核零复活 |
| D1 EXIF 注入器批 | **转V2** | V2 §七 #6 ULTRAHDR-EXIF |
| D2 行序方向断言 | **清偿 T4** ✅ | `76729922`（26/0/0） |
| D3 gain map DPI | **销账**（登记零动作终局） | M6-3 原裁在案 |
| D4 门③载体分叉注记 | **清偿 T5** ✅ | `c651bb51` |
| D5 跨生态目检 | **Manual-Only** | 汇编行 #13/#14 |
| E1 栈顶顶替 + 口径分裂 | **转V2** | V2 §七 #7 STACKS-SEMANTICS |
| E2 GUI 轮 M-1..M-4 + plan01 五行 | **Manual-Only** | 汇编行 #15/#16 |
| E3 D-06/D-07 补录义务 | **Manual-Only**（补录义务行） | 汇编行 #17 |
| E4 SAM CoreML | **转V2** | V2 §七 #8 SAM-COREML |
| E5 livePlane 残差两笔 | **转V2** | V2 §七 #9 PATCH-LIVEPLANE |
| E6 M6-1 四项核查义务 | **销账**（义务已履行→B1..B4 逐条承接） | 本表 B 组 |
| F1 格式键插值机检盲区 | **清偿 T6** ✅ | `0ebdd3c1`（V16 断言 5 常设门） |
| 〔rider〕M4-3 深边界糊 | **Manual-Only** | 汇编行 #18 |

**40 项 + rider 全部闭合：清偿 6 任务 ✅ / 转 V2 9 项 ✅ / Manual-Only 11 项
→ 汇编 19 行 ✅ / 销账 7 项（A2 A5 A7 B4 C4 D3 E6，证据维持）✅ / 留置 5 项
（A9 A12 A16 A19 A20）✅。**（R-2 妆饰计数滑差以 §1 逐项表为准，本表即
逐项表对账。）**

## 六、偏差与事故（详版 = DECISIONS）

- D-1 E-1 归因勘误落位（undo 法 = 真残写源）。
- D-2 T2「nil 档不落键」→ typed-nil 断言（五元数据 wire 恒写 null）。
- D-3 T4 单向方向断言 + aux 读回 top-down 取向实测定格。
- D-4 T6 三活体键实况 = 裸键值承载格式串。
- D-5 T8 触发条款换行断裂 → amend 自纠。
- **I-1 陈旧二进制假绿事故**：test-direct.sh 前置构建步（build-for-testing）
  首轮漏执行 → Sessions 13 = 旧集暴露；重建后三 bundle 全复跑，假绿数字
  未入任何 commit；**LESSONS 候选交翻账批**（「测试命令序列 =
  build-for-testing → test-direct.sh」）。

## 七、翻账申报（建议翻账点；本批不做——闭环批统一）

1. **VALIDATION 面**：M6-5 双重验收（zcode 独立眼 + omp 二次验收，串行）→
   `M6-5-VALIDATION.md` 签核；输入 = 本 SUMMARY §五对表 + DECISIONS。
2. **ROADMAP §M6-5 行 ✅**：随 VALIDATION 批（本批未触 ROADMAP）。
3. **STATE.md**：M6-5 段落账随 VALIDATION 批。
4. **TODO M6-5 条目**：本批已翻 [x]（执行 + 收口完成；VALIDATION 待批
   注记随行）。
5. **LESSONS**：I-1 候选条目（DECISIONS §3 文本可直接录用）。
6. **下一 phase**：M6-6（FEATURE-MAP ID 化 + CI 对账门 + M6 VALIDATION
   收口）。

## 八、红线终检（T9 收口核对，全绿）

- `LightamerIOP/` 全域零 diff ✅ / 全部 `*.metal` 零 diff ✅ /
  `LightamerSidecar.swift` 零 diff ✅ / `Pipe/History/` + `PipeCacheKey.swift`
  零 diff ✅ / V50Order 零触 ✅。
- MCP 快照族零 diff（T3 触两测试文件注释行 = red_lines 明文豁免形）✅。
- Export 六格式矩阵面（ExportFormatSpec/ImageIOEncoders/WebPEncoder）零
  diff ✅ / `Project.swift` 全零 diff（零新 SPM + 零新测试文件）✅。
- `*.xcstrings` 除 T6 三键尾块纯插入（51/0）外零 diff ✅ / UserDefaults 零
  新键 ✅ / `\.runModal(` App/Sources 零命中 ✅ / `String.LocalizationValue("
  ` 插值禁形代码零命中（:2061 命中为既有注释行，非代码）✅ /
  **zh-audit V16 断言 5 ABSENT 零命中（`--check` PASS）** ✅。
- 工作树 untracked 仅三件**批前既有** `.work` 面（`m3-1-w1/` acceptance、
  `m3-4-latitude/retro-dual` 脚本、`research/dt-clone-archive/`——起跑
  `git status` 亲证在先，非本批产物）；`Tests/Fixtures` 零 untracked ✅
  （孤儿 fixture 复扫零命中 = 唯一允许「无残留」态达成）。
