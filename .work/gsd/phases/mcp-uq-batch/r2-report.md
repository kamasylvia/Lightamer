PASS / 0 error + 4 minor（相对 R1 修复后状态；R1 的 2 error + 12 minor 逐项 FIXED 确认，M-4 接受成立，M-8/M-13 挂账合理）

## R1 修复确认

- **E-1 FIXED**：`git diff HEAD -- Project.swift` 纯插入两行（971-972 两新登记）；970 `McpControlToolsetTests` 与 973 `AgentControlCoordinatorTests` 均在位；BUNDLE-MAP 纯插入 `APP 7 McpGetSchemaTests` + `APP 11 McpOnboardingTests`；D-UQ-0 已勘误为双吞行事故（1075=1073+17−15 自洽）。
- **E-2 FIXED**：15 `settings_mcp_onboarding_*` 键 en+zh 双语在位（总值 2116=2100+16，新增恰 16、删除 0、旧值 0 变、旧序保持、新键成尾块）；`mcp_tool_desc_get_schema` 保持 zh-only + 代码 en defaultValue（28/29 同族先例，正确）。
- **M-1 FIXED**：SUMMARY 改「7 快照/count 测试」与实际 7 文件吻合；D-UQ-6 改「count 钉 11 处」，逐项点名 3+1+1+1+1+2+1+1=11，与 grep 11 断言位逐一对应。
- **M-2 FIXED**：悬空指针已删，改为内联证据（`Registry` 命中系测试文件 + R1 §7 同证）。
- **M-3 FIXED**：SKILL `editing (11)` 枚举含 refine_masks + get_schema（11 名与 RefineMasks 测试枚举一致）；§6 得 get_schema nod，主谓一致。
- **M-5 FIXED**：`McpGetSchemaTests.swift:74 testEveryCatalogedOpResolvesEncodedDefaults` 在位，注释声称不再悬空；ΔN 17→18，4461=4443+18 自洽。
- **M-6 FIXED**：默认值法加独立解码比对（:102-112，不走 `encodedDefaults`）+ 非 null 断言；脚本法加 `contains(executablePath)`（:48）。
- **M-7 FIXED**：R1 点名码全入 refused 集（14 token），测试镜像逐一对应；exit-1 四码（render/export/model/internal）语义对。残余见 R2-M2。
- **M-9 FIXED**：`installMarker` 全串单源（:84），install/uninstall 双守卫 + script 嵌入三处同源；与上游 `85c9c16` 全串 `contains` 形态一致。
- **M-10 FIXED**：`parse` :93-94 conscious-choice 注记在位（bare/help exit 2 + usage 走 stderr）。
- **M-11 FIXED**：e2e 60s 有界等 + 超时 terminate/XCTFail（:186-196）；`defer stop` 火忘属 teardown 清理，良性。
- **M-12 FIXED**：NOTICE §V（上游/提交/日期/许可/覆盖三文件/版权保留）+ 三新文件头归属行；`85c9c16` 日期 2026-09-26 已对上游提交对象核实。
- **M-14 FIXED**：转义合一为 `shellQuoted`（:133-135），两调用点（:52/:91）同源。
- **M-4 接受成立**：2100 旧键 JSON 解析级零差异（`":{"` 仅键值间空白风格），语义纯度实证强于 R1 结论；归一化成本论成立。
- **M-8/M-13 挂账合理**：均有明确消解路径（二级 CLI 立项：dup2 兜底 / `--out` 文件臂），pipe-safe 现状无功能阻塞。

## 新 finding

**R2-M1（minor）`McpOneShot.swift:13` 头注引用不存在的 `mcpOneShotIfRequested()`。** 根因：执行期 API 改名残留。证据：全仓 grep 该标识仅此一处（注释）；真实探针为 `tailIfRequested`（定义 :57、调用 `LightamerApp.swift:149`、测试 3 用）。修复：头注改 `tailIfRequested`。

**R2-M2（minor）`imageLiveInEditor`/`renderTimeout` 落 exit 1，与「caller-fault 码全扩」声称及 sibling 处置不一致。** 根因：M-7 扩 token 时未处置此二码。证据：`McpToolRegistry.swift` 19 case 中仅此二码既不在 refused 集（:267-280）也不在 exit-1 测试钉（:106-107）内；同为环境态冲突的 `serverReadOnly`/`projectReadOnly` 判 exit 2（caller 可关图/重试消解，同理适用于 EBUSY 性质的 imageLiveInEditor）。修复：`[imageLiveInEditor]` 入 refused 集 + 测试行，或书面注记 exit-1 理由。

**R2-M3（minor）账本无 R1-fix 后执行记录，收口必须跑 `--all`。** 根因：D-UQ-0 仅记 broken 态 App 1075；SUMMARY 全套仅「预期 4461/34/0（终值见收口）」。证据：账本内无 post-fix App 1091（=1073+18）或全套终值。修复：收口 gate 跑 `--all` 验证 4461/34/0 后再合（SUMMARY 已诚实标为预期，非虚构，故 minor）。

**R2-M4（minor）`parse` 接受 `--list` 但 usage 不载。** 根因：别名顺手加、帮助文本未同步。证据：`McpOneShot.swift:99` 有 `--list` 臂，`:43-51` usage 仅列 `list`。修复：usage 加 `--list` 别名注记一行。

## 残留/封存复核

- `all33`/`Union32`/32-face/`editing (9|10)`/`count, 33|24`/33-face/24-face 全零命中；`no 35th` 为 34-union 下正确 whitelist 负测。
- 封存面：diff 文件清单 17 件零命中，唯一 `Registry` 命中系 `McpRegistrySnapshotTests.swift` 测试文件；`get_schema` descriptor/schema 三处（EditingToolset/Registry 快照/Final 快照/tools.md）verbatim 一致，byte-gate 自洽。

纪律：只读审查（git diff/grep/JSON 校验），零构建、零测试执行、零进程处置、零文件写入；lane prompt/monitor/omp-evidence 未读。
