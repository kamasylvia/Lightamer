# Plan 02-04 — Headless 冒烟 + 真 RAW 全链对照记录

**Date:** 2026-09-19 · **Harness:** `.work/02-04/smoke.swift` + `compare-real.swift`(02-03 swiftc 模式)

## A. 合成链冒烟(smoke.swift,7/7 PASS)

Fixture: `input/RAW/DSC09991.ARW`(60MP,RAW 9)

```
PASS 0. real RAW decoded (6336x9504, v9)
PASS 1. gamma tail is .bgra8Unorm
PASS 2. cold chain: 4 lines (input+colorin+colorout+gamma)
PASS 3. warm chain: top-line hit, zero work
PASS 4. display range respected (unorm encode)
PASS 5. non-degenerate content (mid-tones present, 65%)
PASS 6. ColorSync fallback leg renders
```

## B. 真 RAW vs CI 直渲对照(compare-real.swift,1120px,P3 目标)

- **解码腿逐位一致**:`probe-decode-leg.swift` — pool `renderToTexture(_:longEdge:)` vs CIContext
  直渲 linear Rec2020 float:meanAbsDiff 0.000000 / max 0.0;CI 同 context 双渲亦 0(确定性)。
- **全链字节对照**:R meanAbsDiff **1.52**(<2 ✓);B meanAbsDiff 5.98 —— **89.4% 像素含 <60/255
  通道**(夜景暗部),落在 ColorSync 8-bit ICC 表低端偏差区(见 GoldenColorTests `GoldenTolerance`
  host finding 注释:ColorSync 8-bit 表现 ≈ 纯 gamma-2.2,无 sRGB 1/12.92 线性段;标准曲线才是
  我们的正确输出)。G 通道完全一致。
- **视觉对照**:`real-pipe.png` vs `real-baseline.png` 不可区分(绿调夜 shop 为照片本身内容;
  此前"严重偏绿"恐慌为本 harness 早期版本通道序 bug,已修正并留档)。
- 结论:**管线输出 = 系统参考**(低端表区除外,该区我们遵循 IEC 标准而非 ColorSync 表)。

## C. 执行过程抓出并修复的缺陷

| # | 缺陷 | 修复 |
|---|---|---|
| 1 | **gamma_encode 写成 decode 方向**(`pow((c+0.055)/1.055, 2.4)`)——TRC 表测试 0.5→55 抓住 | 改 `1.055·pow(c, 1/2.4) − 0.055`(kernel + 文档) |
| 2 | **ModuleBox.setParams 不采纳 module-committed piece hash**——colorout 的 stableID fold 对缓存不可见(display change 不失效) | box 采纳 `committedPiece.paramsHash`(其它模块数值不变) |
| 3 | **JSONEncoder 键序同进程跨调用不稳定**(LESSONS L013 预警成真:2 字段 struct 5 次 encode 两种键序,hash 3/2 分裂;测试 run4 复现) | `ParamsCoding.encode`(sortedKeys)统一全部 commitParams 编码 |
| 4 | 16-bit TIFF 生成器未指定 `byteOrder16Little` → 全部字节交换(CGImage 16bpc 默认按大端解释) | 生成器显式 little(注释在案) |
| 5 | Cross 判据双腿缩放半像素差(p99 边界行 50/255,body p50=0)→ 混淆变换对比 | harness 改满分辨率(scale 1.0,零重采样) |
| 6 | 测试采样 y 翻转方向错(管线平面 row 0 = image **TOP**,viz 实证) | 采样 y 直映射,注释在案 |

## D. 环境注记

- 本机屏 = BenQ PD2705U(自定义 ICC,`CGColorSpace.name` = nil)→ `DisplayProfile.current()`
  走 ColorSync fallback;fast-path 单测以显式 Params 驱动,resolve 测试按 plan 的 host-variance
  guard skip-with-log。`probe-tiff.swift` / `probe-ci.swift` / `probe-edge.swift` / `probe-json.swift`
  为定位过程探针,随 .work 归档。
