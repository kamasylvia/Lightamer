# UPSTREAM-QUEUE — 新特性立项阶段的 upstream 候选

> 用途：参考上游增量同步批判定「值得入队」但**不立新 REQUIREMENTS ID** 的小件候选，集中在此。
> 消费时机 = **下一修复批收口后、新特性立项前**，由 orchestrator 逐项裁决（立项 / 续挂 / 撤销）。
> 已落地的项移文末「已兑现」节留痕。既有 EXPORT-PRESET-01 已落
> `ALCEDO-PARITY-2026-10.md` §二 REQUIREMENTS V2 候选节，不在此重复。
> 建档：2026-10-16（Alcedo +19 / lightcraft +43 同步批）。
> **2026-10-16 M7 charter 批：四候选全部入队**（用户裁决③「按推荐」生效）——立 REQUIREMENTS ID：UQ-A1 → M7-6 / UQ-A2 → M7-4 / UQ-L1 → M7-6 / UQ-L2 挂面不入波；本文件为来源正本，兑现后按惯例移文末「已兑现」节。

## 候选区（Alcedo，正本 = ALCEDO-PARITY-2026-10.md §五）

| # | 候选 | 上游锚 | 我方缺口 | 规模 | 入队理由 |
|---|---|---|---|---|---|
| UQ-A1 | DRT-SDR 预览层 colorspace 改挂导出同款 ICC v4 字节（`CGColorSpace(iccProfileData:)`）+ ColorSync 解码等值测试 | `36db9a8`（#391） | 预览层挂 calibrated-RGB 近似空间（srgbPiecewise 以 2.2 幂近似分段），导出文件携 ICC v4——preview/文件双曲线解码失配，上游实测同病同修 | 小件 | M4-1 色彩收尾批顺路；消除 SDR 幂编码观感差；L053 自建字节直接复用 —— **已入队 2026-10-16 = REQUIREMENTS UQ-A1 → M7-6** |
| UQ-A2 | 导出 FAIL 档终写原子不覆盖（tmp 编码 + `link()` EEXIST 拒晋升 + unlink tmp） | `6203791` | `.fail` = occupiedNames 快照检查 + 编码器直写——快照与落盘之间他进程建文件即被覆盖（TOCTOU） | 小件 | ExportCollisionPolicy 语义补全；上游以 renameatx_np/renameat2 落地同纪律，Swift 走 `link()` 排他即达 —— **已入队 2026-10-16 = REQUIREMENTS UQ-A2 → M7-4** |

### 未来面纪律（对应面立项时吸收，不单独立项）

- 自动化/MCP 输出面**排他创建 + 失败清理自建物**（`1f12551`）——MCP thumbnail/preview 类生成命令扩面时。
- CLI 壳 `--version` 旗标惯例（`ace755e`）——若建随包 CLI。
- session-prune「只删自家记录」（`c1a66b4`）——若建 prune 面；sidecar 隔离设计已天然满足，届时核对即可。

## 候选区（LightCraft，正本 = LIGHTCRAFT-NOTES.md §七）

| # | 候选 | 上游锚 | 说明 | 规模 |
|---|---|---|---|---|
| UQ-L1 | 滑杆双击重置 + 值横扫 scrub（KEY-SLIDER-RESET/SCRUB） | `cb8b797c` `ab64e9a5` | SwiftUI Slider 无原生支持需自实现；yiyin 面板与我方 iop 面板通用 UX，两件合一个滑杆 UX 小件 | 小件 —— **已入队 2026-10-16 = REQUIREMENTS UQ-L1 → M7-6** |
| UQ-L2 | 软打样 1:1 zoom window + 「1:1 像素 == 导出」等值测试验收形态（LR-VIEW-ZOOM） | `c78b457c` | 软打样未立项；立项时验收形态直接取用（挂软打样面，不独立排期） | 挂面 —— **已入队 2026-10-16 = REQUIREMENTS UQ-L2（挂面维持，无 phase 指针）** |

### 方法论一次参考（不排队）

- Faces 网络整体 GPU 化的「GPU 批处理 + CPU-only 回退开关 + 限速使用」模式（`0242a75b`/`f625c74c`）——M2AI 推理 worker 设计前翻一次实现即弃。
- 蒙版笔刷 Shift-click 直线笔画（`e5c6e17b`）——我方笔刷若建，Lightroom 惯例对齐。

## 已兑现

（空——本文件 2026-10-16 新建。）
