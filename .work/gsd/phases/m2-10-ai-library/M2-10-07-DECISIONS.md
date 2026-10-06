# M2-10-07 DECISIONS — 执行批裁决记录（2026-10-04）

> 执行 worker 夜间全自动授权在案。正本输入 = PLAN（含 checker 回注 M4/M9/M11）
> + M2-10-01..06 六波 SUMMARY/ACCEPTANCE/DECISIONS + M2-10-CONTEXT（OQ-8/9/12
> 用户裁决 2026-10-02）。本文件记录执行期裁决与申报；晨审可逐条推翻。

## D1 页面落位照 KD 兑现，零重开

LCR/ACA 两页 = KD-1/KD-2 字面：五档位清单（状态六态直映 / 许可 / digest 体积 /
内置-下载徽标 / **待发布禁点** = digestUnpublished 无下载按钮，M2-10-01
fail-closed 的 UI 面）+ 下载/移除/换激活（确认对话框 → `registry.recomputeAll`
入队，进度走 BackgroundTask 栏，页内只显「重算中」）+ 兼容性记录重置（确认 →
`CompatRecord.resetAll()`）+ 就绪探针（bundled 资产在场 + 真 worker ping 一次）
+ 两页数据政策脚注（LCR = 本地不上云；ACA = 远程发送披露，OQ-8-A 字面）。
ACA 页 = 连接表单 + key SecureField→Keychain + 「未配置」横幅 + 严格度/语言 +
不再询问开关 + 连接测试（行内呈现）。`SettingsPage` 枚举 / IA 顺序零 diff
（AC#4，机检在案）。

## D2 落位定案 = `App/Sources/Lightamer/AI/`（checker M11 照办）

`LibraryConnectionStore` 落 AI/ 目录（02 已建，语义即 AI 连接面）；keychain
account 参数化（默认 = `AICredentialStore.ratingProviderAccount` 唯一生产拼写，
测试注入 UUID 账号——测试永不触碰真实 key 槽，AICredentialStoreTests 纪律）。

## D3 申报增量（front-matter 漏列 = 起草缺口；授权原文 + additive）

| 文件 | 触碰 | 授权/理由 |
|---|---|---|
| `UI/SettingsView.swift` | 两 case 换真页 + `@Environment(libraryProjects)` + SettingsDeepLink onAppear | case→视图 switch **就在此文件**（M2-3 T5 迁移后的事实布局——front-matter 写的 SettingsPages.swift 是页体，枚举 switch 在 SettingsView）；additive；03/04 WorkspaceHostView 同族先例 |
| `UI/LightamerApp.swift` | `CommandMenu("Image")` 两命令 + Settings scene 注入 libraryProjects | SwiftUI **菜单栏命令只能声明在 Scene 的 commands 块**——EditorWorkspaceShellView 无法承载；OQ-8-A「编辑器 Image 菜单」字面的唯一实现点 |
| `UI/Shell/WorkspaceModel.swift` | `AIEnhanceRequest` 请求面（kind + imageIDs + pending/consume） | 菜单命令 → 宿主的桥 = 既有 `isSearchDialogPresented` 单一呈现者模式（P1 预埋先例）；3 个成员 |
| `UI/Shell/WorkspaceHostView.swift` | AIEntryPointCoordinator + 两个 sheet 宿主 + 网格/Inspector 接线 | 生产缝装配点（06 交接「接线即换生产闭包」）；03 波 +65 行 / 04 波 +6 行同文件先例 |
| `Tests/LightamerTests/AIProviderClientTests.swift` | 429 测试尾 +1 断言（`recorded.count == 1`） | **04 波验收 O-2 随批消费**（任务书明示「可随批补」）——no-retry 自动机显式钉 |

**`EditorWorkspaceShellView.swift` 零 diff**：front-matter 列名（「Image 菜单增
两命令」）但菜单栏命令的 SwiftUI 落点在 LightamerApp（上表）；本波对该文件
零触碰（收口批最小 diff 惯例），漏列方向与上表相反——同为起草缺口，登记即闭。

## D4 Image 菜单形态

`CommandMenu("Image")` + 两命令（AI 超分辨率… / AI 去杂色…），act on 编辑器
当前图，经 `focusedWorkspace`（FocusedValue 桥，menu_library_search 同款）→
`WorkspaceModel.requestAIEnhance` → 宿主 onChange 消费 → 增强队列。disabled
面 = 非编辑器相位或无当前图。marker `menu.image.aiUpscale/aiDenoise` 入冻结集。

## D5 批量 = 顺序单张循环（v1，KD-3 明文）

一图一对话框：`.done` 且非末张 → 自动推进下一张（`advanceIfMore`）；末张保持
done 面等用户关闭；**用户关闭 = 放弃余量**（`closeEnhance` 停 worker client +
清队列）；空集不入队；重入替换（旧 client stop）。真批量队列（并发/断点）=
plan 挂账观察项。`AIEnhanceBatchSheet` 以 `.id(index)` 重建对话框身份，
`.task(id:)` 重建模型——06 对话框文件零 diff。

## D6 增强副本 albumID = nil（v1）

D-3「落当前相册（可选）」的可选半边：副本入项目网格、不入相册（相册选择态
未进入 coordinator 面）；走查观察项随 VALIDATION-INPUT。

## D7 provenance `source_image_id` = 库行 id 的十进制 String

生产装配取 `String(row.id)`（库内稳定身份；06 测试用 UUID 系合成值——测试缝
形态，不约束生产拼写）。「衍生自」徽标 join 键（06 交接④）以此为准。

## D8 描述无确认门 + rendition_kind 分叉

KD-3 明文（写 ai_understanding 非用户手评语义）：描述扫描直写零确认；评分走
AIRatingController 确认门（OQ-11-A）。rendition_kind 按 `row.hasEdits == 1`
分叉 "edited"/"original"（04 默认 "edited" 是编辑器语境；图库语境按行状态）。

## D9 描述/评片任务面 = BackgroundTaskRegistry 聚合 handle，不扩 AIAnalysisTaskKind

「描述直接入队（registry 任务）」落为 `AIProgressHandle`（ImportTaskAdapter
同款 conformer）注册进宿主既有聚合注册表（M2AI-07 的"任务注册表"正本）——
**不加第四个 `AIAnalysisTaskKind`**（Core AnalysisTaskTypes + AIAnalysisRegistry
零 diff；front-matter 申报集不含两者）。进度可取消（SendableCancelFlag 每张
checkpoint）。

## D10 打开档位盒（modelFacts → tileExecutor 交接）

`CurrentProfileBox`（NSLock Sendable 对）：modelFacts 是唯一写者（open 前写入
当前 choice 的 profileID），tileExecutor 读之路由 `enhanceTile`。运行中切换
对话框 Picker 不改变盒值（tiles 保持已打开会话；worker 侧 feed 验证 typed
拒绝兜底）——06 模型文件零 diff 的约束下最窄正确面。

## D11 SettingsDeepLink + 已开窗口限制

引导「点 = 打开 ACA 页」：Inspector 行内 `SettingsLink` + `simultaneousGesture`
预置 `SettingsDeepLink.pendingPage`，SettingsView onAppear 消费选中页。限制：
Settings 窗口**已开**时不触发 onAppear → pendingPage 滞留至下次开启才消费
（v1 已知限制，走查观察项）。

## D12 提交结构 = 计划四提交 + 共享文件中间态

SettingsPages.swift / SettingsView.swift / LightamerApp.swift / Project.swift /
BUNDLE-MAP 为 T1/T2/T3 共享触碰——每提交为**可构建前缀**（T1 = ACA 面 + LCR 仍
占位；T2 = 两页真 + 无 Image 菜单；T3 = 全量终态），中间态经 tuist generate +
build-for-testing 逐态验证（0 error）。计划「每任务独立提交」语义保全；申报
于 SUMMARY 提交账。

## D13 zh 批 = 审计全集 24 键 + 本波新键 102 键 + 孤元 6 键移除

挂账「20 键」为 03/04 两波口径；`zh-audit --check` 实测缺 23 键 + `search_
fulltext_placeholder`（提取器形状外）= 24（含 **02 波 CLIP tab 4 键**遗留——
02/03/04 三波 O-1 同族全集），一并清账 + 本波两页/入口/对话框/任务新键 102
+ 移除孤儿 6（`settings_placeholder_*` ×2、`settings_lcr_feature`、
`settings_aca_feature`、`search_tab_*_placeholder` ×2——占位退休后的死键）。
最终 `zh-audit --check` **PASS**（1505 源键 / 1753 目录键 / zh 完整 / locale
⊆ {en, zh}）。插值键注意：`String(localized: "K \(x)", defaultValue:)` 的
defaultValue 形态编译不过（key 变 StaticString）——插值键一律 catalog-only
形态（键族提取照常覆盖）。

## D14 OQ-12-A defer 签认（M2AI-08 核验）

- 机检：`git diff --name-only App/Sources/Lightamer/MCP/ LightamerCore/Sources/MCP/`
  over `c573087..9586c1b`（本 plan 全批）= **零命中**；Export/Version 红线域
  同检零命中。
- MCP 既有测试全绿（AIProviderClientTests 同轮 Library 22/0/0；MCP 族测试在
  App bundle `--all` 轮亲点）。
- **`semantic_search` 工具 defer 记录**：OQ-12-A 用户裁决（2026-10-02）采纳
  推荐 A——M2AI-08 按字面零新增，语义工具等外部需求出现再立项（工具 schema/
  文档/安全走查都是新增验收面）；本文件即签认记录。

## D15 悬决销账回执（各 plan 挂账 → 本波）

| 挂账 | 出处 | 回执 |
|---|---|---|
| zh-audit 20 键（O-1 两连挂账） | 03/04 验收 | **清账**：24 键全入目录 + PASS（D13） |
| 04 波 O-2 no-retry 显式断言 | 04 验收 | **随批补**：`recorded.count == 1` 钉死（AIProviderClientTests，22/0/0） |
| 「重置 AI 兼容性记录」按钮 | 05 交接 | LCR 页诊断节兑现（重置→文件删除终态测试钉） |
| 下载行四态接线 | 06 交接③ | LCR 页 + 对话框共走 ModelAssetStore（release 上架后零 UI 改动维持） |
| 双入口接线 | 06 交接①/M2AI-09 注记 | 本波兑现（D4/D5） |
| 命中质量走查（threshold 0.05） | 03 验收/交接 | 挂 M2-10-VALIDATION-INPUT 观察清单（headless 盲区） |
| 「衍生自」徽标 | 06 交接④/OQ-4-C | join 键定案 `source_image_id` = 行 id 十进制（D7）；徽标 UI = 后手，挂 VALIDATION-INPUT |
| 内存口径 + 流水线化（M-1） | 06 验收 | **已于 `c573087` 前置闭环**（两阶段 engine + typed 门 + 文案；基线 2929/16/0 含 +3 回归） |

## D16 续班收尾（2026-10-07，前任死亡 → 续班 worker 补全）

- **事实链**：执行 worker 于 2026-10-04 03:41 后完成 T1/T2/T3 三提交
  （`9daf709`/`47e46c4`/`9586c1b`）+ 收口三稿落盘（本文件 03:47 /
  SUMMARY+VALIDATION-INPUT 04:08）后死亡——T4 提交未落库、`--all` 补跑
  第三跑（SidecarV5 ANE flake 两连红后的隔离复跑）结果未及记录。
- **在制品甄别处置**（逐 diff 读毕）：①`Tests/…/AIProviderClientTests.swift`
  +4 行 = 04 波 O-2 `recorded.count == 1` 显式断言（D3 表末行申报面）——
  **收留，随 T4 批提交**；②`REQUIREMENTS.md` M2AI 族翻账 7 行 = T4 action 2
  产出（diff 边界仅 M2AI 族行，纪律 5 亲验）——**收留**；③`LESSONS.md`
  L066/L067 = 本波执行期踩坑（插值键 StaticString / URLProtocol 嵌套隔离）
  ——**收留**；④两张 `09-3-tiers-*.jpg`（M）= 多波走查证据字节漂移，与本
  plan 无关——**勿动不提交**（遗留事实登记本节）。
- **续班机检复核**：MCP/Export/Version 红线域零 diff 亲跑复现（D14 机检
  复现成立）；`zh-audit --check` PASS 复现（D13 终值成立）；BUNDLE-MAP
  三行 × `grep -c` 逐位；`SettingsPage` 枚举本体零 diff（AC#4 复现）；
  marker 七枚读码在位（D4/D11 面）。
- **终轮定案**：2026-10-07 全套 `--all` 续班重跑 = **`2955/16/0|1019s`
  单轮干净绿**（SidecarV5 复绿 13.338s，ANE flake 第五波收口两红三绿，
  环境型归因维持）；AC#8 终态 = 0 fail。提交结构 = O-2 断言独立
  `test(ai)` 提交 + T4 `docs(m2-10)` 收口批（§2.1 多主题拆分；D12 四提交
  计划的 T4 以此两件构成）。
- **并行会话归属滑差（续班对账登记）**：续班工作期间，并行 orchestrator
  线落 `5ef87a1`（Alcedo 上游 delta 调研，非本 plan 域）+ `de68703`
  （用户 V2 裁决四差异，**将工作树中前任 M2AI 翻账 7 行一并扫入**——
  hunk 与本 plan 申报内容逐行一致零篡改，body 自注 provenance 并点名
  续班 agent 最终对账）。最终归属：REQUIREMENTS 翻账 = `de68703`；
  LESSONS/GOAL-STATE/三收口件 = 本收口批（`docs(m2-10)` closeout）；O-2 断言 = `70d782a`。
  T4 的 plan 申报 subject（`docs(m2-10): close out phase ui requirements
  ledger`）由 本收口批（`docs(m2-10)` closeout） 承载。
