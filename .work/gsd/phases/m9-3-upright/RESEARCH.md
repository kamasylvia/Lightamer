---
phase: M9-3
status: drafted
date: 2026-10-25
author: M9-3 researcher (零 commit 批)
---

# M9-3 RESEARCH — 几何校正 Upright 系（上游测绘 / 我方盘点 / 差距矩阵 / 方案骨架）

> 任务源：ROADMAP §M9（站 3）+ REQUIREMENTS M9GEO-01..02 + `research/M9-CHARTER-INPUT.md` §2.3
> （charter 已按推荐生效；上游 = lightcraft origin/main，MIT OR Apache-2.0 可移植带归属）。
> **本批最重要勘误**：charter §2.3「v50 序无对应 iop」**不成立**——我方 `ashift`（v50 slot 15.0）
> 已在默认 seed、已挂 Geometry 页 Advanced 组、已带 ±45° 旋转 + 透视 + Metal warp + Vision
> auto-detect 面板。真缺口比 charter 描述**窄且深**：crop 工具面旋转/拉直联动 + Guided Upright
> 导线系全缺。方案量级从「rotate 基座新建」翻转为「既有件扩展 + 导线系新建」。

---

## 1. 任务与范围

- **M9GEO-01** rotate/straighten：自由旋转 + 拉直 + 90° 步进 + 裁切框联动（旋转后框重算）。
  验收形态：旋转 90/任意角 golden + sidecar 持久化 + 视口交互探针。
- **M9GEO-02** Guided Upright：画线 + 拖端点 + 求解 + 应用（lightcraft upright.rs MIT 移植 +
  M5-3 Pano homography 复用）。验收形态：合成梯形畸变恢复 golden（已知单应逆解误差门）+
  参考线交互探针。

---

## 2. 上游测绘（lightcraft origin/main，HEAD..origin/main = +1031 在 fetch 内）

### 2.1 `crates/pipeline/src/upright.rs`（634 行，charter 记 611——已有增量）

数学形态三段（全程 **f64**；栅格缓冲 f32）：

1. **线段检测 `detect_segments(lum)`**（:76-198）：σ0.8 高斯 → Sobel 梯度 → level-line 角
   （梯度+90°，mod π）→ 自适应阈（幅值 p90×0.35，下限 0.008）→ 最强种子区域生长
   （倍角均值取向，容差 22.5°，区域 ≥12px）→ 加权主轴拟合（加权质心 + 二阶矩
   `θ = 0.5·atan2(2sxy, sxx−syy)`）→ 区域投影取端点；长度 ≥0.04·长边且长宽比 ≥5 才收。
   输出**居中归一坐标** `(p − centre)/(longEdge/2)`，分辨率无关。
2. **消失点 `vanishing_point(segs)`**（:275-308）：确定性 RANSAC——按长度取前 60 段、全对
   采样、线对叉积 = 候选 VP（齐次）、1.5° 角误差阈记分（得分 = 内点总长）；精化 =
   `refine_vp`：`Σ w·l·lᵀ`（w = 线长，l = 归一化线向量）**最小特征向量**（Jacobi 旋转 50 轮、
   收敛 1e-15）；内线阈 2×thr、≥2 条内点才返回。
3. **求解 `solve(mode, Analysis)`**（:465-504）：虚拟相机旋转 **`K·R·K⁻¹`**（transform.rs
   `rotation_homography`）+ `recentre`（中心不动 + 原点 Jacobian 行列式开方归一尺度）：
   - **Level** = 纯 Z 旋转 `level_angle`：长度加权中位偏角 + 共识门（≥50% 线长在 ±2° 内），
     水平族优先（线长 ≥ 垂直族 0.5 倍即用水平）。
   - **Vertical** = 垂直 VP 方向 → y 轴（Rodrigues `rotation_between`）。
   - **Full** = 垂直→y + 水平→x（Gram–Schmidt）；焦距由两有限 VP **正交性闭式**估
     `f² = −(vx·hx + vy·hy)`（`focal_from_vps` :367-374，接受域 0.5..6.0，VP 在无穷远
     〔v[2]≈0〕返回 None → 回落 DEFAULT_FOCAL=1.5 = 半长边单位 ≈ 27mm/36mm 画幅）。
   - **Auto** = 防呆级联：垂直族隐含的 roll 须水平族确认（≤3° 或水平 level 角一致 ≤3°，
     否则视为场景结构〔圆锥树侧翼〕递归降级）→ full（旋转 <20°）→ vertical（<25°）→
     level（≤5°）→ identity。
   - **Guided `solve_guided(guides)`**（:508-539）：**≤4 条用户导线解同一问题**——按
     `tilt_from_vertical ≤45°` 分垂直/水平族；同族 ≥2 条 → `refine_vp`（跳过 RANSAC，
     导线即内点）；双族 → solve_full + 正交估焦；仅垂直 → solve_vertical；仅水平 →
     问题旋转 90° 解完转回（`(x,y)→(y,−x)` 共轭）；单条/无 → level_angle 纯旋转。

**可靠性与防呆防线**（`reliable` :438-452；`STRAIGHTEN_MAX_DEGREES=10.0` /
`STRAIGHTEN_MIN_LINES=3` :583-587，实测 68 张 LR 手工拉直 + 300 张原样片标定）：
VP 须 ≥3 内点、内点总长 ≥0.5（半长边单位）、横向散布 ≥0.4、≥60% 族线长一致
（镜像侧翼〔树/山峰〕拒判）；**VP 落在帧内半径 <2.0 = 场景特征〔逆光射线/道路〕拒绝**
（相机倾侧 VP 必在帧外远处）。auto straighten 仅 ≤10° 且 ≥3 一致线才转、找不到明说。

**分析源 `analyze_source`**（:544-577）：**lens 校正后**（optics 应用、geometry/crop 归零）
长边 1024 采样；亮度归一到 p99 白 + `powf(1/2.4)` 感知化；结果按源指纹 ^ optics+orientation
哈希缓存（Mutex 8 条）。

### 2.2 配套件（file 级）

| 件 | 出处 | 形态 |
|---|---|---|
| `transform.rs`（89 行） | `crates/pipeline/src/transform.rs` | `DEFAULT_FOCAL=1.5`；`rotation_homography(r,f)=K·R·K⁻¹`；`recentre`（中心钉住 + 数值 Jacobian 面积归一）；manual 滑杆族（vertical/horizontal ±100 → ±0.5rad 虚拟旋转、rotate、aspect、scale、offset）合成单应 |
| `Geometry` struct | `crates/develop/src/settings.rs:763-806` | `upright` 枚举 Off/Auto/Guided/Level/Vertical/Full + `guides: Vec<(Point,Point)>`（≤4，lens 校正后定向帧归一坐标）+ `upright_transform: Option<Homography>`（**自动模式解缓存持久化**——预览/导出字节一致）+ manual 滑杆 + `constrain_crop: bool` |
| `CropGeometry` | `crates/geom/src/crop.rs:13-` | **拉直角挂在 crop**：`{rect 归一, angle −45..45}`；`with_angle()` = **角度设置单漏斗**（旋转手柄/滑杆/角度输入框/crop.straighten/develop.set 全走它——issues #742/#1388/#1794 三代 UX 坑的收敛）；`constrained()`/`crop_fit_angle` = 最大内接矩形闭式（Constrain to image / 角度回 0 框回长） |
| 渲染应用 | `crates/pipeline/src/geometry.rs` | **全几何单遍重采样**：orientation + lens warp + 透视单应 + crop 旋转 affine + flip 合成一个采样变换（`Frame`/`Warp`），**一次 resample**（无多次插值损失）；采样 = f32 bilinear + 下采样时 Mitchell 预滤波（:252-264）；旋转在 CPU 逐像素逆映射 |
| Constrain Crop | `54c6c43b`（commit） | keystone 后黑边收缩：crop 中心收缩 + 平移直到 48×4 边采样点全在源内（`geometry.rs constrain_to_image`）；测试 = blank_fraction <0.002 |
| Guided UI 交互 | `fbc927f0`（merge PR #2347）+ `7635b38c`；`crates/ui-egui/src/tests_guided_guides.rs`（5+5 法）+ `panels/detail.rs` | **按下即画**（新导线起于按压点）+ 拖端点（近端跟随指针 1e-3、远端不动）+ 点线旁选中（白/加粗/大端点）+ 点空白/画新线/离图离工具清除 + Delete/Backspace 只删选中（无选中零动作零 undo）+ **选中态 UI-only（serde skip，不入档）** + 导线本体入 settings（每编辑一步 undo）+ ≤4 条（`take(4)`） |
| auto straighten 防呆 | `693c3593`（LR-CROP-AUTO） | `level_degrees` = crop 面板 Auto straighten 直返角度；**符号约定**：右倾下降 6° 地平线 → **−6°**（crop angle 顺时针正） |
| XMP 互操作 | `7d3cd8af` | Upright warning 模式跨导入路径保留（sidecar 细节，注记级） |

### 2.3 上游测试形态与精度门（`crates/pipeline/src/tests_geometry.rs`，526 行）

| 测试 | 形态 | 门 |
|---|---|---|
| `segment_detector_finds_known_lines` | 合成三条已知角暗线 | 方向误差 <0.7°、长度 ≥0.6×真值 |
| `upright_vertical_fixes_converging_verticals` | 已知 keystone（vertical:35 + roll −2°）合成网格 + 逆解 | 三条竖线 x 迹 spread <1.2px、水平 <1.5px（720×480） |
| `upright_level_straightens_a_tilted_horizon` | rotate:3.5° 合成网格 | 水平迹 spread <1.2px |
| `upright_full_fixes_both_families` | vertical:25 + horizontal:−25 双 keystone | 双族 spread <1.5px |
| `guided_upright_from_two_vertical_guides` | keystone 逆图上沿真实竖线（经 H⁻¹ 映到归一坐标）画两导线 | 竖线 spread <1.2px；**单条垂直导线 → 纯旋转，导线端点 x 差 <1e-9（精确）** |
| `upright_analysis_is_resolution_independent` | 1200×800 vs 600×400 | 四角位移差 <0.006（居中单位）；**lazy（无缓存变换）与 stored 渲染逐字节一致** |
| `upright_auto_leaves_natural_scenes_nearly_alone` | 自然场景库回归 | Auto 四角位移 <0.06（不发明透视） |
| `level_degrees_sign_matches_crop_angle` | 右倾 6° 地平线合成 | 报 **−6° ±0.5** |
| `auto_straighten_needs_more_than_one_line` | 单边线（无带纹）→ None；地平线+带纹 → −4°±0.5 | ≥3 线共识实锤 |
| `auto_straighten_leaves_steep_lines_alone` | 20° → None；8° → −8°±0.5 | ≤10° 门实锤 |
| `manual_transforms_straighten_known_keystone` / `constrain_crop_removes_blank_areas` | 逆变换合成 + 未校正对照必须真畸变 | spread <1px；blank <0.002、aspect 保持 |

**数值域总结**：数学全 f64；栅格/采样 f32；旋转在 CPU（分析 + 变换合成）一次性解，渲染
warp 单遍 bilinear。无 GPU 化的线段检测/VP（CPU 分析 @1024 长边 + 缓存即够）。

---

## 3. 我方盘点

### 3.1 【勘误】几何域现状：charter 低估了我方既有面

charter §2.3「我方现状」称「旋转/拉直/透视校正全缺——v50 序无对应 iop」。实测**不成立**：

| 件 | file:line | 现状 |
|---|---|---|
| **AshiftModule** | `LightamerIOP/Sources/Ashift/AshiftModule.swift`（430 行） | **已注册 + 在编辑默认 seed**（`Registry.swift:653`）+ 默认面**未禁用**（`defaultFaceDisabledOpNames` 六件 = FilmicRGB/Sigmoid/AgX/Denoise/NLMeans/Bilateral，`Registry.swift:39-47`——ashift 不在内）；dt GENERIC 子集：**rotation ±45°** + lensShiftV/H + shear + 内裁 cl/cr/ct/cb；ROI 协商（前向角点 AABB / 逆向后向 + 2px 插值边距）；neutral → blit identity |
| **Homography.swift**（IOP） | 同目录（290 行） | `compose`（dt 十步 ShiftN 型合成，Double）；**`dlt` 4 点 DLT**（8×8 高斯消元，:200-241）；**`fitParams`**（确定性坐标下降 60 轮，rotation/shiftV/shiftH/shear 反解 + RMS，:249-288） |
| **AshiftKernels.metal** | 同目录（110 行） | **`ashift_warp` 通用后向单应 warp**：任意 3×3 逆矩阵（uniforms 三行 float4）+ 像素中心约定 + clamp-edge 双线性 taps + 域外透明写 `(0,0,0,0)`——**Guided Upright 的 warp 直接可骑（零新 kernel 数学）** |
| **VisionDetect.swift** | 同目录（60+ 行） | `VNDetectHorizonRequest`（地平线角，符号约定已探针钉死）+ `VNDetectRectanglesRequest`（矩形四角）——Apple 原生零依赖 |
| **AshiftAutoDetect** | App `State/`（PipeCoordinator/AshiftPanelView 消费） | horizon→rotation 校正 + 矩形→DLT→fitParams 面板门面 |
| **AshiftPanelView** | `App/Sources/Lightamer/UI/Inspector/AshiftPanelView.swift`（299 行） | rotation 滑杆（±45，D-H1 三段）+ **Auto Level 按钮**（Vision 地平线）+ lens-shift/shear 滑杆 + **Auto Detect 按钮**（矩形 DLT）+ 内裁滑杆 + reset；无变化 = notice+toast 零 commit |
| **Geometry 页** | `App/.../Shell/EditorTabRoute.swift:266-278` | crop/flip/lens 基础排 + **ashift/liquify/… 在 Advanced 折叠组**（D6 独有项收纳） |

**修正后的真缺口**（用户可达面视角）：
1. **crop 工具无旋转/拉直联动**：`CropModule.Params` 纯四边 + ratio（`CropModule.swift:63-89`），
   process = 纯 blit（:233-240）；`CropOverlayView` 无角度手柄（:27-28 注记显式「rotation
   handles belong to 04-03 ashift…no stub control」）；**无角度→裁切框重算**（upstream
   `with_angle` 单漏斗 + `crop_fit_angle` 最大内接矩形无对应物）。
2. **90° 步进在 flip 面不在 crop 工具**：`FlipModule` 全 orientation 位集（rotCW90/rotCCW90
   等，`FlipModule.swift:67-81`）+ `.auto` 解 EXIF（:98-103）——能力在，crop 工具无按钮。
3. **拉直检测是单线 Vision 地平线**：无 lightcraft 的 ≥3 线共识防呆（其 300 张实测把误转
   79→19 张的那类防线）。
4. **Guided Upright 全缺**：导线（画/选/删/拖端点）、消失点数学（`Σ w·l·lᵀ` 最小特征向量、
   正交估焦、K·R·K⁻¹ recentre）、Level/Vertical/Full 模式、导线 overlay——零对应物。
   （矩形 Auto Detect ≠ Guided：需画面里有完整矩形，建筑双竖线场景不可用。）

### 3.2 M5-3 Pano 复用判定（charter 的「Pano homography 复用」逐件核实）

| Pano 件 | file | 对 Upright 的复用判定 |
|---|---|---|
| `PanoCamera.swift:95 focalFromHomography` | `LightamerCore/Sources/Stack/` | **复用价值有限**：它是「从相邻帧单应闭式估焦」（多视图标定问题）；upright 的焦距是**单图内两 VP 正交性** `f²=−(vx·hx+vy·hy)`——公式不同源。可复用的是**周边数学件**：`rotation(fromAxisAngle)`/`axisAngle`/`relativeAngle`（Rodrigues 同族）、`bundleAdjust`（LM——upright 不需要，`refine_vp` 特征向量法更稳） |
| `PanoWarp.swift sphericalMap` | 同上 | **不可复用为 warp**：球面投影逐像素 CPU remap（`StackMergeService.swift:1307+` 消费），非平面单应；**可复用的是纪律**：Double 计算 / Float32 存储（L048 同款）、focal 预览→全分辨率回投（upright 坐标系归一化后天然免此问题） |
| **真正的 warp 复用件** | `AshiftKernels.metal ashift_warp` | 见 §3.1——**通用 3×3 后向 warp，upright 落它的 dispatch 形态**（charter 落地路径第 2 条「与 Lens warp 同 dispatch 形态」实际最佳锚点是 ashift_warp：uniforms 形态/L020 重定基/ROI 协商全套现成） |
| `PanoCrop.swift` / `LensAutoCrop`（`LensModule.swift:297+`） | Core/Stack、IOP/Lens | **Constrain Crop 同族先例**：LensAutoCrop = 畸变黑角最小内接 scale 闭式；upright 后黑边收缩可循此形（upstream `constrain_to_image` = 48×4 边采样点数值版） |

**结论**：charter「M5-3 Pano homography 复用」判定 = **数学件部分可借（Rodrigues/矩阵族），
warp 基建复用锚点应改判为 ashift_warp**（更近、形态全同）。

### 3.3 V50Order 几何段与新 op 落位

现行几何段（`LightamerCore/Sources/Foundation/V50Order.swift:42-76`）：
`lens 13.0 → ashift 15.0 → flip 16.0 → liquify 18.0 → … → crop 24.5`。

**新 op `upright` 建议落位 15.5**（ashift 之后、flip 之前）：
- 与 upstream 合成序一致（manual transform 与 upright 同居 geometry 段，upstream 单遍合成
  = 我方 ashift→upright 链式；upright 消费「手动旋转后」的帧，导线画在用户所见帧上）；
- add-only 纪律（V50Order 冻结序零改动，纯追加——crop 24.5 / filmPlacement 20.8 半步先例）；
- flip(16) 与 crop(24.5) 均在其后：upright 的 AABB 输出被 flip/crop 正常消费，与 ashift 同构。

### 3.4 视口交互与坐标基建

- **CropOverlayView**（`App/.../UI/Overlay/CropOverlayView.swift`，305 行）：SwiftUI 层置
  EditorMTKView 上、D-H1 三段回调（begin/live-disabled+scrim/单 commit）、16 态命中位集、
  aspect 锁、归一⇄视口换算——**角度手柄与导线 overlay 的直系模板**。
- **MaskOverlayHost**（`UI/Overlay/`）：蒙版图上绘制 + 手柄 overlay 先例（charter 点名的
  overlay 模式复用对象）。
- **GeometryPointMapper / GeometrySegment**（`LightamerCore/Sources/Pipe/GeometryPointMapper.swift:42-52`）：
  `.affine` / **`.homography(forward:inverse:clip:)`** 双段已在册（ashift :310-338 /
  crop :190-201 各自供段；PipeCoordinator:285/2397 `compose` 消费）——**导线视口坐标 ⇄
  upright 输入帧坐标的映射通道现成**（导线存 op 输入帧归一坐标；用户在最终渲染上画线，
  经 mapper 逆映射入档）。
- **detectionSourceImage()**（`PipeCoordinator.swift:2030`）：decoded 只读探针源（ashift
  Vision 检测现用）——**未过 lens 校正**（upstream 分析在 lens 校正后帧上）；lens 校正后
  探针的先例 = `followEdgesSurface` 截断栈渲染（`PipeCoordinator` M2-7-2 T6 缝）。
- **L014 读回纪律**：`FollowEdges.readEdgeMap`（`FollowEdges.swift:336`）= GPU 边缘图 +
  fence 读回 + ≤512 降采样（**注意：M4-2 终裁后 1024 升域与 RidgeGraph 全撤、缺省回 512**）
  ——线段检测若走 GPU 前端可循此，但 upstream 路线是 CPU 检测 @1024 + 缓存，直接 Swift
  移植更省（见 §5）。

### 3.5 sidecar 与持久化

- sidecar 现行 **v11**（`LightamerSidecar.swift:255 schemaVersionCurrent`）；**v12 已被
  M9-2 预定**。
- **纯新 op params = 零 schema 触碰**：per-instance `paramsData`（Data→base64，:741-752）
  承载任意 Codable Params——`upright.Params`（mode + guides ≤4×4 Double）走既有
  ModuleInstance 编码，**不动 LightamerSidecar schema**（M2-1 colormatch「Params 直存 +
  store 级投影缝」同款先例）；StableHash 哈希 params 原文（D-H4）。
- 90° 步进 = flip.orientation 既有 params 面（零新档位）；拉直角 = ashift.rotation 既有
  params 面；两者零 schema 触碰。
- upstream `upright_transform`（自动模式解缓存持久化）——Guided 路线**不需要**（导线即
  真相、解确定式 f64 重导出逐位同）；若未来上 Auto 模式再按 upstream 缓存形态扩
  （届时才是 schema 触碰点）。

### 3.6 MCP / 键族 / 测试面

- MCP `IopCatalog`：crop/flip/ashift/lens/liquify 已列 payload/geometry 组（`IopCatalog.swift:22`）
  ——新 op 注册为同组（additive）。
- xcstrings：新面板/工具键尾块纯插入（M2-7 惯例）。
- 测试先例：`AshiftParityTests` / `HomographyTests` / `CropParityTests` / `CropOverlayTests`
  / `VisionDetectTests` / `LensAutoCropTests` / `PanoGoldenTests`——golden + overlay 单测
  双轨现成。

---

## 4. 差距矩阵 + 方案骨架

### 4.1 差距矩阵（需求 → 缺口 → 复用件/新建件）

| 能力 | 现状 | 缺口 | 复用 | 新建 |
|---|---|---|---|---|
| 自由旋转 ±45° | **ashift.rotation 已达**（滑杆 + 持久化 + golden） | 视口角度手柄（crop 工具内） | CropOverlayView 形、D-H1、ashift op | 手柄 UI + 写 ashift.rotation |
| 拉直（角度滑杆 + Auto） | ashift 面板 Auto Level（Vision 单线） | crop 工具内拉直滑杆；**≥3 线共识防呆** | ashift.rotation；VisionDetect 可留 | 段检测 `detect_segments`+`level_angle` 移植（Swift CPU，~150 行级）+ 共识门 |
| 90° 步进 | flip orientation 全位集 | crop 工具 90° 按钮（LR 位） | flip op + `.auto` EXIF 解析 | 按钮态映射（CW/CCW ⇄ 位集，探针钉符号） |
| **裁切框联动（旋转后框重算）** | **无**（crop 纯四边，角度变 → AABB 变 → 框语义漂移无保护） | `with_angle` 单漏斗语义 + `crop_fit_angle` 最大内接闭式 | CropModule.clamp 形、LensAutoCrop 同族 | `cropFitAngle` 纯函数（Swift）+ 联动 commit 缝 |
| Guided 导线（画/选/删/拖端点） | **无** | 全套 | CropOverlay/ MaskOverlayHost 模式；导线存 params | 导线 overlay + 交互态机（选中态 UI-only） |
| 消失点求解 + 应用 | `Homography.dlt`（4 点）在但语义不同 | `Σ w·l·lᵀ` 最小特征向量 + 正交估焦 + K·R·K⁻¹ recentre | Mat3D；`ashift_warp` kernel；Rodrigues（PanoCamera 同族） | `UprightMath`（Core 级纯函数，f64）+ `upright` iop |
| Upright 后黑边处理 | ashift 内裁 cl/cr/ct/cb（近似） | Constrain Crop 一键（upstream 数值版） | LensAutoCrop 形 | `constrainCrop` 纯函数 + crop 重写 commit |

### 4.2 方案骨架（供 plan 拆解；量级复核 = charter M 档 12-18N 成立）

**件 A — `UprightMath`（Core 级纯函数，Swift f64，lightcraft 移植带 NOTICE）**
`LightamerCore/Sources/`（建议 `Pipe/` 或新 `Geometry/`；Core 可单测、IOP/app 两侧消费）：
`Segment`（居中归一坐标）+ `line()`/`tiltFromVertical()` + `refineVP`（Jacobi 最小特征向量）+
`focalFromVPs`（正交闭式 + 0.5..6 接受域）+ `rotationBetween`（Rodrigues）+ `solveVertical`
+ `solveFull`（Gram–Schmidt）+ `recentre` + `solveGuided(guides) → Mat3D` + `levelAngle`
（长度加权中位 + ±2° 共识）+ 病态防线（近平行 → VP 叉积范数 <1e-24 拒、VP 帧内 <2.0 拒、
focal 域外回落 1.5）。**不移植** detect_segments/analyze_source/RANSAC（Guided 不需要——
导线即内点；Auto 模式见 OQ-3 挂账）。

**件 B — `upright` iop（LightamerIOP/Sources/Upright/，v50 15.5）**
`Params { mode(off/guided), guides: [Guide]≤4（op 输入帧归一坐标） }`；commit =
`UprightMath.solveGuided` 导出前向/逆向 Mat3D（确定式重导，不缓存）；process **骑
`ashift_warp` kernel 函数**（Registry kernel 清单登记同名或薄 wrapper——零新 kernel 数学）；
ROI 协商 = ashift 同款前向角点 AABB / 逆向后向；neutral(off) → blit identity；pointMapSegment
供 mapper（`.homography` 段）。**零 sidecar schema 触碰**。

**件 C — rotate/straighten 工具面（crop 工具扩展）**
- 角度手柄（框外角度轮）+ 拉直滑杆（±45）→ **写 ashift.rotation**；拖动 live = ashift
  live tick（crop T0「全帧渲染 + scrim」同款预算形；直显旋转用 live 而非 disable——
  见 OQ-5）。
- 90° 按钮 ×2 → 写 flip.orientation（显式位覆盖 `.auto`）。
- **联动重算**：任一角度/90° 变更 commit 时同批重算 crop rect（`cropFitAngle` 最大内接，
  aspect 保持；lightcraft #1794 语义：非最大框永不放大、最大框随角回 0 复原）。
- auto straighten 按钮：段检测移植件（≤10° + ≥3 线）优先，Vision 地平线为回落（OQ-4）。

**件 D — Guided 导线 UI（viewport 工具 + overlay）**
工具槽位（mask 工具栏族）；交互态机照 upstream 语义（按下即画/端点拖/近线点选/空白清/
Delete 删选中/≤4 上限 toast）；导线持久 = upright.Params.guides（每编辑 = 一 history item，
upstream undo 粒度同款）；选中态 UI-only；坐标经 GeometryPointMapper 逆映射入档；端点拖动
live = upright 重解 + preview 重渲（导线解 = 闭式 μs 级，preview bucket 一 warp——hitch 门
内，OQ-5）。

**件 E — Constrain Crop 一键**（upright/ashift 后黑边收缩；数值版 48×4 边采样或
LensAutoCrop 闭式形；crop 重写单 commit）。

### 4.3 坐标系与合成序（红线级约定提案）

- **upright 导线坐标 = upright op 输入帧**（= lens 后 + flip 后 + ashift 手动几何后）归一
  0..1——与 upstream「lens 校正后定向帧」一致到我方链式的对应位；视口 ⇄ 该帧经
  GeometryPointMapper（既有件，勿开第二映射点）。
- upright 解出的 H 在**居中归一域**（上游同款），入 kernel 前 ×平面像素缩放（ashift
  compose 同位换算，Double）。
- 渲染链 = ashift(15.0) → upright(15.5) → flip(16.0) → crop(24.5)：**两遍 warp 的插值损失
  vs upstream 单遍合成**——ashift neutral（纯 Guided 场景常态）时只有一遍，可接受；
  straighten（ashift.rotation）+ upright 叠加为两遍 bilinear——质量风险挂 §6 R-3。

---

## 5. 数值与精度

- **数学域**：`UprightMath` 全 Double（upstream f64 对齐；`Mat3D` = Core 既有 Double 阵）；
  kernel 采样 float32（L006 同款；`ashift_warp` 既有路径零改）。
- **插值核**：bilinear + clamp-edge + 域外透明（`ashift_warp` 既有语义）= upstream 采样
  形（f32 bilinear）一致；**无 Mitchell 预滤波**（upstream 仅下采样前置用；我方 preview
  ladder 自带逐级降采样，不需引入）。
- **golden 形态**（对齐 charter 验收 + upstream 门，供 plan 直取）：
  1. **合成梯形逆解门**（M9GEO-02 主门）：已知 H_shot（`solve_full` 域内）合成网格 →
     导线沿真图竖线经 H_shot⁻¹ 映入 → `solveGuided` → 输出竖线 x 迹 spread **<1.5px**
     （720×480 级测试面）+ 解出 H 与 H_shot⁻¹·recentre 的**四角位移差 <0.01**（居中单位）。
  2. **单条导线 = 纯旋转精确门**：导线端点变换后 x 差 **<1e-9**（upstream 同款精确断言）。
  3. **分辨率无关**：1200×800 vs 600×400 解出 H 四角差 **<0.006**。
  4. **符号约定门**：右倾下降 6° 地平线 → 拉直角 **−6°±0.5**（与 ashift.rotation 的
     CG y-down 符号衔接——VisionDetect 头注已有 y-down 翻转先例， upright 域 y 方向
     同须探针钉死）。
  5. **病态防线**：两近平行导线（夹角 <0.5°）→ identity 回落不崩；全部导线共点 →
     VP 帧内拒；focal 正交解域外（<0.5 或 >6）→ DEFAULT_FOCAL 回落。
  6. **拉直防呆**：单边线 → None；带纹地平线 → −4°±0.5；20° → None、8° → −8°±0.5。
  7. **旋转 90/任意角 golden**（M9GEO-01）：合成网格旋转 θ ∈ {90 的倍数走 flip 位集;
     任意角走 ashift.rotation} → 线迹 spread <1.5px + AABB 尺寸闭式断言；**crop 联动 =
     cropFitAngle 已知角/aspect 闭式对照**（3:2 @10° 等解析例）。
- **确定性**：solveGuided 闭式无 RNG；段检测（若入批）确定性区域生长无随机——双跑逐位
  门照 M4-2 惯例。

---

## 6. 风险与 OQ

**风险**：
- **R-1（最高）旋转×裁切联动 UX 复杂度**：upstream `with_angle` 收敛了三代 issue
  （#742 各入口同框 / #1388 最大框随角复原 / #1794 非最大框永不放大）；我方 crop 存
  ashift-AABB 帧分数（与 upstream 存旋转帧归一不同构），联动重算缝 = 「同 commit 内
  ashift.rotation + crop rect 双实例单动作」——history 粒度（单 item 双实例 vs document
  级 item vs 两 item 一 undo 组）须 plan 定夺（DRT document-item / M3-1 instancesOverrides
  两先例在册）。
- R-2 符号/坐标系三重奏：crop angle（CW+）vs ashift.rotation（dt 约定）vs upright 居中域
  （y 上/下）vs Vision CG y-down——探针钉死 + 精确断言（golden 4 号门）是唯一可信路径。
- R-3 双 warp 叠加（ashift.rotation + upright 同用）两遍 bilinear 软化；缓解 = 检测到
  upright 非空时 UI 提示拉直并入导线解（Level 单线即纯旋转），或挂账单遍合成优化。
- R-4 导线拖动实时性：端点拖 = 每 tick 重解（μs）+ preview 重渲（一 warp + 尾段）；
  M2-11 hitch 门（>50ms = 0）约束下预览桶重渲频率须探针实测（crop T0 全帧渲染先例
  表明可行，但 upright 尾段链更长）。
- R-5 段检测移植面（若 OQ-4 选 lightcraft 路线）：CPU @1024 + 缓存；lens 校正后探针
  （followEdgesSurface 截断栈形）vs decoded 裸探针的检测质量差需一次对比实测。

**OQ（新开，plan 前裁决）**：
- **OQ-M9-3-1 联动 history 粒度**：拉直动作落位 = ①document 级 history item（DRT 先例，
  裁决推荐——单 undo 语义最清）②双实例单 commit ③两 item 一 undo 组。推荐 ①。
- **OQ-M9-3-2 `upright` 新 op vs ashift 扩展**：Guided 落 = ①新 op 15.5（推荐——语义/
  history/封存面干净，ashift 的 dt GENERIC 模型不动）②ashift.Params additive 直矩阵入口
  （少一 op 但污染 dt 语义面 + 封存面清单新增改动点）。
- **OQ-M9-3-3 auto upright 模式范围**：Level/Vertical/Full/Auto 自动分析（detect_segments +
  RANSAC + reliable ~400 行）本站入否？REQUIREMENTS 只点名 Guided；推荐 = **P1 Guided only
  （mode 枚举 off/guided 加 case 即编译期扩点）**，auto 族挂账独立批（上时按 upstream
  upright_transform 缓存持久化形态）。
- **OQ-M9-3-4 auto straighten 检测路线**：①lightcraft 段检测 + ≥3 线共识移植（推荐——
  防呆实证 + 确定性可测）②Vision 地平线现状 + 简单护栏。推荐 ①，②留回落。
- **OQ-M9-3-5 导线拖动 live 形态**：①live 重渲每 tick（推荐，预算探针先行）②crop-T0
  disabled+scrim（保底）。R-4 实测后定。
- **OQ-M9-3-6 90° 按钮与 EXIF orientation 关系**：显式位覆盖 `.auto` 后 EXIF 变化（换图
  不适用；sidecar 重读）语义 = 显式位持久（upstream orientation 同款）；确认无隐藏坑
  （flip `.auto` 解析点唯一性已在案 `FlipModule.swift:98-103`）——低风险，plan 内核即可。

**量级复核**：件 A 3-4N + 件 B 2-3N + 件 C 3-5N + 件 D 3-4N + 件 E 1N + golden/探针
2-3N ≈ **14-22N**，charter M 档（12-18N）基本成立（auto 模式若入批另计 +5-8N）。

---

## 7. 许可与归属

- lightcraft = MIT OR Apache-2.0 双许可：`UprightMath`（upright.rs 数学移植）+ 段检测
  （若入批）Swift 重写 + NOTICE 条目（ALCE-03 LightCraft 先例：移植臂 NOTICE 义务同款；
  上游 commit 锚 = fbc927f0 / 7635b38c / 693c3593 / 54c6c43b / 7d3cd8af）。
- 零新 SPM、零模型依赖（Vision 原生已用；段检测纯 CPU Swift）。

## 8. 来源清单

- lightcraft origin/main：`crates/pipeline/src/upright.rs`（634 行）、`crates/pipeline/src/transform.rs`（89 行）、`crates/pipeline/src/geometry.rs`（Frame 单遍合成）、`crates/pipeline/src/tests_geometry.rs`（526 行）、`crates/develop/src/settings.rs:751-806`（Upright/Geometry）、`crates/geom/src/crop.rs`（CropGeometry/with_angle/crop_fit_angle）、`crates/ui-egui/src/tests_guided_guides.rs`（交互态机断言）
- lightcraft commits：fbc927f0（导线画/拖端点 merge #2347）、7635b38c（选中/删除）、693c3593（auto straighten 防呆 + 符号约定）、54c6c43b（Constrain Crop #1927）、7d3cd8af（XMP upright 跨导入保留）
- 我方：`LightamerIOP/Sources/Ashift/{AshiftModule,Homography,AshiftKernels.metal,VisionDetect}.swift`、`Registry.swift:39-47/653`、`Sources/Crop/CropModule.swift`、`Sources/Flip/FlipModule.swift`、`LightamerCore/Sources/Foundation/V50Order.swift:42-76`、`Sources/Pipe/GeometryPointMapper.swift`、`Sources/Stack/Pano{Camera,Warp,Crop}.swift`、`Sources/Sidecar/LightamerSidecar.swift:255/741-752`、`App/Sources/Lightamer/UI/Overlay/CropOverlayView.swift`、`UI/Inspector/AshiftPanelView.swift`、`UI/Shell/EditorTabRoute.swift:266-278`、`State/PipeCoordinator.swift:2030/285`、`LightamerIOP/Sources/Lens/LensModule.swift:297+`（LensAutoCrop）、`Tests/LightamerTests/{AshiftParity,Homography,CropParity,CropOverlay,VisionDetect,LensAutoCrop,PanoGolden}Tests.swift`
- 规划：ROADMAP §M9 站 3、REQUIREMENTS M9GEO-01..02、`research/M9-CHARTER-INPUT.md` §2.3、`research/LIGHTCRAFT-NOTES.md` 增量节
