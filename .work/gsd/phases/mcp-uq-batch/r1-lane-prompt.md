# MCP-UQ 批域内自审任务书（omp subagent review lane）

你是 MCP-UQ 增量批的独立 review agent。工作目录
/Volumes/UNITEK/Documents/Development/Lightamer。只读产物，不读执行 lane
中间态（`omp-evidence-*`、lane prompt、monitor.log 禁读）。全程中文，
stdout 最后一条消息一次性完整输出结论。

## 审查对象（产物 diff = HEAD `1b241de9` 起全部改动）

三件交付 + 测试 + 文档：
- 新：`App/Sources/Lightamer/MCP/Tools/McpSchemaCatalog.swift`、
  `App/Sources/Lightamer/MCP/McpOnboarding.swift`、
  `App/Sources/Lightamer/MCP/McpOneShot.swift`、
  `Tests/LightamerTests/McpGetSchemaTests.swift`、
  `Tests/LightamerTests/McpOnboardingTests.swift`
- 改：`EditingToolset.swift`（get_schema 注册+descriptor）、
  `LightamerApp.swift`（`mcp` 入口 fork）、`SettingsPages.swift`
  （onboarding 节）、5 快照/count 测试 + SKILL.md/tools.md +
  xcstrings（16 键尾块）+ Project.swift + BUNDLE-MAP
- 账本：`.work/gsd/phases/mcp-uq-batch/MCP-UQ-{SUMMARY,DECISIONS}.md`
- 正本：`.work/gsd/research/UPSTREAM-QUEUE.md` UQ-S1/S2/S3 行；
  上游参考 = SpektraLab 提交 `85c9c16`（`git show` 读提交对象）

## 审查维度

1. **正确性**：合成缝三源是否真单源（key 集/type/version 有无复列漂移）；
   parse/错误映射/exit 码是否与宣称一致；entry fork 是否永不构造 GUI；
   stdout 纯结果 discipline 是否成立（含 SDK client 噪音面）。
2. **快照纪律**：union 33→34 是否每处 conscious（domain/union/SC7/
   control/descriptionKeys/tools.md/SKILL.md）；有无漏钉（grep 33/24 残留）。
3. **封存面**：17 件（DrtRecord/TerminalTailPolicy/DrtTailAssembly/
   PixelPipe/Lut3dKernels.metal/DrtEotf/ExportQueueContract/六格式矩阵/
   NodeGraphCommand/sidecar schema/HistoryStack/HistoryHash/
   PipelineDocument/V50Order/GradeCatalog/Registry/ModuleInstance）零 diff。
4. **测试诚实性**：17 法是否透过生产缝（有无 mock 回声/同义复述）；
   e2e 子进程测试 env 缝是否成立；注记闭合测试是否真钉。
5. **反自取消探针**：执行 lane 宣称 vs 实际 diff 逐项核对——SUMMARY/
   DECISIONS 有无夸大、漏报、与 diff 矛盾处；D-UQ-4（S3 只做 HTTP）
   申报是否诚实；D-UQ-0 欠账注记是否属实。
6. **行为级深审**：`mcp call` 对大 payload（render_preview base64 级）
   的 stdout 形态；Bearer 缺失臂；discovery stale 臂；onboarding 安装
   面误伤他人文件臂；get_schema 对 seed 缺席 op 的 null 默认臂。

## 机器纪律（强制）

- 只读审查：**不跑构建、不跑全套、不派子进程测试**（读代码 + git diff
  + 现有产物即可）。如需实测单点，限 `grep`/`python3` 静态核对。
- 不杀任何进程，不碰 DerivedData，不写任何文件。

## 输出格式

结论头 `PASS / N error + N minor`，后接逐 finding（文件:行 + 根因 +
复现/证据 + 修复建议）。error = 必须修（正确性/纪律违反/漏钉）；
minor = 可顺手（文案/注记/测试增强）。
