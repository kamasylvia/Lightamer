# F0P-02 SUMMARY — plan P2 执行摘要（测试族 + 等价性 + 全套三轮 + 16 面走查）

> 执行窗：2026-10-20（单 worker 会话，commit-per-task，全英文 Conventional
> Commits，未 push）。执行正本 = `F0P-02-PLAN.md`；裁决正本 = `CONTEXT.md`
> （含勘误①..⑦）；逐任务裁定 = `F0P-02-DECISIONS.md`；走查记录 =
> `.work/gui-acceptance/f0prime-p1/MANIFEST.md` §六..八（整批单卷续写，
> m-omp-7）。**执行到 P2 收口为止——C 档停，P3 未启动。**

## 0. 结论头

**P2 全任务闭环：T1-T4 四族 +22 法全绿（App bundle 943/6/0）+ T5 直启宿
主等价性 PASS（738/4/0 双轮逐值）+ T6 全套三轮同值 `TOTAL|3991/37/0|`
（带内、零 MEMFAIL、per-bundle 向量逐值钉）+ T7 16 面走查（12 ✓ / 4 ◑
卷转移或设计态 / 1 ✗ 既有缺陷双臂归因）+ D-6 绝对门定版 PASS
（0.0/0.0/0.0，A 臂 97.6 相对双证）。** 产线 commit 7 个（四测试任务 +
fix + T5 + T6）；主树 tracked 零残留。

## 1. 逐任务 commit 表

| 任务 | commit | 内容 | 验收判定 |
|---|---|---|---|
| T1 NSMenuParityTests（12 法） | `5a651b44` | 树镜像双臂 + 系统族锚 + AX 迁移集 + softproof laState + enabler 真值（undo/redo/paste 二元钉/项目族/export 恒 enabled/16 项 disarm/AI 相位）+ shortcut 双面 pin + 裸键标题门 | --filter 全绿 ✓；法数 +12 在 +8..12 带内 ✓ |
| T2 ShellGraphMigrationTests（4 法） | `0f08198c` | shared 实例身份 + 源码守卫 + columnVisibility 桥 + 值型树外写 + per-session optional | 全绿 ✓ |
| T3 MenuBridgeObservationTests（4 法） | `93b8bc96` | note-box delegate 面 + workspace 臂 arm-prime + mainMenuStomps 观察链 + re-arm 连锁 + stale backstop | 全绿 ✓ |
| T4 窗 smoke（2 法）+ 接线 | `a3d4a715` | 三窗控制器构造/挂载/复显 + Project.swift +4 行 + BUNDLE-MAP +4 行（tuist generate 恒末位） | 全绿 ✓；接线显式清单无 glob ✓ |
| （fix）run-1 findings | `53f43c4b` | 四族 run-1 9 失败全修（smoke IUO 伪象/parity 三处/swap 双重 optional/observation 缝重设计——全部测试侧，产线零 diff） | App 943/6/0 ✓ |
| T5 直启宿主等价性 | `8cc9e916` | worktree @`907c373d` + 供件 + 独立 DD vs HEAD 主树 | **738/4/0 = 738/4/0**，peakRSS 615MB 同值 ✓ |
| T6 全套三轮同值 | `b25c270b` | 三轮 `--all` 留档 + 锁协议 + run-1 错容器事故申报 | **TOTAL\|3991/37/0\| ×3** ✓ |
| T7 走查 + D-6 定版 + 收口 | （本 commit） | 16 面记录 + D-6 门定版数据 + 三臂留档 + 门① 复证 | MANIFEST §六..八 ✓ |

全波清单（git log --oneline，新→旧）：本 commit → b25c270b → 8cc9e916 →
53f43c4b → a3d4a715 → 93b8bc96 → 0f08198c → 5a651b44 → 7c456a9d（P1 收口
docs，非本 plan）。

## 2. ΔN 终账

**P2 实际测试增量 = +22**（带 +15..23 内）：NSMenuParity 12（+8..12 顶）
+ ShellGraphMigration 4 + MenuBridgeObservation 4 + 窗 smoke 2。全批 =
P1 +0 + P2 +22 = **+22** → 终值 **3991**（带 3984..3994 内；3969 基线 +
22 精确对账）。skip 37 零漂移（35 基线 + 探针族 2；第三种 skip 来源零出
现）；per-bundle skip 向量三轮逐值恒（IOP 5 / Parity 3 / Layers 5 /
Library 4 / Sessions 9 / Export 5 / App 6）。

## 3. 全套 --all 三轮数字（T6）

| 轮 | TOTAL | 秒 | IOP | IOPParity | Layers | Library | Sessions | Export | App |
|---|---|---|---|---|---|---|---|---|---|
| r1 | 3991/37/0 | 2102 | 687/5 (6849MB) | 460/3 (5865MB) | 494/5 (800MB) | 738/4 (614MB) | 284/9 (1250MB) | 385/5 (4988MB) | 943/6 (2832MB) |
| r2 | 3991/37/0 | 2136 | 687/5 (7447MB) | 460/3 (6151MB) | 494/5 (800MB) | 738/4 (614MB) | 284/9 (1592MB) | 385/5 (5353MB) | 943/6 (2832MB) |
| r3 | 3991/37/0 | 2107 | 687/5 (7645MB) | 460/3 (6201MB) | 494/5 (800MB) | 738/4 (615MB) | 284/9 (1620MB) | 385/5 (5542MB) | 943/6 (2832MB) |

exit 0 零 MEMFAIL；峰值全部 8G 机检门内（IOP r3 7645MB 最高，±3% 方差
带内）；executed/skip 向量三轮逐值相等。**run-1 事故申报**：首个 --all
launch 经 mtime-glob 拾取 T5 worktree 陈旧 pre-flip 容器（主树 T5 复建
为增量 no-op 未刷新 mtime）——杀自身脚本+宿主（parentage 面核）→ worktree
+ 容器删除 → 干净重跑三轮。教训待录 LESSONS（「worktree 等价性轮后必须
即刻拆除 worktree + 其 DerivedData 容器，防 glob 拾取」）。

## 4. 16 面走查判定（MANIFEST §六 详表）

**12 ✓**（1 启动/最近项目动态子菜单、3 网格真缩略图+EXIF、4 编辑器进出
+RAW 载图渲染、6 Inspector export 页全装配+film dispatch、7 标记 16 项
整、8 copy→paste 使能实时翻转+undo/redo 链、10 三窗全渲染、11 MCP stdio
**32 工具**亲证、14 ⌘Q 干净退出、15 全屏+Dock reopen、16 zh/en 双语菜单
栏双向 catalog、9 软打样 dispatch+无 profile 恒 OFF by-design）；
**4 ◑**（5 视口缩放 crop-route 锁=A 臂同锁设计态、12 导出实跑=m2-9 卷+
Export bundle 三轮绿、13 yiyin=单测绿+入口钮挂账、15 ⌘M AX 读限）；**1
✗ 既有缺陷**（面 2 ImportModeDialog 挂载即崩——**A 臂同法复现同签名，
双重排除 = pre-existing**，M2-9 F-1 家族 mount 腿；非翻转回归，P1/P2 不
修，入既有缺陷队列）。门① 像素/AX 复证 = 面 16 双 dump + 截图。

## 5. D-6 门定版（T7 主验收数字）

B 臂（HEAD）三轮 **0.0/0.0/0.0**（<10% 判据余量 90pp）；**d6-A-r1 =
97.6**（spike A 臂 96.0 带内复现）→ 相对门双证 −97.6pp；L082 四哨兵
3/3（frontmost true / 截图编辑器面渲染 / 主线程泊 mach_msg2_trap
4656/4655 样本 `LightamerShellMain.run → NSApplication.run` / churn 符
号族全 0）。证据 = `probe/logs/d6-{B-r1..3,A-r1}/`。三臂留档定版：A =
/tmp/f0p2-dd-A（907c373d 构建，strings 无桥符号）；B = 主 DD HEAD 构建
（D-6 门基线正本）；C = 位补齐（P1 trace 脚手架零残留；dispatch 链证据
由 parity/observation 单测承载）。

## 6. 偏差清单（6 项，DECISIONS 详节）

1. 接线拓扑：T1-T3 只落测试文件，T4 一次收口 Project.swift/BUNDLE-MAP
   （plan 头「接线收口一次」条款；T1 AC「恰 +1 行」按累计口径兑现）。
2. T3 观察 seam 重设计：metadata note box = untracked plain property
   （delegate 面驱动）；workspace 臂 = fresh-install arm-prime +
   mainMenuStomps 观察链（生产 deps 无测试缝——申报非掩盖）。
3. T5 worktree 构建的 SPM 解析：github 直连+代理双双不可达 → 主容器
   SourcePackages 播种（M7-1 代理坑的扩展形态）。
4. T6 run-1 错容器事故（杀自出进程 + worktree 拆除 + 干净重跑）。
5. 面走查 ◑ 项的卷转移判定（12/13）与 AX 读限记录（7/15）。
6. 面 2 既有缺陷双臂归因（A 臂重建用于走查归因 + D-6 相对门双证，
   一件两用）。

## 7. P3 交接注记

- P2 终态 = P3 起算基线：`TOTAL|3991/37/0|`（App 943/6）。
- 面 2 崩溃（F2-1）为既有缺陷，修复不在 P3 退役范围——按既有缺陷队列
  走（修复候选 = M2-8-3 内容面重注入范式）。
- P3 T1 退役域圈定按 CONTEXT/勘误⑦展开（statics 全列 + probe armed 旗
  标对账 + `LightamerShell.swift:2214` 重指恰一 hunk）。
- F2-2/F2-3 挂账随 SUMMARY 交接（session 空态面残留呈现 / yiyin 入口钮
  定位）。
