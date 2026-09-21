# 04-08 SUMMARY — GUI-5/6/7/8 修复 + 交互复验闭环

- phase: 4, plan: 04-08, date: 2026-09-21, executor: omp
- requirements: IOP-GEO-01, IOP-GEO-02, IOP-GEO-04（UI 交付面缺口）
- tests: **432 tests / 0 fail / 3 skip**（基线 426 → +6：flip +2、toast +1、auto-enable +1、row +3、toggle-off +1；复验后终轮实测 TEST SUCCEEDED）
- commits: 5（T1 flip / T2 ashift toast / T3 auto-enable / T4 row circle / T5 statusbar+evidence）

## Tasks

| Task | 改动 | 验收 |
|---|---|---|
| T1 GUI-6 flip 面板 | `FlipPanelView`（EXIF auto + 8 态 Picker，离散 one-commit）+ 注册 + `module_flip` 标签 + catalog 14 keys + PanelWiring +2 | ✅ dispatch + select 恰 1 commit；交互复验翻转+可逆（下） |
| T2 GUI-8 自动按钮 | 诊断：接线完好，nil 路径只写面板 notice（D-08-T2-1）；`presentToast` 三层转发 + 全路径 toast（nil/epsilon 无 commit，成功/reset commit）+ catalog 4 keys + seam 测试 | ✅ 三按钮各有全局可见效果（T5 旧构建先证面板层、新构建证全局层） |
| T3 GUI-7 自动启用 | `commitContinuousEdit(autoEnable:)` commit 时翻转（D-08-T3-1），live 不翻；toggle-OFF 旁路（D-08-T3-2） | ✅ live-disabled/commit-enabled/exposure 无回归三断言 |
| T4 GUI-5 圆圈 | `InspectorRowModel/View`：形状=enabled、颜色=selected；圆圈独立 toggle（`history_toggle` + autoEnable=false）+ catalog 4 keys + 行测试 +3 | ✅ filled/dashed 绑定 + toggle on/off 各 1 commit |
| T5 交互复验 | PLAYBOOK §3 + GUI-5..8 量化；状态栏迁窗口底（D-08-T2-2）；FINDINGS 闭环节 + 12 截图；终轮 432 绿 | ✅ 下见 |

## T5 复验数字（DSC00012.ARW，AX + 像素量化）

- GUI-6：9 项 Picker；水平翻转左半列均值 31.2→22.7、col4 24.7→33.0，T/B 29.1/25.2 不变；sidecar 恰 1 条；选回逐像素差 0.0。
- GUI-7：soften 混合 50→80（读回 80.0），meanRGB [26.12,30.25,30.62]→[26.31,31.56,31.82]，Δ1.574；toggle 关→开；history 恰 1 条 enabled=true。
- GUI-5：奇位 toggle（13×13，开/关）/偶位 select（412×27）；17/37 初值关与种子一致；soften 启用后翻开。
- GUI-8：自动水平→「未检测到地平线——参数未改动。」/自动检测→「未检测到矩形—参数未改动。」/重置→「自动检测无需校正——参数未改动。」（全局状态栏，history 0 条）；Vision 在 DSC00012 双 nil（夜景无强全局边缘/闭合矩形；合成 4/4 仍绿）。
- 回归：rotation 3° 恰 1 commit；⌘Z position 1→0（items 保留，指针语义）；rot3/undo 差 0.0（760 档 <0.5 LSB）；990pt 布局 20.2/57.4/22.4（≥50% ✓）。
- BLOCKED 不变：CGEvent 拖拽（需输入监控）；AX set 仅 live 不 commit（D-H1 既有语义）。

## 验收标准（plan 逐条）

- [x] GUI-6 flip 面板可操作（渲染翻转 + 1 commit + catalog + a11y）
- [x] GUI-8 三按钮每次点击有可观察效果（值变化 or toast）
- [x] GUI-7 disabled 模块编辑自动启用（PanelWiringTests 钉住）
- [x] GUI-5 圆圈态 = enabled 真状态 + AX 可达
- [x] 交互复验逐项量化数字入 FINDINGS.md
- [x] 全套 LightamerTests 绿；无 /tmp 产物；无 app 残留（.lra 已删、app 已 quit）

## 决策/教训

- 决策：`04-08-DECISIONS.md`（D-08-T1-1 九态 Picker / D-08-T2-1 观测盲区 / D-08-T2-2 状态栏迁移 / D-08-T3-1 commit 翻转 / D-08-T3-2 toggle-OFF 旁路 / D-08-T4-1 圆圈语义）。
- 教训候选（orchestrator 裁决是否入 LESSONS）：①状态栏放编辑列内会被视口量化裁掉——全局 toast 条放窗口底通栏；②xcstrings 手工增键必须落「尾块 `}, version` 之前」且 JSON 校验（T1 曾坏 catalog，两次返工）；③AX set 仅 live 的 D-H1 语义要在复验前先对齐口径（免误判矩阵 c）。
- 残余：滑块 AXPosition 全 None（功能性 AX 可用，平台侧限制）；UITests 腿仍 L011 挂账（`Timed out while enabling automation mode`——本轮 L019a 授权后单测腿畅通）。

## 修复轮 F1–F6（2026-09-21，验收 FAIL 回注）

- tests: **435 tests / 0 fail / 3 skip**（基线 432 → +3：undo/redo
  render+position、AX toggle 语义、perspective guard；终轮实测 TEST SUCCEEDED）。
- commits: 3（F1/F4 布局+guard+测试 / F2/F3 撤销+AX / F3 根因 applyDiscrete
  捕获修复；F5/F6 文档与证据并入第 3 批后另提交）。

| 项 | 改动 | 实证 |
|---|---|---|
| F1 GUI-4 真修复 | inspector ideal 280→240、min 220→200；编辑列硬 min 495pt（990pt 窗 50% 红线） | 干净启动 990×695：frames 200/589/200 = 20.2%/59.5%/20.3% ✓（`fixf1-990-fixed.png`） |
| F2 撤销入口 (GUI-9) | CommandGroup 接 coordinator undo/redo；enabled 跟随 canUndo/canRedo；`testUndoRedoEntryRestoresRenderAndPosition` | ⌘Z ×2：toggles 回关、position 1→−1、视口差 0.0；redo ×1 回开（`fixf2-undo-fixed.png`） |
| F3 AX press 通路 | 根因：行临时 session 的 `Task { [weak self] }` 空捕 → 改捕 coordinator；toggle 补 isButton+显式 default action；`testRowToggleAXPressSemantics` | AXPress/click 翻转 soften/highpass（history 恰 1 条/项、渲染 Δ1.293） |
| F4 perspective guard | `fitIsNoChange`（1e-4 四分量）+ `testPerspectiveFitNoChangeGuard` | 单测钉住；DSC00012 双 nil 路径不变 |
| F5 文档修正 | FINDINGS 修复轮节（T5 两处失实更正 + GUI-9 登记闭环）；04-VALIDATION:80 GUI-7 注记更新；DECISIONS D-08-F1..F4 | 本文件节 |
| F6 交互复验 | F1/F2/F3 实测 + GUI-6/7/8 回归（代码路径未动，全套绿）+ 4 截图 | 上表；`.lra` 已删、app 已 quit |

- 决策：`04-08-DECISIONS.md` D-08-F1（min 约束 vs delegate/autosave 备选）/
  D-08-F2（直调 coordinator）/ D-08-F3（临时 session 空捕）/ D-08-F4（epsilon 对齐）。
- 教训候选：① `Task { [weak self] }` 在临时对象方法内 = 静默 no-op（本轮 F3；
  面板 `let edit` 持有掩盖了它）；② T5 百分比正确但绝对值是 Retina 物理像素
  （2204pt 误读 —— 量化口径要注明 pt vs px）；③ 57.4% 是 resize 记忆值，
  干净启动才是布局验收口径（L021 增补）。
