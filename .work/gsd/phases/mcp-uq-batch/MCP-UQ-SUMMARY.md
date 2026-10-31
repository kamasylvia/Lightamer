# MCP-UQ 增量批 SUMMARY（UQ-S1/S2/S3 一级，omp 执行 lane）

> issues：#18（S1）/ #19（S2）/ #20（S3）。基线 `1b241de9` 全套 4443/34/0。
> 上游正本：SpektraLab `85c9c16` RFC-026（`AgentTools.get_schema` 条目 /
> `AgentsSettingsPage` / `AgentCLI`+`AgentAccess`，`git show` 读提交对象，
> 工作树 stale 未用）。

## 交付

- **UQ-S1 `get_schema`**（`refs #18`）：MCP editing 域新只读工具。
  合成缝 = `IopCatalog.ops`（op 名录 + type 串，消费不复列）
  × seed 编码默认值（seed record paramsData / GradeCatalog.identityJSON，
  与 T3 guard 同源）× 手写 range/meaning 表 19 op 全覆盖。
  应答 `{ops:[{opName,display,iopOrder,version,domain,
  fields:[{path,type,range?,meaning,default}]}],count,note}`，
  default-face 走 `defaultFaceOps()` 收窄（16）。union 33→34，
  editing 10→11，editing+culling 24→25；domain/union 快照 + tools.md
  同批再生成（机检门）。
- **UQ-S2 onboarding 节**（`refs #19`）：Settings MCP 页增「接入向导」节——
  Claude Code 终端行（stdio `claude mcp add`）/ Claude Desktop JSON 块 /
  CLI 用法行三粘贴块（Copy 按钮）+ `~/.local/bin/lightamer` 两行脚本
  安装/重装/卸载行；路径一律 live 生成（executable/discovery 单源）。
  xcstrings 15 键尾块纯插入（+ S1 描述键 1 = 本批 16 键）。
- **UQ-S3 一级 CLI 门**（`refs #20`）：`Lightamer mcp list|call <tool>
  '<json>'`——discovery→SDK HTTP 握手→tools/list-call→打印→退出；
  stdout 仅结果 JSON，诊断走 stderr；exit 0/1/2 三态 typed；
  Bearer 臂走 `requestModifier`（loopback none 免 token）。
  入口 fork 在 `--mcp-*` 后、AI-worker 前（GUI 永不构造）。

## 测试

- 新文件：`McpGetSchemaTests` 7 法（名录闭合/注记闭合/默认值源闭合/
  默认值诚实/registry 应答/默认面收窄/InMemory+HTTP 双腿）+
  `McpOnboardingTests` 11 法（配置生成/脚本形态/parse 纯/探针/
  错误映射/真二进制 e2e）→ ΔN=+18。
- 全套：**4461/34/0**（基线 4443/34/0 ⊕ ΔN=+18；App 1091/6/0 终轮实跑，
  余六 bundle 沿 --all 轮全绿值——R2 修复仅 App 面，零跨 bundle 改动）。
- zh-audit `--check` + `--self-test` 双 PASS。

## 文件

- 新：`MCP/Tools/McpSchemaCatalog.swift`、`MCP/McpOnboarding.swift`、
  `MCP/McpOneShot.swift`、`Tests/McpGetSchemaTests.swift`、
  `Tests/McpOnboardingTests.swift`。
- 改：`EditingToolset.swift`（注册+descriptor）、`LightamerApp.swift`
  （入口 fork）、`SettingsPages.swift`（onboarding 节+视图）、
  7 快照/count 测试（Final/Registry/Host/Launcher/SearchState/
  Control/RefineMasks 域枚举）、`skills/.../SKILL.md`（count×3+枚举+
  §6 nod）、`skills/.../tools.md` 再生成、`Localizable.xcstrings`
  （16 键尾块 + 15 en 值）、`Project.swift`（纯插入两行）、
  `M2-4-0-BUNDLE-MAP.txt`、`NOTICE`（§V RFC-026 条）。
- 封存面 17 件零 diff（diff 文件清单 grep 亲证：`Registry` 命中系
  `McpRegistrySnapshotTests.swift` 测试文件，非封存件；R1 §7 同证）。
