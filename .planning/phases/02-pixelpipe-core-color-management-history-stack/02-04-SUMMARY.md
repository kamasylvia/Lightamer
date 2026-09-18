# Plan 02-04 — Summary

**Executed:** 2026-09-19 · **Branch:** main · **Status:** ✅ COMPLETE

终端三件套落地，显示色彩达到 **SC#1 正确**：管线输出 = 系统 CI/ColorSync 参考逐通道一致（真
RAW 实证）。**colorin = 恒等**（CIRAW 已显影——02-RESEARCH §3.1 的最重要架构事实，displayed-domain
注记写入模块头，Phase 3 golden 容差按此校准）；**colorout** 双路径（Rec2020→P3/sRGB 编译期常量
矩阵 Metal 快路径 + ColorSync 精确腿，D-COL3 参数位预留）；**gamma** 管尾 sRGB TRC →
`.bgra8Unorm`（D-COL4 唯一 clamp 点，缓存止于 colorout，换屏只重渲终端段）。**ModuleRegistry**
actor 锁定 opName→工厂缝（02-06 sidecar 降级 + Phase 3 注册入口）。**D-COL1 双判据 golden
harness** green——Phase 3+ 算法移植的闸门自此生效。

## Tasks

| Task | 内容 | Commit |
|---|---|---|
| 02-04-02 | `ColorInModule`（identity + COLOR-04 hook + displayed-domain 架构注记）+ `TerminalKernels.metal`（Core 首个 metallib；terminal_copy/colorout_matrix/gamma_encode）| 4e3d53d |
| 02-04-03 | `DisplayProfile`（匹配表 + stableID + linear/display spaces）+ `ColorOutModule`（常量矩阵双特化 + ColorSync 腿经 `MetalContext.convertToLinearSpace`）| 6862553 |
| 02-04-04 | `GammaModule`（sRGB 分段 TRC → `.bgra8Unorm`）+ PixelPipe 尾段显示格式策略（gamma 尾平面 4B/px，FULL 同待遇）| e30ba60 |
| 02-04-01 | `ModuleRegistry` actor（default chain + 未知 op nil）+ `LightamerIOPRegistry.populate`（DEBUG testgain）| 250ccca |
| 02-04-05 | D-COL2 屏幕跟随：`WindowCapture`→`configure(window:)`→双通知 observer→幂等 stableID guard→colorout re-commit→PREVIEW 重渲；registry/populate 接线 LightamerApp；blit display-ready 双 PSO + CAMetalLayer colorspace | 34dda70 |
| 02-04-06 | Golden fixtures：合成 `NeutralTarget.tif`（1024² 16-bit sRGB TIFF，3×3 patch，6 灰块线性值逐块精确）+ `Fixtures.neutralPatches/`ARW hook；ARW 采集 pending（记录 + 激活路径） | 8b81a5f |
| 02-04-07 | `TerminalTrioTests`（13）+ `GoldenColorTests`（6，双判据 + 缓存断言 + PFM dump）+ `ParamsCoding` canonical 编码器 | 600b851 |
| 修复 | gamma TRC 方向 / DisplayProfile Equatable / Params Sendable / L013 落地 | 45890c9 |

## 验证(质量门全过)

- 单元:**83 tests, 0 failures, 3 skips**(63 基线零回归 + 20 新增;3 skip = ARW×2 + 既有 RAW 样本)
- **D-COL1 双判据 green**:
  - 判据 1 中性度:NeutralTarget 6 灰块(线性 1.0/0.75/0.5/0.18/0.09/0.0)经全链后通道差全部 <2/255,级别 sanity ±2/255 逐块通过
  - 判据 2 交叉一致性:线性域(colorout 平面 vs CI 直渲 linear-P3)严格 <0.004;字节域 vs ColorSync 8-bit 基准 p90 <2/255 + 低端 ICC 表区有界(host finding:ColorSync 8-bit 表 ≈ 纯 gamma-2.2 无线性段,标准 sRGB 曲线才是正确发射——记录于测试注释)
- **缓存断言**(coordinator 同款操作序列):run1 全 miss(4)→ run2 全 hit → 模拟换屏(override+re-commit)→ **colorin hit / colorout+gamma miss(仅终端段失效)** → 回切全 hit
- **真 RAW 冒烟 7/7**(DSC09991.ARW@RAW9):.bgra8Unorm 尾、冷 4 平面、暖 0 工作、显示范围、非退化、fallback 腿
- **真 RAW 全链 vs CI 直渲对照**:解码腿逐位一致(pool vs CI float max 0.0);全链 R 通道 meanAbsDiff **1.52**(<2)、B 差异全部落在低端表区(89.4% 像素含 <60 通道的夜景);两腿 PNG 视觉不可区分(`.work/02-04/real-*.png`)
- **app 内实证**:color 日志("display profile → ColorSync fallback (custom ICC)")、默认链 4 planes 渲染日志、屏显截图;`.work/02-04/screen-change.md`

## 执行过程抓出并修复的缺陷(3 真 bug + 2 harness 坑)

1. **gamma TRC 写成 decode 方向**(`pow((c+0.055)/1.055, 2.4)`)——TRC 表测试(0.5→55≠188)抓住;改 `1.055·c^(1/2.4)−0.055`。
2. **ModuleBox.setParams 不采纳 module-committed piece hash**——colorout 的 stableID fold 对缓存完全不可见(换屏零失效);box 改为采纳 `committedPiece.paramsHash`(其它模块数值不变,行为无损)。
3. **JSONEncoder 键序同进程跨调用不稳定**(LESSONS L013 预警成真;2 字段 struct 5 次 encode 两种键序,hash 分裂)——`ParamsCoding.encode`(.sortedKeys)统一全部 commitParams;02-05/02-06 的 sidecar 哈希直接复用。
4. 16-bit TIFF 生成器缺 `byteOrder16Little`(CGImage 16bpc 默认按大端)——fixture 全部字节交换,QA 采样抓住。
5. Cross 判据双腿缩放半像素差 + 采样 y 翻转方向错——harness 改满分辨率 + 实证平面 row 0 = image TOP(viz harness 定位)。

## 对 plan 的记录在案偏差

| # | 偏差 | 理由 |
|---|---|---|
| 1 | 任务实现序 02→03→04→01(非 01→07):registry 的 `init()` 自注册 terminal trio,编译上依赖三个模块先存在;每 commit 构建绿是硬约束 | 内容与 plan 完全一致,仅落地顺序 |
| 2 | `ModuleBox` 增 identity-restoring init(instanceID 注入)并让 `setParams` 采纳 committed piece hash | plan 要求 `makeBox(opName:instanceID:)` 恢复持久化 UUID + stableID fold 对缓存可见——两者都需要;对既有模块数值零变化 |
| 3 | `LightamerIOPRegistry.populate` 为 `async` | registry 是 actor(D-33 统一,checker fix);register 隔离方法必须 await |
| 4 | `DisplayProfile` 匹配不走 `NSColorSpace.name`(该属性在 macOS 27 SDK 不存在) | 以 CGColorSpace 注册名 → NSColorSpace 等价 → ICC 数据等价三级实现,语义等同且更稳(plan 写作时的前提 API 不存在,host 探针实证) |
| 5 | 判据 2 拆线性域(<0.004 严格)+ 字节域(ColorSync 基准,低端表区有界)双层 | ColorSync 8-bit ICC 表在低端 ≈ 纯 2.2(无 sRGB 线性 toe),与 IEC 标准曲线物理不可同时满足;我们遵循标准(compositor 按声明色彩空间解释字节)。纯字节域 <2/255 会把正确实现判死;双层结构保住判据的意图(抓 TRC/色域错配)且更严格 |
| 6 | ColorSync fallback 腿输出 linear-sRGB workalike(非未知 profile 的精确原色) | 任意 ICC 无"线性版"可用;精确原色属 Phase 13 COLOR-03 全 ICC 支撑,log + 文档注明 |
| 7 | harness 满分辨率(scale 1.0)跑 | 双腿 scale<1 重采样有半像素差(p99 边界行 50/255,body 全 0),混淆判据要抓的变换误差;满分辨率零重采样 |

## 交接给下游

- **02-05**:`ModuleRegistry`/`makeBox(opName:instanceID:)` 即 sidecar 物化缝;`ParamsCoding.encode` 即 sidecar params 哈希正源;coordinator `adoptChain` 的显式 instances 优先路径即 history 实例集替换位
- **02-06**:unknown op → `makeBox` nil → 降级(keep paramsData/disable/toast);`DisplayProfile.stableID` 已进缓存键,HistoryHash 复用 StableHash
- **Phase 3**:每个 tone iop 注册进 `LightamerIOPRegistry.populate`;golden 双判据 harness 即合并闸门(SC#5)——**displayed-domain 输入校准容差**(colorin 头注记);`commitParams` 模板 = `ParamsCoding.encode` + StableHash
- **Phase 8 EDR**:换 drawable 格式 + colorout 映射即可,管线不动(D-COL4 兑现:全链唯一 clamp 在 gamma kernel)
- **Phase 13**:COLOR-03/04 参数位(`inputProfile`/`outputProfile`/`intent`)已留;fallback 的精确 ICC 原色 + 跨屏 profile 跟随实测在此补

## 环境注记

- 本机屏 = BenQ PD2705U(自定义 ICC,无内建屏):resolve → ColorSync fallback 为**正确**行为;fast-path 测试全部以显式 Params 驱动(计划允许的 host-variance guard 生效两次)
- ColorChecker ARW 采集失败(raw.pixls.us 上传政策排除 color target + 无等效 CC0 源)→ 合成 fixture 承担 gate,ARW 路径 XCTSkip,补拍激活路径在案(`.work/02-04/colorchecker-acquisition.md`)
- L009 全程生效(Resilio SIGSTOP/SIGCONT);新文件已 `tuist generate`
