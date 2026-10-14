---
phase: M6-5
slug: ledger-clearing
created: 2026-10-16
kind: research+plan 合批（清查规划 worker）
status: drafted
---

# M6-5 — 挂账清算批 CONTEXT（全挂账盘点 + 逐项分类裁定）

> **夜间全自动授权头注**：本清查批在夜间全自动授权链内执行（先例
> D-07-3-T5-1——用户显式「开跑，不要停」续指令 = 规划与清偿授权；
> M2-8..M6-4 各 VALIDATION 同款沿用）。**晨审可推翻**：推翻 = 本件分类
> 裁定作废回退，盘点证据不受影响。范围红线：瘦身手术第二次触发不在
> M6（主会话专属）；ALCE-02 维持 V2；零新 SPM。
>
> **输入正本（逐一读齐，禁凭记忆转述）**：`.work/TODO.md` M6-5 条 +
> M5 头部收官行；`phases/m5-1-track/M5-1-VALIDATION.md` 挂账总汇编 +
> `FILM-LEG-FIX.md` §4；`phases/m5-2-mertens/M5-2-VALIDATION.md` 挂账
> 汇编；`phases/m5-3-pano/M5-3-VALIDATION.md` 挂账汇编；
> `phases/m6-1-interop/M6-1-VALIDATION.md` 挂账总汇编（四项）；
> `phases/m6-2-process-version/M6-2-VALIDATION.md` 挂账总汇编（三项 +
> 销账留痕）；`phases/m6-3-ultrahdr/M6-3-VALIDATION.md` 挂账总汇编
> （五项）；`phases/m6-4-gallery-stacks/M6-4-VALIDATION.md` 挂账总汇编
> （六项）；`.work/gsd/REQUIREMENTS.md` parked/V2 区；
> `phases/v2-station/V2-PROPOSAL.md` 全文（登记措辞母版）。
> **代码现状核查锚均为 2026-10-16 工作树 HEAD 亲核**（file:line 见 §3）。

---

## §1 全挂账盘点表（逐项：来源 + 原文摘录 + 现状核查 + 分类）

分类词表：**清偿**（本批修，机检验收）/ **转V2**（登记 V2-PROPOSAL 挂账区）/
**Manual-Only**（汇编一张 MANIFEST 清单，不执行）/ **销账**（已被后续工作
顺带清偿或原裁零动作终局，证据在案）/ **留置**（归他站在案行，零动作）。

### A. M5 三 VALIDATION 挂账汇编

| # | 来源 | 原文摘录（缩写） | 现状核查 | 分类 |
|---|---|---|---|---|
| A1 | M5-1 + M6-1#2 + M6-2#3 | 孤儿 `Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`（M4-1 挂账 #6 延续；M5-1 曾宣告「收口」） | **仍活**：工作树 untracked（mtime 2026-10-15 02:35 = M6-4 验收全套轮再生）；M5-1 的 `7bc6365` 只 temp 化了 RasterRoundTripTests 写腿——真写腿 = `RasterEditFaceTests.testRestoreWinsOverDerive`（:173-190 在 repo fixture 路径驱动真实写腿 + `flushUntilPersisted`，defer 清扫输给迟到 write-behind） | **清偿 T1** |
| A2 | M5-1 批内收口 | M3-3 Film leg P1 竞态结构性根除（静态槽→显式传参，A/B decisive） | `7bc6365` 在库；其后 M5-3/M6-1/M6-2/M6-3/M6-4 五轮全套 0 fail 佐证无复发 | **销账** |
| A3 | M5-1 | Manual-Only 目测行：G3 自然样张目测 + before-after 目测 | 未执行（正本 `gui-acceptance/m5-1/MANIFEST.md` human rows） | **Manual-Only** |
| A4 | M5-1 | bake 生产耗时实测（Release 产物 WebP 嵌入怪癖未追） | 未测；Debug 295ms / -O ~1-3ms 探针带在册（M5-1-02） | **Manual-Only**（观察行） |
| A5 | M5-1 | 修复后全套 `--all` 全绿轮（film-leg 修复后 3477 对账亲证） | 已被后继五轮全套绿清偿（M5-3 3631/24/0 exit 0 + M6-1 3689 + M6-2 3725 + M6-3 3759 + M6-4 3841，全零 MEMFAIL） | **销账** |
| A6 | M5-1 | G2 双面门交越界（cbrt LMS≈0 交越导数无界 = f32 固有数学面；渲染观感亚毫级） | 机制面在册非缺陷；观察 = GUI 走查行 | **Manual-Only**（观察行） |
| A7 | M5-1 | o-2 `ColormatchResolverBox.shared` 裸静态收紧候选（V2 NSLock holder） | **已修**：M6-1 T8 `5ff6ff48` NSLock holder（`ColormatchModule.swift:84-103` 亲核：sharedLock + 锁内 getter + replaceShared）+ ColormatchResolverBoxTests 4 法 + 裸 `shared =` 全仓 0 | **销账** |
| A8 | M5-1 | omp-03 §3.1 面板追色点击无响应观察项（GUI 专项排查建议；omp-02 复验同面走通 = 概率性） | 未排查；配方在 omp-03 报告 §3 | **Manual-Only**（GUI 排查行） |
| A9 | M5-1 | omp-03 §6.2 Tooltip SIGBUS → L057-B 专项（不另立项） | L057-B 专项行在案（AGENTS L057 节 queue 行） | **留置**（归 L057-B） |
| A10 | M5-1 | o-ompre1 filmstrip 行点击不换图 / o-ompre3 菜单撤销一次回退两级 / o-omp1 Mask 页层行点击内容区空白 | 未走查（M2-2/D-H1 GUI 面观察项） | **Manual-Only**（观察行） |
| A11 | M5-1 | MCP 多参考 V1 缺口（单 reference/调用）+ preset 化（求解结果存 LUT 库条目） | 未动（OQ-6 v1 裁决字面）；需求驱动 | **转V2** |
| A12 | M5-1 | lut3d LUT 页无实例 add 行同族缺口（E-omp1 修复面仅 colormatch） | 现状亲核：`EditorAdjustmentStackView.swift:344` add 行 Menu 仅含 colormatch 单 Button；lut3d 有库 apply 既有产品路径 | **留置**（维持 M5-1 原裁定「既有产品形状不改」） |
| A13 | M5-1 | `McpServerController` 头注「frozen 19-tool set」陈旧（19→20，match_color 后） | **仍陈旧**：`McpServerController.swift:15` + `:447-449` 两处 19-tool 字样亲核 | **清偿 T3** |
| A14 | M5-2 | G6 Manual-Only 余行 1/3/4（Robertson02 对照合并 / deghost 三档对比〔需 enqueue 参数通道〕/ `_hdr` 并存分账） | 行 2/5 已 omp 回填；行 1/3/4 未执行 | **Manual-Only** |
| A15 | M5-2 | Release 直启注入链环境债（WebP 包 framework Debug 静态/Release 动态且未 embed；D-09-04-D9 配方不达——framework 未产出为根因） | perf.md §事故 4 在册；工具链债 | **转V2**（触发条件档） |
| A16 | M5-2 | IOP/IOPParity 贴线族 RSS 观察项（7657/7738MB ±3% 方差口径） | AGENTS 在案口径（连续 MEMFAIL 先查重测顺序漂移）；本批零动作 | **留置**（观察口径在案） |
| A17 | M5-3 | G6 Manual-Only 余行 2/3/5 + 行 4 屏面（需同视点扫幅样张） | 行 1 前段 + 行 4 log 面已 omp 回填；余行未执行 | **Manual-Only** |
| A18 | M5-3 | V2 挂账（OQ 裁决原文）：预览合成画布 / 参考帧手选 / use_edits / per-image 焦距（畸变/tilt）/ multiband 融合 | 未动（OQ-M5-3 裁决 V2 字面） | **转V2** |
| A19 | M5-3 | perf 观察项：融合段 freed-but-resident footprint 爬升（+388MB/band）+ Release `-O` 复测；越门 GPU 另立项 | perf.md 挂账观察区在案 | **留置**（perf.md 在案） |
| A20 | M5-3 | 「全史瘦身手术」第二次触发 → 主会话（strip 集重算非空才动手） | 主会话专属，非 M6-5 范围（ROADMAP 红线①） | **留置**（范围外指针） |

### B. M6-1 挂账四项

| # | 原文摘录 | 现状核查 | 分类 |
|---|---|---|---|
| B1 | Manual-Only C 行终端目测（无头 connect 指引终端目测未人驱；decode 级机检全覆盖） | 未人驱；`McpProjectArbitrationTests` 9 法在位 | **Manual-Only** |
| B2 | 孤儿 fixture 全套轮复活（M4-1 #6 仍活） | 同 A1（真写腿已定位） | **清偿 T1**（同条） |
| B3 | legacy 只读回退面缺席（ride-along 仅 typed 冲突 toast，无 GUI 只读回退；用户诉求出现时再裁） | `SessionCoordinator.swift:489` 仍仅 `session_lock_held` toast；legacy 面整体 env 门控 QA 通道（`LibraryPreferences.swift:31-36` `LIGHTAMER_LEGACY_LIBRARY`，默认隐藏）——用户可见面趋零 | **转V2**（需求驱动，维持 M6-1 范围裁定） |
| B4 | move 窗口锁短暂释放 + probe TOCTOU（M-OMP-4 修复后窗口收窄为可接受残留；flock 写腿仍精确仲裁） | M6-1 原裁「观察项，无动作」；`908526fe` create/move role 贯穿在库 | **销账**（原裁零动作终局，观察留痕） |

### C. M6-2 挂账三项 + 销账留痕

| # | 原文摘录 | 现状核查 | 分类 |
|---|---|---|---|
| C1 | coordinator 传值接线件 + 分叉消费件 + 迁移 UX 同批裁形（by-design 挂账；触发 = 首个真实 iop 语义 bump 批） | 生产零传值维持（M6-2 双路亲证）；触发条件在册（DECISIONS §6 四件套） | **转V2**（触发条件档登记；触发条款不变） |
| C2 | pre-M6-2 SessionBatchApplier 既有档臂字段丢弃缺口（`provenance`/`rawOverrides`/`displayTransform`/`versions`/`activeVersionID`/`aiProvenance`/`filmRecord` 静默丢弃） | **仍缺**：`SessionBatchApplier.swift:100-133` 既有档臂仅提 5 字段 + :149-163 全新档构造（M6-2 只补了 process 分支盖章，其余 additive 字段未携带，:104-109 注记自认） | **清偿 T2** |
| C3 | 孤儿 fixture 同源（M4-1 #6） | 同 A1 | **清偿 T1**（同条） |
| C4 | 〔销账留痕〕skip 21 vs 24「口径 quirk」候选条目不立 | M6-2 第二路证伪（段和 = 24 = TOTAL）；TODO/ROADMAP/STATE M6-5 区 grep 零命中（本批复核维持） | **销账**（留痕维持，不复活） |

### D. M6-3 挂账五项

| # | 原文摘录 | 现状核查 | 分类 |
|---|---|---|---|
| D1 | EXIF v1 无 EXIF → v2/EXIF APP1 注入器批（触发 = 用户/生态硬需求；禁自建 APP1 注入器 + LightCraft C 路同批评估） | 未动（by-design 降级预授权；Software 存活座位 = xmp:CreatorTool） | **转V2** |
| D2 | HDR/base 行序方向性断言缺失（`.oriented(.downMirrored)` :137 是增益空间对齐唯一承载；现有测试面均不抓垂直 flip）→ 建议补非 uniform HDR 面 + 非对称 base 方向性断言 | `ExportGainMapTests.swift` 24 法亲点：零行序/flip 断言（:720 direction = 增益值方向非行序） | **清偿 T4** |
| D3 | gain map 臂不带 DPI 元数据（CI writeJPEGRepresentation 无 DPI 选项；UltraHDR 生态通例无用户可见面）——「登记即可，零动作」 | 原裁零动作在案 | **销账**（登记零动作终局） |
| D4 | 门③载体分叉残余 → API 消费者文档注记（render 侧读 `drtTail.record.peakLuminance` vs validate 门③查 `variant.drtOutput.peakLuminance`；全 UI 路不可达，纯 public-API 鲁棒性） | 未注记；锚 = `ExportRecipe.swift:158-191`（validate 门③）+ `ExportRenderer.swift:519`（render 侧 headroom 取值点） | **清偿 T5**（纯注记） |
| D5 | Manual-Only 跨生态目检（Preview/Photos/Chrome/Android 13+/LightCraft 互读；可选行不阻断） | 未执行；配方 = `gui-acceptance/m6-3/MANIFEST.md` | **Manual-Only**（可选行） |

### E. M6-4 挂账六项

| # | 原文摘录 | 现状核查 | 分类 |
|---|---|---|---|
| E1 | 栈顶被滤「首可见成员顶替」+ `overviewCount`/`groupCounts` 口径分裂 → V2 语义腿候选（01 D-06 同条） | 未动（D-06 登记在案） | **转V2** |
| E2 | GUI 轮 M-1..M-4（真图 patch / 多人实例 / 无人像 typed toast〔须真无人像照片〕/ 羽化三档）+ plan01 侧徽章/dialog/菜单五行；layer B 资产引导下载前置 | 未执行；配方 = `gui-acceptance/m6-4/MANIFEST.md` | **Manual-Only** |
| E3 | D-06(02)/D-07(02) 实测申报随 GUI 轮补录（layer B ROI 分辨率 + person 标签编号域） | 未补录（待供件 = M-1/M-2 走查现场） | **Manual-Only**（补录义务行） |
| E4 | Describe 文本选择 → SAM CoreML 挂 V2（charter 裁决⑦；用户裁立项另开独立 phase） | 原生不可达收口在案；ModelAssetStore 安装链 + worker 第四腿已备 | **转V2** |
| E5 | livePlane 残差两笔（D-13 申报：①末次 pass 后切图平面驻留至其余释放点〔eager 释放需新横 wire〕②confirm 在飞切图 = 在飞竞态〔V2「patch pass 互斥锁」可消〕）；主修已闭环 `b49215bb` | 登记级在案；两残差零用户可见面 | **转V2**（登记级 + V2 钩子注记） |
| E6 | M6-1 挂账四项核查 = 未被顺带清偿全额转本批 | 核查义务已由 M6-4 VALIDATION 履行（读账四项全 open）→ 本件 B1-B4 逐条承接 | **销账**（核查义务已履行） |

### F. 顺带候选

| # | 原文摘录 | 现状核查 | 分类 |
|---|---|---|---|
| F1 | 01 N-3 格式键插值形态机检盲区（后续机检补 `String(localized: "…\(` 非格式键形态检查候选） | 红线机检族现仅查 `String.LocalizationValue("…\(` 禁形；`String(localized:` 插值形态无门 | **清偿 T6**（机检硬化，纯 doc + transcript） |

---

## §2 分类汇总

| 分类 | 项数 | 明细 |
|---|---|---|
| **清偿（本批修）** | 6 任务 | T1 孤儿 fixture 根治（A1+B2+C3 三源同条）/ T2 SessionBatchApplier 字段携带补齐（C2）/ T3 McpServerController 头注 19→20（A13）/ T4 HDR-base 行序方向性断言（D2）/ T5 门③载体分叉 API 注记（D4）/ T6 格式键插值形态机检硬化（F1） |
| **Manual-Only 汇编** | 1 任务 ~17 行 | A3 A4 A6 A8 A10 A14 A17 B1 D5 E2 E3（+ rider：M4-3 guided filter 深边界糊〔M4 收口面顺带汇编，非 charter 主清单〕） |
| **转 V2 登记** | 1 任务 9 项 | A11 A15 A18 B3 C1 D1 E1 E4 E5 |
| **销账** | 6 项 | A2 A5 A7 B4 C4 D3（+E6 核查义务履行） |
| **留置（零动作/归他站）** | 6 项 | A9（L057-B 专项行）A12（维持原判）A16（AGENTS 口径）A19（perf.md）A20（手术→主会话） |

---

## §3 清偿项修复量级评估（file:line 证据，HEAD 2026-10-16 亲核）

1. **T1 孤儿 fixture 根治**（S，test-only）：真写腿 =
   `Tests/LightamerTests/RasterEditFaceTests.swift:173-200`
   `testRestoreWinsOverDerive`——:175 取 repo fixture、:189-190
   `recordDrtChange` + `flushUntilPersisted(sidecarURL)` 在 repo 路径驱动
   真实写腿（:181/:182 的入口/出口清扫防不住 defer 之后落地的迟到
   write-behind，即「跑前删跑后复活」形态）。修复 = tempFixtureCopy 化
   （DepthMaskEditingTests.swift:273 既有 helper 同款 + L074 纪律正典），
   repo 路径永不写；保留读方入口前清 + 出口防御扫。验收机检 =
   定向 App 轮绿 + 全套 `--all` 轮毕 `find Tests/Fixtures -name "*.lra"`
   零命中（记 transcript）。
2. **T2 SessionBatchApplier 字段携带补齐**（S-M，Core additive）：
   `LightamerCore/Sources/Session/SessionBatchApplier.swift:110-118`
   （既有档臂提升面）+ `:149-163`（全新档构造点）——七个文档级 additive
   字段（`provenance`/`rawOverrides`/`displayTransform`/`versions`/
   `activeVersionID`/`aiProvenance`/`filmRecord`，字段名 =
   `LightamerSidecar.swift:317-365` 亲核）从 decode document 显式捕获并
   传入构造；`process` 分支条件盖章纪律不动（:158-163 E1 注记原样）；
   pristine 臂构造缺省 nil 不变。回归 =
   `SessionBatchApplierTests.swift` +2 法（七字段全带到 + pristine 臂
   additive 面零变化）。工作量级：捕获 7 行 + 构造 7 参 + 2 测试。
3. **T3 McpServerController 头注 19→20**（S，纯注释）：
   `App/Sources/Lightamer/MCP/McpServerController.swift:15` + `:447-449`
   两处「19-tool」→ 20（match_color = M5-1-03 交付，20-tool 封闭集
   快照族在库钉死）。零行为面。
4. **T4 HDR/base 行序方向性断言**（S，test-only）：
   `Tests/LightamerTests/ExportGainMapTests.swift` +1 法——非 uniform
   增益面（上下半场不同增益）× 非对称 base，产物重读 aux：上/下半场
   采样点增益效应方向断言（flip 反置负测或方向单向断言二选一，执行时
   按断言可检性择稳）。锚 = `ExportGainMapEncoder.swift:137`
   `.oriented(.downMirrored)` 唯一承载。
5. **T5 门③载体分叉 API 注记**（S，纯注释）：`ExportRecipe.swift:158-191`
   validate 门③ + `ExportRenderer.swift:519` render 侧 headroom 取值点
   各加一段 API-consumer 契约注记（直接构造 Request 可组出 drtOutput
   peak 合格 + drtTail record peak 低 → headroom<1 超纲产物；全 UI 路
   不可达〔M6-3 第二眼单值贯穿亲证〕；API 消费者须自证两载体同源）。
6. **T6 格式键插值形态机检硬化**（S，纯 doc + 一次性机检）：扩展红线
   grep 电池——在既有 `String.LocalizationValue("…\(` 禁形之外补
   `String(localized: "` 行内插值形态检查；本批跑一轮全仓机检记
   transcript（零命中基线）；检查形态登记 AGENTS「M6-5 架构增量」节
   （V15 提取器硬化先例同款）。

## §4 全套 `--all` 确认轮口径

- **核销基线** = M6-4 修批后推算 **3843/24/0**（带 3840..3844；= 3841
  实测 + 修批 +2，两数并行申报不混淆）。
- **本批增量记账**：ΔN = T2 +2 + T4 +1 = **+3**（T1 改法不增数；T3/T5/T6
  零测试面）→ **预期 TOTAL = 3846/24/0**（skip 24 + 0）。
- **AC 形态**：`caffeinate -dis Scripts/test-direct.sh --all` exit 0 +
  0 fail + 0 MEMFAIL + 8G 运行门（RSS_LIMIT_MB=8192）内；TOTAL ==
  3843 + ΔN（ΔN 以执行时逐任务实际记账为准，执行批如实申报）；对账式
  = 3841（M6-4 实测）+ 2（修批）+ 3（本批）= 3846 精确。若 ΔN = 0 的
  异常形态出现，回退核销带 3840..3844 判定并停手上报。
- **批准与监视**：全套轮按 AGENTS 资源监控口径须 orchestrator 批准 +
  运行中保持监视；夜间授权链覆盖本批（晨审可推翻），8G 门红线 +
  MEMFAIL 机检兜底，转红立即 kill。

## §5 转 V2 登记措辞（V2-PROPOSAL 挂账区草案，T8 落盘用）

登记体例沿用 V2-PROPOSAL「触发条件档」节（规模 + 触发 + 一句话）：

1. **TRACK-MULTIREF**（M5-1）：MCP `match_color` 多参考聚合 + 求解结果
   preset 化（存 LUT 库条目）——触发 = agent 编排高频多参考工作流出现；
   GUI 面板多参考已交付，本件纯 MCP 面（S）。
2. **RELEASE-DIRECT-INJECT**（M5-2）：Release 直启 WebP 包 framework
   动态链接不对称修复（Debug 静态/Release 动态且未 embed；根因 =
   framework 未产出，D-09-04-D9 配方不达）——触发 = Release 直启基准
   轮需求出现（perf.md §事故 4 正本）（S，工具链债）。
3. **PANO-V2**（M5-3，五件）：预览合成画布 / 参考帧手选 / use_edits /
   per-image 焦距（畸变/tilt）/ multiband 融合——OQ-M5-3 裁决 V2 字面
   （L，独立 research 环）。
4. **SESSION-LEGACY-READONLY**（M6-1）：legacy Session 根只读回退 GUI 面
   （现仅 typed toast `session_lock_held`）——触发 = 用户诉求出现再裁
   （legacy 面 env 门控 QA 通道，默认隐藏，可见面趋零）（M）。
5. **PROCESS-WIRING**（M6-2，触发条件档）：coordinator 传值接线件 +
   分叉 iop `RenderProcess.resolving` 消费 + 分叉 stage 缓存键「非
   legacy 才折」+「Update to Current Process」迁移 UX——触发 = 首个
   真实 iop 语义 bump 批四件同批（触发条款不变，DECISIONS §6 正本）（M）。
6. **ULTRAHDR-EXIF**（M6-3）：gain map 档 EXIF APP1 注入器批——触发 =
   用户/生态对 EXIF 元数据硬需求；禁自建 APP1 注入器裁决在案（段级
   注入与 MPF 副图偏移互斥），届时与 LightCraft C 路（封存零代码）
   同批评估路线（M）。
7. **STACKS-SEMANTICS**（M6-4，D-06）：栈顶被滤「首可见成员顶替」语义腿
   （LightCraft arrange 式 App 侧实现，hit 集有限 id 表）+
   `overviewCount`/`groupCounts` 收起态口径合一——触发 = 图库 stacks
   用户反馈出现（M）。
8. **SAM-COREML**（M6-4，裁决⑦）：Describe 文本选择分割 → SAM CoreML
   大件（3.4GB Meta License 永不入仓 + 全族自转换；ModelAssetStore
   安装链 + AIWorkerProtocol 第四腿已备）——用户裁立项 = 另开独立
   phase（L）。
9. **PATCH-LIVEPLANE**（M6-4，D-13 残差）：livePlane eager 释放
   （EditorState→LayerEditingState 新横 wire）+ patch pass 互斥锁
   （confirm 在飞切图竞态消解）——登记级零用户可见面，V2 语义批一并裁（S）。

## §6 Manual-Only MANIFEST 汇编（T7 落盘用）

汇编正本落 `.work/gui-acceptance/m6-5/MANIFEST.md`（证据域不入 git），
一行一配方 + 来源 VALIDATION 指针 + 前置供件列（含人脸样张 / 真无人像
照片 / 同视点扫幅样张 / 多主体样张 / layer B 资产引导下载 / HDR 屏与
跨生态设备）；来源行 = `gui-acceptance/m5-1/` + `m5-2/` + `m5-3/` +
`m6-1/` + `m6-3/` + `m6-4/` 六份既有 MANIFEST 的 human rows 并集 +
A6/A8/A10 三观察行 + E3 补录义务行 + rider（M4-3 guided filter 深边界糊，
`gui-acceptance/m4-3/MANIFEST.md`）。**本批只汇编不执行**（执行 =
用户/orchestrator 安排的 GUI 批）。

## §7 本批不做（显式边界）

- 瘦身手术第二次触发（主会话专属，A20 指针维持）。
- L057-B 尾款执行（专项行在案，A9 归 L057-B——本批仅在 MANIFEST 记
  同族新实例指针，不立新批）。
- lut3d add 行（A12 维持 M5-1 原裁定）。
- legacy 只读回退面实现（B3 转 V2，不实现）。
- 任何新功能面 / 任何 `.metal` / 零新 SPM / 零新 UserDefaults 键。
