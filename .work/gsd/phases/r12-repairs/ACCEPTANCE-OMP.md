# R12-REPAIRS ACCEPTANCE-OMP — R1/R2 修复批终审（computer-use 实机，2026-10-23）

> 验收对象：接续批 5 commits（`f64593af` M-1 / `266647c1` 标记链断 substrate /
> `926ba65d` F2-4 / `41790826` R2 卫生 / `c09533bf` docs）+ ops（`8acfb31e` v1.2 /
> `e7852a1e` guard v1.3）。正本 = 审计 MANIFEST §R1/R2 + r12 SUMMARY/DECISIONS +
> 一路 ACCEPTANCE.md（PASS/0B+1M+2m+7obs）+ 二路 ACCEPTANCE-2ND.md（PASS/0B+0M+3m+8obs）。
> 主树 HEAD = `076ba696` 亲证；零源码改动；主树 tracked 零 diff；唯一写产物 = 本报告 +
> `.work/gui-acceptance/r12/omp/` 截图；app 用完已退出，零残留进程。
>
> 二进制：默认容器 `Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi`（Debug/Lightamer.app，
> PlugIns 七 .xctest；`testPairChangeRespawns` ×4 / `LibraryMetadataWriter` ×4
> strings 亲证 = 含 R12 新测试符号）。guard 前置 PASS（heavy=0 free=66%）。
> 全套 `--all` 不复跑（两路已各独立复跑 `4106/40/0` 三路逐值一致；本路定向复跑
> R12 新增两测试类 + zh-audit 独立复现 + 实机五项抽验）。

## 结论头

**PASS / 0 blocking + 1 major + 2 minor + 6 obs**

五项实机抽验：a) culling 双 pane 出图 ✓（staggered 中间态 + 双图终态双帧实拍）/
b) 标记链断 ✓（writer 4/4 绿 + 真机工作区命令 no-op 无崩 + 让渡面如实）/
c) SettingsLink 真窗 + ACA 深链 ✓（+ ⌘, 串扰反证复现）/ d) 菜单五项 ✓ /
e) 静置 CPU ~1.2-1.4% ✓（RMS 0.48GB，持续性成立）。
1 major = Import Folder 真机崩溃（M-9 在账形态的运行时实证，非本批引入，不阻断收口）。

## 一、定向复跑（本路独立）

- Sessions `CullingPipelineTests`：**6/0/0**（4s，peakRSS 397MB）——M-1 新法在内。
- Library `LibraryMetadataWriterTests`：**4/0/0**（0s，peakRSS 214MB）——writer 四法。
- zh-audit `--check`：**PASS**（1687 source / 2005 catalog / 41 interp 全
  variant-PRESENT，与两路逐值一致）。

## 二、实机抽验

### a) M-1 culling pair 切换 → 双 pane 出图 — ✓ PASS

- 配方：legacy 门 + `browser.mode=culling` 预置 + File → 打开会话（NSNavLastRootDirectory
  预置缝；注意 ⌘O = 单文件板，需显式点「打开会话…」——第一帧 `cull-omp-1.png` 即此误操作留证）。
- `cull-omp-2.png` = staggered 防风暴中间态（A.ARW 已渲染 + A_mertens.tif「解码中…」占位）
  ——与二路 `cull-shot.png` 同构，独立复现。
- `cull-omp-4.png`（~3min 后）= 双 pane 并排渲染终态（A.ARW 夜景 + A_mertens.tif
  融合图），零加载指示，状态栏「就绪」。
- B pane 落地慢（963.5MB TIFF 解码 ~2-3min，CPU 26%→14% 忙态）属解码负载非缺陷；
  落地后静置 CPU 回落（见 e）。
- pair 切换真机直通仍不存在（复证两路 obs-2：CullingView 零手势；pair 切换重载证明 =
  行为级回归测试 6/0/0 本路复绿）。

### b) 标记应用 → writer 落盘 / 工作区命令 no-op — ✓ PASS（让渡面如实）

- writer 落盘面：`LibraryMetadataWriterTests` 4/4 绿（真 .lalb + 真图档：pristine mint
  双写 / round-trip / SC#2 / grid patch）——MetadataService/DB 面验证兑现。
- 真机面：probe 项目（空库）下 ⌘3（3 星）→ 无崩、无窗、无 .lra 落盘（`ls *.lra`
  零命中双目录）、`images` 表 count=0 不变 → **no-op 与 D5 让渡申报逐字一致**
  （`mark-noop-omp.png`）。
- 接线腿仍开放（下一批首项候选）；二路 minor-2/3（分页一致性 / 崩溃窗时序）设计输入在账，未动。

### c) SettingsLink → 真窗 + 深链「高级内容分析」— ✓ PASS

- probe 项目 + `library.ai.connection` absent → 检查器 AI 区「打开设置…」（AX role=AXLink，
  `.buttonStyle(.link)` 产物，AX 树第 27 位）→ AXPress → **Settings 窗出现 + 侧栏
  「高级内容分析」高亮 + detail = 协议/Base URL/模型/API 密钥/AI 评片区**
  （`settings-omp.png`）——死钮 → 真窗闭环三路复现。
- ⌘, 串扰反证复现：关窗 → ⌘, → **落默认页「语言与主题」**（`settings-cmdcomma-omp.png`），
  零陈旧深链 ——与二路加测一致。
- 深链重现性（关窗复点）本路未重测（二路已证 `settings-reopen.png`；pendingPage 唯一
  setter 形态未变，无回归面）。

### d) 菜单抽验五项 — ✓ PASS

- File 18 / Edit 20 / 显示 20 / 图像 2 / Window 21 项全可枚举，零 ERR。
- 标记菜单 17 项全中文在册（清除评分/1-5 星/精选/拒绝/清除旗标/清除色标/红橙黄绿蓝紫），
  与 zh-audit 零缺 zh 一致。

### e) 编辑器静置 CPU ~0%（壳交接持续性）— ✓ PASS

- probe 空库静置 20s 四采样：**1.4/1.4/1.3/1.2%**，RSS 恒 480928KB 零漂移。
- culling 实例解码落地后同样回落（1.8% @3min，RSS 收敛 152MB）。
- 无持续性回潮（F0' 壳交接 CPU 面守住）。

## 三、分级清单

- **major-1：Import Folder 真机崩溃（EXC_BREAKPOINT / EnvironmentValues 下标断言）**——
  probe 项目 File → Import Folder… → 选 `/tmp/r12-omp/fix`（2×ARW）→ sheet 挂载瞬间崩
  （`crash-import-omp.png` = 「Lightamer 意外退出」报告板；
  `.ips` = `Lightamer-2026-10-23-103210.ips`，pid 31682，本路自出进程）。
  栈顶 = `_assertionFailure` ← `EnvironmentValues.subscript.getter` ←
  `EnvironmentBox.update`（SwiftUI 环境缺对象经典签名）；app 帧仅壳入口四帧，
  无业务符号。归因 = **M-9 在账形态的运行时实证**：`ImportModeDialog:85`
  `@Environment(AgentControlCoordinator.self)` 裸读 + app-root `.sheet(item:)`
  闭包跨界（`LightamerShell.swift:187`）= M2-8-3 已禁形态（Copy Adjustments 同款
  已修先例 `e9c03af`）。**非本批引入**：① R12 四笔源码 commits（`git show --stat`
  逐笔）零触 ImportModeDialog/sheet 挂载点（F2-4 对 LightamerShell 仅 +10 行 onChange
  缝）；② 同签名 `.ips` 在批前已存在（`09:22` 同机早盘，栈顶逐帧一致）；
  ③ 两路走查均成功导入（acc2 `after-import.png` 在案）——触发与环境/时序相关，
  修前即有。**不阻断本批收口**（R12 无 import 面改动；MANIFEST 已路由 M-9 = R1
  小件「init 参数注入 + 走查验证 agent-control 期 confirm 门」——本报告将其
  路由升级为阻塞性输入：M-9 修复批必须附真机 Import Folder 走查复验）。
- **minor-1：一路 minor-2 已关闭（guard v1.3 本路亲历佐证）**——本路 guard 一次过
  （heavy=0 free=66%），v1.3 撤门后零校准零阻塞；一路的 ops 裁决项维持关闭态。
- **minor-2：走查 defaults 副作用**——`browser.mode` 已回写批前值 `grid`；
  `NSNavLastRootDirectory` 本路预置后已 delete（批前 absent）；`library.ai.connection`
  保持 absent；`library.recentProjects` 新增两条 `/tmp/r12-omp/Untitled.lalb` 死路径
  （随 /tmp 清理，下次启动既有清扫自动摘除，不手工动）。
- **obs-1**：culling 打开会话须走「打开会话…」菜单项（⌘O = 单文件板，批前行为，
  非缺陷；`cull-omp-1.png` 留证）。
- **obs-2**：A_mertens.tif（963.5MB）解码 ~2-3min 落地（负载面，非缺陷）。
- **obs-3**：New Project 保存板 ⇧⌘G 路径键入受中文 IME 吞字影响（`probe-created.png`
  留证；切 ABC 输入源后一次通过）——走查环境面，与产物无关。
- **obs-4**：`.lalb` 无 LaunchServices 绑定（`open -n App file.lalb` 报 -10814；
  须经 File → Open Project）——批前行为，非 R12 面。
- **obs-5**：两路结论独立复现成立，无推翻项；一路 major-1（gamma F-2）维持 E 族路由，
  二路花名册（27 处）与 minor-2/3 在账未动。
- **obs-6**：产物 = 本报告 + `r12/omp/` 16 截图（含中间帧/误操作帧全留证）；
  还原干净：双实例均已退出（30436 culling / 32591 plain + 崩溃 31682），
  crash reporter 已清，tracked 零 diff，锁目录无新增。

## 四、结论

**PASS / 0 blocking + 1 major + 2 minor + 6 obs。**四笔修复忠实于 MANIFEST §R1/R2：
M-1 产线修复 + 6/0/0 回归 + 真机双 pane（含 staggered 中间态）；标记链断 writer
4/4 + no-op 让渡如实；F2-4 真窗 + ACA 深链 + ⌘, 反证；R2 卫生 + zh-audit 三路一致。
唯一 major（Import 崩溃）= M-9 在账缺陷的真机实证，非本批引入，不阻断收口，
路由并入 M-9 修复批输入。
