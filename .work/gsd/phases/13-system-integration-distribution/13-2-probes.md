# 13-2 probes — BPC / rendering-intent 可达性探针报告（T1，头项硬闸）

> 执行：2026-09-27，executor subagent worker。探针程序 = ObjC CLI（`/tmp/la-bpc-probe*.m`，v1..v8 迭代），clang 直编直跑真机（macOS 27, arm64, Xcode SDK）。CoreGraphics/ColorSync 公开 API 面。
> 硬闸：本结论落档前 T2 proof 段实现未开写（计划内硬序遵守）。

## 1. API 面事实（头文件 + 运行时符号双证）

| 事实 | 证据 |
|---|---|
| **BPC 公开开关存在** | `CGColorConversionInfo.h:93`：`kCGColorConversionBlackPointCompensation`（API_AVAILABLE(macos(10.12))）。运行时打印符号值 = `kCGColorTransformBlackPointCompensation` |
| intent 全集入口 | `CGColorConversionInfoCreateFromList(options, space, transformType, CGColorRenderingIntent, ...)`——每 leg 显式 intent（C varargs；Swift 不桥接 varargs，ObjC/C 侧可达） |
| float32 数据转换 API | `CGColorConversionInfoConvertData`（macOS 15+）：「only 8, 10, 16 fixed, 16 bit float and 32 bit float are supported」——本项目 floor 27 覆盖 |
| 转换器限制 | 头文件：「CG color spaces must be calibrated (no Device{Gray,RGB,CMYK}, Indexed or DeviceN)」——ICC 派生空间（`CGColorSpaceCreateWithICCData`）**未被拒绝**，converter 创建成功（含 CMYK dst） |
| 布局要求 | float32 必须 `kCGBitmapByteOrder32Little`（big/default 全 FAILED）；**src_format 与 dst_format 的 bitmapInfo 必须同 alpha/byteOrder 语义**（异构组合全 FAILED——v3 全失败的根因） |

## 2. 可达性矩阵（实测）

| 转换腿 | 通道 | 结果 |
|---|---|---|
| Rec2020lin → RGB ICC（AdobeRGB1998.icc / ITU-709.icc / ROMM RGB.icc） | `CGColorConversionInfoConvertData` premulLast+32Little f32 | **可用**；域内往返恒等 ≤1e-4（§3.1） |
| RGB ICC → Rec2020lin（回程） | 同上 | **可用**（同恒等性证据） |
| Rec2020lin → CMYK ICC（Generic CMYK Profile.icc） | ConvertData dst=`kCGImageAlphaNone`（8bit/32f） | **FAILED** |
| 同上 | ConvertData dst=premulLast 128bpp | 返回 OK 但**输出语义不可信**（red→纯黄、K-in-alpha 预乘污染、值随 CMM 内部状态漂移；v6 vs v7 同参数不同输出） |
| 同上 | ConvertData dst=premulLast **160bpp**（4 CMYK + alpha，v4 stderr 明示的要求） | **FAILED** |
| 同上 | vImage `vImageConverter_CreateWithCGColorConversionInfo`（converter 创建 err=0）→ `vImageConvert_AnyToAny` | 创建成功、转换输出全 0/坏值 |
| 同上 | CIContext `render(toBitmap:colorSpace: cmyk)` | no-throw 但**输出全 0**（静默无效） |
| 同上 | CGContext bitmap context | CGBitmapContext 不支持 CMYK（白名单限制） |
| CMYK ICC → Rec2020lin（回程） | ConvertData premulLast 128bpp | 返回 OK 但同样布局不可信（K 与 alpha 槽冲突） |

**判定：CMYK printer profile 在全部四条 CG 数据转换通道上不可用或语义不可信。**

## 3. 行为锚（数字）

### 3.1 RGB pair 往返恒等 / 超域裁剪（proof 引擎形状的数值依据）
样本 = Rec2020 linear [black, near-black(0.02), white, pureR, pureG, pureB, midgray(0.216), greenish(0.3,0.6,0.2), skin(0.6,0.35,0.2)]；腿 = Rec2020lin → AdobeRGB1998.icc → Rec2020lin（relative colorimetric）：

- **域内样本往返 delta 全部 = 0.0000**（black/near-black/white/midgray/greenish/skin，1e-4 精度）——primaries + TRC + 白点适应自洽
- **超域样本 delta**：pureR 0.1227 / pureG 0.1085 / pureB 0.0660——Rec2020 primaries 超出 AdobeRGB 域被 clip，**不可逆 = OOG 往返判定的直接依据**
- 对照锚：sRGB→DisplayP3 float32 输出 (1,0,0)→(0.917, 0.200, 0.139)（P3 红的已知值）✓ 数学正确

### 3.2 BPC 开关行为生效
- **键被消费可证**：同布局同参数仅 BPC 不同 → 输出显著分化（Generic CMYK pair，黑点非零）：black BPC off → (0.737, 0.706, 0.643, 0.871)，BPC on → (0.723, 0.000, 0.897, 0.000)；near-black off → (1.0, 0.812, 0.759, 0.714)，on → (1.0, 0.005, 0.000, 0.000)
- AdobeRGB pair ±BPC 恒等 = 数学预期（AdobeRGB 黑点 L*=0，无可补偿黑点差）——不构成反证
- **Caveat**：CMYK pair 的输出数值受 §2 布局不可信问题影响，BPC 锚取「on/off 分化」为可达性证据，不采信其绝对数值

### 3.3 rendering intent 行为
- **absolute 生效**：ROMM→AdobeRGB 上 absolute vs relative 分化（如 (0.7613,0,0.7460) vs (0.7565,0,0.7562)——白点不适应路径）
- **perceptual 生效**：Rec2020lin→CMYK 上 perceptual vs relative 分化（black (0.8325,0.0128,0.9956,0.035) vs (0.7228,0,0.8974,0)）
- **saturation 退化**：两组 pair 上与 relative 恒等（ColorSync 对无 saturation 表的 profile 退化为相对比色）——记录，UI 提供但注记
- relative/default：RGB monitor-class profiles（同 D65 白点）上与 absolute 恒等 = 预期

## 4. 管线形状判定（三选一）

**判定 = 「公开开关直用」+「CMYK 降级注记」的组合**（探针矩阵否决了纯手做补偿的必要性，也否决了 CMYK 可达）：

1. **BPC：直接开关**。`SoftProofProfile.blackPointCompensation` → `CGColorConversionInfoCreateFromList` options `[kCGColorTransformBlackPointCompensation: bpc]`。不做手做黑点 LUT（公开开关存在且被 ColorSync 消费——§3.2 分化证据）；不为 BPC 自建补偿路径。
2. **intent：枚举全保留，行为两档可证**。relativeColorimetric（默认）与 absoluteColorimetric 行为分化可证；perceptual 在 printer ICC 上可证；saturation 退化记录为已知限制（doc comment + DECISIONS）。
3. **引擎通道**：`CGColorConversionInfoConvertData`（premulLast + 32Little float32）。proof 段 = 往返两腿（工作空间 → printer ICC → 工作空间），OOG = 往返 delta 阈值判定（§3.1 超域 delta 0.066-0.123 vs 域内 ≤1e-4，阈值取 1e-3）。
4. **CMYK printer profile：降级注记**。`SoftProofProfile` 校验 printer ICC 的 `CGColorSpaceGetNumberOfComponents == 3`（RGB）；非 RGB（CMYK/DeviceN）→ profile 拒绝 + UI 注记「该 printer profile 为 CMYK 型，当前版本软打样仅支持 RGB 型 printer profile（摄影打印主流）」。登记 DECISIONS + TODO 遗留对表（v2 若 ColorSync 数据通道开放 CMYK 再议）。

## 5. 探针迭代记录

| 探针 | 学到 |
|---|---|
| v1 | 头文件事实 + ConvertData 全组合 FAILED（bitmapInfo 异构） |
| v2 | 同空间 converter 返 NULL（no conversion required）；vImage converter 创建 err=0 但 AnyToAny 布局错误诊断（3ch 期望 24bpp） |
| v3 | 组合矩阵扫描：8bit premul 族 OK；float 必须 32Little；**src/dst bitmapInfo 必须同语义**；infoC UAF segfault 修复 |
| v4 | AdobeRGB 行为锚（域内恒等/超域 clip）；CI render→CMYK 全 0；CMYK 回程「OK」但布局可疑 |
| v5 | intent 锚（absolute 分化 / perceptual CMYK 分化 / saturation 退化）；BPC CMYK on/off 分化 |
| v6 | BPC 前向分化复证；128bpp CMYK 输出不可信（量化值漂移、样本错位） |
| v7 | 预乘闭合假设失败（K-in-alpha 语义不成立） |
| v8 | 160bpp CMYK FAILED——CMYK dst 判死，转 RGB-only 结论 |

探针二进制与源码留在真机 `/tmp/la-bpc-probe*.m`（不进 repo；本报告 §1-4 为正本记录）。
