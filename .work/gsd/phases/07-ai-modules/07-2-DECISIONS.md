# Plan 07-2 Decisions — skinSmooth 频率分离磨皮（AI-05）

> 执行期决策正本（plan 标注「执行期决策」项 + bring-up 发现）。RESEARCH 未覆盖细节
> 全部落此，不臆造。2026-09-24。

## D-07-2-T2-1 衰减窗形制（k_soft）与幅值口径

**裁决**：`k_soft` = **raised-cosine 软窗**（默认平滑过渡，防分段边界 banding——plan 默认项）：

```
mag = max(|h_R|, |h_G|, |h_B|)          ← 共享幅值（三通道共用同一窗因子）
lo = t·(1−w), hi = t·(1+w), w = 0.25    ← 过渡半宽 = 阈值的 25%（全窗宽 0.5t）
g(mag) = mag ≤ lo ? 1 : mag ≥ hi ? 0 : 0.5·(1+cos(π·(mag−lo)/(2wt)))
out_c = low_c + h_c·(1 − a·m·g)
```

- **共享幅值**：per-channel 独立窗会在过渡带内让 R 衰减而 G 保留 → 色相漂移；共用 mag
  保持衰减过程中色相稳定（分解仍三通道独立——线性 Rec2020 RGB，Soften 同域先例）。
- **t = 0 干净退化**：lo = hi = 0 → g ≡ 0 → out = in（全保留恒等；余弦支仅在 t > 0
  可达，无除零）。
- **硬阈值位**：w → 0⁺ 逼近 plan 公式的分段形态；v2 若要硬档可把 softness 暴露为参数
  （v1 常量 0.25，不进参数面）。

## D-07-2-T2-2 mask seam 形态（不发明新 pipe 通道）

**裁决**：kernel 的 `m` 输入 = module 的 **direct-drive 属性** `SkinSmoothModule.maskPlane`
（单通道 r32Float，output 尺寸，采样用输出 gid）。pipe 生产链路**永不绑定**
（`processErased` 无 mask 参数，未新增）——生产空间限定 = 层 mask 槽经
`MaskCombiner.effectivePlane` → blendop（Phase 6 模型不变，07-CONTEXT specifics
「mask 是层属性」）。seam 的消费者 = parity 测试（m·a 腿）与未来 base 链 API。

**恒等三元组之二语义**：mask nil == 全一纹理**逐字节**（hasMask uniform 只切分支不换
数学）；反向锚 = zero mask 经 kernel 路径回输（m=0 → 因子 1，浮点 split round-trip
≤1e-5）——证明 mask 通道 load-bearing 且 nil 语义无漂移。

## D-07-2-T2-3 σ 链 / halo / 工作集

- `r = max(1, ceil(radius·scale))`（radius ∈ [1,32] FULL 等效 px；floor 1 防 σ=0 IIR 退化）；
- `σ = √((r·(r+1)·8+2)/3)`（**highpass.c:140 援引**，与 soften/highpass 同链）；
- `halo = tileHalo = ceil(3σ)`（D7 口径，soften/highpass 双胞胎；低频腿 halo 语义继承
  L020/L021/L023）；
- `tileWorkingSetBytesPerPixel = 48`（low 16B + IIR planes 32B；in/out 归 pipe 记账）。

## D-07-2-T3-1 hull 外扩 / 保护区 margin 默认值

**裁决**：`hullExpand = 0.06`（轮廓 bounds 对角线的 6%——覆盖 Vision contour 的皮肤
边缘 undercut，均匀外扩保持凸性）；`protectShrink = 0.78`（各 region 凸包向自身质心
收缩到 78%——睫毛/唇缘留在保护区内而非边界上）。两者均为 `SkinRegionConfig` 字段，
07-3 面板可调。

## D-07-2-T3-2 额头带闭合算法

**裁决**：forehead 顶边 y = min(左右眉 y) − `foreheadLift`（默认 **0.12**，脸高的 12%）；
带 = 三合成点（眉 span 左端 / 中点 / 右端）与 faceContour 一起进 **monotone-chain 凸包**
——凸包顶边自然闭合 contour 的 U 形开口（无需显式多边形缝合）。无眉点时退化用
contour bounds 顶边。

## D-07-2-T3-3 坐标换算口径（VNImagePointForFaceLandmarkPoint 等价）

**裁决**：`p_img.x = bb.x + p·bb.w`；`p_img.y = 1 − (bb.y + p·bb.h)`（boundingBox 相对
lower-left → 图归一化 **top-left**）。roll 分量未修正（roll ≈ 0 近似——±45° yaw 门
工作范围内误差可忽略；roll 修正留给 v2 若 GUI 实测出现侧倾脸 hull 偏移）。

## D-07-2-T3-4 personSeg / faceLandmarks 的 pin 现实（回注 planner）

**实测**：`GeneratePersonSegmentationRequest` 与 `DetectFaceLandmarksRequest` 均为
compute-device API 之前的旧请求——**无 `supportedComputeStageDevices` /
`setComputeDevice` 面**。处置（与层 A/B guard 同语义）：pin 请求 → typed
`AIMaskError.deviceUnavailable`（`.anePreferred` 唯一支持）；unpinned 路径 Vision 自行
路由 OS 内置模型（07-1 D-07-1-T1-2 层 B unpinned 逐字节确定的同款先例）。07-CONTEXT
「Vision 测试 pin CPU」红线对这两个请求**不可达**——以 typed-refusal 测试锚替代。

## D-07-2-T3-5 yaw 门与真模型腿

- 门 = **严格大于**（|yaw| = 45° 整的脸保留使用）；超限脸排除出 union + typed
  warning（faceExcludedHighYaw 带 yaw/limit payload）；全部被 gate →
  `SkinRegionError.noUsableFace`（不落 mask——生成失败严格性）。
- 真模型腿：合成卡通脸（CoreGraphics 椭圆+五官）→ `VisionFaceLandmarkProvider` →
  bbox 容差方向断言；本机测试宿主**未检出**（skip-with-reason，07-1 层 B entitlement
  先例）；**07-3 GUI 轮真实 app 复验**（与层 B 同一登记口径）。服务逻辑（换算/几何/
  错误腿）已全量覆盖。

## D-07-2-T4-1 parity 钉参与容差

- **6 case**：skin_default（r8/a0.5/t0.02）/ skin_strong（r12/a0.9/t0.05）/ skin_fine
  （r4/a0.3/t0.01）/ skin_edge_transition（r8/a0.7/t0.03，边界过渡带）/ skin_maxstrength
  （r6/a1.0/t0.02）/ skin_smallthreshold（r6/a0.8/t0.005，近硬阈值）。
- **6 fixture**（既有管线，零新生成脚本——解析参考轨口径同 mask 节，常驻测试即证据）：
  gradient_ramp / flat_0ev / flat_-4ev / checkerboard / delta_impulse /
  ramp_8ev__noisy_iso125_s20260921。
- **双闸**：rel <1e-5 且 abs <1e-5（abs floor 放过近零区的 rel 放大）；实测低频腿
  float64 parity 7.2e-7。参考 σ 链 Double vs 模块 Float 的 ulp（~2e-7 相对）由门吸收。
- graded-mask 腿（m·a 经 kernel）在首 fixture × 全 case 复跑。

## D-07-2-T5-1 tiling 抽查与种子

- **tiling 抽查**：强制 2MB tile 预算 vs 整幅，seam 残差界 **1e-4**（IIR 尾部超出
  3σ halo 的包络；r8 → σ≈13.9 → halo 42px，fixture 尺度已近整幅——界是保守记录，
  100MP 实拍尺度下 halo 占比更小，超预算则只记录不改架构，plan 口径）。实测 maxDiff
  < 1e-4 全绿。
- **种子**：ENABLED-neutral（a=0 blit 恒等，cache 中性，liquify 空路径 disposition）；
  轨 B 零增量测试钉死（种子链含/不含 skinSmooth 逐字节相等）。

## 执行期发现（bring-up 记录，不改变裁决）

1. **自研参考的转置 bug**（已被 parity 门当场抓获——L017 自研参考的价值实证）：
   `SkinSmoothReference` 列 pass 的 store4/accumulate4 参数序（row, x）被传成
   （x, y），平面转置 → GPU vs 参考差 2x；修复后 7.2e-7。
2. **Tuist 新文件惯例**：新源文件/新目录须 `tuist generate` 后才进 project（既有
   惯例重申，非新发现）。
3. **StatefulRequest perform 返回非 Optional**（personSeg）；layer A/B 的
   `guard let observation = perform(...)` 模式不适用于它——直接接收。
4. **V50Order 66.5 插行零回归**：全量 812→838+ 全绿（数字见 SUMMARY）；既有行零
   移动由 testSkinSmoothInsertionMovesNoVerbatimRow 钉死（neighborhood 值 + lut3d
   listing-order 签名 + strip-to-93）。
