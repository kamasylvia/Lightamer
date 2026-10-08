# M3-3-01-ACCEPTANCE — FSIM 数据模型与资产批（wave 1）独立验收

> **结论头：PASS / 0 error + 0 minor**（观察项 2 条，均非本批引入、不阻塞）。
> 验收：2026-10-08/09 夜间独立验收 subagent（零共享上下文，实测核验不轻信；
> 夜间全自动授权在案）。验收对象 = `22e14c8..301f933` 七提交（基线 `c8ddc57`）。
> 验收方式：定向亲跑 + shasum/diff 亲算 + 独立数学复算（uv/Python 按处方独立
> 实现，非复制 Swift 代码）+ 全部新增源/测试文件读码。未 push。

## 一、定向亲跑数字（对表）

| 轮次 | 结果 | 申报 | 判定 |
|---|---|---|---|
| Layers 全量（test-direct.sh 直启） | **346/3/0**，peakRSS 756MB，25s | 346/3/0 | ✅ 逐位一致 |
| Library 全量 | **598/4/0**，peakRSS 612MB，79s | 598/4/0 | ✅ 逐位一致 |
| sidecar 先例回归（v9 bump 面，App bundle 定向） | V5 11/0/0、V7 8/0/0、V8 5/0/0、DrtSidecar 7/0/0、DrtPersistence 7/0/0 | SUMMARY「全绿」 | ✅ 全绿 |
| 构建 | `xcodebuild build-for-testing` RC=0（caffeinate 包裹） | — | ✅ |

- 数字对账链亲核：新方法 52 = LAYERS 46（FilmRecord 9 + FilmProfile 21 + Solver 8
  + FilmHistory 8）+ LIB 6（FilmSidecar）；`grep -c "func test"` 逐文件 = 地图
  逐行 = Executed 增量（LAYERS 执行 346 = 地图总和 345 + DrtEotfTests 预存
  +1，见观察项①）；全套推算 3029 + 52 = 3081 算术自洽（`--all` 未跑，批准制
  未申请，与派发指令限定一致）。
- 登记闭环（E2/L041）三方对表亲核：BUNDLE-MAP 五行增记 × Project.swift 测试
  登记（479-482 LAYERS / 566 LIB）× 测试文件 `func test` 计数一致；
  `Resources/FilmProfiles` folderReference 在 App target（:187）；生成工程
  pbxproj 含全部新登记且 mtime（Oct 8 20:02）先于 T6 提交（20:11）——
  build→test→commit 序自洽。

## 二、资产合规（CC BY-SA 红线）

- **MANIFEST 全量对账亲算**：`shasum -a 256 -c MANIFEST.sha256` = **30/30 OK、
  0 失败**（28 profile + neutral_print_filters.json + LICENSE）；测试内全量
  re-hash + 逆向孤儿覆盖断言（testManifestReconcilesEveryListedFileByteForByte /
  testManifestCoversTheWholeAssetTree）在案。
- **来源仓字节一致性亲算**：`Resources/FilmProfiles/profiles/*.json` 与
  SpektraLab `engine/resources/profiles/` shasum 清单 diff 零输出；
  `neutral_print_filters.json` cmp 零输出；`LICENSE` 与上游
  `license/SPEKTRAFILM_LICENSE.txt` diff 零输出（D-2「上游钦定形式逐字节」
  亲证——该文件含 CC BY-SA 4.0 官方法律全文，grep 计 12 处 Creative Commons）。
- **五件套齐备**：①隔离目录 `Resources/FilmProfiles/`（与 `Resources/LUTs/`
  物理分离；**LUTs 目录本批 diff 零命中亲证**，末次触碰 = M2-5-3 `509eb56`）
  ②LICENSE ③NOTICE（Andrea Volpato / spektrafilm 署名 + citation 全文转录 +
  版本 0.3.2 + 原样副本声明 + 密度域消费披露/非光谱重放边界 + SA 隔离声明）
  ④MANIFEST.sha256（30 行）⑤CHANGELOG.md（0.3.2 snapshot 引入记录）。28/28
  profile `metadata.version` = 0.3.2 亲核一致。
- **字节原样申报亲证**：`git log -- Resources/FilmProfiles` = 仅 T2 `04b2909`
  单提交，其后零改动。
- **GPL 零复制**：四个新 Swift 源文件（FilmRecord/FilmProfile/FilmMaterialStore/
  FilmFilterPackSolver）逐文件读码 = 自研 schema/数学实现，头注「schema facts
  only / math only」与实际相符；SpektraLab 代码/脚本零进入。
- **光谱重放零消费（机制亲证）**：FilmProfile 类型面只含消费键（Codable
  nestedContainer 投影 `data` 节，D-3a）；testReencodingEmitsOnlyTheConsumerKeys
  机械钉死 re-encode 输出 = `{metadata, info, data}` 三节 + data 四键，光谱
  payload（log_sensitivity/channel_density/layers 等）不可能回漏类型面；
  base_density 仅经 baseDensityProjection（650/550/450nm 最近邻）入 RGB 常数，
  wavelengths 仅作轴校验与采样轴。

## 三、数学审计（独立复算）

独立实现（/tmp 一次性脚本，uv/numpy，Float32 存储拓宽 Float64 同口径）按
DECISIONS D-5a 处方重解：

| 断言面 | 亲算值 | 申报值 | 判定 |
|---|---|---|---|
| baseDensityProjection（portra_400, E2 三点） | 0.1945546 / 0.6023984 / 0.8150475 | 同 | ✅ 逐位吻合 |
| midGrayDensities（portra_400） | 0.489136888 / 0.947016837 / 1.272824936 | 同（测试钉死） | ✅ |
| portra_400 × portra_endura 解 (M0, Y0) | 57.9322 / 49.2372 | 57.9322 / 49.2372 | ✅ 精确吻合 |
| —— 表值（TH-KG3 实表亲提） | 51.56801468 / 52.53400422 | 51.568 / 52.534 | ✅ 偏差 +6.36/−3.30，±10 带内 |
| ektar_100 × ultra_endura 解 (M0, Y0) | 63.1549 / 59.1051 | 63.1549 / 59.1051 | ✅ 精确吻合 |
| —— 表值（实表亲提） | 71.21744660 / 55.58437667 | 71.217 / 55.584 | ✅ 偏差 −8.06/+3.52，带内 |
| 错误向量 `k_m·[0,1,1]` 判别 | M 不变；Y = 20.2711 / 27.5277（移出带 −29.0/−31.6 CC） | 20.27 / 27.53（−29/−31.6） | ✅ 出带判别成立 |
| 确定性 | 双调用精确相等（Float64 路径） | bit-identical | ✅ |

- 表值出处亲证：`neutral_print_filters.json` 结构 = paper → `TH-KG3` → film →
  `[C,M,Y]`；两具名组合实表提取与申报一致且 **C=0.0 确证**（160 组合 C 恒 0
  亦由测试全量断言）。E3 修正向量（M=[0,1,0] 只吸绿）在求解器源与测试双侧
  落实；错误向量判别面（solveNeutralPackWrongMagentaVector）+ 双断言（M 不变
  + Y 出带）在案——判别力 ≥22 CC，带宽未放宽。
- 求解器读码：顺序两步 1-D 有界二分、固定 60 迭代 + 1e-12 epsilon 常量、
  无初值无随机、R 锚构造、单调括号前提自检（paperOutputs 内面）——与 KD-5
  处方逐条相符；`Float32 精确拓宽再算术`注释与实现在案。
- 偏差五条核实：D-3a（data 嵌套投影，资产零触碰）✅；D-3b（densitometer
  实盘矩阵：paper 6/6 status_A、positive 4/4 status_A、negative status_M 唯
  2383/2393 例外——testDensitometerDomainsAcrossTheVendoredSet 全集机检）✅；
  film/paper 22/6 实盘写死（plan「执行期以实盘为准」条款授权）✅；两处
  Float64 具体化（exposure 反演 + 双 dial 常数，DECISIONS §5 正本登记，单常数
  不可行论证在案）✅；HistoryHash 实体在 HistoryStack.swift（**HistoryHash.swift
  本批 diff = 0 行亲证**，折叠实体在 HistoryStack 尾部 extension = M2-6-3
  PLACEMENT NOTE 钦定位）✅——front-matter 勘误成立。

## 四、hash 零漂移红线（读码）

- **sidecar v8 字节零漂移负测**（FilmSidecarTests
  testV8FormDocumentDecodesAndReencodesByteExact）：v8 字节经 v9 reader
  decode → canonical re-encode **byte-exact 断言**在案；`filmRecord` 键缺席
  断言（encodeIfPresent）+「nil 面 v9 输出与 v8 形仅差 schemaVersion 一位」
  双向断言在案。机制侧：LightamerSidecar.swift 本批删除行仅 4（= additive
  缝上的被修改行），v9 面 decodeIfPresent/encodeIfPresent 与 v6/v7/v8 先例同构。
- **HistoryHash 尾位折叠**（FilmHistoryTests）：
  - testFoldWithoutFilmItemsIsBitIdenticalToThePreV9Formula——无 film 档
    `filmRecord: nil` 折叠 ≡ pre-v9 4 参式逐位（负测）；
  - testFilmTermFoldsAfterTheDrtTerm——折叠序 film 排 drt 后，独立重推式 +
    反序不等双断言；
  - 默认参 `filmRecord: FilmRecord? = nil`——既有调用点零改动（3 参/4 参式
    仍在用 = 编译级证明）；sidecar driftDetected 双投影喂入
    （effectiveDrtRecord + effectiveFilmRecord，读侧 history 自投影）+
    正反双 tamper 测试（item tamper 翻真 / field-only tamper 不翻）在案。
- FilmRecord ≡ DrtRecord 同构抽查：tolerant decode（decodeIfPresent + init
  默认逐字段）、stableHash（sortedKeys canonical JSON FNV-1a，独立公式复算
  测试）、isFilmRecordDefault pristine 单源、PresetNames 空占位（D-1 授权）
  ——同构申报成立。

## 五、密封面与边界机检

- `git diff --name-only c8ddc57..HEAD` 对 TerminalTailPolicy / DrtTailAssembly
  / PixelPipe.swift / DrtEotf.swift / Lut3dKernels.metal / LutEncodingCatalog /
  V50Order / ModuleRegistry / defaultFaceDisabledOpNames / HistoryHash.swift /
  Resources/LUTs——**零命中亲跑**。
- 七提交边界逐一对照 front-matter：T1 `22e14c8`（FilmRecord+9 测+登记）/
  T2 `04b2909`（36 文件=29 资产+四文书+MANIFEST+测试 229 行）/
  T3 `1ea9264`（loader+11 测）/ T4 `72b7222`（store+5 测）/ T5 `0a48b55`
  （solver+8 测）/ T6 `dc82dc0`（sidecar+HistoryStack+LIB 6+LAYERS 8）/
  T7 `301f933`（docs 四件）——与申报一致；commit message 全英文 Conventional
  Commits。GOAL-STATE/TODO 收口条目在案（`301f933`）。

## 六、观察项（非阻塞，不记 error/minor）

1. **BUNDLE-MAP 预存计数漂移**：DrtEotfTests map=12 vs 实际 13（SidecarV5Tests
   map=10 vs 实际 11、DrtSidecarTests map=8 vs 实际 7 同类）——三文件本批
   **零 diff**（密封面机检佐证），为既有登记陈旧，非本批引入；本次对账以
   文件实数为准（Executed 与文件实数逐位一致）。留待下次触碰对应文件时
   顺手勘误即可。
2. **`--all` 全套未跑**：推算 3081/16/0 系算术推算（+52 全部经定向轮 Executed
   增量逐位确认）；派发指令限定定向 bundle，批准制未申请——合规，但推算值
   在 M3-3-02 前任何全套轮（含验收）应实测校正。

## 七、裁决遗留上报（orchestrator 项，非本 plan 执行面）

plan 头 checker 回注呈报两条（M3-2 裁⑥ spike 验收形态未满足前 M3-2 翻账
问题 + 台账滞后）经核：M3-2 侧已于 `c8ddc57` 补批结案（perf.md §O-1 SPIKE +
证据包 + ROADMAP/STATE/TODO 翻账同批）——**该呈报已被基线批处置完毕，无
遗留**。本验收无新增上报事项。
