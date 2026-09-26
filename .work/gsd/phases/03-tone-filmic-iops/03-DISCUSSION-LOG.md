# Phase 3: Tone & Filmic iops - Discussion Log

> **Audit trail only.**

**Date:** 2026-09-19
**Phase:** 3-Tone & Filmic iops
**Mode:** 保活巡检自动推进（YOLO 授权延续；与 Phase 2 discuss 同模式）

---

## 过程

- 巡检触发，用户离线未应答灰色地带 multiSelect（与 Phase 2 同情形）。
- 处置：按既定模式自主定稿 5 项决策，全部记录于 CONTEXT.md 可审阅推翻。

## 决策摘要

| 域 | 决策 |
|---|---|
| filmicrgb | Darktable 完整移植（verbatim 分段），golden 对照 darktable-cli |
| 顺序 | sigmoid 先行（简单建基线）→ filmicrgb（最难） |
| toneequal | 全局 5-band 进 Phase 3（无蒙版依赖）；蒙版 Phase 6 |
| WB 吸管 | viewport 点击采样 → 中性色解 |
| golden | darktable-cli 已构建可用（1263552fab）；参考存 input/golden/（gitignored + 再生脚本） |
| Inspector | Phase 3 建立首个真实 iop 参数面板框架（UI-SPEC token 体系） |

## 新事实

- darktable-cli 已在 Darktable 构建目录确认可用——golden 参考生成路径打通。
