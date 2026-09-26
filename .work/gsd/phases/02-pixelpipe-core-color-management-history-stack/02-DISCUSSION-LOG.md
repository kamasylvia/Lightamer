# Phase 2: Pixelpipe Core - Discussion Log

> **Audit trail only.** Decisions are captured in CONTEXT.md — this log preserves how they were made.

**Date:** 2026-09-18
**Phase:** 2-Pixelpipe Core, Color Management & History Stack
**Mode:** 保活巡检自动推进（YOLO 授权 + 用户"全自动推进"指令）

---

## 过程

- 巡检触发时向用户呈现 4 个灰色地带（sidecar 格式/history 语义/缓存策略/色彩预览）的 multiSelect 讨论，用户离线未应答。
- 依据：用户已建立保活巡检机制并明确指示"保证全自动推进"；项目 config mode=yolo；用户历史模式为技术决策委托（"其它还需要补充的你来帮我想"、"你决定"、"你来建议"多次）。
- 处置：以研究文档 + Phase 1 spike 证据为基础，全部四域以**最佳判断定稿**，标记为可审阅推翻的自主决策（所有决策 reversible/costly 分级已注明）。

## 决策摘要（详见 CONTEXT.md）

| 域 | 决策 |
|---|---|
| Sidecar | JSON pretty + schemaVersion；`.ARW.lra` 追加式命名；节流 2s 原子写；忽略 .xmp |
| History | drag-end 一步；无上限；快照延 Phase 6；paramsHash 漂移检测 |
| 缓存 | >3GB 自动 clearCaches（load 入口 + 60s 兜底）；PREVIEW 2560px/360px 档位量化 |
| 色彩 | ColorChecker 中性灰 golden 验收；跟随屏 ICC；colorout 预留 profile 参数位；EDR 位深预留 |
| 前置 | issue #1 修复纳入 Phase 2 首任务（渲染路径统一到 load() decodeTask）|

## 用户推翻点

所有决策均可在 Phase 2 执行前/中推翻：修改 `02-CONTEXT.md` 对应 D-XX 并知会执行链即可。
