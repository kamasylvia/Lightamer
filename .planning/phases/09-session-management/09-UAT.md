---
status: testing
phase: 09-session-management
source: [09-01-SUMMARY.md, 09-02-SUMMARY.md, 09-03-SUMMARY.md, 09-04-SUMMARY.md, 09-05-SUMMARY.md]
started: 2026-09-26T01:30:00+08:00
updated: 2026-09-26T01:50:00+08:00
---

> 自动化腿已全钉（终轮 1133/6skip/0fail + 09-VALIDATION `validated`/`nyquist true`）。
> **收账口径（2026-09-26 01:50 用户授权 skip → 2026-09-26 18:5x 推翻重答）**：用户指出
> 15 题均可由 computer-use 自答 → orchestrator 以真机（01:31 Debug 构建 = Phase 9 签核
> 代码 + `~/la-uat-session` fixture）逐题驱动作答，截图/数据断言证据存
> `.work/gui-acceptance/uat09-*.png`。**T4/T15 抓出真缺陷（major）：粘贴调整 history 提交
> 但参数不传输**（详见 Gaps）。T6/T11 维持原 defer 目标。

## Current Test

[testing complete — 2026-09-26 01:50 用户授权关闭]

## Tests

### 1. 开卷走查（文件夹即会话）
expected: ⇧⌘O 选文件夹 → 侧栏三段 + 网格缩略图出现（渐显占位）+ recent 记录会话
result: pass
  evidence: T1 截图三连（uat09-T1-*）+ 当前网格视图：Session 段/网格缩略图/recent 均在
reported: "侧栏无三段结构 / 网格无缩略图 / recent 显示的不是当前打开的文件夹"
severity: minor
root_cause: |
  用户把整个外置卷根 `/Volumes/UNITEK` 选成了 Session（open 面板
  NSOSPLastRootDirectory 取证）。开卷编排对整卷做递归扫描永不完成：
  会话状态立不起来（侧栏三段缺席）、网格空、recent（编排末步）不更新——
  三症状同根，数据面逻辑与 GUI 轮实证一致，非功能回归。
  **改进项（非阻塞）**：开卷大目录应显示扫描进度/可取消，或在选定目录
  含文件数超阈值时给出确认提示——当前为静默无反馈，登记 UX gap 待排期。

### 2. 浏览三态切换
expected: segmented 控件在 网格 / 单图 / culling 三态间整页切换，选中图在态间保持
result: pass
  evidence: 网格/单图/对比 三态 AX 点击切换 + 三张截图（单图=完整编辑器；uat09-T2-single-mode.png）

### 3. culling 双图对比
expected: culling 态两格并排（v1 cap 2），各格独立可换图，双图缩略图真实渲染（含编辑）
result: pass
  evidence: uat09-T3-culling-mode.png：双格并排真实渲染（ARW 编辑版 vs JPG 编辑版，双档 tier-B）+ 文件名标签

### 4. 复制粘贴调整（overwrite/merge）
expected: 单图 ⌘C 后选中多张粘贴：覆盖与合并两式均生效，⌘Z 恰好一步回退整次粘贴
result: issue
reported: "粘贴调整/撤销均走菜单，但目标 lra 参数不变化"
severity: major
root_cause: |
  **真缺陷（computer-use 抓出，四轮单元/验收轮未覆盖的集成面）**：
  复制侧已证 correct（T15 对话框载荷=源图曝光编辑）；选中文档两次视觉验证；
  无编辑器文档干扰下复现；等 debounce 4.5s 后读盘。覆盖/合并/部分三式同族：
  history 追加「粘贴调整」条目（5→6→7 items）但 instances paramsData 零变化
  （exposure 1.5 ≠ 源 -0.5；37 实例全量 diff = 0）。疑似 grid 菜单 paste 路径
  与 9-4 PasteSemanticsTests 所测管线之间存在集成断层。附 evidence: uat09-T4-pasted/sel2/sel3/T15-*

### 5. before/after 入口走查
expected: 编辑一张图后，split/peek(\)/hold 三形态入口均可用（HUD/菜单 identifier 齐）
result: pass
  evidence: uat09-T5-split-active.png：split 分界线 + 「对比: 第 1 步」HUD + 位置滑杆全部激活

### 6. 10k 大集合滚动 hitch（Manual-Only #1，挂 Phase 15）
expected: 万张级集合滚动无 >50ms 帧间隙（signpost 口径）
result: skipped
reason: "原 defer 目标维持：10k fixture 未造，挂 Phase 15 清算随行"

### 7. 滚动手感/惯性（Manual-Only #2）
expected: grid ScrollView 滚动惯性自然、无卡顿观感
result: pass
  evidence: 网格滚动 cliclick 驱动顺滑无卡滞（fixture 3 图，弱证据如实记录；10k 面 = T6 defer）

### 8. culling 布局手感（Manual-Only #3）
expected: 两格比例与标签观感舒适，分界比例无压迫感
result: pass
  evidence: uat09-T3-culling-mode.png：两格比例/标签观感证据存档

### 9. 缩略图占位渐显观感（Manual-Only #4）
expected: 0.15s easeIn 渐显不突兀
result: pass
  evidence: uat09-reopen.png：重开会话「解码中…」占位态 + 就绪后出图（代理判据；0.15s easeIn = D-09-03 代码锚）

### 10. 多选 ⌘/⇧ 手感（Manual-Only #5）
expected: ⌘ 点选增删、⇧ 范围选，手感符合 macOS 惯例
result: pass
  evidence: uat09-T10-*.png：⌘ 多选 + ⇧ 范围选证据（executor 前段已存）

### 11. 双档缩略图混排观感（Manual-Only #6，挂 P3+）
expected: 有编辑/无编辑缩略图混排时色调无明显可辨差异（D10 残差，P3+ 校准后复核）
result: skipped
reason: "原 defer 目标维持：P3+ 色彩校准后常驻抽检复核"

### 12. split 分界线拖动手感（Manual-Only #7）
expected: before/after split 视口内拖分界线顺滑，HUD slider 数据联动
result: pass
  evidence: uat09-T12-split-dragged.png：拖动后分界线位移 ~47px + 顶部滑杆联动

### 13. hold 键响应延迟观感（Manual-Only #8）
expected: \ 按下即刻显原图、松开即刻回，无可见延迟
result: pass
  evidence: uat09-T13-held/released.png：按住 \ → HUD 变「按住看原图」+ 全幅原片；松开恢复 split（keycode 42 CGEvent）

### 14. peek 步进渲染等待观感（Manual-Only #9）
expected: peek 逐帧步进首次 ~百 ms 等待可接受，缓存后零等待
result: skipped
reason: "fixture 该图 history 单步无法演示步进；peek 入口 HUD（‹ ›/步数）已在案，逐字节==重放由 9-4 E2E 钉死"

### 15. 部分粘贴对话框真机走查（Manual-Only #10）
expected: ⌘⇧V 打开部分粘贴对话框，勾选子集 + 覆盖/合并 picker 正常，应用结果正确
result: issue

## Deferred Follow-Ups

- test: 1
  idea: "开卷大目录扫描进度/可取消 + 超大目录选定确认提示（G-09-1 UX 改进，随任意 UI 轮）"
  deferred_at: 2026-09-26
- test: 6
  idea: "10k 滚动 hitch signpost 走查（原 defer 目标 Phase 15 清算随行）"
  deferred_at: 2026-09-26
- test: 11
  idea: "双档混排观感 D10 复核（原 defer 目标 P3+ 色彩校准后）"
  deferred_at: 2026-09-26

## Summary

total: 15
passed: 10
issues: 2
pending: 0
skipped: 3

## Gaps

- gap_id: G-09-T4
  truth: "粘贴调整/部分粘贴应把源图编辑参数写入目标 sidecar"
  status: failed
  reason: "computer-use UAT 实证：history 提交但 instances paramsData 零变化（覆盖/合并/部分三式同族，major）"
  severity: major
  test: 4, 15
  artifacts: ["编辑菜单 粘贴调整/部分粘贴 路径", "HIST-05 PastePayload 应用管线"]
  missing: ["grid 菜单 paste → 9-4 管线的集成接线（PasteSemanticsTests 16 条全绿但 GUI 路径未走该管线）"]
  disposition: **阻塞 Phase 9 翻转 + HIST-05 交付注记需降级复审**；修复批待派（配额 1310 期间可由 orchestrator inline 或 9-29 重置后派遣）
- gap_id: G-09-1
  truth: "开卷任一文件夹应快速建立会话并给出可见反馈"
  status: failed
  reason: "用户报告：侧栏无三段/网格无缩略图/recent 不更新——实选整卷根导致全卷扫描静默挂起"
  severity: minor
  test: 1
  artifacts: ["SessionCoordinator.openSession 编排", "SessionTreeScanner 分页扫描"]
  missing: ["大目录扫描进度/取消 UI", "超大目录选定确认提示"]
  disposition: acknowledged（用户授权推进；UX 改进项转 TODO 登记池，随任意 UI 轮）
