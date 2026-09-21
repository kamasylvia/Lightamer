# NoiseProfiles 数据来源与许可注记（D-05-CONTEXT-2 / 05-01-T3）

## 数据来源

- 上游：darktable `data/noiseprofiles.json`（树 `dc58cf0ba1`，2026-08-02）。
- 转换：`input/golden/fixtures/gen_noise_profiles.py` 构建期规范化
  （makers/models 字典序、profiles ISO 升序、a[3]/b[3] 浮点显式、skip 档
  保留、version 保留）→ 本目录 `noiseprofiles.json`（bundle 内置，
  `LightamerIOP/Resources/**` glob 已覆盖）。
- 内容：19 makers / 433 models / 8538 档（每档 `name/iso/a[3]/b[3]`，
  方差模型 `var = a·I + b` 逐通道 R/G/B，标定域 = 传感器线性域）。

## 许可证核对状态

- darktable 主体为 GPL-3.0；`noiseprofiles.json` 系社区贡献的相机噪声
  拟合数据（各 model `comment` 具贡献者署名）。数据文件再分发合规核对
  **尚未完成**。
- **待用户知悉项**（TODO 已登记）：核对未完成前，不对外分发含本文件的
  release 构建。降级 fallback（保留）：运行时让用户指向其 darktable
  安装的数据文件 + 内置 generic（`a=1e-4×3, b=0`），加载器接口不变。
