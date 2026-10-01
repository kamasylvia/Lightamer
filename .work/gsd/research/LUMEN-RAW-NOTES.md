# Lumen RAW 调研速记（2026-10-01）

> 来源：github.com/hety0211/lumen-raw（MIT，Windows 独占，Python 3.12 + PySide6 + NumPy/OpenCV/rawpy/LibRaw + ONNX Runtime，DirectML/TensorRT/CPU 三级，v1.3.1，193 回归测试）。面向风光/旅修的本地 RAW 工作台，中文界面。

## 与 Lightamer 的重叠面（不借鉴——我方已超集）
LibRaw 解码（我=CIRAW 9）/ Qt UI（SwiftUI）/ CPU spatial 算子（我=Metal 全 GPU）/ 分级 stage 缓存（我=per-module per-ROI + GAC 更细）/ 修图与快照 / 编辑同步 / 水印边框（yiyin 超集）/ 蒙版（我=M2-7 超集：brush/gradient/luminance/color-range/AI subject/Follow Edges）/ DRT（我=M2-6 OpenDRT+ACES 2.0，Lumen 无 DRT）/ 版本历史（M2-8）/ SQLite 库（M2-2）。

## 可借鉴候选（按价值排序，待用户裁决后入 REQUIREMENTS）
1. **单目深度 → IOP-MASK-07 数据面解锁**：Lumen 用 MiDaS 出 relative-depth 前景选择。我方 Depth 蒙版当时因「桌面 RAW 深度源稀缺」挂账——MiDaS 级单目深度（ONNX→CoreML）是现成解法，AI Background/Depth 蒙版可解锁。
2. **Mertens 曝光融合**：无 CRF 快速 HDR（三档 deghosting）——Phase 8 是 Robertson02 辐射图法，Mertens 可作第二合并模式（快/免 CRF 估计）。
3. **全景合成**：SIFT + 相机优化 + 球面投影 + 分块羽化（200MP 上限）——我方合成族（Phase 8：景深/堆栈）无全景，V2 候选。
4. **线性 RGB DNG 导出**：我方导出矩阵（JPG/PNG/TIFF/HEIF/WebP/AVIF）无 DNG 导出；Lumen/暗房类均支持 16-bit linear DNG（互操作/回传其他软件）。
5. **AI 增强的「可编辑 DNG 副本」UX**：Real-ESRGAN 超分 + DRUNet/NAFNet 降噪在独立预览对话框出片，结果作为新条目插入胶片条可继续编辑——M2-10 AI 图库之外的「AI 出片入工作流」模式。
6. **Crash-safe AI worker 进程隔离**：神经模型跑独立 worker 进程，GPU 驱动/EP 崩溃编辑器不死、tile 换设备重试、记住 GPU+driver 组合——M2-10 在 app 内跑 CLIP/推理时的健壮性范式。
7. **统一冲突表 + 单作业调度器**（加载/导出/AI/合并/蒙版推理/预览/缩略共用）——概念上近我方 BackgroundTaskHosting + L031 路由，已覆盖，仅记录。

## 明确不借鉴
AI 作用域 = developed RGB 非 mosaic（我方 RAW 9 在解码层融合降噪更强）；TensorRT EP 目录（Windows 专属）；运行时生成 GPU 图（Python 特定）；CuPy 实验分支。

## 裁决（2026-10-01 用户）

候选 1/2/3/5/6 **全部采纳**（登记：IOP-MASK-07 MiDaS 解锁注记 + 新「Photo Merging Extensions (v2)」节 IOP-HDR-06/IOP-PANO-01 + M2AI-09/M2AI-10 + ROADMAP M2-10 行扩充）；**候选 4（16-bit linear DNG 导出）不采纳**。
