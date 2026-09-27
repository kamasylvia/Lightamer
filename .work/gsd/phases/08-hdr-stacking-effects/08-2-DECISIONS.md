# Plan 08-2 — DECISIONS（执行期决策账）

> 计划纪律：RESEARCH/CONTEXT 未覆盖细节标注执行期决策，不臆造。续班会话（T3 bloom）的 B1-B5
> 收编于 §7。

## D-08-2-1 grain seed 的 imageIdentity 载体（最重要）

**research 终表要求** seed = StableHash(params ⊕ sidecar `imageID`)。执行发现 IOPiece/PixelPipe
不向模块暴露 imageID（`PixelPipe.imageID` 为 internal，IOPiece 无身份字段），且 IOPiece.swift /
PixelPipe.swift / PipeCoordinator.swift 均不在本 plan files_modified（W1 与 08-1 零文件交集纪律）。

**裁决**：seed 公式不变，身份载体 = **box instance UUID**（`GrainModule(imageIdentity: id)` 由
Registry 闭包注入）。性质核验：
- 同图同参 ⇒ 同实例 UUID ⇒ 同 seed ✓（session 内；sidecar 首写后跨启动亦冻结）；
- 同参异图 ⇒ 必异 ✓（paste 语义重铸 UUID "cross-image namespaces"，Pristine 每图加载独立铸造）；
- 缓存键不变量 ✓（PipeCacheKey 含 (imageID, paramsHash)，seed 为其纯函数且 instance UUID 在单图
  effective set 内稳定——dedup tuple (opName, multiPriority) 保证唯一实例；PipeCache 内存态，跨进程
  无键存续）。
**已知 wart**（SUMMARY §4 Manual-Only）：未编辑图（sidecar 未落盘）每次启动重掷 grain 图案——
sidecar 首写后 UUID 冻结、图案恒定。升级路径（additive）：IOPiece 增 imageID 字段由 PixelPipe.run
stamp（dt 的 piece->pipe 身份等价物），`GrainModule.imageIdentity` 换源即可，公式与测试不动。

## D-08-2-2 paper_resp 形态 = 解析直算包络（非 128² LUT）

dt 的 128² LUT 存的是 **Lab-L 域 delta**（固定 ±0.5 exposure 探针查表），线性域注入不可直接复用。
裁决 = 解析包络：`resp(l) = 4γ·eᶻ/(1+eᶻ)²`，`z = 4γ(0.5−u)/(1+2δ)`，`u = paper_resp_inverse(l)`
（:331-345 常量 DELTA_MAX=2.0/MIN=1e-4/PAPER_GAMMA=1.0 verbatim）——paper 响应的斜率即「中间调
偏置越大、暗部/高光颗粒衰减越明显」语义本体（:552 tooltip）。GPU 上 exp 直算无查表收益，省一条
texture 绑定。HDR luma 超纸域（l ≥ 1+δ）钳到白缘值（kernel 内注释；DECISIONS 同源）。float64 参考
同式镜像。

## D-08-2-3 seed offset 的坐标域 = 频率缩放后格点单位

dt `x + hash`（hash = 文件名哈希 % (roi.width·0.3)）在缩放前加——float32 下坐标达 ~1e6
（ulp 0.06 格），分数部分被碾碎（首版实测 kernel-vs-double 偏差 ~1e-2）。裁决 = offset 改**缩放后**
按格点单位加（`x·f/zoom + offset`），坐标上限 ~4400（ulp 2.4e-4），终像素误差 ~4e-5 ≪ 容差 6e-4；
quantum 定 4096（dt 的 % (width·0.3) 同量级；分辨率无关）。kernel/reference/测试三方同式。

## D-08-2-4 grain midtones_bias 默认 0（dt 源注 100.0 的偏离记录）

dt 当前源 `$DEFAULT: 100.0`；本 plan/research 两处独立明文「(0-100,0)」。裁决 = **0.0**（计划面
优先；`legacy_params` v1→v2 迁移注释「it produces the same results as the old version」锚 0 为
历史正典形态）。UI 滑杆范围/格式 verbatim。非「顺手改良」——两上游文档与 dt 注释冲突的忠实记录，
后续如需对齐 dt 当前默认改一行即可。

## D-08-2-5 grain parity 容差与「逐位」的物理边界

「float64 逐位比对」按字面不可满足：×32 终缩放放大 float32 坐标 ulp（坐标 ~4e3 → 噪声场 ~1e-2），
且 Metal 编译器许可 fma 收缩 + lattice 边界翻转（float32/double 在 `floor(xin+s)` 整数边界两侧
合法分叉，离散 O(1) 跳变）。裁决三层：
1. **逐字节硬对** = kernel-vs-kernel（同图同参两次渲染 bit-exact；同参异图必异）——缓存契约本体，
   无折扣；
2. kernel-vs-float64 参考 = 6e-4 绝对（终像素）+ **边界邻域屏蔽**（double 域 frac(xin+s) 距整数
   < 1e-3 的像素跳过值比较，翻转率断言 ≤3% 防vacuous）；
3. 谱锚 = 统计断言（zoom 无关形；第三 octave 在 256 域近 Nyquist 被混叠污染，钉前两峰——f/a 表
   值本体由参考 parity 覆盖）。

## D-08-2-6 vignette 尺度 setup 的坐标域映射

dt `buf_in->width` 族 = **原始图像像素**（roi_center = center×roi.scale − roi.xy 逐纲一致性的唯一
自洽读法；跨分辨率 cplen 不变性成立）。Lightamer 映射 = `dscIn / iscale`（L020 约定的半径消费者
先例）。公式其余逐字照抄。float64 setup 单一正本（`uniformSetup` 返回参考件类型），Float 窄化只在
kernel 派发沿。

## D-08-2-7 vignette/grain 中性种子面 + bloom 无中性

- vignette：brightness 0 + saturation 0 ⇒ 值恒等（任何 scale/falloff/shape 组合）→ ENABLED 时走
  routed-blit 快速路径；**种子实例仍 DISABLED**（dt 默认 −0.5/−0.5 非像素恒等，creative disposition
  ——参数面含默认值全程 verbatim，不改 dt 默认）。
- grain：strength 0 ⇒ delta 恒 0 → 同款 blit；种子 DISABLED（dt 默认 strength 25）。
- bloom：无零参恒等（threshold 90 默认在 HDR 域仍可提取；strength 钳位含 +1 偏置）→ 仅 DISABLED
  种子（pipe walk 跳过 = 恒等，机制既有已测）。面板重置目标 = dt verbatim 默认值。

## D-08-2-8 面板注册落点 + L010 identifier 表

files_modified 写 `IOPPanelProvider.swift`；实际 provider struct 随各 PanelView 文件（Soften 先例），
注册行在 `InspectorState.register`（真正分派面）。落点微偏记录在案。**L010 稳定 key 行全表**：
`inspector.slider.vignette.{scale,falloff,brightness,saturation,centerx,centery,whratio,shape}` /
`inspector.toggle.vignette.{unbound,autoratio}` / `inspector.panel.vignette` /
`inspector.slider.grain.{scale,strength,midtones}` / `inspector.panel.grain`（bloom 键由续班 commit
同款形态）。catalog 键：`panel_vignette_*` 14 键 / `panel_grain_*` 5 键（history_* 各 1）/ bloom 组
由 49db32c。PanelWiring 专项测试不在本 plan 面（L025 catalog smoke 模式已有 yiyin 先例覆盖格式）。

## D-08-2-9 层蒙版用例的采样几何

vignette 中心权重恒 0（fall-off 起点 = dscale 内零作用）——定位采样点取 (0.75w, 0.5h)（0.75·0.3
半径蒙版实心区内、距 vignette 中心 16px → weight ≈0.25 → 显示域差 ≈−0.06，阈值 −0.03 有 2× 裕量）。
蒙版外逐字节断言依赖 normal blend `a·(1−0)+b·0 == a` 位精确（非负通道；渐变 fixture 无 −0.0）。

## D-08-2-10 共享树竞态对策（过程性，供后续双跑 wave 复用）

私有日志副本（`sed 's|/tmp/la-direct-tests.log|…|' Scripts/test-direct.sh`）+ 构建重试循环（build db
locked 退避 30-60s）+ 失败清单即时提取（共享日志随时可能被并行覆盖）。对 08-1 在制品的最小编译
解锁（StackMergeService 自身类型引用去前缀）**不提交**、归属 08-1（BandStreamer 先例同款）。

---

## §7 续班会话（T3 bloom）决策收编

- **B1 σ 映射**：`sigmaSmall = max(0.3, max(0.5, radiusExec/16)/8)`、FIR 半径 `r = ⌈2σ⌉`
  （research §9.3 未锁具体 σ——P5 形状保留，参数已定）。
- **B2 blur 实现**：自研分离 FIR 高斯，不复用共享 Deriche-IIR `GaussianBlur`——float64 参考需逐式
  直译权威（IIR 状态递推镜像成本高且脆）。
- **B3 双线性上采**：kernel 内手写（rgba32Float 在 Apple GPU 不可 filter——纹理采样器过滤不适用）。
- **B4 无中性 blit 快速路径**：bloom 无静态零光晕参数面，L031 靠 makeEncoder 全覆盖（4 处 dispatch）；
  恒等 = DISABLED 种子。
- **B5 容差**：whole-chain float64 parity 1e-5 绝对（链长累计底线；参考为逐段同构直译）。
- **D-08-2-B-6（本班补记）**：bloom 线性阈值映射的 strength 位置 = dt CL 腿同序（缩放先于阈值
  比较，`bloom.cl` L=pixel.x·scale 形）——research §9.2 终式的实现顺序锚。
