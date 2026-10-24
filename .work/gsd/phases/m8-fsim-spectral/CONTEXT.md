# M8 CONTEXT — FSIM 光谱升维（Spectral Film Core）charter + 四 plan 裁决正本（2026-10-24）

> **裁决正本**：OQ-M8-1..8 **全部按 `RESEARCH.md` §5 终推荐落定**（research 正本
> `9b256482`；先例 M6-3/M6-4、M7-2..M7-6、f0prime、lens-01 批同款「OQ 全按推荐」
> auto-advance 制度。**晨审可推翻**——推翻 = 用户晨审修订本文件对应 D 条，下游
> plan 受影响任务面重开，已执行部分按「晨审推翻先例」惯例处理）。读解正本 =
> 同目录 `RESEARCH.md`（§1 上游数学全量 / §2 数据包形态 / §3 我方缝位 / §4 性能
> 预算 / §5 OQ 终推荐 / §6 切分）；planner 2026-10-24 HEAD `9b256482` 抽核
> ~15 点亲核吻合——**亲核登记与精确化**随 §亲核登记节落账（执行以该节为准）。
>
> **M8-0 charter 形态说明（4-plan 形态的由来）**：RESEARCH §6.1 的 M8-0 =
> 「charter 批，非 plan」——其四件交付物（OQ 裁决 / phase 表 / SC 门 / 范围
> 红线）**由本文件全部承载**（§决议 = OQ 裁决；§编排总纲 = phase 表；§Phase
> Goal = SC 门；§红线 = 范围红线）。research 正本已含全量上游数学读解与资产
> 盘点（§1/§2/§3），charter 无新增 research 面 → **M8-0 并入 planner 批，
> 本批交付 = charter（本文件）+ 4 plan（M8-1a / M8-1b / M8-2 / M8-3）**。
>
> **特别登记一（film sub-run 自有面豁免，封存面适配注记）**：M7-6/M3-3 封存
> 清单邻接面（review m2——引称勘正：四名中仅 `PixelPipe` 在 M7-6 封存清单
> 在册）`PixelPipe` / `FilmTailPolicy`（含 FilmMethodBox）/ `FilmPrintBake`
> 的 **film leg 自有区段是本批正业、不在封存清单**
> （LENS-01「lens 域自有 kernel 不在封存清单」同款适配注记）；**`FilmSubRunKernels.metal`
> 不在豁免面——恒零 diff（M8-1b/M8-2 冻结红线钉死），光谱核正业 = 新建
> `SpectralFilmKernels.metal`**（review m2——与两执行 plan 矛盾消解）；但
> `runTerminalTails` 三 leg 编排骨架 / seed 折叠序（`FilmTailAssembly.seed`
> 四项 canonical 序）/ FilmMethodBox 对外面（iopOrder 74.0 / nil-payload blit
> identity / instances per-run 载体）/ `TerminalTailPolicy` 3×2 降出矩阵 /
> `DrtTailAssembly` / `DrtRecord` / `Lut3dKernels.metal` / `Registry` /
> `V50Order` / `NodeOwnershipCatalog` / `HistoryStack` / `HistoryHash` /
> `LightamerSidecar`（**schema 零 bump，v11 维持**）/ 六格式导出矩阵 /
> `ExportQueueContract` / `PipelineDocument` / `NodeGraphCommand` /
> `ModuleInstance` **全程零 diff**（红线 2 逐项机检）。
>
> **特别登记二（数值纪律首用）**：CPU/GPU bit-exact 三板斧（显式 fma 钉形 /
> host double 单次取倒 rounded-to-float / 共享 log2-exp2 多项式）是本项目
> **首次全链应用**（RESEARCH §1.6 上游真实分歧案例三件正本）——不是 stylistic，
> 是 H-M1 hazard 的消解本体，M8-1b 逐项落 + probe ⑤ 实证度量。
>
> **编排总纲**：四 plan **串行**——**M8-1a**（数学核-数据面：谱解码 + 常量
> 资产 + tc 自拟合器 + Float64 构建期引擎 + golden）→ **M8-1b**（数学核-GPU
> 面：七 stage kernel 族 + 表载体 + 三板斧 + probe 批）→ **M8-2**（管线集成：
> film leg 换臂 + solve/bake 光谱域 + process v2 bump + 冻结 golden 双臂）→
> **M8-3**（面板 + 收口：UI 零新增确认 + 迁移 UX + NOTICE 措辞 + 全套
> `--all` 对账）。串行理由：1b 消费 1a 的表数据面；2 消费 1a/1b 全部；机器级
> 单重活制下无并行收益。**执行排程 = 图库选片批验收链之后**（机器级单重活，
> 与在飞重活互斥）。**C 档门控：每 plan 执行+验收闭环后停汇报**，等用户确认
> 再放行下一 plan（AGENTS 暂停机制）。全套 `--all` = orchestrator 批准制 +
> 运行监视 + 8G 门 + MEMFAIL 机检兜底（归 M8-3 收口轮统一对账）；执行批一切
> 重活起跑前必过 `Scripts/machine-guard.sh`。
> **RESEARCH §6.1 切分对本批的一处显式调整**：RESEARCH 把「CC BY-SA 谱面消费
> NOTICE 修订 + OQ-M8-8 裁决落地」列在 M8-2——按 orchestrator 指令**移至
> M8-3**（M8-2 保持纯管线集成；NOTICE/OQ-8 与面板/收口同批申报更连贯），
> M8-2/§任务清单以本编排为准。

## Phase Goal（FSIM-01c 收窄后 ② 面锚定）

把现行 RGB 密度域染料近似 film 核升维为 dt spektrafilm 同级的**逐波长光谱
材料链**：scene-linear Rec2020 → CAT16 → xy → **tc 光谱上采样（自拟合
Jakob-Hanika）** → 感光积分 → DIR coupler 显影 → dichroic 印相 → 相纸 →
扫描 CMFs → gamut 压缩；经 **process v2 双臂**迁移（光谱核 = v2 current，
密度核冻结 legacy 臂，旧档零漂移）。验收形态：构建绿 + 定向 bundle 全绿 +
全套 `--all` 对账（基线 **4206/41/0**，ΔN **+60..82** → 终值带
**4266..4288**，skip 增量逐族申报）+ 光域单元 golden（独立复算 ≤1e-6）+
CPU/GPU bit-exact 断言 + 100MP perf probe（coupler 降采样臂 RSS 实测）+
密度核 legacy 零漂移 golden（process v1 逐位不变）+ 面板零新增走查。四 plan
分账：M8-1a +18..24 / M8-1b +12..18 / M8-2 +20..26 / M8-3 +10..14（合计
+60..82；越带申报理由）。

## 决议（D-M8-1..8，生效值，硬约束，执行中不重开）

### D-M8-1 核拓扑 = process 驱动单源；零 FilmRecord 新字段、零 schema bump（OQ-M8-1）

- **裁决 = RESEARCH §5 推荐**：光谱核开关**单源** = 文档级 `process` 键
  （`≥ 2` = 光谱核；`≤ 1`/absent = 密度核冻结 legacy 臂）；`RenderProcess`
  追加 `.v2`（`all=[.v1,.v2]`、`current=2`、`resolving` clamp 表自动扩）；
  **不设 `FilmRecord.engine` 字段**（避免双真相；按档显式选核需求实证出现
  再议）；`process` 键 v10 起在册（`LightamerSidecar.swift:385` 域亲核，
  hash-isolated）→ **零 schema bump（v11 维持）、零 FilmRecord 新字段、零
  sidecar 键新增**。
- 理由一句：M6-2 账本机制就是为「改观感的核换代」造的——第二真相源（engine
  字段）必然漂移。
- 证据：RESEARCH §3.2 + §OQ-1；`RenderProcess.swift:107-150`（账本 + :109-115
  v2 预案 doc-comment 亲核）；M6-2 五件套预案。
- 晨审推翻点：翻案 = 加 `FilmRecord.engine` 按档显式选核（双真相 + sidecar
  面，不建议）。

### D-M8-2 tc 表来源 = 自拟合首选；GPL 同许可移植为 fallback（OQ-M8-2）

- **裁决 = RESEARCH §5 推荐**：tc 光谱上采样表**自拟合**（Jakob & Hanika
  2019 sigmoid 族数学 + BSD 参考实现方法面，**零代码零表数据拷贝**），fit
  目标 = 每 tc cell 81 点谱，域 = Rec2020 全色度四边形（tri2quad 全域）+
  我方光源集；**fallback 升格** = GPL-3.0 同许可合法移植上游 hanatos2025 表
  （2026-10-20 许可切换直接后果；保留版权 + NOTICE + 标注修改）——fallback
  **不破段结构**（M8-1a 内分支，下游 plan 消费面不变）。
- 理由一句：域合身（Rec2020 working + 我方光源集）+ NOTICE 简洁 + 资产自主；
  GPL 切换后 fallback 已无许可障碍，自拟合失败不再有僵局。
- 证据：RESEARCH §1.2（上游表形态学：pack 存谱非三系数；dt 运行时不含拟合
  代码）+ §2（自装配常量集零 GPL 数据依赖）+ §OQ-2；Jakob & Hanika 2019 /
  rgb2spec（BSD）/ colour-science `colour.recovery`（BSD）。
- 晨审推翻点：翻案 = 直接 GPL 表移植省 1a 拟合器预算（域让位 + NOTICE 加
  条目 + 上游表跨版漂移绑上游节奏，不建议）。

### D-M8-3 重积分形态 = 运行时 3D 表臂 + PCHIP 单调插值采纳（OQ-M8-3）

- **裁决 = RESEARCH §5 推荐**：印相（print_expose）与扫描（scan）走**构建期
  33³ 3D 表 + 运行期单调 PCHIP 插值**（上游双路 bit-exact 工程纪律 §1.6 +
  单调性对密度反演的保形价值；我方现行 rtne 四面体不保形）；表构建 =
  Float64 CPU 精确积分（81 波长循环只在构建期）、存储 float + cmin/cmax
  钳位面全盘平移；精确臂（lut_steps=0 逐像素重积分）**不作运行期目标**，
  仅作 golden 参照（Float64 独立复算，M3-3-03 主门形态平移）。
- 理由一句：PCHIP 保形是密度域反演（print 段 + descriptor probe）的正确性
  前提，且是上游生产路径已验证形态。
- 证据：RESEARCH §1.4（PCHIP 2137-2247 读解：8-cell hermite + slopes/cmin/
  cmax 钳位表）+ §OQ-3；`FilmPrintBake.swift`（65³ Float64 家族——bake 机制
  同位扩展宿主亲核）。
- 晨审推翻点：翻案 = 逐像素精确臂上 GPU（上游明示 no GPU path，逐像素 81
  波长循环 = 预算爆，不建议）/ rtne 四面体沿用（不保形，反演价值倒退）。

### D-M8-4 DIR coupler v1 含入 + 模糊场降采样；空间效果族不入 M8（OQ-M8-4）

- **裁决 = RESEARCH §5 推荐**：v1 **含** coupler correction（模型完整性：
  3×3 矩阵 + Langmuir 饱和数学已全摸清 §1.3），corr 模糊场**降采样
  1/4-1/8 res** 生成-模糊-上采样（§4.2 方案 ①；`film box 不入 tile` 不变式
  维持，全帧两 dispatch + 一小中间面）；grain / halation / diffusion /
  highlight boost / glare **不入 M8**（`spektra_core` 空间族挂账不消费；我方
  grain 已有 dt 遗产面独立承载）。1/4 vs 1/8 终值 = M8-1b probe ③ RSS 实测
  裁决（X3）。
- 理由一句：corr 场是全链唯一新增全幅中间面（float3 @100MP = 1.2GB 超预算
  形），低频模糊场降采样是内存与模型完整性的唯一两全点。
- 证据：RESEARCH §1.3 + §4.2 + §OQ-4；上游 CPU 路 plane+corr+scratch ≈2.8GB
  同判。
- 晨审推翻点：翻案 = v1 砍 coupler（模型完整性缺口，退化为无层间效应的朴素
  密度链，不建议）/ 全幅 corr（1.2GB 中间面，8G 门不可达）。

### D-M8-5 切分 = M8-0 charter 并入 CONTEXT + 四 plan（OQ-M8-5）

- **裁决 = RESEARCH §6.1 切分 + orchestrator 形态指令**：M8-0 charter 四件
  由本文件承载（见 front-matter 形态说明），plan = **1a 数学核-数据面
  （18-24N）→ 1b 数学核-GPU 面（12-18N）→ 2 管线集成（20-26N）→ 3 面板+
  收口（10-14N）**，串行 + C 档门控；ΔN 合计 60-82（L 档，对比 M3-3 批
  ≈45-55 / M2-9 批 ≈60）。风险集中 1b（数值纪律首用）与 2（双臂 golden
  面）；1a 拟合器是长杆，失败回落 D-M8-2 fallback 不破段结构。
- 理由一句：数据面先行让 GPU 面消费确定性输入；集成面把双臂 golden 集中在
  单 plan 内闭环。
- 证据：RESEARCH §6.1-§6.2 + §OQ-5；M3-3/M2-9 批 ΔN 先例。
- 晨审推翻点：翻案 = 1a/1b 并批（单 plan 30-42N 超单批上限，不建议）/
  拟合器独立成第五 plan（段结构碎化，不建议）。

### D-M8-6 FSIM-01c 措辞批修 = NOTICE 披露行升格 + 用户可见措辞 + 历史勘误行（OQ-M8-6）

- **裁决 = RESEARCH §5 推荐**：M8-3 落地批同批——①`Resources/FilmProfiles/
  NOTICE` 消费披露行升格（谱面消费深度从密度域投影扩为「逐波长材料链」，§
  亲核登记⑦——披露条目已在，改的是披露语义）；②用户可见措辞由「物理流程
  建模，非光谱重放」升格为「**光谱重建材质模拟（逐波长），非场景光谱重放**
  」（README/help 面按实际存在点批修）；③历史文档（AGENTS.md M3-3 增量节、
  M3-2 RESEARCH-NOTES）**原文不改**，勘误行追加（惯例）。
- 理由一句：措辞 = 用户对能力边界的唯一知情面；上游 profile JSON 字节原样
  纪律不变。
- 证据：RESEARCH-PRE §2.3 三分口径 + §OQ-6；`Resources/FilmProfiles/NOTICE`
  §2（谱面数组披露在册亲核）。
- 晨审推翻点：翻案 = 措辞维持旧态（能力边界知情面失真，不建议）。

### D-M8-7 UI = 现行 Film 面板平移零新增；adaptation 开关不暴露（OQ-M8-7）

- **裁决 = RESEARCH §5 推荐**：Alcedo 无光谱面对标（M3-2 §10 已核）→ 光谱
  核下 **Film 面板零新增控件**（材料 picker / Y·M / Solve / 宽容度面板数学
  零改；readout 数值随核变 = by design 非 UI 变更）；上游 upsampling 表
  选择器 / 带宽自适应控件 v1 不引入（模型面恒自拟合单表，D-M8-2）；上游
  adaptation_bandwidth / adaptation_surface 两开关（spektrafilm.c:324-332）
  **不暴露**——bandwidth 恒 on / surface 恒 off（上游 reference 同款解析，
  spektra_sim.h:483-497），参数面 = build 期常量（X1）；**UserDefaults 零
  新键**。迁移 UX（「Update to Current Process」= M6-2 §6 挂账正主）为
  M8-3 唯一新 UI 元素（非 Alcedo 对标面，不违本裁决）。
- 理由一句：面板是材料操作的稳定心智面，核换代不该改它；adaptation 两开关
  是 profile 自带的构建期参数不是用户意图面。
- 证据：RESEARCH §OQ-7 + §1.2（adaptation 折 sens_w 构建期亲核段）；
  M3-3-03 Film 面板最小面正本。
- 晨审推翻点：翻案 = 暴露 bandwidth/surface 或表选择器（参数面膨胀 + 双
  心智，不建议）。

### D-M8-8 曝光语义 = exposureEv 走 solve gain 消费层（OQ-M8-8，本版新增 OQ）

- **裁决 = RESEARCH §5 推荐**：上游把 `exposure_ev` 折进 expose 链头
  （`×2^ev`，spektrafilm.c:1514/1780）；我方光谱臂**维持现行 solve-gain
  消费层形态**——`FilmRecord.exposureEv` 经 `FilmSolveCache` 求解折为曝光
  增益施加（record 层手动项走 recordHash 消费叠加、**不入缓存键**——与
  FilmSolveCache「RECORD terms … layer at consumption and are NEVER cached」
  既定契约亲核一致），**不折 expose 链头**。语义对齐账：两者数值等价域不同
  （链头 = 胶片平面曝光缩放；solve gain = 印相曝光归一），我方 M3-4 宽容度
  descriptor 数学与面板已按消费层语义标定，换链头 = 面板数学连锁重标定，
  零收益。
- 理由一句：消费层形态已被 M3-4 面板/descriptor 生态锚定，链头形态 = 纯
  破坏性重标定。
- 证据：RESEARCH §OQ-8；`FilmTailPolicy.swift:441-467`（Solution/
  solvedPackHash + record 项消费层亲核）；M3-4-01 descriptor 标定正本。
- 晨审推翻点：翻案 = exposureEv 折 expose 链头（面板/descriptor 全域重标定，
  不建议）。

## 设计承接钉死（X1..X6，plan 层硬约束）

### X1 tc 表自拟合形态（M8-1a 执行）

- **模型** = Jakob & Hanika 2019 sigmoid 谱族：每色度 cell 三系数（振幅/
  中心/宽度族参数），谱 = 参数化 sigmoid 81 点；拟合目标 = 每 cell 81 点
  目标谱（含反射率/发光两 kind 语义按上游 §1.2 表构建段同构——我方 v1 裁
  **irradiance kind 单臂**（28 张 profile 的 reference/viewing illuminant
  集 + 上游出货表同 kind），reflectance kind 预留 case 不实现）。
- **拟合域** = tri2quad 全色度四边形（`u=(1−x)²`、`v=y/(1−x)`——覆盖光谱
  轨迹内部），网格 192×192（对齐上游边长；`SF_TC_N_MAX`=4096 上限不作运行
  期面）；工作原色 = Rec2020、光源集 = profile reference/viewing illuminant
  ∪ enlarger/observer 集（X 资产面）。
- **拟合器形态** = 构建期 Swift Float64 纯函数（`SpectralTcFit`），输入 =
  常量资产，输出 = 系数表（192²×3 f32 量级）；**拟合目标谱 = 色度域
  metameric 构造式，系数表 film 无关共享——胶片 sens 数据不入拟合目标，
  仅入质量门与下游 per-sim 积分**（review M3①——X1/X2 矛盾消解：X2
  「换光源/感光度适配零重拟合」只在系数表与 film 脱钩时成立；T3 正文
  论文式构造式即共享形，本句为钉死正本）；**产物作为构建期中间量不落包
  资产**（每次 per-sim build 重算——表常驻面 =
  积分后的 442KB tc_lut，系数表只在构建期活；跨 run 缓存 face = X7）；
  质量门 = 覆盖率（全域无
  NaN/发散 cell）+ 平滑度（邻 cell 系数梯度上限）+ 白点积分散 ≤1e-6 带。
- **直接谱表形态否决**（D-M8-2 细化，见 X1 附注）。

### X2 系数表存储形态裁决 = 系数表 + 构建期展开（晨审可推翻点）

- **裁决**：自拟合产物存储 = **每 cell 三系数**（紧凑、可审计、可按
  sens/illuminant 重展开），per-sim 构建期展开成 81 点谱 × 感光度积分 →
  192²×3 f32 tc_lut（442KB 运行期面）；**否决「直接谱表」**（192²×81 f32
  ≈12MB/表，与上游 pack 同形——28 张 film 各一表 = 资产膨胀 +300MB 级，且
  上游存谱的唯一理由 = 表跨胶片共享而适配折入 build；我方系数表形态同样
  达成「模型共享 + per-sim 适配」，以 1/27 体积）。
- 运行期两路等价（RESEARCH §OQ-2 注记在案）：GPU 只见积分后 tc_lut，系数
  表永不进运行期。tc_lut 跨 run 缓存 face = X7（review M3②）。
- 理由一句：系数表是谱表的无损压缩 + 重参数化自由度（换光源/感光度适配零
  重拟合）。

### X3 coupler 降采样臂（M8-1b kernel 形 + M8-1b probe ③ 裁决）

- dispatch 形态 = **A（expose + lograw + corr 生成 fused）→ corr 降采样
  （1/4-1/8 res）→ 分离模糊 pass（现有 blur 基建域，20µm 核 + 可选 3-
  gaussian 指数尾混合）→ 上采样 → B（develop + print_expose +
  print_develop + scan fused）**——两主 dispatch + 一降采样中间面；
  `film box 不入 tile` 不变式维持（RESEARCH §4.2 ①）。
- corr 生成数学 = silver（正片 = dmax−d）× 3×3 coupler 矩阵 + Langmuir
  接收侧饱和（在模糊**之后**应用——上游顺序纪律）；Kr=0 → 1e30 线性哨兵
  NaN 防御平移。
- 1/4 vs 1/8 终值 = probe ③（RSS + corr 高频损失对 golden 的偏差带）双门
  裁决，M8-1b DECISIONS 申报；**fallback 档 = 砍 coupler**（禁用 coupler
  段 = 纯密度链，模型完整性降档但结构不破）——RSS 超 8G 门才启用。

### X4 process v2 双臂（M8-2 执行；M6-2 五件套预案直接执行）

- `RenderProcess` 追加 `.v2`（case doc = 账本行）→ `all=[.v1,.v2]` →
  `RenderProcessVersion.current` 升 2 → **分叉点 = `assembleFilmLeg`/
  `assembleFilmPayloads` 工厂内 exhaustive switch**（编译器逐点指向）：
  `.v1`/`.legacy` = 密度核**冻结臂**（密度核代码 + 65³ bake +
  FilmFilterPackSolver + `film_subrun` kernel 全保留零改）；`.v2` = 光谱臂。
- **缓存折键「非 legacy 才折」契约**（RenderProcess.swift:37-44 亲核）：
  光谱臂 seed 在 `FilmTailAssembly.seed` 的 policyTag 段折 process 标识
  （形态 = policyTag 升 `"lightamer.film.subrun.v2-spectral"` 或等价
  process 折叠段——**折叠序钉死 + legacy 档键字节恒等负测**，v1 文档
  filmRampPlaneHash 与全部既有缓存键逐位不变）。
- 账本五件套随 v2 批交付：①case doc ②AGENTS.md process 账本行 ③新旧
  golden 三件套（v1 零漂移 + v2 光谱 golden）④mint 升号（新档 process=2）
  ⑤分叉点登记（DECISIONS）。
- 子管线继承不变（`filmPipe.renderProcess = renderProcess`，PixelPipe
  :1242/:1395 域）。

### X5 CPU/GPU bit-exact 三板斧移植（M8-1b 逐项落 + golden 门定级输入）

1. **显式 fma 钉形**：所有矩阵乘/累加显式 fma（Swift 侧显式 `fma()` 调用
   ——禁依赖编译器 contract 合并；MSL 侧 `fma()`）〔review m8——原文
   "`a &* `→`fma()`" 残缺：`&*` 是整型溢出算子，Float 无此形〕，禁裸
   `a*b+c*d` 依赖编译器 contract（上游
   spektrafilm.cl:91-103 注释：host `-ffp-contract=off` honored、device 不
   honored → 1 ULP 级分歧）。
2. **host double 单次取倒**：一切倒数（`inv_le_step` / enl/scan inv_range /
   xy 互倒 / 插值步长倒数）在 host Float64 算一次 rounded-to-float 进表，
   禁 device 内重 derive（上游真实分歧源二）。
3. **共享 log2/exp2 多项式**：log10/pow10 走 host 与 MSL 同源多项式
   （共享常量面——Swift/Metal 双落笔 + 逐位同表），禁 libm/设备内建
   （≤3ULP 差异被分段查表边界放大——上游真实分歧源三；我方曲线查表
   256 点分段边界同理敏感）。
- probe ⑤ = 钉形 vs 裸形 CPU-GPU 分歧度量（`LIGHTAMER_PERF_PROBE` 域），
  golden 门精度定级输入（M3-3-03 先例：1e-4/1e-5 分级带）。

### X6 数据资产与曝光语义终式（M8-1a 资产面 + M8-2/3 落地）

- **常量资产五件**（自建/自装配，零 GPL 数据依赖）：CIE 1931 2° CMFs[81×3]
  （公开标准数据，generated Swift 文件 + provenance 头）；illuminant SPD 集
  （D 系列公开公式 + A/ENL 公式 + TH-KG3 卤素+滤光公开描述自近似）；dichroic
  曲线[81×3]（公开描述自近似，dt pack 值域 sanity 带参照）；spectral locus
  多边形（由 CMFs 导出，代码资产）；tc 拟合域常量（tri2quad/中性配平锚）。
  `neutral_print_filters` 已有（CC BY-SA 字节原样纪律不变）。
- **自拟合产物归属注记**：拟合输入 = CC BY-SA profile 数据，产物 = 数学
  拟合系数——**倾向非 SA 衍生**（RESEARCH-PRE §6 判）；M8-1a DECISIONS 落
  charter 法务注记（晨审可推翻；推翻 = 产物随 CC BY-SA 归属 → NOTICE 升格）。
- **曝光语义** = D-M8-8（solve gain 消费层；M8-2 实现随 solve 重推导、
  M8-3 负测钉死 + DECISIONS 裁决登记）。

### X7 tc_lut 运行期缓存 face（M8-2 执行；review M3② 新增裁决）

- **裁决**：tc_lut（含其上游拟合 + 展开 + 积分全成本——构建秒级/表量级
  带，M3③ 重估）**禁每 run 重建、禁逐帧重建**；跨 run 缓存 face =
  **FilmPrintBake 家族同位 per-pair LRU**（进程内、Float64 构建一次、键 =
  materialPair 域 fnv 哈希——对齐 FilmSolveCache 键形先例、bakeCount
  可观测同形），由 **M8-2 T3 bake 家族承载 tc_lut 槽位**（与 print/scan
  PCHIP 槽并存、各自 LRU 槽互不挤兑；容量 DECISIONS 申报），M8-2 T1 光谱
  臂 payload 构造消费缓存命中面。禁执行者临场发明缓存形态（越权面）——
  本条 = 唯一缓存 face。
- 理由一句：与密度域 65³ bake per-pair LRU 机制同位，X2「零重拟合」的
  运行期兑现点（每 run 秒级重建不可接受、每会话首帧大停顿同样不可接受）。

## Hazards（三条，登记 + 消解绑定）

| hazard | 机理 | 消解绑定 |
|---|---|---|
| **H-M1 数值纪律首用** | fma/取倒/log2-exp2 三板斧是本项目首次全链应用（上游三件真实 CPU/GPU 分歧案例为鉴）——分段查表边界 + Poisson 级放大的教训在我方曲线查表/PCHIP 边界同理敏感；漏一项 = golden 门精度崩或 CPU/GPU 双臂漂移 | M8-1b X5 逐项落（fma 钉形 / host double 取倒 / 共享多项式）+ probe ⑤ 钉形 vs 裸形分歧度量 + golden 门精度定级（1e-4/1e-5 分级带先例） |
| **H-M2 coupler corr 场内存面** | 全幅 float3 corr 中间面 @100MP = **1.2GB** 超 8G RSS 门预算形；上游 CPU 路 ≈2.8GB 同判不可接受 | X3 降采样臂 1/4-1/8（19-75MB）+ probe ③ RSS 实测裁决 + 8G 门机检 + MEMFAIL 兜底；fallback = 砍 coupler 禁用档 |
| **H-M3 数据包归属义务** | CC BY-SA 谱面消费披露（NOTICE 已有条目，消费深度升格 = D-M8-6）；自建常量资产来源登记（公开标准/自拟合 provenance）；自拟合产物 SA 衍生判定待法务注记；GPL fallback 表若启用 = 版权 + NOTICE + 修改标注义务 | M8-1a DECISIONS 法务注记 + 资产 provenance 头；M8-3 NOTICE 批修 + 勘误行；GPL fallback 启用 = plan 内分支申报 NOTICE 增补 |

## 亲核登记（planner 抽核批，2026-10-24 HEAD `9b256482`；非矛盾、执行以本节为准）

1. **基线权威数证据链**：LUMEN-BC 独立复跑 `TOTAL|4204/41/0|`
   （`LUMEN-BC-ACCEPTANCE.md:13`）+ LUMEN-C R2 同值（`LUMEN-C-SUMMARY.md:38`
   ，峰值 RSS 全在 8G 门内）→ r13 批 `d2bcaf06` Library bundle +2 测试
   （13/0/0，commit body 亲核）→ **现行基线 = 4206/41/0**（orchestrator
   指令值成立）。全套预期 = 4206 + ΔN 60..82 = **4266..4288**；skip 增量 =
   M8-1b probe 族（LIGHTAMER_PERF_PROBE skip-by-default）逐族申报禁静默吸收。
2. **FilmProfile 类型面缺口精确清单**（RESEARCH §3.3 的执行面细化）：既有
   解码 = `logExposure/densityCurves/baseDensity/wavelengths` 四项 + Info.
   `referenceIlluminant`（亲核）；JSON 在册而**类型面缺席** = `data.
   log_sensitivity[81×3]` + `data.channel_density[81×3]` +
   **`data.midscale_neutral_density[81]`**（RESEARCH 未列，亲核五 profile
   抽样在册）+ `data.hanatos2025_adaptation_window_params` +
   `data.hanatos2025_adaptation_surface_params` + **`info.viewing_
   illuminant`**（RESEARCH 说「随文件携带」= true，但类型面 Info 未解码
   viewingIlluminant——亲核 zero hit）。M8-1a T1 additive 范围以此六项为准。
3. **行号/机制引用抽核吻合**（±1 行微差不影响语义）：`PixelPipe.swift`
   runTerminalTails :1145 起（①film→②DRT→③replay 骨架 + filmTail==nil 零
   路径）；`FilmTailPolicy.swift` FilmTailAssembly.policyTag
   `"lightamer.film.subrun.v1"` :89 + seed 四项 canonical 序 :100-112 +
   FilmMethodBox :197 起 + iopOrder 74.0 :227 + displayReplayResidents 3×2
   :164-185；FilmSolveCache 键 `fnv(materialPairHash ⊕ statsHash ⊕ modeTag)`
   + LRU 8 + Solution.solvedPackHash + RECORD-terms-consumption 契约 :441 起
   ；`FilmPrintBake.swift` level=65 / Float64 / concurrentPerform 文件头亲核
   ；`RenderProcess.swift` all=[.v1]/current=1/resolving clamp/:109-115 v2
   预案 doc-comment/「非 legacy 才折」:37-44；`LightamerSidecar.swift`
   schemaVersionCurrent=11 :255 + process 键 hash-isolated doc。
4. **filmRampPlaneHash 哨兵**：既有值 `14_365_179_805_968_017_957`
   （`FilmDeterminismTests.swift:44`）——RESEARCH §4.3 probe ④「新哨兵」=
   光谱臂新哨兵值（M8-1b probe 批计算登记）；**legacy 哨兵值在册不动**，
   v1 档零漂移负测锚定。
5. **perf probe 先例四件在册**（LensPerfProbe / DepthPerfProbe /
   GradeEnvelopePerfProbe / ColorMatchBakeGolden——`LIGHTAMER_PERF_PROBE` 门
   + XCTSkipUnless + L014 fence 形态可平移，非新模式）。
6. **七 bundle 名亲核** = `IOP / IOPParity / Layers / Library / Sessions /
   Export / App`（`Scripts/test-direct.sh:173` BUNDLES 行）；BUNDLE-MAP 正本
   = `.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt`。
7. **NOTICE 现文**：§2 已披露 81 波长谱数组（log_sensitivity/channel_density/
   midscale_neutral_density 在列）——D-M8-6 批修对象 = 披露语义升格（密度域
   投影 → 逐波长材料链），非新增条目；28 profile + neutral_print_filters
   byte-verbatim + MANIFEST.sha256 对账纪律不变。
8. **machine-guard v1.4 在位**（`93a97ed6`；`Scripts/machine-guard.sh` 亲核
   存在）——执行批重活前置门可用。

## 测试策略（六门，四 plan 共用正本）

1. **dt 同源 golden（GPL 合规直对表）**：GPL-3.0 同许可切换后，上游
   spektrafilm 单测/参考数值可**直接对表**（读解 → 数值转录 → 对拍，版权 +
   修改标注纪律）；对表数值入 plan evidence（`.work/gsd/phases/m8-fsim-
   spectral/evidence/`），**不入 CI 门**（跨仓路径不可 CI 依赖）；dt pack
   本地无克隆维持——对表对象 = 上游单测内嵌期望值与读解转录，pack 仅值域
   sanity 带参照。
2. **NumPy 对拍（独立实现双轨）**：构建期数学（CMFs 积分 / tri2quad /
   sigmoid 谱重建 / PCHIP）以 Python/NumPy 独立复算对拍 Swift Float64 引擎
   （同笔转录系统性误读自消的对冲）；脚本 + 输出落 evidence，golden 门本体
   = Swift 独立复算测试（可 CI）。
3. **CPU/GPU bit-exact 断言（三板斧逐项）**：M8-1b——七 stage CPU 参考
   Float64 vs Metal kernel float 的分歧带门（分级：表构建逐位 / 逐像素
   ≤1e-6 带域 / 分段边界专项例）；fma/取倒/共享多项式各配专项断言。
4. **100MP perf probe（coupler 降采样臂裁决数据）**：RESEARCH §4.3 五件
   ——①tc 表构建耗时/白点散 ②kernel microbench（合成 ramp + 真图 100MP，
   全帧 + 分段 signpost）③RSS 峰值 corr 两方案对照 ④pristine/strength-0
   基线 + 光谱臂新 ramp 哨兵 ⑤钉形 vs 裸形分歧度量；`LIGHTAMER_PERF_PROBE`
   + XCTSkipUnless + L014 fence（无 fence 计时 = 假数）。
5. **密度域 legacy 双臂 golden（process v1 不变）**：既有 FilmDeterminism
   golden（含 `filmRampPlaneHash=14_365_179_805_968_017_957`）零漂移负测 +
   v1 文档全链缓存键逐位恒等断言（「非 legacy 才折」契约的负测面）——
   M8-2 主门之一。
6. **光谱臂 golden 三件套**：合成 ramp 场 + 真图抽样 ×（v1 密度核 /
   v2 光谱核）双臂输出哈希 + 精度带；中性闭合（中灰过全链通道散 ≤2e-3 带，
   M3-3-03 先例平移）+ 白点积分散 ≤1e-6（构建期）。

## 四 plan 红线 front-matter（共用正本，四 plan 逐条引用）

1. **FIX2③ = `App/Sources/Lightamer/Library/LibraryProjectController.swift`
   零 diff**（AGENTS.md:395 现行登记——连续六波亲证；review m3——M7 旧指称
   McpServerController 勘正）；`McpServerController.swift` 零 diff 延续面
   同保（M7-4 起惯例，MCP 面与本批零交集，四 plan 全程不触）。
2. **封存面零 diff（M7-6 清单 + film 自有面适配注记）**：`DrtRecord/
   TerminalTailPolicy/DrtTailAssembly/DrtPanelModel/DrtPanelView/DrtEotf/
   Lut3dKernels.metal/ExportQueueContract/六格式导出矩阵（ExportFormatSpec·
   ImageIOEncoders·WebPEncoder）/NodeGraphCommand/LightamerSidecar（schema
   零 bump v11）/HistoryStack/HistoryHash/PipelineDocument（Core）/V50Order/
   GradeCatalog（NodeOwnershipCatalog）/Registry/ModuleInstance` 零 diff；
   **film sub-run 自有面豁免**（特别登记一清单：FilmTailPolicy / FilmPrintBake /
   PixelPipe film-leg 组装区 / 新建
   SpectralFilmKernels.metal 与 Spectral 载体 = 本批正业；**`FilmSubRunKernels.metal`
   恒零 diff 不在豁免面**——review m2）——但
   `runTerminalTails` 编排骨架 / seed 折叠序 / FilmMethodBox 对外面零改；
   `Project.swift` 仅允许测试数组段与资源段 diff；`RenderProcess.swift` 仅
   允许 v2 bump 面 diff（M8-2）；HistoryHash 零 diff = process 不折 history
   hash 的机检面（RenderProcess 头正交性红线）。
3. **零 FilmRecord 新字段 + 零 sidecar schema bump + 零 sidecar 新键**：
   `process` 键 v10 已在册 = 光谱开关单源（D-M8-1）；sidecar 往返测试
   （v11 文档 decode→encode 逐字节）随 M8-2。
4. **xcstrings 尾块纯插入**：新键（M8-3 迁移 UX 面）一律 append 至
   `Resources/Localizable.xcstrings` `"strings"` 尾部；每批收尾
   `Scripts/zh-audit.py --check` + `--self-test` 双 PASS；动态键显式 switch
   返回静态键（V14）。
5. **LocalizationValue 禁形零命中**：`String.LocalizationValue("prefix_
   \(x)")` 插值动态查表键禁（M2-9 F-2）。
6. **L041 tuist generate 恒末位**：新测试文件 → `Project.swift` 对应
   bundle 显式数组（无 glob）同批更新；`tuist generate` = 该批最后一个动作。
7. **机器级单重活 + 排程**：执行批一切重活（xcodebuild / test-direct /
   probe / GUI 走查）起跑前必过 `Scripts/machine-guard.sh`（--wait 轮询）；
   **本批执行排在图库选片批验收链之后**（orchestrator 排程指令）；两并发 =
   禁止。
8. **perf probe 纪律**：`LIGHTAMER_PERF_PROBE=1` + XCTSkipUnless（默认套件
   skip）；探针读钟前 queue fence（L014）；RSS 经 `/usr/bin/time -l`
   ru_maxrss 口径；skip 增量逐族申报。
9. **--all 批准制 + 运行监视**：orchestrator 批准 + 8G 门
   （RSS_LIMIT_MB=8192）+ MEMFAIL 机检 + caffeinate -dis 包裹 + 测试宿主
   清理先核 parentage（`ps -o ppid`——测试宿主 parent = 脚本进程树，GUI
   实例 parent = launchd，M2-7-3 先例）。
10. **C 档门控**：每 plan 执行+验收闭环后停汇报，等用户确认再放行下一
    plan。
11. **UserDefaults 零新键**：本批无任何应用级新键（D-M8-7——adaptation 恒
    build 期常量无 UI 面；迁移动作不落偏好）。
12. **默认中性零行为门**：无 film record（pristine）文档 + `process ≤ 1`
    文档渲染**逐字节不变**——每 plan 带默认中性 golden 负测；缩略图恒
    legacy 不变（M3-3 先例）；导出面零新增开关（filmTail 跟随文档 record +
    process，`$jobFilmTail` 递缝零改）。
13. **L057 缝**：迁移确认等一切对话框走 SwiftUI sheet / PanelPresentation
    缝；`.runModal(` 在 `App/Sources` 零命中。
14. **测试落域**：新测试文件按 BUNDLE-MAP 域模式归唯一 target——数学核
    纯函数/解码/拟合器 → IOP；golden/bit-exact/perf probe（*Golden*/*Parity*/
    *PerfProbe* 命名）→ IOPParity；process 账本/sidecar 投影 → Layers；
    面板/UI 模型 → App；跨 bundle 零重域；tuist generate 恒末位（红线 6）。
15. **commit 纪律**：每任务独立 commit（Conventional Commits 全英文、只 add
    相关文件、不 push）；plan 内 commit 草稿**零 issue ref**（orchestrator
    登记口径；产品面 issue 关联由 orchestrator 执行批注入）；执行前缀
    `feat(m81a)/fix(m81a)/test(m81a)/docs(m81a)`（1b/2/3 同式）。
16. **GPL 移植合规**：dt 读解转录件（含 GPL fallback 表移植若启用）= 版权
    头 + `Modified by Lightamer` 标注 + NOTICE 登记；零归属入库 = 流程违规；
    自建资产 provenance 头随文件（X6）。
17. **process 账本 bump 五件套**（M8-2 专属）：case doc / AGENTS 账本行 /
    新旧 golden 三件套 / mint 升号 / 分叉点登记——缺一 = v2 bump 不完整，
    收口门拒绝。

## ΔN 分账 + 全套预期带

| plan | ΔN | 累计带（executed） | 构成要点 |
|---|---|---|---|
| 基线 | — | 4206/41/0 | LUMEN-BC 4204 + r13 +2（亲核登记①） |
| M8-1a | +18..24 | 4224..4230 | 谱解码 +2..3 / 常量资产 sanity +3..4 / 拟合器 +5..7 / 构建期引擎 golden +6..8 / 收口 +2 |
| M8-1b | +12..18 | 4236..4248 | kernel golden +2..3 / 表载体 +2..3 / bit-exact 三板斧 +3..5 / probe 批 +4..6〔skip 族〕/ 收口 +1 |
| M8-2 | +20..26 | 4256..4274 | 换臂分叉 +2..3 / solve 光谱域 +4..5 / bake PCHIP +3..4 / process v2 +3..4 / 双臂冻结 golden +5..6 / sidecar+折键负测 +3..4 / 收口 0 |
| M8-3 | +10..14 | 4266..4288 | UI 零新增断言 +2..3 / probe 跟随核验 +2..3（review M2——原 +1..2 致行和 9..13 ≠ 表称 +10..14，+1 对齐；行和复核 2..3+2..3+4..5+2..3 = 10..14 ✓；终值带 4266..4288 复核不变 4206+60=4266 / 4206+82=4288）/ 迁移 UX +4..5 / 曝光语义钉死 +2..3 / --all 对账 0 / 收口 0 |
| **合计** | **+60..82** | **4266..4288** | skip 带内增量 = 1b probe 族，逐族申报 |

## 晨审推翻点索引（可推翻面速查）

- **D-M8-1**：process 单源 ↔ 加 FilmRecord.engine 双真相（不建议）。
- **D-M8-2**：自拟合 ↔ GPL 表直接移植（省拟合器预算，域让位 + NOTICE 加条）。
- **D-M8-3**：PCHIP 3D 表 ↔ 逐像素精确臂上 GPU（no GPU path）/ rtne 沿用
  （不保形）。
- **D-M8-4**：coupler 含入+降采样 ↔ v1 砍 coupler（完整性降档）/ 全幅 corr
  （1.2GB 不可达）。
- **D-M8-5**：四 plan 串行 ↔ 1a/1b 并批 / 拟合器独立第五 plan。
- **D-M8-6**：措辞升格 ↔ 维持旧态。
- **D-M8-7**：UI 零新增 ↔ 暴露 bandwidth/surface/表选择器。
- **D-M8-8**：solve gain 消费层 ↔ exposureEv 折 expose 链头（面板/descriptor
  全域重标定）。
- **X2**：系数表+构建期展开 ↔ 直接谱表（12MB/表 × 资产膨胀）。
- **X6 归属注记**：自拟合产物非 SA 衍生 ↔ 按 CC BY-SA 归属升格。

## 评审回注勘误登记（2026-10-24 plan fixer 批；评审正本 = 同目录
## M8-PLAN-REVIEW.md `a1dd6b65`，FAIL 1 blocking + 4 major + 9 minor）

> 逐条回注四 plan + 本文件，行内标记 `(review B1/M#/m#)`；零源码触碰。
> 落点索引：

- **B1**（blocking）→ M8-1A SC/T1：谱字段类型面 `channelDensity
  [[Float?]]` / `midscaleNeutralDensity [Float?]`（`baseDensity [Float?]`
  先例同款；28/28 张 profile 实测含 null——channel_density 15-78/243、
  midscale 5-26/81）+ null 语义投影/插值 face 单源（`baseDensityProjection()`
  家族同位）+ 28 张冒烟断言 null-aware。
- **M1** → M8-1A T4 增输入 gamut 压缩 remap 构建步（上游默认 on：
  `input_gamut_compress /* true */` spektra_sim.h:601——评审指称
  spektrafilm.c:601 系 sim.h 微差；白心 = proj_xy 居中纪律 sim.c:3840-
  3843）+ M8-1B T1 expose 注记 remap 预折进表（运行期零额外步）。
- **M2** → M8-3 ΔN 表 T2 行 +1..2 → +2..3（行和 9..13 → 10..14 对齐
  表称；终值带 4266..4288 联动复核不变：4206+60=4266 / 4206+82=4288）+
  本文件 ΔN 分账表 M8-3 行构成要点同批。
- **M3** → 本文件 X1 sens 身份勘正（拟合目标 film 无关共享）+ X7 tc_lut
  缓存 face 新增裁决（M8-2 T3 承载/T1 消费）+ M8-1A T5/风险节时长带重估
  （<100ms 级 → 秒级/表量级带 + 并行预期 + 实测 DECISIONS 申报）。
- **M4** → M8-3 面板路径两处勘正 `App/Sources/Lightamer/UI/Shell/
  FilmPanelView.swift`（UI/Inspector/ 下无 FilmPanelView 真身——实测亲核）。
- m1 → M8-2 T4/T6 折键收窄差 DECISIONS 登记要求（fold discriminator =
  resolved arm，窄于 header `rawValue > 0` 字面形）。
- m2 → 本文件特别登记一 + 红线 2 豁免清单（FilmSubRunKernels.metal 移入
  恒零 diff 面 + 封存清单引称改「M7-6/M3-3 邻接面」）。
- m3 → 红线 1 FIX2③ 指称改 `LibraryProjectController.swift`（AGENTS:395
  现行；McpServerController 零 diff 双列延续面）。
- m4 → M8-2 T1 v2 payload 形断言后移 T4（T1 时 `all=[.v1]` 断言不可满足；
  T1 改 resolving 全域 clamp 面断言）。
- m5 → M8-1B 红线 front-matter 补红线 16 + T1 验收 GPL 归属块/NOTICE
  登记 grep 机检。
- m6 → M8-2 T2 指称改「M8-1a T4 SpectralBuildEngine 积分面」（原「T2
  引擎」两头不沾）。
- m7 → M8-1A T4 preflash 参数面预留（sim.h:552 默认 0 恒等关）。
- m8 → 本文件 X5 fma 表述勘正（`&*` 整型算子残缺 → 显式 `fma()` 调用）。
- m9 → M8-1B T2/SC 载体形态 rgba32Float（alpha pad，体积门按 442KB
  量级）或 buffer——Metal 无 float3 像素格式。
