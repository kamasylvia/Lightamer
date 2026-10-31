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

---

## 增量节（2026-10-25 M9 charter 输入批；+518，`git show origin/main`）

> 增量主体三层：①**黑白胶片族产品化**（顶部 ~20 commits，M9 光谱延展站主料）；
> ②Windows/Linux 移植 churn（~300 commits：Vulkan 后端 + LibRaw + Tauri host + wine CI
> + DCP——与我方无关）；③中期功能批（film edge/date back、半幅对、全景幅面、DI Cineon、
> scene latitude、库记忆池）。正本判定 = `M9-CHARTER-INPUT.md` §2.2/§3/§4。

### 黑白族（M9 站 2 主料）

- **`engine/resources_product/`** = SpektraLab 自有产品数据（NOTICE 明示非 spektrafilm
  衍生）：`kodak_tri_x_400 / kodak_tmax_100 / fujifilm_neopan_acros_100_ii /
  ilford_hp5_plus_400` 四 profile（81 波长谱敏感度 + 特性曲线，厂商 PDF 矢量路径或
  600dpi 栅格描点数字化；假设逐项标注于 metadata.tags）+ `ilford_multigrade_iv_rc`
  相纸（三乳剂变反差）+ `paper_grades.json`（滤镜 00-5 → m/y_filter_neutral +
  print_exposure；Tri-X 拟合、四片灰位同密度 `bw_checks.py` 验证）。
  `channel_model: "bw"` = 单乳剂写三通道（银密度 1/3 每通道谱平坦假设）。
- **granularity 标定**（`d610ac9`）：per-film `ownGrain`——滑杆 1 = 厂商发表 RMS
  granularity（wire：Tri-X 1.70 / HP5 1.49 / T-Max 0.74 / Acros 0.64）；引擎侧标定
  实测（6µm 像素、net density 1.0、48µm 孔径）：Tri-X 17 / T-Max 8 / Acros 7（Microfine
  下限）/ HP5 16；wire 上限 2。**owner 裁定（2026-10-07）：胶片颗粒是 per-film 量而非
  引擎变更**——grain 算子不动，标定乘子挂 profile。
- **camera_filter**（`6d46e08`，`camera_filters.hpp`）：8 Wratten（w8/w11/w12/w15/w21/
  w25/w47/w58）各 81 点 5nm 透射谱（Kodak B-3 公开转录，Usenet 1992）；**SHOOT 域**：
  透射谱乘胶片感光度谱、在 tc 上采样表之前；edge print/fog/date back 读未滤光谱；
  F-4017 滤镜因子对照（7 中 6 ≤0.21 档，No.58 偏 0.67 档）。R8 覆盖表登记在
  PORT_COVERAGE（`5b0a995`）。

### 排除/挂起（M9-CHARTER-INPUT §3/§4）

- **半幅对 + 全景幅面**（XPan/6x12/6x17 + 一卷两框各自 Scene Placement/date/print）：
  绑定胶片画布（strip + 底片框 + overscan）产品形态 → OQ-M9-5 不入；输出裁切比例
  预设可 trivial 并站 4。
- **film edge / date back**（每 stock 边缘排版 + DX 条 + 片孔 + overscan + 日期后背，
  RFC-031/032）：强绑胶片画布 + 与 yiyin 印框面重叠度低 → OQ-M9-9 不入。
- **halation 开关 + highlight boost**（`8c0f555`）：M8 D-M8-4 空间族挂账项的上游参照
  （grain/halation/diffusion/glare 独立站的形态证据）。
- **DI Digital Intermediate**（Cineon log 导出/Tone Mask 撤回）、scene latitude/contrast
  mask/pre-flash（RFC-023/024）：光谱域上游先例库既有登记，无新 M9 输入。
- **spklib-host 2.0**（`f4df99c` 二进制 helper + API-SPEC，MIT）：外围库分发件，注记。
- **许可注记**：resources_product 数据文件整体在 GPL-3.0 仓内，NOTICE 自声明来源独立
  （厂商出版物数字化 = 事实数据）；M9 站 2 **建议自建数据**（同法数字化，NOTICE 干净），
  复制决策留 charter。

## 增量登记（2026-10-31 晚复查；+22 新窗口）

- **sidecar 热重载 + 自保存回声抑制**（PR#32 + `54c6bb9`「不采纳窗口自身保存为外部编辑」）：外部编辑热重载 + **自保存回声不误判为外部变更**——我方 SidecarStore 2s debounce 单写者 + adopt-external 路径需核对此回声抑制语义（登记核对项，非缺陷申报）。
- **original after relaunch 修复**（`9a05ba0`）：重开恢复原片 + 直方图跟随——观感修复参考。
- 其余 = CI 分发面（Linux/Windows only）。无 MCP/Agent 演进（RFC-026 后持续休眠）。
