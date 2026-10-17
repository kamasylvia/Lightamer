# M7-6-01 第二路独立验收（2026-10-17，零共享上下文五面错位切入）

**PASS / 0 blocking + 0 major + 1 minor + 4 obs**

- 验收对象：执行链 `ad003e88..83db9107` 六 commits（T1 三缺陷 / T2 UQ-A1 /
  T3 UQ-L1 / T4 SKILLS-01 / T5 对账 / T6 站收口）+ 中间夹带 docs-only
  research commits（`30916dd6` / `6555d78e` / `388e3875`，不在判定面）。
- 切入方式：不按 plan 顺序，从端到端行为与攻击面进入；执行申报（SUMMARY
  / DECISIONS / VALIDATION）只作对照正本，不信自述。
- 零源码改动；验证产物全部 /tmp 即弃；工作树还原干净（untracked 三项 =
  验收前既有）；自身测试进程零残留（GUI 实例已杀、stdio 零孤儿、endpoint
  json 已清——`mcp-endpoint.lock` 空文件为既有形态）。

## 五面判定

### 面 1 — 真端到端 stdio 裸臂 e2e（真 Debug 二进制 `--mcp-stdio` spawn，JSON-RPC 实跑）

**ALL PASS。**

| 腿 | 结果 |
|---|---|
| tools/list | **32** 整（行为级） |
| 未 acquire 直调 set_rating | **落 handler 面 `[internalError] metadata service unavailable`，非 controlNotHeld**——无头臂恒放行语义（admit 缺省 nil 字节零 diff）的行为级印证；与修复前 face 一致（正确语义，非缺陷，见 obs-1 正面发现） |
| lock 争用重放（第一轮 e2e 残留进程持锁时） | `[serverReadOnly]` typed 面——**writer 门先于 control 门的门序行为级实证**（事故即证据） |
| get_state.control.agent | `{"held":true,"holder":"","revokedByUser":false}`——minor-1 诚实面行为级实锤（非 null 镜像谎报） |
| control_acquire/get/release/re-acquire | 四步全可达，恒 `held:true`（无头恒持有） |

### 面 2 — 真机 GUI 臂（自 spawn Debug GUI + argument domain `-mcp_server_enabled 1` 注入，零偏好持久化）

**ALL PASS。**

- endpoint 发现：`mcp-endpoint.json` schema v1 **九字段**行为级齐验
  （schemaVersion/transport=streamable-http/host=127.0.0.1/port/pid/
  startedAt/serverName/serverVersion/auth=none——review m3 实证）。
- **major-1 行为级执法实锤**（本波核心验证目标）：GUI embedded 宿主未
  acquire `set_rating` → JSON-RPC error `**[controlNotHeld]**`（zh 文案
  「此命令会更改会话状态，需要 agent 控制权——请先调用 control_acquire」）
  ——M7-5 第二路 e2e「落 handler internalError」的翻转面真链亲证；
  acquire 后同调用错误面变为 handler 域（`internalError: metadata
  service unavailable`，无项目环境的 session 域 face）= **门放行对照态**。
- 活动卡：agent 持锁期间底栏 `Agent · Agent · agent` 卡带 Stop 按钮真实
  可见（截图 `held-cmdN.png`）；release 后卡转结束态（截图
  `released-cmdN.png`）——TURN-02 行为级可见。
- **禁编辑面行为判（非 AX 判）双半边闭环**：
  - 持锁 ⌘N → **无** New Project 面板（窗口/sheet 均无，截图在案）；
  - release 后 ⌘N → New Project SavePanel 出现（Untitled.lalb，截图在案）
    ——`.disabled(agentControl.holdsControl)` 行为级生效，obs-A C12
    「行为门为准、AXEnabled 恒真不产码」的处置正确性同时获行为佐证。
  - Open Recent 行为判本环境无区分度（无项目态 `recentProjects.isEmpty`
    与禁门双条件恒 disabled）——判据收敛为 New Project 单点行为 + 三落点
    代码面核（LightamerApp :1866/:1871/:1875-76 恰三处 `.disabled(...)`)。
- control_get 跨 session 视角一致（第二 session 见 held:true → release 后
  held:false）——控制面进程级单源。
- UQ-L1 scrub 实机走查**未做**（无项目无图环境不可达；家目录禁创建项目
  文件）——与执行申报一致：机检腿（ScrubTests 3 法）+ MANIFEST 配方
  A1-A6 归实机走查批/用户，不构成验收缺口。

### 面 3 — 对抗性 grep/diff（`beb8937c..83db9107` 全波）

**PASS，1 minor finding。**

- McpFinalSnapshotTests 全波 diff **恰一行**（`private func` →
  `func` makeUnionRegistry，:277）——union 32 断言面/五钉 23 零触双证
  （union 内容零 diff + App 域 union 断言全绿随全套）。
- 封存面 17 件零 diff 逐件机扫（DrtRecord/TerminalTailPolicy/
  DrtTailAssembly/PixelPipe/Lut3dKernels.metal/DrtEotf/ExportQueueContract/
  ExportFormatSpec/ImageIOEncoders/WebPEncoder/NodeGraphCommand/
  LightamerSidecar/HistoryStack/HistoryHash/PipelineDocument/V50Order/
  NodeOwnershipCatalog/Registry/ModuleInstance）+ 全域 `.metal` 零 diff。
- xcstrings diff = 恰 +10/-0 尾块纯插入（`slider_scrub_hint` zh-only），
  历史键零触碰。
- UserDefaults +/− 行精确扫描零命中（diff 内命中为上下文行）。
- Project.swift 恰三行登记 / BUNDLE-MAP 恰三行新增（3/3/2 method 数）。
- LibraryProjectController.swift / EditorState.swift（denoise 旁路面）/
  MonochromePanelView.swift 三文件零 diff（FIX2③ 第五波 + OQ-5）。
- EditorMTKView diff hunk 面核：HDR/linear 臂代码零触（仅 doc 注释更新）、
  drtSurfaceSpec 段不在 diff。
- setControlAdmit 构成 = 恰 5 处（定义 :367 + ControlToolset :20 头注 +
  三宿主调用 :754/:841/:1109——embedded 无独立安装点，box→startHTTPHost
  单点装配 :1198/:1213 读出透传亲证）；`admit:` 缺省参恰四签名 + box 字段
  恰一；`headlessConstant` 恰 6 处（:218-220 既有 control face +
  :488/:508 新 minor-1 + :617 既有 arbitrated 臂零 diff）。
- 禁令族：`String.LocalizationValue("…\(` 插值形零命中（唯一命中 =
  既有注释行，`git show beb8937c` 亲证基线已在）；`.runModal(` 零命中；
  skills/ CJK 零命中（exit 1）。
- LightamerSlider 调用点 177 处全 App（REQUIREMENTS 翻账数精确）+ yiyin
  面板 8 处（YiyinPanelView.swift，review R1 勘正 3→8 翻转属实）。
- **minor finding（BUNDLE-MAP method 数漂移）**：T1 扩 5 法未按 M2-4-3
  增行记录的「行内 method 数随扩法同 commit 闭环修订」自家纪律回写——
  AgentControlCoordinatorTests 登记 10/实际 13、McpHostTests 18/19、
  McpSearchStateToolsetTests 17/21。其中 SearchState 17→20 的 +3 漂移在
  M7-5 基线已存在（M7-5 时代既违未申报）。plan 红线「BUNDLE-MAP 恰三行」
  字面达标（新增行恰三），非行为缺陷；但该文件头注「对账以各行 method
  数为准」——对账文档数字失真，下次触 BUNDLE-MAP 的波随批修订。

### 面 4 — 数字独立复跑

**PASS，与执行申报零分歧。**

- 全套 `--all`（fcntl 锁 /tmp/la-m76-all.lock 串行，orchestrator 预批；
  注意 macOS 无 `flock(1)`，以 fcntl 等价锁实现同路径互斥）：
  `TOTAL|3963/35/0|` 2080s **exit 0 零 MEMFAIL**，七 bundle 逐值：
  IOP 687/5/0（7705MB）/ IOPParity 460/3/0（7710MB）/ Layers 494/5/0
  （810MB）/ Library 736/4/0（624MB）/ Sessions 284/9/0（1617MB）/
  Export 385/5/0（6248MB）/ App **917/4/0（2832MB，+13）**——与 SUMMARY
  §记账表逐值一致（peakRSS ±3% SPIKE 方差内），skip 35 零漂移。
- zh-audit 双 PASS 独立复跑：`--check` PASS（source keys **1709** = 1708→
  1709 恰 +1 / 1957 catalog / 38 interp）+ `--self-test` PASS。
- App 域 ΔN 记账复核：904 + T1 5 + T2 3 + T3 3 + T4 2 = 917 ✓（带
  3959..3964 命中点估 3963）。

### 面 5 — 台账一致性对抗

**PASS，零翻账矛盾。**

- M7-VALIDATION.md 六节齐全（§1 全套轮判定式 / §2 五 phase 收口矩阵 /
  §3 红线族 11 项 / §4 SC 表翻账 / §5 制度偏离三件 / §6 M7-5 signed 节
  + §7 挂账清算 + §8 留痕）；front-matter 对齐 M7-1 体例（status:
  validated + nyquist true + C 档第 3 停声明）。
- 引用真伪核：MANIFEST 存在（`.work/gui-acceptance/m7-6/MANIFEST.md`，
  .gitignore:79 政策 B 副本惯例）；§4 引用的测试法名逐一真实
  （testLegalSDRPairsPreviewSharesTheExportICCInstance 等 3 法）；
  errors.md 实数 **19 码**表（16 非控制 + 3 控制，恢复动作句对表
  ControlToolset 语义）。
- 对账链交叉：3860→3877→3905→3925→3950→3963 与 GOAL-STATE/TODO/ROADMAP
  历史 M7-1..M7-6 行逐值一致；四台账（ROADMAP M7-6 行 / REQUIREMENTS
  SKILLS-01+UQ-A1+UQ-L1 Delivered 带 commit 指针 / TODO 勾选 + 站收口 /
  GOAL-STATE 续接点）+ AGENTS.md M7-6 节——全部追加形，历史行零改写
  （`git diff` 逐 hunk 核）。
- 偏差①-⑨抽查行为级复验四条（挑对抗性最强者）：
  - **T4 tools.md description 列省略**：读产物核——tools.md 头部显式
    声明 GENERATED FILE + 省略理由（zh 活文案 vs en 单语门结构冲突）；
    schema verbatim 全文（字段级 en description 内嵌）；域边界语义确实
    由 SKILL.md §3 英文承载（五域逐域段落亲读）；N2-2 句在 SKILL.md §7。
    裁定成立、承载兑现。
  - **T3 Shift 通道 onModifierKeysChanged**：源码真挂（HStack 级
    `.onModifierKeysChanged` → `@State shiftActive` → tick 消费）——
    编译面成立；实机拖拽 Shift 1/10 速细调行为归走查批（A2 行，本环境
    无图不可达）。
  - **T2 等值测试实现形**：3 法实现与 DECISIONS §6 申报逐项吻合（legal
    8 对 `===` 同实例 + ICC bytes 逐字节 + srgbPiecewise CGColor.converted
    真分段行为判别 + 域外回落负腿；8 对清单与 Core legal 表一致）。
  - **obs-3 复检落点块内等价形**：diff 亲核（入口快照 + revoked 臂
    `stoppedByUser, !stoppedAtEntry` + busy 无条件臂，拼写与既有臂逐字
    同构）；等价性证明成立（alreadyHeldBySelf=true 路径两臂条件恒
    false/放行同路）；三测试腿（PollTriggerBox 串行交错零真 poll +
    resume B1 病灶拦截腿）实现形亲读吻合。

## 与执行申报的分歧清单

1. **（minor，唯一实质分歧）BUNDLE-MAP 三既有行 method 数漂移**（见
   面 3）——申报「恰三行 + tuist generate 末位」字面达标，自家「同 commit
   闭环修订」纪律漏办；不影响测试执行与全套对账。
2. 无推翻性分歧：全套数字 / zh-audit / 红线族 / 偏差申报 / 站收口判定
   全部独立复跑或行为级复验吻合。major-1 修复的行为级验证执行申报只给
   了单元腿（McpHostTests admit stub），本路补齐真链双臂实锤（GUI 臂
   controlNotHeld 执法 + stdio 臂恒放行 handler 面 + writer 门序
   serverReadOnly 三态），申报结论（执法语义完整）成立且加固。

## 分级清单

- **minor-1**：BUNDLE-MAP method 数三行漂移（T1 +5 法未回写；
  SearchState 行含 M7-5 既有 +3）——下次触 BUNDLE-MAP 随批修订。
- **obs-1（正面行为级发现）**：裸 stdio 臂未 acquire 写工具落 handler
  `[internalError] metadata service unavailable`——恒放行语义的行为面
  本征（非缺陷）；同环境 lock 争用变体给出 `[serverReadOnly]` typed
  面 = writer→control→handler 门序的意外实证。建议后续若有「无头臂写
  工具无项目」的 UX 需求（internalError → notSessionMember 类 typed 化）
  另行立项，不在本波范围。
- **obs-2**：SKILL.md §7 N2-2 句措辞精度——「headless liveState carries
  project.heldByOther」未显式限定「liveState 存在（有项目打开）时」；
  裸臂无项目实测 project 对象不含 heldByOther。兜底句「Treat key
  presence as informational」在，非误导级；下次触 SKILL.md 随批加限定。
- **obs-3**：McpServerController :508 注释换行瑕疵（"the arbitrated /
  -arm same spelling" 行首连字符）——纯排版，下次触文件随批。
- **obs-4**：GUI e2e 附带观察——transport session 容量帽（503）在客户端
  异常退出（无 DELETE）时累积可达；MCP v1 无通知通道的已知偏离族（M7-5
  登记在案），session 过期策略 = 框架行为，不判本波缺陷，留作 MCP 后续
  波诚实化候选（与 M7-4 挂账 ② 同族）。

## 证据索引（/tmp 即弃，本报告为持久正本）

- stdio e2e：`/tmp/m76-acc2-stdio-e2e.py`（ALL PASS 输出在会话记录）
- GUI e2e：`/tmp/m76-acc2-gui-e2e.py` + `/tmp/m76-acc2-gui-e2e.out`
- 截图：`/tmp/m76-acc2-held-cmdN.png`（持锁 ⌘N 无面板 + 活动卡）/
  `/tmp/m76-acc2-released-cmdN.png`（release 后面板出现）
- 全套：`/tmp/m76-acc2-all.log`（fcntl wrapper 轮 BUNDLE 行 + TOTAL 行）

## 结论

第二路独立验收 **PASS**：执行申报 `3963/35/0` 与六任务交付全数独立复跑
/ 行为级复验成立；major-1/obs-3 的真链行为级执法实锤补齐（GUI 臂
controlNotHeld + resume 链可达）；1 minor（BUNDLE-MAP 对账面数字失真，
非行为）+ 4 obs 全数非阻断。站收口判定（M7-VALIDATION 六节 + 四台账
翻账）无矛盾，维持 `status: validated` 呈用户晨审过目（C 档第 3 停）。
