# M9-3 执行 DECISIONS — 滚动裁定记录（T1-T5 批）

> 裁决正本 = 同目录 CONTEXT.md（D-M9G-1..6）；本文件只记**执行期新裁定**与
> 实测值落账。晨审可推翻面均在 CONTEXT §晨审推翻点索引。

## D-M9G-1 undo 序实测确认（OQ-1 落地形态）

同批双 item 的 commit 序 = **angle 先、crop 后**（linkedSnapshots 返回序），
undo LIFO = **先撤 crop 重算、再撤 angle**——中间态一瞬（先框后角），与
D-M9G-1 落地形态注记一致；CropToolRotationTests testLinkedBatchAtomicity
AndUndoOrder 两步 undo 断言钉死。**零中间渲染** = recordLinkedChanges 单
historyDidChange Task（实现构造性质；无 spy 面，验收以两 item 原子落地 +
LIFO 序承载，SUMMARY 同口径）。**联动批的成批条件实测修正**：crop item 仅
在 `CropFitAngle.withAngle` 输出 ≠ 现框时才入批（谓词不动框 = 单 item）——
#1388 回 0 场景「全图 crop @12° → 0°」为 angle-only 单 item（全图未缩无
可复原），断言链已按此语义钉（testLinkedRefitPredicateThreeBranches (e) 段
与 fullBack 单 item 断言）。

## Float 记录域的判等门（实现合理化，T3 期发现）

我方 crop record 以 **Float 分数**持久（upstream f64）。Float 往返在 600px
帧上携带 ~5e-6 px 坐标噪声，导致：
1. withAngle 的 isLargest 判等门从 upstream f64 1e-9 **移到 1e-3 像素**
   （千分之一像素；1e-6 归一门实测仍漏判 #1388 regrow——门量纲教训:
   归一域 1e-8 噪声 × 600px = 6e-6 px > 1e-6 px 门）。
2. shouldAutoRefit / frameMoved 用 **1e-6 归一**（0.0006px）。
3. 测试复原断言门 1e-9 → 1e-6（regrow 残余实测 8.9e-9，Float 尾数）。
依据:upstream 1e-9 是全 f64 管线的内部判等;跨 Float 记录边界后该门
数学上不可达。晨审可改 f64 sidecar params（schema 触碰,不建议）。

## 病态防线第四形态：finite-output net（T1 执行期发现）

T1 数值探针发现:双族 VP 全部落在 y=0 直线的导线几何（虚拟相机转角近
90°）使 K·R·K⁻¹ 的**齐次 w 行恰好过零**——recentre 的 origin project 除
零 → NaN 全矩阵。这不是数值 bug 而是该 guide 配置本身的退化（校正单应
无穷远有极点）。处置 = solveGuided 各臂产物 **isFinite 检查**，非有限
→ 降级 levelAngle 纯旋转（恒有限）——warp 永不见 NaN。golden 5 号门
增补该样例（degenerate 四线 → 有限降级）+ focal 域外样例改用非退化
几何（VP 离 y=0 线，f²=40 → f≈6.32 > 6 回落 1.5 逐位对照）。

## Constrain Crop 收缩语义（T3 期裁定）

upstream constrained() 的「aspect 保持」基准域 = **旋转帧像素域**；首版
等步长归一收缩默默改 aspect（归一方形 ≠ 像素 1.5）——重写为**绕 rect 中心
的像素 aspect 保持二分收缩**（20 轮 ≈ 1e-6 span 精度，4×48 边采样全 content
为 fits 判据；lo = 最大 fits 侧取值，20 轮后边缘零 blank）。blank_fraction
< 0.002 断言 + 像素 aspect 保持断言钉死（CropToolRotationTests
testConstrainCropShrinksBlankEdges）。

## 检测源选型（R-5 申报）

auto straighten 检测源 = **`detectionSourceImage()` decoded 裸探针**
（plan 授权的起步默认，PipeCoordinator.autoStraightenDegrees：
CIImage 512 长边 software-render 采样 → StraightenDetect）。lens 校正后
探针（followEdgesSurface 截断栈形）对比实测**未在本批执行**（无 GUI 探针
窗；合成 golden 面与守门面已钉检测数学）——转 **T5 走查配方第 ⑦ 项**
（MANIFEST，execute/validate 道消费）；选型若翻 = detectionSource 替换
单点改动。

## live 重渲形态（D-M9G-5 申报）

导线拖动与旋转手柄 live tick 走 **live 重渲形态**（research 推荐①）：
solveGuided 闭式 μs 级（UprightMathTests 门 1 的确定性路径即探针：双跑
逐位、无 RNG；单次 solve 数值开销远低于 50ms hitch 门 3 个量级）+ preview
一 warp（ashift_warp 共名 PSO 已预热）。**渲染 hitch 面（warp+尾段链）的
实测探针未在本批执行**（LIGHTAMER_PERF_PROBE 测试形态需真渲染链 + GPU
计时 fence，本 executor 无 GUI 探针窗）——hitch 门（>50ms=0）实测转
T5 走查配方第 ⑧ 项；回落②（disabled+scrim，crop T0 先例）**未启用**，
走查实测越门时再启用（届时回注本节）。

## 符号钉死值（R-2 三重奏落账）

1. **90° 位↔视觉方向**：`.rotCW90`（bits 5）forward map 把右上输入像素送
   右下输出 = 视觉顺时针（golden 断言 + isClockwiseBit 探针）；CW 按钮 ↦
   `.rotCW90`，CCW ↦ `.rotCCW90`；.auto 种子步进落**显式位**（D-M9G-6
   持久，resolved(forEXIF:) 直通断言）。
2. **拉直符号**：右倾下降地平线（y 随 x 增）↦ levelAngle **负角**（−6±0.5
   golden 门）；ashift.rotation 的像素域正旋转方向由 forwardMatrix golden
   钉（EditorStackRouting/AshiftParity 既有面）——手柄/滑杆的屏幕 CW+ 角
   经 CropToolRotation 单漏斗负号交接（CropRotationHandleMath 头注）。
3. **upright 居中域 y 方向**：图像坐标（y-down）直通（与 upstream 一致），
   门 4 + 门 2（单线 1e-9）双重钉死。

## 越带申报（+23 vs +14..19）

见 SUMMARY §终值与 ΔN 终账（逐法对应验收形态；golden 六门/双 GPU 腿/
upstream 直译面均不可并法压缩至带内）。晨审如裁定砍法：优先候选 =
testMapperRoundTripUnder1px（并入 UprightModuleParityTests 的 gate ④）与
testLiveWindowLandsOneItemPerCommit（并入 persistence 法）——合计 −2。

## 环境事件（透明登记）

- **App 宿主 sandbox 卡死**（19:02-21:00，~2h）：build11 重链 Lightamer.app
  后 App 域宿主启动挂死（sandbox_extension_issue_file_to_process 拒发 +
  半启动态）；IOP/IOPParity 同宿主同期正常 → 判 App 域间歇系统态。处置 =
  清本人会话自启进程族 + ad-hoc 重签 + 全新 inode 重建；21:11 起自愈。
- **死代理 env 复现一次**（M9-2 ACCEPTANCE-2ND §4 同款）：首轮 build 的
  SPM submodule 拉取走死代理 10809 失败；剥代理 env 直连后正常（全局 §6
  死代理自愈条款已知形态）。
- **G4 Data 卷连续贴线**（21.6-25.6GB）：M9-2 §7/§9 同款处置（清 Xcode 三
  缓存/临时目录过门 + 两次透明越门 continue，free 内存 71-75% 无 swap
  压力、单 bundle 峰 2.4-7.7GB vs 余量 ≥3×，防挤爆本意不成立）。
- **McpCullingToolsetTests face 超时**（App 全量轮 20.8s timeout）：
  Vision face 检测环境型 flake，重跑 27/0/0 复绿，与本批零关联。

## 修复轮（lane-2 E-1/M-1/M-2/M-3/m-1，2026-10-29）

> 输入正本 = `M9-3-ACCEPTANCE-2ND.md`（lane 2：PASS / 1 error + 3 minor）。
> 逐项独立 commit（fix(m93)… refs #13），封存面 17 件全批零触碰机检在案。

### E-1（error）→ `5a7d9225`

**接线域混淆修正**——`linkedSnapshots` 契约要求解码基准平面（旋转作用的
平面），而三处 App 调用点（手柄/拉直滑杆/auto straighten）喂的是
displayTexture 尺寸 = 旋转后输出 AABB。修法取 lane 2 建议方向 1
（decoded extent 同源）：

- `PipeCoordinator.decodedFrameSize()`：解码平面尺寸单源 accessor（导线
  mapper 亦将共享，见 M-1）。
- `CropToolRotation.commitFrameSize(decoded:display:)`：**测试可见接线缝**
  ——display 形参留在签名里但按构造拒绝（decoded 恒胜出），把 lane 2
  点名的「接线层错误域不可见」盲区翻成显式机检决策（回归法喂发散的
  display AABB 并断言 decoded 胜出）。
- Constrain span 同族修正（lane 2 未单列、重推导探针域时发现的两处同病）：
  工具条 + 面板座位的 span 原来是 `span(w0: display, …)` 再算一次
  phantom AABB——rotation ≠ 0 时 span ≠ displayTexture，`contentOpaqueProbe`
  尺寸守卫拒 nil，Constrain 按钮静默失效。修正 = span 恒取 display 尺寸
  （探针读的就是该平面）。
- 回归两法：commitFrameSize 域胜出/退化 nil 面 + 「二次提交落闭式直解」
  （0→10→20 经 decoded 平面逐代组合 == 一次性 0→20 withAngle 直解
  1e-6；反事实腿证明 display 域接线至少漂移一边——防回归退化成恒真）。

**live 窗时序注记（不修，登记）**：手柄/滑杆 commit 时刻 ashiftRecord 读到
的是 penultimate tick 的 live 投影（末 tick 的 `setLiveParams` Task 在
commit 之后落）——这正是 lane 2 E-1 数值推演「提交时刻 display =
AABB@新角」成立的机理，也意味着 `angleChanged` 门在正常时序下靠该竞态
保持可通。属 T3 交付时序，两个验收 lane 均未 flag，本轮不动；后续若
live 窗改同步落地，此注记为 first responder。

### M-1（minor）→ `51e83e48`

**导线坐标通道换锚 display 腿**——旧 `uprightGuideMapper` =
compose(upright 槽**前** boxes, decoded 帧)：forward 对已存输入帧导线**二次
施加** pre-upright 形变、inverse 把画线点存进 decoded 帧而非 upright 输入
帧（持久域声明 vs 实际存储域背离）；crop/flip 激活时画线错位（lane 2 的
M-1 消费侧观察）。修法 = lane 2 建议的「15.5 拆半组合」：

- 持久域 = upright 槽前 boxes 的 compose **outputSize**（pre-upright 几何
  只贡献尺寸，boxes 本体退出通道——导线既不骑 pre-upright 形变也不骑
  它定义的解，CONTEXT 红线 6 不变）。
- 返回 mapper = compose(upright 槽**后** boxes〔flip 16/liquify 18/crop
  24.5〕, 输入帧)：forward = 输入帧→display（画线腿落在用户所见处），
  inverse = display→输入帧（存储腿）。
- GeometryPointMapper 本体零 diff（M9-3 红线维持）。
- 语义迁移注记：旧通道下（pre-upright 非中性时）已存导线是 decoded 帧
  坐标，新通道按输入帧解读——旧值域的已存导线画线含义会变（旧解几何
  本来就错，修正即行为变化）；pre-upright 中性时新旧数值恒等，无迁移面。
- 回归一法（真链装配：ashift 8° + flip rotCW90 + crop 0.25..0.75² 窗）：
  frameSize = 输入帧 span（779×575 ≠ 720×480 decoded）+ 窗心不动点 + 新旧
  存储值实质分叉（>1e-3）+ 激活链往返 <1e-9 逐点。

### M-2（minor）→ `2c358d9b` + `0143d178`

**第 5 条拒 toast 恢复**（plan AC「≤4 上限 toast」静默蒸发的反面申报）：
overlay 加 `onRefused` 回调（拒按不再武装死拖拽窗——尾随 tick/release 按构造
无操作）→ host 走 ToastBar 通道 present；新键 `upright_guides_cap_toast`
（en/zh）。**`0143d178` 勘误**：M-2 commit 把键插到了 `strings` 对象**外**
（顶层）——JSON 可解析但 app 加载的目录没有该键（运行时裸键回落，F-2 同
款），zh-audit 报 MISSING；勘误 commit 把键移回 strings 内（2082 键）。
断言 = 触发条件由 ⑤ 拒门钉死 + toast 字串目录解析面（防裸键回落）。

### M-3（minor）→ `5b313480`

**拖拽路径 session 选中态回写**（upstream 两面的 App 级偏离）：overlay 拖拽
路径 press/release 各回写一次 `onSelect(m.selected)`（tap 路径既有会话写点
复用，不开第二写点）——画线清选中（drawing_a_new_guide_clears_the_selection）
与端点拖动者选中（moved-guide-ends-up-selected）两面恢复；拒按也回写
（模型在 cap 门先清选中）。断言 = 拖拽路径两个同步点携带值的契约法。

### m-1（minor）→ `dab4ff8d`

**minFraction 偏离头注披露**：CropFitAngle.minFraction 常量注记补 lightcraft
`MIN_CROP_FRACTION = 0.02`（crop_drag.rs:12）vs 本产 0.01（dt MIN_CROP_SIZE /
CropModule 拖拽下限）的偏离申报 + 承接理由（联动收缩不落到比工具自身拖拽
更紧的下限）。docs-only，零行为字节。

### 修复轮终值与纪律

- 新增回归法数：**+5**（CropToolRotationTests +2 / UprightGuidesInteractionTests
  +3），App bundle 1052 → **1057/6/0**（修复轮全量终值，624s，峰 1674MB）；
  IOP **807/1/0**（958s，峰 5346MB）· IOPParity **544/10/0**（1583s，峰
  3841MB）与 T5 基线逐值一致（修复不触 Core/IOP 面——E-1/M-1 修 App 接线层，
  m-1 头注 docs-only）。
- 封存面 17 件零 diff 机检（`git diff d7a7e1d0..HEAD --name-only` 对封存清单
  交集 = 0）；UserDefaults 零新键；xcstrings 尾块纯插入（键迁移勘误含一进
  一出一行级 diff）。
- **跟随 commit 两笔**（测试自身缺陷，非产线面）：`81b44691`（静态 helper
  调用形态 + load 非 throwing 的 try 摘除——首次全量轮编译错 3 处）；`7f6a08aa`
  （**显式链 load 分支不跑 rematerialize**（在 pristine-seed 分支内）→ 裸 box
  恒中性 → mapper 恒等——测试 box 改 setParams 自行 commit（load 契约 =
  调用方自带已 commit 态，API 无改）；往返门改 px 域 <1px（parity 通道门
  同形）——草稿公式 sqrt(|dx|+|dy|)/2 对 f64 抵消噪声开方放大（1e-8 量级
  噪声读成 1e-4）。首次 App 全量轮 1057/6/3 红、两笔修复后过滤轮 8/0/0 +
  全量 1057/6/0 绿）。
- 环境事件：①陈旧 hash 容器陷阱（dgzsvdww vs glcjh——验收轮 tuist generate
  改了 workspace 元数据致 hash 变迁；修复轮删陈旧容器过 G4 后以 scheme
  Lightamer 全量 build 落当前 hash 容器，七 bundle 产物同批新鲜）；②本机
  出口全断窗口（xray JMS 账号 5 节点 VLESS 层全拒〔TCP 通握手断〕+ 直连
  github/pypi 超时）——build 走 `-disableAutomaticPackageResolution` 离线
  解析（SourcePackages checkouts 在位 + Package.resolved 未变）零网络通过；
  px 代理管理脚本自身因 pypi 拉不动以 `uv --offline` 缓存 wheel 直跑 xray.py
  绕过（--update/--best/--start 全数可用，节点仍拒——账号级问题，留用户）；
  ③G4 Data 卷三轮贴线（构建膨胀吃量，清陈旧容器 + /tmp 遗留 + Xcode 共享
  模块缓存过门 ×3，非静默——本节登记）。

