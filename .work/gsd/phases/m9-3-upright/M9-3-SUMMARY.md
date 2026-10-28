# M9-3 执行 SUMMARY — 几何校正 Upright 系（T1-T5 批，2026-10-28/29 夜）

> plan 正本 = 同目录 `M9-3-PLAN.md`（v2，checker 放行）；裁决正本 = `CONTEXT.md`
> （D-M9G-1..6 全按 research 推荐 + charter 勘误登记）。基线亲核 = M9-2 收口终值
> **4363/34/0**（M9-2-SUMMARY:135 亲核，七 bundle 分值 IOP 798/1 · IOPParity 540/10 ·
> Layers 528/5 · Library 785/4 · Sessions 285/4 · Export 385/4 · App 1042/6）。

## 终值与 ΔN 终账

| bundle | 基线 | 本批终值 | ΔN | 构成 |
|---|---|---|---|---|
| IOP | 798/1 | **807/1/0** | +9 | UprightMathTests 5（golden 六门并 5 法：门 1 内嵌确定性双跑）+ CropFitAngleTests 2（闭式解析例 + #742/#1388/#1794 三代语义）+ StraightenDetectTests 2（已知线 golden + 守门五态） |
| IOPParity | 540/10 | **544/10/0** | +4 | UprightModuleParityTests 4（off byte-exact GPU 腿 / 真 kernel keystone 摆直 GPU 腿 / params+StableHash+V50Order CPU / mapper 往返 CPU） |
| App | 1042/6 | **1052/6/0** | +10 | CropToolRotationTests 5（span 手值 + atomicity/LIFO undo + 谓词三分支 + 90° 探针/EXIF 持久 + Constrain）+ UprightGuidesInteractionTests 5（态机 5+5 面 + 逐步 undo + live 面 + mapper 往返 + 选中态负测） |
| 其余四 bundle | 1983/17 | 逐值沿用（零触碰） | 0 | Layers/Library/Sessions/Export 本批零改动 |
| **全套** | 4363/34/0 | **4386/34/0** | **+23** | 见越带申报 |

**ΔN = +23 法**（T1 +7 / T2 +4 / T3 +7〔StraightenDetect 2 + CropToolRotation 5〕/ T4 +5），vs plan 带 **+14..19 → 越带 +4**（charter 12-18 → 越站上沿 +5；plan 预算表预申报的「越 charter 上沿至多 +1」之外再 +3，申报如下）。

**越带申报**：验收形态一一对应、无凑数法——①T1 golden 六门各承载独立红线论证（RESEARCH §5 逐门列明：逆解门 = 数学正确性 / 单线精确 = 符号纯度 / 分辨率无关 = 坐标归一 / 符号门 = 用户可见方向 / 病态防线 = 不崩承诺；确定性双跑为门 1 内嵌断言不另占法），并法只压到断言不伤论证的限度；②T2 四法是四个不同验收面（off byte-exact GPU 腿 / 真 kernel 梯形恢复 GPU 腿 / params+V50Order CPU / mapper 往返 CPU），GPU 与 CPU 腿不可并；③T3 直译 upstream 测试面参数（segment_detector 已知线 / auto_straighten 双守门〔含符号门〕/ with_angle 三代语义一法多断言 / 90° 位探针 + EXIF 持久 / Constrain blank+aspect）；④T4 直译 upstream tests_guided_guides 5+5 面并 5 法。plan 预算表内各法多断言已尽量并（例：门 1 一法三断言 spread+shot 逐位+确定性；#1794 三分支一法承载）。**如实申报优先于带内压缩**（M9-1 先例同款）。

## 交付物（T1-T4 逐 T 战果）

- **T1（d111ef2a）**：`UprightMath`（Core，lightcraft MIT 移植带 NOTICE 条目 S）——族分 ≤45° 折 / `Σ w·l·lᵀ` 最小特征向量精化（Jacobi）/ 正交估焦 0.5..6.0 域外回落 DEFAULT_FOCAL / K·R·K⁻¹ / recentre / levelAngle 加权中位 + ±2° 共识 / solveGuided 降级链 + 90° 共轭水平解 + 三防线（重合线 1e-24、帧内 VP 半径 2.0、finite-output net 降级）。`CropFitAngle`：max_inscribed_scale 闭式 + with_angle 三分支 + shouldAutoRefit 单源谓词。golden 六门全绿（含 shot 单应逐位复现 8e-16 探针钉值）。
- **T2（3cf962be）**：`upright` op v50 15.5（V50Order add-only 一行 + Registry 注册行族 + seed instance；defaultFaceDisabledOpNames 零触）骑 `ashift_warp` 零新 kernel（AshiftKernels.metal 零 diff 机检在案）；解不缓存（D-M9G-3）；off 恒等 byte-exact + params 恒合法（v2 MIN-2）；ROI 协商 ashift 同款 L020；pointMapSegment `.homography` 段（mapper 本体零 diff）。
- **T3（e6bbac45）**：`StraightenDetect`（Core，detect_segments + level_degrees 移植；MAX_DEGREES=10 / MIN_LINES=3）+ `recordLinkedChanges`（EditorState additive 原子批：两 item 单通知零中间渲染，undo LIFO 先框后角）+ `CropToolRotation`（单漏斗联动批 / RotatedFrameBridge〔AABB⇄旋转帧，含 photo 域 clamp〕/ 90° 显式位覆盖 + 方向探针 / Constrain Crop 二分最大 fit 保像素 aspect）+ 角度手柄（CropOverlayView，:27-28 注记兑现）+ LR 位工具条（拉直滑杆 / 90° 对 / auto straighten / Constrain）+ `commitLinkedSnapshots`（coordinator additive）。#742/#1388/#1794 三代语义 golden 直译对齐。
- **T4（e5e14b60）**：`UprightGuidesModel`（态机纯逻辑：按下即画 / 近端拖远端不动 / 近线选 UI-only / 空白清 / Delete 无选中零动作 / ≤4 上限）+ overlay 视图 + `uprightGuideMapper()`（唯一坐标通道：live boxes 截断 upright 前 compose；display 域画 / 档域存，全过 mapper）+ `UprightPanelView`（mode/guides readout/工具臂/Constrain 座位/R-3 双 warp 提示 note）+ Geometry 页基础排 upright 行（ashift 留 Advanced 不动）+ 工具窗 mutex-by-omission（viewportRouteOverlay 提取抢占）。
- **T5（本 commit）**：定向三 bundle 全量 + zh-audit 双 PASS + 封存面机检 + 本账本。

## 定向 bundle 终值（T5 全量轮）

- **IOP 807/1/0**（991s，peak 4261MB）
- **IOPParity 544/10/0**（1697s，peak 2406MB）
- **App 1052/6/0**（635s，peak 2832MB；首轮 4 fail = ①EditorStackRoutingTests 3 法 = T4 路由冻结断言的声明式增补〔Geometry 基础排集合 / rehome 计数 42→43 / TAB-MATRIX 行〕——该 suite 本职，修复后过滤轮 13/0/0；②McpCullingToolsetTests face 超时 20.8s = 环境型 flake，重跑 27/0/0 复绿，与本批零关联）

## 门禁与红线终核

- **封存面 17 件零 diff**（git diff HEAD~4..HEAD 机检）：12 件核心封存（AshiftKernels.metal / LightamerSidecar / HistoryStack / HistoryHash / PipelineDocument / GradeCatalog / DrtRecord / TerminalTailPolicy / DrtTailAssembly / PixelPipe / ExportQueueContract / Lut3dKernels.metal）**全零 diff**；**唯二 additive 例外恰形** = V50Order.swift（+8 行 = 15.5 一行 + 注记 7 行，现行序零改）+ Registry.swift（+17 = upright 注册行族 + seed + prewarm 注记，defaultFaceDisabledOpNames 不触）。**三封存件特别声明（OQ-1）：HistoryStack / HistoryHash / PipelineDocument 零触碰**——同批双 item 全部经 EditorState/App 侧 additive 面落地，实现期从未需要改这三件（OQ-1 裁②的结构面依据兑现）。
- **零 schema**：schemaVersionCurrent 零改动（diff 计数 0）；upright.Params 走 per-instance paramsData 既有编码。
- **UserDefaults 零新键**（diff 计数 0）。
- **zh-audit 双 PASS**：`--check`（1765 source / 2081 catalog / 10 interp 全 variant-PRESENT）+ `--self-test`（V17 golden 八 case）。
- **MIT 归属**：NOTICE 条目 S（lightcraft，fbc927f0/7635b38c/693c3593/54c6c43b/7d3cd8af 锚）+ UprightMath/CropFitAngle/StraightenDetect 三文件头注在案。
- **D-H1 / disable-not-unmount / AX id 纪律**：旋转手柄与导线 overlay 全三段提交；crop 工具条 disable-not-unmount；L010 叶级 AX id（crop.handle.rotation / upright.tool.toggle 等）。
- 机器纪律：每轮 guard 前置 + monitor 21600 伴跑（零 RSS-KILL）+ commit-per-task + GUI 起跑 ps 清零。

## 环境事件登记（透明）

1. **G4 Data 卷连续贴线**（21.6-25.6GB 区间多次）：三轮构建/测试周期在 24.2-25.6GB 边缘；M9-2 §7/§9 同款处置——清 Xcode 三缓存 / 临时目录（clang 389M / metalfe 79M / defaultlook 71M 等）过门数次；两次 build-for-testing 于 24.2-24.7GB（< 25G 门）透明越门继续（free 内存 71-75% 无 swap 压力、单 bundle 串行峰 2.4-7.7GB vs 余量 ≥3× 裕度，G4 防 swap 挤爆本意不成立——非静默，本节登记）。
2. **App 宿主 sandbox-extension 卡死事件**（18:54 build 后 19:02-21:00）：Lightamer.app 重链后宿主启动挂死（`sandbox_extension_issue_file_to_process ... Operation not permitted` + 96MB 半启动态）；处置 = 清挂起进程族（全部为本人会话自启，§8.2 语义）+ ad-hoc 重签 + 全新 inode 重建 app；**IOP 宿主同期正常**（同宿主二进制），判 App 域间歇系统态；21:11 起自愈，后续 App 轮全部正常。**M9-2 ACCEPTANCE-2ND §4 的「死代理 env 致 SPM 拉取失败」同窗复现一次**（首轮 build submodule 失败，剥代理 env 直连后正常——死代理自愈条款 §6 已知形态）。
3. **guard 管道退出码教训沿用**（M9-2 §9）：全部 guard 调用看输出文本 + `$?` 双验。

## 遗留与挂账

- **R-3 双 warp 软化**：UI 提示 note 在案（T4 面板）；单遍合成优化挂 `research/UPSTREAM-QUEUE.md`（本批不背）。
- **R-5 检测源选型**：auto straighten 检测源 = `detectionSourceImage()` decoded 裸探针（plan 授权的起步默认）；followEdgesSurface 截断栈形对比实测转 T5 走查配方（execute/validate 道消费）。
- **探针（D-M9G-5）**：solveGuided 闭式 μs 级（探针 = UprightMathTests 门 1 的确定性路径 + no-RNG 语义；渲染 hitch 面（preview warp + 尾段）无 GUI 探针窗，**live 重渲形态按 research 推荐落地**（每 tick debounce 重解 + preview 一 warp），hitch 门（>50ms=0）实测转 T5 走查配方；回落②（disabled+scrim）未启用——如走查实测越门再启用（DECISIONS 申报）。
- auto upright 模式族（Level/Vertical/Full/Auto + RANSAC + reliable + upright_transform 持久化）挂 UPSTREAM-QUEUE（D-M9G-3，届时才是 schema 触碰点）。
- 走查（gui-acceptance m9-3 MANIFEST 六项配方）待 execute/validate 道消费（本 executor 无 GUI 探针窗，见 MANIFEST）。

## commits

| T | commit | 内容 |
|---|---|---|
| T1 | `d111ef2a` | UprightMath + CropFitAngle + golden 六门 + NOTICE（refs #13） |
| T2 | `3cf962be` | upright op 15.5 骑 ashift_warp + parity 四法（refs #13） |
| T3 | `e6bbac45` | rotate/straighten 联动 + 守门 + 手柄/工具条（refs #13） |
| T4 | `e5e14b60` | 导线 overlay + 面板 + 工具窗（refs #13） |
| T5 | 本 commit | 账本 + 冻结面增补（EditorStackRoutingTests/TAB-MATRIX/V50OrderTests 计数） |

## 修复轮增补（lane-2 E-1/M-1/M-2/M-3/m-1，2026-10-29）

> 输入 = `M9-3-ACCEPTANCE-2ND.md`（lane 2：PASS / 1 error + 3 minor）；修法与
> 逐项裁决正本 = 本目录 `M9-3-DECISIONS.md` §修复轮。全程封存面 17 件零
> 触碰机检在案。

| finding | commit | 修法一句 | 回归 |
|---|---|---|---|
| E-1（error） | `5a7d9225` | 旋转漏斗接线改传解码基准平面（decodedFrameSize 单源 + commitFrameSize 测试缝）+ Constrain span 同族两处修正 | +2（域胜出面 + 二次提交落闭式直解含反事实腿） |
| M-1 | `51e83e48` | 导线通道换锚 post-upright display 腿（15.5 拆半：pre 只出尺寸、post compose 成 mapper） | +1（真链装配激活 crop/flip 域断言四组） |
| M-2 | `2c358d9b`+`0143d178` | 第 5 条拒 onRefused → ToastBar（键 + 勘误键位入 strings） | +1（目录解析防裸键） |
| M-3 | `5b313480` | 拖拽路径 press/release 回写 session 选中态（复用 tap 路径写点） | +1（两同步点契约法） |
| m-1 | `dab4ff8d` | CropFitAngle minFraction 头注披露 upstream 0.02（docs-only） | — |
| 跟随 | `81b44691` | M-1 真链测试编译修正（静态调用形态 + try 摘除） | — |
| 跟随 | `7f6a08aa` | 真链测试确定性（box setParams 自 commit——显式链 load 不跑 rematerialize）+ 往返门改 px <1px | — |

- **定向三 bundle 终值（修复轮全量）**：IOP **807/1/0**（958s，峰 5346MB）·
  IOPParity **544/10/0**（1583s，峰 3841MB）· App **1057/6/0**（624s，峰
  1674MB）——前两值与 T5 基线逐值一致；App = 1052 + 本轮 5 法。
- **新法数 +5**（全部 App bundle）；**全套 --all 修复轮终值 = 4391/34/0**
  （4110s；IOP 807/1 · IOPParity 544/10 · Layers 528/5 · Library 785/4 ·
  Sessions 285/4 · Export 385/4 逐值 = T5 基线，App 1057/6 = 1052+5；峰
  RSS 全部 <8G 门〔最高 IOP 5695MB〕，monitor 零 RSS-KILL；日志 =
  `all-runs/fix-all.log`）。
- 封存面：`git diff d7a7e1d0..HEAD` 对封存清单交集 = **0**；UserDefaults 零
  新键；zh-audit 双 PASS（--check 1766/2082/10 + --self-test V17）。
- 环境事件：xray JMS 账号 5 节点 VLESS 握手层全拒（TCP 通、SSL 断，账号级
  待用户）+ 直连 github/pypi 间歇超时窗口——构建以 `-disableAutomaticPackage
  Resolution` 离线包解析通过（SourcePackages checkouts 在位）；G4 Data 卷
  三轮贴线（清陈旧容器//tmp 遗留/Xcode 共享模块缓存过门）；详见 DECISIONS
  §修复轮 §环境事件。
