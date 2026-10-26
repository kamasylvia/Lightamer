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

- darktable 主体与 `noiseprofiles.json` 数据均为 GPL-3.0-or-later（源文件
  头声明；贡献无 CLA/无宽松许可特例）。本仓 2026-10-20 切 GPL-3.0
  (`4071402d`) 后同许可再分发合规；修改 = 规范化转换（已标注）。核对结论
  （2026-10-26）= 限制解除，attribution 已入根 NOTICE 条目 R——**发布门
  解除**。正本 =
  `.work/gsd/phases/evidence-legacy/plans/05-01/noiseprofiles-license-check.md`。
- 维护性义务（持续）：从 dt 同步新相机 profile 时保留 `comment` 贡献者
  署名 + 更新基准树 SHA 登记。降级 fallback（保留）：运行时让用户指向其
  darktable 安装的数据文件 + 内置 generic（`a=1e-4×3, b=0`），加载器
  接口不变。
