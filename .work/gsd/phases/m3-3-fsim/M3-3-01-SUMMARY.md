# M3-3-01-SUMMARY — FSIM 数据模型与资产批（wave 1）

> 执行：2026-10-07/08 夜间（executor subagent，夜间全自动授权「开跑，不要停」在案）。
> 基线：`c8ddc57`（3029/16/0 = 3024 + `571c3c0` +5；今日两场历史手术后以
> 文件名/符号定位，SHA 引用以本文件 commit 列为准）。
> 产出 commits：T1 `22e14c8` → T2 `04b2909` → T3 `1ea9264` → T4 `72b7222`
> → T5 `0a48b55` → T6 `dc82dc0` → T7 本批（docs）。
> **未 push**（纪律）。

## 一、交付面（对表 plan front-matter files_modified）

| 文件 | 变更 | commit |
|---|---|---|
| `LightamerCore/Sources/Graph/FilmRecord.swift` | 新建：七字段 document 级 record + tolerant decode + stableHash + isFilmRecordDefault + PresetNames 空占位命名空间（D-1） | `22e14c8` |
| `LightamerCore/Sources/Film/FilmProfile.swift` | 新建：消费键 Codable（`data` 嵌套投影，D-3a）+ 形状校验 typed 族 + baseDensityProjection（E2 正本） | `1ea9264` |
| `LightamerCore/Sources/Film/FilmMaterialStore.swift` | 新建：目录注入 store + 分型索引 + materialPairHash（消费域 ≡ 身份域） | `72b7222` |
| `LightamerCore/Sources/Film/FilmFilterPackSolver.swift` | 新建：midGrayDensities 参考 + 顺序两步 1-D 有界二分 + 错误向量判别面 + 常量族（D-5a/b/c） | `0a48b55` |
| `LightamerCore/Sources/Sidecar/LightamerSidecar.swift` | v9 additive：`filmRecord` 文档字段 + `SidecarHistoryItemRecord` 镜像 + driftDetected 双投影喂入（§6 勘误注记） | `dc82dc0` |
| `LightamerCore/Sources/Pipe/History/HistoryStack.swift` | `HistoryItem.filmRecord` + `filmDocumentScope` + `commitFilm` + `effectiveFilmRecord` + HistoryHash 尾位折叠（**折叠函数实体在此文件**，front-matter 勘误见 §七） | `dc82dc0` |
| `Resources/FilmProfiles/`（新建隔离目录） | 28 profile + neutral_print_filters.json 字节原样 + LICENSE（上游 SPEKTRAFILM_LICENSE.txt 逐字节，D-2）+ NOTICE + MANIFEST.sha256（30 行）+ CHANGELOG.md | `04b2909` |
| `Project.swift` | App target `.folderReference(path: "Resources/FilmProfiles")` + 测试登记五处 | 随各任务 |
| `Tests/LightamerTests/FilmRecordTests.swift` | 新建（LAYERS）9 法 | `22e14c8` |
| `Tests/LightamerTests/FilmProfileTests.swift` | 新建（LAYERS）21 法 = 资产完整性 5（T2）+ 加载器/投影 11（T3）+ store/pair-hash 5（T4，按 front-matter 五文件清单并入） | `04b2909`/`1ea9264`/`72b7222` |
| `Tests/LightamerTests/FilmFilterPackSolverTests.swift` | 新建（LAYERS）8 法 | `0a48b55` |
| `Tests/LightamerTests/FilmSidecarTests.swift` | 新建（LIB）6 法 | `dc82dc0` |
| `Tests/LightamerTests/FilmHistoryTests.swift` | 新建（LAYERS）8 法 | `dc82dc0` |
| `.work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt` | 五行增记 + T3/T4 计数同批勘误（E2 闭环） | 随各任务 |
| `.work/GOAL-STATE.md` / `.work/TODO.md` | 续接点 / M3-3 条目 | 本批 |

## 二、AC 总表核验

| # | AC | 结果 |
|---|---|---|
| 1 | FilmRecord 落位 + round-trip/tolerant decode | ✅ 9 法绿（defaults/snake_case 键集/部分键+未知键/stableHash 公式独立复算/pristine） |
| 2 | 资产五件套（MANIFEST 全量对账 + 隔离 + MIT 零触碰） | ✅ 源/仓 shasum 双对账 + diff -r 零输出（引入时）+ 21 法内 5 法持续对账；LUTs 目录零命中（diff 机检） |
| 3 | 加载器只解码消费键 + 形状校验含 base_density/wavelengths + fail-closed | ✅ re-encode 键集机械钉死；三形 mismatch/坏文件/坏轴 typed 拒；投影 fail-closed（None/轴空） |
| 4 | 求解器确定性 + 两具名组合窄带 + 错误向量判别 + 常量族 | ✅ bit-identical 双调用；portra/ektar 四值全落 ±10 带（57.93/49.24、63.15/59.11，表值 51.57/52.53、71.22/55.58）；错误向量 Y 出带 −29.0/−31.6 CC；常量 2:1 比例在册 |
| 5 | sidecar v9 additive（v8 零漂移负测）+ history 三件 + 默认参零改动 | ✅ v8 字节回环 byte-exact（digit-only diff）；无 film item 折叠逐位不变负测；film 排 drt 后序断言 |
| 6 | 登记闭环 + 密封面零命中 | ✅ 三方对表（下方）+ `git diff c8ddc57..HEAD` 密封词零命中 |

## 三、测试数字（vs 基线 3029/16/0）

- **定向 bundle 实跑**（`Scripts/test-direct.sh` + `caffeinate -dis`）：
  - Layers：**346/3/0**（基线 300/3/0 + 46 新 = 9+21+8+8）
  - Library：**598/4/0**（基线 592/4/0 + 6 新）
- **APP 侧 sidecar 先例套件定向复跑**（v9 bump 回归面）：SidecarV5 / V7 / V8 /
  DrtSidecar / DrtPersistence 全绿（v8 字节形 pin 与动态 digit 替换机制在
  schemaVersionCurrent=9 下自洽）。
- **全套推算**：3029 + 52 新 = **3081/16/0**（+Δ52）；未跑全套 `--all`
  （批准制未申请，派发指令限定定向 bundle；验收/收口轮可按需申请全套）。
- func test 计数对账：46 LAYERS 文件法 + 6 LIB = 52；Executed 增量逐位一致。

## 四、「光谱不可达边界」架构注记（plan 头转述，交付语义）

本批消费面 = `density_curves`/`log_exposure`（256×3 密度域，RESEARCH §1.5
同构发现）+ `base_density` **仅经** E2 登记三点标定投影（650/550/450nm 最近
邻）为 RGB 常数 + `wavelengths` 仅作 λ 轴校验与投影采样轴。81 波长光谱
**重放**零消费、随文件原样保留（机制 = 消费键 Codable + re-encode 键集
测试钉死）；用户可见措辞 =「物理流程建模，非光谱重放」（M3-2 D-M3-2-2）。
m3 密度域口径按实盘细化：求解输入对 = status_M 负片 × status_A 相纸
（2383/2393 print 库存例外见 DECISIONS D-3b）。

## 五、求解器 sanity（汇报面摘要；正本 = DECISIONS §5）

- 模型 = 印相 exposure 反演（x = −f + gain）+ 双 dial 常数 s_m=0.0085 /
  s_y=0.017（2:1 dichroic 比例）——plan 方程的两处 Float64 具体化，标定依据
  与「单常数不可行」的数值证据在 DECISIONS D-5a。
- 两具名组合解值（Float32 存储路径精确值）：portra×endura 57.9322/49.2372，
  ektar×ultra 63.1549/59.1051——全落表值 ±10 CC。
- 错误向量 `k_m·[0,1,1]` 判别：Y 解出带 −29.0/−31.6 CC，M 解不变（构造性）；
  带宽未放宽（无上报条件触发）。
- 确定性：双调用 bit-identical + 跨加载一致 + 单调括号自检 + 常量族在册。

## 六、偏差与发现（全部已处置，无阻塞）

1. **资产数据嵌套结构**（D-3a）：`data` 对象嵌套——类型面平铺、Codable
   nestedContainer 投影；资产零触碰。
2. **densitometer 实盘矩阵**（D-3b）：2383/2393 print 库存 = status_A 例外；
   测试按实盘断言，M3-3-02 细读挂账。
3. **film/paper 分型实盘 22/6**（plan 预估「20+8 量级」）——按「执行期以
   实盘为准写死」条款录入测试。
4. **LICENSE 采用上游钦定形式**（D-2）：SPEKTRAFILM_LICENSE.txt 逐字节
   （含官方全文）——比裸 creativecommons 文本更合规，NOTICE 交叉引用。
5. **求解器模型具体化**（D-5a）：印相输入反演 + 双 dial 常数——plan 方程的
   必要 Float64 具体化，预标定证伪/离散域计算在案，DECISIONS 正本登记。
6. **currentValue 语义**：document-scope item 的 placeholder 会出现在
   `currentValue`（裸顶层访问器，DRT 同款行为）——测试按 `effectiveInstances()`
   断言排除面（首版误断言已修）。
7. **front-matter 勘误**：HistoryHash 折叠实体在 HistoryStack.swift（M2-6-3
   PLACEMENT NOTE 钦定），HistoryHash.swift 零 diff——见 §七。

## 七、front-matter files_modified 申报勘误（M3-1-03 obs-1 同款纪律）

实际触面 = front-matter 清单 ∪ 以下勘误：
- `HistoryHash.swift` **未触碰**（折叠函数实体在 HistoryStack.swift 尾部
  extension——M2-6-3 PLACEMENT NOTE 的钦定位置；front-matter 所列路径不准）。
- `LightamerSidecar.swift` 的 diff 含 `SidecarHistoryItemRecord` 条目级镜像
  与 `driftDetected` 喂入行（KD-6 additive 面的机械必然，非扩面）。

密封面机检：`git diff --name-only c8ddc57..HEAD` 对 TerminalTailPolicy /
DrtTailAssembly / PixelPipe.swift / DrtEotf.swift / Lut3dKernels.metal /
LutEncodingCatalog / V50Order / ModuleRegistry / defaultFaceDisabledOpNames
**零命中**；`LightamerSidecar.swift` 删除行仅 4（= additive 缝上的被修改行，
§六.7）。`Resources/LUTs/` 零命中。

## 八、续接点增量（正本回写 GOAL-STATE）

M3-3-01 六任务闭环 + docs 批 = 本文件；**下一步 = M3-3-02**（film sub-run
渲染面 + filmPlacement grade op + coordinator/App 接线 + carrier/写腿/恢复腿
——写侧须 film item + 文档字段成对写入以保锚一致）。M3-3-02 移交清单 =
DECISIONS §7 五条（串扰回填义务 / 2383-2393 归属 / 统计分量缓存键 /
PresetNames 填充 / 成对写入）。
