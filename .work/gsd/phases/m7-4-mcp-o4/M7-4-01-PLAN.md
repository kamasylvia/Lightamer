---
phase: m7-4-mcp-o4
plan: "M7-4-01"
title: "MCP O4 跨图批量 + note 归属 + UQ-A2 原子终写单 plan——T1 S1 修复批首项（poll POLLIN + revents 分流 + bounded re-poll 250ms + /tmp/m73_probe 探针迁 evidence + e2e 真断连回归〔12s 活性 + .lalb-wal==0〕+ ⑥/H3③ 措辞校订注记）/ T2 S2 A+C（两臂 launch 预热 3 装配点 + list_luts 文案原位改）+ S3 正臂腿 / T3 O4（AdjustmentTransferCatalog 纯 helper 抽取消二份 + copy_adjustments 只读枚举 + paste_adjustments 批量写 + apply_params note 参 + author=mcp 盖章 + HistoryItem additive note/author + get_history 读面翻转）/ T4 UQ-A2（encodeStage additive exclusiveFinalWrite + tmp 同目录 encode + link() EEXIST + gain-map 同 wrap + $jobNamingCarrier 递缝 + TOCTOU 负测）/ T5 match_color 勘正（目录锚一行 + kind0 腿）/ T6 测试批（union 27→29 全点位显式改本波取权 + 新工具 golden + 既有 27 工具零回归 + MCP2-09 GUI 面 + zh-audit）/ T7 定向轮 + 全套 --all（批准制）+ 红线族 + 收口翻账"
wave: 1
depends_on: []
autonomous: true
requirements: ["REQUIREMENTS MCP2-08..09（:438-439）+ UQ-A2（:459）→ M7-4 + ROADMAP §M7-4 行", "OQ 裁决正本 = phases/m7-4-mcp-o4/M7-4-CONTEXT.md（D-M7-4-1..10 全按 RESEARCH §7 推荐，站 charter 授权落定，晨审可推翻）", "调研正本 = phases/m7-4-mcp-o4/M7-4-RESEARCH.md（§1 O4 测绘 / §2 S1 / §3 S2 / §4 UQ-A2 / §5 match_color / §6 测试策略；file:line 经 planner 2026-10-13 HEAD 0b34d199 逐点亲核复核吻合——union 外计数钉行号 M7-3 后已漂移，plan 内一律用 fresh 坐标）", "M7-3 挂账单一清单六项 = phases/m7-3-mcp-o2o3/M7-3-VALIDATION.md §挂账（本波 T1/T2/T5 收口①②③⑤ + ⑥ 措辞注记；④ 无动作）", "夜间全自动授权在案（先例 D-07-3-T5-1；晨审可推翻）"]
success_criteria: "SC 全可机检——T1：armStdioEOFReleaseOnce poll 体 grep 三判据（events: POLLIN 在位 / poll(&fds, 1, 250) 超时形在位 / 分流 revents & (POLLHUP|POLLERR) → break + else 分支只清 fds[0].revents 零消费）+ once guard/M1 自守卫/http 不 arm 三语义零 diff（函数其余行逐行核）+ 探针源迁 evidence（ls phases/m7-4-mcp-o4/evidence/m73-probe/ 含 probe.c/harness.c/harness.sh/e2edrv*）+ e2e 新法绿（spawn 真二进制 --mcp-stdio → initialize → project_create → 关 stdin → exit ≤12s 断言 + .lalb-wal size==0 断言——graceful checkpoint 正面证）+ 定向 App bundle 绿；T2：grep `LutLibraryStore.shared` 预热恰 3 装配点（LightamerApp + startHeadlessStdioHost/startHTTPHost 段，共享 helper 单处定义）+ Task.detached(priority: .utility) 形在位 + mcp_tool_desc_list_luts 原位值改含冷首调句（en+zh 同批）+ McpTimeouts 零 diff + S3 正臂腿绿（heldTargets 非空 → before==nil ∧ after!=nil ∧ store 未变 → typed projectReadOnly）+ 产线逻辑零新增（S3 恰测试文件 diff）；T3：copy_adjustments 注册（readOnlyHint:true / writer 缺省）+ paste_adjustments 注册（requiresWriter:true + destructiveHint:true + targets maxItems 1000 + applyBatch 60s 既有档）+ 双工具 source 双形态 resolveReference 复用（grep MatchColorToolset.resolveReference 调用）+ paste per-target live 硬拒 + probe + membership 前置 + flushForTeardown 写达后方返 + AdjustmentTransferCatalog 纯 helper 抽取（GUI model 委托 + MCP 双消费——grep isAdjustmentTransferable 调用面恰单一函数零第二份排除逻辑）+ HistoryItem 恰 additive 两字段（CodingKeys decodeIfPresent/encodeIfPresent + nil 不编码 + 旧档字节零漂移负测）+ HistoryHash 零 diff（git diff HistoryHash.swift = 空）+ 负测：同编辑态 note/author 有无 → hash 逐位同 + get_history per-item 恰 +2 键 + 顶层 author = 最新 kept item 翻转（pristine .null 负测）+ apply_params additive note 参 + author=mcp 盖章 + label 恒 MCP paste_adjustments / MCP apply_params；T4：encodeStage 签名恰尾追 exclusiveFinalWrite: Bool = false（缺省调用方零 diff 负测——既有 encodeStage 测试面零改全绿）+ exclusive 臂 tmp `.<name>.<uuid>.tmp` 同目录 + link() 晋升（成功 unlink(tmp) / EEXIST → unlink + BaseNameOccupiedError(name:) 复用 / 其它 errno internalError）+ defer 清理零 tmp 残留（glob 断言）+ gain-map 臂同 wrap + queue encode 腿 $jobNamingCarrier.withValue 装配（:489-493 render 腿同形）+ encodeLeg 内读 jobNamingCarrier?.collisionPolicy == .fail 传参 + render 步快照检查保留（diff 面核）+ TOCTOU 负测绿（render → 手工建 destination 文件 → encodeStage(exclusiveFinalWrite:true) → typed 错 + destination 字节不变 + 无 tmp 残留）+ 正向恒等（exclusive ≡ 非 exclusive byte-equal）+ .replace 覆盖仍发生负测 + ExportNamer.swift 零 diff；T5：LightamerApp match_color provider 恰一行目录锚（deletingLastPathComponent 在位）+ 两测试 provider 同形勘正 + kind0 锚腿新法绿（pathKind 0 行 → id 形 resolve == <projectDir>/Media/x.jpg）；T6：union 显式改全点位——冻结表 +2 行（descriptors() 名序）+ 计数 ×4（:249/:299/:327/:479）27→29 + destructive 集 9→10（+ paste_adjustments）+ descriptionKeys +2（:334）+ all27→all29（:219 定义）+ 测试名 Union27→Union29（:244）+ 头注 :20 + message :250/:327 同批 + editing 层（McpRegistrySnapshotTests）apply_params note 行 + copy/paste 两行 + :203 计数钉 21→22 + union 外五钉显式改（McpRegistrySnapshotTests :203 / McpSearchStateToolsetTests :274 / McpHostTests :243/:697 / McpLauncherTests :200——21→22 + message 同批）+ MCP 测试面 `count, 21` / `count == 21` / `all27` 零残漏 grep + 新工具 golden（枚举恒等：GUI pastePayload ≡ Catalog 产物实例集逐参恒等 / 两形态寻址 / greyed 计数 / DRT present / paste per-target 分账 + live 硬拒 + probe held 拒 + membership 拒 + include 子集 + includeDrt=false + mask contentRevision==nil + flush 写达后方返）+ MCP2-09 golden（sidecar 字节 roundtrip + 旧档 tolerant 负测 + hash 不变负测 + per-item 键 + 顶层翻转）+ 既有 27 工具 descriptor 零 diff（除 apply_params 申报内 note 行）+ EditorToolRailView note 副标题（lineLimit(1)）+ author 徽章（nil 无徽章）+ zh-audit --check（+3）与 --self-test 双 PASS；T7：--bundle App+Layers+EXPORT 定向绿 + 全套 --all = TOTAL|3905+ΔN/35/0| 对账闭合（exit 0 / 0 MEMFAIL / 七 bundle 8G 门内 / 批准制标注）+ 红线族逐条机检 PASS + 四台账同批落盘（历史行只追加不改写）"
estimated_tests: "+21..28（research §6 带 −1〔S2 探针腿改观察证据不入 XCTest——skip 35 口径维持〕：T1 ~2..3〔e2e 活性 + WAL==0（+可选锁腿）〕/ T2 ~1〔S3 正臂〕/ T3 ~14〔copy ~4 + paste ~6 + MCP2-09 ~4〕/ T4 ~4〔§4.3 必做四腿；可选 queue 级/gain-map 腿若行使 +2〕/ T5 ~2〔kind0 锚腿 + provider 勘正随行〕/ T6 union 显式改零新测试；执行时逐任务如实记账，越带申报）"
test_bundles: [APP, LAYERS, EXPORT]
baseline: "3905/35/0（M7-3 三路全套同值；其后 9e42c25e〔VALIDATION 签核〕+ 0b34d199〔M7-4 research docs〕两跳 docs-only 基线零漂移；HEAD 0b34d199 planner 2026-10-13 亲核 git log/status——其上仅三处无关 untracked 旧件）"
expected_all: "3905 + ΔN（对账式；ΔN 预期带 +21..28，执行时按实记账；skip 35 口径维持——本波零 skip 门新测试，S2 观察证据不入 XCTest；第三种 skip 来源 = 逐族差分申报禁静默吸收）"
red_lines:
  - "零新 SPM 依赖（Project.swift dependencies 块零 diff）"
  - "MCP 快照族显式改——本波显式取 union 文件（McpFinalSnapshotTests.swift）改动权（union 27→29；M7-2/M7-3 权已用讫、M7-4 在 M7-5 前串行执行取权合法）：union 全点位显式改 + apply_params schema 两层（editing 域层 + union 层）consciously change together 同批；快照改动全部走「显式改 + DECISIONS 申报」形禁静默；M7-4 持权窗口内禁并行派发 M7-5（orchestrator 编排保证——若误并行派发立即停手上报，禁抢先合并快照表）"
  - "HistoryHash 零 diff（折叠面零触——note/author additive 不入折，机制证 + 负测双钉）；HistoryItem 仅 additive optional 两字段 note/author（drtRecord/filmRecord 同族先例——decodeIfPresent/encodeIfPresent、nil 不编码、schemaVersion 零动、tolerant 双向；GUI 写腿 author 恒 nil 零 diff）；LightamerSidecar 类型/schemaVersion 零 diff"
  - "错误码 16 档封闭表零新增（McpToolRegistry.swift 零 diff——copy/paste 全走 invalidParams/notSessionMember/projectReadOnly/imageLiveInEditor/serverReadOnly/internalError；UQ-A2 复用 ExportNamer.BaseNameOccupiedError）；McpTimeouts 零新档零改档（applyBatch 60s 既有档消费——D-M7-4-8 新档支线不行使）"
  - "封存面零触 + 申报内例外：encodeStage 仅 additive 默认参一处（exclusiveFinalWrite，缺省 = 既有调用方零 diff——renderedPlane pristineOnly 同族先例）；ExportQueueContract leg 形零 diff（renderLeg/encodeLeg 闭包签名冻结——policy 递缝走 $jobNamingCarrier.withValue wrapper，$jobExifSoftware 同款第四例）；ExportNamer.swift 零 diff；ExportCollisionPolicy 三档枚举零动（.increment 字节冻结 / .replace 保持 plain rename）；六格式导出矩阵（ExportFormatSpec·ImageIOEncoders·WebPEncoder）零触；UI ExportInspectorView 零触；PixelPipe / V50Order / GradeCatalog（NodeOwnershipCatalog）/ Registry / ModuleInstance / Lut3dKernels.metal / DrtRecord / TerminalTailPolicy / DrtTailAssembly / DrtEotf / PipelineDocument / NodeGraphCommand 零 diff；零新 .metal（全域零 diff）"
  - "排除谓词单源红线（AdjustmentTransfer.swift 头注 :25-27 同构延续）：isAdjustmentTransferable 全仓恰单一函数定义——AdjustmentTransferCatalog 抽取 = 枚举/载荷构建纯函数化（GUI model 与 MCP toolset 双消费），零第二份排除逻辑；GUI model 行为零 diff（M2-8 既有 AdjustmentTransferTests 面作守卫）"
  - "LibraryProjectController.swift 文件零 diff（FIX2③ 连续第三波维持——若执行期行使须显式申报）"
  - "Alcedo GPL 代码/文档文案零复制零翻译——工具名/参数/schema/文案全部自写（6203791/e75cf2a/9f9fc5e/1f12551 只对表命令语义；link() 修法为 POSIX 标准面非 Alcedo 抄写）"
  - "xcstrings = 三新键 mcp_tool_desc_copy_adjustments / mcp_tool_desc_paste_adjustments / editor_history_author_badge 尾块纯插入（历史键字节与顺序零触碰）+ mcp_tool_desc_list_luts 原位值改（en defaultValue + zh 译文同批——非尾块插入，DECISIONS 申报）；UserDefaults 零新键；执行中如需更多键 = 同纪律 + DECISIONS 申报"
  - "\\.runModal( 在 App/Sources 零命中（L057 禁令）；LocalizationValue 插值禁形代码零命中（新键一律 String(localized: 静态键, defaultValue:) 显式形态——禁 String.LocalizationValue(\"prefix_\\(x)\" 插值形，M2-9 F-2 禁令）"
  - "S1 修复语义钉：once guard / M1 mode 自守卫 / http 臂不 arm / close+exit(0) HUP 体四语义零改——恰改 poll 请求位（events: POLLIN）+ 超时形（250ms）+ revents 分流三点；「清位」只清 revents 绝不清 events 位（措辞在 action 写实）；纯 POLLIN 分支零字节消费（watches HUP without stealing bytes 原意图保持）"
  - "登记纪律：新测试一律 additive 到既有文件——预期 Project.swift 与 BUNDLE-MAP 零行变更；若执行期必须新建测试文件 = Project.swift 恰一行 + BUNDLE-MAP 恰一行 + tuist generate 恒为该批最后一个动作（L041）+ DECISIONS 申报；构建 caffeinate -dis 包裹；单测 = Scripts/test-direct.sh --bundle <域>；全套 --all orchestrator 批准制（本 plan 标注批准制，执行时 orchestrator 派发 prompt 即批准）+ 8G 门 + MEMFAIL 机检 + 运行中保持监视（AGENTS 资源监控节）；测试宿主清理先核 parentage（ps -o ppid——测试宿主 parent = 脚本进程树，GUI 实例 parent = launchd）"
files_modified:
  - App/Sources/Lightamer/MCP/McpServerController.swift                              # T1：armStdioEOFReleaseOnce poll 体三点改形（events: POLLIN / poll(&fds,1,250) 超时形 / revents 分流——once guard + M1 自守卫 + close+exit(0) 体零改）。T2：warmLutLibrary() 一行 helper + startHeadlessStdioHost/startHTTPHost 两装配点调用
  - App/Sources/Lightamer/UI/LightamerApp.swift                                     # T2：GUI 装配段 warmLutLibrary() 第三装配点。T5：match_color installLibraryProvider return 行恰一行目录锚（url.deletingLastPathComponent()——fix 20997721 先例形）
  - App/Sources/Lightamer/State/AdjustmentTransfer.swift                            # T3：AdjustmentTransferCatalog 纯 helper 抽取（enumerate 快照 + 载荷构建；AdjustmentTransferModel.enumerate/pastePayload 改委托——行为零 diff，M2-8 测试面守卫；头注排除单源句随形更新）
  - App/Sources/Lightamer/MCP/Tools/EditingToolset.swift                            # T3：copy_adjustments + paste_adjustments 注册与 body（source 双形态 resolveReference 复用 / copy 只读枚举应答 / paste per-target 前置 + SessionBatchApplier.apply 数组腿 .overwrite label "MCP paste_adjustments" + flushForTeardown 写达后方返 + per-target 结果列应答）+ apply_params additive note 参 + 双写工具 author="mcp" 盖章透传
  - App/Sources/Lightamer/MCP/Tools/SearchStateToolset.swift                        # T3：get_history per-item dict 恰 +2 键（note/author 缺省 .null）+ 顶层 author 占位翻转（position 位 item 的 author——:897-900 占位注记替换为消费体）
  - App/Sources/Lightamer/UI/Shell/EditorToolRailView.swift                         # T6：historyRow note 副标题（单行截断 caption2）+ author 徽章（"mcp" 徽章文本 + AX label 键；nil 无徽章）
  - LightamerCore/Sources/Pipe/History/HistoryStack.swift                           # T3：HistoryItem additive note: String? + author: String?（存储 + init 默认参 + CodingKeys decodeIfPresent/encodeIfPresent——drtRecord/filmRecord 同族形；nil 不编码）
  - LightamerCore/Sources/Pipe/History/PasteSemantics.swift                         # T3：paste additive note/author 默认参透传 HistoryItem（缺省 nil = 既有调用方零 diff）
  - LightamerCore/Sources/Session/SessionBatchApplier.swift                         # T3：apply additive note/author 默认参 → segment1 compose 透传（缺省 nil = 既有调用方零 diff；M2-8 Copy Adjustments GUI 面零触）
  - LightamerCore/Sources/Export/ExportRenderer.swift                               # T4：encodeStage 签名恰尾追 exclusiveFinalWrite: Bool = false + exclusive 臂（同目录隐藏 tmp `.<name>.<uuid>.tmp` encode + post-encode 两腿原位跑 + link() 晋升：成功 unlink(tmp) / EEXIST → unlink + BaseNameOccupiedError(name:) / 其它 errno → internalError；defer 清 tmp 零残留）+ gain-map 臂同 wrap（ExportGainMapEncoder destination 形参换 tmp+link）
  - LightamerCore/Sources/Export/ExportQueue.swift                                  # T4：encode 腿调用点（:521-528 段）加 $jobNamingCarrier.withValue namingCarrier additive wrapper（:489-493 render 腿同形装配 queued.naming/collisionPolicy/subfolder）+ encodeLeg 内读 jobNamingCarrier?.collisionPolicy == .fail 传 exclusiveFinalWrite: true
  - Resources/Localizable.xcstrings                                                 # T2：mcp_tool_desc_list_luts 原位值改（冷首调代价句）。T3：mcp_tool_desc_copy_adjustments/_paste_adjustments 两新键。T6：editor_history_author_badge 新键（尾块纯插入三键 + 原位改一键）
  - Tests/LightamerTests/McpProjectArbitrationTests.swift                           # T1：e2e 真断连新法 additive（真二进制 spawn fixture 复用——--mcp-stdio → initialize → project_create → 关 stdin → exit ≤12s + .lalb-wal size==0；可选锁窗腿：持锁期第二 project_open = typed projectReadOnly）
  - Tests/LightamerTests/McpProjectToolsetTests.swift                               # T2：S3 正臂腿（makeGuiShapedProvider(stub:heldTargets:) 传非空 heldTargets → 差分谓词正臂 typed projectReadOnly 断言——零产线代码）
  - Tests/LightamerTests/AdjustmentTransferTests.swift                              # T6：Catalog golden（同链 → GUI pastePayload 与 Catalog 产物实例集逐参恒等——no-second-copy 机检正面 + mask 纪元重置断言）；T3 期 GUI model 委托零 diff 守卫（既有法全绿）
  - Tests/LightamerTests/McpEditingToolsetTests.swift                               # T6：copy/paste golden additive（两形态寻址 / greyed 计数 / DRT present 面 / paste per-target applied|rejected 分账 + live 硬拒 + probe held 拒 + membership 拒 + include 子集 + includeDrt=false + label 断言 + flush 写达后方返）
  - Tests/LightamerTests/McpSearchStateToolsetTests.swift                           # T6：get_history per-item 两键 + 顶层 author 翻转 golden（pristine .null 负测）+ :274 计数钉显式改 21→22 + message 同批
  - Tests/LightamerTests/SidecarV10Tests.swift                                      # T6：HistoryItem note/author roundtrip（sidecar 字节 + nil 不编码负测）+ 旧档 tolerant decode 负测（缺两键旧档读回 nil）+ HistoryHash 不变负测（同编辑态 note/author 有无 → hash 逐位同）——LAYERS 域现行归域
  - Tests/LightamerTests/ExportRendererE2ETests.swift                               # T4：TOCTOU 负测（render → 手工建 destination → encodeStage(exclusiveFinalWrite:true) → typed 错 + 字节不变 + 无 tmp 残留 glob）+ 正向恒等（exclusive ≡ 非 exclusive byte-equal）+ .replace 负面守卫
  - Tests/LightamerTests/McpMatchColorToolsetTests.swift                            # T5：:177/:402 两测试 provider 目录锚同形勘正 + kind0 锚腿新法（pathKind 0 行 → id 形 resolve == <projectDir>/Media/x.jpg）
  - Tests/LightamerTests/McpRegistrySnapshotTests.swift                             # T6：editing 层显式改（apply_params note 行 + copy/paste 两行加入 + :203 计数钉 21→22 + message 同批）——与 union 层 consciously change together
  - Tests/LightamerTests/McpFinalSnapshotTests.swift                                # T6：union 27→29 全点位显式改（冻结表 +2 行 + 计数 ×4 :249/:299/:327/:479 + destructive 9→10 集断言 :255-260 + descriptionKeys +2 :334 + all27→all29 :219 + 测试名 :244 + 头注 :20 + message :250/:327——DECISIONS 申报附点位清单）
  - Tests/LightamerTests/McpHostTests.swift                                         # T6：:243/:697 计数钉显式改 21→22 + message 同批
  - Tests/LightamerTests/McpLauncherTests.swift                                     # T6：:200 计数钉显式改 21→22 + message 同批
  - .work/gsd/phases/m7-4-mcp-o4/evidence/m73-probe/                                # T1：/tmp/m73_probe 三层探针源迁入（probe.c / harness.c+sh / e2edrv*.c / e2e.sh——小件文本随 T1 commit）
  - .work/gsd/phases/m7-4-mcp-o4/M7-4-01-SUMMARY.md                                 # T7：执行摘要（逐任务 ΔN 记账 + 中间红窗申报〔T3..T6 MCP 两快照红——构建绿门维持〕+ S2 观察证据）
  - .work/gsd/phases/m7-4-mcp-o4/M7-4-01-DECISIONS.md                               # T7：裁定记录（union 显式改点位清单 + destructive 9→10 申报 + list_luts 原位改申报 + UQ-A2 上游分歧申报〔保留 render 快照检查〕+ ⑥/H3③/特殊事项 5 三处措辞校订注记〔M7-3 签核文档不回改〕+ S3/O1 漂移注记维持裁定 + 全拒批诚实应答形 + tmp 命名/清理终形）
  - AGENTS.md                                                                       # T7：「M7-4 架构增量」节（O4 双工具语义 + note/author 面 + S1 终形 + UQ-A2 缝 + match_color 锚 + ΔN 终值）
  - .work/TODO.md                                                                   # T7：M7-4 条目翻账（挂账①②③⑤⑥收口申报 + FIX2③ 第三波维持）
  - .work/GOAL-STATE.md                                                             # T7：续接点翻新（M7-4 收口 → next = M7-5〔union 改动权移交〕）
  - .work/gsd/REQUIREMENTS.md                                                       # T7：MCP2-08..09 + UQ-A2 翻账（Delivered + M7-4 commit 指针）
  - .work/gsd/research/UPSTREAM-QUEUE.md                                            # T7：三观察项入队（tasks/wait_task 面 / paste per-target 版本化 / 库域批量写 + withTimeout v2 B 线——D-M7-4-1/3/6/8 挂账兑现）
---

# Plan M7-4-01 — MCP O4 跨图批量 + note 归属 + UQ-A2 原子终写（S1 修复首项 + S2 A+C + S3 腿 + match_color 勘正 + 快照 27→29 + 顺路清算）

> **夜间全自动授权**（先例 D-07-3-T5-1；晨审可推翻）。裁决正本 =
> `M7-4-CONTEXT.md`（D-M7-4-1..10 全按 RESEARCH §7 推荐——站 charter 授权
> 落定）；规格正本 = `M7-4-RESEARCH.md`（§1 O4 测绘 / §2 S1 修复 / §3 S2 三
> 选一 / §4 UQ-A2 / §5 match_color / §6 测试策略；file:line 经 planner
> 2026-10-13 HEAD `0b34d199` 逐点亲核复核吻合；**union 外计数钉行号 M7-3 后
> 已漂移**——McpRegistrySnapshotTests :194→:203 / McpHostTests :696→:697 /
> McpSearchStateToolsetTests :270→:274，plan 内一律用 fresh 坐标）。
>
> **裁定权归属钉**：本 plan 无用户裁决分支（O4 双工具 additive + HistoryItem
> additive 两字段 + UQ-A2 additive 一参 + S1 三点改形——既有工具行为面零变化
> 由 T6 快照/零 diff 门钉死，除 apply_params 申报内 note 行与 list_luts 申报内
> description 字节）。执行中如触「必须扩面」（新错误码 / 新超时档 / 库域写投
> 影 / 排除谓词第二份）= 停手上报，不得自裁扩界。
>
> **执行序**：T1 → T2 → T3 → T4 → T5 → T6 → T7。T1-T5 产线码（每任务独立
> commit + 构建绿机检；App bundle MCP 两快照红窗自 T3 起见「风险与回退」第 1
> 条），T6 测试批一次落位（orchestrator 指定分批——测试集中在码面稳定后落
> 位），T7 轮次 + 收口。每任务独立 commit（Conventional Commits，全英文，只
> add 相关文件，不 push）。
>
> **基线**：**3905/35/0**（M7-3 三路全套同值；其后两跳 docs-only 零漂移；HEAD
> `0b34d199`）。全套预期 `3905+ΔN/35/0|`（ΔN 预期带 +21..28，对账式）。
>
> **快照改动权**：本波**显式取** union 文件改动权（27→29——M7-2/M7-3 权用讫，
> M7-4 在 M7-5 前串行执行取权合法，research §1.5）——**M7-5 禁并行**
> （orchestrator 编排保证）。

## 已定裁决（生效值，硬约束，不得重开）

OQ-M7-4-1..10 **全部按 RESEARCH §7 推荐裁**（CONTEXT D-M7-4-1..10）。本单
plan 承载全部十项；执行面速查：

1. **paste targets = session relPaths**（OQ-1）：maxItems 1000；headless =
   typed `notSessionMember` 诚实拒；库域批量写 → UPSTREAM-QUEUE。
2. **copy source 双形态**（OQ-2）：库 id digits + session relPath——
   `MatchColorToolset.resolveReference` verbatim 复用；无 editor-current 哨兵。
3. **无状态双动词**（OQ-3）：copy = 只读枚举预览；paste = source + targets[]
   一次性写（载荷无状态重读）；无剪贴板、无 list_tasks/wait_task（→
   UPSTREAM-QUEUE）。
4. **author 盖章 = `"mcp"`**（OQ-4）：apply_params/paste_adjustments 写 commit
   固定 token；版本级 author 悬置；GUI 写腿零 diff（author nil = user 隐式）。
5. **get_history 顶层 author = 最新 kept item 的 author**（OQ-5）：per-item 恰
   +note/author 两键；pristine .null。
6. **paste 不建版本**（OQ-6）：OVERWRITE epoch 既有语义；per-target 版本化 →
   UPSTREAM-QUEUE。
7. **S1 = bounded re-poll 250ms**（OQ-7）：POLLIN + 超时形 + revents 分流；
   恒可读 fd 忙旋消解；HUP/once/M1/http 四语义零改。
8. **S2 = A 预热 + C 文案**（OQ-8）：3 装配点 .utility 后台预热；list_luts
   description 冷首调句；**零新超时档**（新档支线不行使）；B → UPSTREAM-QUEUE。
9. **UQ-A2 typed 错 = 复用 `BaseNameOccupiedError`**（OQ-9）：link() EEXIST 表
   面一致；render 步快照检查保留（成本门，上游分歧 DECISIONS 申报）。
10. **includeDrt 默认 true + include 缺省全 transferable**（OQ-10）：GUI「默认
    全选可贴 + DRT 默认勾」镜像；mask 纪元重置恒生效。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/m7-4-mcp-o4/M7-4-CONTEXT.md`（D-M7-4-1..10 裁决 + 顺路件
  清算表 + 红线摘要 + 晨审推翻点索引）
- `.work/gsd/phases/m7-4-mcp-o4/M7-4-RESEARCH.md` §1（O4 全链 file:line）+
  §2（S1 病灶/修法/波及）+ §3（S2 机制链）+ §4（UQ-A2 TOCTOU 窗/修法/测试形）
  + §5（match_color 锚病）+ §6（测试策略 ΔN 表）
- `.work/config.toml [gsd]` paused/auto 开关（开工前亲核）
- `.work/LESSONS.md` L041（tuist generate 恒末位）+ CONVENTIONS「新测试文件落
  域规则」
- `App/Sources/Lightamer/MCP/McpToolRegistry.swift`（:61-111 McpToolError 16
  档封闭表 / :209-225 McpTimeouts——applyBatch 60s 既有档 / :335-355 writer
  gate）
- `App/Sources/Lightamer/MCP/Tools/EditingToolset.swift`（:141 register 面 /
  :591-685 apply_params body——gate/live 硬拒/probe/boundedWait/apply/flush 全
  框）+ `MatchColorToolset.swift` :549-602（resolveReference 双形态）
- `App/Sources/Lightamer/State/AdjustmentTransfer.swift`（:25-27 排除单源头注
  / :35-38 谓词 / :241-265 enumerate / :302-324 pastePayload）
- `LightamerCore/Sources/Export/ExportRenderer.swift`（:133-161 naming carrier
  + :655 encodeStage + :683-706 gain-map 臂）+ `ExportQueue.swift`（:489-493
  render 腿 carrier wrap + :521-528 encode 腿 wrap 点 + :710-732 productionLegs）

---

## T1 — S1 修复批首项（M7-3 挂账①）+ 探针迁 evidence + e2e 真断连回归

> **病灶**（research §2.1 双路三层复现在案）：`armStdioEOFReleaseOnce`
> （McpServerController.swift :388-408）poll `events: 0` 形 macOS 管道写端关闭
> 永不唤醒——「agent 断连 → checkpoint 优雅释放」面自 M6-1 `1f981f9b` 起实际
> 惰性。**修法 = 恰三点改形**（research §2.2 + OQ-M7-4-7）：poll 请求位
> `events: POLLIN` + 超时形 `poll(&fds, 1, 250)` + 醒后按 `revents` 分流。
> **四语义零改**：once guard / M1 `mode == .stdio` 自守卫 / close+exit(0) HUP
> 体 / http 臂不 arm。

**read_first**：`M7-4-RESEARCH.md` §2 全节（病灶 + 修法 + 回归脚本 + 波及面
五条）；`McpServerController.swift` :376-412（现体全文——Task.detached 内
poll 循环 + break 后 close+exit）；`M7-3-VALIDATION.md` §特殊事项 5（dup2
卫生注记——修后更 load-bearing）+ §挂账①⑥；`McpProjectArbitrationTests.swift`
（跨进程真二进制 spawn fixture——e2e 新法复用其定位/spawn 形）；
`/tmp/m73_probe/`（迁移源——probe.c / harness.c+sh / e2edrv*.c / e2e.sh）。

- **action**：
  1. **poll 体三点改形**（恰此三点，函数其余逐行零改）：
     ① `pollfd(fd: STDIN_FILENO, events: 0, revents: 0)` →
     `events: Int16(POLLIN)`（请求位**永不清**——「清位」只清 `revents`，措辞
     写实防误读）；② `poll(&fds, 1, -1)` → `poll(&fds, 1, 250)`（bounded
     re-poll——恒可读 fd〔测试面 dup2 /dev/null〕退化 4Hz .utility 低频循环，
     忙旋消解；真管道 HUP 阻塞至事件或 250ms 粒度，12s 活性窗无影响）；
     ③ 醒后分流保持 `count > 0 ∧ revents & (POLLHUP|POLLERR)` → break（HUP
     体 close + exit(0) 原样）；`count == 0`（超时）或纯 POLLIN → 只清
     `fds[0].revents = 0` 续 poll，**零字节消费**（watches HUP without
     stealing bytes 原意图保持——请求读取线程独占消费）。
  2. **探针源迁 evidence**：`/tmp/m73_probe/{probe.c, harness.c, harness.sh,
     e2edrv*.c, e2e.sh}` → `.work/gsd/phases/m7-4-mcp-o4/evidence/m73-probe/`
     （小件文本随本 commit；文件头各加一行来源注记——M7-3 第二路验收遗产，
     S1 三层复现证据正本）。
  3. **e2e 真断连新法**（McpProjectArbitrationTests additive，APP 域；fixture
     复用其真二进制 spawn 形）：spawn 产线宿主 `--mcp-stdio` → initialize 握手
     → `project_create`（临时目录；arm watcher）→ **关 stdin**（真 EOF 断连面
     ——仲裁测试 `child.terminate()` SIGTERM 从未真跑 HUP，本测试是第一个真
     HUP 腿）→ 断言 **exit ≤12s**（修复前此形 ≥12s 不退 = 已知失败形）→
     断言 **`.lalb-wal` 文件 size == 0**（close 的 TRUNCATE checkpoint 兑现证
     ——kill 形不可能产生此状态 = graceful face 正面证据）。可选腿（时间盒
     内顺手）：12s 窗内进程持锁期间第二 `project_open` = typed
     `projectReadOnly`（锁语义侧写）。
  4. **措辞校订注记**（挂账⑥ + DECISIONS H3③ + VALIDATION 特殊事项 5 三处；
     需求在此登记、落点在 T6 DECISIONS——**M7-3 签核文档不回改**，M7-3 CONTEXT
     L1 先例形）：修后 stdio 优雅面**成真**（此前双臂皆惰性：http = kernel
     地板、stdio = watcher 惰性）；不对称变为「stdio graceful / http
     kernel-floor」的**真实**差异（不再是「都惰性」的措辞高估）；dup2 卫生修
     后**仍必要且更 load-bearing**（无 dup2 测试宿主真 stdin 关闭即 exit(0)
     自噬；有 dup2 + 250ms bounded re-poll = 4Hz 循环不自噬不忙旋）。
  5. 构建绿机检 + `--bundle App` 定向绿（e2e 新法 + 既有 MCP 面全绿——MCP
     快照零触，本任务无红窗）。
- **验收标准（机检）**：
  - 构建绿；`git diff App/Sources/Lightamer/MCP/McpServerController.swift` 逐
    hunk 核 = poll 体恰三点（events 位 / 超时 250 / 分流清位面），once guard
    + M1 自守卫 + eofArmDone/eofArmLock + close+exit(0) 体零触。
  - grep：`events: Int16(POLLIN)` 在位；`poll(&fds, 1, 250)` 在位；
    `POLLHUP) | Int16(POLLERR)` 分流在位；`exit(0)` 恰原位一处。
  - `ls .work/gsd/phases/m7-4-mcp-o4/evidence/m73-probe/` 含 probe.c +
    harness.c + harness.sh + e2edrv*.c（迁移完整）；`/tmp/m73_probe` 原件留存
    不删（迁非移）。
  - e2e 新法绿（--bundle App 定向含之）；两断言（≤12s + wal==0）在断言文本中
    可 grep。
- **commit**: `fix(m7-4): wake the stdio EOF watcher on POLLHUP with a bounded re-poll`

## T2 — S2 A+C（预热 + 文案）+ S3 正臂腿（M7-3 挂账②③）

> **零新超时档**（D-M7-4-8）：`McpTimeouts` 零 diff——预热消解真实痛点（agent
> 首调即答），残余窗由 description 诚实覆盖；`withTimeout` v1 stuck-body 形不
> 动（B 线 → UPSTREAM-QUEUE）。

**read_first**：`M7-4-RESEARCH.md` §3（机制链 + 三选项表 + 推荐序）；
`LutLibraryStore.swift` :103-120（shared holder + replaceShared）；`McpProjectToolsetTests.swift` :444-469（makeGuiShapedProvider/stub heldTargets 形）+
:495/:514（现两腿 heldTargets: []——正臂腿照此 additive）。

- **action**：
  1. **A 预热**：McpServerController 加内部一行 helper（如
     `static func warmLutLibrary() { Task.detached(priority: .utility) { _ =
     LutLibraryStore.shared } }`——fire-and-forget；swift_once 幂等底层，多调
     无害）+ **恰 3 装配点调用**：`startHeadlessStdioHost`（:524 段宿主启动
     处）/ `startHTTPHost`（:754 段）/ GUI 装配段（LightamerApp 内嵌 MCP
     context 装配同段）。预热窗内到达的首调仍阻塞 swift_once（至多 ~50s）=
     概率性收窄至启动邻域——description 句如实覆盖。
  2. **C 文案**：`mcp_tool_desc_list_luts` **原位值改**（en defaultValue + zh
     译文同批）——追加冷首调代价句（首次调用在库预热完成前至多 ~50s；短超时
     客户端建议重试）。非尾块插入 = DECISIONS 申报形。
  3. **S3 正臂腿**（McpProjectToolsetTests additive，零产线代码）：复用
     `makeGuiShapedProvider(stub:heldTargets:)` 传**非空 heldTargets**（目标 =
     当前在持项目）→ 断言差分谓词正臂可达——`pendingConflict` before==nil ∧
     after!=nil ∧ `projectStore` 未变 → 工具应答 typed `projectReadOnly` 携
     holder summary（防御网 clause 的确定性触发形；现两腿 :495/:514 均
     heldTargets: [] 走不到）。O1 同形复制漂移裁定：复制体在测试桩内，产线单
     源由 T3 Catalog 抽取建立——**漂移注记维持不另抽**（DECISIONS 一句）。
  4. 构建绿机检 + grep 结构核（golden 面零新增——S3 腿即测试，随本 commit 绿
     门）。
- **验收标准（机检）**：
  - 构建绿；grep：`warmLutLibrary` 恰一处定义 + 恰三调用点（stdio/http/GUI）；
    `Task.detached(priority: .utility)` 在 helper 内；`McpTimeouts` 文件零
    diff（新档支线不行使机检）。
  - `git diff Resources/Localizable.xcstrings` 逐 hunk 核 = 恰 list_luts 原位
    一处（历史键字节与顺序零触碰）。
  - S3 正臂腿绿（--bundle App 定向含之）；断言文本含三 clause（before==nil /
    after!=nil / store 未变）可 grep。
  - `git diff --stat` T2 恰四文件（McpServerController + LightamerApp +
    xcstrings + McpProjectToolsetTests），无它。
- **commit**: `fix(m7-4): preheat the LUT store and pin the gui readonly predicate leg`

## T3 — O4 双工具 + MCP2-09 note/author 归属（MCP2-08..09）

> **单源红线**：`isAdjustmentTransferable` 全仓恰单一函数定义（AdjustmentTransfer.swift 头注 :25-27 纪律延续）——Catalog 抽取 = 枚举/载荷构建纯函数
> 化，GUI model 与 MCP toolset **双消费**，禁复制形。**错误码零新增**（invalidParams/notSessionMember/projectReadOnly/imageLiveInEditor/serverReadOnly/internalError 全既有）；**超时档零新增**（applyBatch 60s 既有档消费）。

**read_first**：`M7-4-RESEARCH.md` §1 全节（单源盘点表 + 工具语义 + note 面 +
writer 面 + union 评估）；`AdjustmentTransfer.swift` :20-330（model 全形——
enumerate :241-265 / pastePayload :302-324 / mask 纪元重置 :311-313）；
`EditingToolset.swift` :591-685（apply_params 全框——逐段照抄形）+ :141-160
（register 面——双工具注册落此）；`SearchStateToolset.swift` :860-905（get_history 顶层 payload + :897-900 author 占位）+ :930-945（per-item dict）；
`HistoryStack.swift` :61-185 + :131-133（CodingKeys 现九键）；
`HistoryHash.swift` :37-130（折叠面——item 元数据不入折机制证）；
`SessionBatchApplier.swift` :232-296（apply 三段批 + CarriedDocumentState）；
`PasteSemantics.swift` :69-100（paste 签名 + UUID recast）；
`EditorToolRailView.swift` :199-235（historyRow——T6 GUI 面落点预读）。

- **action**：
  1. **AdjustmentTransferCatalog 抽取**（AdjustmentTransfer.swift 内，零新文
     件）：纯 helper（enum/struct 均可，无 @MainActor 依赖）——
     `enumerateSnapshot(chain:)`（LayerStackProjection.rebuild → nodes/items
     快照 + transferable 计数 + drtRecord/versions 面）与
     `buildPayload(snapshot:include:includeDrt:)`（checked 实例平铺 + layer
     snapshot + **mask.contentRevision 置 nil** + DRT 行；include 缺省 = 全
     transferable；includeDrt 缺省 true）。`AdjustmentTransferModel
     .enumerate(chain:)`/`pastePayload()`/`setChecked` 等改委托 Catalog（GUI
     行为零 diff——M2-8 既有 AdjustmentTransferTests 全绿作守卫）；头注排除单
     源句随形更新（「panel 与 batch face 共享 Catalog」）。
  2. **HistoryItem additive 两字段**（HistoryStack.swift）：`note: String?` +
     `author: String?`——存储属性 + init 默认参 `= nil` + CodingKeys 追加两
     case + decodeIfPresent/encodeIfPresent（drtRecord/filmRecord 同族形；
     **nil 不编码** = 无字段不入 bytes）；schemaVersion 零动；`PasteSemantics
     .paste` 与 `SessionBatchApplier.apply` 各加 additive 默认参
     `note: String? = nil, author: String? = nil` 透传至 HistoryItem（缺省 =
     既有调用方零 diff——M2-8 GUI Copy Adjustments 面零触）。
  3. **copy_adjustments**（EditingToolset.register additive）：descriptor 零
     入参外仅 `source`（string 必填）+ `readOnlyHint: true` + writer 缺省 +
     超时 `McpTimeouts.list`；body = source 双形态 resolveReference（库 id
     stale → typed `notSessionMember` 携 relink reason）→
     `ExportRenderer.readDocument` 读源链 → `Catalog.enumerateSnapshot` →
     应答 JSON `{source, versions[]（v7 版本行 + active 标记）, selectedVersion,
     grades[]（每 Grade 层 {id, name, chainCount, transferableCount, items[
     {instanceId, opName, multiPriority, enabled, transferable}]}）, drt:
     {present, eligible}, summary}`——不可贴行 greyed 计数面（visible-not-
     silent，M2-8 头注纪律）。**不落任何服务端状态**。
  4. **paste_adjustments**（register additive）：`requiresWriter: true` +
     `destructiveHint: true` + 超时 `McpTimeouts.applyBatch`；schema =
     `source`（string 必填）/ `targets`（array of string，**maxItems 1000**，
     必填）/ `note`（string，minLength 1，optional）/ `include`（array of
     string = instanceId 列表，optional，缺省全 transferable）/
     `includeDrt`（bool，默认 true）/ `version`（string，optional，缺省
     active）。body = gate（McpRenderGate 串行）外框 → per-target 前置**全部
     在 gate 内、预算窗外**（fast local reads，apply_params :609-634 同理）：
     membership（resolveMember 同形；失败 = per-target rejected
     notSessionMember 行）→ **live 硬拒**（seams.liveImageURL() 比对——命中 =
     per-target rejected imageLiveInEditor 行，**不是 skip**——MCP 无
     interactive layer，SessionBatchApplier 的 liveRelPaths 软跳语义在 MCP 帖
     面翻成 typed 分账，match_color attach 先例同判）→ `rejectIfProjectReadOnly`
     （probe held = 全调 typed projectReadOnly）→ 预算窗内
     `boundedWait(seconds: applyBatch)`：源链无状态重读（非 copy 应答缓存）→
     `Catalog.buildPayload` → `SessionBatchApplier.apply(root:, relPaths:
     targets〔全部前置清场，liveRelPaths: []〕, payload:, mode: .overwrite,
     seed: editingSeed 同源, note:, author: "mcp", label: "MCP
     paste_adjustments")` → **flushForTeardown 写达后方返**（apply_params
     :676-678 同款——agent 下一步 get_history/render_preview 读到新状态无
     drain race）。应答 = per-target 结果列 `{targets: [{relPath, status:
     applied|rejected(reason)}], appliedCount, note, author}`；全拒批 =
     appliedCount=0 诚实应答非 throw（reason 列自解释——DECISIONS 钉形）；
     compose/claim 未落 = internalError 兜底（apply_params 同形）。
  5. **apply_params note 参 + 双工具盖章**：apply_params schema 恰 +`note`
     属性（string，minLength 1，optional）+ body 透传；两写工具 commit 恒
     `author: "mcp"`（固定 token）；note 缺省 = 无字段不入 bytes。
  6. **get_history 读面**（SearchStateToolset）：per-item dict 恰 +2 键
     `"note"`/`"author"`（item 字段缺省 .null）；顶层 `"author"` 占位（:897-900
     注记段）翻转为 **position 位 item（最新 kept item）的 author**（缺省
     .null；pristine/空链 .null）——占位注释随消费体替换。
  7. **xcstrings 两新键**：`mcp_tool_desc_copy_adjustments` /
     `mcp_tool_desc_paste_adjustments` 尾块纯插入（zh-only 形——description 含
     requiresWriter/destructive 语义句 + source 双形态句 + paste 预算边界句
     ≤1000 targets）。
  8. 构建绿机检 + grep 结构核（golden 随 T6；本任务 gate = 构建绿——App bundle
     快照红窗自本任务起，见风险第 1 条）。
- **验收标准（机检）**：
  - 构建绿；grep：`isAdjustmentTransferable` 全仓恰单一 `func` 定义（零第二
    份排除逻辑）；`requiresWriter: true` 在 paste_adjustments 恰一处 +
    `readOnlyHint: true` 在 copy_adjustments；`maxItems.*1000` 在 paste
    schema；`McpTimeouts.applyBatch` 消费点在 paste body；`"MCP
    paste_adjustments"` label 在位；`author.*"mcp"` 盖章在双写工具 body；
    `flushForTeardown` 在 paste body（写达后方返）。
  - `git diff LightamerCore/Sources/Pipe/History/HistoryHash.swift` = 零 diff
    （折叠面零触）；`git diff .../HistoryStack.swift` 逐 hunk 核 = 恰两字段 +
    init 默认参 + CodingKeys 两 case。
  - `git diff App/Sources/Lightamer/MCP/McpToolRegistry.swift` = 零 diff（错
    误码/超时封闭表零触）。
  - 既有 apply_params/SessionBatchApplier 调用方零 diff（缺省参 = 编译零改；
    `git diff` 面核 :591-685 除 note/additive 外零触）。
  - xcstrings diff 逐 hunk 核 = 恰两尾块插入。
- **commit**: `feat(m7-4): add the adjustment copy/paste tools and note attribution`

## T4 — UQ-A2 导出 FAIL 档终写原子不覆盖

> **TOCTOU 窗**（research §4.1）：render 步 9 occupiedNames 快照检查与 encode
> `.atomic` rename（Darwin 无条件替换）之间他进程建同名文件 → 被静默覆盖。
> **修法**：encodeStage additive 一参 + tmp 同目录 encode + `link()` EEXIST 拒
> 晋升；**policy 递缝 = `$jobNamingCarrier` wrapper**（`$jobExifSoftware` 同款
> 纪律——M2-9「递缝三件套」范式第四例）；**与上游 `6203791` 唯一分歧 = 保留
> render 步快照检查**（渲染前成本门；正确性门 = link() EEXIST）。

**read_first**：`M7-4-RESEARCH.md` §4 全节；`ExportRenderer.swift` :625-645
（步 9 命名 + `.fail` 快照门——**零触**）+ :652-782（encodeStage 全形：签名尾
`hdrGainPlane` / `.atomic` 写 / gain-map 臂 :683-706 早退 / ICC strip
:744-758 / XMP mount :761-777）+ :133-161（carrier 结构 + `$jobNamingCarrier`
TaskLocal）；`ExportQueue.swift` :483-533（render 腿 :489-493 carrier 装配 wrap
形 + gate ③ :506-516 + encode 腿 :521-528 双 wrap 点）+ :705-732（productionLegs
encodeLeg 体）；`ExportNamer.swift` :30-40/:110-140（BaseNameOccupiedError 形 +
`.fail` 门——**零触**）。

- **action**：
  1. **encodeStage additive 参数**：签名恰尾追
     `exclusiveFinalWrite: Bool = false`（缺省 = 既有调用方零 diff）。true 时：
     encode 目标改**同目录隐藏 tmp**（`.<name>.<uuid>.tmp`——同目录 = 同卷，
     link() 无 EXDEV 面）；post-encode 两腿（ICC strip / XMP mount）在 tmp 上
     原位跑（destination 形参喂 tmp——文件内操作与目标无关）；晋升 =
     `link(tmpPath, destPath)`：成功 → `unlink(tmp)`（双链接收敛单链接）；
     **EEXIST** → `unlink(tmp)` + `throw
     ExportNamer.BaseNameOccupiedError(name: destPath.lastPathComponent)`（复
     用既有 typed，OQ-M7-4-9）；其它 errno → `internalError` 形（16 档封闭表
     零新增）；**defer 清 tmp**（任何 throw 路径零残留——现「throw cleans
     pre-rename residue」纪律延伸到 tmp 形）。`.replace`/缺省路径保持 plain
     rename（覆盖语义原样，负测钉住不误伤）。
  2. **gain-map 臂同 wrap**：`ExportGainMapEncoder.encode` 的 destination 形参
     喂 tmp + 同款 link 晋升（其 post-encode 腿本就跳过——早退面直包即可）；
     exclusiveFinalWrite false = 现行为逐字节。
  3. **policy 递缝**（ExportQueue）：encode 腿调用点（:521-528 段）加一层
     `ExportRenderer.$jobNamingCarrier.withValue(namingCarrier)` additive
     wrapper——namingCarrier 装配 = render 腿 :489-492 **同形**（queued.naming
     / collisionPolicy / subfolder）；`encodeLeg` 体（productionLegs :710-732）
     内读 `ExportRenderer.jobNamingCarrier?.collisionPolicy == .fail` →
     `encodeStage(..., exclusiveFinalWrite: true)` 传参。**contract-frozen leg
     签名零 diff**（闭包形 `(StageOutput, ExportVariant) throws -> URL` 不
     动）；直连 renderStage+encodeStage 的测试/E2E 调用方显式传参（缺省 nil
     carrier = false = 既有行为逐字节）。
  4. **测试四腿**（ExportRendererE2ETests additive，EXPORT 域；§4.3 必做）：
     ①**TOCTOU 负测**——renderStage（destination 已落 StageOutput）→ **手工在
     destination 建文件**（确定性交错注入）→ `encodeStage(exclusiveFinalWrite:
     true)` → 断言 typed `BaseNameOccupiedError` + **destination 字节不变**
     （预植内容 byte-compare）+ 目录无 tmp 残留（glob `.*.tmp` 断言零命中）；
     ②**正向恒等**——exclusive 形 ≡ 非 exclusive 形同平面产物 byte-equal
     （exclusive 只改晋升方式不改产物）；③**`.replace` 负面守卫**——目标存在
     + replace 档（exclusiveFinalWrite=false 路径）→ 覆盖仍发生；④
     **`.increment` 字节冻结**——既有 E2E increment face 全绿即守卫（零新增
     法）。可选腿（时间盒）：queue 级腿（.fail job + 占名快照空集 + encode 前
     真建文件 → job typed fail 无覆盖——wrapper 递缝成立证）/ gain-map 变体
     （同形①）。
  5. 构建绿机检 + `--bundle EXPORT` 定向绿。
- **验收标准（机检）**：
  - 构建绿；`git diff LightamerCore/Sources/Export/ExportNamer.swift` = 零
    diff；`git diff .../ExportRenderer.swift` 逐 hunk 核 = 恰签名尾追 + tmp/
    link/defer 段 + gain-map wrap 段（步 9 `.fail` 快照门 :633-637 零触——
    render 快照检查保留机检）；`git diff .../ExportQueue.swift` 逐 hunk 核 =
    恰 encode 腿 wrapper 层 + encodeLeg 读点（leg 闭包签名零 diff）。
  - grep：`exclusiveFinalWrite` 在 encodeStage 签名恰一处（缺省 false）+
    queue encodeLeg 读点一处；`link(` 在 exclusive 晋升处；`BaseNameOccupiedError`
    复用（零新 typed case——McpToolRegistry/Core 错误表零 diff）。
  - 四腿绿（--bundle EXPORT 定向含之）；TOCTOU 负测断言三件（typed 错 / 字节
    不变 / 无 tmp 残留）可 grep。
- **commit**: `fix(m7-4): make the FAIL collision tier reject on final write via link`

## T5 — match_color provider projectDirectory 勘正（M7-3 挂账⑤ + M7-2 挂账⑤）

> **病灶**（research §5）：GUI 装配点 LightamerApp :1364-1372 传 `url =
> libraryProjects.projectURL`（**.lalb 文件 URL**）充作 projectDirectory——
> ImageLinker.resolve kind0 臂（:152-156 `appendingPathComponent`）与 kind1
> 快路径产出坏路径。未爆因 = golden 全走 absolute kind 行。**O4 copy source 库
> id 形骑同一 provider 面**——写面前卫生前提，同一缝两波触碰 = churn。

**read_first**：`M7-4-RESEARCH.md` §5；`LightamerApp.swift` :1360-1375（provider
装配段）；`ImageLinker.swift` :145-165（kind0/1 消费面）；`MatchColorToolset.swift`
:549-602（resolveReference——零改，只勘正 provider 喂入）；
`McpMatchColorToolsetTests.swift` :170-185/:395-410（两测试 provider packageURL
同病点）。

- **action**：
  1. **GUI 装配点恰一行**：return 行 `(LibraryStore(store: store), url)` →
     `(LibraryStore(store: store), url.deletingLastPathComponent())`（目录锚
     ——fix `20997721` 先例形；searchState 两装配点 M7-3 已勘正，此为同族第三
     实例收口）。
  2. **两测试 provider 同形勘正**（:177/:402 packageURL → 目录锚）。
  3. **kind0 锚腿新法**（McpMatchColorToolsetTests additive）：库种行 fixture
     （imagePath = `Media/x.jpg`, pathKind = 0）→ id 形 reference resolve →
     断言 resolved URL == `<projectDir>/Media/x.jpg`（锚正确性正面证据——
     absolute kind 行永远抓不到此病，T5 golden 抓获 20997721 同族教训）。
  4. 构建绿机检 + `--bundle App` 定向绿。
- **验收标准（机检）**：
  - 构建绿；grep：`installLibraryProvider` 段内 `deletingLastPathComponent`
    恰一处；两测试 provider 同形（grep packageURL 零残漏）。
  - kind0 锚腿绿；resolved URL 断言文本可 grep。
  - `git diff App/Sources/Lightamer/UI/LightamerApp.swift` 本任务 hunk 恰一行
    （T2 预热点之外的增量面核）。
- **commit**: `fix(m7-4): anchor the match_color library provider at the project directory`

## T6 — 测试批：union 27→29 全点位 + 新工具/归属 golden + GUI 面 + 零回归

> **orchestrator 指定分批**：测试集中本任务一次落位（T1-T5 码面稳定后；T1 e2e
> 与 T2 S3 腿已随各自任务落位）。**union 显式改 = 本波显式取权**——全点位清
> 单落位 + DECISIONS 申报。**两层 consciously change together**（M5-1-03 先例
> 形）：apply_params schema note 行 = editing 域层 + union 层同批显式改。
> **F-1 家族防复发**：union 外计数钉点位清单对照 M7-3 五钉教训列全（fresh 坐
> 标）+ 残漏 grep 收口。

**read_first**：`M7-4-RESEARCH.md` §6（测试策略表）；`McpFinalSnapshotTests.swift`
（:20 头注 / :219 all27 / :225 makeUnionRegistry / :244 test 名 / :249-260
计数 + destructive 集 / :299/:327 组合代数计数 / :334 descriptionKeys /
:479 directTools 计数——union 显式改全点位 fresh 坐标）；`McpRegistrySnapshotTests.swift`
（:150-165 editing 冻结表行区 + :203 计数钉）；`McpSearchStateToolsetTests.swift`
:274（钉）+ `McpHostTests.swift` :243/:697（钉）+ `McpLauncherTests.swift` :200
（钉）；`SidecarV10Tests.swift`（roundtrip/drift 先例形）；`EditorToolRailView.swift`
:199-235（historyRow 落点）。

- **action**：
  1. **union 显式改全点位**（McpFinalSnapshotTests）：冻结表 +2 行（copy/
     paste——descriptors() 名序亲核后落）+ apply_params schema 行同批（note
     属性）+ 计数断言 ×4（:249/:299/:327/:479）27→29 + **destructive 集 9→10**
     （:255-260 集断言 + paste_adjustments——注释非易碎形随批改写）+
     descriptionKeys +2 行（:334）+ `all27` → `all29`（:219 定义 + :247 引用
     同批改名）+ 测试名 `testFinalSnapshotUnion27Verbatim` → `...Union29...`
     （:244）+ 头注 :20 + message :250/:327 过时计数同批改写——DECISIONS 附
     点位清单。
  2. **editing 层显式改**（McpRegistrySnapshotTests）：apply_params schema 行
     （note）+ copy_adjustments/paste_adjustments 两行加入（editing 7→9）+
     **:203 计数钉显式改**（21→22 + message 同批）——与 union 层同批。
  3. **union 外五钉显式改**（F-1 家族防复发，M7-3 五钉教训清单形）：`McpRegistrySnapshotTests :203`（上条）/ `McpSearchStateToolsetTests :274` /
     `McpHostTests :243` / `McpHostTests :697` / `McpLauncherTests :200`——
     21→22 + message 同批（「M7-4 copy/paste joined」句式）。
  4. **残漏 grep 收口**：全仓 MCP 测试面 `count, 21` / `count == 21` /
     `all27` 零命中（防第六处）；「27-tool」注释形态随手清（清单内文件）。
  5. **O4 golden**（McpEditingToolsetTests additive + AdjustmentTransferTests
     additive）：**枚举恒等**（同链 fixture → GUI model `pastePayload` ≡
     `AdjustmentTransferCatalog` 产物实例集逐参恒等——no-second-copy 红线机
     检正面）+ mask 纪元重置断言（贴后 `contentRevision == nil`）+ 两形态寻址
     （库 id kind0 行 + session relPath）+ greyed 计数 + DRT present/eligible
     面 + paste per-target applied|rejected 分账 + live 硬拒 + probe held 拒
     （projectReadOnly 携 holder summary）+ membership 拒 + include 子集 +
     includeDrt=false（DRT 行不随）+ label `"MCP paste_adjustments"` 进
     HistoryItem + flush 写达后方返（apply 后立即 readDocument 断言新态）。
  6. **MCP2-09 golden**（SidecarV10Tests additive〔LAYERS 域〕+
     McpSearchStateToolsetTests additive）：note/author roundtrip（sidecar
     字节——写读恒等）+ **nil 不编码负测**（缺省 commit 旧档字节零漂移）+ 旧
     档 tolerant decode 负测（缺两键旧档读回 note/author == nil）+
     **HistoryHash 不变负测**（同编辑态 note/author 有无 → hash 逐位同）+
     get_history per-item 两键 + 顶层 author 翻转（pristine .null / 盖章后
     = "mcp"）。
  7. **GUI 面**（EditorToolRailView）：historyRow = note 副标题（caption2 单行
     截断，nil 不占位）+ author 徽章（`"mcp"` 徽章文本 + AX label =
     `editor_history_author_badge` 键；nil 无徽章）；xcstrings 第三新键尾块
     纯插入。VersionsPanelView 零触（版本级 author 悬置）。
  8. **零回归门**：既有 27 工具 descriptor/handler 零 diff（除 apply_params
     申报内 note 行——`git diff` 面 + 快照门双证）；`McpProjectArbitrationTests`
     既有法全绿；`McpProjectToolsetTests` 既有法全绿（S3 腿随 T2 已落）；
     AdjustmentTransferTests 既有法全绿（Catalog 委托零 diff 守卫）；
     ExportRendererE2ETests 既有法全绿（encodeStage 缺省参零 diff 守卫）。
  9. **zh-audit 对账**：`uv run python3 Scripts/zh-audit.py --check` PASS
     （source keys +3 对账：两 desc + 一徽章键；list_luts 原位改不入计）+
     `--self-test` PASS。
- **验收标准（机检）**：`--bundle App` 全绿（红窗闭合点）+ `--bundle Layers`
  全绿（SidecarV10 新法）；快照显式改申报在 DECISIONS（点位清单附）；残漏
  grep 零命中；既有 27 工具零 diff 面核；zh-audit 双 PASS。
- **commit**: `test(m7-4): pin the o4 goldens and grow the union snapshot to 29`

## T7 — 定向轮 + 全套 `--all` + 红线族 + 收口翻账

- **action**：
  1. **定向轮**：`caffeinate -dis Scripts/test-direct.sh --bundle App --bundle
     Layers --bundle EXPORT` 全绿（App = MCP 面 + Catalog + e2e + S3；Layers =
     sidecar/hash 归属面；EXPORT = UQ-A2 四腿——三域覆盖本批全部新测试面；
     IOP/IOPParity 消费方随全套轮验证）。
  2. **全套确认轮**：`caffeinate -dis Scripts/test-direct.sh --all`
     （**批准制**——本 plan 标注在案，执行时 orchestrator 派发 prompt 即批
     准；运行中保持监视 + 8G 门 + MEMFAIL 机检，超门立即 kill）。
     `TOTAL|3905+ΔN/35/0|` 对账精确闭合（ΔN 逐任务记账；skip 35 构成声明——
     本波零 skip 门新测试，第三种 skip 来源 = 逐族差分申报禁静默吸收）。
  3. **红线族机检**（front-matter `red_lines` 逐条亲跑）：零新 SPM / `.metal`
     全域零 diff / 封存面逐件零 diff（含申报内例外面核：encodeStage 恰一参/
     ExportQueueContract leg 形零 diff/ExportNamer 零 diff）/
     HistoryHash.swift 零 diff / McpToolRegistry.swift 零 diff / McpTimeouts
     零 diff / controller 文件零 diff / isAdjustmentTransferable 单函数 grep /
     xcstrings 恰三尾块插入 + 一原位改 / UserDefaults 零新键 / runModal 零
     命中 / LocalizationValue 插值禁形零命中 / Project.swift 与 BUNDLE-MAP
     零行变更核（或申报内恰行）。
  4. **SUMMARY + DECISIONS**：逐任务 ΔN 记账 + union 显式改点位清单 +
     destructive 9→10 申报 + list_luts 原位改申报 + UQ-A2 上游分歧申报（保留
     render 快照检查 = 成本门）+ **⑥/H3③/特殊事项 5 三处措辞校订注记**（M7-3
     签核文档不回改——T1 action 4 需求在此兑现）+ S3/O1 漂移注记维持裁定 +
     全拒批诚实应答形 + tmp 命名/清理终形 + S2 预热观察证据（e2e/验收轮实测
     冷窗收敛记录，非门值）+ 中间红窗处置申报。
  5. **翻账**：REQUIREMENTS MCP2-08..09 + UQ-A2 → Delivered（M7-4 commit 指
     针）；AGENTS「M7-4 架构增量」节；TODO（M7-4 条目 + 挂账①②③⑤⑥收口 +
     FIX2③ 第三波维持）；GOAL-STATE 续接点（M7-4 收口 → next = M7-5，**union
     改动权移交**注记）；UPSTREAM-QUEUE 三观察项入队（tasks/wait_task 面 /
     paste per-target 版本化 / 库域批量写 + withTimeout v2 B 线）。
- **验收标准（机检）**：三域定向轮绿 + 全套 exit 0 / 0 fail / 0 MEMFAIL /
  七 bundle 8G 门内 + 对账闭合 + 红线族全 PASS + zh-audit 双 PASS + 五台账
  同批落盘（历史行只追加不改写）。
- **commit**: `docs(m7-4): reconcile the full suite and close the M7-4 ledgers`

---

## 风险与回退

- **快照红窗（T3..T6 App bundle 中间态，已申报）**：copy/paste 注册自 T3 起
  union/editing 两层快照红（计数 27≠29 + 21≠22）至 T6 显式改收口；**每任务
  gate = 构建绿 + 定向非 App bundle 绿（T1 App〔无红窗——快照零触〕/ T4
  EXPORT）**；T6 `--bundle App` 为红窗闭合点；T7 全套轮终证。**禁为凑绿在
  T3-T5 提前改快照**（显式改集中 T6 一批 = 全点位亲核审计面）。
- **S1 e2e 稳定性**：真二进制 spawn + 真 EOF 面受构建产物定位/宿主启动时序
  影响——fixture 复用 McpProjectArbitrationTests 既有 spawn 形（已实战）；若
  in-process 环境抓不到真 HUP（dup2 干扰）→ e2e 独立成新测试文件（登记纪律
  申报形）或降级为 acceptance 证据脚本（DECISIONS 申报），禁静默放宽 12s 窗。
- **paste 大批预算**：≤1000 targets × applyBatch 60s 窗——compose 零渲染红线
  保证小常数；超窗 = internalError 兜底臂（幂等可重试，apply_params 同文案
  族）；实测超窗才立项 tasks 面（UPSTREAM-QUEUE），本波不做服务端降档。
- **Catalog 抽取回归**：GUI model 委托改形若引入行为差（selection/checked 态
  重建时序）→ M2-8 既有 AdjustmentTransferTests 全绿门 + T6 枚举恒等 golden
  双门抓；违例 = 回注 T3 修复。
- **UQ-A2 tmp 残留**：任何 throw 路径 defer 清 tmp——断言 glob 零残留钉死；
  link() 在 APFS 外卷语义（本项目导出目录皆本地卷）不做特殊分支，其它 errno
  internalError 兜底。
- **destructiveHint 语义**：paste_adjustments destructiveHint:true → destructive
  集 9→10——M2-9 Export 页冲突档/UI 零联动面（MCP 注解纯描述面）；若 checker
  判「overwrite 粘贴非 destructive」→ 降 readOnly 级注解 = 快照集断言同步
  改，DECISIONS 申报（不静默）。
- **预热副作用**：3 装配点 .utility 后台 ~50s CPU——GUI 机与启动工作并发实测
  无感面待走查（S2 观察证据）；测试面 replaceShared 注入小 store 不受扰（预
  热只触 shared getter）。
- **T6 大批量测试后置**（orchestrator 指定分批内在风险）：T3-T5 码面缺陷在
  T6 才暴露 → 回注对应任务修复（fix commit + T6 重跑），禁为凑绿放宽断言；
  golden 任一不恒等 = 停手归因。
- **快照族冲突**：本波持 union 改动权——若 orchestrator 误并行派发 M7-5 →
  立即停手上报，禁抢先合并快照表。
- 全套轮任何 fail：先归因（本批 Δfiles 窗内?）——窗外 fail = 既有缺陷，停手
  上报不静默修。

---

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：ROADMAP §M7-4 行 ↔ 任务面逐项映射——O4 双工具
   （T3 工具面 + T6 golden）/ MCP2-09 归属（T3 字段/读面 + T6 GUI 面 + golden）
   / UQ-A2 原子终写（T4 + TOCTOU 负测）/ S1-S3 挂账清算（T1/T2 + 措辞注记）；
   REQUIREMENTS MCP2-08..09 + UQ-A2 无孤儿项；Alcedo 对表锚（adjustments
   copy/paste / 输出防覆盖）→ 偏离申报面（items 并入 copy 应答 / 保留 render
   快照检查 / 无 per-target 版本——CONTEXT D-M7-4-3/6/9 申报）。
2. **OQ 兑现核**：D-M7-4-1..10 逐条对任务面——①targets session 域 + maxItems
   1000（T3 schema）②双形态 resolveReference 复用（T3 + grep 调用点）③无状
   态双动词 + 无 tasks 面（T3——grep 剪贴板/服务端态零命中）④author="mcp" 固
   定 + GUI 写腿零 diff（T3——grep 盖章点 + GUI 面零触）⑤顶层 author 翻转 +
   pristine .null（T3 + T6 golden）⑥零版本面（T3——versions 面零触 grep）⑦
   bounded re-poll 三点改形 + 四语义零改（T1——diff 逐 hunk 核）⑧预热 3 点 +
   零新档（T2——grep warmLutLibrary + McpTimeouts 零 diff）⑨BaseNameOccupiedError
   复用 + render 快照保留（T4——diff 面核 :633-637 零触）⑩includeDrt 默认
   true + include 缺省全贴（T3 schema + golden）。
3. **快照族纪律**：union 显式改全点位（fresh 坐标清单：计数 ×4 :249/:299/:327/
   :479 + destructive 集 :255-260 + descriptionKeys :334 + all27→all29 :219 +
   测试名 :244 + 头注 :20 + message :250/:327）+ editing 层（apply_params note
   行 + 两新行 + :203 钉）+ **union 外五钉显式改**（:203〔同文件连带〕/:274/
   :243/:697/:200——M7-3 后行号漂移，fresh 坐标已亲核）+ 残漏 grep（`count,
   21` / `count == 21` / `all27` 零命中）+ DECISIONS 点位清单申报；
   「本波显式取权 + M7-5 禁并行」在 plan 头注与红线双写。
4. **单源红线**：isAdjustmentTransferable 全仓恰单一函数定义（grep 机检）；
   Catalog 双消费形（GUI model 委托 + MCP toolset 直调——零复制形）；mask 纪
   元重置在 Catalog buildPayload 恰一处（:311-313 逻辑搬迁非复制）。
5. **S1 修复语义钉**：恰三点改形（events 位 / 250ms / revents 分流）——once
   guard + M1 自守卫 + close+exit(0) + http 不 arm 四语义零改（diff 逐 hunk
   核）；「清位 = revents 非 events」在 action 与断言双写实；e2e 两断言（≤12s
   + wal==0）为修复核心判据（kill 形不可能产生 wal==0 = graceful 正面证）。
6. **HistoryItem additive 面**：恰两字段 + init 默认参 + decodeIfPresent/
   encodeIfPresent + nil 不编码（diff 逐 hunk 核）；HistoryHash.swift 零 diff
   + 负测（同态有无 note/author → hash 逐位同）；旧档字节零漂移负测；GUI 写
   腿零 diff（author 恒 nil）；schemaVersion 零动。
7. **UQ-A2 缝纪律**：encodeStage 恰 additive 一参（缺省调用方零 diff——既有
   EXPORT 测试面零改全绿）；ExportQueueContract leg 形零 diff（wrapper 递缝非
   签名改）；ExportNamer 零 diff + render 快照门零触；gain-map 臂同 wrap；tmp
   defer 清理 + glob 断言；BaseNameOccupiedError 复用（错误表零 diff）。
8. **SC 可机检性**：每条 SC 有命令级判据（byte-equal / grep / 计数断言 / 对账
   行 / 定向 bundle 绿），非「目测」；expected_all 对账式非死数；skip 35 构成
   声明条款在 T7。
9. **xcstrings 双形纪律**：三新键尾块纯插入（历史键字节与顺序零触碰——diff 逐
   hunk 核）+ list_luts **原位值改**（非插入——DECISIONS 申报）；描述键显式
   String(localized:defaultValue:) 形态（插值禁形 regex 零命中）；zh-audit
   --check（+3 对账）+ --self-test 双 PASS。
10. **登记纪律**：预期 Project.swift / BUNDLE-MAP 零行变更（全 additive）——
    若新建测试文件 = 恰一行 + BUNDLE-MAP 恰一行 + tuist generate 恒末位
    （L041）+ DECISIONS 申报；commit 顺序核（登记与测试同 commit，generate
    最后动作）。
11. **零回归面**：既有 27 工具 descriptor/handler 零 diff（除 apply_params 申
    报内 note 行）；AdjustmentTransferTests / ExportRendererE2ETests /
    McpProjectArbitrationTests / McpProjectToolsetTests 既有法全绿；`--all`
    3905+ΔN 对账闭合（skip 35 构成声明）；GUI Export 面/Copy Adjustments 面
    零触（controller 零 diff 门第三波）。
12. **措辞校订兑现核**：T6 DECISIONS 含三处校订注记（⑥ 双臂不对称 / H3③
    graceful 面 / 特殊事项 5 dup2）+ M7-3 签核文档零 diff（不回改纪律 grep
    git diff 核）+ UPSTREAM-QUEUE 三观察项入队（tasks 面 / per-target 版本 /
    库域批量写 + B 线）。
