# M4-1-01-SUMMARY — TIFF 开发分支底座批（wave 1：新腿直驱，decode 路由不切）

> 执行 = ZCode subagent worker（夜间全自动授权「开跑，不要停」在案）。
> 起点 = `71f8f8d` 后 HEAD；基线 = 3174/16/0。收口 = 本文件 + DECISIONS +
> GOAL-STATE 续接点 + TODO 同批。双重验收（config `dual_acceptance = true`）=
> orchestrator 编排（zcode 独立验收 → 串行 omp 二次验收 → `M4-1-01-ACCEPTANCE.md`）。

## 任务逐条（commit SHA）

| 任务 | 交付 | commit |
|---|---|---|
| T1 | RasterColorDescription（解析序 ①→①′→②→③ + usable 三检查 + FNV 指纹 + 截断 SHA-256 profileHash）+ RasterIccParser（ICC 头/tag 表自解析、chad 反解、para 0..4、curv 采样、v4.4 cicp、mDCv/ccll、LUT 判别、canonicalization 阶梯）+ 测试 28 | `80c96c2` |
| T2 | `Scripts/gen-tiff-fixtures.py`（tifffile+numpy，幂等双跑聚合 shasum 一致）+ 21 fixture + MANIFEST + README（`Tests/Fixtures/TiffRaster/`） | `d391946` |
| T3 | RasterIccSemanticsTests 20（全 fixture 描述 golden 走 TIFF IFD tag 34675 真链 + TRC 公开标准双锚 + 平台行为钉）+ `tiffEmbeddedICCData` IFD 读取器 + RasterIccMat3 逆矩阵笔误修复 + 生成器 gray-kTRC 修复 | `2de7b99` |
| T4 | Aces2InverseReference（outputTransform_inv Float64 移植，上游锚注 ：1690/:544/:890；E3 数据依赖序在文件头钉死；Aces2Reference.swift 纯头注 diff；NOTICE §2 additive） | `d3a0268` |
| T5 | Aces2InverseTests 8（黑/白锚、fwd-first 恒等 4.4e-15、display-first 网格带 3.9e-3 + artifact 类普查、FMA 近黑哨兵 1e-6 全绿、色相保持） | `daf3542` |
| T6 | RasterDecoder.decodeTIFF（原生字节腿：8/16/32F 零转换、灰→RGB、alpha 丢弃不反 premul、CMYK typed 拒、多页取 0、内容探针 ≤4096 格；LUT-ICC 唯一 CI 腿分流）+ DecodedImage additive 双字段 + 测试 13 | `d9b8a51` |
| T7 | RasterInputKernels.metal 双入口（linearize+逆融合单 pass / scene-linear 矩阵支，上限不钳）+ RasterInputUniforms 自有 ABI（1611 float4 含 4096 采样面）+ RasterInputStage（develop-output 缓存 LRU4 + bucket-uniform + typed 失败）+ RasterInputPlaneTests 8 | `01c46b1` |
| T8 | RasterKernelParityTests 3（33³×五键 kernel parity：近黑=0（FMA 清白）、p99.9 实测带、scene-linear 8.7e-8、bucket 三桶同值） | `07cbbde` |
| T9 | srgbPiecewise 全族：DrtEotf case（kernelIndex 7/serde/Math 双臂）+ kernel case-7 镜像 + legalEOTFs rec709/p3d65 增行（顺序=KD-9 链）+ isHdrEncoding false 臂 + DrtOutputColorSpace 六臂组（curv 采样表方向修正）+ DrtPanelView 臂 + 新 xcstrings 键（尾块纯插入 +17 行）+ EditorMTKView γ2.2 近似 + hdrDrawable 布尔链补位 + 测试（DrtEotf+2、Export 5、Viewport+1、accept-set 面更新） | `7f7f000` |
| T10 | RasterDefaultRecord（derive 纯函数：两表分离/联合规则/γ pinned fits/linear 特例/探针 HDR 分支/fallback 链 + isHdrRaster 三支 + RGC 政策单源）+ 测试 14（逐行 joint rule + stableHash 零漂移） | `5b2caa7` |
| T11 | 收口（本文件 + DECISIONS + GOAL-STATE + TODO） | 本 commit |

## 测试数字 vs 基线

- 新增测试文件 7：RasterColorDescriptionTests 28（IOP）/ RasterIccSemanticsTests 20（IOP）/
  RasterDecodeLegTests 13（IOP）/ Aces2InverseTests 8（IOPP）/ RasterInputPlaneTests 8（IOPP）/
  RasterKernelParityTests 3（IOPP）/ RasterDefaultRecordTests 14（LAYERS）/
  ExportDrtColorSpaceSrgbTests 5（EXPORT）= 99；既有文件增法 +3（DrtEotfTests +2、
  DrtViewportTests +1）。**合计 +102**（plan 估 +75..85，超出声明）。
- 定向轮终值（亲跑）：IOP **544/1/0** + IOPParity **427/3/0** + Layers **394/3/0** +
  Export **347/1/0** —— 四 bundle 全绿零 MEMFAIL（基线 1611 → 1712，+101）；App +1
  （DrtViewportTests 定向绿）。**全套预期 3276/16/0**（3174+102；--all 留 02 收口轮）。
- zh-audit `--check` PASS 1585 source / 1823 catalog（**+1 键 = `drt_eotf_srgb_piecewise`**，checker E6 勘误兑现）。

## 红线自证（`git diff 71f8f8d..HEAD`）

- `LightamerCore/Sources/Pipe/Drt/Aces2Kernels.metal` **零 diff**；`LightamerIOP/` 零 diff；
  `LightamerCore/Sources/Sidecar/` 零 diff；`LightamerCore/Sources/Pipe/History/` 零 diff；
  `LightamerCore/Sources/Library/` 零 diff（机检在案，T11 收口批亲跑）。
- `Aces2Reference.swift` 仅文件头 NOT-ported 注记 diff（6 insert/3 delete 注释行，算法体零触碰）。
- `RAWDecoder.decode()` 路由零 diff（TIFF 仍走 decodeRaster CI 通路；`decodeRaster` 函数体
  零触碰；golden 钉死 = RasterDecodeLegTests.testProductionDecodeRoutingStillCIPath）。
- DrtRecord **结构零字段**（DrtEotf 枚举 additive case + legalEOTFs/isHdrEncoding switch 补臂
  = 申报在册的解封面）；sidecar/`.lalb` 零 schema 变更；六格式导出矩阵零改动
  （DrtOutputColorSpace additive 臂 = 申报在册）。
- 恒等面：RAW 文档渲染零变化（本批不触管线接线）；DRT 关闭文档 byte 不变（无管线 diff）。

## 申报外扩面（front-matter 之外的实触文件）

1. `LightamerCore/Sources/Decode/RAWDecoder.swift` — `contentDedupeID` private→internal
   （可见性提升，复用零行为 diff）。
2. `LightamerCore/Sources/Graph/RasterDefaultRecord.swift` — 新文件（plan front-matter
   漏列，T10 任务文本钦定交付物）。
3. 既有测试文件五处增改：DrtEotfTests/DrtRecordTests/DrtOutputColorSpaceTests（accept-set
   与 count 既有面更新 = T9 验收标准钦定）+ DrtViewportTests（hdrDrawable 负测 = T9 验收
   标准钦定，App bundle）+ Project.swift/BUNDLE-MAP 随批登记。

## 转接 M4-1-02（续接点详见 GOAL-STATE）

- `decode()` UTI 分流翻转（TIFF → decodeTIFF 新腿）+ PixelPipe position-0 装配 +
  decodeParamsHash 式显式折叠 + 编辑面门控（RAW Decode 页隐藏/defaultLook mint 跳过）+
  导入选择器（OQ-5/6/7）+ round-trip SC#1 收口 + 全套回归。
- 本批已就位：描述解析/fixture 矩阵/逆变换 Float64 authority/kernel 镜像/缓存位/默认
  record 推导/srgbPiecewise 全族——02 只做接线与翻转。
