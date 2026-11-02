# 首启界面改为图库优先（omp 执行）

你是「首启图库优先」UX 改造执行者。工作目录 /Volumes/UNITEK/Documents/Development/Lightamer。全程中文，commit 英文。当前 HEAD = 最新，全套基线见最近 --all 终值。

## 用户指令

首启界面不满意——用户希望和 darktable 一样，一打开就看到**图库布局**（空态无图 + 导入入口），而非当前的项目 Welcome sheet（新建项目/打开项目/暂不使用项目）。

## 现状架构（file:line）

- 启动路由：`ContentView.swift:201` gate-false face = `ProjectWorkspaceFace` 容器（M2-2-4 KD-3/OQ-1 项目优先范式）
- Welcome sheet：`ProjectWorkspaceFace` 内 auto-present `LibraryWelcomeView`（无项目时）
- 图库视图：`WorkspaceHostView.swift:692` 有完整图库面（P2 seams），但当前在无项目时不可达
- `LibraryLegacyGate`：`LIGHTAMER_LEGACY_LIBRARY=1` QA 回切（本批不动此门）

## 改造目标

首启（无项目/无 recents）→ 直接呈现图库视图（空态 + File > Import 入口），**不走项目 Welcome sheet**。用户可从图库直接导入照片，不强制创建项目。已有项目打开时走正常编辑器路由。

## 任务

1. **改启动路由**：ContentView gate-false face 不再默认走 ProjectWorkspaceFace → 直接挂 WorkspaceHostView 的图库面（空态）。
2. **图库空态面**：无图时显示空态设计（引导文案 + 导入按钮/拖放提示）——非白屏。
3. **项目流兼容**：已有项目可从 File > Open 打开（现有功能不动）；新建项目入口保留（File > New）但不再是首启强制路径。
4. **测试**：受影响测试修绿 + 新增首启路由测试。

## 纪律
封存面 17 件零 diff；zh-audit PASS；全套 --all 绿；域内自审层照常。G4 透明越门先例。

## 汇报
改造 diff + 测试结果 + 截图 + commits。
