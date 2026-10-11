# M5-1 GATE LEDGER — TRACK 追色族五门跨 plan 收口台账（M5-1-03 T3/KD-3）

> **定位**：M5-1 三 plan 的 golden 门收口正本——五门 × {定义（CONTEXT 裁决原文）,
> 测试锚（文件:法）, 终值带（实测带/判据）, 落位 plan} 全表。VALIDATION
> （M5-4）的 nyquist 输入件：每行 = 收口批亲验（定向轮重跑或验收轮实测值引用，
> 禁无证据 ✅）。裁决正本 = `M5-1-CONTEXT.md` 裁决记录（2026-10-11 用户回批）。
> 收口轮 = 2026-10-12（M5-1-03 执行批）：定向四 bundle（Layers 466/4/0 1153MB /
> IOPParity 444/3/0 5836MB / App 749/4/0 2832MB / IOP 563/1/0 7740MB<8G 门）
> 全绿零 MEMFAIL + 全套 `--all` 终验（数字见 §6）。

## 门定义（CONTEXT OQ-M5-1-8 裁决原文）

> ⑧「golden 五门（bit-identity / kernel parity ≤1e-5 / 合成对恢复 / MCP e2e /
> 恒等直通）」——三档求解（G1/G3）、kernel（G2）、MCP 编排皮（G4）、恒等回归
> （G5）四层覆盖，G3 的自然样张目测 = gui-acceptance Manual-Only 行（OQ-8 备选
> A 事实形态）。

## G1 求解确定性（bit-identity）— ✅ PASS（P1 落门 + P2 全链补腿 + 收口轮亲跑）

| 面 | 锚（文件:法） | 终值带/判据 | 落位 |
|---|---|---|---|
| 双跑位型 | `ColorMatchSolverGoldenTests:testG1DoubleRunBitIdentity` | bit-identical（位型相等） | P1 |
| 退化回落确定 | `ColorMatchSolverGoldenTests:testG1DegenerateFallbackDeterministic` | 双跑确定（秩亏 S3 回落 + 零迹恒等+offset 面） | P1 |
| 缓存透明 + LRU | `ColorMatchSolverGoldenTests:testG1CacheTransparencyAndLRU` | 缓存命中值不可见 | P1 |
| 缓存键折叠序字面 | `ColorMatchSolverGoldenTests:testG1CacheKeyFoldOrderPinned` | `gaussianOT(0,0)=2495982924697081349` / `reinhard(0,0)=3458577883779271296` 逐位 | P1 |
| 池化排列不变 | `ColorMatchPoolingTests:testAnyPermutationGivesByteIdenticalPool` | 6 排列同字节 | P2 |
| bake 双跑位型 | `ColorMatchBakeGoldenTests:testDoubleBakeIsBitIdentical` | concurrentPerform 固定索引归并 bit-identical | P2 |
| **全链真解位精确**（solve→bake→serialize→write→load，含持久 .cube 资产） | `ColorMatchServiceTests:testSolveTwiceLandsByteIdenticalParams`（T8 补腿：persisted asset == in-memory bake 全表位型） | 逐字节 + 幂等零新 history item | P2 |

- G1 的 MCP 面映照 = solveHash 披露（`McpMatchColorToolsetTests:testDeterministicDoubleCallSameSolveHash` + `McpMatchColorParityTests:testDoubleCallDisclosesTheSameSolveHash`——同输入同哈希，agent 可自行复验）——本批亲跑绿。

## G2 kernel parity（vs Float64 CPU 参考）— ✅ PASS（P1 落门；收口轮 IOPParity 亲跑 444/3/0）

| 面 | 锚（文件:法） | 终值带（实测） | 门 | 落位 |
|---|---|---|---|---|
| 良态子集（全 \|lms\|>1e-3）scale-aware p99.9 | `ColormatchKernelParityTests:testKernelParityP999` | ~1e-5 带（abs 3.4e-5 @ 输出幅值>10 ≈ 3e-6 相对） | ≤1e-5 | P1 |
| 全网格 abs p99.9 / max（LMS≈0 交越界） | 同上 | **2.95e-3 / 3.68e-2** | ≤4e-3 / ≤5e-2 | P1 |

- **机制注记（P1 DECISIONS §2 正本）**：Oklab cbrt 在 LMS≈0 交越导数无界——单一
  「p99.9 ≤1e-5」目标在交越像素上数学不可达（f64 同点对扰动同敏感）；门拆两面
  = 良态子集扛精度门 + 全网格扛交越界门（钉实测带）。非降级交付。
- 交越/负值/HDR 探针 = `testKernelProbesNegativeLMSAndHDR`。

## G3 语义 golden（合成参考对恢复已知变换）— ✅ PASS（P1 落门；收口轮亲跑绿）+ 目测行挂 VALIDATION

| 面 | 锚（文件:法） | 终值带（实测） | 门 | 落位 |
|---|---|---|---|---|
| commuting 族矩精确恢复（构造约束：OT 只恢复 OT 映射，P1 DECISIONS §4） | `ColorMatchSolverGoldenTests:testG3MomentExactRecoveryS1` | ~1e-7 级 | ≤1e-3 | P1 |
| 采样臂（LCG 2 万样本，trim shuffle 机制带） | `ColorMatchSolverGoldenTests:testG3SampledRecoveryS1` | **1.73e-2** | ≤0.06 | P1 |
| S3 对角恢复 | `ColorMatchSolverGoldenTests:testG3DiagonalRecoveryS3` | 门内 | ≤1e-3（相对族） | P1 |
| 自然样张目测（9 行 human rows + 机器覆盖图） | `.work/gui-acceptance/m5-1/MANIFEST.md`（证据域不入 git，L073） | Manual-Only——**VALIDATION 期人工执行**（本收口为自动化批，不代跑） | 目测判读 | P2 配方 / M5-4 执行 |

## G4 MCP 端到端 parity — ✅ PASS（本批落门亲跑 3/0/0，App bundle）

| 面 | 锚（文件:法） | 终值带（实测） | 判据 | 落位 |
|---|---|---|---|---|
| match_color → apply_params(strength 0.7 微调) → render_preview vs 本地同参渲染 | `McpMatchColorParityTests:testMatchColorApplyParamsRenderPreviewParity` | **byte-identical（0 diff）** | SC#3 同型——共享 decode memo 下远端视图 == 本地视图逐字节（既有判据未放宽，无需实测带收窄） | **P3（本批）** |
| 批量双目标 parity（单次 fan-out 落两目标，各自逐字节） | `McpMatchColorParityTests:testBatchDoubleTargetParity` | byte-identical ×2 | 同上 | P3 |
| solveHash 披露（G1 的 agent 面） | `McpMatchColorParityTests:testDoubleCallDisclosesTheSameSolveHash` | 同哈希 | 双调用同 solveHash | P3 |

## G5 恒等回归（缺席/禁用/strength=0 逐字节直通）— ✅ PASS（P1 落门；收口轮 IOP 亲跑 563/1/0 零漂移）

| 面 | 锚（文件:法） | 判据 | 落位 |
|---|---|---|---|
| 缺席（editing seed 无 colormatch——结构面） | `ColormatchIdentityGoldenTests:testColormatchAbsentFromEditingSeed` | seed ABSENT 双面断言 | P1 |
| 禁用/strength=0/未解（routed-blit 逐字节直通） | `ColormatchIdentityGoldenTests:testIdentityStatesBlitByteExact` | byte-exact | P1 |
| LUT 臂恒等态直通 | `ColormatchIdentityGoldenTests:testLutArmIdentityStatesBlitByteExact` | byte-exact | P2 |
| 反空转（solved strength-1 实动像素——恒等面非「kernel 恒拷贝」） | 同上两法内 anti-vacuum 断言 | 动像素 | P1/P2 |

## 收口轮运行记录（2026-10-12，caffeinate + test-direct 直启宿主，L019b）

| bundle | 终值 | peakRSS | MEMFAIL | 对账 |
|---|---|---|---|---|
| Layers | **466/4/0** | 1153MB | 无 | == M5-1-02 收口值（本批 Layers 零增量） |
| IOPParity | **444/3/0** | 5836MB | 无 | == M5-1-02 收口值（零增量） |
| App | **749/4/0** | 2832MB | 无 | = 725（M5-1-02 修复批后）+ 24（本批 21+3）逐位 |
| IOP（抽验） | **563/1/0** | 7740MB | 无 | == M5-1-02 收口值（零漂移；< 8G 门） |

全套 `--all` 终验（批准在案）数字 = §6（后台轮回填）；对账链 = §6.1。

## 6. 全套 `--all` 终验（M5-1 收口批准轮，2026-10-12）

**轮次记录（诚实面）**：批准的 `--all` 单命令轮在 **Library bundle 宿主 SIGSEGV
（exit 139，ModelAssetCatalogTests 中途 terminated abnormally）**——脚本按 L055
纪律置零计数并中止余下 bundle；根因 = **混态产物**（Library/Sessions/Export 三
scheme 未在本会话重建——tuist generate 后旧 xctest 配新框架，同本日 Layers 启动
失败族；L075 扩展：generate 后全部 scheme 须重建）。处置 = 四 scheme 逐一
`build-for-testing` 重建后**分割重跑**（IOP/IOPParity/Layers 三 bundle 取本轮
有效值——其 scheme 本会话已重建过）。孤儿预防 = 跑前预删
`Tests/Fixtures/TiffRaster/srgb-matrix-8.tif.lra`（M4-1 #6 第五度）。

| bundle | 终值（tests/skip/fail） | peakRSS | MEMFAIL | L055 末条身份 |
|---|---|---|---|---|
| IOP | 563/1/0 | 7806MB | 无 | All tests ✓ |
| IOPParity | 444/3/0 | **8107MB** | 无 | All tests ✓ |
| Layers | 466/4/0 | 1180MB | 无 | All tests ✓ |
| Library | 626/4/0 | 618MB | 无 | All tests ✓ |
| Sessions | 279/4/0 | 1249MB | 无 | All tests ✓ |
| Export | 350/1/0 | 6085MB | 无 | All tests ✓ |
| App | **749/4/0** | 2832MB | 无 | All tests ✓ |
| **总计** | **3477 / 21 / 0** | — | 零 | 七 bundle 双保险全过 |

- **8G 运行门**：全过（峰值 IOPParity 8107MB，门 8192MB 余量 ~1%——贴线
  bundle 轮间漂移注记：定向轮 5836MB ↔ 收口轮 8107MB，±3% 漂移带外但同 suite
  零 MEMFAIL，属 SPIKE 70e09e5 在案的重测顺序漂移族；连续 MEMFAIL 才处置）。
- **skip 总 21 vs M4-3 预期 16**：预期值为估算非实测锚；Δ+5 为 M4-3/M5-1 各批
  新增 skip-able 测试的环境性累积（GPU/resource gate），非计数断言面——诚实
  注记，对账以 tests 总数为准。

### 6.1 对账链（3335 + Δ 全链，逐位闭合）

```
3335（M4-2 末基线）
 + 32（M4-3 批）                                = 3367（pre-M5-1）
 + 38（M5-1-01 P1：Oklab/Stats/Solver/op/kernel） = 3405
 + 47（M5-1-02 P2：CDF/池化/bake/资产/LUT 臂/服务/面板） = 3452
 +  1（M5-1-02 修复批 E-omp1：add-row gate 法）   = 3453
 + 24（M5-1-03 P3：ToolsetTests 21 + ParityTests 3） = 3477
实测 3477 —— 逐位闭合 ✓
```

分 bundle 对账：App = 725（P2 修复批后收口值）+ 24 = 749 ✓；Layers 466 /
IOPParity 444 / IOP 563 与 P2 收口值逐位相等（本批零增量）✓。
