# F0P-01-ACCEPTANCE-OMP — P1 终审（dual_acceptance 终审眼，computer-use 实机）

> **PASS / 0 blocking + 0 major + 1 minor + 2 obs。**
> 验收窗：2026-10-19 20:57–21:12。验收对象 = P1 执行链 `907c373d..ef312a2a`
> + 三窗修复 `c4d107bf` + docs `dd1bd494`（主树 HEAD = `dd1bd494` 亲核；
> c4d107bf diff 逐行亲读）。方法 = 零源码改动 + 终 HEAD 独立 DerivedData
> 自建二进制（`/tmp/f0p1-omp-dd`，BUILD SUCCEEDED，strings 亲证
> LightamerShellMain×1 + NSMenuBridgeController×2）+ 探针协议复跑（60s
> settle + frontmost 先行）+ computer-use 实机抽验（a/b/c/d 四项全做）+
> 零残留收尾（自出 pid 81895 显式回收，`pgrep Lightamer.app` 零残留）。
> 前置双路结论：第一路 PASS（一路机检路线），第二路 FAIL→blocking-1 已由
> fix 修复（fix-verify 三窗截图在卷）。本轮 = 终审眼独立复验。
> 证据卷 = `.work/gui-acceptance/f0prime-p1/omp/`（7 截图 + 7 菜单 dump +
> cpu×2 + sample + stderr）。

## 0. 结论头

**PASS / 0 blocking + 0 major + 1 minor + 2 obs**——四项实机抽验全过：

- a) 编辑器静置 CPU：第一窗 6 采样单调衰减 1.6→1.2（中位 1.4），第二窗
  0.9→0.7（中位 0.8）；churn 符号族 7 符号全 0；主线程 4394/4394 泊
  `LightamerShellMain.run → NSApplication.run → mach_msg2_trap`。**D-6
  绝对门 <10% = PASS**（余量 9.2pp；非 0.0 读数的归因见 minor-1——
  `ps %cpu` 衰减平均残留 + 后台线程全泊，主证据链无 churn）。
- b) 三窗逐个开 + 截图：Settings（10 侧栏项 + 语言与主题详情面）、
  预设管理器（Tone/Sunny + 未分类/Web150 + 坏预设脚注）、MCP 启动器
  （工具栏 + 空闲态 + 暂无输出占位）**三窗内容真实渲染，零空白**。
  blocking-1 修复实机复验闭合。
- c) 菜单七族抽查 10 项点验全活（AX click 实测 + enabled 翻转判读）。
- d) 图库→编辑器主链往返：⌘W 出编辑器（图库 2 缩略图 + EXIF 概览）→
  ⌘E 回编辑器（返回面与静置面 0.36% 像素差 = 仅时钟/hover 级差异）。

1 minor = 证据解读面（CPU 非零归因留痕，不触行为）；2 obs = 方法学注记。

## 一、抽验 a) 编辑器静置 CPU（D-6 门独立复测）

二进制 = 终 HEAD `dd1bd494` 自建（独立 DerivedData `/tmp/f0p1-omp-dd`，
与执行/双路三方构建路径全异构）。协议 = `-la_editor_probe
/tmp/nsmenu-spike-fixtures -la_probe_stay`（供件 = 01-05/samples 双 DNG
亲拷）→ stay 标记（stderr 亲核双行 loaded/rendered=yes + staying alive）
→ 60s settle（盖 LUT 预热）→ frontmost 先行复验 true → 截图 →
30s 窗 6 采样 @6s → `sample 6s`。

| 窗 | 六采样 | 中位 | 判定 |
|---|---|---|---|
| 第一窗（t=0..30s） | 1.6/1.5/1.4/1.3/1.2/1.2 | **1.4** | <10% ✓ |
| 第二窗（t≈+2min） | 0.9/0.8/0.8/0.8/0.7/0.7 | **0.8** | <10% ✓ |

- L082 四哨兵：①frontmost 1/1 true（读数前先行）②窗内截图编辑器面完整
  渲染（见 §五）③主线程泊 4394/4394（另 4387 落 mach_msg2_trap 栈顶行，
  余 7 为 runloop 帧内采样，泊语义成立）④churn 符号族 7 符号总量全 0
  （前缀感知求和，与 run-one-f0p1.sh 同式）。
- 后台线程：NSEventThread + 2 workq 全泊（__workq_kernreturn/mach_msg2）。
- 非 0.0 归因（minor-1）：两窗读数均呈严格单调衰减（1.6→0.7），`ps %cpu`
  为指数衰减平均——启动/LUT/解码残留热未散尽；主线程 100% 泊 + 符号族
  全零 = 无 churn 机器在场。前三方（执行 B-r/一路 acc-r/二路 r1）0.0
  与本轮 0.8–1.4 的差 = 采样时点在衰减曲线上的位置差，非行为差。
  D-6 绝对门判据 <10% 下余量 9.2pp，结论不受影响。

## 二、抽验 b) 三窗逐个开（blocking-1 修复复验）

逐窗 AX 真点击菜单路由开窗 → 置前 → 截图 → 识图 → 红叉关窗 →
窗清单复核。每窗结论：

| 窗 | 路由 | 渲染内容（识图亲验） | 判定 |
|---|---|---|---|
| Settings（⌘,） | Lightamer 菜单 Settings… | 10 侧栏项（语言与主题选中/默认行为/缓存/本地内容识别/高级内容分析/键盘/关于/导入默认设置/显示/MCP）+ 详情面（界面语言跟随系统/主题外观深色v1固定） | ✓ 非空白 |
| 预设管理器 | Edit 菜单 预设管理器… | Tone/Sunny 调整行 + 未分类/Web150 导出行 + 顶部 +/分享按钮 + 底部坏预设脚注 broken.lightamer-preset | ✓ 非空白 |
| MCP 启动器 | Edit 菜单 MCP Agent 启动器… | 工具栏（启动 Agent/停止灰/跟随输出勾/复制日志）+ 空闲——无 agent 会话 + (暂无输出) 占位 | ✓ 非空白（占位 = 空闲态合法面） |

- fix 形态亲核：`ShellWindowControllers.swift` 三处 `contentView =
  NSHostingView` 无条件挂载在位，`if window.contentView == nil`
  全仓零命中；c4d107bf 恰 1 产线文件 25+/23-，root view 与 env 链
  零改（纯 guard→无条件形）。
- 三窗开关过程 app 存活（ALIVE 逐窗复核），关窗后窗清单回单主窗。

## 三、抽验 c) 菜单七族抽查 10 项点验

menubar 九项上屏（Apple/Lightamer/File/Edit/显示/标记/图像/Window/Help，
中英混排 = D-F0P-01-5.4 登记态）。七族 dump 全量存档（数量与双路一致：
File 18/Edit 22/显示 20/标记 18/图像 2/Window 20/Help 1）。

| # | 项 | 点验法 | 结果 |
|---|---|---|---|
| 1 | Settings… | AX click → 真窗渲染（§二） | ✓ |
| 2 | 返回图库 ⌘W | AX click → 图库面（§四） | ✓ |
| 3 | 进入编辑器 ⌘E | AX click → 编辑器面（§四） | ✓ |
| 4 | 导出… ⇧⌘E | launch 态 enabled=true（dump）+ AX click → 导出页全装配（§四） | ✓ |
| 5 | 复制调整 ⇧⌘C | AX click | ✓（下游翻转见 6） |
| 6 | 粘贴调整 ⇧⌘V | click 前 enabled=false → 复制后 =true | ✓ 实时翻转 |
| 7 | 撤销 ⌘Z | AX click（有编辑态） | ✓ |
| 8 | 重做 ⇧⌘Z | undo 后 撤销=false/重做=true | ✓ 环翻转 |
| 9 | 预设管理器… | AX click → 真窗渲染（§二） | ✓ |
| 10 | MCP Agent 启动器… | AX click → 真窗渲染（§二） | ✓ |

附加判读：标记族 16 语义项全 enabled（rating 6+flag 3+color 7）；
⌘W 双面语义与 D-F0P-01-5.1 对齐（editor 面 返回图库 enabled，
进入编辑器 disabled）；export 恒 enabled（D-F0P-01-5.2）行为级再证。

## 四、抽验 d) 图库→编辑器主链往返

返回图库点击 → 图库面（2 缩略图 + 图库概览 inspector：2 照片总数 +
按日期/相机/色标/镜头分组 + 活动/搜索/AI 分析/智能相册）→ 进入编辑器
点击 → 编辑器面（大画布 + 右调色面板 + 左 filmstrip + 底工具轨）。
往返前后编辑器帧像素差 = 18139/5089536（0.36%，时钟走字 + 菜单 hover
级差异），返回面与静置面逐像素同构。导出页 ⇧⌘E 全装配再证（预设/
输出位置/文件命名 10 token/命名冲突/元数据与色彩/SDR 导出/格式 JPEG/
UltraHDR/质量 95%/尺寸/高级/导出队列）。

## 五、分级残留清单

**minor（1）**

1. **CPU 读数非 0.0 的归因留痕**：本轮两窗中位 1.4/0.8，前三方 0.0。
   主证据链（主线程全泊 + 符号族全零 + 后台全泊 + 单调衰减曲线）已闭合
   「无 churn」结论，差值 = `ps %cpu` 衰减平均的采样时点差。D-6 门余量
   9.2pp。处方：P2 定版轮沿用既定配方即可；本条为终审轮读数诚实留痕，
   不开修复项。

**obs（2）**

1. **探针态中央欢迎 modal 常驻**：本轮三张主窗截图中央均有「创建项目，
   整理你的照片库」modal（执行 B-r1/一路 acc-r1 留档屏无此 modal）。
   模态来源 = 探针临时项目 `.lalb` 落 $TMPDIR + Welcome 面逻辑，非翻转
   面（菜单/探针/往返全活，主窗 AX 窗清单恒常）。P2 走查轮如需无 modal
   净面，配方补「暂不使用项目」点击一步。
2. **探针画布 false-color 呈现在案**：本轮编辑器画布呈 teal 灰色块
   false-color，与 B-r1 留档屏同构（双路亦见同态，未单独立项）。
   stderr 双行 rendered=yes + 纹理在位 = 解码渲染链活；呈色属探针
   fixture（DNG 无 sidecar 默认管线）的显示态，非回归信号。

**双路遗留路由追认**：major-1（标记应用链断 = 既有缺陷 → 既有缺陷队列，
MANIFEST 面 7 ✓→✗ 勘正）与 major-2（export 加入选中 action 失效 →
P2 首批归因）按 DECISIONS deviation-6 路由生效，本轮不重验（C 档停位下
P1 验收边界外）。revert 两步叙事（revert 752c5294 + revert c4d107bf）
经 diff 面亲核成立（fix 恰单文件，翻转三文件零交集），git 层 revert
复跑由双路覆盖，本轮不重复。

## 六、验收轮痕迹与还原

- 主树 HEAD = `dd1bd494` 零改动（本报告为唯一写产物，不 commit）；
  defaults `library.ai.labelingMode` 未写（读 UNSET，探针协议的 defaults
  钳制本轮未启用——60s settle 覆盖预热）。
- 构建：`/tmp/f0p1-omp-dd` 独立 DerivedData（Debug, BUILD SUCCEEDED）。
- 进程：自出 pid 81895（ppid = 本 omp 进程）TERM + 显式回收复核；
  `pgrep Lightamer.app` 零残留；/tmp 即弃域（f0p1-omp 日志/截图/ax dump、
  f0p1-omp-dd 构建产物、nsmenu-spike-fixtures 供件拷）按惯例即弃。
- GUI 独占：本轮运行窗内零他路 Lightamer 实例（ps 亲核）。
