# Scripts/ai-models — AI 模型资产转换与内置打包

Plan M2-10-01。本目录脚本族从上游权重重建 `Resources/AIModels/` 内置模型资产
（模型字节永不入 git——体积红线），并重写
`LightamerCore/Sources/AI/ModelAssetDigests.generated.swift` 的 digest 锁。

## 资产与许可

| profile | 上游 | revision | 许可 | 档位 |
|---|---|---|---|---|
| `chinese-clip-vitb16-int8` | HF `OFA-Sys/chinese-clip-vit-base-patch16` | `36e679e65c2a2fead755ae21162091293ad37834` | Apache-2.0 | 内置（OQ-1-B 质量档） |
| `realesr-general-x4v3-fp16` | GitHub `xinntao/Real-ESRGAN` release v0.2.5.0 | tag pin | BSD-3-Clause | 内置（OQ-3-B 快速档） |
| `real-esrgan-x4plus-fp16` | GitHub `xinntao/Real-ESRGAN` release v0.1.0 | tag pin | BSD-3-Clause | Release（A/B spike 用） |
| `jina-clip-v2-int8` | HF `jinaai/jina-clip-v2` | `e10d47f5691d0454a0fb5d13f46f2199b74cb436` | Apache-2.0 | Release（本仓 GitHub Release 上架） |
| `drunet-color-fp16` | GitHub `cszn/KAIR` | - | MIT | Release（脚本支持，转换未执行） |

## 复现步骤

```bash
# 0. 缓存目录（三目录分工沿 Lumen host.py 同型；可重建）
mkdir -p ~/Library/Caches/LightamerModels/{chinese-clip,realesrgan}

# 1. 拉取权重（revision/tag 双锁；huggingface.co 不可达时换 hf-mirror）
REV=36e679e65c2a2fead755ae21162091293ad37834
for f in pytorch_model.bin config.json vocab.txt preprocessor_config.json; do
  curl -L -o ~/Library/Caches/LightamerModels/chinese-clip/$f \
    "https://hf-mirror.com/OFA-Sys/chinese-clip-vit-base-patch16/resolve/$REV/$f"
done
curl -L -o ~/Library/Caches/LightamerModels/realesrgan/RealESRGAN_x4plus.pth \
  "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth"
curl -L -o ~/Library/Caches/LightamerModels/realesrgan/realesr-general-x4v3.pth \
  "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesr-general-x4v3.pth"

# 2. 一键：转换 → 组装 Resources/AIModels → 重写 digests
Scripts/ai-models/build_default_bundle.sh

# 3. 验证：LightamerCore 编译 + LIB bundle 测试
#    （ModelAssetCatalogTests 的 bundled digest/盘上一致性断言此时激活）
```

单步转换（调参用）：

```bash
uv run --with torch --with transformers --with coremltools --with numpy --with pillow \
  python Scripts/ai-models/convert_chinese_clip.py \
  --weights-dir ~/Library/Caches/LightamerModels/chinese-clip \
  --out ~/Library/Caches/LightamerModels/converted --benchmark

uv run --with torch --with coremltools --with numpy \
  python Scripts/ai-models/convert_real_esrgan.py \
  --model x4plus --weights ~/Library/Caches/LightamerModels/realesrgan/RealESRGAN_x4plus.pth \
  --out ~/Library/Caches/LightamerModels/converted --format both --benchmark
```

## 契约（KD-2，勿改）

- **静态形状**：CLIP 图塔 1×3×224×224（E4 实证值 = manifest `inputSize`）、
  文塔 seq 52；超分 tile 1×3×256×256。flexible shapes 伤 ANE（coremltools#1764）。
- **CLIP 文本塔 mask 契约**：输入 = **展开后的 float32 [1,1,52,52]**（kv 轴
  padding mask；图内 `>0.5` 转 bool）。2D mask 会走现代 masking-function
  管线，其 `new_ones` op coremltools 无法转换（torch 2.7 实测）。Swift 消费方
  （M2-10-02）把 1D padding mask 沿 kv 轴展开即可。
- **CLIP 图塔预处理契约**：模型吃**已归一化**的 pixel_values——消费方先
  resize 到 manifest `inputSize`，再按 preprocessor_config.json 常数归一化：
  mean = (0.48145466, 0.4578275, 0.40821073)，std = (0.26862954, 0.26130258,
  0.27577711)，RGB、[0,1] 输入域。
- **int8 只量权重**（激活保 fp16；int8 激活需 A17 Pro/M4+）；超分族纯 fp16。
  per_block 粒度要求 `minimum_deployment_target ≥ ct.target.iOS18`（本仓
  macOS 27 地板下无兼容负担）。
- **L2-normalize 收进图**：CLIP 两塔输出已归一化（norm=1 实测验证），消费方
  零归一化负担（D-M2-10-CONTEXT-8）。
- **转换入口 = torch trace**（非 ONNX 文件中转）：图语义与官方 ONNX 导出一致
  （静态形状同参），省 onnx 依赖；偏离已记 M2-10-01-DECISIONS。torch 钉
  2.7.x（coremltools 官方测试矩阵上限）。
- **digest 对最终分发字节计算**：文件 = 文件 SHA-256；目录（.mlpackage）=
  canonical tree hash（sorted relPaths，逐文件 `<relpath> <size> <sha256>\n`
  拼接后 SHA-256）。Swift 侧 `ModelAssetStore` 同规则实现，两侧互验。

## 实测落账位

转换/延迟/体积实测数字记录于
`.work/gsd/phases/m2-10-ai-library/M2-10-01-SPIKE.md`（每次重跑后更新该文件，
勿在本 README 内堆积数字）。

## 上架清单维护者动作（phase 后）

Release 三档（jina / x4plus / drunet）转换完成后，把压缩包上传本仓 GitHub
Release `ai-models-v1`，并在 `ModelAssetDigests.generated.swift` 里回填对应
digest（把 `= nil` 哨兵换成脚本产出的 literal，同 build_default_bundle.sh
第 3 步的算法）。digest 未发布 = App 内下载面显示「待发布」（fail-closed）。
