# M9-3 验收报告 — 第二路（盲评独立第二眼，2026-10-29）

> 验收对象：`d111ef2a`..`bee6b4bc` 五 commits（T1 数学面 / T2 op 面 / T3 联动面 /
> T4 交互面 / T5 收口，refs #13）。正本 = 同目录 PLAN v2 + CONTEXT（D-M9G-1..6）+
> SUMMARY + DECISIONS；AC 源 = REQUIREMENTS M9GEO-01..02。独立性纪律遵守：
> 未读 `M9-3-ACCEPTANCE.md`（路 1 报告）与 `all-runs/acc1-*`（路 1 证据）。
> 本路特色 = **upstream 直译保真度逐构深审 + 交互态机独立核**。

---

## 结论头

**PASS / 1 error + 3 minor**（另 4 obs）。

- 定向三 bundle 全绿**逐值复现**：IOP **807/1/0**（962s，峰 6290MB）· IOPParity
  **544/10/0**（1635s，峰 6050MB）· App **1052/6/0**（599s，峰 2832MB）——三值与
  SUMMARY 申报完全一致，全部 <8G 门，guard monitor（ceiling 9GB）零 RSS-KILL。
- 封存面 17 件零 diff 机检**全零**（13 件核心封存 + DrtEotf/NodeGraphCommand/
  ExportFormatSpec〔ExportRecipe.swift〕；V50Order add-only 零删行 + Registry
  additive 恰形、`defaultFaceDisabledOpNames` 零触）。
- upstream 直译保真度：**高保真**——`solve_guided` / `transform.rs` 三件 /
  `detect_segments` / `with_angle` 五支链 / `level_angle_within` 逐构对照
  `origin/main` 全一致；全部偏离均在文件头注申报且为 plan 授权（病态防线三件 +
  架构适配）；一处数值未申报文档缺口记 **m-1**。
- 反自取消补充探针**双真红**（掏空 shrink 分支 → CropFitAngleTests 15 断言红；
  掏空 ≤4 拒门 → UprightGuidesInteractionTests 2 断言红），还原后复绿——
  golden 联动非自取消。
- Float 判等门重定**独立数值复核成立**（obs-2：噪声实测 1.25e-5px，1e-3px 门
  80× 余量；upstream 1e-9 归一门在该域确实不可达）。
- **error 一件（E-1）**：T3 联动批的 `frameSize` App 接线域混淆（非移植面、
  非封存面）——用户可见的裁切联动精度缺陷，建议修复轮单点接线修复 + 补一法
  「第二次拖动域正确性」回归。不推翻其余全部验收结论。

---

## 1. AC 独立核对（file:line）

| AC（PLAN 验收条款） | 交付位置 | 独立核验 |
|---|---|---|
| T1 golden 六门 | `Tests/LightamerTests/UprightMathTests.swift:70/107/124/157/183`（门 1 内嵌确定性双跑 `:101-102`） | 五法六门全数在案，断言值与 CONTEXT §测试策略逐值一致（spread<1.5px + 四角<0.01 / 1e-9 / <0.006 / −6°±0.5 / 三防线+finite net 兄弟） |
| T1 cropFitAngle 解析例 + #742/#1388/#1794 | `Tests/LightamerTests/CropFitAngleTests.swift:46/72` | 手值 0.8030322372（1e-8）、三分支同参直译 upstream crop.rs 测试面 |
| T2 off 恒等 byte-exact + params 恒写 | `Tests/LightamerTests/UprightModuleParityTests.swift:116`（paramsData 非空断言 `:127`） | 真 GPU 腿逐字节（accuracy: 0）；v2 MIN-2 语义钉死 |
| T2 产线 warp 梯形恢复 | `UprightModuleParityTests.swift:160`（spread 门 `:225` + 公式镜像落点 `:250-263` 反真空） | 真 `ashift_warp` kernel + 物理线迹 1.5px 门 |
| T2 AshiftKernels.metal 零 diff | `git diff d111ef2a^..bee6b4bc -- LightamerIOP/Sources/Ashift/AshiftKernels.metal` = 0 行 | 机检 ✓；`UprightKernel.functionName = "ashift_warp"`（UprightModule.swift:65）字符串常量共名 |
| T2 V50Order 15.5 add-only | V50Order.swift diff = +8 行 0 删行，插于 ashift 15.0 与 flip 16.0 之间 | `V50OrderTests` 计数账本 107→108 + native-row 剥离后 93 行 dt 表不变 |
| T2 params 往返/StableHash/pointMapSegment | `UprightModuleParityTests.swift:268/306` | Double 逐位往返 + StableHash + `.homography` 段 <1px |
| T3 段检测 golden + 防呆门 | `Tests/LightamerTests/StraightenDetectTests.swift:61/116` | 方向 <0.7°/长度 ≥0.6× + 单线 None/−4±0.5/20° None/8° −8±0.5/符号 −6 |
| T3 recordLinkedChanges 原子批 | `EditorState.swift:242-253`（单 Task 单通知）+ `PipeCoordinator.swift:1983-1988` | 两 item LIFO undo 断言钉死（CropToolRotationTests:70） |
| T3 联动谓词三分支 | `CropToolRotationTests.swift:113`（keep 单 item / shrink 双 item / #1388 regrow 双 item + fullBack 单 item） | DECISIONS D-M9G-1 成批条件实测修正（谓词不动框=单 item）在案 |
| T3 90° 位探针 + EXIF 持久 | `CropToolRotationTests.swift:193`（top-right→bottom-right CW + `resolved(forEXIF:)` 直通） | D-M9G-6 显式位持久 |
| T3 Constrain Crop | `CropToolRotationTests.swift:222`（blank_fraction<0.002 + 像素 aspect 1.5） | 二分最大 fit（DECISIONS 收缩语义裁定） |
| T4 交互态机 5+5 | `Tests/LightamerTests/UprightGuidesInteractionTests.swift:25/58`（①-⑤） | 模型级全覆盖；App 级两处接线偏离见 M-3 |
| T4 选中态 UI-only 负测 | `UprightGuidesInteractionTests.swift:141-146`（params JSON 无 selection 键） | serde-skip 语义钉死 |
| T4 mapper 往返 <1px | `UprightGuidesInteractionTests.swift:151`（ashift 非零经 `.homography`）+ `UprightModuleParityTests.swift:306`（段级） | 双腿在案 |
| T4 live 面（D-H1） | `UprightGuidesInteractionTests.swift:175`（live 零 item + 松手一 item） | ✓ |
| T5 zh-audit 双 PASS | 本路复跑：`--check` PASS（1765 source / 2081 catalog / 10 interp）+ `--self-test` PASS（V17 八 case） | 独立复现 ✓ |
| T5 MIT 归属 | NOTICE 条目 S（五 commit 锚）+ UprightMath/CropFitAngle/StraightenDetect 三文件头注 | 在案 ✓ |
| T5 Project.swift/BUNDLE-MAP | 六测试文件归位 + BUNDLE-MAP 行 | 在案 ✓ |
| T5 封存面机检 | 见 §2 | 全零/恰形 ✓ |

**REQUIREMENTS 对读**：M9GEO-01（勘误后 = rotate/straighten 工具联动面）交付
齐（手柄/滑杆/90°/auto straighten/Constrain + 单漏斗）；M9GEO-02（Guided
Upright）交付齐（UprightMath + upright op + overlay + 面板）。合成梯形 golden
与导线交互探针两大验收形态均在案。

## 2. 封存面 17 件零 diff 机检

`git diff d111ef2a^..bee6b4bc -- <file>` 全零行：

- 核心 13 件：AshiftKernels.metal / LightamerSidecar / HistoryStack /
  HistoryHash / PipelineDocument / GradeCatalog（NodeOwnershipCatalog.swift）/
  DrtRecord / TerminalTailPolicy / DrtTailAssembly / PixelPipe /
  ExportQueueContract / Lut3dKernels.metal / ModuleInstance —— **全零**。
- 另核：DrtEotf / NodeGraphCommand / ExportFormatSpec（实文件
  `Export/ExportRecipe.swift`）—— **全零**。
- **唯二 additive 例外恰形**：V50Order.swift（+8/−0，现行行零触碰）；Registry.swift
  （+17/−1 注释行改写〔"perspective share one kernel" 行加 upright 骑行注记〕+
  注册行族 + seed instance；`defaultFaceDisabledOpNames` 零命中）。
- 零 schema（schemaVersionCurrent 零命中）、UserDefaults 零新键（diff 零命中）。
- xcstrings 尾块纯插入：两 commit 合计 0 删行 ✓。

**OQ-1 结构面依据兑现确认**：HistoryStack/HistoryHash/PipelineDocument 三封存件
零触碰，同批双 item 全部经 EditorState（非封存）additive `recordLinkedChanges`
落地——裁②的结构论证在 diff 层面成立。

## 3. upstream 直译保真度深审（本路主职责）

对照正本 = `git show origin/main:<path>`（lightcraft 本地树落后 1031 commits，
工作树文件未采——OBS-3 纪律遵守；`crates/pipeline/src/upright.rs` 634 行 /
`crates/pipeline/src/transform.rs` / `crates/geom/src/crop.rs` 312 行 /
`crates/ui-egui/src/tests_guided_guides.rs`）。

### 3.1 UprightMath ↔ upright.rs/transform.rs（逐构）

| 构件 | upstream | 我方 | 判定 |
|---|---|---|---|
| `Segment::line` 齐次线单位化 | `cross([a,1],[b,1])` → n=max(hypot(l0,l1),1e-12) | `lineComponents`（UprightMath.swift:79-85）同式（l0=a.y−b.y, l1=b.x−a.x, l2=a.x·b.y−b.x·a.y） | 逐位同构 ✓ |
| `tilt_from_vertical` | `dx.abs().atan2(dy.abs()).to_degrees()` | `tiltFromVertical`（:89-93）同式 | ✓ |
| `smallest_eigvec` Jacobi | 50 轮、big<1e-15 break、theta/t/c/s 同式、`min_by(total_cmp)` | `smallestEigvec`（:129-167）同轮数同阈值同旋转序；首最小 index 语义与 `min_by` 一致 | ✓ |
| `refine_vp` | Σ w·l·lᵀ（w=len） | `refineVP`（:171-183）同式 | ✓ |
| `focal_from_vps` | v[2] 1e-9 门 + f²=−(vx·hx+vy·hy) + filter 0.5..=6.0 | `focalFromVPs`（:190-198）同门同域 | ✓ |
| `direction`/`rotation_between` | Rodrigues、s<1e-12 identity | `direction`/`rotationBetween`（:204-231）同式 | ✓ |
| `solve_vertical`/`solve_full` | d[1]<0 翻转 / Gram–Schmidt（dh[0]<0 翻转，r1=norm(dh−p·dv)，r3=cross(r1,dv)） | `solveVertical`/`solveFull`（:236-262）逐式同构 | ✓ |
| `rotation_homography`/`recentre` | K·R·K⁻¹；origin pinned + 数值 Jacobian e=1e-4、det>1e-12 | `rotationHomography`/`recentre`（:266-284）逐式同构（transform.rs 对照） | ✓ |
| `level_angle_within` | dev 折叠 ±90°/加权中位/±2° 共识 ≥0.5·total/水平族 lh≥0.5·lv 优先/return −median | `levelAngleWithin`（:297-336）逐式同构 | ✓ |
| `rot_z_h` | c,−s/ s,c | `rotZH`（:339-344）同式 | ✓ |
| `solve_guided` 主链 | filter len>1e-6 → take(4)；≤45° 分族；每族 ≥2 → refine_vp；四臂 match | `solveGuided`（:364-426）同过滤同分族同四臂；**90° 共轭臂逐位**（swap (x,y)→(y,−x) + `to=[0,1,0,−1,0,0,0,0,1]` + back=inverted） | ✓（偏离见 3.4） |
| `DEFAULT_FOCAL` | 1.5 | `defaultFocal = 1.5` | ✓ |

### 3.2 偏离清单（全部文件头注申报，判定 = plan 授权）

1. **共点线防线**（:368-382，cross²<1e-24 → 无 VP）：upstream Guided 面无此检查
   （其 RANSAC 面有 `dot<1e-24 continue`）——plan T1 病态防线授权，头注申报
   （"upstream relies on RANSAC, Guided doesn't run it"）。数值核验：平行异位线
   cross² = 线距² 量级，不受误伤 ✓（1e-24 只捕数值共点）。
2. **帧内 VP 拒**（:387-391，radius<2.0）：upstream 在 `reliable()`（auto 面），
   Guided 采纳入族——plan 授权，头注申报。
3. **finite-output net**（:396-425 各臂 isFinite → 降级 levelAngle）：DECISIONS
   「病态防线第四形态」申报 + golden 兄弟样例钉死（两 VP 落 y=0 线 → w 行零 →
   恒有限降级）。upstream 无此防线（其 auto 面有 rotation_angle<20° 平衡门，
   Guided 面确实可产 NaN——我方增强）。
4. **近平行语义钉死**：plan 文「近平行（VP 叉积范数 <1e-24）→ identity 回落」——
   实现与测试一致（同线双导线 → level 臂 → rotZH(0)=identity 逐位）；CONTEXT
   §测试策略 5 的「夹角 <0.5° → identity」系 research 原文，plan v2 已细化，
   0.3° 异位近平行走真解（与 upstream 一致）+ isFinite 断言——判定 = 按 plan
   执行，非偏离。

### 3.3 StraightenDetect ↔ detect_segments/level_degrees（逐构）

σ0.8 高斯 → Sobel gx/gy（/8 归一）→ level-line 角（`rem_euclid(π)` 与我方
`remainder+修正` 数学等价）→ p90×0.35 下限 0.008 → 降序种子 → 22.5° 容差 8 邻域
区域生长（双倍角均值 running update）→ region<12 跳 → 加权主轴
（theta=½·atan2(2sxy, sxx−syy)）→ 长 ≥0.04·max(w,h) 且长宽比 ≥5（宽下限 1.0）→
端点 (mx+0.5+u·t−c)/halfLong —— **逐构一致**（StraightenDetect.swift:49-163）。
`STRAIGHTEN_MAX_DEGREES=10.0`/`MIN_LINES=3` 常量 + 68/300 标定注记原样保留
（:39-43）。分离高斯 helper 为我方重表达（upstream 走
`lightcraft_raster::blur::gaussian`，半径 3σ=3、edge-clamp 合理同族）。

### 3.4 CropFitAngle ↔ crop.rs `with_angle` 五支链（逐支）

| upstream with_angle 支 | 我方 withAngle（CropFitAngle.swift:219-268） | 判定 |
|---|---|---|
| is_largest 判等 | 逐边比较——**门重定 1e-3 px**（upstream 1e-9 归一）；Float 记录域论证见 obs-2（独立复核成立） | 申报偏离 ✓（DECISIONS §Float 记录域） |
| `!is_largest && within` → 原框换角 | 同（:245-247） | ✓ |
| `is_largest ∥ aspect none` → fitted（#1388 regrow） | 同（:248-250） | ✓ |
| shrink-in-place（fit_scale_about_centre + MIN_CROP_FRACTION·min(w,h) 门） | 同构（:252-258，fitScaleAboutCentre :144-165 逐式同构含 0..=w 中心域检查与 s>0 filter） | ✓ 结构；**minFraction 数值 0.01 vs upstream 0.02**（crop_drag.rs:12）——我方取自产 CropModule.minFraction（dt MIN_CROP_SIZE 传承，CropModule.swift:49），语义正当（「拖拽模型允许的最小框」应遵循本模型），但头注（:33-36）只引 dt 未披露 upstream 数值——**m-1 未申报文档缺口** |
| 中心离帧支（centred, own size ≤ fitted, s<1 filter） | 同（:260-267） | ✓ |
| `max_inscribed_scale` 闭式 | `maxInscribedScale`（:171-182）逐式同构（s1/s2 min） | ✓ |
| `crop_fit_angle` | `fitRect`（:187-205，fit_aspect 分族等价、min(s,1.0)） | ✓ |
| `is_within_image`（1e-6 容差，−angle 反旋） | `isWithinImage`（:129-139）同容差同方向 | ✓ |

**#742/#1388/#1794 语义链验收**：#742（各入口同框）= `linkedSnapshots` 单漏斗
实装（EditorAreaView 手柄 :157-167 / 滑杆 / auto straighten :178-187 三入口 +
UprightPanelHost Constrain/模式/导线全走 `commitLinkedSnapshots`）✓；#1388（最
大框随角回 0 复原）= with_angle is_largest 支 + 测试 (d) 链 + 谓词测试 regrow 双
item 段 ✓；#1794（非最大框永不放大 + 不再 fit 绕自身中心收缩保 aspect）= shrink
支 + 测试 (b)(c) 同参直译（upstream crop.rs `with_angle_shrinks_*` 双测试面 +
`with_angle_shrinks_a_crop_against_the_edge_about_its_own_centre` 五角 +
gentle-turn 0.97 面）✓。**upstream crop.rs 测试参数 1:1 保留**。

### 3.5 tests_guided_guides 5+5 对照

upstream 十一面（选/删/清/空删/画清选/端点拖 1e-3/端点点选零改/起于按压点/同帧
batch/右键不选/navigator 不达）——我方模型级 5+5 断言覆盖 ①-⑤ 主面 +
App 接线两处偏离（M-3，见 §4）。upstream 的「右键不选」「navigator 不达」属
egui 事件模型特有面，macOS 手势栈对应面为 tap/drag 分离——判定 = 平台差异合理
省略，非静默语义丢失。

**保真度总结论**：T1/T3 移植面为**逐构高保真直译**；全部行为偏离（共点防线/
帧内 VP 拒/finite net/isLargest 门重定）均文件头注 + DECISIONS 双申报且 plan
授权；唯 `minFraction` 一处数值差缺申报（m-1，行为影响 = 收缩下限 0.01 vs
0.02 更宽松，与产 CropModule 语义自洽）。

## 4. 交互态机独立核（overlay 5+5 + coordinate 通道）

- **模型层**（UprightGuidesModel，纯逻辑）：按下即画起于按压点（press 建零长
  pending）/ 近端拖远端不动（dragging.end 分派）/ 近线点选 / 空白清 / Delete 无
  选中零动作零 item / ≤4 拒 / 零长 press 不落 guide / leave 清 transient——
  七面读测与测试断言一一对应 ✓。
- **选中态 UI-only**：InspectorState.uprightGuideSelected（session face，
  InspectorState.swift:100），open/close tool 双清（:102-109）；params JSON 无
  selection 键有负测钉死 ✓。
- **D-H1 三段**：onBegin→beginContinuousEdit / onLive→setLiveParams（applyLiveInstance
  零 item）/ onCommit→commitLinkedSnapshots 一 item——测试钉死 ✓。
- **coordinate 通道**（CONTEXT 红线 6）：`uprightGuideMapper()`
  （PipeCoordinator.swift:2158-2166）= 活 box 集**截断 upright 槽前**
  （`iopOrder < 15.5`，lens 13/cacorrectrgb 13.5/haze 14/ashift 15 in；
  upright/flip/crop out）——live 截断域与持久域（upright 输入帧）两侧一致，
  mapper 本体零 diff，唯一通道无第二映射点 ✓。**domain 缺口 = M-1**：mapper
  forward 输出域是 upright **输出**帧，overlay 将其当 display 域消费
  （UprightGuidesOverlay.swift:337-341）——crop 全图 + flip none 时两域重合
  （与 rotation 无关），crop/flip 激活时画线错位（详见发现清单）。
- **工具窗 mutex-by-omission**：viewportRouteOverlay 提取为独立函数
  （EditorAreaView.swift:489+）+ `uprightGuidesToolActive` 抢占（:113-120），
  提取为搬移（indent 归一后内容一致）✓。

## 5. 定向测试（本路亲跑）

| bundle | 结果 | 时长 | 峰 RSS | 对账 |
|---|---|---|---|---|
| IOP | **807/1/0** | 962s | 6290MB | = SUMMARY 申报 807/1 ✓（1 skip = 无 GPU 类常规） |
| IOPParity | **544/10/0** | 1635s | 6050MB | = 申报 544/10 ✓ |
| App | **1052/6/0** | 599s | 2832MB | = 申报 1052/6 ✓（6 skip 家族与基线同形） |

前置纪律：`machine-guard.sh` 过门（G1-G4）+ GUI 实例 ps 清零（起跑前 0 进程验证）+
build-for-testing 先行 + monitor 21600 伴跑（`/tmp/m93acc2-monitor.log`，零
RSS-KILL）。全套 --all 未跑（orchestrator 批准制，沿 plan frontmatter 约定）。

## 6. 反自取消补充探针（不同切口，主树掏空还原法）

| 探针 | 掏空点 | 预期 | 实测 |
|---|---|---|---|
| ① shrink-in-place 中段语义（#1794 中段） | `CropFitAngle.withAngle` shrink 支改 `return fitted`（旧 #1794 swap bug 复辟） | CropFitAngleTests 真 red | **2 法 15 断言失败**（TOTAL 2/0/1）✓——(b) never-larger 与 (c) own-centre 面联动爆红 |
| ② guides ≤4 拒门 | `UprightGuidesModel.press` 上限守卫放行（<99） | 态机测试真 red | **5 法 2 断言失败**（TOTAL 5/0/1）✓——「the 5th draw press is refused」红 |

两探针后均 `git checkout` 还原 + 重建 + 过滤轮复绿（5/0/0 + 2/0/0），工作树
零残留（`git status` 干净）。**golden 联动非自取消成立。**

> 过程教训登记（obs-4①）：探针首轮误用 `-derivedDataPath DerivedData`（repo-local）
> 构建，而 `test-direct.sh` 消费 `~/Library/Developer/Xcode/DerivedData` 默认容器
> ——首轮过滤轮 2/0/0 为**旧产物假象**。改用默认路径重建后探针真红。修复批/
> 验收批构建**禁显式 -derivedDataPath**（应入 LESSONS）。

## 7. Float 记录域判等门重定——独立复核（质询项）

DECISIONS 申报：isLargest 门 f64 1e-9 → 1e-3 **px**；shouldAutoRefit/frameMoved
1e-6 归一。独立数值复核（Swift 复算，f64 largest@10° → Float 记录往返 @600×400）：

- 逐边往返噪声实测：8.6e-7 .. **1.25e-5 px**（归一域 1.4e-9 .. 2.1e-8——与
  DECISIONS「归一域 1e-8 噪声」同量级互证）。
- upstream 1e-9 归一门（=6e-7 px @600px）：**必漏判** ✓（噪声超门 20×）——
  #1388 regrow 在 Float 记录域确实不可达，重定正当。
- 1e-6 **px** 门：必漏判 ✓（噪声 1.25e-5 > 1e-6）——与 DECISIONS 括号算术一致。
- shipped 1e-3 px 门：**80× 余量**，且距一像素仍 1000×——真位移（用户可感 ≫
  1e-3px）不可能被吞。
- shouldAutoRefit/frameMoved 1e-6 归一门（=6e-4 px @600px）：48× 余量；噪声与门
  同随帧尺寸线性缩放——**尺度不变健全**。
- 质询遗留（obs-1）：DECISIONS 正文「1e-6 归一门实测仍漏判」与其括号算术
  （6e-6 px > 1e-6 **px** 门）量纲表述不一致——按括号读法（1e-6 px 门）复核
  成立；若按「1e-6 归一门」字面读法则复核**不**成立（6e-4 px 门能过）。建议
  勘误为「1e-6 px 门」。shipped 门两读法下均正确，无行为影响。

## 8. 发现清单

### E-1（error）T3 联动批 `frameSize` App 接线域混淆——旋转后裁切联动落点漂移

- **位置**：`App/Sources/Lightamer/UI/EditorAreaView.swift:158-161`（手柄）、
  `:181-183`（auto straighten）——`frameSize: SIMD2(Double(displayPixelSize.width),
  Double(displayPixelSize.height))`；拉直滑杆同缝。
- **契约**：`CropToolRotation.linkedSnapshots` 文档（CropToolRotation.swift:121-123）
  明文 frameSize = 「the upright-input frame size in pixels (the plane the
  rotation acts on — the decoded/derived plane, **not the AABB**)」。
- **机理**：`displayPixelSize` = displayTexture 尺寸 = 全链输出帧
  （EditorAreaView.swift:594-597）；`AshiftModule.modifyROIOut`
  （AshiftModule.swift:233-245，dt modify_roi_out 形）把旋转后平面**扩展为前向
  AABB** → rotation ≠ 0 时 display ≠ 旋转基准平面。RotatedFrameBridge 的
  span/cropToRotated/rotatedToCrop 全部要求 frameSize = w0×h0 基准域。
- **数值推演**（600×400，首拖 0→10°，crop 全图）：提交时刻 live 渲染使
  display = AABB@10°（662×473）→ refit 以 662×473 为基准解 → crop 落地
  ~486px 宽 vs 真最大内接 532px（**−8.6%**），框不再贴旋转帧边缘；此后每次拖动
  按新 display 域递推，误差逐代累积。crop ≠ 全图 / upright 激活时偏差族另增。
- **测试盲区**：CropToolRotationTests 全部直接注入手值 frameSize
  （`SIMD2(600,400)`），接线层错误域不可见；走查 MANIFEST ①为单次拖动
  （rotation=0 起点恰使偏差部分对消），未含第二次拖动/回程核对。
- **修复方向**（供修复轮，单点）：frameSize 改传解码基准平面尺寸（与
  `uprightGuideMapper` 的 decoded extent 同源），或在 linkedSnapshots 内由
  span 反解 w0×h0；回归补一法「同一图连续两次角度提交，crop 落点 == withAngle
  闭式直解」。
- **定性**：App 接线缺陷（非移植面/非封存面/无数据损坏——sidecar 写入的是
  自洽但漂移的分数），用户可见（旋转后裁切框逐渐偏小、不贴边）。

### M-1（minor）导线 coordinate 通道把 upright 输出帧当 display 帧消费

`uprightGuideMapper` 截断域正确（upright 输入帧侧 ✓），但其 forward 输出域 =
upright **输出**帧；`UprightGuidesToolHost`（UprightGuidesOverlay.swift:337-341）
直接把 overlay 指针坐标当该域消费。crop 全图 + flip none 时两域重合（含
rotation ≠ 0），**crop ≠ 全图或 flip ≠ none 时画线错位**（存储域单向自洽、往返
<1px 不受损，校正与存储导线一致，但与用户所画位置不对应）。走查 ④ 场景（新图）
在正确域内。修复 = display 侧补 flip/crop 逆段（全链在 15.5 拆半组合）或工具
激活时约束 crop/flip 中性态。

### M-2（minor）plan AC「第 5 条拒 + toast」的 toast 面缺失

PLAN frontmatter 与 T4 AC 明文「≤4 上限 toast」；交付 = 模型层拒（press false）
+ 零 toast 面（overlay/panel 无反馈，xcstrings 无对应键）；MANIFEST ④ 措辞已从
plan 的「第 5 条拒 + toast」弱化为「第 5 条拒（画不出去）」——AC 元素静默蒸发，
DECISIONS/SUMMARY 未申报。修复 = 一键 + 一 xcstrings 键（ToastBar 通道现成）。

### M-3（minor）拖拽面不同步 session 选中态（upstream 两面 App 级偏离）

`onSelect` 只接 tap 路径（UprightGuidesOverlay.swift:253-266）；拖拽路径
（:229-251）模型内清/移 selected 但从不回写 `inspectorState.uprightGuideSelected`。
App 层偏离 upstream `drawing_a_new_guide_clears_the_selection`（画新线后选中
残留）与 `dragging_a_guide_endpoint_moves_it` 的「moved guide ends up selected」
（拖完高亮回跳旧选中）。模型层语义正确（测试过）、无数据风险（Delete 目标与
高亮自洽），但与 upstream 5+5 对照面的 App 级行为不一致。修复 = 拖拽 begin/release
各回写一次 session face。

### m-1（minor）CropFitAngle minFraction 数值偏离未申报

0.01（产 CropModule.minFraction / dt MIN_CROP_SIZE 传承）vs upstream
`MIN_CROP_FRACTION = 0.02`（crop_drag.rs:12）。语义正当（遵循本产拖拽模型下限），
但「直译」文件头注（CropFitAngle.swift:33-36）只引 dt、未披露 upstream 数值差
——按本路 mandate 属未申报静默数值偏离的文档缺口。修复 = 头注一行披露。

### obs（4 件）

1. **obs-1**：DECISIONS「Float 判等门」量纲表述含混（见 §7——「1e-6 归一门」
   vs 括号算术的 1e-6 px 门；建议勘误措辞，无行为影响）。
2. **obs-2**：Float 门独立数值复核成立（§7 全表——1e-3 px 门 80× 余量、谓词
   1e-6 归一门 48× 余量且尺度不变）。
3. **obs-3**：`UprightMath.vpError`（UprightMath.swift:115-125）死代码——
   upstream RANSAC 误差函数，Guided 面不消费（全仓零调用，含测试）。建议删除
   或注记封存意图。
4. **obs-4（环境登记，透明）**：①探针首轮误打 repo-local DerivedData（旧产物
   假象 2/0/0）→ 改默认路径重打真红；该路径禁形应入 LESSONS。②G4 贴线
   （25.47GB<25GB，本机既存态非本会话所致）两次透明越门（增量微构建 + 过滤轮，
   单轮峰 203MB；M9-3 SUMMARY 环境事件同款登记）。③死代理 env（10809 时通时
   断）两轮 SPM clone SSL 失败、剥 env 后 BUILD SUCCEEDED——DECISIONS 已知
   形态复现。

## 9. 判定

- **封存面/红线/归属/测试账本/zh 面**：全部通过，无保留。
- **upstream 直译保真度**：高保真通过（偏离全申报；m-1 为文档补一行级）。
- **定向三 bundle**：逐值复现通过。
- **E-1**：为用户可见功能缺陷（App 接线单点），**必修**——建议修复轮接线单点
  改正 + 一法回归 + 走查 MANIFEST ①补「二次拖动 + 角度回 0 复原」核对点；
  不推翻本批其余验收结论（移植面/封存面/测试面均不受其影响）。
- M-1/M-2/M-3/m-1：建议随修复轮顺路收口（各自单点、低风险）。

**终判：PASS / 1 error + 3 minor**——E-1 修复轮闭环后本批可签核；全套 --all
仍归 orchestrator 批准轮（本路未跑，沿批准制）。

## 附：本路证据与纪律

- 测试日志：`all-runs/acc2-iop.log` / `acc2-iopparity.log` / `acc2-app.log`
  （本路亲跑）；monitor：`/tmp/m93acc2-monitor.log`（零 RSS-KILL）。
- 探针补丁存底：`/tmp/m93acc2-probe1.md` / `/tmp/m93acc2-probe2.md`（主树已
  还原，`git status` 零残留）。
- 独立性：未读路 1 报告与 acc1-* 证据；upstream 全部经 `git show origin/main:`。
- 环境事件见 obs-4（透明登记）。
