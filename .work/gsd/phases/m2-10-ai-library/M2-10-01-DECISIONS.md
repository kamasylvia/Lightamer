# M2-10-01 DECISIONS — 执行期裁决与偏离签注

> 状态：执行波 worker 落盘，晨审可推翻。正本 plan = 同目录
> `M2-10-01-PLAN.md`；spike 数字正本 = `M2-10-01-SPIKE.md`。

## 1. Real-ESRGAN 打包格式 = mlprogram（A/B 平级裁决）

x4plus 256² tile 20 次中位：mlprogram 62.83ms vs neuralnetwork 62.35ms——
差 0.8%，噪声带内，**coremltools#2545（mlprogram 逆优化）在本机未复现**。
采纳 **mlprogram** 为超分/降噪族打包格式：①与 iOS18 deployment target 对齐；
②后续 int8 per-block 量化仅 mlprogram 支持；③实测零延迟差。
general-x4v3 已按 mlprogram 转换内置（20.55ms/tile）。M2-10-06 实测若推翻，
重转换 = 单脚本一次（`--format neuralnetwork` 腿已就位）。

## 2. 转换入口 = torch trace，非 ONNX 文件中转（KD-2 语义偏离签注）

KD-2 原文「官方 ONNX 导出语义 → coremltools.convert」。实际入口 =
`torch.jit.trace` 直转（coremltools torch frontend），**图语义逐条保持
KD-2 处方**：静态形状（224²/52tok/256²）、seq 52、L2 收进图、int8 只量权重。
偏离收益 = 省 onnx 依赖（依赖最小化红线）+ 少一次 ONNX opset 兼容面。
风险 = 无 ONNX 中间产物可交叉验证；M2-10-02 的 golden 测试承担语义验证。

## 3. digest 算法：目录 artifact = canonical tree hash

KD-2 原文「digest 对最终分发字节（.mlpackage 压缩包）计算」。bundled 档
分发形态 = **解包目录**（folder reference 零安装，KD-3「bundled 优先…命中
即返（零下载零安装）」），故 digest 定义为：文件 = 文件 SHA-256；目录 =
canonical tree hash（sorted posix relPath，逐文件 `<relpath> <size> <sha256>\n`
拼接后 SHA-256；byteCount = 递归字节和）。**Python（build_default_bundle.sh）
与 Swift（`ModelAssetStore.artifactDigestHex`）双侧同构实现并在真实 app
bundle 上互验通过**（ModelAssetCatalogTests 资源门激活态）。Release 档为
单文件 zip，digest = 纯文件 SHA-256，KD-2 原文无偏离。

### 3.1 DigestEntry 增 `auxiliaryFiles`（KD-1 字段形状扩展签注）

KD-1 的 DigestEntry = `sha256Hex + byteCount + generatedAt`（单文件语义）。
bundled CLIP 档 = img + txt + vocab 三件套，单字段不可锁全量 → 增
`auxiliaryFiles: [FileEntry]`（name+sha256+bytes，主件外的同目录随行文件）。
KD 三字段名与语义原样保留（primary = assetFileName）。Store 校验走 primary +
全部 auxiliary。

## 4. 路径拼写归一化（执行期真缺陷，L039/L027 同族）

测试宿主经 test-direct.sh 启动，launch path 含 `Debug//Lightamer.app` 双斜杠：
`URL.path` **保留**冗余分隔符，`FileManager.enumerator` 物理化时（realpath）
**折叠**——tree-hash 的 prefix 匹配全数失败静默退化 lastPathComponent（字节
总量守恒所以不炸、只有 hash 不符）。修复 = prefix 比较前两侧统一折叠 `//+`
与尾斜杠。教训已沉淀 LESSONS L039 增补。

## 5. 任务边界偏离（三处，均 commit body 申报）

1. **T1 吸收 T4 接线**：`.keep` + `.gitignore` + Project.swift
   folderReference + LIB 登记 + generate 提前到 T1（T2 体积红线机检
   「git status 零模型字节」依赖 gitignore 先行；KD-4 generate-after-files
   顺序保持）。T4 保留验证与收口。
2. **T3 先于 T2 提交**（`6a7e81e` < `318a473`）：T3 代码不消费 T2 产物
   （digest 经注入缝），转换链为长杆后台任务；git 序不影响审计（每提交
   自洽、SUMMARY 记账）。
3. **T2 携带 T3 修正**：tree-hash 拼写修复（`ModelAssetStore.swift`）与
   CatalogTests 消费改造随 T2 提交（修正属 digest 互验链路的功能性必需，
   commit body 已申报）。

## 6. Release 上架维护者清单（phase 后动作；fail-closed 的解除条件）

上传目标 = 本仓 GitHub Release **`ai-models-v1`**（catalog `releaseTag`）。
转换命令（缓存目录备好权重后）：

```bash
uv run --with "torch==2.7.*" --with coremltools --with numpy \
  python Scripts/ai-models/convert_real_esrgan.py --model x4plus \
  --weights ~/Library/Caches/LightamerModels/realesrgan/RealESRGAN_x4plus.pth \
  --out <dir> --format mlprogram --benchmark
# jina：无需转换——HF 官方 onnx/model_int8.onnx（874,350,932 B）zip 后上架
uv run --with "torch==2.7.*" --with coremltools --with numpy \
  python Scripts/ai-models/convert_real_esrgan.py --model drunet-color \
  --weights <KAIR drunet_color.pth> --out <dir> --format mlprogram
```

| 资产名 | 内容 | 上架前必核 |
|---|---|---|
| `jina-clip-v2-int8.mlpackage.zip` | HF onnx int8 转 mlpackage 后压缩（或直接 zip ONNX + 02 走 onnxruntime？——**须先裁**：当前 Store 契约 = zip 内 mlpackage） | 转换/打包方式定稿 |
| `real-esrgan-x4plus-fp16.mlpackage.zip` | converted/real-esrgan-x4plus-fp16.mlpackage（本机已转换，`~/Library/Caches/LightamerModels/converted/`） | SHA-256 回填 digests |
| `drunet-color-fp16.mlpackage.zip` | 未转换（DRUNet 权重未下载；脚本已支持） | KAIR 权重路径核实（hfFallback `cszn/KAIR` + `drunet_color.pth` 为占位拼写，上架时核对该仓 release 资产实名） |

上架后：跑 build_default_bundle.sh 的 digest 算法（或手算文件 SHA-256）回填
`ModelAssetDigests.generated.swift` 三个 `= nil` 哨兵 → fail-closed 解除、
M2-10-07 LCR 页下载入口放行。digest 未回填前 UI 恒「待发布」。

## 7. manifest 字段取值签注

- **ESRGAN 族 modelID = 上游 git 仓**（`xinntao/Real-ESRGAN`，revision =
  release tag `v0.1.0`/`v0.2.5.0`）——非 HF 仓（该族原生分发在 GitHub
  Releases；modelID 语义按「上游模型仓 id」从宽执行）。hfFallback 指向
  HF 镜像仓（x4plus = `schwgHao/RealESRGAN_x4plus`、general =
  `qualcomm/Real-ESRGAN-General-x4v3`）——**本轮权重实取自 GitHub 官方
  release（URL 200 实测），镜像仓未经字节核验**，仅作兜底拼写；上架时
  digest 以本仓 Release 资产为准，兜底源字节若不一致即兜底失效（fail-closed
  拦截，不产生静默错装）。
- **jina revision = `e10d47f5691d0454a0fb5d13f46f2199b74cb436`**（hf-mirror
  resolve 响应 `x-repo-commit` 头实取；与 Alcedo `model_asset_catalog.cpp`
  的 pin 前缀一致）。
- **DRUNet revision = `v1.1`**（KAIR 标签占位；上架时核实）。
- **超分族 inputSize = 256**（tile 形状族基准；M2-10-06 族 = {256, 512}，
  256 = 基准档，消费方读 manifest）。
- **jina inputSize = 512**（RESEARCH §1.4：512×512）。

## 8. 消费契约交接（M2-10-02/03/06 读此节）

- **CLIP 图塔**：输入 = 已归一化 pixel_values——消费方 resize 到
  manifest.inputSize 后按 mean=(0.48145466,0.4578275,0.40821073) /
  std=(0.26862954,0.26130258,0.27577711)（RGB、[0,1] 域）归一化。
- **CLIP 文本塔**：输入 = input_ids int32[1,52] + **展开 float32
  attention mask [1,1,52,52]**（kv 轴广播 1D padding mask；图内 `>0.5`）。
  输出已 L2 归一化（norm=1 实测），消费方零归一化负担。
- **词表**：`vocab.txt`（BERT WordPiece，21128 token）随包；tokenizer 自实现
  归 M2-10-02（D-8）。
- **label 原型占位**：`AIModels/chinese-clip-vitb16-int8/prototypes/`（README
  占位）；真原型 = M2-10-03，与模型 revision 同生共死。
- **超分/降噪**：静态 1×3×256×256 → 1×3×1024×1024；tile 编排归 M2-10-06。

## 9. 质量抽查 inconclusive 的处置

合成线稿余弦平票（0.32-0.35 带），spike ③如实记 inconclusive；管线端到端
（前向/归一化/余弦）验证成立。真图相对序验证归 M2-10-02 golden 测试
（真实照片 fixture）。KD-2 原文「人读判断，非阈值断言」满足。

## 10. 越界文件申报

front-matter 申报集内零越界。`ModelAssetStore.swift`（T3 申报文件）与
`ModelAssetCatalogTests.swift`（T1 申报文件）的 T2 批改动 = §4/§3.1 所述
功能性必需，随 T2 commit body 申报。工作区滞留（非本批）：`IMG_3061..3063.ARW`
（仓根，用户文件，未触碰）、`.work/gui-acceptance/09-3-tiers-*.jpg` 两文件
（前波遗留，GOAL-STATE 在案）。
