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
