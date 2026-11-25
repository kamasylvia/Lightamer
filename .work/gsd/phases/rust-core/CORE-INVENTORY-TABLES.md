# CORE-INVENTORY-TABLES — 明细与大表

> 配套 `CORE-INVENTORY.md`。所有数字的命令见 §K。行数口径：模块表为 `wc -l`，分层表为逐文件 `splitlines()`（合计 156,050，`wc` 156,048，差 2 行为无尾换行文件）。

## §A LightamerCore 目录明细与主导难度档

| 目录 | 文件 | 行 | 主导档 | 分档行数（纯/着色器/Apple/UI） | 关键公开类型 |
|---|---:|---:|---|---|---|
| `AI/` | 30 | 8,102 | 纯逻辑（混合） | 5,285 / 99 / 2,718 / 0 | `SemanticEngine`, `SemanticStore`, `AIWorkerProtocol`, `AIMaskService`, `AISubjectSeed`, `AICredentialStore` |
| `Catalog/` | 5 | 2,907 | 纯逻辑 | 2,907 / 0 / 0 / 0 | `CatalogIndexStore`, `CatalogProjector`, `CatalogRebuilder`, `CatalogIndexSchema` |
| `ColorMatch/` | 8 | 1,609 | 纯逻辑 | 1,609 / 0 / 0 / 0 | `ColorMatchSolver`, `ColorMatchCDFSolver`, `ColorMatchBake`, `OklabMath` |
| `Decode/` | 10 | 4,049 | Apple 适配 | 616 / 0 / 3,434 / 0 | `RAWDecoder`, `RasterDecoder`, `SmartPreviewStore`, `CaptureMetadata`, `DecodedImage` |
| `Export/` | 18 | 6,491 | Apple 适配 | 1,963 / 0 / 4,528 / 0 | `ExportQueue`, `ExportRenderer`, `ExportEncoder`, `ExportFormatSpec`, `ExportMetadataPolicy`, `DrtOutputColorSpace` |
| `Film/` | 13 | 5,093 | 纯逻辑 | 5,093 / 0 / 0 / 0 | `FilmMaterialStore`, `SpectralFilmRuntime`, `SpectralBuildEngine`, `FilmProfile`, `PaperGradeTable` |
| `Foundation/` | 11 | 1,697 | 纯逻辑（混合） | 990 / 0 / 707 / 0 | `StableHash`, `WorkingSpace`, `V50Order`, `ParamsCoding`, `AppError`, `SoftProofProfile` |
| `Graph/` | 6 | 1,548 | 纯逻辑 | 1,548 / 0 / 0 / 0 | `PipelineDocument`, `NodeGraphCommand`, `DrtRecord`, `FilmRecord`, `RasterDefaultRecord` |
| `Layers/` | 18 | 4,474 | 着色器宿主（混合） | 1,761 / 2,451 / 262 / 0 | `LayerStack`, `AdjustmentLayer`, `MaskSpec`, `DrawnMaskRasterizer`, `RetouchEngine`, `BlendMode` |
| `Library/` | 17 | 7,853 | 纯逻辑（混合） | 6,903 / 0 / 950 / 0 | `ProjectFileStore`, `LibraryStore`, `LibrarySchema`, `ImportService`, `LibraryQueries`, `LibraryAnalysisService` |
| `Metal/` | 6 | 1,402 | Apple 适配（Metal/CIContext） | 68 / 33 / 1,301 / 0 | `MetalContext`, `CIContextPool`, `ComputeEncoderSession`, `MetalError` |
| `Pipe/` | 48 | 17,758 | 纯逻辑（混合） | 8,796 / 5,879 / 3,083 / 0 | `PixelPipe`, `IOPModule`, `ModuleRegistry`, `PipeCache`, `HistoryStack`, `DrtTailAssembly`, `FilmTailAssembly` |
| `Presets/` | 3 | 654 | 纯逻辑 | 654 / 0 / 0 / 0 | `LightamerPreset`, `PresetsStore`, `PresetApplier` |
| `Session/` | 16 | 5,720 | 纯逻辑（混合） | 3,316 / 0 / 2,404 / 0 | `SessionIndexStore`, `SessionThumbnailProvider`, `FilterSQL`, `SmartAlbumStore`, `XMPImport` |
| `Sidecar/` | 6 | 2,127 | 纯逻辑（混合） | 1,797 / 0 / 330 / 0 | `LightamerSidecar`, `SidecarStore`, `SidecarLayerStack`, `RasterMaskStore`, `UInt64String` |
| `Stack/` | 17 | 9,403 | 纯逻辑（混合） | 5,447 / 247 / 3,710 / 0 | `StackMergeService`, `FocusStackMerge`, `HDRMergeMath`, `MertensFusion`, `PanoWarp`, `FloatTIFFWriter` |

## §B LightamerIOP 逐目录 / opName / kernel

| 目录 | Swift 文件 | Swift 行 | .metal | kernels | opName |
|---|---:|---:|---:|---:|---|
| `ACEScc/` | 1 | 144 | 2 | 2 | acesccIn, acesccOut |
| `AgX/` | 1 | 563 | 1 | 1 | agx |
| `Ashift/` | 3 | 854 | 1 | 1 | ashift |
| `Bilateral/` | 1 | 566 | 1 | 4 | bilateral |
| `BlendOp/` | 2 | 544 | 1 | 2 | —（共享合成引擎） |
| `Bloom/` | 2 | 456 | 1 | 4 | bloom |
| `Cat02WB/` | 1 | 830 | 1 | 1 | cat02WhiteBalance |
| `ChannelMixer/` | 1 | 340 | 1 | 1 | channelmixer |
| `ChannelMixerRGB/` | 2 | 803 | 1 | 1 | channelmixerrgb |
| `Colisa/` | 1 | 250 | 1 | 1 | colisa |
| `ColorBalanceRGB/` | 1 | 843 | 1 | 1 | colorbalancergb |
| `ColorContrast/` | 1 | 156 | 1 | 1 | colorcontrast |
| `ColorMatch/` | 2 | 756 | 1 | 1 | colormatch |
| `ColorWheels/` | 2 | 948 | 1 | 2 | colorWheels |
| `ColorZones/` | 2 | 695 | 1 | 1 | colorzones |
| `Common/` | 8 | 1,461 | 5 | 18 | —（共享 kernel） |
| `Contrast/` | 1 | 161 | 1 | 1 | contrast |
| `Crop/` | 1 | 242 | 0 | 0 | crop |
| `Dehaze/` | 2 | 720 | 1 | 9 | hazeremoval |
| `DenoiseProfile/` | 2 | 1,542 | 1 | 14 | denoiseprofile |
| `Equalizer/` | 1 | 367 | 1 | 2 | equalizer |
| `Exposure/` | 1 | 211 | 1 | 1 | exposure |
| `FilmPlacement/` | 1 | 458 | 1 | 1 | filmPlacement |
| `FilmicRGB/` | 3 | 1,314 | 1 | 2 | filmicrgb |
| `Flip/` | 1 | 307 | 1 | 1 | flip |
| `Grain/` | 3 | 553 | 1 | 1 | grain |
| `Highpass/` | 1 | 266 | 1 | 2 | highpass |
| `Hls/` | 1 | 286 | 1 | 1 | hls |
| `Lens/` | 5 | 2,477 | 1 | 1 | lens |
| `Levels/` | 1 | 263 | 1 | 1 | levels |
| `Liquify/` | 2 | 955 | 1 | 1 | liquify |
| `LocalContrast/` | 1 | 460 | 1 | 2 | bilat |
| `Lut3d/` | 6 | 2,656 | 1 | 3 | lut3d |
| `Masks/` | 0 | 0 | 2 | 5 | —（蒙版共享 kernel） |
| `Monochrome/` | 2 | 454 | 1 | 2 | monochrome |
| `NLMeans/` | 1 | 483 | 1 | 6 | nlmeans |
| `Saturation/` | 1 | 117 | 1 | 1 | saturation |
| `Shadhi/` | 1 | 347 | 1 | 2 | shadhi |
| `Sharpen/` | 1 | 364 | 1 | 2 | sharpen |
| `Sigmoid/` | 2 | 687 | 1 | 2 | sigmoid |
| `SkinSmooth/` | 3 | 1,117 | 1 | 1 | skinSmooth |
| `Soften/` | 1 | 361 | 1 | 2 | soften |
| `SpektraFilm/` | 1 | 196 | 0 | 0 | spektraFilm |
| `Temperature/` | 2 | 733 | 1 | 1 | temperature |
| `TextOverlay/` | 2 | 462 | 1 | 1 | textOverlay |
| `Tint/` | 1 | 110 | 1 | 1 | tint |
| `ToneCurve/` | 2 | 629 | 1 | 1 | tonecurve |
| `ToneEqual/` | 2 | 1,097 | 1 | 9 | toneequal |
| `Upright/` | 1 | 370 | 0 | 0 | upright |
| `Velvia/` | 1 | 174 | 1 | 1 | velvia |
| `Vibrance/` | 1 | 149 | 1 | 1 | vibrance |
| `Vignette/` | 2 | 408 | 1 | 1 | vignette |
| `WhiteBlack/` | 2 | 216 | 1 | 2 | black, white |
| `Yiyin/` | 8 | 3,302 | 1 | 4 | borders, watermark |
| `Sources/*.swift`（root） | 4 | 1,496 | 2 | 3 | passthrough_spike, testgain |
| **合计** | **105** | **36,719** | **59** | **133** | 56 个 opName / 56 个 `*Module` 类 |

> `BlendOp/`、`Common/`、`Masks/` 不是 op；`Crop/`/`Upright/`/`SpektraFilm/` 无自有 metal，复用共享/几何 kernel。

## §C App 非 UI 目录的 UI 视图清单

| 目录 | 视图/面板文件 | 行 | 说明 |
|---|---|---:|---|
| `Export/` | `ExportInspectorView.swift`, `ExportPanelView.swift`, `ExportQueueFaceView.swift`, `ExportNamingEditor.swift` | 2,660 | SwiftUI 页面；不属于 Rust 核 |
| `Library/` | `Views/*` 6 文件 + `ImportModeDialog.swift`, `ImportProgressView.swift` | ~2,970 | SwiftUI 页面/对话框 |
| `Yiyin/` | `YiyinPanelView.swift` | 746 | SwiftUI 面板 |
| `State/` | 17 个 `@Observable` 模型（非 View） | 9,352 | 逻辑 + Observation 绑定，需要拆薄壳 |
| `AI/` | 6 个 `@Observable` 模型（非 View） | 1,544 | 逻辑 + Observation 绑定 |

## §D Apple 依赖逐文件表

### CIRAWFilter — 5 files / 18 occurrences

| 文件 | 处 |
|---|---:|
| `LightamerCore/Sources/Decode/RAWDecoder.swift` | 14 |
| `LightamerCore/Sources/Decode/CaptureMetadata.swift` | 1 |
| `LightamerCore/Sources/Decode/DecodedImage.swift` | 1 |
| `LightamerCore/Sources/Metal/CIContextPool.swift` | 1 |
| `LightamerCore/Sources/Pipe/Terminal/ColorInModule.swift` | 1 |

### CIContext — 21 files / 64 occurrences

| 文件 | 处 |
|---|---:|
| `LightamerCore/Sources/Metal/MetalContext.swift` | 14 |
| `LightamerCore/Sources/Metal/CIContextPool.swift` | 10 |
| `LightamerCore/Sources/Stack/StackMergeService.swift` | 8 |
| `LightamerCore/Sources/Decode/SmartPreviewStore.swift` | 4 |
| `LightamerCore/Sources/Export/ExportGainMapEncoder.swift` | 4 |
| `App/Sources/Lightamer/MCP/Tools/CullingToolset.swift` | 3 |
| `LightamerCore/Sources/Foundation/DisplayProfile.swift` | 3 |
| `LightamerCore/Sources/Decode/RAWDecoder.swift` | 2 |
| `LightamerCore/Sources/Export/ExportRenderer.swift` | 2 |
| `LightamerCore/Sources/Export/QuickLookRenderer.swift` | 2 |
| `LightamerCore/Sources/Pipe/Terminal/SoftProofStage.swift` | 2 |
| `App/Sources/Lightamer/AI/DepthMaskService.swift` | 1 |
| `App/Sources/Lightamer/Library/CullViewLoader.swift` | 1 |
| `App/Sources/Lightamer/State/PipeCoordinator.swift` | 1 |
| `App/Sources/Lightamer/State/SessionThumbnailRenderer.swift` | 1 |
| `LightamerCore/Sources/AI/AIMaskService.swift` | 1 |
| `LightamerCore/Sources/Decode/DecodedImage.swift` | 1 |
| `LightamerCore/Sources/Export/ExportEncoder.swift` | 1 |
| `LightamerCore/Sources/Export/ExportQuantizer.swift` | 1 |
| `LightamerCore/Sources/Pipe/Terminal/ColorOutModule.swift` | 1 |
| `LightamerIOP/Sources/Ashift/VisionDetect.swift` | 1 |

### CIImage — 13 files / 84 occurrences

| 文件 | 处 |
|---|---:|
| `LightamerCore/Sources/Metal/CIContextPool.swift` | 29 |
| `LightamerCore/Sources/Export/ExportGainMapEncoder.swift` | 9 |
| `LightamerCore/Sources/AI/AIMaskService.swift` | 8 |
| `LightamerCore/Sources/Decode/DecodedImage.swift` | 6 |
| `LightamerCore/Sources/Metal/MetalContext.swift` | 6 |
| `LightamerCore/Sources/Stack/StackMergeService.swift` | 5 |
| `LightamerCore/Sources/Decode/SmartPreviewStore.swift` | 4 |
| `App/Sources/Lightamer/State/SessionThumbnailRenderer.swift` | 4 |
| `LightamerCore/Sources/Pipe/PixelPipe.swift` | 4 |
| `LightamerCore/Sources/Decode/RasterDecoder.swift` | 3 |
| `LightamerIOP/Sources/Ashift/VisionDetect.swift` | 3 |
| `LightamerCore/Sources/Decode/RAWDecoder.swift` | 2 |
| `App/Sources/Lightamer/State/AIMaskEditing.swift` | 1 |

### ColorSync C API（CMProfile/CMWorld）— 0 files / 0 occurrences

全仓无直接调用。色彩管理只走 `CGColorSpace`（40 文件 / 221 处）与 `CGColorConversion`（2 文件 / 10 处）。

### CGColorSpace — 40 files / 221 occurrences

| 文件 | 处 |
|---|---:|
| `LightamerCore/Sources/Foundation/DisplayProfile.swift` | 34 |
| `LightamerCore/Sources/Export/ExportEncoder.swift` | 26 |
| `LightamerCore/Sources/Pipe/Terminal/ColorOutModule.swift` | 20 |
| `LightamerCore/Sources/Export/DrtOutputColorSpace.swift` | 18 |
| `LightamerCore/Sources/Decode/RasterColorDescription.swift` | 16 |
| `LightamerCore/Sources/Decode/SmartPreviewStore.swift` | 6 |
| `LightamerCore/Sources/Export/ExportChainBuilder.swift` | 6 |
| `LightamerCore/Sources/Metal/CIContextPool.swift` | 6 |
| `LightamerIOP/Sources/Yiyin/YiyinLogoStore.swift` | 6 |
| `App/Sources/Lightamer/AI/EnhanceDialogModel.swift` | 5 |
| `LightamerCore/Sources/Stack/BandStreamer.swift` | 5 |
| `LightamerCore/Sources/Stack/StackMergeService.swift` | 5 |
| `App/Sources/Lightamer/AI/AIWorkerEnhancement.swift` | 4 |
| `App/Sources/Lightamer/MCP/Tools/CullingToolset.swift` | 4 |
| `App/Sources/Lightamer/State/SessionThumbnailRenderer.swift` | 4 |
| `LightamerCore/Sources/AI/EnhanceEngine.swift` | 4 |
| `LightamerCore/Sources/Foundation/ManualDisplayOverrideStore.swift` | 4 |
| `LightamerCore/Sources/Foundation/WorkingSpace.swift` | 4 |
| `LightamerCore/Sources/Export/ExportQueueContract.swift` | 3 |
| `LightamerCore/Sources/Export/ExportRenderer.swift` | 3 |
| `LightamerCore/Sources/Foundation/SoftProofProfile.swift` | 3 |
| `LightamerCore/Sources/Library/EyeClosureAnalyzer.swift` | 3 |
| `LightamerCore/Sources/Library/LibraryAnalysisService.swift` | 3 |
| `LightamerCore/Sources/Metal/MetalContext.swift` | 3 |
| `App/Sources/Lightamer/AI/AIWorkerDepth.swift` | 2 |
| `App/Sources/Lightamer/AI/DepthMaskService.swift` | 2 |
| `App/Sources/Lightamer/AI/EnhanceCopyWriter.swift` | 2 |
| `LightamerCore/Sources/AI/SemanticEngine.swift` | 2 |
| `LightamerCore/Sources/Decode/RasterDecoder.swift` | 2 |
| `LightamerCore/Sources/Export/QuickLookRenderer.swift` | 2 |
| `LightamerCore/Sources/Sidecar/RasterMaskStore.swift` | 2 |
| `LightamerCore/Sources/Stack/GhostMaskWriter.swift` | 2 |
| `LightamerIOP/Sources/TextOverlay/TextRasterizer.swift` | 2 |
| `LightamerIOP/Sources/Yiyin/YiyinTextRenderer.swift` | 2 |
| `App/Sources/Lightamer/State/PipeCoordinator.swift` | 1 |
| `LightamerCore/Sources/Decode/RasterIccParser.swift` | 1 |
| `LightamerCore/Sources/Export/ExportGainMapEncoder.swift` | 1 |
| `LightamerCore/Sources/Export/ImageIOEncoders.swift` | 1 |
| `LightamerCore/Sources/Layers/Masks/MaskThumbnailRenderer.swift` | 1 |
| `LightamerIOP/Sources/Yiyin/YiyinColor.swift` | 1 |

### CGColorConversion — 2 files / 10 occurrences

| 文件 | 处 |
|---|---:|
| `LightamerCore/Sources/Pipe/Terminal/SoftProofStage.swift` | 6 |
| `LightamerCore/Sources/Foundation/SoftProofProfile.swift` | 4 |

### Vision（VN*）— 4 files / 28 occurrences

| 文件 | 处 |
|---|---:|
| `LightamerIOP/Sources/Ashift/VisionDetect.swift` | 11 |
| `LightamerCore/Sources/Library/EyeClosureAnalyzer.swift` | 8 |
| `App/Sources/Lightamer/MCP/Tools/CullingToolset.swift` | 5 |
| `LightamerIOP/Sources/SkinSmooth/SkinRegionLocator.swift` | 4 |

> `import Vision` 共 7 文件；其中 4 文件出现 `VN*` 符号（上表），其余 3 文件（`AIMaskTypes.swift`、`AIAssetStatus.swift`、`AIMaskService.swift`）只 import 类型/协议，不计入 28 处。

### CGImageSource — 18 files / 95 occurrences

| 文件 | 处 |
|---|---:|
| `LightamerCore/Sources/Decode/RAWDecoder.swift` | 15 |
| `App/Sources/Lightamer/Library/CullViewLoader.swift` | 11 |
| `App/Sources/Lightamer/AI/EnhanceCopyWriter.swift` | 9 |
| `LightamerCore/Sources/Session/SessionThumbnailProvider.swift` | 8 |
| `LightamerCore/Sources/AI/SemanticEngine.swift` | 6 |
| `LightamerCore/Sources/Library/LibraryAnalysisService.swift` | 6 |
| `LightamerCore/Sources/Decode/RasterDecoder.swift` | 5 |
| `App/Sources/Lightamer/AI/AIWorkerDepth.swift` | 4 |
| `App/Sources/Lightamer/AI/AIWorkerEnhancement.swift` | 4 |
| `LightamerCore/Sources/AI/EnhanceEngine.swift` | 4 |
| `LightamerCore/Sources/Export/ImageIOEncoders.swift` | 4 |
| `LightamerCore/Sources/Library/ExifSearchIndexer.swift` | 4 |
| `LightamerCore/Sources/Session/SessionIndexStore.swift` | 4 |
| `LightamerIOP/Sources/Yiyin/YiyinLogoStore.swift` | 4 |
| `LightamerCore/Sources/Export/ExportGainMapEncoder.swift` | 2 |
| `LightamerCore/Sources/Session/ThumbnailDiskStore.swift` | 2 |
| `LightamerCore/Sources/Sidecar/RasterMaskStore.swift` | 2 |
| `LightamerCore/Sources/Foundation/AppError.swift` | 1 |

### CGImageDestination — 17 files / 71 occurrences

| 文件 | 处 |
|---|---:|
| `LightamerCore/Sources/Export/ImageIOEncoders.swift` | 12 |
| `LightamerCore/Sources/Export/ExportGainMapEncoder.swift` | 7 |
| `LightamerCore/Sources/Session/ThumbnailDiskStore.swift` | 7 |
| `App/Sources/Lightamer/MCP/Tools/CullingToolset.swift` | 6 |
| `LightamerCore/Sources/Stack/BandStreamer.swift` | 5 |
| `App/Sources/Lightamer/AI/DepthMaskService.swift` | 4 |
| `App/Sources/Lightamer/MCP/Tools/EditingToolset.swift` | 4 |
| `LightamerCore/Sources/AI/SemanticEngine.swift` | 4 |
| `LightamerCore/Sources/Stack/GhostMaskWriter.swift` | 4 |
| `App/Sources/Lightamer/AI/AIWorkerEnhancement.swift` | 3 |
| `App/Sources/Lightamer/AI/EnhanceCopyWriter.swift` | 3 |
| `LightamerCore/Sources/AI/EnhanceEngine.swift` | 3 |
| `LightamerCore/Sources/Sidecar/RasterMaskStore.swift` | 3 |
| `LightamerCore/Sources/Export/ExportEncoder.swift` | 2 |
| `LightamerCore/Sources/Export/ExportRecipe.swift` | 2 |
| `LightamerCore/Sources/Export/ExportQueueContract.swift` | 1 |
| `LightamerCore/Sources/Foundation/AppError.swift` | 1 |

### Metal（MTL*）— 102 files / 1,485 occurrences（Top 60；词界 `\bMTL[A-Z]` 口径，plain 子串 1,488）

| 文件 | 处 |
|---|---:|
| `LightamerCore/Sources/Pipe/Film/SpectralPayloads.swift` | 167 |
| `LightamerCore/Sources/Pipe/PixelPipe.swift` | 71 |
| `LightamerIOP/Sources/ToneEqual/ToneEqualModule.swift` | 66 |
| `LightamerCore/Sources/Metal/MetalContext.swift` | 61 |
| `LightamerIOP/Sources/DenoiseProfile/WaveletEngine.swift` | 58 |
| `LightamerCore/Sources/Layers/Masks/MaskCombiner.swift` | 55 |
| `LightamerCore/Sources/Layers/Retouch/RetouchEngine.swift` | 53 |
| `LightamerIOP/Sources/Yiyin/BordersModule.swift` | 43 |
| `LightamerIOP/Sources/LocalContrast/LocalContrastModule.swift` | 40 |
| `LightamerCore/Sources/Layers/Masks/DrawnMaskRasterizer.swift` | 38 |
| `LightamerIOP/Sources/Dehaze/DehazeModule.swift` | 33 |
| `App/Sources/Lightamer/State/PipeCoordinator.swift` | 29 |
| `LightamerIOP/Sources/Lut3d/Lut3dModule.swift` | 27 |
| `LightamerIOP/Sources/ColorMatch/ColormatchModule.swift` | 25 |
| `LightamerIOP/Sources/Bilateral/BilateralModule.swift` | 22 |
| `LightamerIOP/Sources/NLMeans/NLMeansModule.swift` | 22 |
| `LightamerIOP/Sources/Soften/SoftenModule.swift` | 21 |
| `LightamerCore/Sources/Metal/CIContextPool.swift` | 19 |
| `LightamerCore/Sources/Pipe/Film/SpectralScratchAllocator.swift` | 19 |
| `LightamerCore/Sources/Pipe/Input/RasterInputStage.swift` | 19 |
| `LightamerIOP/Sources/Bloom/BloomModule.swift` | 19 |
| `LightamerIOP/Sources/Equalizer/EqualizerModule.swift` | 19 |
| `LightamerIOP/Sources/BlendOp/BlendOpEngine.swift` | 18 |
| `LightamerIOP/Sources/Sharpen/SharpenModule.swift` | 18 |
| `LightamerIOP/Sources/SkinSmooth/SkinSmoothModule.swift` | 18 |
| `LightamerIOP/Sources/Monochrome/MonochromeGridLeg.swift` | 16 |
| `LightamerIOP/Sources/Yiyin/WatermarkModule.swift` | 14 |
| `LightamerIOP/Sources/Highpass/HighpassModule.swift` | 13 |
| `LightamerIOP/Sources/Shadhi/ShadhiModule.swift` | 13 |
| `LightamerIOP/Sources/TextOverlay/TextOverlayModule.swift` | 13 |
| `LightamerCore/Sources/Pipe/Film/FilmTailPolicy.swift` | 12 |
| `LightamerCore/Sources/Pipe/LayerCompositeDriver.swift` | 12 |
| `LightamerIOP/Sources/Common/ScopeReduce.swift` | 12 |
| `LightamerIOP/Sources/SpektraFilm/SpektraFilmModule.swift` | 12 |
| `LightamerCore/Sources/Stack/FocusMeasure.swift` | 11 |
| `LightamerIOP/Sources/Common/GaussianBlur.swift` | 11 |
| `LightamerCore/Sources/Export/ExportGainMapEncoder.swift` | 10 |
| `LightamerIOP/Sources/Common/HistogramReduce.swift` | 10 |
| `LightamerIOP/Sources/Liquify/LiquifyModule.swift` | 10 |
| `LightamerCore/Sources/Sidecar/RasterMaskStore.swift` | 9 |
| `LightamerCore/Sources/Stack/StackMergeService.swift` | 9 |
| `LightamerIOP/Sources/ColorWheels/ColorWheelsModule.swift` | 9 |
| `LightamerIOP/Sources/FilmPlacement/FilmPlacementModule.swift` | 9 |
| `LightamerIOP/Sources/Grain/GrainModule.swift` | 9 |
| `LightamerIOP/Sources/Lens/LensModule.swift` | 9 |
| `LightamerIOP/Sources/Monochrome/MonochromeModule.swift` | 9 |
| `LightamerIOP/Sources/Vignette/VignetteModule.swift` | 9 |
| `LightamerCore/Sources/Layers/Masks/MaskThumbnailRenderer.swift` | 8 |
| `LightamerIOP/Sources/Ashift/AshiftModule.swift` | 8 |
| `LightamerIOP/Sources/ColorBalanceRGB/ColorBalanceRGBModule.swift` | 8 |
| `LightamerIOP/Sources/Upright/UprightModule.swift` | 8 |
| `LightamerCore/Sources/Pipe/Terminal/ColorOutModule.swift` | 7 |
| `LightamerIOP/Sources/AgX/AgXModule.swift` | 7 |
| `LightamerIOP/Sources/Colisa/ColisaModule.swift` | 7 |
| `LightamerIOP/Sources/ColorZones/ColorZonesModule.swift` | 7 |
| `LightamerIOP/Sources/Exposure/ExposureModule.swift` | 7 |
| `LightamerIOP/Sources/FilmicRGB/FilmicRGBModule.swift` | 7 |
| `LightamerIOP/Sources/Levels/LevelsModule.swift` | 7 |
| `LightamerIOP/Sources/Sigmoid/SigmoidModule.swift` | 7 |
| `LightamerIOP/Sources/Temperature/TemperatureModule.swift` | 7 |

> 其余 42 个文件各 1–7 处；完整列表可由 §K 的 grep 命令复现。另有 3 文件仅出现 `MTLSize` 等非资源类型，故 `MTL*` 总命中 102 文件、核心资源类型 99 文件。

### CoreML — 3 files / 28 occurrences

| 文件 | 处 |
|---|---:|
| `LightamerCore/Sources/AI/SemanticEngine.swift` | 14 |
| `App/Sources/Lightamer/AI/AIWorkerEnhancement.swift` | 8 |
| `App/Sources/Lightamer/AI/AIWorkerDepth.swift` | 6 |

> `import CoreML` 共 7 文件；其余 4 文件只用协议/类型，不直接实例化 `MLModel`。28 处是符号口径（`MLModel`/`MLFeatureProvider`/`MLMultiArray`/`VNCoreMLRequest`，排除 `MLModelRunner` 类名）；字面 `MLModel` 为 32 处/3 文件。

### UTType — 9 files / 13 occurrences

| 文件 | 处 |
|---|---:|
| `LightamerCore/Sources/Decode/RAWDecoder.swift` | 5 |
| `App/Sources/Lightamer/AI/DepthMaskService.swift` | 1 |
| `App/Sources/Lightamer/AI/EnhanceCopyWriter.swift` | 1 |
| `App/Sources/Lightamer/MCP/Tools/EditingToolset.swift` | 1 |
| `LightamerCore/Sources/Export/ExportGainMapEncoder.swift` | 1 |
| `LightamerCore/Sources/Session/ThumbnailDiskStore.swift` | 1 |
| `LightamerCore/Sources/Sidecar/RasterMaskStore.swift` | 1 |
| `LightamerCore/Sources/Stack/BandStreamer.swift` | 1 |
| `LightamerCore/Sources/Stack/GhostMaskWriter.swift` | 1 |

### CoreText — 4 files / 38 occurrences

| 文件 | 处 |
|---|---:|
| `LightamerIOP/Sources/TextOverlay/TextRasterizer.swift` | 15 |
| `LightamerIOP/Sources/Yiyin/YiyinTextRenderer.swift` | 11 |
| `LightamerIOP/Sources/Yiyin/YiyinFontStore.swift` | 8 |
| `App/Sources/Lightamer/MCP/Tools/CullingToolset.swift` | 4 |

### SQLite（非 Apple，平台 C）— 6 files / 117 occurrences

| 文件 | 处 |
|---|---:|
| `LightamerCore/Sources/Decode/SmartPreviewStore.swift` | 45 |
| `LightamerCore/Sources/Session/SQLiteHandle.swift` | 42 |
| `LightamerCore/Sources/Library/ProjectFileStore.swift` | 19 |
| `LightamerCore/Sources/Library/LibrarySchema.swift` | 7 |
| `App/Sources/Lightamer/Library/LibraryProjectController.swift` | 2 |
| `LightamerCore/Sources/Library/LibraryError.swift` | 2 |

## §E 73 个 `.metal` 逐文件表

| # | .metal 文件 | 行 | kernels | 宿主 Swift |
|---|---|---:|---:|---|
| 1 | `App/Sources/Lightamer/UI/EditorBlitShader.metal` | 86 | 0 | EditorMTKView.swift（vertex+fragment） |
| 2 | `LightamerCore/Sources/Metal/MaskCombineKernels.metal` | 115 | 4 | Layers/Masks/MaskCombiner.swift |
| 3 | `LightamerCore/Sources/Metal/MaskEdgeKernels.metal` | 49 | 1 | Layers/Masks/FollowEdges.swift |
| 4 | `LightamerCore/Sources/Metal/MaskRasterKernels.metal` | 352 | 3 | Layers/Masks/DrawnMaskRasterizer.swift; State/PipeCoordinator.swift |
| 5 | `LightamerCore/Sources/Metal/RetouchKernels.metal` | 277 | 7 | Layers/Retouch/RetouchEngine.swift |
| 6 | `LightamerCore/Sources/Metal/StackKernels.metal` | 90 | 1 | Stack/FocusMeasure.swift |
| 7 | `LightamerCore/Sources/Pipe/Drt/Aces2Kernels.metal` | 480 | 2 | Pipe/PixelPipe.swift |
| 8 | `LightamerCore/Sources/Pipe/Drt/DrtEotfKernels.metal` | 211 | 3 | Pipe/Drt/DrtEotf.swift; Pipe/PixelPipe.swift |
| 9 | `LightamerCore/Sources/Pipe/Drt/OpenDrtKernels.metal` | 479 | 2 | Pipe/PixelPipe.swift |
| 10 | `LightamerCore/Sources/Pipe/Film/FilmSubRunKernels.metal` | 138 | 1 | Pipe/Film/FilmTailPolicy.swift; Pipe/PixelPipe.swift |
| 11 | `LightamerCore/Sources/Pipe/Film/SpectralFilmKernels.metal` | 1,070 | 7 | Pipe/Film/SpectralPayloads.swift |
| 12 | `LightamerCore/Sources/Pipe/Film/SpectralSpatialKernels.metal` | 593 | 16 | Pipe/Film/SpectralPayloads.swift |
| 13 | `LightamerCore/Sources/Pipe/Input/RasterInputKernels.metal` | 582 | 3 | Pipe/Input/RasterInputStage.swift |
| 14 | `LightamerCore/Sources/Pipe/Terminal/TerminalKernels.metal` | 95 | 3 | Pipe/Terminal/ColorInModule.swift; ColorOutModule.swift |
| 15 | `LightamerIOP/Sources/ACEScc/ACESccConvert.metal` | 32 | 2 | ACESccInModule.swift; ACESccOutModule.swift |
| 16 | `LightamerIOP/Sources/ACEScc/ACESccMath.metal` | 74 | 0 | header-only，被 ACESccConvert.metal `#include` |
| 17 | `LightamerIOP/Sources/AgX/AgXKernels.metal` | 269 | 1 | AgXModule.swift |
| 18 | `LightamerIOP/Sources/Ashift/AshiftKernels.metal` | 109 | 1 | AshiftModule.swift; UprightModule.swift |
| 19 | `LightamerIOP/Sources/Bilateral/BilateralKernels.metal` | 266 | 4 | BilateralModule.swift |
| 20 | `LightamerIOP/Sources/BlendOp/BlendOpKernels.metal` | 349 | 2 | BlendOpEngine.swift; Core/Pipe/LayerCompositeDriver.swift |
| 21 | `LightamerIOP/Sources/Bloom/BloomKernels.metal` | 168 | 4 | BloomModule.swift |
| 22 | `LightamerIOP/Sources/Cat02WB/Cat02WB.metal` | 41 | 1 | Cat02WBModule.swift |
| 23 | `LightamerIOP/Sources/ChannelMixer/ChannelMixerKernels.metal` | 115 | 1 | ChannelMixerModule.swift |
| 24 | `LightamerIOP/Sources/ChannelMixerRGB/ChannelMixerRGBKernels.metal` | 250 | 1 | ChannelMixerRGBModule.swift |
| 25 | `LightamerIOP/Sources/Colisa/ColisaKernels.metal` | 63 | 1 | ColisaModule.swift |
| 26 | `LightamerIOP/Sources/ColorBalanceRGB/ColorBalanceRGBKernels.metal` | 494 | 1 | ColorBalanceRGBModule.swift |
| 27 | `LightamerIOP/Sources/ColorContrast/ColorContrastKernels.metal` | 42 | 1 | ColorContrastModule.swift |
| 28 | `LightamerIOP/Sources/ColorMatch/ColorMatchKernels.metal` | 103 | 1 | ColormatchModule.swift |
| 29 | `LightamerIOP/Sources/ColorWheels/ColorWheels.metal` | 109 | 2 | ColorWheelsModule.swift; Core/Pipe/RenderProcess.swift |
| 30 | `LightamerIOP/Sources/ColorZones/ColorZonesKernels.metal` | 75 | 1 | ColorZonesModule.swift |
| 31 | `LightamerIOP/Sources/Common/BilateralGrid3DKernels.metal` | 192 | 4 | Common/BilateralGrid3D.swift |
| 32 | `LightamerIOP/Sources/Common/GaussianBlurKernels.metal` | 155 | 4 | Common/GaussianBlur.swift; ToneEqual/ToneEqualModule.swift |
| 33 | `LightamerIOP/Sources/Common/HistogramReduceKernels.metal` | 143 | 4 | Common/HistogramReduce.swift |
| 34 | `LightamerIOP/Sources/Common/LabKernels.metal` | 36 | 2 | Common/LabRoundTrip.swift |
| 35 | `LightamerIOP/Sources/Common/ScopeReduceKernels.metal` | 131 | 4 | Common/ScopeReduce.swift |
| 36 | `LightamerIOP/Sources/Contrast/Contrast.metal` | 78 | 1 | ContrastModule.swift |
| 37 | `LightamerIOP/Sources/Dehaze/DehazeKernels.metal` | 248 | 9 | DehazeModule.swift |
| 38 | `LightamerIOP/Sources/DenoiseProfile/DenoiseProfileKernels.metal` | 570 | 14 | DenoiseProfileModule.swift; WaveletEngine.swift |
| 39 | `LightamerIOP/Sources/Equalizer/EqualizerKernels.metal` | 93 | 2 | EqualizerModule.swift |
| 40 | `LightamerIOP/Sources/Exposure/ExposureKernels.metal` | 28 | 1 | ExposureModule.swift |
| 41 | `LightamerIOP/Sources/FilmPlacement/FilmPlacementKernels.metal` | 79 | 1 | FilmPlacementModule.swift |
| 42 | `LightamerIOP/Sources/FilmicRGB/FilmicRGBKernels.metal` | 374 | 2 | FilmicRGBModule.swift |
| 43 | `LightamerIOP/Sources/Flip/FlipKernels.metal` | 45 | 1 | FlipModule.swift |
| 44 | `LightamerIOP/Sources/Grain/GrainKernels.metal` | 236 | 1 | GrainModule.swift |
| 45 | `LightamerIOP/Sources/Highpass/HighpassKernels.metal` | 65 | 2 | HighpassModule.swift |
| 46 | `LightamerIOP/Sources/Hls/Hls.metal` | 97 | 1 | HlsModule.swift |
| 47 | `LightamerIOP/Sources/Lens/LensKernels.metal` | 307 | 1 | LensModule.swift |
| 48 | `LightamerIOP/Sources/Levels/LevelsKernels.metal` | 53 | 1 | LevelsModule.swift |
| 49 | `LightamerIOP/Sources/Liquify/LiquifyKernels.metal` | 103 | 1 | LiquifyModule.swift |
| 50 | `LightamerIOP/Sources/LocalContrast/LocalContrastKernels.metal` | 66 | 2 | LocalContrastModule.swift |
| 51 | `LightamerIOP/Sources/Lut3d/Lut3dKernels.metal` | 210 | 3 | Lut3dModule.swift; Core/ColorMatch/ColorMatchBake.swift |
| 52 | `LightamerIOP/Sources/Masks/MaskPostProcessKernels.metal` | 120 | 3 | Core/Layers/Masks/MaskCombiner.swift |
| 53 | `LightamerIOP/Sources/Masks/ParametricMaskKernels.metal` | 248 | 2 | Core/Layers/Masks/MaskCombiner.swift |
| 54 | `LightamerIOP/Sources/Monochrome/MonochromeKernels.metal` | 84 | 2 | MonochromeModule.swift |
| 55 | `LightamerIOP/Sources/NLMeans/NLMeansKernels.metal` | 345 | 6 | NLMeansModule.swift |
| 56 | `LightamerIOP/Sources/Passthrough.metal` | 25 | 1 | Passthrough.swift |
| 57 | `LightamerIOP/Sources/Saturation/Saturation.metal` | 54 | 1 | SaturationModule.swift |
| 58 | `LightamerIOP/Sources/Shadhi/ShadhiKernels.metal` | 177 | 2 | ShadhiModule.swift |
| 59 | `LightamerIOP/Sources/Sharpen/SharpenKernels.metal` | 83 | 2 | SharpenModule.swift |
| 60 | `LightamerIOP/Sources/Sigmoid/SigmoidKernels.metal` | 243 | 2 | SigmoidModule.swift |
| 61 | `LightamerIOP/Sources/SkinSmooth/SkinSmoothKernels.metal` | 90 | 1 | SkinSmoothModule.swift |
| 62 | `LightamerIOP/Sources/Soften/SoftenKernels.metal` | 111 | 2 | SoftenModule.swift |
| 63 | `LightamerIOP/Sources/Temperature/TemperatureKernels.metal` | 30 | 1 | TemperatureModule.swift |
| 64 | `LightamerIOP/Sources/TestGain.metal` | 44 | 2 | TestGain.swift（DEBUG only） |
| 65 | `LightamerIOP/Sources/TextOverlay/TextOverlayKernels.metal` | 65 | 1 | TextOverlayModule.swift |
| 66 | `LightamerIOP/Sources/Tint/Tint.metal` | 46 | 1 | TintModule.swift |
| 67 | `LightamerIOP/Sources/ToneCurve/ToneCurveKernels.metal` | 145 | 1 | ToneCurveModule.swift |
| 68 | `LightamerIOP/Sources/ToneEqual/ToneEqualKernels.metal` | 454 | 9 | ToneEqualModule.swift |
| 69 | `LightamerIOP/Sources/Velvia/VelviaKernels.metal` | 60 | 1 | VelviaModule.swift |
| 70 | `LightamerIOP/Sources/Vibrance/VibranceKernels.metal` | 37 | 1 | VibranceModule.swift |
| 71 | `LightamerIOP/Sources/Vignette/VignetteKernels.metal` | 105 | 1 | VignetteModule.swift |
| 72 | `LightamerIOP/Sources/WhiteBlack/WhiteBlack.metal` | 49 | 2 | BlackModule.swift; WhiteModule.swift |
| 73 | `LightamerIOP/Sources/Yiyin/YiyinKernels.metal` | 217 | 4 | BordersModule.swift; WatermarkModule.swift |

### E.2 特殊依赖（逐文件）

| 文件 | 特殊依赖 |
|---|---|
| `LightamerCore/Sources/Metal/RetouchKernels.metal` | `atomic_float` + `atomic_fetch_add_explicit` |
| `LightamerIOP/Sources/Bilateral/BilateralKernels.metal` | `atomic_float` + `atomic_fetch_add_explicit` |
| `LightamerIOP/Sources/Common/BilateralGrid3DKernels.metal` | `atomic_uint` + `atomic_float` + `atomic_fetch_add_explicit` |
| `LightamerIOP/Sources/Common/HistogramReduceKernels.metal` | `atomic_uint` + min/max/load/store |
| `LightamerIOP/Sources/Common/ScopeReduceKernels.metal` | `atomic_uint` + `texture2d<uint, access::write>` |
| `LightamerIOP/Sources/Common/GaussianBlurKernels.metal` | 注释记录 L018 禁用 `read_write`（无实际声明；实际声明仅 `SpectralSpatial`） |
| `LightamerCore/Sources/Pipe/Film/SpectralSpatialKernels.metal` | `texture2d<float, access::read_write>` |
| `LightamerIOP/Sources/Lut3d/Lut3dKernels.metal` | `texture3d<float, access::read>` + `texture1d<float, access::read>` |
| `LightamerCore/Sources/Pipe/Film/FilmSubRunKernels.metal` | `texture3d<float, access::read>`（打印表） |
| `LightamerIOP/Sources/Liquify/LiquifyKernels.metal` | `texture2d<float, access::sample>` |
| `LightamerIOP/Sources/Yiyin/YiyinKernels.metal` | `texture2d<float, access::sample>` |
| `App/Sources/Lightamer/UI/EditorBlitShader.metal` | `[[function_constant(0)]]` + vertex/fragment（非 compute） |
| `LightamerCore/Sources/Pipe/Terminal/TerminalKernels.metal` | `[[function_constant]]` |
| `LightamerIOP/Sources/Passthrough.metal` | `[[function_constant]]` |
| `LightamerIOP/Sources/ToneEqual/ToneEqualKernels.metal` | `[[function_constant]]` |
| `LightamerCore/Sources/Metal/StackKernels.metal` | buffer-only（`focus_sml` 无纹理） |
| `LightamerIOP/Sources/ACEScc/ACESccMath.metal` | header-only，无 kernel，被 `ACESccConvert.metal` include |

## §F UserDefaults 键族（本 lane 7 目录范围：37 键 + 2 前缀；邻近 4 键另列）

| 族 | 键 | 正本 |
|---|---|---|
| AI/图库 | `ai.layerB.downloadPromptChoice`, `library.ai.ratingConfirm`, `library.ai.connection`, `library.ai.strictness`, `library.ai.outputLanguage`, `library.ai.labelingMode` | `AI/AIAssetStatus.swift`; `AI/AIRatingController.swift`; `AI/LibraryConnectionStore.swift`; `Library/LibraryPreferences.swift` |
| 目录/分析 | `catalogs.enabled`, `library.analysis.enabled`, `previews.cacheMB` | `Catalog/CatalogProjector.swift`; `Library/LibraryAnalysisService.swift`; `Decode/SmartPreviewStore.swift` |
| 导入 | `library.import.mode`, `library.import.rememberMode`, `library.import.rawExtensions`, `library.import.categories` | `Library/ImportFilter.swift` |
| 导出 | `export.namingTemplates`, `export.presets`, `export.lastDirectory`, `export.jpegQuality`, `export.heicQuality`, `export.avifQuality`, `export.webpQuality`, `export.postaction.scriptBookmark`, `export.postaction.runScript`, `export.postaction.revealInFinder` | `Export/ExportNamingTemplates.swift`; `Export/ExportPresetStore.swift`; `State/ExportState.swift`; `Export/PostExportActions.swift` |
| 图库/session | `library.recentProjects`, `session.recentPaths`, `browser.sort.key`, `browser.sort.ascending`, `softproof.recent.names` | `Library/LibraryProjectController.swift`; `State/SessionState.swift`; `State/SoftProofState.swift` |
| MCP | `mcp_server_enabled`, `mcp_lan_exposure_enabled` | `MCP/McpServerController.swift` |
| Lensfun/LUT | `lensfun.customPath`, `lensfun.autoApply`, `lut.library.root` | `Session/LensfunDownloadService.swift`; `Lens/LensModule.swift`; `Lut3d/LutLibraryStore.swift` |
| 蒙版/印框 | `mask.fineAuto`, `yiyin.sheet.widthRatio`, `yiyin.sheet.heightRatio` | `State/MaskRefineCoordinator.swift`; `State/YiyinSheetMetrics.swift` |
| 应用/显示 | `app.cleanTerminate`, `display.override.icc.<hash>`（前缀）, `orphanIgnore/<path>`（前缀） | `State/CleanTerminateSentinel.swift`; `Foundation/ManualDisplayOverrideStore.swift`; `Session/SessionIndexStore.swift` |
| 邻近（不计入 37） | `mask.behavior.default`, `catalogs.databasePath`, `organization.mode`, `keyboard.override.`（前缀） | `Settings/AppPreferences.swift`; `Catalog/CatalogPreferences.swift` |

## §G MCP 34 工具（名称 / 域 / 控制权 / 主参数）

> 逐字 JSON Schema 正本 = `Tests/LightamerTests/McpFinalSnapshotTests.swift`；下表只列主参数/必填面，`*` = 该域 schema 里可选但常用。

| 工具 | 域 | requiresControl | 主参数 |
|---|---|---|---|
| `load_image` | editing | 是 | `relPath` |
| `apply_params` | editing | 是 | `relPath`, `ops[{opName, params, enabled, remove, multiPriority}]`, `note`* |
| `copy_adjustments` | editing | 否 | `source` |
| `paste_adjustments` | editing | 是 | `source`, `targets[]`, `note`*, `include[]`*, `includeDrt`* |
| `export_image` | editing | 是 | `relPath`, `format`, `quality`*, `sizing`*, `colorSpace`*, `yiyin`* |
| `render_preview` | editing | 否 | `relPath`, `longEdge`*, `quality`*, `roi`* |
| `get_schema` | editing | 否 | 无 |
| `list_iops` | editing | 否 | 无 |
| `list_luts` | editing | 否 | 无 |
| `refine_masks` | editing | 是 | `relPath`, `maskIds[]`, `region`*, `strength`* |
| `match_color` | editing | 是 | `reference`, `targets`*, `strength`*, `solver`* |
| `list_photos` | culling | 否 | `cursor`*, `filter`*, `limit`*, `sort`* |
| `list_presets` | culling | 否 | `kind`* |
| `apply_preset` | culling | 是 | `presetID`, `relPaths[]`, `mode`*, `selection[]`* |
| `diff_presets` | culling | 否 | `presetIDA`, `presetIDB` |
| `get_thumbnails` | culling | 否 | `relPaths[]`, `regenerate`* |
| `get_contact_sheet` | culling | 否 | `relPaths[]`*, `filter`*, `sort`*, `cols`*, `rows`* |
| `get_detail_crop` | culling | 否 | `relPath`, `roi{x,y,w,h}`, `longEdge`* |
| `list_bursts` | culling | 否 | `gapSeconds`* |
| `get_face_regions` | culling | 否 | `relPaths[]`, `includeLandmarks`* |
| `set_rating` | culling | 是 | `relPaths[]`, `rating`（0–5/null） |
| `set_flag` | culling | 是 | `relPaths[]`, `flag`（0/1/2/null） |
| `set_color_label` | culling | 是 | `relPaths[]`, `color`（0–6/null） |
| `append_note` | culling | 是 | `relPaths[]`, `note` |
| `set_keywords` | culling | 是 | `relPaths[]`, `keywords[]/null` |
| `search_photos` | search/state | 否 | `query`, `mode`*, `limit`*, `cursor`*, `sort`* |
| `get_history` | search/state | 否 | `image`, `includeParams`*, `limit`* |
| `get_state` | search/state | 否 | 无 |
| `project_open` | project | 是 | `path` |
| `project_create` | project | 是 | `folder`, `name` |
| `list_versions` | project | 否 | `image`, `includeItems`* |
| `control_acquire` | control | 否 | `holder_name`* |
| `control_release` | control | 否 | 无 |
| `control_get` | control | 否 | 无 |

> `requiresControl` 实际 14 个（上表标“是”的 14 行）；`McpControlToolsetTests.controlCandidateTools` 的 13 名单是 `refine_masks` 之前的陈旧集，测试只断言候选被 gate，不排除额外 gate。

## §H `.lalb` 表结构（`user_version = 6`）

| 对象 | 列 / 形态 |
|---|---|
| `project_meta` | `key TEXT PRIMARY KEY`, `value TEXT` |
| `images` | `id INTEGER PK`, `image_path`, `path_kind`, `volume_uuid`, `camera_make/model`, `lens_model`, `iso`, `focal_length`, `aperture`, `exposure`, `capture_date`, `file_stem/ext`, `exif_search_text/words`, `rating`, `color_label`, `keywords`, `filename`, `dir`, `flag`, `note`, `has_edits`, `params_hash TEXT`, `ref_count`, `added_time`, `modified_time`, `default_look_pending`, `analysis_version`, `sharpness`, `faces`, `eyes_closed`, `signature BLOB`, `face_boxes`, `camera_serial` |
| `albums` | `id`, `type`, `name`, `parent_id`, `filter_data`, `added_time`, `modified_time` |
| `album_content` | `album_id`, `image_id`，PK 二者，`WITHOUT ROWID` |
| `version_ref` | `version_id TEXT PK`, `element_id INTEGER FK images`, `display_name`, `created_at_unix`, `updated_at_unix` |
| `stacks` | `id`, `collapsed`, `added_time`, `modified_time` |
| `stack_content` | `stack_id`, `image_id`, `position`，PK(stack_id,image_id)，`WITHOUT ROWID`；`position 0` = 封面 |
| `semantic_model` | `model_key PK`, `model_id`, `revision`, `embedding_dim`, `image_size`, `prompt_config_hash`, `active` |
| `image_embedding` | `image_id`, `model_key`, `dim`, `embedding BLOB`, `computed_time`，PK(image_id,model_key) |
| `image_label` | `image_id`, `model_key`, `label`, `score`, `second_label`, `second_score`, `margin`, `confident`, `top_scores`，PK(image_id,model_key,label) |
| `label_query` | `model_key`, `label`, `query_text`, `lang`，PK(model_key,label,lang) |
| `ai_understanding` | `id PK`, `image_id`, `task_id`, `provider_id`, `model_id`, `prompt_profile_id`, `rendition_kind`, `caption`, `tags`, `scene`, `confidence`, `active`, `computed_time`，UNIQUE(image_id,task_id) |
| `ai_rating` | `id PK`, `image_id`, `task_id`, `provider_id`, `model_id`, `prompt_profile_id`, `rating`, `reasons`, `computed_time` |
| `images_fts` | FTS5 external-content：`exif_search_words`，`content='images'`, `content_rowid='id'`，`unicode61`；3 个同步触发器 |
| `ai_understanding_fts` | FTS5 external-content：`caption`, `tags`，`content='ai_understanding'`, `content_rowid='id'`；3 个同步触发器 |

写入：WAL + `synchronous=NORMAL`；close → `journal_mode=TRUNCATE`（实现见 `ProjectFileStore`）；迁移前 `sqlite3_backup` 快照；`backup(to:)` 在线一致性拷贝。正本：`LibrarySchema.swift`（DDL）、`ProjectFileStore.swift`（生命周期）。

## §I 测试明细

### I.1 按 target（实计，不是 BUNDLE-MAP 的陈旧 method 列）

| Target | 文件 | 方法 | 主要性质 |
|---|---:|---:|---|
| `LightamerTestsIOPParity` | 84 | 587 | kernel golden/parity（AgX/Ashift/Bilateral/BlendOp/ColorBalance/ColorMatch/ColorWheels/Crop/Denoise/DRT/Equalizer/Filmic/Flip/Grain/HDR/Lens/LUT/NLMeans/Spectral/ToneEqual…） |
| `LightamerTestsIOP` | 100 | 843 | iop 行为、参数、数学、部分 golden |
| `LightamerTestsLayers` | 67 | 576 | 图层/蒙版/retouch/mask kernel |
| `LightamerTestsLibrary` | 83 | 802 | `.lalb` v1–v6、导入、EXIF 搜索、分析、stack（含 3 个 BUNDLE-MAP 未登记文件） |
| `LightamerTestsSessions` | 26 | 289 | session 索引 v2、过滤 SQL、缩略图、智能相册 |
| `LightamerTestsExport` | 40 | 391 | 六格式编码、DRT 输出、元数据、命名、碰撞 |
| `LightamerTestsApp` | 127 | 1,135 | App 状态/面板/宿主/菜单/可访问性 |
| `LightamerUITests` | 1 | 3 | XCUITest |

> 7 target 文件列 527 + 3 个零测试 SHARED helper（`Fixtures`/`ParityGate`/`ChainBuilderHelpers` 跨 target 重复列出）= 530；方法 4,623。BUNDLE-MAP 的 83/581 + 101/849 把 `LutEncodingExpansionTests` 仍标在 IOP；3 个未登记文件（`ImportTransportTiffTests`/`LibraryDocumentTests`/`MetadataTests`）在 Project.swift 归 LIB，已计入 83/802。

### I.2 Golden / Parity 命名（61 文件 / 429 方法）

- Golden（28 文件 / 204 方法）：`Aces2KernelGoldenTests`, `BWSpectralGoldenTests`, `ColorMatchBakeGoldenTests`, `ColorMatchSolverGoldenTests`, `ColorWheelsToneWheelGoldenTests`, `ColormatchIdentityGoldenTests`, `CullingAnalysisGoldenTests`, `DepthGoldenTests`, `DrtKernelGoldenTests`, `ExportEncoderGoldenTests`, `FilmGoldenTests`, `GeometryGoldenTests`, `GoldenColorTests`, `GoldenParityTests`, `GradeKernelGoldenTests`, `LensDefaultNeutralGoldenTests`, `LensProjectionGoldenTests`, `LensScaleGoldenTests`, `Lut3dGoldenImageTests`, `MertensFusionGoldenTests`, `PanoGoldenTests`, `SpectralBuildGoldenTests`, `SpectralClampedGoldenTests`, `SpectralCrossArmGoldenTests`, `SpectralDualArmGoldenTests`, `SpectralGrainGoldenTests`（其余 2 个同族 golden 见目录）。
- Parity（34 文件 / 230 方法）：`AshiftParity`, `BilateralParity`, `BlendOpParity`, `ChannelMixerColorContrastParity`, `ChannelMixerRGBParity`, `ColisaParity`, `ColorBalanceRGBParity`, `ColorZonesParity`, `ColormatchKernelParity`, `CropParity`, `DenoiseProfileParity`, `EqualizerParity`, `FlipParity`, `GoldenParity`, `LensParity`, `LevelsParity`, `LiquifyParity`, `McpMatchColorParity`, `McpRenderParity`, `MonochromeParity`, `NLMeansParity`, `NSMenuParity`, `ParametricMaskParity`, `ParityGate`, `RasterKernelParity`, `RetouchParity`, `ShadhiParity`, `SharpenParity`, `SkinSmoothParity`, `TemperatureParity`, `ToneCurveParity`, `ToneEqualParity`, `UprightModuleParity`, `VibranceVelviaParity`（名称按目录实际为准）。
- 注意：`GoldenParityTests` 同时命中两类；`NSMenuParity` 是 AppKit 菜单，不是图像 golden。`ParityGate.swift` 是零测试 helper，故“61 文件”= 60 个测试文件 + 该 helper。
- 按 target 的 Golden/Parity 分布（文件/方法）：IOPP 53/374、LAYERS 2/16、LIB 1/4、EXPORT 1/17、APP 3/18；IOP/SESS/未映射为 0。

### I.3 UI / 框架依赖

- import SwiftUI/AppKit 的测试 20 文件：`AgentControlCoordinatorTests`, `BeforeAfterTests`, `CullingPipelineTests`, `DrtViewportTests`, `EDRViewportTests`, `ExportCollisionPickerTests`, `ExportInspectorFaceTests`, `FilmPanelSpectralUITests`, `LibraryAnalysisWiringTests`, `MenuBridgeObservationTests`, `NSMenuParityTests`, `NodeCanvasGeometryTests`, `ProjectReadOnlyFaceTests`, `RasterHdrViewportTests`, `SessionSwitchTests`, `SheetEnvironmentInjectionTests`, `ShellGraphMigrationTests`, `ShellWindowControllerSmokeTests`, `ThemeTokensTests`, `ToastFaceTests`。
- import Vision/CoreML 的测试 7 文件：`AIMaskDeterminismTests`, `AIMaskSemanticTests`, `AIWorkerClientTests`, `DepthGoldenTests`, `DepthPerfProbeTests`, `PersonInstanceMaskTests`, `VisionDetectTests`。
- import Metal 的测试 211 文件；import CoreImage 99；import ImageIO 30。

### I.4 可直接作 Rust 验收对照的判据

- 纳入：非 `LightamerTestsApp` target、无 SwiftUI/AppKit import、输入是 fixture/临时文件、输出是像素/JSON/字节的断言。400 文件 / 3,455 方法。
- 强候选：其中不 import Metal 的 233 文件 / 2,121 方法（纯 CPU/数学/SQL/JSON）。
- 排除：`LightamerTestsApp` 的 1,135 方法（`EditorState`/`LayerEditingState`/面板/菜单/可访问性）、20 个 SwiftUI/AppKit import 文件、`LightamerUITests` 3 方法、依赖屏幕 EDR/真实窗口的用例。

## §J Q6 逐模块主导档与混合行数（估）

| 模块 | 总行 | 主导档 | 纯 | 着色器宿主 | Apple 适配 | UI |
|---|---:|---|---:|---:|---:|---:|
| Core AI | 8,102 | 纯逻辑（混合） | 5,285 | 99 | 2,718 | 0 |
| Core Catalog | 2,907 | 纯逻辑 | 2,907 | 0 | 0 | 0 |
| Core ColorMatch | 1,609 | 纯逻辑 | 1,609 | 0 | 0 | 0 |
| Core Decode | 4,049 | Apple 适配 | 616 | 0 | 3,434 | 0 |
| Core Export | 6,491 | Apple 适配 | 1,963 | 0 | 4,528 | 0 |
| Core Film | 5,093 | 纯逻辑 | 5,093 | 0 | 0 | 0 |
| Core Foundation | 1,697 | 纯逻辑（混合） | 990 | 0 | 707 | 0 |
| Core Graph | 1,548 | 纯逻辑 | 1,548 | 0 | 0 | 0 |
| Core Layers | 4,474 | 着色器宿主（混合） | 1,761 | 2,451 | 262 | 0 |
| Core Library | 7,853 | 纯逻辑（混合） | 6,903 | 0 | 950 | 0 |
| Core Metal | 1,402 | Apple 适配 | 68 | 33 | 1,301 | 0 |
| Core Pipe | 17,758 | 纯逻辑（混合） | 8,796 | 5,879 | 3,083 | 0 |
| Core Presets | 654 | 纯逻辑 | 654 | 0 | 0 | 0 |
| Core Session | 5,720 | 纯逻辑（混合） | 3,316 | 0 | 2,404 | 0 |
| Core Sidecar | 2,127 | 纯逻辑（混合） | 1,797 | 0 | 330 | 0 |
| Core Stack | 9,403 | 纯逻辑（混合） | 5,447 | 247 | 3,710 | 0 |
| IOP（全） | 36,719 | 着色器宿主 | 0 | 34,516 | 2,203 | 0 |
| App AI | 3,924 | UI（混合） | 883 | 0 | 1,497 | 1,544 |
| App Export | 3,312 | UI | 480 | 0 | 0 | 2,832 |
| App Library | 6,567 | UI | 452 | 0 | 286 | 5,829 |
| App MCP | 10,280 | 纯逻辑（混合） | 7,158 | 0 | 3,122 | 0 |
| App Session | 2,372 | UI（混合） | 1,076 | 0 | 0 | 1,296 |
| App State | 10,956 | UI | 918 | 0 | 686 | 9,352 |
| App Yiyin | 1,031 | UI | 0 | 0 | 0 | 1,031 |

> 主导档 = 该目录行数最多的档；不是把整个目录判死。四档合计 59,720 / 43,225 / 31,221 / 21,884 = 156,050。估 ±10–15%。

## §K 数字复现命令

```bash
# 总量
find LightamerCore/Sources -name '*.swift' | wc -l
find LightamerCore/Sources -name '*.swift' -print0 | xargs -0 cat | wc -l
find LightamerIOP/Sources -name '*.swift' | wc -l
find LightamerIOP/Sources -name '*.swift' -print0 | xargs -0 cat | wc -l
find App/Sources/Lightamer/{AI,Export,Library,MCP,Session,State,Yiyin} -name '*.swift' | wc -l
find App/Sources/Lightamer/{AI,Export,Library,MCP,Session,State,Yiyin} -name '*.swift' -print0 | xargs -0 cat | wc -l

# Metal
find . -name '*.metal' -not -path './.git/*' -not -path './.work/*' | wc -l
find . -name '*.metal' -not -path './.git/*' -not -path './.work/*' -print0 | xargs -0 wc -l | tail -1
grep -rho 'kernel void [A-Za-z0-9_]*' --include='*.metal' LightamerCore LightamerIOP App | wc -l

# 逐目录（Core）
for d in LightamerCore/Sources/*/; do printf '%s ' "$d"; find "$d" -name '*.swift' | wc -l; find "$d" -name '*.swift' -print0 | xargs -0 cat | wc -l; done

# Apple 依赖（示例；完整正则见 §D）
grep -rc 'CIRAWFilter' LightamerCore/Sources LightamerIOP/Sources App/Sources/Lightamer/{AI,Export,Library,MCP,Session,State,Yiyin} | grep -v ':0$'
grep -rc 'CGImageSource' ... ; grep -rc 'CGImageDestination' ...
grep -rc 'MTL[A-Z]' ... ; grep -rc 'VN[A-Z]' ... ; grep -rc 'MLModel' ...

# 测试
grep -rho 'func test[A-Za-z0-9_]+' Tests/LightamerTests --include='*.swift' | wc -l
grep -rho '@Test' Tests/LightamerTests --include='*.swift' | wc -l
ls Tests/LightamerTests | grep -E 'Golden|Parity' | wc -l
grep -rl 'import SwiftUI\|import AppKit' Tests/LightamerTests --include='*.swift' | wc -l

# 契约
grep -n 'schemaVersionCurrent' LightamerCore/Sources/Sidecar/LightamerSidecar.swift
grep -n 'schemaVersion' LightamerCore/Sources/Library/LibrarySchema.swift | head
grep -n 'schemaVersion' LightamerCore/Sources/Session/SessionIndexSchema.swift | head
grep -rn 'requiresControl' App/Sources/Lightamer/MCP/Tools/*.swift
grep -n '30\|34' Tests/LightamerTests/McpFinalSnapshotTests.swift | head
```

> 注：`grep -rc` 统计的是“行命中”，§D 的“处”是同一行内重复计数的正则命中；两者会差少量。本盘点 §D 用后者，模块总量用前者。
