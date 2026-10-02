# SpektraLab 调研速记（2026-10-02，源 = 小红书公告笔记 → 官方指南 + 开源仓实测）

> 来源链：XHS 笔记（v1.2.2 上线使用指南公告，笔记本体薄、干货在指南与仓）→ 指南 jamesqiu2005.github.io/SpektraLab（camoufox 渲染）+ 仓 `JamesQiu2005/SpektraLab`（已克隆 `/Volumes/UNITEK/Documents/Development/SpektraLab`）。
> 定位：**macOS 胶片+放大相纸模拟器**——81 波长光谱穿染料层物理建模（非 LUT）、28 款实测胶片/相纸配置 + 8 放大 LUT（上游 andrevolpato/spektrafilm）、C++20 + Metal 编译进 app、45MP 全渲染 <1s、预览重印 ~0.01s、单 arm64 二进制 32MB。
> 许可：**代码 GPL-3.0-or-later**；**胶片/相纸配置与放大 LUT = CC BY-SA 4.0**（Andrea Volpato spektrafilm，独立于代码许可）；metal-cpp Apache-2.0。

## 可借鉴（按价值排序）

1. **模拟链阶段分离语义（核心）**：「场景置位（显影/胶片**前**）→ 胶片记录光 → 相纸呈现（配光 = 软件测光自动算放大机滤色组合 + Y/M 手动偏移叠加）→ 导出」。film sim 从「贴一段 LUT」升维为「物理流程」的语义框架；配光 = 对当前相纸的自动滤色求解是 UX 亮点（换材料重配光作比较起点）。若未来胶片模拟升级（V2+），照此两段式建模而非 M2GRADE 现行单段 LUT。
2. **宽容度面板 + 场景置位 UX**：直方图 + 胶片容纳范围双虚线 + 低于/内/高于占比；「场景置位在胶片前、显影曝光在胶片后，两者不可互替」「EDR 在输出侧、不能找回输入端已丢高光」——输入端/输出端分离的教导对我们 exposure/DRT 交互直接适用（即便我方在 CIRAW 后 RGB 域，语义同构）。
3. **CLI + MCP 同会话三前门**（RFC-026）：窗口/CLI/MCP 驱动同一 Session + 同一 sidecar——与我们 Phase 14 MCP+launcher（M2AI-08）完全同构，独立验证方向正确；`API-SPEC-callable-render-service.md` + `CONTRACT-frontend-backend.md` 的 wire 契约纪律（字段名即 wire 变更）可借鉴进 MCP 面演进。
4. **导出色彩纪律**（RFC-018）：全程 ProPhoto working、每导出恰一次色域映射、软打样内建——与我们 linear Rec2020 + 13-2 色彩资产/软打样 proof 段同域，对照其细节校准。
5. **设置剪贴板**（RFC-027 settings-clipboard）：跨图设置组复制 UX，对照我们 HIST-05 pasteSet 三式互补。
6. **性能标杆**：45MP <1s / 重印 0.01s / 32MB 单二进制——M2-11 PERF 对标线。
7. **蒙版阶段归属学**：「影调蒙版属于负片之后、相纸之前的印放阶段，与场景置位不是同一功能」——若未来做印相域局部调整，阶段划分参考。
8. **工程文档文化**：29 篇 RFC + PRD + 前后端契约 + AGENTS.md「真耗过时间的坑」——方法学参考。

## 明确不借鉴 / 架构性不可达

- **81 波长光谱引擎本体**：GPLv3 C++/MSL 不复制；且我方 CIRAW 路线从解码后 RGB 起步——真光谱重放需传感器域数据，架构性不可达（同 demosaic 菜单逻辑）；RGB 域只能做染料近似，升维收益有限。
- 其 SwiftUI/AppKit 面非对标对象（我们 UI 对标 Alcedo）。

## 许可红线

代码只读参考（GPL 同 darktable/Alcedo 纪律，零复制）。**若未来引入其胶片/相纸配置或放大 LUT**：以独立 CC BY-SA 4.0 资产身份附归属与 CHANGELOG（不得并入 MIT 代码许可；SA 传染仅及资产本体）——与 M2GRADE-07 现行 spectral_film_lut（MIT）来源不同，不混用。
