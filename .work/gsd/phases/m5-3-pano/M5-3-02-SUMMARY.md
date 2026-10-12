# M5-3-02 SUMMARY — 全景生产腿批（wave 2）

> 执行批 2026-10-13（夜间全自动授权「开跑，不要停」在案）。六任务六
> 提交收口。规格 = M5-3-02-PLAN.md（checker 5 minor 同批采纳）；偏差
> /定夺/探针定案正本 = M5-3-02-DECISIONS.md（§1-§6）；预算探针出数
> 正本 = perf.md。

## 任务序与提交

| 任务 | 产物 | commit |
|---|---|---|
| T1 | PanoWarp.swift（sphericalMap 直译/projectToCanvas 前向/boundedCanvas 收缩循环/200MP 帽/typed）+ PanoWarpTests 8 法 | `ba2b2cc` |
| T2 | PanoGain.swift（≤900px 采样画布/逐带 span 读/中位 log 方程/锚 10/dgelsd 最小范数/clip±0.5）+ PanoGainTests 13 法 | `1daad17` |
| T3 | PanoCrop.swift（min-pool ≤1024 格/直方图栈/naive O(N²M²) 参照/typed）+ PanoCropTests 10 法 | `b6332ba` |
| T4 | runPanoLeg 换腿体 + StagedSet.readRows(+into 变体) + FloatTIFFWriter（手写 strip TIFF）+ landStackProduct rowProvider 臂 + PanoLegTests 8 法 + 01 stub 测试退役 | `fa10355` |
| T5 | PanoFusionPerfProbeTests 2 法（主探针 + footprint 诊断三臂）+ band-union span 读产线修复 + syncForDiagnostics 钩子 + perf.md | `613c8ad` |
| T6 | G3② 补靶 2 法（羽化带表/权重归一，`940a658`）+ 收口轮 + 红线自证 + 本批文档（本提交） | 本提交 |

## 收口轮数字（定向双 bundle，2026-10-13）

| bundle | 本轮 | 基线增量 | MEMFAIL | peakRSS |
|---|---|---|---|---|
| IOP | **682/1/0**（450s） | 642 → +41（Warp 8/Gain 13/Crop 10/Leg 10）−1（stub 退役） | 0 | 7800MB |
| Export | **353/4/0**（202s） | 351 → +2（PerfProbe 主+诊断） | 0 | 7021MB |

- **对账**：3582（M5-3-01 后拼表）+ 41（本批净增）= **3623**；定向双
  bundle 拼表口径 pass 3623 / skip **22+2 = 24**（探针两法 env 门，O3
  估 +1 修正为 +2——DECISIONS §6.6）/ fail 0。估数 +30..40 净增 ✓
  （41 减 stub 退役 1 = 40 法上沿）。
- 贴线注记：IOP 7800MB（贴线族 ±3% 方差口径，零 MEMFAIL）；Export
  7021MB（探针轮 RSS 3.8GB 远低于 8G 门）。

## G3 五靶全覆盖清单（KD-11 交叉复核）

| 靶 | 落点 | 状态 |
|---|---|---|
| G3① sphericalMap vs 闭式解逐点 | PanoWarpTests（独立重算参照，12288 点 worst 2.44e-4 px，带 ≤1e-3 钉）| ✓ |
| G3② 羽化带 12% 短边 + 权重归一 | PanoLegTests（带表点列 + 双恒色源端到端 α 加权均值 + valid=weight>0 行对行）| ✓（T6 补靶）|
| G3③ gain 合成方程组恢复 | PanoGainTests（恢复带 1e-6、门值正反、锚定、clip 双侧、不连通恒等、双跑逐位）| ✓ |
| G3④ 直方图栈 vs naive 逐位 | PanoCropTests（L 形/双岛/满格/单行/缺口带逐位 + 全无效 typed + 随机网格面积一致）| ✓ |
| G3⑤ boundedRois 不变式 | PanoWarpTests（帽/收缩轮/ROI 非空/并集=界/typed）| ✓ |
| G1 腿级闭环（全链双跑逐位） | PanoLegTests.testDoubleRunProductsBitIdentical（产物字节含落盘）| ✓ |

## 生产腿证据（T4/T5 申报面）

- **双 pass 几何/融合分离**：pass1 = `panoValidMask` 纯几何（0
  staged 读，UInt8 1B/px）+ PanoCrop；pass2 = `panoFuseRows` 逐带。
  valid=weight>0 纯几何量依据落 DECISIONS §4；G3② valid=weight>0
  行对行亲证。
- **band×源联合 span 读**（探针事故产线修复）：读体量 84× 降，
  footprint 爬升 +2.5GB/band → +242MB/band；位值不受影响（PanoLegTests
  逐位 + 双跑 bit-identity 复验）。
- **rowProvider additive nil 零漂移**：既有六 kind 全部经
  `landStackProduct` nil 臂（rowProvider 缺省 nil）——IOP 全轮 682/1/0
  即零漂移证人（含 MertensLegTests 14 法/StackMergeServiceTests 11 法/
  PanoMergeKindTests 7 法逐类亲跑）；`writeFloatTIFF` 零 diff
  （BandStreamer diff 仅头注）+ `MertensRasterDomainTests` 默认参数
  零漂移负测保持绿。
- **200MP×8 预算探针**：196MP 画布，几何 183.8s / 增益 1.07s /
  融合+流写 895.4s（0.2 MPx/s）/ 产物 3.1GB / **ru_maxrss 3814MB（8G
  门内零 MEMFAIL）**——CPU 预算未被证伪，无 GPU 化触发（NO GATE，
  决策面保持关闭）。三连杀定位链与产线修复 = DECISIONS §5 + perf.md。
- **产物面**：`_pano` 分账名 + sRGB-tagged 32f strip TIFF（REAL
  raster 重导入 resolve .srgbPiecewise/.displayReferred/ICC hash 在册
  —— PanoLegTests 走 RAWDecoder 真链）+ alpha 恒 1 + provenance
  快照三字段（panoCanvas/panoGains/panoCrop）+ alignment 标签
  （reference / inliers=<n> 确定性字符串）。

## 零 diff 红线自证（T6 收口轮实测，基 = f5b56b7）

```
git diff f5b56b7..HEAD -- LightamerIOP/ LightamerCore/Sources/Sidecar/
  LightamerCore/Sources/Export/ LightamerCore/Sources/Graph/ '*.metal'
  → 0 行
git diff f5b56b7..HEAD -- '*ExifPrecheck.swift'                → 0 行
leg 体（runHDRLeg/runMertensLeg/runFocusStackLeg/runStackAggregateLeg）
  → 函数体零 diff（diff 中唯一命中 = landStackProduct 头注注释行）
dependencies 块 → 0 diff（Project.swift diff = 5 行测试登记）
grep -rnE "SystemRandomNumberGenerator|srand|arc4random|\.random\("
  Pano*.swift（源+测）→ 0 命中
sidecar schemaVersion → 零触（Sidecar/ 零 diff）
runModal 门（App/Sources .runModal()）→ 本批零 App 文件触碰
```

既有六 kind 零回归：IOP 全轮 682/1/0（含 HDRMergeMath/MTBAlign/
FocusStack/Mertens 全族）+ Export 353/4/0（Robertson/Mertens/导出矩阵
全族）。

## bundle 分账（BUNDLE-MAP 增行随各自任务 commit）

PanoWarpTests/PanoGainTests/PanoCropTests/PanoLegTests → IOP；
PanoFusionPerfProbeTests → EXPORT（Mertens 探针同位；IOP 贴线族不叠
GB 级探针——同 M5-2-02 rationale）。

## files_modified 外申报（最小必要）

- `Tests/LightamerTests/PanoMergeKindTests.swift`（T4）：01 stub 测试
  退役 + MARK 注记（腿体替换连带，M5-2-02 先例）。
- `Tests/LightamerTests/MertensLegTests.swift` 等既有测试 = 零修改
  （nil rowProvider 零漂移证人，未触）。

## 偏差与发现（DECISIONS §1-§6 详）

1. 基线链「+32 正本」= 派发注记转写残迹，plan 文本零命中——§1 申报
   吸收，不重开基线。
2. 增益求解 = dgelsd 最小范数（checker O2，非等价自由度）。
3. FloatTIFFWriter = 手写 strip TIFF（minor-3 容器策略定夺）。
4. 预算探针三连杀 → band×源联合 span 读产线修复（读体量 84× 降）；
   探针源钉 8×28MP；skip 增量 +2（O3 修正）。
5. 腿级超帽 canvas-invalid 降级单元级（200MP 帽测试尺度数学不可达
   —— shrink 单轮必收敛）；8 轮不达臂保留（Lumen parity）。
6. fixture 纹理 = 编码域作者 + srgbDecode 还原（raw 域作者 encode 后
   对比破门的探针链）；medianFocal 2× 初值观察项（BA 收敛不设门）。

## 验收与续接

- **双重验收待派**（config `dual_acceptance = true`，m1）：本批执行完
  成，待 orchestrator 派 zcode 独立验收（PASS 后串行 omp 二验，严禁
  并发），结论落 `M5-3-02-ACCEPTANCE.md`（本批未创建——验收波产物）。
- **C 档第 2 停**：执行+验收闭环后停——汇报本 plan 战果（含探针数值
  196MP/895s/3814MB）+ M5-3-03 摘要，等用户确认再启。
- M5-3-03（UI 与收口：菜单第三项 + 简形 sheet + zh 八键 + typed 报错
  面 + G4 OpenCV 对照 + G5 红线机检 + G6 MANIFEST）待启；M5-4
  VALIDATION 兼「全史瘦身手术」第二次随后。
