# Plan 14-4 launcher + 收口签核（W3）执行 SUMMARY

**Executor:** ZCode executor subagent worker · **Date:** 2026-09-28
**Plan:** `.work/gsd/phases/14-mcp-server/14-4-PLAN.md`（W3：launcher + 日志面板 + 探针退役 + 终快照冻结 + SC#7 全链 + 安全走查 + PROJECT.md 漂移修正 + VALIDATION 签核）
**Status:** 完成（4 tasks / 4 commits + 1 收尾提交，未 push）

## 任务表与提交

| Task | 内容 | Commit | 证据 |
|---|---|---|---|
| T1 | 偏好 UI（server 开关/模板/提示词/LAN toggle）+ `McpLauncher`（占位符/串行门/终止只及自家）+ 探针退役 + **culling union 宿主装配** + EXP-08 双向纪律留痕 | `e4f80f7` | `McpLauncherTests` 10/0（占位符逐字 + zsh 元字符往返 + env 注入 + 串行拒绝 + launch-failed 槽位释放 + 退出码 + 退役断言）；Snapshot 7/0（probe 域退役断言）；Host 18/0（hello canonical 换 list_iops）|
| T2 | `McpLauncherPanelView`（环形缓冲 2000/跟随滚动/复制/停止/写回计数诚实面）+ registry `writeCallCount` 缝 + 窗口/菜单挂点 | `4f5d547` | `McpLauncherSentinelTests` 9/0（注入逐字端到端 + 共享核串行哨兵 + 终止只及自家〔外来 pid `.notOurs` 且 `kill -0` 存活〕+ TERM 顽抗 SIGKILL 兜底 + 2000 行裁头 + 复制/跟随语义）；计数缝 `testWriteCallCounterCountsOnlyTheWriteFace` |
| T3 | 终快照 19 封闭集冻结 + SC#7 端到端全链 + 白名单负例 + zh 描述键 + burst 2.0s 补钉 + face-regions 超时档 + PROJECT.md/README 文档收口 | `23928ec` | `McpFinalSnapshotTests` 6/0（union 逐字 + 分域组合 + 第 20 工具负例 + zh 键覆盖 + **SC#7 全链双入口** + burst 边界）|
| T4 | 全套终轮 + 14-VALIDATION + 翻账（REQUIREMENTS/GOAL-STATE/TODO）+ 本文档 + DECISIONS | 本提交 | 终轮 **1881/11skip/0fail**（780.3s，`/tmp/la-144-final.log`）|

## 提交链（未 push）

```
e4f80f7 feat(14-4): launcher core + Settings MCP section + probe retirement + union assembly
4f5d547 feat(14-4): launcher log panel + sentinel trio + write-call counter
23928ec feat(14-4): final 19-tool snapshot freeze + SC#7 launcher chain + doc closure
(T4)    docs(14-4): close out plan 14-4 - VALIDATION + SUMMARY + DECISIONS + ledgers
```

## 收尾轮计数（基线 1857 → 1881）

- 基线：**1857/11skip/0fail**（14-2 验收修复后终值）
- 本 plan 新增：Launcher 10 + Sentinel 9 + 写回计数 1 + FinalSnapshot 6 = **+26**；probe 域净退役 **−2**（Snapshot 域 probe 快照/键形两测试删除，退役断言顶替）→ 理论 **1881**
- 终轮实测：**Executed 1881 tests, with 11 tests skipped and 0 failures（780.3s）**——与理论账严格吻合
- 在案 flake（LayerE2E / ToneEqual / QuickLook 计时类）未现身，零归因单列

## 安全走查输出（§RQ-14-13 口径四条 + 公开仓专项，逐条）

1. **绑定常量走查 ✅**——`McpHTTPHost.loopbackHost = "127.0.0.1"`（McpHTTPTransport.swift:65）为硬编码常量，Settings 无任何可改绑定地址的键；运行时实证 = `testHTTPEndToEndSDKClientRoundTrip`。非回环 = 显式 toggle（`mcp_lan_exposure_enabled`）→ `.lan` 分支绑 `0.0.0.0` **并强制 Bearer**（load 或 SecRandom 生成 + keychain store），toggle 切换即重启宿主使绑定真实生效；风险明示文案 = `settings_mcp_lan_risk`（「监听接口将暴露至局域网，鉴权 token 将强制启用」）。
2. **token 比较常量时间 ✅**——`McpBearerValidator.constantTimeCompare`（手写异或累积比较）+ 真值表测试 `testBearerTokenGenerateAndConstantTimeCompare`（含长度不等/翻转/前后缀负例）。
3. **Origin pipeline 未被禁用 ✅**——`validationPipelineWithBearer` = SDK 默认五 valve 原序 + Bearer **追加在尾**（永不能抢先传输级校验）；实测 `testOriginAndHostValidationPipeline`：evil Origin 403 / 无端口 localhost Origin 403（D6：`*` 要求端口存在）/ Host mismatch 421 / 无 Origin（agent CLI 形态）放行。
4. **工具白名单负例 ✅**——`testTwentiethToolIsWhitelistNegative`：`match_color`（研究项 C 具名零占用）/`delete_file`/`run_shell` → typed `[internalError] unknownTool`；tools/list 恒 19；终快照 19 封闭集逐字冻结（新增/删减工具必须显式改快照）。
5. **公开仓专项 ✅**——①token 不落日志：MCP 面源码 grep（token × logger/log/print）**零命中**；②端点文件无 token 真身：schema v1 九键冻结测试（`testEndpointFileSchemaV1Keys`），auth 字段只放 `"none"`/`"bearer"` 标记（McpEndpointFile.swift:61-63），token 真身只在 keychain（0600 fallback `~/.lightamer/mcp-token`，权限测试在案）；③keychain/0600 拼写无敏感串硬编：MCP 面 40+ 字符常量串 grep（schema 外）**零命中**；④gitleaks 面自查同批（13-4 审计闸纪律沿用）。

## SC#7 全链证据指针

- 自动化锚：`McpFinalSnapshotTests.testSC7LauncherChainEndToEndWithDualEntry`——真子进程 agent（`/bin/zsh -c` + curl，真实 Streamable HTTP + JSON-RPC 形态）：从发现文件取 port → initialize（`mcp-session-id` 配对）→ list_photos → get_thumbnails（stale:true，真 tier-B 缓存图）→ set_rating → `AGENT-DONE`；sidecar 真身 rating=4 + lindex 行 rating=4 + 直连 SDK client（先在 session）经 rating=4 filter 观察到该写 = **双入口并存**。
- 日志面板捕获：launcher 日志环含 `agent: discovered/listed` + `AGENT-DONE`；停止面：会话结束 `.notRunning`（按钮禁用态语义）。
- 「本次会话无写回」：`writeCallCount` delta（requiresWriter 完成调用计数；gated-out 不计）→ 面板 done(writes:) 诚实面。

## 交付物清单（files_modified 对照）

- `App/Sources/Lightamer/MCP/McpLauncher.swift` ✓ 新建（模板渲染 + launcher 核 + 日志环 + shared 单例 + 发现态查询）
- `App/Sources/Lightamer/MCP/McpServerController.swift` ✓（探针退役 + union 装配 + LAN 分支 + EmbeddedState + handle.registry + embeddedWriteCallCount）
- `App/Sources/Lightamer/MCP/McpToolRegistry.swift` ✓（writeCallCount 计数缝）
- `App/Sources/Lightamer/MCP/Tools/EditingToolset.swift` / `CullingToolset.swift` ✓（描述键 15 枚 defaultValue 包裹 + face-regions 超时档）
- `App/Sources/Lightamer/UI/SettingsView.swift` ✓（MCP 节：开关/LAN/模板/提示词）
- `App/Sources/Lightamer/UI/McpLauncherPanelView.swift` ✓ 新建（面板 + model）
- `App/Sources/Lightamer/UI/LightamerApp.swift` ✓（McpWriteFaceBox + 生产 culling context 装配 + mcp-launcher 窗口 + 菜单 + 写面孔发布/清理）
- `App/Sources/Lightamer/Export/PostExportActions.swift` ✓（EXP-08 侧纪律对照注释）
- `Resources/Localizable.xcstrings` ✓（+45 键：Settings 12 + 面板 18 + 工具描述 zh 15）
- `Tests/LightamerTests/McpLauncherTests.swift` / `McpLauncherSentinelTests.swift` / `McpFinalSnapshotTests.swift` ✓ 新建
- `Tests/LightamerTests/McpRegistrySnapshotTests.swift` / `McpHostTests.swift` / `McpRenderParityTests.swift` ✓（探针退役适配 + 计数测试）
- `README.md` ✓（依赖枚举修正 + MCP server 节）+ `.work/gsd/PROJECT.md` ✓（依赖漂移修正）
- `14-VALIDATION.md` ✓ 新建 / 本文档 / `14-4-DECISIONS.md` / REQUIREMENTS / GOAL-STATE / TODO / PROGRESS ✓
