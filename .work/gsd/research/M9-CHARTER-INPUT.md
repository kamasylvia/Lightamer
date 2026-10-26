# M9 CHARTER 输入 — 五仓增量调研与候选站组成（2026-10-25）

> 调研批产物（纯文本，零 commit）。任务：深读 M8 后五仓 9 天增量（AlcedoStudio +138 /
> lumen-raw +8 / SpektraLab +518 / lightcraft +1031 / RawLab +203；darktable/yiyin 零增量）
> → 对照我方现有面 → 产出 M9 charter 候选输入呈用户裁决。
> 方法注记：五仓本地 checkout 均落后，增量一律经 `git log/ls-tree/show origin/main`
> （或 RawLab `origin/development`）读取；我方现状引用带 file:line，上游带 repo 路径。
> GPL 三仓按行为对照写（复制决策留 charter）；MIT/Apache 仓可复制件逐处标明。

---

## 0. 调研总结论（一句话版）

1. **Alcedo +138 的 ~90% 是 AI Mask 工具**（0.3.4 主功能，SM1-SM9 十六个子阶段）——
   parity 主料成立，但**我方无需跟其模型路线**：macOS 27 `GenerateIterativeSegmentationRequest`
   （我方 Layer B，`LightamerCore/Sources/AI/AIMaskService.swift:18-24`）原生覆盖其
   SAM 2.1 交互分割能力；真差距 = 任务蒙版面（Sky/Background 缺）+ 编辑会话语义 +
   GPU Expand + coverage 显示面。
2. **任务书预设的 dehaze/clarity「真缺口」不成立**：我方已有 DehazeModule
   （dark-channel-prior，Plan 08-5-T1）与 Clarity（Equalizer EIGF，Plan 04-05-T2）；
   RawLab 的同名件走闭源 sony2fuji 引擎 atmosphere API，无可读算法面——**排除**。
3. RawLab AI 降噪（Restormer/DualDn）**许可 + 架构双壁垒排除**：DualDn = CC BY-NC 4.0、
   Restormer = Academic Public License（均禁商用，开源再分发风险）；且需解包 Bayer 原始
   数据，我方 CIRAW 路线不暴露。
4. **光谱延展站主料扎实**：SpektraLab 黑白胶片族（4 film + Multigrade IV RC 相纸 +
   逐胶片 granularity 发表值）与 camera_filter（8 Wratten 81 点透射谱）**天然落 M8
   光谱核**（谱链感光积分前乘透射谱 = M8 tc 上采样产物直接消费）；M8-3 已收口
   （全套 4286/46/0，2026-10-26），地基就绪。
5. **Guided Upright = 意外真缺口**：我方几何面 = Crop 纯裁切框（`CropModule.swift:63-70`，
   无 rotation/透视）+ Flip + Liquify；lightcraft `upright.rs` 611 行 MIT OR Apache-2.0
   可移植，且我方 Pano homography 数学基建（`PanoCamera.swift:95 focalFromHomography`）可复用。

---

## 1. 候选站 A/B 两案

### A 案（orchestrator 原口头推荐，存档对照）

AI Mask 交互 parity 主料 + 光谱延展站 + dehaze/clarity + 小件池。

**调研后失效点**：dehaze/clarity 我方已有（见 §0.2），直接从候选中剔除；其余三站成立。
A 案不再展开，其有效部分被 B 案吸收。

### B 案（调研后修正案，推荐）

四站 + 一池，总量级 **L 档**（对比 M8 的 +60..82N，M9 估 +55..75N，C 档门控四段）：

| 站 | 内容 | 量级 | 工期档 | 主依赖 |
|---|---|---|---|---|
| **站 1：AI Mask 工具 parity** | 任务蒙版四件（Subject/Background/Sky/People）+ viewport 交互面升级 + 编辑会话语义 + GPU Feather/Expand 面板化 | **M-L**（20-28N） | 3-4 周 | macOS 27 Layer B（已就绪）；Sky 路径待 OQ-2 |
| **站 2：光谱延展（黑白域 + 滤色镜）** | BW 胶片族 profile 化 + channel bw 单通道化 + 变反差相纸（m/y filter）+ camera_filter 谱域乘法 + per-film granularity 标定 | **M**（15-20N） | 2-3 周 | M8 光谱核（已收口）；BW/滤色镜数据包构建 |
| **站 3：几何校正（Upright 系）** | rotate/straighten 几何基座 + Guided Upright（≤4 导线）+ auto straighten | **M**（12-18N） | 2-3 周 | lightcraft MIT 移植 + Pano homography 复用 |
| **站 4：小件池** | ColorWheels LGG+Offset 语义修订（含旧档迁移）、LUT encodings +24 条 + searchable picker、Filmstrip rating stars、图库 Show in Finder | **S-M**（10-15N） | 1.5-2 周 | 无外部依赖 |

**挂起件（不入 B 案主线，逐项 OQ 裁决）**：AI removal（LaMa）、landscape masks（语义
分割五类）、自更新（Sparkle）、半幅对/全景幅面、film edge/date back、grain 接谱。

**串行编排建议**：站 1 → 站 2 → 站 3 → 站 4（站 1 是 parity 正本主料优先；站 2 消费
M8 刚收口的地基热乎劲；站 3/4 无依赖可按 orchestrator 排程穿插）。每站执行+验收闭环
后 C 档停汇报。

---

## 2. 逐候选条目（差距面 → 上游形态 → 落地路径 → 依赖与许可 → 量级）

### 2.1 AI Mask 工具 parity（站 1，M-L）

**上游形态**（AlcedoStudio origin/main，master plan
`docs/roadmap/alcedo_studio/edit/ai_segmentation_mask_master_plan.md` + SM9 plan）：

- 模型集（§8.2）：SAM 2.1 Hiera tiny encoder（macOS CoreML 134MB / ONNX 109MB，
  Apache-2.0）+ prompt decoder（21MB，Apache-2.0）+ people_sky_head（1.1MB，自有）+
  S3OD s3od-synth（271MB CoreML，MIT + DINOv3 License）。macOS 实测：encoder 191ms/图、
  decoder 33ms、S3OD 531ms/图、全载内存 3.19GB（M4）。
- 交互流（SM9 plan §1）：任务四件 icon（Subject/Background/Sky/People，People 列表
  点选 person）+ 三 prompt 工具（Point/Box/Path，≤64 点）+ Add/Subtract + Click level
  + Feather/Expand + 会话 Undo/Redo + 单 Confirm 按钮；面板黄框转 + 五段开进度 +
  阶段进度条。
- 编辑会话（D16/D17/D20）：两级 history（session 内存栈，Commit 才发布 1 条主 history
  op；Cancel 零发布）；R8 coverage asset 内容寻址存项目库（bounding rect + margin，
  ≤4096 轴）；Feather/Expand 是 mask source 字段（改值不写 asset）；paste 不拷 AI Mask
  （D18）；几何指纹 + 失配提示（D9/P6，SM7）。
- 显示（SM8）：coverage 专属视口通道（RGBA32F 红通道承载），淡红 tint
  （maskCoverageTintColor 主题角色，#515），Commit 后隐藏；候选/已提交/Grade Union 共用
  一次 viewport composite；GPU Feather/Expand 三后端（CUDA/OpenCL/Metal）。
- sidecar 治理：模型闲时停/按需载（U6：回到调节即卸载）、S3OD 常驻（D22）、embedding
  缓存 4 张（B2）、分析渲染走 ReferenceSpace 无 crop/rotation（D7/D8）。

**我方现状**（file:line）：

| 面 | 现状 | 差距 |
|---|---|---|
| 交互分割 | `AIMaskService.swift:18-24` Layer B `GenerateIterativeSegmentationRequest`（seed point/box/scribble + addIncluded/addExcludedPoint，`buildLayerBRequest:366-410`）+ `SegmentEditingOverlayHost.swift`（click seed / ⌥-click excluded / ⇧-drag box / confirm → bake） | 点/框/加减点**已有**；Path（多笔触采样）缺；click level 缺 |
| 任务蒙版 | subject（Layer A `GenerateForegroundInstanceMaskRequest` 两段式）/ person（`personSegmentationMask:428` + 实例 `personInstanceMasks:538`）/ skin / depth 五源（`AIMaskEditing.swift` AIMaskSource） | **Background（=1−Subject，纯逻辑）与 Sky 缺**；无任务面板入口 |
| 会话语义 | `AIMaskEditing.swift`：AI 生成参数**不持久**、bake 成普通 raster PNG（AI-06 非黑箱哲学）、每次 confirm = 1 条 stackSnapshot | 无独立编辑会话栈（undo/redo 直通主 history）；无「会话中保留旧 coverage + 失败 Retry」面——我方 confirm 即 bake 的形态更简单，**范式差异需裁决**（OQ-1 附带） |
| Feather | `AIMaskFeather.swift`（±100 双腿：正 = GPU bake Deriche，负 = logit-gain） | 已有；**Expand 缺**（全仓 grep 无 expand iop 面） |
| 精修 | `MaskRefine.swift`（lumen MIT 采样抠图，发丝级） | **超集**（Alcedo 无对应件；U3 明示不做边缘后处理） |
| 显示 | `MaskToolbarView.swift:136-140` maskOverlayStyle tint 交换；`AIMaskEditing` commit 后 mask edit mode + display tint | 无独立 coverage 通道（走 mask edit tint 语义近似）；候选态 live 预览形态简 |
| 模型治理 | `ModelAssetCatalog/ModelAssetStore/AIAssetStatus.swift`（自管目录 + digest）+ Layer B `DownloadableAssetsRequest`（Apple 官方一次性下载，`modelNotReady` typed 门控） | **已有**（且无需 sidecar 进程——Vision 进程内）；无「闲时卸载」面（Vision 按请求载卸，天然满足） |

**落地路径**：

1. 任务蒙版面板（MaskToolbar 扩展或独立 sheet）：Subject（Layer A 现成）/ Background
   （1−Subject 纯函数）/ People（person instances 现成）/ Sky（OQ-2 裁决路径）四 icon；
2. Path prompt 工具：`SegmentSession` 扩笔触采样（Alcedo 24px 间隔 ≤16 点/笔参考）；
   Layer B `addIncludedPoint` 序列投喂（macOS 27 API 逐点迭代，等价 SAM 多点）；
3. Expand 算子：形态学膨胀（与 feather 同 GPU bake 缝，`RasterMaskStore.bake` 邻位）；
4. 会话升级（可选深度）：SegmentSession 内存栈 + confirm 单 commit（已有）+
   live 候选 coverage tint（maskOverlayStyle 扩候选态样式）——**不引** Alcedo 的
   R8 asset/sidecar 进程/模型下载面板（我方参数不持久哲学 + Vision 进程内天然免）；
5. 几何指纹失配提示（D9 类）：mask 记录 decode 几何 fingerprint，lens/decode 参数变更
   后提示（对齐我方 raster mask 同款问题——现状同样不校正，加提示即可）。

**依赖与许可**：零新模型引入（Sky 除外，见 OQ-2）；零第三方代码复制（行为对照）。
若 Sky 走 lumen EfficientViT-Seg = MIT 模型转 CoreML（引入裁决）。

**量级**：M-L（20-28N）。任务面板 4-6N；Path 工具 3-5N；Expand 3-4N；会话/coverage
显示 5-8N；几何指纹 3-5N。

### 2.2 光谱延展站：黑白域 + 镜头滤色镜（站 2，M）

**上游形态**（SpektraLab origin/main）：

- **黑白胶片族**（`engine/resources_product/profiles/`，NOTICE.md 声明 = SpektraLab
  自有产品数据，非 spektrafilm 衍生）：Tri-X 400（F-4017）/ T-Max 100（F-4016）/
  Acros II（AF3-0258E）/ HP5 Plus 400 各一 JSON，81 波长谱敏感度 + D-76 特性曲线
  （厂商 PDF 矢量/栅格数字化），`channel_model: "bw"`（单乳剂写三通道，银密度 1/3 每
  通道）+ `target_print: ilford_multigrade_iv_rc`；相纸 Multigrade IV RC（三乳剂变反差，
  HARMAN 数据表拟合）+ `paper_grades.json`（滤镜 00-5 → m/y_filter_neutral +
  print_exposure，Tri-X 上拟合、四片灰位同密度验证 `bw_checks.py`）。
- **granularity**（commit `d610ac9`）：per-film `ownGrain` 换算——滑杆 1 = 厂商发表
  RMS granularity；实测标定（6µm 像素 / net density 1.0 / 48µm 孔径）：Tri-X 17 /
  T-Max 8 / Acros 7（Microfine 下限）/ HP5 16；wire 值 = 发表值（Tri-X 1.70 / HP5
  1.49 / T-Max 0.74 / Acros 0.64），wire 上限 2。
- **camera_filter**（commit `6d46e08`，`engine/src/core/camera_filters.hpp`）：8 个
  Wratten（w8 黄 / w11 黄绿 / w12 深黄 / w15 深黄 / w21 橙 / w25 红 / w47 蓝 / w58 绿）
  各 81 点 5nm 透射谱（Kodak B-3 公开转录，Usenet 1992 数据源）；**SHOOT 域**（拍照时
  镜头上）——透射谱乘胶片感光度谱、在 tc 上采样表**之前**；edge print/fog/date back
  读未滤光谱；对照 F-4017 滤镜因子验证（7 个中 6 个 ≤0.21 档）。
- 半幅对（half-frame pair，一卷两框）/ 全景幅面（XPan/6x12/6x17）+ film edge/
  date back + halation 开关 + highlight boost（详见 §4 排除与挂起）。

**我方现状**：

- M8 光谱核全链已收口（`.work/gsd/phases/m8-fsim-spectral/` 四 plan；CONTEXT.md Phase
  Goal）：scene-linear → CAT16 → xy → **tc 光谱上采样** → 感光积分 → DIR coupler →
  dichroic 印相 → 相纸 → 扫描 CMFs；process v2 双臂（光谱 current / 密度 legacy 冻结）。
- 胶片资产：`Resources/FilmProfiles/`（spektrafilm 28 profile CC BY-SA + 中性印相
  滤镜）——**全彩色负片/反转，无黑白**；`FilmMaterialStore/FilmProfile.swift` 无
  channel_model 面板。
- 印相段：`FilmFilterPackSolver` + `paper_grades` 类 m/y dichroic 增益面（M3-3
  s_m/s_y）已有；变反差相纸（grade 滤镜 00-5）无。
- grain：M8 D-M8-4 明示「grain/halation/diffusion/highlight boost/glare 不入 M8
  （挂账）」；我方 Grain IOP（dt 遗产独立承载）无 per-film 物理标定。
- 滤色镜：无任何 camera_filter 面。

**落地路径**（全部消费 M8 谱链，零新 kernel 族预期）：

1. **camera_filter**（最小闭环）：FilmRecord 或 document 级新字段（SHOOT 域语义 =
  decode 后第一站）→ 81 点透射谱乘 tc 上采样谱（SpectralFilmKernels 感光积分
  stage 前插乘法）——**注意 M8 冻结红线**：`FilmSubRunKernels.metal` 恒零 diff，
  谱链乘法落在 `SpectralFilmKernels.metal` 自有区段或新 .metal；Wratten 数据表
  自建（Kodak B-3 转录数据 = 事实数据，公开来源，非 GPL 代码——数据表独立重录，
  NOTICE 引来源页）。
2. **BW 域**：profile 侧加 `channelModel: "bw"`（单乳剂三通道同值）+ 四 BW profile
  资产构建（厂商数据表数字化流程照 SpektraLab 方法面：矢量路径/栅格 600dpi 描点 +
  假设标注——**行为对照，数据自建**）；谱链单通道化 = 感光积分输出单通道 + 印相
  段配变反差相纸；变反差 = paper m/y filter 对已扩展（`paper_grades.json` 形态 =
  grade→m/y/exposure 三元组表，相纸 profile 三乳剂）。
3. **granularity**：grain IOP 加 per-film 标定面（profile 侧携带 published RMS +
  实测换算表；grain IOP 强度 1 = 发表值）——grain 消费属 M8 挂账项的**部分解冻**
  （仅标定面，不动 grain 算子本体）。

**依赖与许可**：GPL-3.0 仓（SpektraLab）——行为/结构对照为主；若直接复制其
profile JSON 数据文件 = GPL 同许可可复制（2026-10-20 切换后合法，保留版权 +
NOTICE + 标注修改），但**建议自建**（厂商数据表数字化 = 事实数据，自建后 NOTICE
干净、无 GPL 传染面；同 MIT LUT/CC BY-SA 谱面分仓物理隔离先例）。granularity
标定常量（17/8/7/16）= 实测事实值，引用无碍。

**量级**：M（15-20N）。camera_filter 4-6N；BW profile 化 + 单通道化 5-7N；变反差
相纸 3-4N；granularity 标定 2-3N。

### 2.3 几何校正：rotate/straighten + Guided Upright（站 3，M）

**上游形态**（lightcraft origin/main）：

- `crates/pipeline/src/upright.rs`（611 行，MIT OR Apache-2.0 可复制带归属）：
  ① 线段检测（梯度 level-line 方向一致区域 + 加权主轴拟合）；② 消失点（近垂直/
  近水平分组 + RANSAC 线对 + 加权最小二乘精化 `Σ w·l·lᵀ` 最小特征向量）；③ 校正 =
  虚拟相机旋转 `K·R·K⁻¹`（Level 纯旋转；Full 双消失点 + 正交性估焦距）；**Guided
  Upright = ≤4 条用户导线解同问题**（`fbc927f0` 拖拽画导线/端点编辑/`7635b38c` 选中
  删除）；坐标 = 居中归一（lens 校正后），分辨率无关。
- auto straighten 防呆（`693c3593`）：仅 ≤10° 且 ≥3 一致线才转，找不到就明说
  （实测 300 张原样片：误转 79→19 张）。

**我方现状**：

- 几何面 = `LightamerIOP/Sources/Crop/CropModule.swift:63-70`（left/top/right/bottom/
  ratio 纯裁切框，**无 rotation 字段**）+ Flip（h/v 翻转）+ Liquify（位移场）+
  Lens（Lensfun，LENS-01）。
- **旋转/拉直/透视校正全缺**——v50 序无对应 iop；crop UI 无角度轮。
- 可复用基建：`PanoCamera.swift:95 focalFromHomography`（单焦距 + N 旋转结构，
  homography 闭式估焦距）+ `GeometryPointMapper.swift`（几何点映射单源）+ M2-4
  EdgeMapField（线段检测的梯度基建同类）。

**落地路径**：

1. 新 iop `rotate`（v50 add-only 纪律，geometry 段 Flip 邻位）：角度参数 + 画布角度
   轮交互（crop 工具扩展）；auto straighten = 线段检测 + 主方向角（lightcraft
   防呆参数照抄：≤10°、≥3 线）；
2. 新 iop `perspective`（upright）：upright.rs 数学移植（MIT OR Apache-2.0，Swift
   重写带归属；RANSAC/消失点/K·R·K⁻¹ 纯 CPU Float64 构建期一次解 → homography 下发
   GPU warp——与 Lens warp 同 dispatch 形态）；
3. Guided 导线 UI：viewport overlay 画线/端点拖拽（MaskOverlayHost 同款 overlay
   模式复用）；Level/Full/Auto/Guided 四档；
4. 裁切联动（自动裁有效区，lightcraft `54c6c43b` Constrain Crop 类）。

**依赖与许可**：lightcraft = MIT OR Apache-2.0（CONVENTIONS 参考项目表在册）——
代码可复制带归属（NOTICE 条目）；数学自主实现亦可（公式公开）。零模型依赖。

**量级**：M（12-18N）。rotate + auto straighten 4-6N；upright 数学 + iop 4-6N；
Guided UI + 裁切联动 4-6N。

### 2.4 小件池（站 4，S-M）

| 小件 | 上游形态 | 我方现状 | 落地 | 量级 |
|---|---|---|---|---|
| **ColorWheels LGG+Offset 语义修订** | Alcedo `e1effd8` + `color_wheel_tonal_lgg_plan.md`：归一化影调坐标 t∈[0,1]（黑 −6EV..白 +6EV，中灰 t=0.5），Lift 支点 t≥1 / Gamma 幂 t^p（p=ln(0.5+K/R)/ln0.5）/ Gain 支点 t≤0 / **Offset 整体平移**；K 单位 EV；kDiscMaxStops=1.0、kMasterMaxStops=2.0；CPU 预计算 p 与 K/R 下发，kernel 查表级；旧档读入时**参数转换** + 无旧公式分支；UI 改名 暗部/中间调/高光/整体 | `ColorWheelsModule.swift` + `ColorWheels.metal`（M2-5-1 T6）= **逐字照抄 Alcedo 旧 CDL 公式**（`out=\|c+lift\|^(1/gamma)·gain` 直接作用 ACEScc——正是上游已废弃并修订的语义；三支点全在可见范围外，Lift≈整体乘法） | 数学照 `color_wheel_tonal_lgg_plan.md` §3 重写 kernel（单公式无分支）+ `ColorWheelControl` 加 offset 第四轮 + 旧档迁移（Alcedo 转换式对照）+ UI 四轮改名。**GPL 行为对照**（公式数学不受版权保护） | 4-6N |
| **LUT encodings 扩充 +24 条** | Alcedo `eedc0c0`：catalog 26→50 条（ARRI LogC3 EI 160-1600、Canon Log 1/2/3 × BT.2020/BT.709 gamut、Cineon、REDLogFilm、F-Log2 C、Apple Log 2、L-Log、KineLOG3、GP-Log2；每条曲线+gamut 带厂白皮书源）+ `0fa8548` searchable encoding picker | `LutEncodingCatalog.swift:32-52` = 16 条（scene 8 + display 8） | 逐条 Float64 正逆族补录（M3-1-01 表驱动形态平移；厂白皮书源照上游登记法）+ picker 加搜索框。行为对照 | 3-4N |
| **Filmstrip rating stars** | Alcedo `7ccb0ec`：磁贴双态（editing/selected）+ caption 两行（stars 右对齐 + 文件名）+ 被过滤掉的打开图关闭 | `FilmstripView.swift:269-329`：跟随 Library 过滤器（`LibraryGridModel.rows` 同游标，20 行注释在案）+ selection ring + current accent dot + 文件名 caption——**无 stars** | `FilmstripRowView` caption 扩 rating 星（`LibraryImageRow` rating 字段现成，M2-9 命名模板已消费盘上 rating 同源）；editing/selected 双 token 细化 | 1-2N |
| **图库 Show in Finder** | lightcraft LR 面 / lumen 常规件 | 仅导出后 reveal（`PostExportActions.swift:173 revealInFinder`）；图库对原图无 | LibraryGrid contextMenu + 键盘 ⌘⇧R → `NSWorkspace.activateFileViewerSelecting`（PostExportActions 同 API 复用） | 0.5-1N |
| **（挂起）自更新** | lumen `dd53fcd` in-app updates（update feed + 增量模型下载 + 安装器接力）；lightcraft craft-update + startup prompt | 无（unsigned DMG/zip 分发，2026-09-27 终裁） | **OQ-6**：Sparkle 框架（unsigned app 适配 appcast 自建）vs 不做（用户手动下载）。**注意**：unsigned + 无公证 → Gatekeeper 提示常态化，自更新体验打折 | 挂起 |

**依赖与许可**：全零第三方依赖；ColorWheels/LUT = GPL 行为对照（数学/数据自建）；
Show in Finder = 原生 API。

---

## 3. OQ-M9-x 裁决点清单（charter 门用户裁决）

| OQ | 问题 | 推荐与理由 |
|---|---|---|
| **OQ-M9-1** | **S3OD 类交互分割是否引 CoreML 模型**（跟 Alcedo SAM 2.1+S3OD 路线）？ | **推荐：否**。macOS 27 Layer B（`GenerateIterativeSegmentationRequest`）原生 tap-to-segment + included/excluded 点迭代，我方已建成（07-3 面已上线）；Alcedo 引模型是跨平台（Windows DirectML）无奈之举，且 427MB 模型 + 3.19GB 内存 + 下载面板 + sidecar 进程全是我方免付成本。**附带裁决**：我方 bake-to-raster 非黑箱哲学（AI-06）vs Alcedo AI Mask source kind + R8 asset——保持我方范式（参数不持久 + 像素即真相），charter 里显式声明为合法 parity 偏离（同 DRT pristine 先例） |
| **OQ-M9-2** | **Sky 任务蒙版路径**？Vision 无原生 sky 分割 API（person/foreground/saliency 有，sky 无） | 三选：**A（推荐）** 首发砍 Sky（面板三件 Subject/Background/People，Sky 留槽）——Sky 使用频率 + 无原生路径；**B** 引 lumen EfficientViT-Seg B2（MIT，ADE20K 五类含 sky）转 CoreML——顺带解 landscape masks（OQ-4）但引 ~XX MB 模型 + 离线包下载面；**C** depth/saliency 代用启发式（质量无保证，不建议） |
| **OQ-M9-3** | **AI removal（LaMa inpainting）是否 v1/M9**？ | **推荐：M9 不入，挂起**。lumen 2.1.0 形态 = big-lama ONNX CPU（全分辨率上下文 ≤1024px 模型侧）+ 16-bit RGBA patch 存 remove retouch op + grain 补回——工程面完整可参照；但 LaMa 模型引入（big-lama Apache-2.0 可合法）+ retouch op 扩展 + 队列/export 等待面 = M 级独立站，超出 M9 预算。**若用户强需求可换掉站 3** |
| **OQ-M9-4** | **landscape masks（water/vegetation/mountain/building/ground 语义五类）入不入**？ | **推荐：不入**（与 OQ-2 B 路绑定）。仅当 OQ-2 选 B（引 EfficientViT-Seg）才顺带激活；独立立项价值低（我方蒙版体系已厚，语义类是锦上添花） |
| **OQ-M9-5** | **黑白域幅面（半幅对/XPan/6x12/6x17）入不入**？ | **推荐：不入 M9**。SpektraLab 的幅面 = 胶片画布（strip + 底片框 + overscan）产品形态，我方无胶片画布概念；若只要「输出裁切比例预设」（XPan 65:24 等）= 站 4 加 3 行 ratio 预设的 trivial 件，可随手并入（不单列） |
| **OQ-M9-6** | **自更新（Sparkle）入不入**？ | **推荐：不入 M9，挂 UPSTREAM-QUEUE**。unsigned 分发 + 无公证下自更新价值打折（每次更新仍过 Gatekeeper）；lumen/lightcraft 形态均为签名安装器场景。开源 GitHub Releases + 手动下载已是 2026-09-27 终裁的既定分发形态 |
| **OQ-M9-7** | **ColorWheels 旧档迁移策略**？ | **推荐：跟 Alcedo 同款**——读入时参数转换 + 单公式无分支 + 版本字段保旧渲染语义（我方 process version 机制 M6-2 五件套现成：改观感 = 新 process 号 + 旧号冻结；比 Alcedo 的「读入转换」更保守更稳——旧档零漂移）。**附带**：ColorWheels 修订是否升 process v3（film 已用 v2） |
| **OQ-M9-8** | **grain 接谱形态**（M8 挂账项部分解冻）？ | **推荐：M9 仅做 per-film granularity 标定面**（站 2 内，grain IOP 强度 1 = 发表 RMS 值）；grain 算子本体接谱（密度域调制/显影耦合）继续挂账——那是 M8 D-M8-4 空间族全家（grain/halation/diffusion/glare）的独立站 |
| **OQ-M9-9** | **film edge / date back（胶片边缘打印/日期后背）入不入**？ | **推荐：不入**。SpektraLab 大件（每 stock 边缘排版 + DX 条 + 片孔 + overscan，~15N+）且强绑定胶片画布形态（OQ-5 同判）；yiyin 印框/水印面板已有类似「边框装饰」面，产品重叠度低 |

---

## 4. 排除项与理由（明确不入 M9）

| 排除项 | 来源仓 | 理由 |
|---|---|---|
| **dehaze / clarity** | RawLab development（`33d4a9bd`） | **我方已有**：DehazeModule（dark-channel-prior，`Registry.swift:448` Plan 08-5-T1）+ Clarity（Equalizer EIGF base+detail mix，`Registry.swift:273` Plan 04-05-T2，`NodeOwnershipCatalog.swift:236` clarity→Equalizer）；RawLab 侧走闭源 sony2fuji atmosphere API 无可读算法面。任务书预设缺口不成立 |
| **Restormer / DualDn AI 降噪** | RawLab development（`b9e5de06` + `docs/architecture/dualdn-inline-denoise.md`） | **许可壁垒**：DualDn = CC BY-NC 4.0、Restormer = Academic Public License（commit `77dce309` 明示），均禁商用——开源再分发后商用用户使用即违约风险；**架构壁垒**：需解包 Bayer 四相位 + 黑白位 + CFA，CIRAWFilter 不暴露原始 Bayer（我方 CON 约束：不写 RAW 解码器）；我方 RAW 9 Neural Engine demosaic+denoise（Apple 官方）+ DenoiseProfile（dt 移植）已覆盖 |
| **selective adjustments** | RawLab development（`405ceff3` 等 6 commits） | 我方 layers + masks + AI mask 体系（Phase 6 + M2/M4/M6-4/lumen 批）**能力超集**；RawLab 侧 = 全局参数蒙版化的追赶实现 |
| **三区色彩分级** | RawLab colorGrading | 我方 ColorBalanceRGB（dt v50 移植）+ colorWheels + Hls/HSL 已覆盖同类 |
| **多照片对比视图** | RawLab compare | RawLab 实为单图 before/after split（`EditorView.swift:198` 中性显影对比）；我方 09-04 T7 compare point（原图/第 k 步）+ CullingView 双窗 compare 已有 |
| **SAM 2.1 / S3OD / people_sky_head 模型引入 + AI sidecar 进程 + 模型下载面板 + R8 asset 存储** | Alcedo SM 系列 | OQ-M9-1 推荐否的核心：Vision 原生等价能力已建成；427MB 模型 + sidecar 进程 + 下载治理全免；bake-to-raster 范式已定（AI-06） |
| **Windows/Linux 移植 churn** | SpektraLab（Tauri/Vulkan/LibRaw，~300 commits）、RawLab（四平台 CI/DCP/批处理）、lightcraft（docking/egui 0.37/title bar/craft-libs repin，~900 commits） | 平台移植与 UI 框架演进，与我方 macOS 27 独占无关；lightcraft 的 HEIF/RAW 安全加固（`d00df631` 等）注记入 UPSTREAM-QUEUE 观察项（我方 ImageIO/CIRAW 官方解码面攻击面不同） |
| **语义搜索 / search palette** | Alcedo（`54d4c95` 等） | 我方 M7-2 MCP `search_photos` + `SemanticEngine/EmbeddingScanner/SemanticStore` 已有 |
| **LibRaw 并行 LJPEG / camera matrices 更新 / Lensfun 43f9e001** | Alcedo（`ada6f00`/`8b17e2a`/`c0d8dd4`） | CIRAW 路线解码与镜头库均走 Apple/Lensfun 自管（LENS-01 数据钉版自控），上游解码器补丁无关 |
| **语义相关 folder scope / 冷启动 UI 线程 / GPU 导出资源释放** | Alcedo（`023a1d1`/`8d851f1`/`dab2473`） | 各为 Alcedo 自研 sidecar/RHI 结构的缺陷修复；我方无同构面。GPU 导出资源释放一条注记观察（我方 MetalContext clearCICaches 面） |
| **spklib-host 2.0 / DeepSeek Harness / MiMo** | SpektraLab / lumen 2.1.1 | 外围 AI harness/库分发件，与图像管线无关 |
| **JPEG XL DNG / DCP import / 跨相机 preset** | RawLab 0.7-0.8 | DNG SDK/DCP 路线 = RawLab 自养解码器方向，与 CIRAW 冲突；跨相机 preset 无用户需求信号 |

---

## 5. 五 NOTES 增量节指针

本批同步追加（同 commit 批次由 orchestrator 收割）：

- `.work/gsd/research/ALCEDO-PARITY-2026-10.md` — §+138 增量节（AI Mask 工具全量
  判定 + color wheels/filmstrip/LUT encodings 逐 commit 判定）
- `.work/gsd/research/SPEKTRALAB-NOTES.md` — 增量节（黑白族/滤色镜/幅面/移植 churn 分层）
- `research/RAWLAB-NOTES.md` — 增量节（main churn + development 0.9 真货：atmospace/
  Restormer/selective 判定）
- `.work/gsd/research/LUMEN-RAW-NOTES.md` — 增量节（2.1.0/2.1.1 五采纳先例续）
- `.work/gsd/research/LIGHTCRAFT-NOTES.md` — 增量节（Guided Upright 主料 + churn 分层）

---

## 6. 附:证据锚点速查

| 事实 | 锚 |
|---|---|
| Alcedo 模型集与性能 | master plan §8.2.1-8.2.4（origin/main） |
| Alcedo 编辑会话/asset 语义 | master plan D16-D23 + SM5 plan |
| Alcedo SM9 工具面板 | `ai_segmentation_mask/phase_sm9_tool_and_sm7_notice_plan.md` §1 |
| Alcedo LGG 数学 | `edit/color_wheel_tonal_lgg_plan.md` §3 |
| Alcedo filmstrip | commit `7ccb0ec` |
| 我方 Layer B 交互分割 | `LightamerCore/Sources/AI/AIMaskService.swift:18-24,366-410` |
| 我方 AI 五源 | `App/Sources/Lightamer/State/AIMaskEditing.swift`（AIMaskSource 枚举） |
| 我方 feather 双腿 | `LightamerCore/Sources/AI/AIMaskFeather.swift`（KD-3） |
| 我方 dehaze/clarity 已有 | `LightamerIOP/Sources/Registry.swift:448,273` + `NodeOwnershipCatalog.swift:236` |
| 我方 ColorWheels 旧公式 | `LightamerIOP/Sources/ColorWheels/ColorWheels.metal`（头注 primary_grade behavior 11） |
| 我方 Crop 无旋转 | `LightamerIOP/Sources/Crop/CropModule.swift:63-70` |
| 我方 pano homography | `LightamerCore/Sources/Stack/PanoCamera.swift:95` |
| lightcraft upright | `crates/pipeline/src/upright.rs`（611 行，MIT OR Apache-2.0） |
| SpektraLab BW 资产 | `engine/resources_product/{profiles,paper_grades.json,NOTICE.md}` |
| SpektraLab 滤色镜 | `engine/src/core/camera_filters.hpp` + commit `6d46e08` |
| SpektraLab granularity | commit `d610ac9`（ownGrain + 实测 17/8/7/16） |
| RawLab 双壁垒 | development `77dce309`（许可）+ `docs/architecture/dualdn-inline-denoise.md`（Bayer 依赖） |
| lumen removal/masks | commits `a862e0c`（2.1.0）/ `dd53fcd`（2.1.1） |
| M8 收口 | `.work/gsd/phases/m8-fsim-spectral/M8-3-SUMMARY.md`（4286/46/0） |
