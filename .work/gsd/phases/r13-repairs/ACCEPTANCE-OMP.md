# R13（R4）修复批 omp 终审（dual_acceptance 终审眼，computer-use 实机）

> 2026-10-24。对象 = `d2bcaf06`（流一 Link os_log + 双模回归，fixes #2）/ `b0690452`（流二 F-2 全族 46 处显式形，fixes #3）/ `acd3074b`（docs）/ `93a97ed6`（SOP 硬化）/ `e4efefc4`（zcode 综合验收）；HEAD 实测 = `e4efefc4`。
> zcode 综合验收已过：PASS / 0B+0M+2m+4obs。本轮为独占终审眼 computer-use 实机抽验。
> 纪律执行：guard `--wait` 起跑一过（heavy=0 free=75%）+ 起跑前 ps 验证 GUI 清零 + 只杀自出 PID（自出 = 35238，osascript quit 正常退出）+ 主树 tracked 零 diff + app 用完已退出。
> 证据 = `.work/gui-acceptance/r13/omp/`（8 截图）+ `/tmp/omp-r13/`（harness/AX 脚本/log，即弃）。

## 结论

**PASS / 0 blocking + 0 major + 0 minor + 2 obs。**双流交付物实机成立：gamma 读出 zh 实渲染、mcp 真 bug 同形渲染实锤、LCR 页转换键实渲染、编辑器主链加载渲染正常、静置 CPU ~0%。无新增 blocking/major/minor；zcode 的 2m+4obs 维持（本轮不重复登记）。

## 一、抽验 a：gamma RAW 读出（E 族形渲染抽验）——过

- 路径：自造 AdobeRGB1998-tagged TIFF（`curv` count=1 gamma=563/256=2.199 → 格式化期望 `2.20`）→ 新建项目 → ⌘⇧I Copy 导入 2/2 行 → ⌘E 进编辑器 → 双击 filmstrip.row.1 加载 → 点击 RAW 解码 tab（`editor.stack.tab.*` AX 不可见，坐标点击，见 obs-1）。
- **AX 实读**：`editor.rawdecode.raster.transfer` = **`伽马 2.20`**（`rawdecode_raster_trc_gamma_value` zh 值 `伽马 %@` + `%.2f`，数学核对 563/256=2.199→2.20 精确）；profile = `Adobe RGB (1998)` / origin = `内嵌 ICC` / peak = `100 nits`，四行全中文无裸键。
- 同形交叉：zh.lproj 编译表直读 `String(format:)` 同形渲染 `伽马 2.20`，与屏上逐字一致。
- 证据：`omp-a-gamma-readout.png`（读出区裁切）/ `omp-a-gamma-full.png`（全屏）。

## 二、抽验 b：mcp_launcher 启动失败提示（真 bug 修复验证）——过（通道降级如实申报）

- **GUI 可达链亲通**：Edit → `MCP Agent 启动器…` → 面板（`mcp.launcher.start/stop/follow/copy` 四 AX 全在）→ 空模板启动 = `尚未配置 agent 命令模板——请先在设置中填写。` → 写模板后启动 = `MCP 服务器未运行——请先在设置中启用（agent 将无从连接）。` → Settings MCP 页勾 `settings.mcp.enable`（endpoint json 落盘 port 65376）→ 启动 `echo hello-agent` → 日志 `hello-agent` + `任务完成——本次会话无写回`。**启动面三态（缺模板/无服务/正常跑）屏上全绿，无裸键。**
- **真 bug 构造不可达（源码级实锤）**：`launchFailed` 仅 `Process.run()` throw 触发（`shellPath` 生产恒 `/bin/zsh`，可注入 shellPath 只暴露给测试）；zsh `-c` 恒成功——命令错/端口占用等只走 exit code（`mcp_launcher_exit_code` 键），**永不进 `launchFailed` 臂**。任务书「可构造端口占用」配方对此键无效——端口占用是子进程内错，非 spawn 错。
- **替代验证（同形渲染实锤）**：zh.lproj 编译表直读 harness（`/tmp/omp-r13/mcpharness.swift`，2035 键）：新形 `String(format: String(localized: "mcp_launcher_launch_failed"), reason)` → **`启动失败：port 8765 in use`**；旧形运行时键 `mcp_launcher_launch_failed <reason>` → **MISS（回退渲染裸键串，bug 复现）**。转换前后行为差实锤，与 zcode bundle  harness 同结论、zh 表口径。
- 证据：`omp-b-launcher-idle.png` / `omp-b-launcher-run.png` / `omp-b-mcp-settings.png`。
- 副作用还原：MCP server 已关（toggle 回 0，endpoint json 已收，残留 lock 文件为常态）；`mcp_agent_command_template` 测试值已删（`@AppStorage` 空串回写覆盖，键已不存在）；`library.import.rememberMode` 对话框写入已删；recentProjects 余 `/tmp` 自清项（既有清扫自愈）。

## 三、抽验 c：设置页本地化字符串（随机 3 个 + 全窗裸键扫描）——过

- LCR 页（`settings.page.localContentRecognition`）AX 实读：①`语义 · 512 维 · Apache-2.0 · 88 MB`（`settings_lcr_tier_detail %@ %@ %@` + `settings_lcr_dim_semantic %lld`，F-2 转换键）；②`增强 · BSD-3-Clause · 2 MB`；③`语义 · 768 维 · Apache-2.0 · —`（缺尺寸 `—` 回退臂）。三处全中文渲染，零裸键零英文回退。
- 全窗裸键扫描：三窗（Settings/MCP 启动器/主窗）全部 `AXStaticText` 值正则 `[a-z]+_[a-z_0-9]+` = **零命中**（仅文件名/项目名/模型名连字符形，合法）。
- 抽样诚实注记：Displays 页当前 `overridePath=nil` 走 `settings_displays_auto` 臂，`settings_displays_overridden %@`（三孤儿删除的孪生 survivor）屏上不可见——覆盖此键需手动指定 ICC override（写用户级显示配置），本轮未做；该键由 zh-audit specifier 深检 + 目录 dump 背书（zcode §四已亲核孪生逐字节相等）。
- 证据：`omp-c-lcr-page.png`（模型行裁切）/ `omp-c-lcr-full.png`（全屏）。

## 四、回归：编辑器主链 + 静置 CPU ——过

- 主链：adobe-gamma.tiff（AdobeRGB ICC）+ plain.tiff 双 TIFF 经项目导入（COUNT(*)=2，退出后持久）→ 编辑器 filmstrip 双行 → 双击加载 → 视口渲染粉色画布 + 直方图 RGB 峰 + RAW 解码页输入色彩四行。加载/渲染/读出链全通，无错误对话框。
- 静置 CPU：40s 双采样 `0.2% → 0.1%`，RSS 211.5MB 恒定（远低于 GUI 3G 线）；app log 零 error（仅 IMK 输入法 mach 端口噪音一行）。
- 证据：`omp-d-editor-mainchain.png`。

## 五、obs（2，新；zcode 2m+4obs 维持不重复）

1. **七 tab 轨 `editor.stack.tab.*` AX 不可见**：`EditorAdjustmentStackView.tabBar` 的 `.accessibilityIdentifier(tab.marker)` 在 AX 树中零命中（`editor.stack` 容器本身亦不可见，仅面板内容区 `editor.stack.panel.container` 可见）——SwiftUI `.buttonStyle(.plain)` + 背景态切换疑似吞标识。本轮 RAW tab 靠坐标点击。影响：后续验收/自动化探针仍须坐标兜底；建议后批给 tabBar 加 AX 可达回归（`editor.stack.tab.rawDecode` press）。
2. **任务书 b 项「端口占用」配方不可行**：见 §二——`launchFailed` 仅 spawn 失败可达，GUI 无构造面（shellPath 注入仅测试）。后批验收任务书应改配方为「zh 表同形渲染 + 启动面三态」，不再要求 GUI 构造 `launchFailed`。

（撤回注记：初稿 obs-3 指 `Text("mcp_launcher_exit_code \(code)")` 为 F-2 同族残留——核目录后撤回。`Text(…)` 插值走编译期 LocalizedStringKey（查表键 = `mcp_launcher_exit_code %lld`，在册），与 `String(localized:)` 运行时插值键漂移是两回事；`rawdecode_raster_peak_value` 同形屏上实读 `100 nits` 已证正确渲染。R13 未转 `Text` 形正确，无遗漏。）

## 六、还原与卫生

- 进程终态：自出 35238 已 quit；Lightamer/xctest/test-direct/machine-guard 全清零（ps 亲证）。
- 主树 tracked 零 diff（`git status --porcelain` 仅既有 untracked + 本轮新证据 untracked）。
- defaults：测试写入三键全清（`mcp_agent_command_template` 不存在；`library.import.rememberMode` 已删；`mcp_server_enabled`=0 回位）；recentProjects 余 /tmp 自清项。
- 文件：`~/Library/Application Support/Lightamer/Catalog/` 未动（本轮未开 Catalogs）；LUT 根未动；`/tmp/omp-r13` 即弃（含项目/截图/harness， evid 正本已入 `.work/gui-acceptance/r13/omp/`）。
- 本文件不入 git（验收轮产物，待 orchestrator 决定随批或留档）。
