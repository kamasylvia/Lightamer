---
status: complete
phase: 09-session-management
source: [09-01-SUMMARY.md, 09-02-SUMMARY.md, 09-03-SUMMARY.md, 09-04-SUMMARY.md, 09-05-SUMMARY.md]
started: 2026-09-26T01:30:00+08:00
updated: 2026-09-26T01:50:00+08:00
---

> 自动化腿已全钉（终轮 1133/6skip/0fail + 09-VALIDATION `validated`/`nyquist true`）。
> **收账口径（2026-09-26 01:50 用户授权）**：用户明确「没空手工验证 15 题，先全自动推进」
> → 测试 2-15 按用户授权 skip；test 1 保留 1 个 minor issue（G-09-1，环境误用暴露的
> 静默扫描 UX 缺陷，acknowledged defer）。Manual-Only 10 行已各自带 defer 目标。

## Current Test

[testing complete — 2026-09-26 01:50 用户授权关闭]

## Tests

### 1. 开卷走查（文件夹即会话）
expected: ⇧⌘O 选文件夹 → 侧栏三段 + 网格缩略图出现（渐显占位）+ recent 记录会话
result: issue
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
result: skipped
reason: "用户授权跳过人工验证（2026-09-26 01:50「没空手工验证 15 题，先全自动推进」）"

### 3. culling 双图对比
expected: culling 态两格并排（v1 cap 2），各格独立可换图，双图缩略图真实渲染（含编辑）
result: skipped
reason: "用户授权跳过人工验证（2026-09-26 01:50「没空手工验证 15 题，先全自动推进」）"

### 4. 复制粘贴调整（overwrite/merge）
expected: 单图 ⌘C 后选中多张粘贴：覆盖与合并两式均生效，⌘Z 恰好一步回退整次粘贴
result: skipped
reason: "用户授权跳过人工验证（2026-09-26 01:50「没空手工验证 15 题，先全自动推进」）"

### 5. before/after 入口走查
expected: 编辑一张图后，split/peek(\)/hold 三形态入口均可用（HUD/菜单 identifier 齐）
result: skipped
reason: "用户授权跳过人工验证（2026-09-26 01:50「没空手工验证 15 题，先全自动推进」）"

### 6. 10k 大集合滚动 hitch（Manual-Only #1，挂 Phase 15）
expected: 万张级集合滚动无 >50ms 帧间隙（signpost 口径）
result: skipped
reason: "用户授权跳过人工验证（2026-09-26 01:50「没空手工验证 15 题，先全自动推进」）"

### 7. 滚动手感/惯性（Manual-Only #2）
expected: grid ScrollView 滚动惯性自然、无卡顿观感
result: skipped
reason: "用户授权跳过人工验证（2026-09-26 01:50「没空手工验证 15 题，先全自动推进」）"

### 8. culling 布局手感（Manual-Only #3）
expected: 两格比例与标签观感舒适，分界比例无压迫感
result: skipped
reason: "用户授权跳过人工验证（2026-09-26 01:50「没空手工验证 15 题，先全自动推进」）"

### 9. 缩略图占位渐显观感（Manual-Only #4）
expected: 0.15s easeIn 渐显不突兀
result: skipped
reason: "用户授权跳过人工验证（2026-09-26 01:50「没空手工验证 15 题，先全自动推进」）"

### 10. 多选 ⌘/⇧ 手感（Manual-Only #5）
expected: ⌘ 点选增删、⇧ 范围选，手感符合 macOS 惯例
result: skipped
reason: "用户授权跳过人工验证（2026-09-26 01:50「没空手工验证 15 题，先全自动推进」）"

### 11. 双档缩略图混排观感（Manual-Only #6，挂 P3+）
expected: 有编辑/无编辑缩略图混排时色调无明显可辨差异（D10 残差，P3+ 校准后复核）
result: skipped
reason: "用户授权跳过人工验证（2026-09-26 01:50「没空手工验证 15 题，先全自动推进」）"

### 12. split 分界线拖动手感（Manual-Only #7）
expected: before/after split 视口内拖分界线顺滑，HUD slider 数据联动
result: skipped
reason: "用户授权跳过人工验证（2026-09-26 01:50「没空手工验证 15 题，先全自动推进」）"

### 13. hold 键响应延迟观感（Manual-Only #8）
expected: \ 按下即刻显原图、松开即刻回，无可见延迟
result: skipped
reason: "用户授权跳过人工验证（2026-09-26 01:50「没空手工验证 15 题，先全自动推进」）"

### 14. peek 步进渲染等待观感（Manual-Only #9）
expected: peek 逐帧步进首次 ~百 ms 等待可接受，缓存后零等待
result: skipped
reason: "用户授权跳过人工验证（2026-09-26 01:50「没空手工验证 15 题，先全自动推进」）"

### 15. 部分粘贴对话框真机走查（Manual-Only #10）
expected: ⌘⇧V 打开部分粘贴对话框，勾选子集 + 覆盖/合并 picker 正常，应用结果正确
result: skipped
reason: "用户授权跳过人工验证（2026-09-26 01:50「没空手工验证 15 题，先全自动推进」）"

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
passed: 0
issues: 1
pending: 0
skipped: 14

## Gaps

- gap_id: G-09-1
  truth: "开卷任一文件夹应快速建立会话并给出可见反馈"
  status: failed
  reason: "用户报告：侧栏无三段/网格无缩略图/recent 不更新——实选整卷根导致全卷扫描静默挂起"
  severity: minor
  test: 1
  artifacts: ["SessionCoordinator.openSession 编排", "SessionTreeScanner 分页扫描"]
  missing: ["大目录扫描进度/取消 UI", "超大目录选定确认提示"]
  disposition: acknowledged（用户授权推进；UX 改进项转 TODO 登记池，随任意 UI 轮）
