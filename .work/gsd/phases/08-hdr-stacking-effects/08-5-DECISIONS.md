# Plan 08-5 执行期决策（D-08-5-*）

> RESEARCH/CONTEXT 未覆盖细节的执行期定夺，逐条编号。日期：2026-09-28。

## D-08-5-T0-1 EXIF E2E fixture 的 L 取 0.25（§1.2 交集带裁剪门避让）

带 EXIF 数值断言的 E2E（`testE2EEXIFBracketMergesToKnownLuminance`）首版 L=0.5：+1EV 帧像素
恰为 1.0 > clipGate 0.995 → §1.2 交集带为空 → 自检判「无法验证」。L 降 0.25（+1EV 帧顶值
0.5，全部落在 0.001–0.995 带内）。教训：比例自检的 band 门槛对 fixture 亮度有实质约束。

## D-08-5-T1-1 compatibility_mode 不移植

dt `hazeremoval.c` 的 `compatibility_mode` 只在 `_quick_select` 的 pivot 策略（中位三人 vs
固定中点）间切换——纯 CPU 排序顺序伪影，阶统计量（分位数值）数学上恒等，无任何结果差异。
Swift 参考用 sort 直取第 p 位，与 quickselect 的 order statistic 同值。不引入死参数。

## D-08-5-T1-2 A0 统计 = 固定 1024 长边降采样网格 + 内容哈希缓存

dt 的 gui_data 形态（preview 算、full/export 复用、pipe hash 失效）的 Lightamer 同形：

- **统计平面 = 固定 1024 长边 block-mean 网格**（`dehaze_ambient_grid` kernel）：读回上界
  12.6MB（1024×768×16B）——规避 full-pipe 兜底时整幅 1.63GB 读回（16GB 机内存红线）；同内容
  在 preview/full 两 pipe 的降采样估计相互一致（dt 的「full ROI 内估计不稳」结构性消解）。
- **缓存失效键 = 网格内容哈希**（StableHash over float bits ⊕ dims，L013）：上游/内容变更 →
  网格变 → 重算；**本模块自身参数变更（strength 拖动）不改输入平面 → 复用**——dt gui_data 的
  激励场景（滑杆拖动不重算 A0）按内容语义复现。跨 pipe 尺度差导致的哈希失配 → 本地重算
  （降采样网格使本地估计稳定，安全方向）。
- **dark-channel 窗口随网格缩放**：w1Grid = round(w1·gridW/W)（dt 不降采样故无此项；缩放保持
  暗通道支撑的物理尺度）。

## D-08-5-T1-3 合成雾反演 golden 容差 = 0.15（绝对，J 域）

plan 预留的容差决策位。断言带 = t ≥ t_min（dt 的 distance 深度限语义项——t < t_min 处恢复
**有意**不完整，不在容差带内）。0.15 的包络构成：①A0 阶统计估计对真值的偏移（黑点 lattice
+ 近零 t 边缘使 A0_est ≈ 0.994·A0，残差 ~1%）②box 近似平滑对 t̂ 的偏置（dot 主导的 box
max→min→mean 链，t̂ ≈ t·(1−ε)，ε ≈ 2–8%）③dot lattice 的 t̂ 系统偏置 ≤1.5%。三场景
（base/brightA0/deepHaze）全部实测 ≤0.05（钉 0.15 = 2.5× 余量）。fixture 依 prior 前提构造：
近零 t 边缘（纯空气光候选）+ 8px dot lattice（每 w1 窗见局部黑）+ 亮斑在清晰区。

## D-08-5-T1-4 执行期修复：box mean 是 2D kernel（stage probe 抓获）

dt 的 min/max 四 kernel 是 1D 行/列启动（get_global_id(0) = 行号/列号），transision/dehaze/
box_mean 是 2D 栅格。首版把 mean 对也走了 1D dispatchBox → 只处理 row 0、其余像素读到旧值。
表现 = parity 最大相对偏差 44×（中心像素恰落在 tMin 钳位平台而假绿）。新增 stage-by-stage
probe（kernel tmap/sA/sB vs 参考各级）定位后以 `dispatchBox2D` 分型修复；修复后 parity
6.6e-5 rel / 2.2e-7 abs。教训入 LESSONS 候选：多形 kernel 链的逐级探针应先于容差收敛。

## D-08-5-T1-5 dehaze 旗标/种子/中性面

- flags = `.supportsBlending`（dt `flags()` verbatim 无 ALLOW_TILING——全图环境光统计是原因；
  tileHalo 保持默认 0 = 整幅执行契约）。
- 种子 DISABLED（dt 默认 strength 0.2/distance 0.2 非像素恒等——creative 处置惯例）。
- strength==0 中性走 routed blit（(in−A0)+A0 的除法形式非逐位恒等）。

## D-08-5-T2-1 textOverlay 种子 ENABLED-neutral + lineSpacing additive 位

- 与非恒等 creative 模块不同：空内容（默认）**就是** routed-blit 恒等 → 种子 ENABLED 空内容
  （lut3d nil-neutral 先例，cache-neutral exposure-0EV style）。
- `lineSpacing`（行距增量占比，默认 0）为 additive 参数——多行排版的最小间隙旋钮，v1 参数面
  之外的最小增量（SC#4 无字面，不扩描边/阴影）。

## D-08-5-T2-2 几何契约：字号随长边比例、位置 y 向下、旋转逆时针绕块心

- fontSize 单位 = **1000px 长边参考下的 px**（effective = fontSize·planeLongEdge/1000）：
  绝对 px 在 100MP 全幅下会缩为尘埃，比例语义才满足「编辑期文字层」跨分辨率一致。
- posX/posY = 文字块**中心**的归一化坐标，y 自图像顶向下（图像空间惯例，与 CoreText 的
  y-up 分离在 rasterizer 一处换算）。
- rotationDegrees 逆时针、绕块心（kernel 以逆旋转回采样实现）。

## D-08-5-T2-3 光栅化形态：RGBA 白字上下文 + alpha 抽取 → r8Unorm

alpha-only CGBitmapContext 需要 NULL colorspace，Swift overlay 拒收（`CGContext.init` 的
space 非可选、`CGBitmapContextCreate` 被 Swift 6 替换诊断封锁）。取 yiyin 已验证的 RGBA
premultipliedLast 上下文画白字、抽取 alpha 字节为 coverage（白字时 coverage ≡ alpha）上传
r8Unorm。文字颜色 = 线性 RGB uniform 直加（无色彩矩阵——research §11.2 COLOR-2 不涉及）。

## D-08-5-T2-4 字体解析：YiyinFontStore 已装名优先，系统族 CTFont 回落

`resolveFont` 先查 YiyinFontStore（用户安装字体，目录惯例与 yiyin 共用），未命中走
`CTFontCreateWithName`（未知名 CoreText 回落默认字体，永不失败）。模块持自己的
YiyinFontStore 实例（无 shared 单例；同一 Application Support 目录 → 与 yiyin 面互通）。

## D-08-5-T3-1 LUT 判定形状：双表族测量 + 判定常量写死 + 32F 行为钉

- **双表族**：正域 HDR（[0.5,8]，research §13.3「half ~5e-4」预期面）与混合符号 HDR
  （±2.8，12-5 D7 破门形状，零穿越 cell）。相对误差分母 floor 1e-4（纯零点除法防爆，
  同时保留近零交叉的放大效应）。
- **实测**：正域 maxRel = **3.8e-4**（≤1e-3，16F 对正域面本可达标——research 预期证实）；
  混合符号 maxRel = **4.6e-1、78 点破门**——**D7 升格的常驻原因坐实**。
- **判定写死**：`rgba16FloatDefaultAccepted = false` 测试常量 + 分支——翻转需同时改常量并
  让双表族过门（「升格路径可编译可达、结论翻转只改常量」的字面兑现）。
- **32F 生产行为钉**：lattice 点值 4.0009765625（half 必失真）经 GPU 采样须逐位达 1e-5 内
  （16F 表会偏 ~2e-3）——存储格式不经内省即被行为锁死。

## D-08-5-T3-2 lut3d 矩阵列断言形状

列断言走真 pipe（注入 resolver 的 ModuleBox）：①HDR 域 identity 表 vs 无 LUT 链 ≤1e-4
（LUT 位不得弯折 HDR 链）②×2 gain 线性表恰放大 ×2（tetrahedral 精确复现线性函数）
③colorspace 取 rec2020（12-5 实证 = 恒等矩阵，列断言不被矩阵污染）。实测 1.2e-7 双绿。

## D-08-5-T3-3 preview 预算正式结论 + Release 秒表去向

- 上限断言 = 70MB/平面 ×1.05（2560×1707×16B 研究口径）+ 四管线缓存策略结构钉（preview/
  thumbnail 缓存、full/export 不缓存）——**合并不进缓存面新类，enforceBudget 五档零改，
  预算零增**。
- EDR drawable 16F @3008×1692×8B ≈62MB 注记（08-4 面，瞬态非驻留）。
- Release 全程秒表：`@testable` 与 Release 测试互斥（08-1 记录在案）→ 正式 Release 计量归
  Phase 15，与 D-09-05-T1-2「Release 计量只认 clean 构建」同批。

## D-08-5-T4-1 前序验收注记的消费方式

- 08-1 注记#2（Tile width:1 vs Full-width 矛盾）：`bands(height:width:)` 带全宽，几何测试
  改钉 width == 平面宽（`cd0b5b9`；消费方只读 y/height，零功能差）。
- 08-1 注记#4（「N 无关」断言同参自比的同义反复）：改显式 N 对照表 {1,2,3,4,5,8,16} 逐项
  相等 + 28/41 B/px 契约保留（同 commit）。
- 08-1 注记#3（torture 全链 parity 缩水）：随 D-08-1-13①② 收口——峰值重归一 4.0 绕开
  RGBAh 下溢后 patch 行/torture 诊断行双绿；≤6e-8 subnormal 面登记 L006 HDR 附件
  （真实产物值域 0.001–100 多在 half normal 域），非 Phase 8 阻塞。
- 08-4 注记（EDR toggle 瞬态单帧编码错配）：EDR 文件不在本 plan files_modified 集，additive
  不动，登记遗留（随 verify-work/后续 plan 酌情打磨）。
- 08-2 注记（grain 坐标 leg 用 roiIn vs dt roi_out）：同上不在本 plan 文件集，等几何 ROI 下
  逐字节等价，登记遗留（后续 plan 顺手对齐）。
