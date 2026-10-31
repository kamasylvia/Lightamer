# MCP-UQ 增量批：UQ-S1/S2/S3 一级（omp 执行 lane）

你是 MCP 增量批执行者。工作目录 /Volumes/UNITEK/Documents/Development/Lightamer。全程中文，commit 英文。当前 HEAD = `1b241de9`，全套基线 **4443/34/0**。产品 commit `refs #N`（gh 建 UQ-S 族 issue）。

## 交付三件（正本 = `.work/gsd/research/UPSTREAM-QUEUE.md` UQ-S1/S2/S3 行）

1. **UQ-S1 get_schema 自描述工具**：MCP 新工具 `get_schema`——「每个可编辑字段：路径/类型/范围/含义，编辑前必读」。数据源 = op 注册表 + 参数元数据合成（读 M7 工具注册表现役面找合成缝）；覆盖全部可编辑 op 字段。参考形态 = SpektraLab `git show origin/main:modern_UI/Spektrafilm/Spektrafilm/Agent/AgentTools.swift` 的 get_schema 条目（本地树 stale，禁工作树文件）。**skill 文档仓 tools.md 同批再生成**（机检测试即门 M7-6 先例）。
2. **UQ-S2 Agents onboarding 设置节**：Settings MCP 页增「接入向导」节——显示粘贴即用配置（Claude Code / Claude Desktop 两种形态的 JSON 配置块，从 discovery 文件路径动态生成）+ CLI 命令安装说明（若有 CLI 门则一并）。zh/en 双语（xcstrings 尾块纯插入）。
3. **UQ-S3 一级一次性 CLI 门**：`Lightamer mcp call <tool> '<json>'`——读 discovery 文件 → stdio/HTTP 握手 → tools/call → 打印结果 → 退出。协议级复用（零新工具定义 = 天然 parity）；支持 `--list`（列工具）；错误态（app 未开/MCP 未启/控制权要求）typed 输出。

## 纪律

- 封存面 17 件零 diff；`McpFinalSnapshotTests` union 快照改动按 M7 快照纪律（additive 显式申报 + 快照测试同步）；**get_schema 入 union 快照**。
- 机器：guard **G4 透明越门先例（Data 卷 ~19G 现实基线，DECISIONS 追记；起跑前清 /tmp 残留尽人事）** + `--monitor` 伴跑 + ps 清零；SPM 失败 `-disableAutomaticPackageResolution` 离线先例。
- 测试透过生产缝（真 MCP stdio/HTTP 客户端抽测——M7 e2e 先例）；zh-audit 双 PASS；全套 `--all` 预批（预期 4443 ⊕ ΔN，带 +8..14 自行按任务分解落，红即停分类）。
- **域内自审层**：三件完成后派自己的 omp subagent review lane（隔离白名单：review 只读产物不读你的中间态；机器纪律进 subagent 任务书），发现回注自修，收敛后收口。

## 产出契约

SUMMARY/DECISIONS（`phases/mcp-uq-batch/`）+ issue + commits + stdout 一次性完整输出（含 ΔN 实数、union 快照变化、域内自审结论）。
