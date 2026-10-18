# NSMenu Spike（F0 AppKit 实验桥 + D-6 缓解实验）— SPIKE.md

> **性质**：research/UI-STACK-SUCCESSOR-PRE §4 的 NSMenu spike——条件账拉正后的第一实验。
> **日期**：2026-10-19（04:03–04:27 对测窗）。**worktree**：`../Lightamer-nsmenu-spike`
> （分支 `spike/nsmenu-f0`，spike commit `dfde03bc`，主 tip `03830b01`）。
> **结论头：FAIL（一天封顶收兵）**——B vs A 编辑器静置差分 **−0.5pp**，
> |Δ| ≤ 1.9% 噪声带 → 相对门（逆向使用）未达改善线；C vs A −1.4pp 带内
> （flag OFF 零回归成立）。**净知识增益 = 两条机制级发现**（§3）：
> macOS 27 SwiftUI 绕过 `NSApp.mainMenu`；稳态编辑器面 menu 环符号缺席
> （三臂一致）——churn 载体是面自身 ViewGraph/layout，非菜单重建。
> **NSMenu 条件账维持原触发条件不变，且账上新增一条实测反证。**

---

## §1 实验设计

### 1.1 三臂

| 臂 | 构建 | 内容 | 二进制身份 |
|---|---|---|---|
| **A** | 主 tip `03830b01` + 仅 probe-stay hunk（测量基建，见 §1.3） | HEAD 现行（SwiftUI Commands 全族） | strings 无 `NSMenuBridgeController`、有 `la_probe_stay` |
| **B** | spike commit `dfde03bc`，flag ON | `.commands` 缩为 inert Help stub（45 自定义项不建）+ NSMenu 桥 install（`MenuCommandSet` 消费 + 观察适配器） | strings 有 `NSMenuBridgeController` |
| **C** | 同 B 的二进制，flag OFF | 代码在、桥未启——隔离「纯增量」 | 同 B |

flag 注入走 `defaults write la.menu.nsmenuBridge`（**不走启动参数**——§3.3 的
实测陷阱：混合 argv 下 `-la.menu.nsmenuBridge 1` 炸窗口创建）。B/C 同二进制、
同 argv，flag 是唯一变量。

### 1.2 协议（D-AR1-10 F-8 钉死形 + L082 纪律）

- 驱动 = `-la_editor_probe <fixtures>`（2 DNG link 导入）+ `-la_probe_stay`
  留编辑器面；probe stderr 标记（`rendered=yes` + `staying alive`）=
  **phase=editor 机检**（9/9 轮全绿）。
- settle 60s（盖 LUT 预热 ~50s）→ System Events `frontmost` 先行 + 复验
  （9/9 轮 `frontmost=true`；读数 ~95% ≠ 0% = 遮挡哨兵通过）→ 截图。
- 30s 窗 6 采样 @6s 中位（`ps -o %cpu`）→ `sample 6s` 栈旁证（符号总量
  跨行求和，前缀感知解析——初版计数脚本漏 `+`/`!` 前缀行，已对原始
  sample 文件重提，正本 = 各轮 `sample.txt`，可复算）。
- 三轮交错（A→B→C ×3）去漂移。

### 1.3 偏差申报

- **A 臂非纯 HEAD**：HEAD 的 `-la_editor_probe` 加载完即 `NSApp.terminate`
  （AR-01 F-8 §1 已勘定不可作静置探针）。A 臂 = HEAD + 仅 probe-stay hunk
  （DEBUG 探针尾 3 行，零产品路径），patch 内可见。C 臂的存在正是为隔离
  一切代码存在性增量——C vs A 带内即证明测量基建与 spike 代码存在均零回归。
- **桥未争夺菜单栏所有权**（见 §3.1——争不了）：install 落在专设 `.task`
  （大 wiring task 在裸直启下早期 await 挂起，与本 spike 无关的既有现象，
  probe 任务独立不受扰）；stomp 被动计数全程零命中（§3.1）。

## §2 三臂数据

| 轮 | A %cpu 中位 | B | C |
|---|---|---|---|
| r1 | 95.7 | 95.8 | 94.3 |
| r2 | 96.6 | 95.8 | 95.3 |
| r3 | 96.3 | 97.8 | 94.9 |
| **中位** | **96.3** | **95.8** | **94.9** |

- **B vs A = −0.5pp** → 带内（≤1.9%）→ **FAIL**（判据要 >1.9pp 改善）。
- **C vs A = −1.4pp** → 带内 → flag OFF 零回归证明成立。
- 9/9 轮 `editor-face=confirmed` + `frontmost=true` + VERDICT=OK；
  正本 = `logs/<臂>-<轮>/{meta,cpu,symbols}.txt + sample.txt + screen.png`。

### 2.1 栈旁证（符号总量，前缀感知重提正本）

| 量 | A (r1/r2/r3) | B (r1/r2/r3) | C (r1/r2/r3) |
|---|---|---|---|
| makeMainMenu | 1/0/0 | 0/0/0 | 0/0/0 |
| updateMainMenu | 1/0/0 | 0/0/0 | 0/0/0 |
| appGraphDidChange | 2/0/0 | 0/0/0 | 0/0/0 |
| beginTransaction | 64/0/4266 | 1189/0/4061 | 0/1699/0 |
| UpdateStack | 16/257/297 | 90/297/299 | 278/178/276 |
| sizeThatFits | 124/635/584 | 359/716/755 | 724/480/702 |

**menu 环符号三臂一致缺席**（≈0/样本）而 CPU 恒 ~95%：本操作点（2 图
probe 项目、60s settle、遮挡纪律前置）下，churn 载体 = 面自身
ViewGraph/layout 机器（UpdateStack/sizeThatFits/NSHostingView
beginTransaction——后者双峰 0↔4000+，采样相位依赖）。菜单重建不是振幅
载体。M7-1 Exp-3 时代 mm 274 的样本采自激活后即时窗，与本稳态窗操作点
不同——两读数不矛盾，是同一环在不同相位/面权重的采样差。

## §3 机制发现（净知识增益）

### 3.1 macOS 27 SwiftUI 绕过 `NSApp.mainMenu`（F0 路线结构性失效）

- `install()` 成功执行并持有属性级所有权：bridge log（`logs/bridge-install-trace.log`）
  `install begin/end` ×3 轮全落；+1s/+3s 复查 + 观察驱动 refreshAll 全程
  **零 stomp**——`NSApp.mainMenu` === 桥树从未被属性级覆盖。
- 但**像素 + AX 菜单栏恒为 SwiftUI 骨架**：截图（`logs/bridge-ownership-screen.png`）
  栏 = `Lightamer | 显示 | 窗口 | 帮助`；AX dump：帮助菜单内容 = stub
  Button「Lightamer」（SwiftUI stub 的内容）、窗口菜单 = SwiftUI 全窗口
  清单（含 预设管理器/MCP Agent 启动器 两窗名）——均为 SwiftUI 自持
  菜单栏宿主的特征。桥树（File/Edit/标记/图像…）从未上屏。
- **裁定**：macOS 27 SwiftUI 生命周期下，菜单栏不（只）经 `NSApp.mainMenu`
  通道——`makeMainMenu/updateMainMenu` 是 SwiftUI 自持宿主的内部机器，
  AppKit 侧 setter 赋值不夺屏。**F0「NSApp.mainMenu 装配」前提在此
  SwiftUI 版本上不成立**；要夺屏只能进 SwiftUI 私有宿主（脆弱，超
  spike 范围）或等 SwiftUI 让位（不可能）。

### 3.2 churn 非菜单驱动（§2.1 数据 + B vs A 带内同证）

即便 §3.1 的所有权机制失效，B 臂仍完成了一次「SwiftUI Commands 45 项
→ inert stub」的实测——`makeMainMenu` 级别的重建工作量若曾是振幅载体，
B 应显著下降；实测 B ≈ A（−0.5pp 带内）。**菜单内容最小化不是 D-6 缓解
杠杆**——与 FIX2 C1/C2 树形证伪、M7-1「可见性门控 × 振幅随面重」行为
模型同向，本次以「菜单面摘除」完成第三次独立同向复现（前两次 = 摘
.inspector/safeAreaInset 段，本次 = 摘 Commands 全族 + NSMenu 桥）。

### 3.3 启动参数陷阱（配方教训）

`-la.menu.nsmenuBridge 1` 混入 `-la_editor_probe <path> -la_probe_stay`
argv → 窗口创建炸（无窗 + 骨架菜单，两次复现）；flag 改 defaults 注入后
一切正常。**后续探针配方：flag 一律 defaults 注入，不做混合 argv。**

## §4 判定与回滚处置

- **判定：FAIL**（B vs A −0.5pp ≤ 1.9% 带；spec §4.1 判据线逆向行使——
  找改善，未达）。
- **不 commit 到 main**（FAIL 分支）。spike 代码保存在分支
  `spike/nsmenu-f0`（commit `dfde03bc`，worktree 删除后分支保留）+
  `nsmenu-f0.patch`（937 行，本目录）备查。
- **条件账处置**：NSMenu 外科替换维持原触发条件（macOS 27.1 落地仍未修
  ∧ 用户判定 churn 痛到值得动）不变；新增实测反证两条（§3.1/§3.2）——
  「等上游」立场的证据更厚（research §6 预期的 FAIL 分支价值兑现）。
- **strangler 校准输入**：F0（菜单桥）作为 AppKit 路第一砖被证伪——
  菜单面不是 churn 杠杆，AppKit 迁移路线若立项应以 F1 编辑器面为起点
  （froze F0），且需先解决 §3.1 的菜单栏所有权机制问题（F0 前置项，
  任何 AppKit 化都必须回答「SwiftUI 菜单栏宿主如何让位」）。
- **收尾申报**：worktree `../Lightamer-nsmenu-spike` 删除（目录），
  分支保留；主树只落本 doc + evidence commit；defaults 已还原
  （`library.ai.labelingMode=never` 原值保持、spike flag 键删除）；
  代理 daemon 停机。

## §5 证据文件清单

- `logs/<臂>-<轮>/`：meta.txt（pid/frontmost/verdict）、cpu.txt（6 采样+中位）、
  symbols.txt（初版计数——被 §2.1 前缀感知重提取代，保留作过程记录）、
  stderr.log（probe 全输出）。每轮 sample.txt/screen.png 体量大已按代表性
  修剪：全臂原始 sample 三份留档（sample-A-r3 / sample-B-r1 / sample-C-r3）
  + 桥燃烧形态一份（sample-bridge-burn.txt）；截屏仅留所有权裁决像素正本
  （bridge-ownership-screen.png）。
- `logs/bridge-install-trace.log`：install begin/end ×3（B 轮全落）。
- `logs/bridge-ownership-screen.png`：所有权夺屏失败的像素正本。
- `logs/sample-bridge-burn.txt`：桥 CPU 燃烧形态样本（ViewGraph churn）。
- `logs/driver-stdout.log` / `logs/defaults-state.txt`：驱动留痕。
- `nsmenu-f0.patch`：spike 全部代码 diff（含 §1.3 的 A 臂 hunk 说明）。
- 二进制（即弃域 /tmp/nsmenu-spike-bin/，A/B 身份 strings 校验记录在 §1.1）。
