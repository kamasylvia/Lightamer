# LENS-01 CONTEXT — Lensfun 镜头校正收口落地（OQ 裁决落定批，2026-10-20）

> **裁决正本**：OQ-LENS-1..8 **全部按 `RESEARCH.md` §Open Questions 推荐落定**
> （charter = `8bd94370` UQ-R4 拉正；research 正本 `b2b31909`；先例 M6-3/
> M6-4、M7-2..M7-6、f0prime 批同款「OQ 全按推荐」auto-advance 制度。
> **晨审可推翻**——推翻 = 用户晨审修订本文件对应 D 条，下游 plan 受影响
> 任务面重开，已执行部分按「晨审推翻先例」惯例处理）。读解正本 = 同目录
> `RESEARCH.md`（§Summary / §Baseline / §Mutex / §Auto-Detection /
> §Geometry Seam / §Persistence / §UI-UX / §Test Strategy / §Plan Split /
> §OQ）；planner 2026-10-20 HEAD `b2b31909` 抽核 ~20 点亲核吻合——
> **转写勘误两条**随 §转写勘误节登记（①sidecar schema v10→v11；②测试
> 基线权威数 3991/37/0 登记），执行以勘误为准。
>
> **特别登记一（hazards 三条，消解绑定到 plan，§Hazards 正表）**：
> ①per-render 全库匹配（现役 `process` 每次 run 全库线性打分）→ LENS-01
> 进程内 memo 消预览开销 + LENS-04 系数快照根治；②DB 更新静默改旧档渲
> 染 → LENS-04 匹配期系数快照（渲染与 DB 版本解耦）；③CC-BY-SA-3.0 数
> 据归属独立义务（NOTICE 现无 lensfun 条目，亲核）→ LENS-03 钉版快照 +
> 许可全套 + NOTICE 三条目，**不可延后件**。
>
> **特别登记二（04-04 遗产为基座，本批是收口不是重写）**：路线 A 主体已
> 在产线（`LightamerIOP/Sources/Lens/` 四件 + 下载服务 + 面板 + 注册路由
> + parity 测试，RESEARCH §Baseline 全表在案，planner 亲核吻合）；四
> plan 一律**增量接线**，既有已验收行为（手动滑杆/manual 路径/mask 蒙版
> 缝 pointMapSegment/anti-double-correction 默认 off/D1 devignette 除法
> 语义）零回归是底线门。
>
> **编排总纲**：四 plan——**LENS-01**（互斥三态 + 匹配硬化 + 匹配移出
> process 期）→ **LENS-02**（enable/per-correction/scale/auto-crop/
> profile browser）→ **LENS-03**（projection + 数据分发 + NOTICE）串行；
> **LENS-04**（系数快照 + process version 裁决 + 测试收口 + perf probe）
> 依赖 LENS-02、与 LENS-03 **并行**（触碰面不相交：03 = kernel 投影数学
> + 数据分发面；04 = params 持久化 + 验收面；唯一共享收口点 = LENS-04
> T2 process version 裁决消费 02/03 全部语义变更，故 04 的裁决任务在
> 03 闭环后执行——排程上 04 先行任务〔T1 快照/T3 缓存隔离〕可与 03 并
> 行，T2 串行垫底）。**C 档门控：每 plan 执行+验收闭环后停汇报**，等用
> 户确认再放行下一 plan（charter 门 + AGENTS 暂停机制）；并行波 = 两
> plan 各自闭环后一并汇报停。全套 `--all` = orchestrator 批准制 + 运行
> 监视 + 8G 门 + MEMFAIL 机检兜底（AGENTS 资源监控节）；执行批一切重活
> 起跑前必过 `Scripts/machine-guard.sh`（机器级单重活，与一切在飞重活
> 互斥排程——2026-10-20 L0xx-e 红线）。

## Phase Goal（FEAT-DEV-07 锚定）

把 Phase 04-04 的 Lensfun 数据只读路线收口到 Alcedo 验收锚完整形态：
**enable + scale + projection + profile database + auto-detection** 五件
全落地 + 双重校正互斥三态探测（detected/unknown/notApplicable）+ 系数快
照持久化（渲染与 DB 版本彻底解耦）+ 数据钉版分发与 CC-BY-SA-3.0 归属。
验收形态：构建绿 + 定向 bundle 全绿 + 全套 `--all` 对账（基线
**3991/37/0**，ΔN **+60..90** → 终值带 **4051..4081**，skip 增量逐族申
报）+ 互斥状态机表驱动 + projection/scale golden（GPL 同源对表）+
100MP perf probe（fence 纪律）+ 面板五段 GUI 走查。四 plan 分账：
LENS-01 +14..20 / LENS-02 +18..28 / LENS-03 +16..26 / LENS-04 +12..16
（合计 +60..90；越带申报理由）。

## 决议（D-LENS-1..8，生效值，硬约束，执行中不重开）

### D-LENS-1 auto 默认行为 = 全局 opt-in 关 +「自动应用匹配」开关；生效域 = raster 链（OQ-LENS-1）

- **裁决 = RESEARCH §OQ 推荐**：新片**不**自动应用（`unknown` 态占多数
  ——厂商 RAW 无可靠检测面，自动开 = 高概率双补）；开关 = UserDefaults
  `lensfun.autoApply`（默认 false，本批唯一新应用级键）；**生效域钉死 =
  `embeddedGeometry == .notApplicable`（raster/TIFF 链）**——detected/
  unknown 恒需显式 Apply（互斥硬守卫不受开关影响，RESEARCH §Mutex 三态
  行为表）；开关读法走注入式 defaults（KD-4 惯例：`LensModule` init 直
  读 `.standard` + 测试注入缝；面板 body 零直读）。
- 理由一句：错误的双补比没有校正更伤信任，且不可检测面架构性恒存。
- 证据：RESEARCH §Mutex + §OQ-1；RawLab per-photo 默认关同判
  （`RawLabMac/Sources/Adjustments/AdjustmentTypes.swift`）；04-04 默认
  `.off`（`LensModule.reloadDefaults` 亲核）。
- 晨审推翻点：翻案 = auto-apply 生效域扩到 `unknown` 态（双补风险自担，
  不建议）。

### D-LENS-2 覆盖语义 = v1 只做 Lensfun 侧「强制启用」；解码侧 per-image override 挂 v1.x（OQ-LENS-2）

- **裁决 = RESEARCH §OQ 推荐**：detected 态逃生门 = 面板「强制启用」
  （确认文案 + source 直接置 lensfun——Lensfun 侧覆盖，v1 面）；
  **解码侧** override（`RAWTechnicalOverrides.vendorLensCorrection=false`
  → CIRAW 跳过嵌入校正 → 重解码）= **v1.x parked，本批四 plan 不执行**
  ，设计契约钉死于 §X2 供后续批接手。
- 理由一句：重解码缓存失效链改动面大，逃生门价值配不上本批预算；两套
  覆盖并存 = 用户叠加困惑。
- 证据：RESEARCH §Mutex（CIRAW 无「是否已应用」查询 API——架构性事实）
  + §OQ-2；`RAWDecoder.swift:216-221`（键恒默认 true 注释亲核）。
- 晨审推翻点：翻案 = 解码侧 override 提前进本批（建议独立小批，不并入
  L1/L2——重解码缓存链回放开销）。

### D-LENS-3 系数快照 = 快照进 params，渲染与 DB 版本彻底解耦（OQ-LENS-3）

- **裁决 = RESEARCH §OQ 推荐**：Apply/auto-apply/browser 选型时把归一化
  系数（15 float：dc1..dc4/vr,cr,br/vb,cb,bb/vk1..k3/centerX/centerY）
  + profile id + score + dbTag 快照进 `Params` additive optional（形态
  钉死 = §X3）；渲染期 snapshot 在先（零 DB 依赖）；snapshot nil
  （legacy 档）回落现役 live resolve（字节级旧行为）；DB 更新 = 用户显
  式「Re-match」才生效。L1/L4 分工：LENS-01 = 进程内 memo（消 per-render
  开销）；LENS-04 = 持久快照（消跨会话确定性缺口）——两段独立可回退。
- 理由一句：「非破坏 + 渲染确定性」纪律管不住数据源漂移，快照是唯一根
  治，顺带消掉 per-render 全库匹配开销（Hazard ①②一并闭合）。
- 证据：RESEARCH §Persistence + §OQ-3；`RenderProcess.swift:25-44` bump
  纪律；M3-1-01 LUT 编码对「hash 零漂移专测钉死」先例。
- 晨审推翻点：翻案 = 实时解析 + DB 版本折进 paramsHash + process 评估
  （确定性弱化 + DB 每次更新全档 hash 抖动，不建议）。

### D-LENS-4 匹配硬化 = 阈值分档 ≥60 + 歧义拒绝 + 全参匹配接线（OQ-LENS-4）

- **裁决 = RESEARCH §OQ 推荐**：auto/committed 通道匹配阈值收紧
  `>= 60`（contains 档；40 word-overlap 档仅作 profile browser 排序提
  示，不再自动入选）；同分多候选 = RawLab 式 `Ambiguous` 拒绝进手动；
  **crop gate 修复** = 匹配走 `LensfunMatch.match` 全参路径（maker/model
  /imageCrop 实值——现役 `resolveCommitted` 传 nil/nil/1.0，crop gate
  0.96 实际未生效，亲核吻合）；imageCrop 来源优先序 = EXIF
  FocalLengthIn35mm 推导（`FocalLengthIn35mm/focal`，RawLab 式）> DB
  camera 唯一命中 cropfactor > 1.0（现状兜底）；camera 匹配唯一命中才
  用（多命中弃，RawLab `FindCameras` 语义）。
- 理由一句：错误校正比无校正更伤信任；全画幅/APS-C 误配是 crop gate
  失效的直接后果。
- 证据：RESEARCH §Auto-Detection + §OQ-4；`LensfunMatch.swift:405-428`
  （resolveCommitted 现状亲核）/`:126-155`（全参 match 本体已实现，纯接
  线）；RawLab `lens_correction.cpp:19-25,:74-77` + `raw_processor.cpp
  :45-46`。
- 晨审推翻点：翻案 = 阈值回 40 / 歧义取最高分即用（误匹配面放大，不建
  议）。

### D-LENS-5 auto-crop = scale 补偿 + 接力 crop 面板；不采纳 crop_bounds/CIRCLE（OQ-LENS-5）

- **裁决 = RESEARCH §OQ 推荐**：RawLab 二分语义移植（输出帧四边 inside
  测试 + zoom ×1.25 粗探至 8 + 18 轮二分最小 cropScale + ×1.00001 余
  量；超 8 = UnsupportedInput）算最小 scale；「接力 crop」按钮把建议裁
  切框一键填入 Crop 面板（裁切真相单源在 CropModule 24.5）；Alcedo
  `crop_bounds[4]` + CIRCLE 模式不采纳。
- 理由一句：两套裁切真相必然漂移，几何裁切已有家；scale 补偿是
  RawLab/Alcedo 同语义的最小形态。
- 证据：RESEARCH §Geometry Pipeline Seam + §OQ-5；RawLab
  `lens_correction.cpp:196-247`。
- 晨审推翻点：翻案 = 内嵌 crop_bounds/CIRCLE（双真相 + Alcedo framing
  分工背离，不建议）。

### D-LENS-6 数据分发 = 随包钉版快照 + NOTICE 全套 + 手动检查更新（OQ-LENS-6）

- **裁决 = RESEARCH §OQ 推荐**：官方 `version_1.tar.bz2` 钉版快照
  （SHA-256 登记）随包 `Resources/Lensfun/`（folderReference——Tuist
  4.208 裸目录字符串静默忽略教训）；首装 seeder 拷入支持目录（哨兵 =
  存在且字节数相等跳过、漂移重拷，LutLibraryStore seeder 先例）；解析优
  先序 = customPath > 随包种子 > 已下载副本 > absent（customPath 既有
  语义不变，`LensfunDownloadService.customPathKey` 零改）；设置面手动
  「检查更新」（下载 + SHA 校验失败拒绝安装 + 失败降级保留现下载服务路
  径；无自动更新）；**NOTICE 补三条目 = lensfun 数据（CC-BY-SA-3.0，来
  源 + SHA + unmodified 声明）+ Alcedo（projection 移植）+ RawLab
  （auto-crop/状态机移植）——L3 不可延后件**。
- 理由一句：离线即用 + 复现可审计；「依赖最小化」管代码库不管数据资产
  （~5MB）。
- 证据：RESEARCH §Upstream Facts（许可双轨 + 体积 4.2-5.1MB 实测 + RawLab
  `build.sh:63-65` 打包形 + 钉版 SHA 先例）；NOTICE 现无 lensfun 条目
  （亲核）；fixtures README 已有 CC-BY-SA 声明（`input/golden/fixtures/
  lensfun/README.md` 亲核，L3 复核一致性即可）。
- 晨审推翻点：翻案 = 维持首跑下载（不可复现 + 离线缺数据，不建议）。

### D-LENS-7 vignetting 纳入 per-correction 开关族（OQ-LENS-7）

- **裁决 = RESEARCH §OQ 推荐**：渐晕随 per-correction 三 toggle
  （distortion/TCA/vignette）落地（kernel IDW 插值已在位，只是开关 + 默
  认档 on）；aperture 缺失 = nearest-aperture 行（现 IDW 已处理，零改）。
- 理由一句：三件套是 Alcedo `apply_*` 对齐面，缺一即验收锚不闭合。
- 证据：RESEARCH §OQ-7 + Alcedo `LensCorrectionSettings` 四分开关
  （`apply_crop_` 不采纳 = D-LENS-5）。
- 晨审推翻点：翻案 = v1 砍渐晕（对齐缺口，不建议）。

### D-LENS-8 projection = 四型起步 + 枚举槽位预留；Alcedo 移植为基（OQ-LENS-8）

- **裁决 = RESEARCH §OQ 推荐**：source/target projection 枚举 8 槽全备
  （additive，编译期穷举 switch 自然指向未激活槽），**v1 激活四型 =
  fisheye/equisolid/stereographic/orthographic**（target 侧；rectilinear
  = 恒等基态/默认）；panoramic/equirectangular/thoby 槽位预留不激活；
  数学移植 = Alcedo `lens_calib.metal` + `LensCalibGpuParams` 结构（GPL
  合规形态 = §X8）；`LensfunMatch.resolve()` 对非 rectilinear 条目的硬
  拒随本特性解除（entry `<type>` → source projection；target 未设时维
  持保守拒绝 + blit identity 现状）。
- 理由一句：主流用例四型覆盖；全景族数据面与用例双重稀疏，枚举槽位零成
  本预留。
- 证据：RESEARCH §Route Decision Matrix（吸收件 1）+ §OQ-8 + Alcedo
  `lens_calib_runtime.hpp:35-45,:53-119` + `resolve():199-201` 硬拒现
  状亲核。
- 晨审推翻点：翻案 = 8 型全量（数据面稀疏件无对账锚，不建议）。

## 设计承接钉死（X1..X8，plan 层硬约束）

### X1 互斥三态探测挂载位

- 新 Core 纯函数 `DNGOpcodeProbe`（`LightamerCore/Sources/Decode/`）：
  TIFF 结构字节探针（IFD0 + SubIFD walk，tags **51008/51009/51010**
  存在性）——纯读、零 ImageIO 私有面依赖。
- `DecodedImage` additive optional `embeddedGeometry:
  EmbeddedGeometryState?`（新枚举 `detected/unknown/notApplicable`，Core
  定义、IOP 可读——IOP → Core 依赖方向既有）。
- 三腿赋值：RAW DNG = 探针（任一 tag 存在 = detected）；RAW 非 DNG =
  unknown；raster/TIFF 腿（M4-1）= notApplicable。
- 消费：`LensModule.reloadDefaults` 把判定折进 `Params` additive
  `embeddedGeometry`（D6 自描述哲学——params 携带 resolve 上下文；面板
  §1 readout 经 params 读，无第二缝）；nil = pre-batch 档 → 面板显示
  中性「未判定」不冒充结论。
- 保守语义：tag 存在 = 视为已应用（CIRAW 键默认 on；存在性判定，不做
  opcode 应用语义推断）。

### X2 per-image override 重解码语义（v1.x parked 设计契约，本批不执行）

- 形态：`RAWTechnicalOverrides.vendorLensCorrection: Bool?` additive
  （nil = 默认 true）；false → CIRAW filter 写
  `kCIInputEnableVendorLensCorrectionKey = false` → 跳过嵌入校正。
- 缓存语义：override 属 decode-params 面 → 必须折进 decodeParamsHash
  （现 hash 覆盖面核验 = LENS-01 T1 顺带核验项；若未覆盖 = 补折叠 + 回
  归，v1.x 批自带）。
- 触发 = 重解码（缓存键变化自然失效）；与 D-LENS-2 的 v1/x 边界 = 本批
  四 plan 零执行，仅契约在案。

### X3 系数快照形态（LENS-04 执行）

- `LensCoefficientSnapshot`（Codable/Hashable/Sendable，IOP Lens 域）：
  15 系数 Float（与 `LensKernelParams` 一一对应）+ profileMaker/
  profileModel/profileMount: String? + profileCrop: Float? + matchScore:
  Int? + dbTag: String?（DB 快照 SHA-256 前 16 hex，审计面非渲染面）。
- `LensModule.Params` additive：`public var snapshot:
  LensCoefficientSnapshot?`（默认 nil；encodeIfPresent——默认 params
  JSON 逐字节零漂移，M3-1-01 先例 + 专测钉死；历史档 hash 零漂移）。
- 消费序：`source == .lensfun && snapshot != nil` → 直用快照（零 DB 依
  赖）；`snapshot == nil` → 现役 live resolve（legacy 档字节级行为不
  变）。
- 写入点恰三处：面板 Apply / auto-apply 命中 / browser 选型；「Re-match」
  动作 = 失效快照 → 按当前 DB 重匹配 → 新快照一次 commit（终形 LENS-04
  DECISIONS 申报）。
- dbTag 语义：审计字段，不折 paramsHash（DB 更新不抖 hash——与 D-LENS-3
  快照语义自洽）。

### X4 crop gate 修复接线（LENS-01 T3）

- EXIF 补字段：`CaptureMetadata` += `focalLengthIn35mm: Double?`
  （ImageIO `kCGImagePropertyExifFocalLenIn35mmFilm`）+ `lensMake:
  String?`（ExifAux dict）——tolerant additive，旧档 decode 零漂移负测
  随批。
- imageCrop 终式（优先序见 D-LENS-4）；35mm 推导缺 focal 时弃用（除零
  守卫）。
- `Params` additive 记录 resolve 输入（cameraMaker/cameraModel/
  imageCrop: optional——与 snapshot 同批字节纪律）。

### X5 scale 折算（LENS-02 T3）

- `LensWarpUniforms` += `scale: Float`（默认 1.0）；kernel 采样坐标
  ×1/scale；`modifyROIIn` 边框点同步缩放；kernel 仍单 pass（无结构改，
  80 字节 struct 对齐面随批复核）。
- auto scale = `LensAutoCrop.minimumScale`（IOP 纯函数，RawLab 二分移植
  + GPL 合规头 §X8）；user scale 滑杆 + resolved readout；auto/user 互
  斥（Alcedo `use_user_scale_` 语义）。
- scale ≠ 1 = 采样域放大（有效视场收窄）；接力 crop 按钮换算建议裁切框
  填 Crop 面板（不落第二裁切真相）。

### X6 profile browser UX 面（LENS-02 T4）

- LensPanelView 目标五段（RESEARCH §UI/UX 终表）：§1 状态（互斥三态 +
  匹配状态机 readout：Matched(name/score)/Ambiguous/NoLens/NoDatabase/
  MissingFocal/NotApplicable）/ §2 enable + per-correction 三 toggle /
  §3 scale（auto 开关 + user 滑杆 + resolved readout + 接力 crop 按钮）
  / §4 profile browser（搜索 + 候选列表 + matched 置顶；40 分档条目可
  见但标注「低置信」不自动入选）/ §5 数据管理（DB 版本/条目数 readout
  + 更新按钮；设置项迁 Settings 归 LENS-03）。
- Apply/Clear 两按钮退役进 browser（Clear 语义 = 回 manual，保留为
  browser 空/禁用臂——终形 LENS-02 DECISIONS 申报）。
- 交互纪律：D-H1 拖拽三件 + 单 discrete commit 键族 `history_lens`/
  `panel_lens_*` 既有 + 新键尾块纯插入。

### X7 数据分发终形（LENS-03 T3）

- `Resources/Lensfun/`（folderReference，App target）= 钉版 `version_1`
  xml 集 + `README.md`（来源 URL + SHA-256 + 检取日期 + unmodified 快照
  声明）。
- Seeder：首装拷入支持目录（哨兵 = 存在且字节数相等跳过，漂移重拷）；
  `LensfunDataLocation` 优先序 = customPath > 随包种子 > 已下载 > absent。
- 更新通道 = 设置面手动（官方 tar.bz2 + SHA 校验失败拒绝安装 + 失败
  toast；L057 缝）；下载服务 legacy 路径保留为降级臂。
- fixtures 侧（`input/golden/fixtures/lensfun/`）README 已有 CC-BY-SA 声
  明（亲核在案）——LENS-03 T4 复核一致性即可，不重写。

### X8 Alcedo/RawLab GPL 移植合规形态

- 移植文件头：upstream 版权声明（`Portions Copyright … Alcedo Studio
  contributors` / RawLab contributors）+ `Modified by Lightamer …` 修改
  标注 + 指向 NOTICE 条目。
- NOTICE 第三方 provenance 节新增三目：Alcedo Studio（projection 数学/
  GPU 参数结构，GPL-3.0）、RawLab（auto-crop 二分/状态机语义，GPL-3.0）、
  lensfun 数据（CC-BY-SA-3.0，来源 + SHA-256 + unmodified 快照声明）。
- golden 合法化：GPL 同源后 projection/scale 参考可与 Alcedo
  `lens_calib.metal` / RawLab 二分直接对表——对表数值入 plan evidence
  ，不入 CI 门（跨仓路径不可 CI 依赖）；dt 侧维持合成参考（无 lens 腿
  ，`LensParityTests.swift:14-27` 既定结论）。

## Hazards（三条，登记 + 消解绑定）

| hazard | 机理 | 消解绑定 |
|---|---|---|
| **H-L1 per-render 全库匹配** | `process` 每次 run 全库线性打分（`LensModule.resolveUniforms` → `LensfunStore.resolveCommitted` → `LensFunMatch.match` 扫全 lenses × 打分；拖滑杆每帧数千条目字符串打分，亲核在案） | LENS-01 T4 进程内 memo 消预览开销；LENS-04 T1 持久快照根治（D-LENS-3） |
| **H-L2 DB 更新静默改旧档** | 系数 process 期按当前 DB 实时解析——DB 更新即重写全部旧档渲染，违反非破坏 + 渲染确定性（M6-2 bump 纪律管代码语义、管不住数据源漂移） | LENS-04 T1 匹配期系数快照（渲染与 DB 版本解耦；DB 更新 = 显式 Re-match 才生效） |
| **H-L3 CC-BY-SA-3.0 归属独立义务** | 数据 share-alike 归属独立于代码许可；随包分发缺归属 = 许可违规；NOTICE 现无 lensfun 条目（亲核） | LENS-03 T3/T4：钉版快照 + 全套许可文本 + NOTICE 三条目（§X7/§X8）；不可延后件 |

## 转写勘误（RESEARCH → 本批 planner 亲核批，非矛盾、执行以勘误为准）

1. **sidecar schema 版本勘误（v10 → v11）**：RESEARCH §Persistence 首行
   「sidecar v10 现行 schema」= stale——现行 = **v11**（M7-4-01
   note/author 面，`LightamerSidecar.swift:255` `schemaVersionCurrent =
   11` 亲核）。对本批**零影响**：lens params 骑 history item paramsData
   ，快照/additive 字段不触 sidecar schema（`LightamerSidecar` 封存零
   diff 维持）——勘误仅作引用修正，RESEARCH 正文不返工。
2. **测试基线权威数登记（RESEARCH 仅给 ΔN +60..90，未给绝对数）**：权威
   基线 = **`3991/37/0`**（f0prime 批终态——F0P-02 三轮同值
   `TOTAL|3991/37/0|`，P3 退役零 ΔN；`.work/gsd/phases/f0prime-prod/
   F0P-02-SUMMARY.md:12,:99` 亲核）。全套预期 = **3991 + ΔN（+60..90 →
   终值带 4051..4081）**；skip 37 = 基线 + 本批 perf probe 族增量逐族申
   报禁静默吸收。四 plan 以本数为正本。
3. 其余 ~20 抽核点全部吻合（±1 行微差不影响语义）：`LensModule.swift`
   :57-74（divergence 登记）/:151-156（slot 13.0 + flags）/:170-178
   （reloadDefaults 默认 off）/ :261-295（modifyROIIn AABB+2px+clamp）
   / :318-329（pointMapSegment）/ :335-346（resolveUniforms →
   resolveCommitted 每帧路径）；`LensfunMatch.swift` :51-82
   （LensKernelParams 15 系数 + uniforms）/ :107-118（modelScore
   100/60/40+5）/ :126-155（match 全参 + crop gate 0.96）/ :199-201
   （非 rectilinear 硬拒）/ :387-395（install）/ :405-428
   （resolveCommitted maker/model nil + imageCrop 1.0 + distance nil）
   / :431-446（fallbackEntry ≥40）；`LensPanelView.swift` :42-50（§1 静
   态文案）/ :226-237（stub matchName=key）/ :240-256（Apply/Clear）；
   `RAWDecoder.swift` :39（RAWTechnicalOverrides）/:216-221（vendor lens
   correction 键恒默认 true）；`CaptureMetadata.swift` :10-37（无
   35mm/lensMake）；`RenderProcess.swift` :25-44（bump 纪律）/:89
   （current = v1）；`Registry.swift` :39-50（disabled 集无 lens）/
   :238-241（注册 13.0）；`LensfunDownloadService.swift` :35-37
   （master.zip 不钉版）/ :39（customPathKey）；`LightamerShell.swift`
   :920-927（resolveAndInstall 启动装）；`AdjustmentTransfer.swift`
   :34-38（.grade 谓词——lens 天然不在传输面，正确）；`EditorTabRoute
   .swift` :266-275（geometry 行 lens 可达）；`LensParityTests.swift`
   :10-27（合成参考 + 无 dt lens 腿）；`Project.swift` :141-142（IOP
   sources glob——纳新产线文件免改）/:280-288/:379（测试 bundle 显式数
   组——纳新测试文件必改 + tuist generate 末位）；`Resources/`（LUTs/
   FilmProfiles/AIModels folderReference 先例 :179-192）；`.gitignore
   :28-35` + fixtures README（CC-BY-SA 声明在案）；NOTICE（无 lensfun
   条目）。

## 四 plan 红线 front-matter（共用正本，四 plan 逐条引用）

1. **FIX2③ = `App/Sources/Lightamer/Mcp/McpServerController.swift` 零
   diff**（MCP 面与本批零交集，四 plan 全程不触）。
2. **封存面零 diff（M3-3 清单适配注记）**：`DrtPanelModel/DrtPanelView/
   DrtRecord/TerminalTailPolicy/DrtTailAssembly/PixelPipe/Lut3dKernels
   .metal/DrtEotf/ExportQueueContract/六格式导出矩阵（ExportFormatSpec·
   ImageIOEncoders·WebPEncoder）/NodeGraphCommand/LightamerSidecar
   （schema 零 bump）/HistoryStack/HistoryHash/PipelineDocument（Core）/
   V50Order/GradeCatalog/Registry/ModuleInstance` 全程零 diff——本批无
   新 iop（lens 已注册 13.0，V50 零新增）；**`LensKernels.metal` 是
   lens 域自有 kernel，不在封存清单，L2/L3 扩参/投影数学是本批正业**；
   `Project.swift` 仅允许 resources 段与测试数组段 diff。
3. **xcstrings 尾块纯插入**：新键一律 append 至 `Resources/
   Localizable.xcstrings` 的 `"strings"` 尾部（历史键字节与顺序零触碰）
   ；每批收尾 `Scripts/zh-audit.py --check` + `--self-test` 双 PASS；
   动态键一律显式 switch 返回静态键（V14）。
4. **LocalizationValue 禁形零命中**：`String.LocalizationValue("prefix_
   \(x)")` 插值动态查表键禁（M2-9 F-2）。
5. **L041 tuist generate 恒末位**：新测试文件 → `Project.swift` 对应
   bundle 显式数组（无 glob）同批更新；`tuist generate` = 该批最后一个
   动作；IOP 产线源 glob 纳新文件免改。
6. **机器级单重活（L0xx-e 红线）**：执行批一切重活（xcodebuild/
   test-direct/GUI 走查）起跑前必过 `Scripts/machine-guard.sh`（不满足
   = `--wait` 轮询或停）；与 F0'-prod 验收链及一切在飞重活互斥排程，
   两并发 = 禁止。
7. **GPL 移植合规**：Alcedo/RawLab 移植件 = 版权头 + 修改标注 + NOTICE
   登记（§X8）；零归属入库 = 流程违规。
8. **perf probe 纪律**：`LIGHTAMER_PERF_PROBE=1` + XCTSkipUnless（默认
   套件 skip）；探针读钟前 queue fence（L014——无 fence 计时 = 假数）；
   skip 增量逐族申报。
9. **--all 批准制 + 运行监视**：orchestrator 批准 + 8G 门
   （RSS_LIMIT_MB=8192）+ MEMFAIL 机检 + caffeinate -dis 包裹 + 测试宿
   主清理先核 parentage（`ps -o ppid`——测试宿主 parent = 脚本进程树，
   GUI 实例 parent = launchd，M2-7-3 先例）。
10. **C 档门控**：每 plan 执行+验收闭环后停汇报，等用户确认再放行下一
    plan；LENS-03/LENS-04 并行波 = 两 plan 各自闭环后一并汇报停。
11. **UserDefaults 新键登记面**：本批恰一键 `lensfun.autoApply`（Bool，
    默认 false，LENS-02）——读法走注入式 defaults（body 零直读）；键登
    记随 LENS-02 DECISIONS 入 AGENTS.md 键族节。
12. **默认中性零行为门**：默认参数（source=.off、enabled=nil=true、
    scale=1、target=rectilinear、三 toggle 全 on、snapshot=nil）下渲染
    逐字节不变——每 plan 带默认中性 golden 负测（非 RAW / lens-off 文
    档零行为）。
13. **L057 缝**：面板/设置一切文件面板（DB 导入/更新/自备路径）走
    `PanelPresentation.present` async 缝；`.runModal(` 在 `App/Sources`
    零命中。
14. **测试落域**：新测试文件按 BUNDLE-MAP 域模式归唯一 target（kernel
    golden → IOPParity；解析/匹配/纯函数/Decode 域 → IOP；面板/UI 模型
    → App）；跨 bundle 零重域；`tuist generate` 恒末位（红线 5）。
15. **commit 纪律**：每任务独立 commit（Conventional Commits 全英文、
    只 add 相关文件、不 push）；规划文档免 issue 关联（orchestrator 登
    记口径）；执行 commit 前缀 `feat(lens0N)/fix(lens0N)/test(lens0N)/
    docs(lens0N)`。

## 晨审推翻点索引（可推翻面速查）

- **D-LENS-1**：auto 生效域 = raster 链 ↔ 扩到 unknown 态（双补风险自担）。
- **D-LENS-2**：v1 只 Lensfun 侧覆盖 ↔ 解码侧 override 提前（建议独立
  小批）。
- **D-LENS-3**：快照 ↔ 实时解析 + DB 版本折 paramsHash。
- **D-LENS-4**：≥60 + 歧义拒绝 ↔ 阈值 40 / 最高分即用。
- **D-LENS-5**：scale 补偿 + 接力 crop ↔ 内嵌 crop_bounds/CIRCLE。
- **D-LENS-6**：随包钉版 ↔ 首跑下载（不可复现 + 离线缺数据）。
- **D-LENS-7**：vignetting 纳入 ↔ v1 砍渐晕（验收锚缺口）。
- **D-LENS-8**：四型起步 ↔ 8 型全量。
- **X1 消费缝**：params additive 携带 embeddedGeometry ↔ document 级
  元数据缝（第二缝，不建议——params 自描述哲学）。
