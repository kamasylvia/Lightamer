# LENS-01 DECISIONS — plan L1 裁定记录

> 正本 = CONTEXT.md(D-LENS-1..8 / X1..X4);本文件只记执行期裁定与偏差申报。

## D-L1-1 decodeParamsHash 覆盖面核验结论(T1,X2 边界)= **已覆盖**

`RAWTechnicalOverrides` 全部 setter legs 落 `RAWTechnicalParams`,`HistoryHash.decodeParamsHash`(HistoryHash.swift:148-175)逐字段显式折叠:

| override | rawTech 载体 | 折叠面 |
|---|---|---|
| noiseReductionAmount | noiseReductionAmount | 恒折 |
| luminanceNoiseReduction | optional | 设才折 |
| colorNoiseReduction | optional | 设才折 |
| sharpness | sharpnessAmount(optional) | 设才折 |
| boost | optional | 设才折 |
| decoderVersion | decoderVersionUsed.rawValue | 恒折(渲染真相——request 与结果同 v8 时语义等价,折结果正确) |

结论:**v1.x 的 `vendorLensCorrection` override 落地时按 L013 规则扩字段列表即可**(optional nil 不折,旧档 hash 零漂移),本批零改。证据行号:RAWDecoder.swift:36-60(overrides struct)/ HistoryHash.swift:148-175。

## D-L1-2 ImageIO 写侧丢弃 0xA405(T1 fixture 形态)

CGImageDestination 对 TIFF/JPEG 的 EXIF dict 写入**不序列化** `FocalLenIn35mmFilm`(0xA405;2026-10-21 探针实证,LensMake/LensModel/FocalLength 正常)。ExifLensFieldsTests 的 fixture 改为**手织最小 TIFF 字节**(II 头 + IFD0 十 entry + Exif IFD 0xA405/0xA433/0xA434 + 4×4 RGB8 strip),ImageIO 读侧正常拾取。该织器骨架供 T2 探针测试复用。无产线影响(读侧行为既有且被钉住)。

## D-L1-3 T2 构造点拓扑(review M6 执行形)

plan 预写行号 `:236/:358/:121/:138`,实际提交后 = `RAWDecoder.swift:236/:361`(T2 自身插入 isDNGUTI helper 使 decodeRaster 构造点 +3)+ `RasterDecoder.swift:121/:139`(embeddedGeometry 注释行 +1)。「各腿恰一处」按实际拓扑兑现:RAW 腿一处条件分支(`isDNGUTI(uti) && probe → .detected`,否则 `.unknown`,含 DNG 无 tag 桶);退役 decodeRaster 与 RasterDecoder 两腿恒 `.notApplicable`。

**DNG 无 opcode tag 落 `.unknown` 非 `.notApplicable`/`.detected`**:plan 措辞「任一 tag 存在 = detected;非 DNG = unknown」未明 DNG-without-tag 桶——执行取 unknown(缺席 tag 不能证明无校正,与 X1 保守语义一致;风险节「探针假阳性保守方向无害」同理)。

## D-L1-4 探针入口双缝(review m10)

`probe(url:)`(FileHandle seek 式有界读,产线面)+ `probe(data:)`(窗口语义:引用越窗 = 缺席 = false → 调用方落 unknown 安全向)。walk 深度帽 1(IFD0→SubIFD),entry 帽 4096,SubIFD 数帽 8;opcode payload 零读取(存在性语义)。

## D-L1-5 阈值常量与 `?? 1.0` 兜底分布(T3)

`autoApplyThreshold = 60` 恰一处声明(LensfunMatch.swift:111)。`params.imageCrop ?? 1.0` 兜底出现两处——`matchCommitted`(match gate 输入面)与 `resolveCommitted`(resolve crop/NS·HW 折算面)——同一 X4 优先链穷尽后的兜底语义在两个消费点的投影,非双真相(链源头 = reloadDefaults 单点 bake)。plan grep「恰一处」按「兜底语义单源」兑现,特此申报。

## D-L1-6 歧义判定语义(T3)

同分多候选 = **不同 entry 同最高分**;同 entry 多 model 变体(model 数组)不算歧义(lensfun 单 entry 多语言/别名变体)。40 分档无同分拒绝面(40 本身已被阈值摘除,歧义判定只作用于 ≥60 段)。

## D-L1-7 LensMatchOutcome public 形态(T5 App 可达面)

App 面板消费 outcome → `LensMatchedProfile`(public:maker/model/cropFactor + internal entryIndex)替代 LensEntry 关联值(App 不可见 internal LensEntry)。resolveCommitted 经 internal index 在同一 stamp 内回取 entry。`matchHardened` 的 100/60/40+5 打分本体零改(红线)。

## D-L1-8 memo 键面(T4,review M4 落地形)

键 = FNV-1a("lightamer.lensfun.memo.v1" ⊕ cameraMaker ⊕ cameraModel ⊕ lensKey ⊕ imageCrop bits ⊕ focal bits);aperture/distance 不折(resolve-only);width/height 结构性缺席(值 = 匹配结果非系数)。值 = `(matched(entryIndex)/ambiguous/noLens/missingFocal)`;LRU 32;install/uninstall 换 stamp 清表;打分在锁外、读写表在锁内。memo 结果不写 params(持久化 = LENS-04 T1 域)。

## D-L1-9 旧键复用终形(T5)

`panel_lens_embedded_note` 保留 = **未判定(nil)文案**(zh/en 值零触碰);`panel_lens_no_exif` 保留 = idle 面。新增七键:`panel_lens_embedded_detected/unknown/notapplicable` + `panel_lens_match_matched/ambiguous/nolens/nodatabase`。

## D-L1-10 parity fixture 硬化适配(T3 回归面)

LensParityTests `testUnifiedExitMatchesManual` 的两 fixture params 补 `imageCrop = 1.534`——硬化后 nil→1.0 兜底撞 0.96 crop gate(1.0/1.534=0.652)→ blit identity。此即 plan 风险节预告的「阈值收紧匹配率回落」在测试 fixture 上的显形:fixture 相机本就是 1.534-crop 机身,补 crop = 语义正确化,非放宽门。

## 偏差清单

- ΔN +36 越带(+13..18)——SUMMARY 申报(表驱动密度,非膨胀)。
- plan 预写行号漂移(D-L1-3)——拓扑等价兑现。
- 其余零偏差。
