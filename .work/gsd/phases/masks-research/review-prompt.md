# 蒙版调研复审任务书（只读复审，不写产品代码）

你是独立复审实例。被审产物（只读，不许改）：

- `/Volumes/UNITEK/Documents/Development/Lightamer/.work/gsd/phases/masks-research/RESEARCH.md`
- `/Volumes/UNITEK/Documents/Development/Lightamer/.work/gsd/phases/masks-research/RESEARCH-TABLES.md`

架构约束（只读）：

- `/Volumes/UNITEK/Documents/Development/Lightamer/.work/gsd/phases/rust-core/PLAN-B.md`（§1.9 命令/作业界线、§7）
- `/Volumes/UNITEK/Documents/Development/Lightamer/docs/APPLE-BOUNDARY.md`
- `/Volumes/UNITEK/Documents/Development/Lightamer/.work/gsd/phases/rust-core/FRAMEWORK-TABLES.md`（T-F9 层表）

参考项目源码（只读；禁任何 git 写操作；禁进 `/Volumes/UNITEK/Documents/Development/darktable` 与 `darktamer`；dt 读 `/Volumes/UNITEK/Documents/Development/Lightamer-rust-spike/refs/dt-master-latest`）：AlcedoStudio、lumen-raw、SpektraLab、RawLab、lightcraft、yiyin（均在 `/Volumes/UNITEK/Documents/Development/` 下）。

## 复审项（全部做）

1. **行号抽查**：从两份产物里抽至少 12 处 `文件:行号`，打开文件核对行号与内容相符（行号漂移 >5 行记 minor，内容不符记 error）。抽样须覆盖 dt、Alcedo、lumen、lightcraft 四家。
2. **类别对照表**：T-M2 里每一个 ●（正式功能）逐个打开源码确认功能存在且为正式（非占位/残根/规划）；每一个 ◐ 确认确实是实验/下线/部分；抽 3 个 — 确认真的没有（grep + 读上下文）。
3. **许可证**：每一条许可结论对着仓库里的许可文件核一遍原文（代码许可与模型/资产许可分开核：lumen 的 `assets/*-LICENSE.txt` + `THIRD_PARTY.md` + 根 `LICENSE`；Alcedo 的 `THIRD_PARTY_NOTICE.txt` + `NOTICE` + `LICENSE` + `third_party_licenses/`；lightcraft 的 `NOTICE` + `Cargo.toml` + `faces/known.rs`；dt 的 `LICENSE` + `data/ai_models.json`（确认无许可字段）；SpektraLab 的 `README` + `license/`；RawLab 的 `LICENSE` + `docs/reference/licensing.md`；yiyin 的 `LICENSE` vs `package.json` 矛盾）。
4. **B14 范围纪律**：Q1 建议的 B14 基础包（10 lane / 30 h）有没有把费时活（光栅化、混合计算、推理）放进命令里（对照 PLAN-B §1.9：命令只做有界活）；有没有让 Apple 的东西跑到 `dt-apple` 之外（对照 APPLE-BOUNDARY.md + T-F9）；估时与引用的 dt 源码量级是否对得上（数量级错 3 倍以上记 minor）。
5. **Q4**：亲跑 `git log --oneline 679d594f5d..FETCH_HEAD -- <蒙版路径>` 与 `git diff --stat`（在 `refs/dt-master` 里，只读，不许改基线/worktree），确认「1 笔 GUI 提交」结论。

## 纪律

- 只读：不写任何文件（你的输出直接 stdout，不落盘，由调用方重定向存档）；不构建、不跑测试、不下载模型、不装软件；不碰用户照片库；不读凭据。
- 结论头第一行必须是 `PASS / N error + N minor`（N 为数字）。
- 之后逐条列 finding：级别 + 位置（产物文件+节）+ 证据（源码文件:行号）+ 修法建议。
- 最后一条消息一次性完整输出全部结论（合并为最后一条消息）。

中文汇报，标识符英文。墙钟 40 分钟内交卷。
