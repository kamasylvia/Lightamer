# 04-04 DECISIONS — lens correction 执行决策记录

> Plan 未覆盖点的裁决记录（任务书指令：写入本文件并继续，不停下等确认）。
> T0 三条按 plan 决策记录走（见 DISCUSSION-LOG 04-04-T0 节）；以下为实现期细化与分歧。

## 04-04-T0 数据分发 / 归一化 / 插值（plan 推荐采纳 + 细化）

- **D-04-04-T0-1 数据分发（Open Q4，采纳 plan 推荐）**：首跑从 `lensfun-data` GitHub master.zip 下载，
  落 `Application Support/Lensfun/version_1/*.xml`（`/usr/bin/unzip -j '*.xml'` 扁平解包）；
  设置经 `UserDefaults lensfun.customPath` 可指用户自备路径（覆盖）；下载失败/未配置 →
  (c) 层静默缺席、(b) 手动层照常。数据文件**不入 git**（D-G1）；测试用
  `input/golden/fixtures/lensfun/` 3 个手摘最小子集（注明 lensfun-data 来源 + trimmed，
  `.gitignore` 加 `*.xml` 例外——全库仍忽略）。
- **D-04-04-T0-2 归一化半径约定**（lensfun GitHub 源码钉死，`modifier.cpp` 头注释 + 各 `rescale_*`）：
  - lensfun 内部归一化坐标 = 以 real focal 为单位的自然坐标；Hugin 畸变/TCA 模型 r=1 于**半高**
    （长边中点 = landscape 半高，`mod-coord.cpp rescale` 分母 `hypot(36,24)/crop/hypot(aspect,1)/2`）；
    vignetting pa r=1 于**像角**（分母 `hypot(36,24)/crop/2`，无 aspect 项）。
  - `NormScale = hypot(36,24)/Crop/hypot(W+1,H+1)/RealFocal`；`CenterX/CenterY = 0`
    （子集无 `<center>`，Parser 保留字段，缺省 0）。
  - **kernel 内约定（两侧统一）**：`u = (p − c)/halfW`，halfW = 输入平面半宽；
    XML 系数在 resolve 期经 `(NS·HW)^幂` 换算喂入（畸变 k'·(NS·HW)²、ptlens a/b/c × (NS·HW)³/²/¹、
    TCA cr/cb × (NS·HW)、br/bb × (NS·HW)²、vr/vb/linear 不变、vig k1/k2/k3 × (NS·HW)²/⁴/⁶）。
    `NS·HW` 与分辨率无关（`21.633/Crop·(HW/diag)/F`），preview/full 同参同貌。
    结论进 `LensKernels.metal` 头注释（T0 acceptance）。
- **D-04-04-T0-3 插值语义**（`lens.cpp` 逐式）：
  - distortion/TCA focal 维 = 4 点 Hermite 样条（`_lf_interpolate`，`auxfun.cpp`；边点 FLT_MAX 退化
    切线 = y3−y2；exact match 直取；非 ACM 的 `__parameter_scales` 为恒等——v1 无 ACM 数据）。
  - vignetting = IDW p=3.5（三维归一距离：focal 线性按 calib 焦段归一、aperture→4/a、distance→0.1/d；
    exact <1e-4 直取；最小距离 >1 →  miss 返回 nil 降级手动层）。
  - `MinFocal/MaxFocal` 取该镜头 vignetting 标定焦段 min/max（lensfun 从 lens 聚合；v1 等效近似，落账此处）。
  - cropfactor 选集：`imageCrop/setCrop ≥ 0.96` 且比值最小（`lens.cpp` 口径）；无满足 → miss。
    AspectRatio 缺省 1.5（v1 数据多无 `aspect-ratio`；lensfun 默认同值）。

## 实现裁决（plan 未覆盖）

- **D1 vignette 方向（与 plan 字面分歧，lensfun 为准）**：plan 写 `I' = I·(1+k r²…)` 前向乘；
  lensfun correct 模式实为 **devignette 除法**（`mod-color.cpp ModifyColor_DeVignetting_PA`：
  multiplier = `1/c`，`c = 1+k1 r²+k2 r⁴+k3 r⁶`）。kernel 取除法语义（XML 负 k 角落变亮 = 真校正；
  plan 字面乘法配 XML 负 k 会越校越暗）。手动滑块语义随之 = “镜头实测暗角系数”（与 XML 同号），
  默认 0 = 恒等。顺序仍先 vignette 后查样（`lens.cc:1194-1206`，在**采样点**半径处求值——
  dt 先对输入 buf 施加再 warp，等价于 fused kernel 在畸变后坐标处求 V）。
- **D2 统一多项式（精度只增）**：kernel 畸变取全式 `Rd = Ru·(1+dc1 Ru+dc2 Ru²+dc3 Ru³+dc4 Ru⁴)`；
  poly3→dc2、poly5→dc2/dc4、ptlens→dc1/dc2/dc3（`a,b,c` 经 d-factor 重标后精确映射，
  `mod-coord.cpp` 注记 `a'=a/d⁴, b'=b/d³, c'=c/d²` 逐式）；TCA 取全 6 项
  `(vr,cr,br/vb,cb,bb)`，manual `tcaR/tcaB` → `vr=1+tcaR` 其余 0（plan 的“poly3 按半径展开”
  改为精确直通——kernel 本来就算 radius 多项式，展开反而引入近似）。
- **D3 TCA/distortion 复合顺序**：先畸变 D，后 TCA 在畸变后半径处求值
  （lensfun 回调链顺序：CoordCallbacks distortion 750 → SubpixelCallbacks TCA 500，
  `ApplySubpixelGeometryDistortion` 先后执行——同一 buffer 链式）。
- **D4 出界语义**：clamp taps（plan 字面；lens 边缘拉伸非黑角——与 ashift 透明黑区分；
  ROI grow 后边缘像素采样 clamp，最坏情况边缘 streak 而非黑边，内容测试钉住）。
- **D5 中性/病态 → blit 恒等**（ashift D5 同款：管线拥有 enablement，模块不碰）；
  中性谓词 = 全部 k/dc/tca/vig 零 + `vr==vb==1`（eps 1e-6）；`source` 不参与谓词
  （lensfun resolve 全零同样恒等），`source` 只决定系数来源 + 面板文案。
- **D6 EXIF→resolve 数据流**：`reloadDefaults(image:)` 从 `CaptureMetadata`
  取 `cameraMake/cameraModel/lensModel/focalLength/aperture`（distance 无 EXIF 源 → NaN 缺席标记）→
  DB 匹配命中则 `source=.lensfun` + 快照 `focal/aperture/lensKey` 进 Params（自描述，跨 pipe 边界；
  flip `.auto` 分歧同理）；miss/无数据 → `.off` 全零。`commitParams` 只做哈希 + working copy
  （几何尺寸 process 期才知——ashift D2 同款）；resolve（focal 插值 + 系数换算）在 process 期执行，
  DB 经 `LensfunStore` actor 首用加载（路径：customPath > App Support > 缺席=nil）。
- **D7 帧约定（L020 前置，注释钉死三处）**：forward walk 输出 `levelROI` xy 即上游相对原点；
  `modifyROIOut` 保持 `x/y = input.x/y` 只重算 w/h（输入帧边框点经 D（G 通道）前向映射 → AABB + 2px）；
  `modifyROIIn` 收到的 roi 已是输出帧坐标，边框点经 D+TCA（R/G/B 三组）前向映射 → union AABB + 2px
  → clamp bufIn（**无 Newton 反解**——dt `_modify_roi_in_lf` 同样用 correct-modifier 前向映射边框，
  `lens.cc:1741-1758`）；`process` 按 `(gid+oroi − roiIn − c)/halfW` re-base（ashift 同式，
  中心用 `dscIn/2 − roiIn.xy` 全帧光心——crop 在 lens 下游故 lens 恒见全幅上游，roiHint 子窗同样正确）。
- **D8 测试 XML 内联 + 子集文件双轨**：`LensfunDBTests` 用内联最小 XML 字面（hermetic，不依赖
  `/opt/homebrew`）；`fixtures/lensfun/` 3 文件供人工对照 + 跨实现核对（commit 进 git，gitignore 例外）。
- **D9 下载实现**：`URLSession` 拉 master.zip → `/usr/bin/unzip -j '*.xml'`（非沙盒独立分发允许
  Process；Archive 框架版本不确定性规避）；成功校验（≥1 xml 可解析）→ toast；失败 toast + 降级。
  网络路径无单测（降级态有单测：无数据目录 → resolve nil → 手动层正常）。
