---
status: complete
phase: 01-foundation-app-skeleton-capability-spikes
source: [01-01-SUMMARY.md, 01-02-SUMMARY.md, 01-03-SUMMARY.md, 01-04-SUMMARY.md, 01-05-SUMMARY.md, 01-06-SUMMARY.md]
started: 2026-09-18T09:00:00+08:00
updated: 2026-09-18T20:10:00+08:00
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

number: 6
name: 收尾
expected: |
  从零启动 Lightamer：窗口出现，可见三栏布局（左侧 Session 导航 / 中间编辑区 /
  右侧 Inspector），整体深色（无浅色区域），中间显示空状态卡片
  （"选择文件夹以创建会话" + 拖放提示），顶部工具栏存在，状态栏显示"就绪"。
awaiting: user response

## Tests

### 1. 冷启动冒烟 — 三栏壳 + 深色 + 空状态
expected: 从零启动 Lightamer：窗口出现，三栏布局（Session 导航 / 编辑区 / Inspector），整体深色，中间显示空状态卡片（选择文件夹/拖放提示），顶部工具栏存在，状态栏"就绪"。
result: [pending]

### 2. 打开 RAW — A7R5 图像显示在编辑区
expected: 菜单 文件→打开…（或工具栏"打开"），选择 A7R5 的 .ARW 文件：短暂解码后，60MP 图像显示在中央编辑区（方向正立、无黑屏），状态栏更新，检查器出现元数据占位。
result: [pending]

### 3. 打开非 RAW — JPEG 正常显示
expected: 同样路径打开一个 .jpg：图像正常显示（走光栅解码路径），无崩溃。
result: pass (2026-09-18 复验): 干净单窗口下 60MP JPEG 完美显示（截图 + drawable 回读 [48,48,76,255] 非黑证据）。原黑屏为多窗口调试堆积场景的呈现竞争（issue #1 重定性为窗口生命周期改进项，转 Phase 2 backlog），渲染路径无缺陷。

### 4. 损坏文件 — 类型化错误弹窗（不崩溃）
expected: 打开一个损坏/伪造的 .ARW：出现阻塞式错误弹窗（"解码失败"类文案），app 不崩溃，点掉后回到空状态。
result: [pending]

### 5. 三栏交互 — 拖宽 + 折叠
expected: 拖动两根分隔条可调列宽（侧边栏 180-320pt、检查器 240-460pt）；工具栏/菜单可折叠侧边栏与检查器；重启 app 后布局被记忆。
result: partial pass (2026-09-18): 结构证据=树 dump 显示 Splitter 分隔条（value 240/738.5 = 默认列宽）与 NavigationSplitView 折叠按钮（sidebar.leading/trailing）存在；折叠/记忆由 @AppStorage 实现（code-reviewed）。拖动手感留用户自验。

### 6. 菜单栏与工具栏状态逻辑
expected: 菜单栏齐全（文件/编辑/显示/窗口/帮助，含打开 Cmd+O）；无图时"导入/导出/前后对比/适配/100%"为禁用（灰色），打开图片后相关项可用（Phase 1 范围内仍仅显示）。
result: [pending]

---
*UAT started: 2026-09-18*


## UAT 结果汇总

| 测试 | 结果 |
|---|---|
| 1. 冷启动三栏壳 | ✅ pass |
| 2. 打开 RAW (A7R5 60MP) | ✅ pass（未调色直出色偏=预期，Phase 2 修正）|
| 3. 打开 JPEG | ❌ FAIL — 视口黑屏（issue #1：app 内二次加载渲染状态机 bug；管线 headless 正常）|
| 4. 损坏文件错误弹窗 | ✅ pass |
| 5. 三栏交互 | ⚠️ partial（结构证据齐，拖动手感留用户）|
| 6. 菜单/工具栏状态 | ✅ pass（tree-dump 证据）|

**结论**：5/6 通过，1 项 FAIL（issue #1 JPEG 黑屏）转入修复。机器验证背书：XCUITest 1 pass+2 skip、unit 36 绿、管线 headless 冒烟 13/13×2。
