# RAWmakase 调研速记（2026-10-03，源 = 用户给链；已克隆 `/Volumes/UNITEK/Documents/Development/rawmakase`）

> 定位：**Rust 写的 Linux/macOS Lightroom 替代品**（MIT 代码；Adobe DNG SDK tone curve 单独许可/Inter OFL/Lucide ISC 见 `licenses/`）。单 crate 显式域模块（解析/持久化/渲染不 import 桌面 UI——与我方 Core/App 同纪律）。亮点 = **对 Lightroom 的量化 parity 工程学**。

## 可借鉴候选（待用户裁决；按价值排序）

1. **`.lrcat` 只读导入全家桶**（docs/catalogs.md + `src/catalog/lightroom/`）：rating/flag/colorLabels（含自定义文本标签保留原文）/keywords/collections 虚拟副本身份/serialized Develop settings/**Develop history steps（lightroom_history 表逐 step 可应用）**。导入纪律范本：私有快照 + SQLite 完整性检查 + **拒绝带 WAL 的活动目录**（非静默忽略）+ <2GB 限 + **源 .lrcat 字节级全量备份进 `sources.original_catalog`**（未解释字段不丢：smart rules/faces/IPTC/GPS）。对照：我方 12-3 只读导入仅 .xmp 单文件；**Lightroom 目录级迁移 = 真实 V2 interop 候选**（我们 FTS/图库/评分底座全在）。
2. **Lightroom parity 评分方法论**（docs/parity-gaps.md + `scripts/lightroom-scorecard.py`）：编码 sRGB MAE 对 Camera Raw/LR Classic 导出打分、逐控件拟合误差量化（Whites +50 photo-adaptive 不可拟合等诚实边界）、`macos-lightroom-validation.md`。**工程价值**：证明「LR 预设/参数互通」可行且可量化——我方现裁决「预设与 LR 不互通」（CONVENTIONS），此方法论是 V2 重开该决策的依据与施工图。
3. **筛图键盘流**（shift+评级/旗标/色标 = 应用并前进；`[`/`]` 星级增减；backtick toggle pick；6-9 色标 toggle；再按同色清色标）——Phase 9 CullingView UX 补强候选（小件）。
4. **DCP 有界子集 + 相机 profile 库**（`src/camera_profiles/` + docs/lightroom-profiles.md：triple-illuminant/HDR 拒绝、Enhanced XMP looks、自有 look）——CIRAW 不吃外部 DCP（STACK 架构边界），v2 libraw 兜底路径下再议；先记研究注记。
5. **docs 工程文化**：code-map/usage-stats/parity-gaps 诚实量化边界——方法学参考（我方 LESSONS/GOAL-STATE 同精神）。

## 已覆盖/不借鉴
草稿→全质量预览升级（我双档缩略图+PREVIEW 管线覆盖）/ spot removal（Phase 6 heal+clone）/ 生成式 AI 蒙版（its coming-soon；我方裁决不做生成式填充）/ CLI（Phase 14 MCP 超集）/ decode_cache 键设计（PipeCache 同构）/ 单 slot mailbox+generation+取消（EditorState/ExportQueue 同构）/ 导出恒 sRGB（其弱项，我方 ICC=DRT 联动更强）。

## 裁决记录
（待用户：候选 1/2/3 是否立项——1/2 为 V2 interop 大件，3 为 UX 小件）

## 裁决（2026-10-03 用户）

**候选 1/2/3 全部不吸取**；AGENTS.md 参考条目已撤、本地克隆已删（可随时重克隆）。本调研存档备查——若未来重开「Lightroom 互通」决策，第 2 节方法论仍是有效施工图。
