# MCP-UQ 增量批 zcode 独立 review（MCP-UQ-REVIEW）

> 审批人：zcode 独立眼（omp 执行 + zcode 审核新阵容的审核腿）。
> 对象：`a98318cc`（UQ-S1 get_schema）/ `f9ceb510`（UQ-S2 onboarding）/
> `310a499a`（UQ-S3 CLI 门）/ `7ad4a9c2`（closeout）。基线 `1b241de9`。
> 正本：本目录 `MCP-UQ-SUMMARY.md` + `MCP-UQ-DECISIONS.md`（D-UQ-0..7）。
> 日期：2026-10-31。纪律：只读审查 + 定向复跑（App / IOPParity）+ zh-audit。

## 结论：PASS（1 error 独立发现，修复轮回注；不阻塞批结构判定）

批交付结构成立：三件齐、Project.swift 吞行事故已修复亲证、union 快照
additive 合规、安全面净、AgentAccess off-by-default 未被绕过。但独立
复核在 omp 两层自审（R1 FAIL/2+14 → R2 PASS/0+4）之外发现 **1 个 error
级缺陷**（E-3，get_schema 默认值 Bool 桥接污染），需修复轮回注后重跑
App bundle 方可视为终态。

## 逐件判定

### UQ-S1 get_schema（`a98318cc`）— 判定：结构 PASS + 1 error（E-3）

- **合成缝三源亲证**：`McpSchemaCatalog.swift` 消费 `IopCatalog.ops`
  （名录+type 串）× seed 编码默认（`encodedDefaults`：seed record
  paramsData / `GradeCatalog.identityJSON`，guard 同源）× 手写
  annotations 表（仅 range+meaning 两列新数据）。IopCatalog 零复列
  （D-UQ-1 成立）。
- **覆盖面声明 vs 实际**：annotations 223 字段行 = 19 op 的
  IopCatalog params 键全集（`testEveryCatalogKeyHasAnAnnotationRow`
  钉死 silent fallback 死路）；default-face 16（`defaultFaceOps()` =
  19 − 3 disable 集，测试钉 count 16 + filmicrgb/sigmoid/agx 缺席）。
- **抽 3 op 深核**：temperature（type `range:[0,8]` ↔ annotations
  `[0,8]` ✓；preset enum 串逐字 ✓）/ exposure（`range:[-18,18] (EV)`
  ↔ `[-18,18] EV` ✓）/ colormatch（`enum:gaussianOT=0,reinhard=1` ↔
  annotations 同串 ✓；`[0,1]` ✓）。三处全对上。
- **descriptor/快照/tools.md 三处 verbatim 一致**（EditingToolset
  descriptor ↔ FinalSnapshot ↔ RegistrySnapshot ↔ tools.md byte-gate）。
- **SKILL.md 同步**：34/11/枚举含 refine_masks+get_schema/§6 nod 齐
  （原 stale「32 tools」顺路修对）。
- **❌ E-3（error）**：`jsonValue()` 的 Bool 检查
  （`McpSchemaCatalog.swift:387` `if let b = value as? Bool`）被
  Foundation NSNumber 桥接污染——JSON 数字 **0/1（含 0.0/1.0）经
  `as? Bool` 成功桥接**（本机实测：`__NSCFNumber(1) as? Bool` =
  `Optional(true)`，`0` = `Optional(false)`；2/-1/2.5 正常返回 nil）。
  后果：get_schema 应答中所有默认值为 0/1 的数值字段输出 `false`/
  `true` 而非数字——实锤样本：`temperature.red/green/blue`（默认
  1.0，`TemperatureModule.Params` init）→ `"default": true`；
  `colisa.contrast/brightness/saturation`（默认 0）→ `false`；
  `exposure.exposure`（默认 0）→ `false`；toneequal 十 band、
  equalizer g0..g5 同理全污染。**omp 两层自审未抓的根因**：
  `testDefaultsEqualTheEncodedDefaults`（`McpGetSchemaTests.swift:102-112`）
  的「独立解码比对」拿 wire 值再过**同一个污染函数** `jsonValue()`
  自我镜像（`bool(false) == bool(false)`），自洽通过——独立源实际
  不独立。修复方向：NSNumber 分支用 `CFGetTypeID(n) ==
  CFBooleanGetTypeID()` 判真布尔（Bool 检查删除或后置），补一条
  「数值 0/1 不误判」断言（断言走独立期望值，非镜像函数）。

### UQ-S2 onboarding 节（`f9ceb510`）— 判定：PASS

- `McpOnboarding.swift` 模型单源（executable/discovery live 生成）+
  `SettingsPages.swift` 三粘贴块（Claude Code stdio 终端行 / Desktop
  JSON / CLI 用法）+ 安装行（marker 全串守卫 + 0o755 + 原子写 +
  非本 app 文件拒覆盖）。D-UQ-3（stdio 双块、HTTP 端口 ephemeral
  不入配置）成立。
- **安全面净**：配置块仅含可执行路径 + `--mcp-stdio` 参数 +
  discovery 路径显示——无 token/key/端口泄露面；Bearer token 不入
  任何粘贴块。installError 输出 `String(describing:)` 仅 refused
  message（路径），无堆栈。
- xcstrings 15+1 键尾块；zh-audit --check PASS（2116 catalog = 2100+16
  与 R2 核对一致）。

### UQ-S3 CLI 门（`310a499a`）— 判定：PASS（协议/门序/错误面核对全过）

- **协议链**：discovery（`resolveEndpoint` → `McpEndpointDiscovery
  .discover`，no file/stale 均 typed refused）→ SDK `HTTPClientTransport`
  握手（Bearer 经 `requestModifier`，loopback none 免 token）→
  `tools/list` / `tools/call` → `resultJSON` 打印 → `exit(code)`。
  入口 fork 在 headless 臂后、AI-worker 前（`LightamerApp.swift:146-154`），
  GUI 永不构造；`mcp` argv 不含 `--mcp-*`，不会被 headless 臂截走。
- **错误码面**：`clientError` 15 token（14 McpToolError caller-fault
  + SDK unknownTool）→ exit 2；19 case 全集 = 14 refused + 5 failed
  （renderFailed/renderTimeout/exportFailed/modelUnavailable/internalError），
  无缺口；R2-M2 修复（imageLiveInEditor 入 refused）亲证在位
  （`McpOneShot.swift:277`）。parse 的 bare/help exit 2（M-10）、
  `--list` 别名在位（R2-M4 指出的 usage 缺 `--list` 注记仍未补——
  见 B-2）。
- **stdout 纪律**：成功仅结果 JSON（D-UQ-5），sinks 可注入，
  e2e 真二进制测试断言 stdout 含 get_schema/list_iops。
- **AgentAccess off-by-default 未被绕过**：CLI 门要求 app 开 + MCP
  启（discovery 缺文件即 refused）；stdio 臂是显式 flag 授权；
  requiresWriter 工具走 server 侧既有 turn-taking，无新旁路。
- **D-UQ-4（HTTP 单腿）申报接受**：stdio 派生抢 writer lock + 语义
  分裂的理由成立，二级挂账合理。

## 专项复核

### Project.swift 吞行事故（任务书 §3）— 亲证修复

`git diff 1b241de9..HEAD -- Project.swift` 逐行：**纯插入两行**
（`McpGetSchemaTests.swift` / `McpOnboardingTests.swift` 登记），零删除
零改写；970 `McpControlToolsetTests` / 973 `AgentControlCoordinatorTests`
双补回行均在位。BUNDLE-MAP 同批两行（`APP 7 McpGetSchemaTests` /
`APP 11 McpOnboardingTests`）在位。D-UQ-0 双吞行事故勘误与 diff 实况
自洽（1075 = 1073+17−15）。**无其它被吞行**。

### union 快照纪律（任务书 §2）— additive 合规

`McpFinalSnapshotTests` 改动 = 快照行 + `all33→all34` 改名 + count
33→34 + 注记链申报（serial right 行使，editing 10→11 注记续写）；
destructive 集 10 枚不动（get_schema readOnly）。7 个 count 钉文件
（Final/Registry/Host×2/Launcher/SearchState/Control/RefineMasks）逐一
grep 对上 D-UQ-6 的 11 处清单；`McpRegistrySnapshotTests` 的
editing+culling 24→25 同批申报。五钉未破（无 35th whitelist 负测在位）。

### 安全面（任务书 §4）

三件均无凭据打印/堆栈泄露面；onboarding 配置仅路径/参数形态（见
UQ-S2 节）；CLI 门 stderr 仅 error message（typed `String(describing:)`
of refused/failed message，均短句）；token 只走 requestModifier 内存
传递，不落盘不入输出。off-by-default 见 UQ-S3 节。

## 自审盲区扫描（任务书 §6——omp R1/R2 之外的切口）

1. **E-3（error）get_schema 默认值 Bool 桥接污染**——见 UQ-S1 节。
   omp 两层自审的测试镜像盲区（独立解码过同一污染函数）。
2. **obs-1 get_schema token 体量**：223 字段 pretty JSON ≈ 59KB
   ≈ 15k tokens/次（defaultFace 16 op ≈ 46KB ≈ 12k）。对 agent 上下文
   可感知（上游 RFC-026 同构，非本批偏离）；二级 CLI 立项时建议
   compact 输出或 `op` 过滤参数一并考虑。
3. **obs-2 unsigned 分发下的安装面**：`executablePath` 走
   `resolvingSymlinksInPath`——app 从 DMG 直跑（卷未装）时配置块嵌
   `/Volumes/...` 路径，卷卸载即失效；app 移动后旧 script 判 `.other`
   （显示语义略偏，但 uninstall/reinstall 守卫均按 marker 正确放行）。
   unsigned 分发固有属性，不构成缺陷。
4. **B-2（minor，R2-M4 残留）**：`McpOneShot.swift:43-51` usage 仍不载
   `--list` 别名（`:99` 在位）——R2 已报、未修、未申报接受，修复轮
   顺路一行。

## 回归复跑（任务书 §5）

| 项 | 结果 |
|---|---|
| App bundle（zcode 复跑） | **1091/6/0**，peakRSS 1895MB，646s —— 与 omp 终轮一致 |
| IOPParity bundle（zcode 复跑） | **565/10/0**，peakRSS 4632MB，1629s（8G 门内），0 failed |
| zh-audit --check | PASS（1783 source keys / 2116 catalog keys / 10 interp keys） |
| machine-guard | G4 贴线透明越门（16.36GB 可用 < 25GB 门；本批执行注记同款先例），`--monitor` 伴跑零告警 |

omP 申报全套 4461/34/0 的 App 腿（1091/6/0）已独立复现；余五 bundle
按 R2 修复零跨 bundle 改动沿用 `--all` 轮值，本 review 不重跑。

## 发现清单汇总

| # | 级 | 位置 | 内容 | 处置 |
|---|---|---|---|---|
| E-3 | **error** | `McpSchemaCatalog.swift:384-394` | `jsonValue` Bool 桥接污染：默认值 0/1 输出 false/true（temperature/colisa/exposure/toneequal/equalizer 实锤）；测试镜像自洽故两层自审未抓 | 修复轮必修：CFBoolean 判型 + 独立期望断言 |
| B-1 | — | （账本） | R2-M3（收口 `--all` 终值落账）由收口 gate 承接，非缺陷 | 收口时落账 |
| B-2 | minor | `McpOneShot.swift:43-51` | usage 不载 `--list` 别名（R2-M4 未修未申报） | 修复轮顺路 |
| obs-1 | obs | `McpSchemaCatalog.schemaJSON` | 输出 ≈59KB/15k tokens（pretty 全量） | 二级 CLI 立项面 |
| obs-2 | obs | `McpOnboarding.installState` | app 移动后旧 script 判 `.other`（守卫行为正确，仅显示语义） | 不动 |

## 判定依据

- 三件 AC 逐项核过（合成缝/覆盖面/协议链/门序/错误码全集），批结构
  与申报一致，无虚报。
- E-3 为数据正确性缺陷（agent 面向参考文档的默认值列失真），非结构
  性——不推翻批交付，但按闸门纪律**必修后方可视为批终态**；修复后
  只需重跑 App bundle（get_schema 测试域）+ zh-audit。
- 其余全部 PASS 或已有合理挂账/申报。
