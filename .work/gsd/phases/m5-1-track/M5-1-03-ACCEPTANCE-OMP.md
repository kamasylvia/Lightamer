# M5-1-03 ACCEPTANCE-OMP — omp 独立二次验收

> 结论头：**PASS / 0 error + 2 minor**
>
> 验收批 2026-10-11（omp 独立第二遍；与 zcode 首验零共享上下文，全部程序独立执行）。
> 对象 = `3be69ee..2002779` 四提交（与首验同窗）。首验结论 PASS / 0E；我方复验结论一致，
> 另记 2 minor（皆非本批阻塞项）+ 1 非本批 P1 佐证 + 1 面板面观察项。
> 全套 `--all` 未跑（§7 缺陷 + 批准制）；App bundle 定向轮我方亲跑全绿。

## 0. 程序与亲跑数字

| 步骤 | 我方执行 | 结果 |
|---|---|---|
| 读四文档 | ACCEPTANCE + DECISIONS + GATE-LEDGER + PLAN 全文 | 齐 |
| 定向轮 | `Scripts/test-direct.sh --bundle App`（跑前预删孤儿 `.lra`） | **749/4/0**，371s，peakRSS 2427MB，零 MEMFAIL |
| 实机走查 | GUI 建项目/导入/编辑器/LUT 页/追色实例/参考添加 + headless stdio MCP 三连 | 见 §3 |
| 读码抽查 | MatchColorToolset 616 行全文 + G4 258 行 + m4/gate 两法 + 快照 diff | 见 §1/§2 |
| 红线机检 | diff 面 + grep 机检 + zh-audit | 见 §5 |

**对表**：App `749/4/0` 与 worker 申报（GATE-LEDGER §6）及首验定向轮逐位一致。
4 skip 身份 = DepthGolden ×3 + DepthPerfProbe ×1（模型包缺席族，首验 §3 #18-21 同族——
我方未逐条重枚举日志，采信首验 21-skip 身份表 + App 轮计数一致；属复用非亲证，诚实声明）。

**与首验的关键差异**：首验 App 全量轮被 §7 Film leg 竞态阻断（3/3 crash），我方定向轮一次全绿。
两者不矛盾：§7 是概率性竞态（首验原文"时序敏感"），我方轮次恰未触发。且我方走查期间
**独立复现 §7 同签名 crash 一次**（见 §6.1），反向佐证 §7 真实存在、非首验环境偶发。

## 1. match_color 工具面审计（亲读源码 + 实机 stdio）

**读码**（`MatchColorToolset.swift` 616 行全文亲读）：

- 五参签名全落：reference 必填（`requiredString` :174）；targets string|array 缺省当前图
  （`parseTargets` :224 + liveImageURL→relPath 映射 :271-285，live 缺席 = typed invalidParams）；
  strength 0...1 缺省 1.0（`doubleArgument` :187，isFinite + range 双守卫）；solver kebab 三档
  缺省 gaussian-ot（`parseSolver` :210）；attach 缺省 true（:265 `?? true`）。
- fan-out 逐目标独立求解：参考统计共享（:337-346，ONE reference + pristine THUMBNAIL instances `[]`）、
  源统计逐图独立（:416-423，当前编辑链 + sourcePreviewCap 桶）；帽 30（`maxTargets` :54）在 gate 之前
  fail-fast（:289-293）；部分失败形态 = results[] + errors[] + partialFailure（:372-389）。
- attach=true = `projectColormatch` @MainActor 值调用（:489）+ `SessionBatchApplier` 一次写（:503）
  + `flushForTeardown`（:512），desired==current 免写（:514 `unchanged`）；attach=false = 参数组返回
  （`paramsSummary` :534，键集 = list_iops colormatch 键，explicit null 同形）。
- render gate：整调用 `seams.gate.withRenderGate`（:301）+ render 档 bounded wait（:305）；
  硬超时 typed `renderTimeout`（:311-317，落盘真相保留文案）；GUI-live 拒写不拒读
  （:404 `if attach` 守卫，attach=false 只读放行）。
- 确定性披露：线性臂 solveHash = `ColorMatchSolveCache.cacheKey` 折叠（:440）、CDF 臂 =
  `solution.solutionHash`（:470），十进制 String（:526，L013）。首验注记的"与 plan KD-1
  「solution.stableHash」措辞出入"属实——语义 = 解身份不含 strength，确定性承诺不受扰，非缺陷。
- solver 拼写二态：入参 kebab / 返回 `solver.rawValue`（`gaussianOT`，:374/:536）——apply_params
  回灌字节诚实；`IopCatalog` colormatch 行零 diff（亲证 §5）。
- 宿主形态：自持两 box（library provider :95 / service :120，NSLock 守卫 + `resetForTesting` :153）
  + LightamerApp 装配两 install（diff 亲读，order 先于 `startEmbeddedIfPreferenceEnabled`）。
  偏离合理，接受（同首验）。
- 两段流与 seed ABSENT：`testColormatchAbsentFromEditingSeed` 双面断言亲读（registry 可解析 +
  双 seed 无 colormatch）；m4 回灌法 `testAttachFalseParamsRideApplyParamsBack` 全文亲读——
  attach=true 建实例 → attach=false 组经 apply_params verbatim 回灌 → 落盘 hash 逐位断言（:597-599）。

**实机 stdio**（`--mcp-stdio` 真进程，JSON-RPC 三连亲跑）：

- `tools/list` = **20 工具**，含 `match_color`；inputSchema properties =
  `[attach, reference, solver, strength, targets]`，required = `[reference]` ✓
- 非法 solver → `[invalidParams] solver 'bogus' is not one of gaussian-ot|reinhard|cdf` ✓
- 31 目标 → `[invalidParams] targets batch of 31 exceeds the 30 cap` ✓
- 无 session 显式 targets → `[notSessionMember] no Lightamer session is open` ✓
- 缺省 targets 无 live 图 → `[invalidParams] targets is required when no editor image is addressable` ✓
- 注：description 实机返回为**中文**（`mcp_tool_desc_match_color` 的 zh 译文——server 按系统语言
  解析 xcstrings）。许可红线（LumaRescue 零搬）针对文本来源非语种，在案工具 doc 系自写，
  中文呈现 = 本地化机制正常行为，非缺陷。

## 2. G4 + 快照族审计

**G4**（`McpMatchColorParityTests.swift` 258 行全文亲读）：

- `testMatchColorApplyParamsRenderPreviewParity`：match_color(attach) → apply_params(strength 0.7
  真实微调，:186-198 `applied=Capture/cool.tif` 断言）→ render_preview == 本地 renderedPlane+JPEG q85
  **逐字节**（:208 `XCTAssertEqual(remote, local)`，零容差带）；共享 decode memo（:28-36，GUI-22 纪律）。
- `testBatchDoubleTargetParity`：单次 fan-out 双目标各自逐字节（:228-234）。
- `testDoubleCallDisclosesTheSameSolveHash`：双调用同 solveHash（G1 agent 面，:256）。
- 定向轮 App 749/4/0 全绿覆盖三法；G4 byte-identical 判据成立。

**快照族**（四文件 diff 亲核 + 机检）：

- `McpFinalSnapshotTests` diff：frozen 表入 verbatim descriptor + `all19→all20` 更名 +
  `testFinalSnapshotUnion19Verbatim→20` + 白名单负测重形（`testTwentiethToolIsWhitelistNegative→
  testPostUnionToolIsWhitelistNegative`，名单剩 delete_file/run_shell）+ destructive 集 8→9
  （match_color 入破坏列）+ descriptionKeys 增 `mcp_tool_desc_match_color` + 计数 19→20 四处。
- `McpRegistrySnapshotTests` diff：editing 域表入 verbatim descriptor + :191 计数 + 三处注释。
- `McpLauncherTests`/`McpHostTests`：计数 19→20 + 注释。
- **schema 三方字节比对（机检亲跑）**：注册源 / final 表 / editing 域表三处 inputSchemaJSON
  md5 均为 `786257700ddd`（691 字节）——逐字节一致。
- 不动点亲核：`McpHostTests:726`「19 ops」= `IopCatalog.Op(` 构造数 19（colormatch 在列 :287），
  非工具数，未触碰 ✓；`McpRenderParityTests.swift` / `IopCatalog.swift` /
  `McpServerController.swift` 三者零 diff ✓（`frozen 19-tool set` 头注陈旧保留 = files_modified 纪律，接受）。
- xcstrings +1 键 `mcp_tool_desc_match_color`（:31526，尾块纯插入）；`zh-audit --check` 亲跑
  PASS（1638 source / 1877 catalog，与申报逐位一致）。
- 快照断言语义亲读：`assertSnapshot` 比 name 集 + inputSchema verbatim + 三 hint（description 仅非空，
  非逐字——与"逐字表"表述的口径差在 P14 即定，非本批事项）。

## 3. 实机 computer-use 走查（证据链）

会话 = Debug 构建（dgzsvdww 容器）+ throwaway 项目 `/tmp/omp-m5-1-03/omp-verify.lalb`
（已 quit，会话目录保留在 /tmp 供复核，不入仓）。证据原图 75 张在
`/tmp/omp-m5-1-03/evidence/`，报告引用 4 张裁剪版同目录 `report-assets/`。

| # | 步骤 | 证据 | 判定 |
|---|---|---|---|
| 1 | New Project → omp-verify.lalb 落 /tmp | `ls` 真相 + omp-11 | ✅ |
| 2 | Import Folder → Capture（拷贝模式，TIFF 2 文件）→ 导入 | omp-13/14/18：`images` 表 COUNT=2，Media 落两 tif | ✅ |
| 3 | 双击缩略图进编辑器（ref.tif / target.tif） | omp-20：filmstrip 双图 + 画布 + 右列 | ✅ |
| 4 | LUT 页 → 追色按钮 → colormatch 实例行（蓝点选中）+ solver 三段（高斯/Reinhard/CDF）+ 参考空态 | omp-34（ref.tif 图）、omp-53（target.tif 图） | ✅ |
| 5 | + 按钮 → 选择参考图面板 → ref.tif 入列（权重 1.00 + 移除钮） | omp-56 | ✅ |
| 6 | MCP stdio 真进程：tools/list 20 + 五参 schema + typed 错误四连 | §1 机检原文 | ✅ |
| 7 | 面板追色按钮点击求解 | **未触发**（两次点击无求解迹象，见 §3.1） | ⚠️ 观察项 |

### 3.1 面板追色点击无响应（观察项，非本批阻塞）

现象：target.tif 图上 colormatch 实例已建 + ref.tif 参考已加（权重 1.00），两次视觉定位点击
"追色"按钮（坐标经全分辨率 crop 换算，第二次 (1248,743) 逻辑坐标经像素级复核），均无求解迹象：
无进度态、无 `.lra` 落盘（Media/Capture 下空）、无 solveError 橙字、无强度滑杆/readout 出现。

定性分析（读码 + AX 交叉）：

- 按钮 disabled 条件 = `!hasImage || references.isEmpty || isSolving`（ColorMatchPanelView :179）。
  references 非空（行在位）；hasImage = `pipeCoordinator?.liveImageURL != nil`——编辑器开着应非 nil；
  故按钮理论 enabled（截图亦非灰化态）。
- 异常信号：①强度 HStack + readoutSection **视觉缺失**（追色下直接预设 footer，多轮截图一致，
  与 P2 走查 m5fix-02"空态亦有强度 0.00"布局不符）；②AX 树有两个 slider 但**同位置同尺寸重叠**
  （(1250,740,196x16) ×2，value 均为 0.0——与视觉权重 1.00 矛盾）。
- 以上指向 **P2 面板面（M5-1-02 交付）的 GUI 布局/绑定问题**，非本批 match_color MCP 面。
  本批 diff 零触碰 `ColorMatchPanelView/Model`（§5 红线铁证）。且 P2 走查（m5fix-01..09）当时
  面板求解走通——回归窗口 = M5-1-02 之后（M3-4/M4/Apple SDK 行为漂移皆可能）。
- **处置**：记观察项，不阻断本批（本批对象 = MCP 工具面，其求解链由 G4/McpMatchColorToolsetTests
  24 法自动化覆盖，实机 stdio 亦亲证）。建议 orchestrator 立 GUI 面板项排查（复现载体 = 本报告
  §3 会话配方 + omp-56 截图态）。

## 4. 五门台账审计（GATE-LEDGER 逐行对锚）

- **锚真实性（机检亲跑）**：18 个锚方法 `grep -rl "func <锚>"` 全部命中实文件（G1 七锚/
  G2 两锚/G3 三锚/G4 三锚/G5 三锚——G4 三锚 = 本批 `McpMatchColorParityTests`）。
- **门值抽查**：G2 `ColormatchKernelParityTests` 门值、G1 缓存键字面 `2495982924697081349`/
  `3458577883779271296`——首验已亲读行号，我方采信（台账行与 P1/P2 DECISIONS 交叉一致，
  收口轮定向值 Layers 466/IOPParity 444/IOP 563 与 P2 收口逐位相等由首验全套轮亲证）。
- **对账链**：3335+32+38+47+1+24 = 3477 算术闭合；App = 725+24 = 749（我方定向轮亲证 749）。
  M4-3"估 16"→实测 21 的口径修正注记在案，诚实。
- **亲验性**：G4 = 本批落门（我方定向轮覆盖 + 源码全文亲读）；G1/G2/G3/G5 = 前波落门 +
  首验全套轮六 bundle 逐位复核（我方未重跑六 bundle——定向轮范围所限，采信首验 §0 表）。
- G3 自然样张目测 = Manual-Only 挂 M5-4，台账未代跑 ✓。

## 5. 逐 commit 边界 + 红线机检（亲跑）

| commit | 边界核验 |
|---|---|
| `e13d750` T1 | 11 文件：工具 616 行新文件 + EditingToolset **+1 行**（register 一行 + 行尾注释，diff 亲数）+ LightamerApp +13（装配两 install + 注释）+ 快照族四文件 + ToolsetTests 835 行 + xcstrings +1 键 + Project.swift +1 + BUNDLE-MAP +4 行 |
| `1f4270e` T2 | 3 文件：ParityTests 258 行 + Project.swift +1 + BUNDLE-MAP +1 |
| `c99e149` T3 | 仅 GATE-LEDGER 123 行 ✓ |
| `2002779` T4 | GOAL-STATE/LESSONS/TODO/REQUIREMENTS/DECISIONS/SUMMARY 六文件 ✓（message 与 plan 约定逐字吻合 ×4） |

红线机检（`git diff 3be69ee..2002779` + grep 亲跑，全过）：

- `LightamerCore`/`LightamerIOP` **零 diff**（0 行输出）；`.metal` 零 diff 零新文件；
  V50Order/Registry/GradeCatalog 零触碰（零 diff 推得）。
- `grep -rln '"match_' .../MCP/Tools/` = **MatchColorToolset 一文件**（零新工具面）。
- `runModal` App/Sources **0 命中**；`String.LocalizationValue("…\(x)…")` 禁形唯一命中 =
  LightamerApp:1805 **注释行**（doc comment 内代码引用，非代码）。
- 零新 SPM：Project.swift diff 仅测试编列 2 行。
- LumaRescue：全仓唯一命中 = MatchColorToolset.swift:45 注释行"License red line: the tool text
  above is self-written; LumaRescue text/code is never copied"——系红线声明本身，非搬运。
  工具 description 全英文自写 + 中文译文为本地化（§1 注），无 LumaRescue 术语/文本。
- render gate 消费：源 :301 `withRenderGate` + 专测 `testMatchColorSerializesOnTheRenderGate`
  （hold/release 两断言）全文亲读 ✓。
- m4 机制根基：`ColormatchModule.swift` :33-39 NIL ENCODING 注释（P1 显式 null / M5-1-02
  assetRef omit-nil 分域）亲读 ✓。
- BUNDLE-MAP 登记：APP 21 + APP 3 两行 + 注记（T1 注记与 T2 落行分离，合读齐）✓。
- REQUIREMENTS 翻账：TRACK-01..05 + MCP-09 研究项 C 勾选 + 门锚 + TRACK-03 派生资产偏差注记
  （checker m7）✓。

## 6. 非本批缺陷与分歧点

### 6.1 §7 Film leg 竞态——我方独立佐证（非分歧，是加强）

走查期间（17:11）本机另有 Export bundle 轮在跑，其测试宿主 crash，.ips（`Lightamer-2026-10-11-171153.ips`，
pid 12003）签名 = `EXC_BAD_ACCESS/SIGSEGV` @ `_swift_release_dealloc` ←
`PixelPipe.runFilmLeg` ← `runTerminalTails` ← `FilmLegTests.stressConcurrentLegs`——
与首验 §7 三份 .ips **同栈同签名**。首验§7 的"概率性潜伏竞态"判断得我方独立实证加强。
（该 crash 非我方进程触发——我方 GUI app pid 7465/13651 另有其人；属并行环境事故，
我方仅保全证据 `report-assets/omp-filmleg-crash-testhost.json`。）

### 6.2 GUI Tooltip SIGBUS crash（L057-B 族，新实例，非本批）

我方 GUI app（pid 7465）在点击 colormatch 面板 + 按钮期间崩溃（17:16:51），签名 =
`EXC_BAD_ACCESS/SIGBUS`（stack guard）@ 主线程 `TooltipBridge.DynamicTooltipManager`
← hover 计时器 ← `ButtonResponder.updateValue`。机制 = L057-B 在案族（AX 自动化压力/
hover tooltip 栈边界故障），与 match_color 零交集（本批无 GUI 触碰；崩栈无 MCP/ColorMatch
帧）。证据保全 `report-assets/omp-gui-crash-tooltip.json`。建议并入 L057-B 专项，
不另立项。

### 6.3 与首验的分歧点（共 2 处，皆 minor 级）

1. **minor-1：GATE-LEDGER §6 表头措辞**——"**全套 `--all` 终验（M5-1 收口批准轮）**"表述
   易误读为单命令全套轮一次通过；实际 = 首轮 Library SIGSEGV 中断 + 分割重跑拼表（正文
   "轮次记录（诚实面）"段已如实披露）。首验未点名。我方判 minor：正文诚实披露在案，
   仅表头有乐观色彩，建议 VALIDATION 期改表头为"全套终验（分割重跑拼表）"。不阻断。
2. **minor-2：App 4 skip 身份我方未逐条重枚举**——首验 §3 #18-21 为 Depth 族模型缺席；
   我方定向轮计数 749/4/0 一致即采信，未重提日志逐条理由。属验收覆盖度差异（首验已全枚举），
   非产物分歧。记 minor 以诚实标定我方证据边界。

**无 error 级分歧**：五参/fan-out/attach 双态/render gate/typed 面/快照 all20/G4 byte-identical/
红线零 diff/LumaRescue 零搬——我方逐项独立亲证，与首验一致。

## 7. 终态意见

- **本批可交付**：生效值⑥⑧全兑现——match_color 最小面（五参/批量独立求解/attach 双态/
  确定性披露/零新增面机检）+ G4 byte-identical（源码亲读 + 定向轮覆盖）+ 五门台账闭合 +
  翻账 + 对账链 3477 闭合。批内质量高：DECISIONS 申报偏离（装配两行/两段流/solver 二态/
  快照超 plan 行号面）逐条核实合理。
- **挂账移交**：①首验 §7 Film leg 竞态 P1（我方 §6.1 独立佐证，建议紧随修复批）；
  ②§3.1 面板追色点击无响应观察项（P2 面回归嫌疑，建议 GUI 专项排查，不阻断 VALIDATION 的
  MCP 面）；③§6.2 Tooltip crash 并入 L057-B；④M4-1 #6 孤儿预防照旧（本批已执行，
  且定向轮后再生孤儿已清）。
- **走查会话清理**：GUI app 已 quit；MCP 偏好键已恢复删除；`/tmp/omp-m5-1-03/` 保留
  （证据 + throwaway 项目，不入仓）；工作区 `git status` 仅验收前即有项（M5-1-01/02 OMP
  报告 + dt-clone-archive），本验收零工作区残留（除本报告文件本身）。

OMP-VERDICT: PASS
