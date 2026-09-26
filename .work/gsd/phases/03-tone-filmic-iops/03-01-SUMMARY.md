# Plan 03-01 — Summary

**Executed:** 2026-09-19 · **Branch:** main · **Status:** ✅ COMPLETE（tracer 达成）

Phase 3 golden 验收基建全线打通：**exposure golden parity <1e-5 GREEN**——dt-cli 钉参参考 →
合成 fixture → Lightamer 全管线 → 逐像素比对，整条验收链可信。后续 5 个 plan（03-02..03-06）
直接复用本 plan 的 dt-cli 重建、fixture 组、双轨 harness、CPU 单测框架与两份 LESSONS。

## Tasks

| Task | 内容 | Commit |
|---|---|---|
| 03-01-T1 | darktable-cli 从 dc58cf0ba1 重建（`5.5.0+1862~gdc58cf0ba1-dirty`）+ XMP 钉参采纳实证（+1EV：ramp 0.25 列 → 0.5 exact；直通 bit-exact） | 6c7bc7e |
| 03-01-T2 | `input/golden/`：gen_fixtures.py（stdlib EXR writer + 8 fixtures + 4 钉参 XMP cases）+ regenerate.sh（四段、hermetic conf）+ manifest（映射表 + 双 hash）+ gitignore 切分 | 6c7bc7e |
| 03-01-T5 | `ExposureModule`（.swift+.metal 对，v50=21.0 注册进 LightamerIOPRegistry）：v7 params 镜像 + white/scale 推导 + 4 项 divergence 头注 | 5c57916 |
| 03-01-T3 | `GoldenParityTests` 双轨 harness：轨 A（fixture×case 逐像素 <1e-5）+ 轨 B（Phase 2 双判据带新 iop 插入）+ 手写 float32 EXR reader/writer + 失败 dump | 5c57916 |
| 03-01-T4 | `CPUDerivationTests`：exposure 公式直译 + 8 已知向量 + clamp/hash 契约 + WB/Lab/sigmoid/toneequal/filmic 占位节 | 5c57916 |
| 03-01-T6 | tracer 签收：VALIDATION 三行 ✅ + IOP-TONE-01 green + TODO 更新 + LESSONS L015/L016 | （本提交） |

## 验证（质量门全过）

- **单测**：143 tests, 0 failures, 3 skips（合规 skip：ARW ×2 + RAW 样本），`xcodebuild test -only-testing:LightamerTests`
- **tracer（轨 A）**：4 钉参 case × 4 灰度 fixture（ramp/0/−4/−8EV 平场）全部逐像素相对误差 <1e-5（`testExposureGoldenParityAgainstDarktableCLI`）
- **XMP 采纳证据**：+1EV XMP 输出 = 2×输入 maxdiff **0.0**；0.25 列（幂次锚定 col 48）→ 0.5 ±1e-6 ✓；无 XMP 直通 maxdiff 0.0（预算 ≤1e-6，6 月基线 3.6e-7）
- **轨 B**：中性度 6 灰块 <2/255 + 线性域交叉一致性 <0.004，均带 exposure（identity）插入链
- **kernel 单测**：0.25 灰 +1EV → 0.5 ±1e-6（dispatch→drain→readback，L014）
- **regenerate.sh**：全新目录一键复现（hermetic `--configdir` 钉 float32/uncompressed，manifest hash 机器无关）

## checkpoint:decision（REVERSIBILITY_GATES）

**未触发**：重建后 XMP 历史被正常采纳（采纳证据见上），RESEARCH §6.3 的 GUI 模板回退方案无需启用，继续自主执行。

## 执行过程抓出并修复的缺陷（2 真 bug + 3 host finding）

1. **EXR offset 表漏算 8 字节魔数**（gen_fixtures 首版）：所有 chunk −8B，libopenexr/dt 仍解析成
   「干净但错位」的数据（float EV 网格值到处都是，肉眼难察）→ 手写 reader 对账抓住。教训：合成
   文件必须做语义断言（灰度/单调），不能只看「解析成功」。
2. **RESEARCH §6.3 勘误——XMP params 编码**：未压缩 params 是**小写 HEX ASCII 非 base64**
   （`dt_exif_xmp_decode` 按 `gz` 前缀分派）；base64 会被解出错误长度 → `params WRONG` → dt
   静默回退默认参数。→ **LESSONS L015**。
3. **macOS 27 ImageIO float32 EXR 解码逐通道错位**（dt 与自研文件同样中招；官方解码器是离群
   点）→ 轨 A 改自研 reader + `CGImageCreate` float32 直构（不经过 ImageIO 解码器）。→ **L016**。
4. **`CGColorSpace.itur_2020` 是 gamma-2.4 非 linear**：fixture CGImage 曾用它打标签，CI 把
   linear 值再 gamma 解码（v^2.4，2^-19.2 特征值暴露）→ 改 `WorkingSpace.colorSpace`
   （`CGColorSpace.linearITUR_2020`）。→ **L016**。
5. **darktable 构建缓存漂移**：6 月配置的 CMakeCache 混着 CLT SDK `-isystem`（与 Xcode 27 clang
   的 libc++ `<cstddef>` 冲突）+ 已不存在的 librsvg 2.62.2/lua5.4 路径 → CLT SDK include 改指
   Xcode SDK + `cmake --fresh` + 显式 libomp flags + `-DDONT_USE_INTERNAL_LUA=Off`。

## 对 plan 的记录在案偏差

| # | 偏差 | 理由 |
|---|---|---|
| 1 | ramp fixture 改为 `v(x)=2^(−8+x/8)`（末列 −0.125EV，col 48 = 0.25 幂次精确） | plan 验收「0.25→0.5 ±1e-6」需要 0.25 精确存在；8 等分 EV 网格（8x/63）不存在精确 0.25 列 |
| 2 | T2 验收平场只跑 gray 系 fixture 做轨 A parity（饱和色块/1D 阶梯 fixture 已产出，gray staircase/深阴影已生成 golden） | plan T6 明确「fixture（灰阶 ramp + 平场）× 钉参组」；色彩敏感 fixture 的 parity 属 filmic/gamut plan（03-06），届时 ImageIO 错位问题已被 L016 路线绕开 |
| 3 | 轨 A fixture 解码不走 `RAWDecoder.decodeRaster`（ImageIO），改 `decodeFixtureEXR`（UncompressedEXR + CGImageCreate） | host finding #3——ImageIO float EXR 错位；管线段（RenderPipeline.process）保持真实路径不变 |
| 4 | `regenerate.sh` 用 `--configdir` hermetic conf 而非 plan 草图的裸 `/tmp/golden.db` | dt 写出格式（PIZ/half）由 conf 决定，不钉则 manifest hash 机器间漂移；DB/中间件仍全在 `.conf/`（gitignored） |
| 5 | `GoldenParityTests` 内置手写 EXR reader 而非 ImageIO | 同 #3；PIZ 输入 fail-fast 提示重新 regenerate，防止静默错位 |

## 交接给下游

- **03-02（WB）/ 03-03（Lab 三模块）**：`GoldenParityTests` 文件头 API 注记（`runTrackA` 思路 =
  `decodeFixtureEXR` + registry 链 + `runExposurePipe` 模式；轨 B = `makeChainWithExposure` 换模块）；
  `CPUDerivationTests` 占位节已列 RESEARCH 小节号；钉参 XMP 生成照 `exposure_params_blob`（hex！）
- **全部后续 plan**：`bash input/golden/regenerate.sh` 必须在新增 case/fixture 后重跑并提交
  manifest 增量；`--apply-custom-presets 0` 已固化
- **Phase 11（Export）**：L016 意味着 app 侧 float EXR 导入/回读不能走 ImageIO——自研 reader
  已在测试侧验证，产品化时上移到 Core（已在本 SUMMARY 记录，未提前实现）

## 环境注记

- L009 全程生效：darktable 全量重建期间 Resilio SIGSTOP/SIGCONT
- 观察到一个 **02-04 遗留 flake**（非本 plan 回归）：`GoldenColorTests.testCrossConsistencyLinearDomain`
  在多测试会话中偶发 diverge 1.0（单测隔离/多数全 suite 运行通过；03-01 测试排除后仍复现），
  已挂 TODO.md 待排查（疑似 CI baseline 腿时序，L014 同族）
- cmake 经 brew 重装（4.4.3）；darktable build 目录 fresh configure 后全量增量编译 ~7 分钟（M4）

## Artifacts

- `input/golden/`（regenerate.sh + gen_fixtures.py + cases/*.xmp + manifest.md）— D-T5 兑现
- `Tests/LightamerTests/GoldenParityTests.swift`、`Tests/LightamerTests/CPUDerivationTests.swift`
- `LightamerIOP/Sources/Exposure/` 文件对（Phase 3 首个真实 iop）
- `LESSONS.md` L015（XMP hex 编码）/ L016（ImageIO float EXR + itur_2020 陷阱）
- `.planning/phases/03-tone-filmic-iops/03-VALIDATION.md`（Wave 0 三行 ✅ + wave_0_complete: true）
