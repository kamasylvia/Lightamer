# Plan 06-02 — blendop 合成引擎执行 SUMMARY

**执行**：2026-09-23 夜间 ZCode subagent worker（GSD executor）
**状态**：✅ 全部 6 任务完成，验收标准全过；终轮全 suite **670 tests / 3 skip / 0 fail**（直启宿主，touch + build-for-testing 重编后复跑；基线 648 → 670，+22）
**提交**：T1 `430056c`（float64 参考 + JzCzhz 链 + blob 配方）→ T2 `533bef9`（compositeLayer kernel + driver 接线 + GPU parity）→ T3 `7b862a6`（L023 GPU 探针 + 感知 parity + hue 全环 sweep）→ T4 `f2cbd39`（BlendMode 枚举增补 + REVERSE 消费/正交性）→ T5 `bda5188`（dt 三证据 resident + manifest 总账 + 分块恒等）→ T6 `137bf02`（本文档同批）

## 任务完成表

| 任务 | commit | 验证数字 / 证据 |
|---|---|---|
| T1 float64 参考公式表 + blob 配方 | 首提交 | `BlendOpReference.swift` 每模式一函数（逐式对照 blendop.cl / blendif_rgb_jzczhz.c 行号注释，先于 kernel）；`JzCzhz.swift`（Common/）五腿全往返链复用 ColorBalanceRGBMath/LabRoundTrip 同源常量（L023 半边契约注释）；CPU 往返实测 maxRel 3.1e-5（dt 常量集非对称地板：7 位前向 vs 16 位逆矩阵 × PQ p=134 放大），门 1e-4 + 精确腿（矩阵对/极性）<1e-12；`blendop_params_blob` 运行时实证 **420 字节**（本机 5.5.0+755 二进制 sizeof = 检出树算术 404 + 16B 尾，默认 blob 解码逐段核对）；`--d params` **`blendop v. 14: version ok params ok`** + DB hex 840 字符逐字节一致；54 个 XMP（18 模式 × 3 opacity）生成 |
| T2 compositeLayer 单 kernel + driver 接线 | 533bef9 | `BlendOpKernels.metal`：mask×blend×opacity 三元组单 kernel（mask 平面值 = 有效 opacity，dt blend.c:458 CLIP + :530 折叠契约）；算术模式全表（NORMAL2/multiply(p=exp2 host 折叠 blend.c:1301)/lighten/darken/linearBurn(a+b−1, lmin=0)/screen/overlay/softlight/hardlight/difference/PS dodge+burn）+ JzCzhz 感知族 + REVERSE；6-1 退化 kernel 退役（LayerCompositeKernels.metal 删除）；parity 门逐模式 × 3 opacity <1e-5 rel（2.5e-5 abs floor）非平场 HDR fixture；防空转（每模式 composite != below）+ 恒等三元组（算术 op=0/op=1 逐字节）；**kernel 逆变换 hue 通道错乘真 bug 被 parity 门抓住并修复**（JzAzBz[2] = sin·Cz 非 sin·hz——灰暗像素输出爆至 ~1e3 的证据链：fwd 探针逐值吻合 → inv 探针逐 stage 二分定位）；LayerComposite 8 + LayerCache 10 + LayerCore 11 + MemoryBudget 12 + Phase6Sidecar 6 全绿 |
| T3 JzCzhz 往返 + 感知四件证据 | 7b862a6 | L023 GPU 探针（`blendop_jz_probe` mode 0/1）：**矩阵对 mo·M·mi ≈ I <1e-6** + **极性往返 Jz/Cz/hz 恒等 <1e-6**（in-shader float32 实测）；感知 5 模式 × 3 opacity vs float64 参考（实测 float32 pow-chain 地板：rel 2e-3 / abs 5e-4 门，RGB 空间；极性域才是紧门）；**hue 全环 sweep**（24 步 × 4 行，hz_a=0.98 近环绕）：Jz/Cz 随 a 至 1e-6、hz 端到端落 hz_b 实测 1.19e-5 turns（门 5e-5，plan 的 1e-5 由极性探针承担） |
| T4 REVERSE 位 + 增补模式 | f2cbd39 | BlendMode +4 case（扩展永不重编）：lighten 0x02 / darken 0x03（dt RGB shape max/min mix）+ **psColorDodge 0x2A / psColorBurn 0x2B 新 raw 值**（blend.h:44-91 占用审计：dt 上限 0x29；W3C Compositing-1 公式；进 dt 退化为 normal 的单向损失入账）；头注映射表扩展 + 公式落成注记；新 4 模式进 GPU parity sweep（<1e-5）；**REVERSE == a/b 平面交换逐字节**（6 算术模式）+ REVERSE(normal, op=1) == below 逐字节；枚举/位正交（raw 值不带位、dtModeSlot 投影恒等、13 冻结槽位不变、0x18 保持未占）；sidecar 回归绿（LayerCore 11 / Phase6Sidecar 6 / LayerSkeleton 5） |
| T5 dt 三证据 + manifest + 恒等扩展 | bda5188 | **54/54 probe 采纳**（DB blendop_params hex 逐字节 + `version ok params ok` + 平场 PFM 值），证据归档 `.work/plans/06-02/adoption/`（54 log + pfm-values.tsv）；公式共享模式 Lightamer==reference==**dt PFM** 逐值（normal 1.0/0.8/0.625、multiply 0.5×3、difference 0.5×3、lighten；**REVERSE 0.5/0.7/0.875 与 dt 完全一致**——dt 位消费语义坐实；saturation 灰保持 0.5 双侧一致）；dt scene 回退实测坐实（darken/hue/color/coloradjust/psburn op<1 = normal 值 0.8/0.625；screen/overlay/soft/hard 同；linearburn = max(a−p·b,0) 0/0.2/0.375 精确复现 dt 场景 SUBTRACT）→ manifest「blendop golden 总账」节（regenerate.sh ④ 自动生成）+ 回退差异 **ASSERT-NOT-EQUAL 常驻**（darken/psBurn/linearBurn ≠ 0.8，未来静默公式变更即红）；LayerCompositeTests +2：感知模式灰轴不偏色（≤1 display step）+ driver 端到端 multiply 闭式 S²（无终端 base，float32 读回）；**分块恒等**：整幅 vs 行带分块派发逐字节（multiply/hue/linearBurn × 梯度 mask） |
| T6 全量回归 + 收尾 | 本提交 | 终轮 **670 / 3 skip / 0 fail**（173s）；SUMMARY/DECISIONS 落盘；轨 B 全链零增量（LayerCacheTests testTrackBFullChainWithIdentityLayerIsZeroIncrement 既有常驻 + 本轮全绿） |

## 全套测试

- 终轮：**670 / 3 skip / 0 fail**（173s，`Scripts/test-direct.sh`，构建 = `caffeinate -dis xcodebuild build-for-testing`，touch 重编后复跑）
- 基线 648 → 670：+22（BlendOpParityTests 20、LayerCompositeTests +2）
- 密码弹窗：无（单测直启路径，全程零弹窗）

## 防空转自检

- 每模式 `testEveryModeChangesTheComposite`（composite != below 逐字节 diverging > 0）✓
- parity 循环 compared>0 断言 + violations==0 精确断言（非不等式）✓
- 分块恒等逐字节（非容差）✓；REVERSE 平面交换逐字节 ✓
- 渲染类断言全部 L014 fence 读回 ✓

## 遗留 / 风险（移交 6-3+）

1. **感知模式与 dt 场景路径的公式族分歧（已定案入账）**：dt RGB_SCENE 对 hue/color/coloradjust 无 case（回退 normal）、lightness/chromaticity 用 RGB 范数缩放（blendif_rgb_jzczhz.c:703-761）；Lightamer 按 plan/CONTEXT 钉 JzCzhz 域公式族（parity 源唯一性）。dt 侧三证据对回退模式是「采纳 + 回退值记录」而非公式对照——语义分歧表在 DECISIONS D-06-02-T5-1，UI 面模式命名与帮助文案在 6-5 需按此对齐用户预期。
2. mask 平面契约 = 「红通道即有效 opacity」（dt 折叠后语义）——6-3 光栅化输出必须预乘 gopacity（BlendOpEngine/BlendOpKernels 头注已钉）。
3. alpha 走 normal 混合（非 dt 的 o.w=opacity 覆写）——不透明图像不变量由恒等三元组钉住；11 导出若需携带混合信息走 sidecar/manifest，不走 alpha（DECISIONS D-06-02-T2-2）。
4. blendParameter（dt blend_parameter）driver 层固定 1（exp2(0)）；BlendOpEngine 已参数化（multiply p 语义有测试）——层 UI 若暴露「强度」滑杆在 6-5 接 lineBlendParameter。
5. blob 420 字节 = 本机 dt 二进制实证；dt 上游若变 sizeof，「params ok」门自动红（regenerate.sh ③c2），届时按 ledger 增补尾字段。
6. `blendop_jz_probe`/`compositeRows` 为测试/验证 seam，生产路径零调用（PSO 缓存按需构建，无预暖成本）。
