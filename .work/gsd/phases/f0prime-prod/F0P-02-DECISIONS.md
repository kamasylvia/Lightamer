# F0P-02 DECISIONS — plan P2 执行裁定记录

> 正本性质：plan F0P-02（测试族 + 等价性 + 全套 + 走查）执行期裁定 + 偏
> 差申报。规格正本 = `F0P-02-PLAN.md`；裁决正本 = `CONTEXT.md`（勘误
> ①..⑦）。本文只记录 plan 授权范围内的「落 DECISIONS」点与执行偏差。

## D-F0P-02-1 测试 seam 落形（T1/T3，omp M3 处方兑现记录）

1. **树遍历缝（T1）**：fresh `NSMenuBridgeController()` + stub Deps（8
   状态对象真值 + ~40 空闭包）+ internal `install(deps:)` 装配（写
   NSApp.mainMenu）→ mainMenu 遍历 + `item.isEnabled/.state` 读回 +
   `validateMenuItem` 探针；**隔离 = 每法 save/restore NSApp.mainMenu**
   （repo-precedent defer 形——tearDown override 为 nonisolated 不可触
   主 Actor 面，Swift 6 严格并发亲证）。itemActions/itemEnablers 不直读
   （private 红线维持）——动作捕获改走 T3-4 的 sendAction 全链。
2. **测试隔离形态落 DECISIONS（omp M3 要求）**：如上 save/restore +
   fresh 实例；单例 note 盒仅 T3 触（armHarness/disarmHarness）。
3. **观察适配器 seam 重设计（T3，deviation）**：测试宿主内 app main 先
   于测试运行——生产 face 已 install 共享单例（生产 Deps 的状态对象为
   shell controller 私有，无测试缝）。可达面拆两半：
   - **metadata note box = untracked plain property**（armObservation
     的 17 读中该读不注册观察——by-design：其生产刷新驱动 =
     menuNeedsUpdate delegate 调用）→ 测试驱动 delegate 面本身。
   - **workspace 臂 = tracked @Observable 腿**，但仅「note 之后运行的
     arm 周期」注册 → 测试以 fresh-install 为 arm-primer（armObservation
     读 SHARED workspace 盒）→ 变异经 F1 臂 onChange →
     shared.refreshAll（NSApp.mainMenu=F1 树 → **mainMenuStomps +1 =
     派递回执**）→ shared.armObservation 重武装（仍读 shared 盒）→ 后
     续变异逐个派递 = **re-arm 连锁**（T3-2 改形 (a) 的间接覆盖，omp M3
     推荐案行使；「恰一次调度」回执 = stomp 计数严格递增断言）。
   - 17 读集的 deps 组 11 读与生产 deps 同机制（同一 armObservation 块
     ）——生产对象不可达为**申报事实**（非静默吸收）；机制级覆盖由
     workspace 腿 + note-box 腿承载（plan「sample 字段子集驱动全流程」
     条款行使）。
4. **paste 族二元钉（T1，勘误③/⑦ AC 承接）**：`testPasteFamilyBinary-
     EnablerWithoutHoldsControl`——hasPayload 置位后 acquire 持锁 → 粘
     贴/部分粘贴恒 enabled ✓（无 holdsControl 合取）；holdControl 合取
     族 = undo/redo + New/Open Project 分测钉死。

## D-F0P-02-2 run-1 失败归因与修复（fix commit `53f43c4b`，全测试侧）

| 失败 | 根因 | 修法 |
|---|---|---|
| smoke ×5 | `type(of:)` 过 NSView! IUO 恒印 `Optional<NSView>`（IUO 语义，独立 AppKit 探针复现）——**窗口实际挂载成功** | bind 后读具体类型名 contains("NSHostingView") |
| parity 首菜单断言 | items[0] = app-menu HOLDER（bundle 名），非 About 项 | 断言 holder.submenu 首项 hasPrefix("About ") |
| parity editor-无图腿 | `openEditor(imageID: nil)` 不清除已设 id——无图编辑态只存在于首载前 | 腿序重排（无图腿先行） |
| parity color 快捷键 | color 族键 = 槽位号（clear=⌘0 … color_5=⌘6），本地化标题 "(⌘N)" 同值 | pin 改槽位号 |
| graph swap | 双重 optional 与单层比较 | flatMap 展平 |
| observation ×3 | D-F0P-02-1.3 缝事实 | 重设计如上 |

App bundle run-2 = **943/6/0**（921+22，skip 6 零漂移）。

## D-F0P-02-3 T5 等价性数据 + 构建环境

- **Round A**（pre-flip，worktree @`907c373d` + 供件 `input/` 314MB +
  `Resources/AIModels` 194MB——m-omp-6 步）：Library **738/4/0**
  peakRSS 615MB；**Round B**（HEAD 主树复建）：**738/4/0** 615MB——
  Executed/failed/skip 逐值相等 + 峰值同值 → **等价性 PASS，--all 放行
  **。DEBUG fork 序零触旁证：McpHost 族在 T6 三轮全绿（--all 覆盖）。
- **SPM 解析环境（M7-1 坑扩展）**：github.com 直连超时 + 代理 daemon 停
  → worktree 新容器无法 clone libwebp 子模块 → **主容器 resolved
  SourcePackages（156MB 含子模块 checkout）ditto 播种 worktree 默认容器
  ** → 零网络 generate + build。独立容器红线维持（未共享）。
- mtime-glob 副作用教训：worktree 构建使其容器成为 newest → **T6 首轮
  拾取错容器**（pre-flip 二进制 + 无 P2 测试，IOP skip 5→11 即此伪象）
  → 杀自出脚本/宿主（`ps -o ppid` parentage 面核，M2-7-3 纪律）→ 拆
  worktree + 容器 → 干净三轮。**LESSONS 候选：等价性/worktree 轮收尾必
  须同批拆除 worktree + DerivedData 容器。**

## D-F0P-02-4 T6 三轮同值账 + 锁协议

三轮 `TOTAL|3991/37/0|`（2102s/2136s/2107s，exit 0，零 MEMFAIL）；per-
bundle executed/skip 向量三轮逐值相等（m-omp-8 向量钉）；skip 37 零漂移
、第三种 skip 来源零出现；峰值 IOP r3 7645MB 最高（8G 门内，±3% 方差带
）。锁协议 = `/tmp/f0p2-all-runs/all.lock` 自建锁文件贯穿三轮；运行中
巡检 = Lightamer 进程 ps + ru_maxrss 机检（脚本内置 MEMFAIL）+ parentage
核查。批准 = orchestrator 预批（任务指令）兑现。

## D-F0P-02-5 T7 走查裁定（面级）

1. **面 2 = 既有缺陷双臂归因（本轮最重要发现）**：ImportModeDialog 挂
   载即崩（`No Observable object of type AgentControlCoordinator`，
   ips 064532/065317 同签名）；**A 臂（pre-flip 907c373d）同法复现同签
   名** → 载体非壳交接（翻转窗排除）。归属 = 既有缺陷队列（M2-9 F-1 家
   族：cancel 腿 + 本轮 mount 腿）；修复候选 = M2-8-3 内容面重注入范式
   （sheet 挂链处补 environment 或 dialog 自足）——**P2 不修**（plan 窗
   外 fail = 停手归因上报 routing；不入 P3 退役范围）。
2. **面 16 门① 双语复证**：zh 系统（File, Edit, 显示, 标记, 图像,
   Window, Help）vs en 强制（File, Edit, View, Metadata, Image, Window,
   Help）——自定义组双向 catalog 本地化 ✓；File/Edit/Window/Help 桥字面
   量 = **D-F0P-01-5.4 已登记差异维持**（zh 侧呈英文；翻案 = 桥侧改走
   系统本地化串，后置微任务）。
3. **面 11 = 32 工具亲证**（m-omp-1 勘正数；initialize → tools/list →
   32，名单在走查 stdout）。
4. **D-6 定版**：B 三轮 0.0 + d6-A-r1 **97.6**（A 臂重建 = 走查归因与
   相对门双证一件两用）；四哨兵全过；三臂留档（A/B 二进制 strings 身份
   亲核；C 位补齐 = P1 trace 零残留 + 单测承载 dispatch 证据）。
5. **卷转移项**：面 12 导出实跑（m2-9 卷 + Export bundle 三轮绿）、面
   13 yiyin（单测绿 + M3-1 卷；翻转后编辑器工具条未见入口钮 = 挂账
   F2-3）；**AX 读限记录**：面 7 disarm 聚焦态无法可靠建立（机检面 =
   parity note-box 腿）、面 15 ⌘M minimized 读数不确定（Dock reopen
   腿 ✓）——均非功能 fail，记录为测量限制。
6. **F2-2**：⌘E 空态编辑器呈 legacy Session 空态面（选择文件夹以创建
   会话）= M2-2 剥离门残留呈现，设计态挂账。

## 偏差申报（行内 (deviation) 标记累计）

- **(deviation)-1**（T4）：接线拓扑 = T1-T3 纯测试文件 + T4 一次收口
  接线（plan 头「接线收口一次」条款行使；T1 AC「恰 +1 行」按 T4 终态
  累计口径兑现——四文件各恰 +1 行 + BUNDLE-MAP 各恰 +1 行）。
- **(deviation)-2**（T3，`93b8bc96`）：观察测试缝重设计（D-F0P-02-1.3
  ）——metadata 腿走 menuNeedsUpdate delegate 面、workspace 腿走
  arm-prime + stomps 回执；17 读集 deps 组以机制级覆盖 + 不可达申报承
  接（omp m-omp-2 终值条款维持 17 无改）。
- **(deviation)-3**（T5，`8cc9e916`）：SourcePackages 播种构建法（网络
  双断环境的零网络解析；独立容器维持）。
- **(deviation)-4**（T6，`b25c270b`）：run-1 错容器事故 + 杀自出进程 +
  拆除重跑（LESSONS 候选登记）。
- **(deviation)-5**（T7）：面级卷转移/AX 读限判定（5 项，D-F0P-02-5.5
  ）；face-5 mask/segment 深度验证仍为后置（与 P1 同注记续挂）。
- **(deviation)-6**（T7）：A 臂重建一件两用（走查归因 + D-6 相对门双证
  ）；d6 驱动 = P1 脚本派生（/tmp/f0p2-d6-driver.sh，B×3 + A×1）。
