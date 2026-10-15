# V2M-02 DECISIONS（波 2 清算批执行裁定，2026-10-16 夜间批）

> 夜间全自动授权（先例 D-07-3-T5-1；晨审可推翻）。对象 = 执行链
> `2ba1d1fe..de786663`（5 commits + T6 收口 docs）。裁决正本 =
> `V2M-CONTEXT.md` OQ-VM-1..5 全 A。

## D-V2M2-1 V17 门实现的三处执行批裁量

1. **spec 正则的 `%@` 字符类**：首跑分诊抓到实现 bug——`%[a-zA-Z]+` 不覆盖
   `%@`（`@` 非字母），`('%@',)` 被解析成空序列 → 每个 String-arg 键假
   MISMATCH（`edr_headroom_label` / `settings_lcr_size_mb` 两例幻红）。修复 =
   `%(?:@|[a-zA-Z]+)`，两例转绿。教训入注记：specifier 解析的字符类必须含
   `@` 显式位。
2. **Text 族多行形态重derive（plan 预扫 9 处 vs RESEARCH 记 11）**：执行批
   扫描 = 单行 9 处（8 键）+ `Text(` 行尾续行形（regex 实现；活体树内该形
   零命中——现存多行 `Text(` 皆为三目/verbatim 域）。RESEARCH 的 11 含
   planner 当时的树态差异（波 1 修后），以 V17 首跑 transcript 为准（38
   interp 键 = 30 localized + 8 text）。
3. **EXEMPT 供给面实测分布**：30/38 site EXEMPT（成员链/闭包参数/未注解
   let 为主）——**禁误报纪律的代价面如实登记**：门只对 8 键 site 全 derivable
   断 MISMATCH（现树 0）；D-5 键 `toast_hdr_merge_done` 绿例亲证（函数参数 +
   `Int(…rounded())` 包装形）。C-3 预言命中：McpLauncher 三键 EXEMPT 非绿，
   断言 5 层 PRESENT 过——与 CHECKER「不违 AC」口径一致。

## D-V2M2-2 T2 走查批「通道受阻收兵」裁定（本批最重裁定）

走查批开工即撞三条独立通道阻断，按「不硬造判定」纪律收兵：

- **D-6（新缺陷，error 级候选，登记不修）**：进程重启后重开项目 →
  文件>进入编辑器 → filmstrip 在（AX 可寻址）但视口呈 legacy Session 空态卡
  / 全黑 + 右栏「未选择图像」；filmstrip 点击 24 步循环全部零响应
  （AXPress err=0 无效果）；主线程 spin（CPU 99.9%，sample = SwiftUI
  AttributeGraph update 循环，全框架帧零 Lightamer 帧——m6-closeout D-1
  layout churn 同族）。触发路径 = **重开项目**（波 1 同会话新建项目路径
  walk-8-editor.png 健康）。证据 = t2-spin.sample.txt + diag-*.png +
  d3_cycle.py（v2m 证据域）。
- **D-7 注记**：波 1 批外疑点①（导入停滞）同面复现——同会话新建项目
  V2M02 → Import Folder → CPU ~62% churn、images 20s 后仍 0 行。
- **D-8 注记**：legacy face 会话建立不可达（文件>打开… 行 AXSelected+OK
  rc=0 后无会话；`open -a` 文档语义同；Import Folder 菜单无面板）。
- **D-4 返工预案不触发的裁定**：E2-1 触发条件 =「走查批复验仍见 0 张」
  ——前提是对话框实际呈现。本批通道不可达 ≠ 复验见 0；按「不硬造判定」
  记 **Blocked-Channel 保持**，返工裁定上报 orchestrator（波 1 代码面证据
  链不变：`.sheet(item:)` payload + Sessions 284/9/0 + 本批 T1 V17 绿例）。
- **通道本身健康**：menu AX 通道（AXMenu 下钻 + 重试 AXPress）修复了波 1
  「menu-item 被吞」堵点——项目重开、New Project save sheet、Import Folder
  面板全部机检可达；失败面全在 app 内容面（编辑器 spin / 导入 churn /
  legacy 会话腿）。harness 与证据已拷 `.work/gui-acceptance/v2m/`。
- 资源处置：spin 实例两度按 AGENTS 处置线杀（本会话自起实例，§8.2 静默）。

## D-V2M2-3 T3 余量盘点 = 余量非零 → 修复臂（双残差实修）

plan action 1 的销账臂不成立：D-13 主修（`b49215bb`）只盖 debounce 窗内
切换，E5 两残差原样 open（原文对照在案）。修复形态三件（D-V2M2 §AGENTS 节
详）：eager 释放双点（select 异值 + loadedImageURL onChange）、`armedImageURL`
函数头捕获、segment 腿装载门。**测试时序裁量**：mid-flight 法以
decodeWidth/Height 6000² 放宽 bake await 窗——16×16 小 plane bake <50ms，
切换会输掉竞态（首跑 5红/4红 的根因，含一次未重建 test bundle 的假红）。
裁量为测试专用构造，零产线注入缝。

## D-V2M2-4 T4 余量盘点 = 主债形态已消 → 防御脚本入库

当前依赖图下新 Release 构建**无 PackageFrameworks 目录**：WebP 静态内联进
LightamerCore（nm 零 webp 未定义符号），直启探针零修复 PASS（rc=0 + 主窗）。
perf.md 事故 4 的债形态（WebP PackageProduct 动态 framework 未 embed）是
SPM/Tuist 链接代际的函数——脚本以防御形态入库（回摆自愈 + make-dmg 先行
则分发自足），零产线 diff。`Scripts/release/make-dmg.sh` 本身的 embed 缺口
（不跑本脚本则 DMG 带病）记翻账建议。

## D-V2M2-5 T5 捕获面裁量与文件落位

1. **捕获面 = REQUIREMENTS :401 清单精确**：格式/质量/位深/sizing/
   metadataOn/embedICC/命名模板；`collisionPolicy`（M-5 钉死）与
   `gainMapHDR`（:401 无此项）结构性不入捕获面——`ExportPresetPanelFace`
   值面不带两字段，编译期钉死「预设静默开立跨会话记忆」与「预设拉起
   gain map」两条路。plan files_modified 列 ExportState.swift——实际落
   **独立文件 `ExportPresetStore.swift`**（NamingTemplateStore 同级先例；
   ExportState 零 diff）——plan 侧清单偏差，N-B 同族注记。
2. **键族复用裁量**：alert 命名框的 OK/Cancel 复用在册 `alert_ok`/
   `alert_cancel`——新增键族收敛为 7 键。
3. **内置默认三预设**（JPEG 90 / TIFF 16-bit / WebP 85）代码内置不入库
   （NamingTemplateStore 三内置先例）；命名模板悬挂回落 =
   `builtIns[0].pattern`（`{source}`）。
4. **测试时序**：无（纯函数域 + isolated defaults suite，无 Metal 依赖）。

## D-V2M2-6 条件任务（T6 步 1）= 零动作

波 1 T5（D-5）已清（`8133726e` 调用点 Int 化 + 本批 T1 V17 首跑绿例
亲证）——条件并入步零动作。

## 偏差清单（对 plan 文本）

| # | 偏差 | 定级 |
|---|---|---|
| 1 | T5 实触文件 `ExportPresetStore.swift` 新文件替代 plan files_modified 的 ExportState.swift 行（ExportState 零 diff） | plan 侧不全（N-B 同族），本节申报 |
| 2 | T5 测试 +4 落 plan 带上界（+2..4）；T3 +2 落带内；ΔN₂ = +6 = 带上界 | 如实记账 |
| 3 | T2 可达行集缩水为零（通道受阻，非供件缺席单因） | plan 风险节「可达行缩水合法」的通道变体，MANIFEST 逐行终态 |
| 4 | T2 harness 修复了波 1 的 menu-item 堵点（改良 AXMenu 下钻）——波 1 MANIFEST 的「项目重开 flaky」形态不复现 | 正向偏差，证据在 MANIFEST |
