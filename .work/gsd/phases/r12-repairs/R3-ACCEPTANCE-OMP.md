# R3 修复批终审（ACCEPTANCE-OMP — computer-use 实机，2026-10-23）

> 验收对象：R3 三件 `3d325125`(F2-1)/`22082049`(标记接线)/`856f2396`(gamma E 族)+docs
> `8a1a5c2d`（主树 HEAD = `2b2246cb` 亲证，验收零源码改动、tracked 零 diff）。
> 正本 = R3-ACCEPTANCE.md（zcode 综合验收 PASS/0B+0M+0m+2obs）+ r3 MANIFEST +
> 四笔 commit bodies。本路 = 独占终审眼，实机四项抽验全亲驱。
>
> 二进制：默认容器 `Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi`（Debug/Lightamer.app，
> mtime 10-23 12:08；strings 亲证 `ImportModeDialogSheetContent` ×2 /
> `LibraryMarkApplier` ×1 / `rawdecode_raster_trc_gamma_value` ×1 = R3 三件在位）。
> guard 前置 PASS（heavy=0 free=78%）。全套 `--all` 不复跑（zcode 已独立复跑
> `4112/40/0` 逐位对账；本路实机四项 + 定向三重零机器核验）。
> 进程：自出 PID 81140 全程唯一（a→d 单实例贯穿），⌘Q 已退出；无新 .ips；
> NSNavLastRootDirectory 预置后已删（批前 absent 态还原）；browser.mode=grid 未动；
> recentProjects 新增一条 /tmp 死路径（随 /tmp 清理，下次启动既有清扫摘除）；
> /tmp/r3-omp 已清，家目录零残留。

## 结论头

**PASS / 0 blocking + 0 major + 0 minor + 3 obs**

四项实机抽验：a) Import Folder 全流程 ✓（sheet 挂载存活 + 扫描 3 TIFF +
导入完成——修复前此点确定性 EXC_BREAKPOINT）/ b) 标记三面同步 ✓（菜单 5 星 →
徽章 + DB=5 + sidecar=5；清除 → DB NULL + sidecar None + 徽章消 + 聚合回位）/
c) gamma 读出 ✓（raster 面「伽马 1.80」，裸键零残留）/ d) 三窗 + 主链 ✓
（⌘,/预设管理器/MCP 同开共存 + 编辑器主链出图 + idle 0.2%/526MB）。

## 一、实机抽验

### a) F2-1 Import Folder 全流程 — ✓ PASS（修复实锤）

- 配方：probe 项目（Untitled.lalb @/tmp/r3-omp）+ ⌘⇧I + NSNavLastRootDirectory 预置缝。
- `omp-06-sheet-mounted.png` = **ImportModeDialog sheet 挂载存活**：标题「导入 "src"」
  + 移动/拷贝/链接三段（拷贝选中）+ 相机 RAW 0 / TIFF 图像 3 / 其他类型锁灰 +
  导入钮 —— 挂载点 PID 存活（R12 omp ips 崩点，修复前 = 此刻 EXC_BREAKPOINT）。
- `omp-07c/08` = 导入完成：3 缩略图入格（红绿蓝）+ 图库概览 3 照片 + AI 询问 sheet
  同活后「暂不」消解；机器核验 DB images=3 + Media/src 3×tif 落盘。全流程闭合。
- 第二轮导入（gamma 夹，omp-12/13）同路径再活一次，4 照片。

### b) 标记链接线（D5 让渡兑现）— ✓ PASS（三重零闭合）

- 菜单 标记 → `5 星 (5)`（AX 三层：menubar→AXMenu→AXMenuItem，标题精确匹配）→
  `omp-10-rating5.png` = 蓝格左下 ★★★★★ 徽章 + 侧栏按色标 Unrated 2 / ★★★★★ 1 +
  高分组 1；机器核验 **DB `images.rating=5`（c.tif 行）+ `Media/src/c.tif.lra`
  schemaVersion 11 `rating=5`** —— UI/DB/sidecar 三面齐动。
- 标记 → `清除评分 (0)` → `omp-11-rating-cleared.png` = 徽章消失 + 按色标 Unrated 3 +
  高分组 0；机器核验 **DB rating=NULL + sidecar `rating=None`** —— 三面齐清。
- 驱动注记：菜单 AXPress 须先 AXPress 顶层「标记」展开 lazily-loaded AXMenu 再取子项
  （axmenu3.py 形态）；walk.py `press` 对菜单项 MISS（非窗内按钮）——走查工具面，
  非产物缺口。

### c) gamma E 族显式形 — ✓ PASS

- Generic RGB Profile（gamma 1.8）TIFF 开编辑器 → RAW 解码 tab（AXDescription
  「RAW 解码」按钮坐标点击）→ `omp-19-rawdecode.png` = 输入色彩节：配置文件=
  Generic RGB Profile / 来源=内嵌 ICC / **传递曲线=「伽马 1.80」** / 峰值=100 nits
  —— 静态键 + `%.2f` 值分离渲染，裸键/`%@` 未替换零残留。
- 复证 zcode obs-2：raster 读出为 TIFF 载体专属面（either/or 布局既有行为）。

### d) 三窗 + 主链回归 — ✓ PASS

- 三窗同开共存（PID 81140 全程不变）：⌘, Settings 落默认页「语言与主题」
  （omp-20，十项侧栏 + 界面语言/主题面非空）/ Edit▸预设管理器（omp-21，
  Tone Sunny + 未分类 Web150 + 坏预设 footer）/ Edit▸MCP Agent 启动器
  （omp-22，空闲无会话 + 跟随输出勾选）。关窗经 traffic-light 坐标点击逐一关
  （⌘W 对 Settings/MCP 非主窗不生效——走查工具面）。
- 主链：File▸进入编辑器 → filmstrip 双击 g18.tif → omp-26 = 编辑器画布出图
  （灰调 + 3×3 网格 + 变换手柄）+ 色温 6504K 白平衡模块展开 + 右列七 tab 齐全，
  零错误窗。
- 静置：三采样 CPU **0.2/0.2/0.2%**，RSS 526MB 恒定（<3G 触发线一个量级）——
  F0' 壳交接 CPU 面守住。

## 二、分级清单

- **blocking (0)**：无。
- **major (0)**：无。
- **minor (0)**：无。
- **obs (3)**：
  1. zcode obs-1（单槽请求域语义）本路未复测——连发攻击面已有 zcode 真机终态
     证据（DB=5 + sidecar=5），本路单发路径三重零闭合一致，观察项维持。
  2. 编辑器画布 g18.tif 呈近白/灰调均匀场、直方图稀疏（omp-18/26）——合成纯色
     夹料（120,110,100）在 scene-referred 管线下的预期渲染，非解码缺口；
     真图渲染面由既有 golden/走查覆盖。
  3. ⌘W 关闭 Settings/MCP/preset 三窗不生效（须 traffic-light 坐标关）——
     SwiftUI Settings scene / NSWindowController 系既有行为（F0' 三窗控制器），
     非 R3 面；走查工具注记。

**验收材料**：真机证据 `.work/gui-acceptance/r3/omp/omp-01..26`（30 帧，含中间帧
全留证）；驱动脚本随 /tmp 即弃（axpress/axmenu3/axdo/axbtn/axwins/axclose 皆
walk.py + AX 拼装，无仓库残留）。

## 三、结论

**PASS / 0 blocking + 0 major + 0 minor + 3 obs。**R3 三件忠实落地：F2-1
sheet 挂载存活（R12 major-1 真机崩点亲手复验通过）+ 标记三重零闭合（D5 让渡
兑现）+ gamma 键值分离渲染（E 族显式形）。zcode PASS 结论独立复现成立，无推翻项。
