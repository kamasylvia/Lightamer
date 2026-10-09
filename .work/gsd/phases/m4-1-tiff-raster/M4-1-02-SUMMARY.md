# M4-1-02-SUMMARY — TIFF 开发链切换与收口批(wave 2:路由翻转 → 编辑/导入面 → SC 收口)

> 执行 = ZCode subagent worker(夜间全自动授权「开跑,不要停」在案)。
> 起点 = `1220581` 后 HEAD;基线 = 3174/16/0。本批 commit:
> `1b2b520`(T1+T2 合并)→ `db7f7dc`(T3)→ `ad9f7dc`(T4)→
> `a565f1e`(T5)→ `5790526`(T6)→ `ef0183c`(T7)→ 本 T8 docs。
> 双重验收(config `dual_acceptance = true`)= orchestrator 编排:zcode 独立
> 验收 PASS 后串行 omp 二次验收,结论落 `M4-1-02-ACCEPTANCE.md`;**VALIDATION
> 仅在双验收 PASS 后成文**(m1 工序)。不 push。

## 任务逐条(commit SHA)

| 任务 | 交付 | commit |
|---|---|---|
| T1 | decode() UTI 分流翻转(RAW → **TIFF**(`isTIFFUTI` = public.tiff conform)→ 其余 raster);decodeRaster 退役保留 + 头注;BandStreamer 头注刷新;路由 golden 翻转(native leg + 退役臂快照);RasterRoutingTests 12(tiff→新腿 / lut-icc→CI 臂 / jpeg·png·heic 零回退 / 族谓词 / CMYK typed 拒 / multipage / E1 回流 / 折叠键×2 / 管分派) | `1b2b520` |
| T2 | PixelPipe.renderInputPlane 分派(`rasterColor != nil` 键,三 return 之前)+ renderRasterInputPlane 两子形(原生字节 = negotiation-window payload + Stage;iccLutConverted = CI 转换平面 → runDisplayInverse 逆腿 TRC 恒等);RasterDecoder.windowedPayload(top-first + LE 字节序 + box 平均 ≤1px);inputPlaneDedupeKey 描述指纹显式折叠(nil = 旧两元折叠逐字节);Tier A fallback 钉测;**NeutralTarget 容器 TIFF→PNG 无损转换**(像素恒等,~10 套件留在 CI 臂);omp-minor-1 五处字面订正 + BUNDLE-MAP 勘误(omp-obs-1/-2) | `1b2b520` |
| T3 | WorkspaceModel.seedRasterDrtRecord 三支(②非 raster 零动作 / ①restore·幂等先 / ③carrier-only derive,method aces20 恒非默认故 carrier 必持有)+ PipeCoordinator.load 单调用点 + syncDrtCarrierWithHistory 的 raster「DRT 恒在」臂(undo 到顶**替换 stale carrier 重铺 derive**,与 RAW 的显式偏离)+ EditorState mint skip + RawDecodePanelView 门控(三节隐藏)与输入色 readout 四行(V14 静态键);RasterEditFaceTests 7;xcstrings +25 键尾块纯插入 | `db7f7dc` |
| T4 | RasterHdrViewportTests 5(PQ/HLG fixture → derive(rec2020,st2084/hlg)→ 16F+EDR+itur_2100_PQ/HLG 视口臂;peak 贯通 1000/4000;ExportVariant.validate 峰值门零扰动;followGate 互斥)。**零新渲染代码**(M2-6 交付面) | `ad9f7dc` |
| T5 | ImportCategory OptionSet + `library.import.categories`(缺键/域外 = 双开;reset 同族)+ ImportFilter ③ 类别掩码改写(①②不动;tif 硬编码族不入 rawExtensions)+ Reason.excludedType + ImportProgress.excludedType 分账 + ImportModeDialog 类型选择器(checkbox×2 + 不可勾其他计数 + 扫描完成&&允许数>0 门 + 选择即写)+ recursiveFiles 升 public(App 侧模块限定规避 Session 域同名枚举)+ runImport 传掩码;ImportCategoryTests 16 + ImportCategorySelectorTests 5;翻转 AC 恰一处(ImportFilterTests :79-87 原位改名)+ C1 fixture 契约钉 categories .raw + excludedType 分账 | `a565f1e` |
| T6 | ImportTransportTiffTests 4(真 fixture 字节 move/copy/link + .lra 随行 + 重复跳过 + link 外部替换 → 描述重解析[p3d65 limiting 替换 sRGB] + contentDedupeID 翻新) | `5790526` |
| T7 | RasterRoundTripTests 3(SC#1 抽样矩阵经真队列:drd 恒装配 + 三行编码对 + γ u8Fixed8 邻域 + HDR 行 LUT 臂面;inverse→forward 带 8e-3;D-H1 生产提交面编辑重放像素稳定) | `ef0183c` |
| T8 | 本文件 + DECISIONS + GOAL-STATE + TODO + AGENTS 增量节 | 本 commit |

## 测试数字 vs 基线

- 新增测试文件 7:RasterRoutingTests 12(IOP)/ RasterEditFaceTests 7(APP)/
  RasterHdrViewportTests 5(APP)/ ImportCategoryTests 16(LIB)/
  ImportCategorySelectorTests 5(APP)/ ImportTransportTiffTests 4(LIB)/
  RasterRoundTripTests 3(EXPORT)= 52;既有文件净增 +7(RasterDecodeLegTests
  13→19[routing −1+2、windowed +5]、LibraryThumbnailBridgeTests +1)=
  **+59**(plan 估 +40..46,超出声明);对账基线 = 3276(3174+01 的 +102)→
  **3335**。
- **全套 `--all` 终验轮**(本批亲跑,见 DECISIONS §9):TOTAL **3335/16/0**
  (1604s,exit 0;对账链 3174 + 102[01] + 59[02] 逐 bundle 两式互证),
  零 MEMFAIL,IOPParity 峰值 8104MB < 8192 门,L055 双保险亲核。
- zh-audit `--check` PASS **1610 source / 1848 catalog**(+25 键)。

## 红线自证(`git diff 1220581..HEAD`)

- `Aces2Kernels.metal` / `LightamerIOP/` / `Sidecar/` / `Pipe/History/` /
  `Graph/DrtRecord.swift` **全零 diff**(机检在案)。
- `decode()` 分派翻转 = RAWDecoder 单文件 17 行;decodeRaster 本体零改
  (退役保留,退役臂快照测试钉住)。
- sidecar/`.lalb` 零 schema 变更;六格式导出矩阵零改动;IOP/IOPParity 逐位
  基线 = IOP 562/1/0 + IOPParity 427/3/0 全绿(**E1 自洽终证:torture 源
  :92-95 与 merge 产品 :800 经新腿 sceneLinear 矩阵支,基线零漂移**)。
- RAW 文档渲染零变化(分派键 = rasterColor,RAW/CI-raster 路径不触);
  JPEG/PNG/HEIC 零回退(RasterRoutingTests 逐 UTI 机检锚)。

## 申报外扩面(front-matter 之外的实触文件)

1. `LightamerCore/Sources/Pipe/Input/RasterInputStage.swift` — runDisplayInverse
   入口 + cacheKey 几何重载(LUT-ICC 子形必需;plan 简写 `makePlane` 的兑现形)。
2. `LightamerCore/Sources/Stack/BandStreamer.swift` — 纯头注措辞刷新(plan T1 注记)。
3. `Resources/TestFixtures/NeutralTarget.{tif→png}` + `Tests/Fixtures.swift` —
   fixture 换容器(E2 普查处置,见 DECISIONS §2)。
4. `LightamerCore/Sources/Decode/RasterColorDescription.swift` +
   `RasterColorDescriptionTests` + `RasterIccSemanticsTests` +
   `RESEARCH-NOTES.md` — omp-minor-1 字面订正(②默认 = Rec.2020)。
5. `Tests/LightamerTests/ImportServiceTests.swift` — C1 契约的类别面注册(T5 钦定)。
6. `Tests/LightamerTests/LibraryThumbnailBridgeTests.swift` — Tier A fallback 钉测(T2 钦定)。
7. `LightamerCore/Sources/Library/ImportService.swift` recursiveFiles private→public
   (选择器复用唯一扫描面;App 侧 `ImportService` Session 域同名枚举需模块限定)。
8. Project.swift / BUNDLE-MAP 注册与勘误(E2/L041 纪律);xcstrings +25 键。

## 转接 M4-2(续接点详见 GOAL-STATE)

- M4-1 双重验收(orchestrator:zcode → 串行 omp)→ VALIDATION 成文 → C 档签核。
- 遗留观察项:深影饱和中性化(01 §4)随 gui-acceptance 走查;HDR TIFF 重导入
  LUT 臂面(DECISIONS §6);CMYK/16-bit gray typed 拒现在**在 open 时上浮**
  decode 错误 alert(翻转前静默走 CI——行为变化,DECISIONS §7)。
