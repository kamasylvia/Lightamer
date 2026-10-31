FAIL / 2 error + 14 minor（MCP-UQ 批域内自审，基线 `1b241de9`，静态只读：代码 + git diff + 账本 + 上游 `85c9c16` 提交对象；lane 中间态未读）

## 先说干净的面（机检实证）

- 合成缝真单源：多行感知脚本交叉核对 `IopCatalog` 19 op / 223 param == `annotations` 19 op / 223 row，CLEAN，零漂移；key/type/version/iopOrder/domain 全消费 `IopCatalog.Op`（`McpSchemaCatalog.swift:360-377`），默认值走 seed paramsData ∥ `GradeCatalog.identityJSON`，与 T3 guard（`McpEditingToolsetTests.swift:453-495`）同源；默认面经 `defaultFaceOps()`，与 `list_iops` 同缝。
- 快照纪律机器面全 conscious：union 33→34（`all33→all34` 改名 + 4 处 count 钉 + SC7 direct-entry 34 + descriptionKeys 1 键）、editing 10→11、editing+culling 24→25（Registry/Host×2/Launcher/SearchState）、destructive 恒 10、`tools.md` get_schema 插位与 registry name-sorted 渲染一致（byte-gate 形态对）、`grep 33/24/all33/Union32` 零残留（仅 Mertens/Pano/Spectral 无关数字）。
- 封存面 17 件零 diff：diff 文件清单无一命中（`Registry` 命中系 `McpRegistrySnapshotTests.swift` 测试文件，非封存件）。
- D-UQ-4 诚实：S3 纯 HTTP（`HTTPClientTransport` 两处，无 stdio 派生），writer-lock 理由成立；D-UQ-7 诚实：`resolveEndpoint` 默认 `headlessEndpointPaths`，DEBUG env 门与 headless 臂同源；entry fork 在 `--mcp-*` 后、AI-worker 前，`Task+dispatchMain+exit` 永不构造 GUI（`LightamerApp.swift:149-155`）；`tailIfRequested` 不扰正常启动/`--mcp-stdio`。
- 上游引用属实：`AgentTools.get_schema` 摘要句、AgentSchema "ranges are the interface's, not the wire's"（`85c9c16:AgentSchema.swift:11-13`）、0/1/2 exit 形、两行脚本形、`claudeCodeCommand/desktopConfig/install/uninstall` 结构均对得上。
- xcstrings 语义纯：2100→2116 键，新增恰 16 键、删除 0、既有值变更 0、旧序保持、新键成尾块。

## error（必须修，阻塞合并）

**E-1 `Project.swift:969-971` 静默摘除 `McpControlToolsetTests`（15 法），D-UQ-0 注记虚假。** 根因：diff 把 HEAD `Project.swift:970` 的 `McpControlToolsetTests.swift` 行**替换**成两新文件行，而非插入；工作树全文件 `grep McpControlToolsetTests Project.swift` 零命中 = 不编译进任何 bundle。证据：`git show HEAD:Project.swift` 第 970 行即该登记；文件本体仍在且被改了 union 断言（死改）；BUNDLE-MAP:775 仍记 `APP 15 McpControlToolsetTests.swift`，与 Project.swift 矛盾。后果：D-UQ-0「M7-5 欠账/零登记/基线 4443 不含」三句全错——基线含这 15 法；本批实际执行增量是 +17−15=+2，「预期 4460/34/0」落空（应为 4445，且 control 域 union 钉从此不执行）。修复：把该行加回（HEAD 原位，Registry 行之后），D-UQ-0 整节勘误，套件基线预期恢复 4460。

**E-2 15 个 `settings_mcp_onboarding_*` 键 zh-only、无 en、无 call-site defaultValue → en locale 设置页显示裸键。** 根因：新键 catalog 仅 `zh` localization（已 dump 全键确认），而 `SettingsPages.swift:1459-1558` 全用无 defaultValue 形（`String(localized:)` / 裸 `Text("key")` / `titleKey:`），en 下回退显示 key 本体。证据：`settings_mcp_*` 既有 12/12 双语（en+zh），新键破家族惯例（`mcp_tool_desc_get_schema` 的 zh-only + 代码 en defaultValue 反而是对的，28/29 同族先例）。修复：给 15 键补 en 值（或 call-site 加 defaultValue；按家族惯例选前者）。注：zh-audit 只查 zh 可见键，故「双 PASS」与本缺陷并存不矛盾。

## minor（可顺手）

**M-1 账本漏报改动文件数。** SUMMARY:44-47 称「5 快照/count 测试」，实际 7：`McpRefineMasksToolTests.swift`（editing 10→11 + get_schema 名录，conscious 但未申报）+ Control（E-1 死改）；D-UQ-6「count 钉 6 处……8 断言」与实际 11 处 count 断言对不上。修账本数字。

**M-2 「亲证见 DECISIONS」悬空。** SUMMARY:48 指封存面亲证在 DECISIONS，但 DECISIONS 无封存节。结论本身已由本审验证为真，补清单或删指针。

**M-3 `SKILL.md:88-93` §3 `editing (9)` 枚举 stale。** HEAD 起已 stale（缺 refine_masks，9 vs 10），本批顺手改了同文件三处 count 却未修枚举（现 9 vs 11，缺 refine_masks + get_schema）；§6 `SKILL.md:136-144` 称 list_iops 为 "the agent-facing schema channel"，应 nod 一下 get_schema。SKILL 散文非机检门（门只盖 tools.md/errors.md），故 minor。

**M-4 xcstrings 5368 行 diff 系空白重序列化。** 语义零触（M2-7「尾块纯插入」语义成立），但字节级违反「历史键字节零触碰」（`": {` → `":{` 全文件）。接受或归一化，二选一注记。

**M-5 空默认臂注记悬空。** `McpSchemaCatalog.swift:333-337` 称「coverage test pins that this never happens for cataloged ops」，但无任何测试断言 `encodedDefaults` 对 19 op 非 nil（S1-2 只钉注记闭合；colormatch 的 GradeCatalog fallback 今天成立但无人钉）。补一法或 soften 注释。

**M-6 两测试名 overclaim。** `McpGetSchemaTests.swift:71-91` 名为 `…EqualTheEncodedDefaults`，实只断言 range 串 + 一个 null，无任何非空 defaultValue 断言、未与独立解码的 seed 比对；`McpOnboardingTests.swift:44-50` 名为 `…ExecutesTheLiveExecutable`，实未断言 script 含 `executablePath`。各加一行断言或改名。

**M-7 `clientError` 漏 `unknownOp` 族。** `McpOneShot.swift:259-273` 8 token 与 wire 形（`McpAdapters.swift:40-44` 的 `[code]` 包裹 + registry `unknownTool:` 明文）一致，但 `unknownOp/unknownPreset/invalidFilter/roiOutOfBounds/keywordContainsSeparator/exportPresetNotApplicable` 等调用方过错码落 exit 1（"ours"）。header 枚举（unknown tool/bad JSON/control）倒是自洽，故 minor： consciousness 扩 token 或维持。

**M-8 stdout discipline 缺 fd 级兜底。** sinks 分流正确（成功 stdout 仅结果、诊断全 stderr、usage 走 stderr），但无上游 `AgentOutput.takeStdout()`（dup2 兜底 stray print）。SDK/框架锥无 observed 噪音，静态无法证伪；`| jq` 管道场景的硬化缺口。

**M-9 安装守卫 marker 收窄。** `McpOnboarding.swift:103,119` 用 `"Installed by Settings"` 前缀，而 script 注释写全串 `Installed by Settings ▸ MCP ▸ 接入向导`；上游用全串比对。安装路径与 SpektraLab 不同名（`lightamer` vs `spektralab`），现实碰撞概率 ~0，收紧为全串即可（低成本 defense-in-depth）。

**M-10 `mcp help`/裸 `mcp` exit 2。** `McpOneShot.swift:89-92,117-118` 经 refused 臂，exit 2 非惯例 0；usage 在 stderr 是对的（保 stdout 纯）。conscious 选择，注记即可。

**M-11 e2e 无超时。** `McpOnboardingTests.swift:174` `waitUntilExit()` 无界（先例 `spawnHolder` 用 deadline-bounded 握手）；`:159` `defer { Task { stop } }` fire-and-forget。挂起则测试挂，加读者侧超时或注记。

**M-12 NOTICE 未同步 RFC-026 派生。** 新三件 + Settings 节在结构/文案/exit 形上多处派生自 `85c9c16`（`install/uninstall`/视图体近 verbatim 结构），in-file 仅「借鉴」一提，无版权行、无 NOTICE 条目。GPL-3.0↔GPL-3.0 同许可使用合法，按本仓纪律补 NOTICE 条 + header 归属行。

**M-13 `mcp call render_preview` stdout MB 级。** `resultJSON`（`McpOneShot.swift:232-252`）把 base64 全内联进 pretty JSON（默认 `[current,root,text]` 双图）；pipe-safe 但笨重，上游走 `--preview` 文件臂。文档注记或立项 `--out`，本批不改。

**M-14 script 转义与 `shellQuoted` 双实现。** `McpOnboarding.swift:86` 内联复写了 `:128-130` 的同款转义，顺手合一。

## 结论

S1 合成缝、S3 协议臂、快照 serial right、封存面、D-UQ-4/D-UQ-7 均实；但 **E-1（15 法静默出套 + 账本反向虚构欠账）与 E-2（en 面裸键）阻塞合并**，先修后终审。
