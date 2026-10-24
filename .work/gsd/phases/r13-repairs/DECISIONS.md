# R13 修复批 DECISIONS

## §1 流一归因判定的证据链与置信级

**判定：omp major-1（Link×4 零行）在 HEAD 不可复现，判「环境型一次性表型」；不作行为修改，补观测性 + 回归钉死。**

推理链（每步实测）：
1. 代码面无删行路径：`removeImage(id:)` 生产零调用点；迁移全 additive（六臂逐一核）；FK 级联只挂在
   album/stack 删除（本流程不触）；`create()` 拒绝已存在包、`open()` 无重建臂——「插入后被删」不可能。
2. AI-ask 与零行互斥：ask 出现要求 `outcome.imported > 0` 且 `imageIDs(afterRowID:)` 非空——行曾提交。
   omp 流程描述（AI ask → 暂不）若逐字成立，则行必然存在过，与 COUNT=0 矛盾；两者不可同真。
3. 双实证：DEBUG 探针 8/8 行 + **与 omp 同配方的完整 AX 驱动 GUI 流** 8/8 kind1 行（退出后 COUNT=8 持久）。
   同一源形态（8 TIFF）、同一对话框状态（TIFF 勾选、缺键双开）、同一 AI-ask 分支（ask → 暂不）。
4. 剩余差异因子（omp 会话独有，本批不复刻）：MCP endpoint 在场、前一导入（「omp-cull 整选误选」）
   的会话残态、stale 实例的锁历史。其中可产生「静默零行无 alert 无 lastError」的机制恰好只有两个：
   a. `runImport` 入口 guard 静默 return（`importProgress != nil` 被上一卡死导入占住）——位于
      **FIX2③ 冻结文件**，本批不加日志（红线优先）；omp 的「无 watchdog 日志」与此机制吻合
      （watchdog 行只在 run 真正启动后打）。
   b. Link 腿 typed 吞错（omp 自列首要嫌疑）——**已补日志**（Core 侧，红线外）。
   残余不确定性如实申报：omp 会话的复现条件未能锁定；若复发，新日志 + watchdog 联合定位，
   届时再裁 guard 面（须先解 FIX2③ 或走 orchestrator 特批）。

## §2 修复范围裁定：观测性补洞而非「行为修复」

- 行为面无可修（不可复现）；改动 = ①`importFolder` 逐文件 catch 加 os_log error（mode/path/error）；
  ②+2 integration 回归把「Link 行入库 + AI-tail 前置 + 与 Copy 批共存」钉成行为契约。
- `runImport` guard 面不动（FIX2③）——偏差申报：omp 报告的「断点定位（哪一层把行丢了）」在
  不可复现前提下以证据链替代；如 orchestrator 认为 guard 面必须有观测，属红线变更，须显式解冻。

## §3 E 族花名册 27 → 46 的扩容依据

- 账面 27（r12 验收 §四）+ gamma（r12 路由，实为 `856f2396` 已修——任务书滞后，未重复修）。
- 本批两轮扫描：①单行/`localized:` 后换行两布局（+1 = `LibraryAnalysisWiring:65`，账面漏登）；
  ②**宽版式**（`String(` 与 `localized:` 间换行，如 `Text(String(\n localized: "…\(x)"))`）再 +18。
  合计 46 处 / 21 文件，全部转换，机检零残留。
- 合法形不转（负清单）：`defaultValue:` 内插值（FilmPanelView:385..393、CullFaceView:178 等）；
  静态键 + 字符串拼接（AIMaskEditing:390 / MaskRefineCoordinator:214 / DepthMaskService:252 /
  AIDownloadPrompt:159 / PresetManagerWindow:216）；V14 显式 switch 形（LightamerShell:1592 注记）。
- 全族无「有限枚举形」站点——花名册分类任务的双形分类以「格式串形 46 / 枚举形 0」收口。

## §4 xcstrings 三孤儿删除 + 一个真 bug 的定性

- 三个裸键孪生（edr_headroom_label / settings_displays_overridden / softproof_active_label）原本就
  在册且无消费者（插值形站点被 zh-audit 旧口径计为消费）；转换后 orphan 化，zh-audit FAIL (3)→
  删除后 PASS。值与 `%@` 孪生逐字节相同（脚本断言后删）。
- `mcp_launcher_launch_failed` 裸键在册而运行时键带 `%@` = **真裸键 UI bug**（r12 验收的
  「零运行时裸键」结论对其为误判——该验收用 stem 级在册比对，未对齐运行时 `%@` 变体）。
  本批转换顺带修复。教训：在册性比对必须用「运行时键 = 键 + 占位符变体」口径。

## §5 渲染抽验的通道降级申报

- 要求 = 抽 3 处真机读出非裸键非英文回退。实得：
  - **GUI zh 实渲染 ×2**（Settings LCR 页 AX 读出：「语义 · 512 维 · Apache-2.0 · 88 MB」——
    `settings_lcr_tier_detail %@ %@ %@` + `settings_lcr_dim_semantic %lld`）；
  - **bundle 直载渲染机 ×8 键**（同产线 `String(format: String(localized:bundle:))` + 编译目录查表），
    替换正确零裸键；locale 参数强制 zh 在本 OS 上未生效（读数为 en 表）——zh 侧由 zh-audit
    zh-completeness + 目录 dump 背书。
- 第三处 GUI 直读的障碍 = Settings 页面切换后 AX 窗口枚举永久失联（L057 域 AX 脆性，frontmost
  翻转只救回一次）+ 合成滚轮事件不入 ScrollView——如实申报，不加测。总覆盖 10 键 ≥ 3 键要求。

## §6 副作用清理（走查卫生，对齐 r12 obs-6 口径）

- defaults：`catalogs.enabled`（本批走查开启）已删；`library.import.rememberMode`（对话框 confirm
  写 0）已删；`library.import.mode/categories` 未产生；recentProjects 死路径项（/tmp 探针项目）由
  既有清扫自愈，不手工动。
- 文件：`~/Library/Application Support/Lightamer/Catalog/`（走查中启用 Catalogs 模式创建）已删；
  LUT 根未被改（reset 落默认根 = 批前状态）；/tmp/r13-link 探针目录即弃。

## §7 偏差清单（相对任务书）

1. gamma 一处「未修」申报失效——`856f2396 fix(r3)` 已按先例形落盘（任务书信息滞后）。
2. E 族实际 46 处（账面 27+gamma=28）——扩容 = 宽版式扫描增量，非账面错转。
3. 流一「修复」= 观测性 + 回归（行为面不可复现）；`runImport` guard 观测化因 FIX2③ 未做（§2）。
4. 渲染抽验第三处 GUI 直读降级为 bundle 机读（§5）。
5. 花名册漏登 1 处（LibraryAnalysisWiring:65）随批补转。
