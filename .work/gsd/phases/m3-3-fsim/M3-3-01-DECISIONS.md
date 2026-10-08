# M3-3-01-DECISIONS — FSIM 数据模型与资产批（wave 1）

> 执行：2026-10-07/08 夜间（executor subagent，夜间全自动授权在案）。
>  commits：T1 `22e14c8` → T2 `04b2909` → T3 `1ea9264` → T4 `72b7222` → T5
>  `0a48b55` → T6 `dc82dc0` → T7 本批（docs）。
> 本文 = KD-1..6 执行期裁决正本。checker 回注（2026-10-08）四条（E2/E3/m2/m3）
> 全部落地为执行处方，此处登记落点与执行期细化。

## §1 KD-1 FilmRecord —— 按处方落地，零偏离

- 字段七件：`film_stock` / `paper_stock`（空串 = pristine 组成部分）+
  `y_filter_shift` / `m_filter_shift`（CC 点域 0-100，手动恒在，Core 不钳）+
  `content_adaptive_shift`（默认 false = SpektraLab 对齐）+ `strength`
  （RFC-025 密度域混入，默认 1.0，Core 不钳）+ `exposure_ev`（默认 0）。
- `stableHash()` = `.sortedKeys` canonical JSON 的 FNV-1a（DrtRecord 同式，
  L013）；`isFilmRecordDefault` = pristine 判定单源（非渲染身份声明）。
- **PresetNames = 空命名空间**（占位常量族，D-1）：plan 要求「占位常量族」，
  执行裁 = 空 enum + 注释说明 M3-3-03 拥有预设注册面后在此追加拼写——不虚构
  预设名（虚构会有下游键族语义）。编译面零 warning。
- 枚举不设（开放字符串 id）照处方；typed 降级在 store/loader（本 plan =
  加载器 fail-closed + store `profile(id:) -> nil`，App 面 typed 提示 = M3-3-02）。

## §2 KD-2 资产五件套 —— 一处授权内形式细化

- 28 profile + neutral_print_filters.json **字节原样**（copy + `shasum -a 256`
  源/仓双对账 + `diff -r` 零输出；MANIFEST.sha256 30 行 = LICENSE + 29 资产；
  FilmProfileTests 全量对账（逐行 re-hash）+ 逆向覆盖断言（树内无孤儿）。
- **LICENSE 形式细化（D-2）**：plan 写「CC BY-SA 4.0 法律全文，
  creativecommons.org 官方文本」。执行采用**上游 `SPEKTRAFILM_LICENSE.txt`
  逐字节副本**（preamble v1.1 + 完整 CC BY-SA 4.0 法律文本 520 行）——
  依据：①该文件**包含**官方全文（尾部至 Creative Commons 联系段）；②上游
  许可文本自身要求「保持本文件不变地随 profiles 分发」+「changes 记入
  CHANGELOG.txt 随附」——采用上游钦定形式比裸 official 文本更合规；
  ③逐字节原样符合「资产零改动」总纪律。NOTICE 交叉引用。
- NOTICE：署名/citation 全文转录/来源版本 0.3.2/原样副本声明/**消费面披露**
  （密度域消费 + base_density 仅经登记三点投影 + wavelengths 仅作轴——
  「物理流程建模，非光谱重放」边界注记）；SA 传染面（及资产本体与衍生资产）
  与 MIT LUT 物理隔离声明。
- CHANGELOG.md：引入版本 **0.3.2**（28/28 文件 metadata.version 实盘一致，
  非抽样）+ 引入日期 2026-10-07。
- `Resources/LUTs/`（MIT）零触碰（plan diff 文件清单机检在案）。
- folderReference 进 App target（Tuist 4.208 裸目录字符串坑注记在代码注释，
  M2-5-3 先例）；`tuist generate` 恒批尾（L041，每任务遵守）。

## §3 KD-3 FilmProfile schema/加载器 —— 两项执行期发现

- **D-3a（schema 结构发现）**：资产数据键嵌套在顶层 `data` 对象内
  （`{metadata, info, data:{log_exposure,...}}`），plan 消费键清单按平铺拼读。
  处置 = 类型面保持平铺消费形状（`profile.logExposure` 等），
  Codable 经 `nestedContainer` 投影 `data`——**资产零触碰**，RESEARCH §1.5
  的表读法按嵌套修正。消费键只解码不变：re-encode 输出 = `{metadata, info,
  data}` 三节、data 四键（测试机械钉死——光谱 payload 不进类型面且不可能
  回漏）。
- **D-3b（densitometer 矩阵细化，m3 落点）**：plan 粗注「film 侧 status_M /
  相纸侧 status_A」。28 文件实盘矩阵：**paper 6/6 = status_A；positive 反转片
  4/4 = status_A；negative film 18/18 = status_M——唯 kodak_2383/2393
  （print-film 库存，support=film/type=negative）= status_A**。mixed-domain
  近似边界口径收窄为「求解输入对 = status_M 负片 × status_A 相纸」；2383/2393
  的消费归属（print 路材料，非负片路）挂 M3-3-02+ 细读，本 plan 不消费。
  全集断言机检入 FilmProfileTests（含 2383/2393 例外显式列出）。
- 形状校验族（fail-closed typed）：曲线行数 = log_exposure 行数（≥2）+ 每行
  3 通道 + `base_density.count == wavelengths.count`（E2 错位防）+ λ 轴严格
  递增有限（轴校验——E2：禁网格假设的另一半）。load() 解码后显式校验
  （合成 Codable 不经 memberwise init 的缝，注释在案）。
- **baseDensityProjection（E2 正本）**：`base_R/G/B := base_density(λ≈650/
  550/450nm)` 三点最近邻（并列取低 index，确定性）；采样点 None 或轴空 =
  `baseProjectionUnavailable(wavelength:)` fail-closed（优先于缺省 0，E2
  处方原文）。portra_400 落点 = 0.1945546/0.6023984/0.8150475（回注亲核值
  0.195/0.602/0.815 逐位吻合）。常量族 `CalibrationWavelength.{red,green,blue}`
  单源。

## §4 KD-4 FilmMaterialStore —— 零偏离

- 目录注入式 init（App bundle 零依赖）；load-and-index-once；坏资产/重名/
  缺 id = typed 错误，**不携带部分索引**。`filmStocks()/paperStocks()` 按
  stock id 排序（菜单序确定性）。
- `materialPairHash`：FNV-1a 64，字段显式折叠（L013）——stock UTF-8 ‖
  log_exposure bits ‖ density_curves bits（行主序）‖ base_density
  （**nil tag + bits**，nil 恒不与 0.0 碰撞）‖ wavelengths bits；film 先、
  paper 后。**E2 联动**：base_density + wavelengths 随裁决入消费集 = 入身份域
  （身份域 ≡ 消费域恒等式；弃投影则同批移除折叠——注释钉死）。
  未消费光谱 payload 与 metadata/info 散文不入身份。
- store 测试按 front-matter 五测试文件清单并入 FilmProfileTests（+5 法，
  不另立文件——front-matter 面零扩散；BUNDLE-MAP 行 16→21 同批勘误）。

## §5 KD-5 bake 期求解器 —— 执行期标定正本（本文核心节）

### D-5a 模型域定义（plan 方程的 Float64 具体化）

plan 方程 `paper_R(f_R)=paper_G(f_G+k_m)` 的可直接实现需要两处具体化，
均为本节登记后成为正本：

1. **印相输入反演**：相纸的 log-exposure 输入 = **负片密度的取负**
   （`x_c = −f_c + gain_c`）。直读正密度入相纸曲线（`x = f + gain`）不可行
   ——输出顶死 Dmax 肩部、G/B 无解空间（预标定数值证伪在案）；取负 = 光学
   正确方向（负片密度衰减曝光），dial 常数吸收光源谱/相纸感光的标定差。
2. **双表盘换算常数**（RESEARCH §4.1「k = CC 点 × 换算系数，plan 期标定」
   的兑现）：`s_m = 0.0085`、`s_y = 0.017` log10 曝光单位每 CC 点——
   **2:1 黄/品红 dial 比例**（经典 dichroic 头标定关系；Y 表值域到 116 而
   M 到 92 的实测分布与该比例一致）。单一常数无法同时落两具名组合于
   ±10 带（M 交域 [0.00799,0.00877] 与 Y 交域 [0.01532,0.01969] 离散，
   预标定计算在案）——双常数是数据要求的形状，非拟合自由度滥用。

### D-5b 修正向量解值（E3 复核终值，测试写死）

Float32 存储路径（资产全量经 Float32 round-trip 再拓宽 Double）+ 60 迭代
+ 1e-12 epsilon 的精确解：

| 组合 | 表值 (M, Y) | 我方解 (M0, Y0) | 偏差 |
|---|---|---|---|
| portra_400 × portra_endura | 51.568 / 52.534 | **57.9322 / 49.2372** | +6.36 / −3.30 |
| ektar_100 × ultra_endura | 71.217 / 55.584 | **63.1549 / 59.1051** | −8.06 / +3.52 |

四值全部落表值 ±10 CC 窄带。错误向量 `k_m·[0,1,1]` 重解：**Y 解移出带
−29.0 / −31.6 CC**（20.27 / 27.53），M 解不变（G 方程不受污染——判别力
住在 Y 通道，构造使然，测试双断言）。±10 带不改宽：判别自检在带外充分
（≥22 CC 距离），无「实测不出带」上报条件。

### D-5c 确定性门（FSIM-01b 数学半面，先钉）

Float64 通道数学（Float32 存储**先精确拓宽再算术**——注释与测试同钉）；
固定 60 迭代 + 固定 1e-12 epsilon（无自适应步长）；无初值依赖（纯二分）；
双调用 **bit-identical**（bitPattern 断言）+ 跨 fresh 盘加载一致。
`paperOutputs` 内面暴露给测试做单调括号前提自检（零滤色时 G/B 低于 R 锚、
dial 单调升、解点三通道相等 ≤1e-9）。

### D-5d 串扰矩阵义务（双向登记）

本 plan 参考链恒等串扰；M3-3-02 kernel 定形时**回填本参考 + 重标 sanity
解值**（解随模型走是设计内，断言带宽不变、中心值随解更新写死）——
M3-3-02 DECISIONS 须回收本条。

## §6 KD-6 持久化三件 —— 零偏离 + 一处 front-matter 勘误

- sidecar v9 additive 面（`filmRecord` 文档字段 + `SidecarHistoryItemRecord`
  镜像）+ `HistoryItem.filmRecord` + `commitFilm`（`filmDocumentScope =
  "__filmDocument__"`）+ `effectiveFilmRecord` + HistoryHash 尾位折叠
  （`filmRecord: FilmRecord? = nil` 默认参——全部既有调用点零改动编译；
  film 排 drt 之后，序换断言钉死）。
- driftDetected 双投影喂入：`effectiveDrtRecord()` + `effectiveFilmRecord()`
  （读侧 = history 自投影，**非**文档字段——P1「字段无 backing item 不进锚」
  形态 DRT 同款保真，正反双 tamper 测试钉死：item tamper → drift 翻真；
  field-only tamper → 不翻）。
- **front-matter 勘误（obs 同款登记）**：折叠函数实体在 `HistoryStack.swift`
  尾部 extension（M2-6-3 PLACEMENT NOTE 钦定位置），非 front-matter 所列
  `HistoryHash.swift`——实际触面 = HistoryStack.swift；HistoryHash.swift
  本 plan **零 diff**（机检在案）。SUMMARY §七如实申报。

## §7 执行期遗留与移交（M3-3-02 读此处）

1. carrier/写腿/恢复腿（App 面）+ 渲染 sub-run + coordinator 接线 = M3-3-02
   （plan 原文）；`driftDetected` 已含 film 折叠——写侧 `makeSidecarDocument`
   接线时 film item + 文档字段必须**成对写入**（锚一致性条件）。
2. 串扰矩阵回填义务（D-5d）。
3. kodak_2383/2393 消费归属细读（D-3b）。
4. contentAdaptiveShift 运行期统计分量 + 缓存键
   `fnv(材料对Hash ⊕ 统计Hash ⊕ 模式tag)`（materialPairHash 已备第一项）。
5. FilmRecord.PresetNames 待 M3-3-03 预设注册面填充。
