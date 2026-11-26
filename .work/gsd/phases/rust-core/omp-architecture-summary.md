# omp-architecture-summary — 会话架构定稿调研交付（stdout 同文落盘）

> 日期 2026-11-26。产物：`.work/gsd/phases/rust-core/` 下 `ARCHITECTURE.md`（正文 §0–§9 + 两附录）、`ARCHITECTURE-TABLES.md`（T-A1–T-A9）、`architecture-review.log`（域内自审）、本文件。零 commit。

## 结论（§0 一页纸摘要）

会话包=plain 文件夹：`Capture/ Selects/ Output/ Trash/ <Name>.lmsessiondb(SQLite) Cache/Thumbs/ session.lock`，每张图一份同目录 `Lightamer/<stem>.lmsettings`（JSON 调整+元数据，随图走）；应用层 Recent/模板/偏好在会话之外。分层沿 T-F9：L2 历史+设置文件编解码，L3 会话库+预览，L4 会话命令+锁+导出（默认 Output/），L5 会话浏览器+灯箱+暗房。

用户问题的答案：历史存每张图的设置文件，不在库里（库只结构/索引/缓存）；XMP 第 0 期不要（不选库不写；导出嵌标准字段；跨软件 XMP 排 C 期）。导入默认复制进 Capture（可选引用）；Selects=物理移动；删除=移进 Trash 只读，清空=永久删除，撤回=移回；最近 10 会话存应用层；模板=结构；多会话多窗口，单会话单写者锁。

5 个裁决点（§8）：历史位→乙；库存储→SQLite；导入→默认复制；目录模式→不做；单张搬出→可以。

新估时：A 9 波 18 lane 45.5h；B 20 波 79 lane 217h；合计 97 lane 262.5h（含自审 ≈315h ≈40 日）。首个可用版仍 B20 后。

## 取证说明

- Capture One：13 篇官方文档（12 篇支持指南经 web.archive.org 2025 快照取，support 本体 Cloudflare 直取失败已记录；3 篇官方博客经官网/快照取）。T-A1 共 55 条引文，每条带原文与链接；T-A9 列 10 项没查到/版本差异/官方未说明。
- LightCraft：只读本地树 `0da998f2`，Q3/Q4/Q5 引用的代码位置均为当日 `grep -n`/`sed -n` 重核行号。
- 九月笔记勘误 6 条（T-A2）：`Captures`→`Capture`、`Crop/` 无此文件夹、设置文件位置表述、cosessiondb 半真相、Selects 可重指定漏列、目录 SQLite 系推断。
- 数字诚实：无实测标推断（SQLite 批量、10 万行体积/查询、多窗口预算）；LC 三性能数沿 FRAMEWORK §13 查不到。

## 未验/风险

- 复审结论见 `architecture-review.log`（本文件落盘时待填：___）。
- B12'/B13 实测填数前，批量粘贴 1s 门与 10 万行查询均为推断。
- 总墙钟要求 170 分钟内含自审；到点交已有结果（本文件即全量结果）。
