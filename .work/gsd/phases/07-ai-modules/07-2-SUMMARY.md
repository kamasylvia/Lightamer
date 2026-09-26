# Plan 07-2 Summary — skinSmooth 频率分离磨皮 iop（AI-05）

**Status: COMPLETE**（2026-09-24；5/5 任务；全 suite **830 tests / 6 skip / 0 fail（×1 复跑轮；首轮曾现 GoldenColorTests.testCrossConsistencySyntheticTarget 一次 flaky fail，单独+全套复跑均绿——顺序依赖 display-profile 状态嫌疑，与 07-2 改动无关，遗留 4 登记）**（基线 812→830 +18；skip 变化 = 真模型腿 skip-with-reason，见下）；未 push）

## 任务完成表

| 任务 | commit | 交付 | 验证数字 |
|---|---|---|---|
| T1 V50Order 66.5 + 模块骨架 | `fbc9045` | `skinSmooth = 66.5` 新行（soften 66.0 / splittoning 67.0 之间，**dt verbatim 表插非 dt 行项目首例**——表头 + 行内双标记，dt 纪律同等适用）+ SkinSmoothModule（三滑块参数面 radius σ/strength a/detailPreserve t + Variant enum 位预留【v1 单 case twoBandGaussian】+ 全 IOPModule conformance + ROI 恒等/ceil(3σ) 反向 halo）+ Registry 注册 + ENABLED-neutral 种子 + prewarm | V50OrderTests 14/14（含 66.5 槽位/顺序/唯一 + **零移动钉**：neighborhood 值 + lut3d listing-order 签名 + strip-to-93）；ModuleBoundary/IOPModule/LayerComposite/TerminalTrio 回归 OK |
| T2 阈值衰减 kernel + 三元组 | `56d28c8` | `skin_smooth_mix` kernel（low = **既有 GaussianBlur Deriche IIR 复用零重写**；高 = I − low；衰减 = raised-cosine 软窗【D-07-2-T2-1】× m·a；共享 RGB 幅值防色偏）+ **恒等三元组**：a=0 blit 逐字节 / mask nil == 全一 mask 逐字节 / 平场 DC-1 恒等 <1e-5 + zero-mask kernel 路径反向锚 | SkinSmoothParityTests 5/5（bit-pattern 级比较 + compared>0 防空转） |
| T3 SkinRegionLocator | `fb93c95` | 纯 Swift 几何链（contour hull + 额头带闭合 − eyes∪brows∪outerLips∪nostrils 保护区 ⊗ personSeg + 多脸 union + yaw 门 + 羽化经 bake featherRadius）+ FaceLandmarkProviding 注入 seam + VisionFaceLandmarkProvider + SkinRegionService.locate/bake（07-3「定位皮肤」后端）+ AIMaskService.personSegmentationMask（.accurate） | SkinRegionGeometryTests 8 exec / **1 skip-with-reason**（真模型腿卡通脸未检出——07-1 层 B entitlement 先例，07-3 GUI 复验）/ 0 fail；07-1 AI 三套件回归 OK |
| T4 float64 参考 + parity | `4f5baf8` | SkinSmoothReference（IIR 低频腿 Double 直译 + 系数同 float32 grid + 阈值衰减逐式；lowBand 暴露）+ **6 case × 6 fixture 双闸 parity <1e-5**（含 graded-mask m·a 腿）+ manifest skinSmooth 节（L017 分流落账——无 dt 轨） | 36 组合全绿（低频腿实测 7.2e-7）；bring-up 抓获参考平面转置 bug（parity 门价值实证） |
| T5 轨 B + 收口 | 本 commit | **轨 B 零增量**（种子链含/不含 skinSmooth 逐字节相等——retouch 空层同款 disposition）+ tiling 抽查（强制 2MB tile vs 整幅，seam 残差 <1e-4 界内，D-07-2-T5-1）+ 全量回归 + TODO/GOAL-STATE/本文件/DECISIONS | 轨 B 8 tests 0 fail；全套见上 |

## 关键执行期发现（正本 = 07-2-DECISIONS.md，9 条 + bring-up 4 条）

1. **k_soft 形制（D-07-2-T2-1）**：raised-cosine 软窗（过渡半宽 0.25t）× 共享 RGB 幅值
   max(|h_R|,|h_G|,|h_B|)——per-channel 独立窗会在过渡带漂色相；t=0 干净退化为全保留。
2. **mask seam（D-07-2-T2-2）**：module direct-drive `maskPlane` 属性，pipe 永不绑定
   （processErased 无 mask 参数，零新通道）——生产空间限定 = 层 mask 经 blendop
   （Phase 6 模型不变）；nil == 全一逐字节 + zero-mask 反向锚。
3. **personSeg/faceLandmarks 无 compute-device API（D-07-2-T3-4，回注 planner）**：
   两旧请求无 supportedComputeStageDevices/setComputeDevice 面——pin 请求 typed 拒绝
   （anePreferred 唯一）；07-CONTEXT「测试 pin CPU」红线对这两腿不可达，以
   typed-refusal 测试锚替代。
4. **自研参考 bring-up bug**（D-07-2 执行期发现 1）：参考列 pass 平面转置（store4
   参数序 (row,x) 被传 (x,y)）→ GPU vs 参考差 2x——parity 门当场抓获，修复后 7.2e-7
   （L017 自研参考轨的价值实证）。
5. **真模型腿**（D-07-2-T3-5）：合成卡通脸在测试宿主未检出 → skip-with-reason
   （与 07-1 层 B 同登记）；服务逻辑全测，**07-3 GUI 轮真实 app 复验**（追加登记）。

## 交付面（移交 07-3）

- `SkinSmoothModule`（66.5 槽 + ENABLED-neutral 种子）——07-3 面板四件套的驱动面
  （三滑块 + 变体位）。
- `SkinRegionService.locate / bake` + `VisionFaceLandmarkProvider`——「定位皮肤」按钮
  接线即用（bake 羽化经既有 featherRadius）。
- `AIMaskService.personSegmentationMask`——skin 链的 person matte 腿（OS 内置离线）。
- 测试锚全常驻：V50OrderTests / SkinSmoothParityTests（8）/ SkinRegionGeometryTests（8+1skip）。

## 验收标准对账

- [x] V50Order 66.5 新行 + 表头「非 dt 行」标记（项目首例）+ 唯一性/零移动断言 + 全量回归零破坏
- [x] 频率分离 parity <1e-5（σ×a×t 6 case 双闸）+ 恒等三元组逐字节（a=0 / mask 空 / 平场）
- [x] hull 几何解析断言 4 case（正脸/侧脸 yaw 门/多脸 union/空 landmarks 降级）不依赖模型输出；真模型腿方向断言（宿主 skip-with-reason + 07-3 复验登记）
- [x] 低频腿 = 既有 GaussianBlur 复用（零重写）；L018 纪律合规（planes buffer 双平面沿用）；衰减只作用幅值、linear Rec2020 RGB 分解
- [x] variant enum 位预留（v2 多频/bilateral 升级缝）+ 决策（k_soft/hull 外扩/margin/yaw 阈值/tileHalo）入 `07-2-DECISIONS.md`（9 条）
- [x] manifest skinSmooth 节（自研参考口径 + L017 分流落账）+ 轨 B 中性插链零增量 + 全量 suite 0 fail + SUMMARY 落盘

## 遗留/风险

1. **真模型腿未在测试宿主复验**（卡通脸未检出）——07-3 GUI 验收轮真实 app 复验
   （与 07-1 层 B 端到端同一登记项，两条并案处理）。
2. **坐标换算 roll 近似**（D-07-2-T3-3）：roll ≈ 0 假设；若 GUI 实测侧倾脸 hull 偏移，
   v2 加 roll 修正（VNImagePointForFaceLandmarkPoint 的 roll 分支）。
3. **tiling seam 残差**为 IIR 尾部包络（<1e-4 界记录在案）；100MP 实拍尺度复检留
   07-3 GUI 轮（不设架构变更预期——halo 口径与 soften/highpass 同源）。
4. `GoldenColorTests.testCrossConsistencySyntheticTarget` 在全套运行中出现一次
   ColorSync 低端区发散（单独重跑 PASS——顺序依赖 flaky，与 07-2 改动无关的
   display-profile 状态污染嫌疑）；已在复跑轮核实（见 SUMMARY 数字行），若再现
   建议登记 TODO 单独排查。
