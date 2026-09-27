# QL 渲染时延探针(Plan 13-1 T2)— perf.md

> 实测日期:2026-09-27;机器:macOS M2 (darwin 27.0),Debug 构建。
> 探针:`Tests/LightamerTests/QuickLookPerfProbeTests.swift`(门控 `LA_QL_PERF=1`,
> 不入常驻 suite);原始表落盘 `/tmp/la-ql-perf.md`,渲染路径 =
> `QuickLookRenderer` 前身原型(default chain → sRGB display-terminal →
> CGImage)。
> 口径:每格 = 1 冷 + 3 热取中位。**冷** = 该格进程内首次渲染;全表唯一
> 真「PSO 编译冷」是第一格(100MP@512,已标注);A7R V@512 冷额外含
> RAW 9 CoreML 模型一次性编译(decode 冷 2.62s → 热 0.11s)。

## 时延全表(秒)

| sample | long edge | cold (s) | warm median (s) | warm ×3 (s) | out px |
|---|---|---|---|---|---|
| 100MP GFX100S RAF | 512 (thumb) | 2.249(PSO) | 0.166 | 0.177 / 0.166 / 0.164 | 512×384 |
| 100MP GFX100S RAF | 1440 (mid) | 1.541 | 0.702 | 0.697 / 0.702 / 0.709 | 1440×1080 |
| 100MP GFX100S RAF | 2560 (fit) | 2.858 | 2.080 | 2.064 / 2.080 / 2.080 | 2560×1920 |
| A7R V ARW (mid) | 512 (thumb) | 5.442(CML+PSO) | 0.194 | 0.191 / 0.198 / 0.194 | 512×341 |
| A7R V ARW (mid) | 1440 (mid) | 3.354 | 0.688 | 0.686 / 0.695 / 0.688 | 1440×960 |
| A7R V ARW (mid) | 2560 (fit) | 5.109 | 1.925 | 1.925 / 1.917 / 1.940 | 2560×1707 |

分项(冷格分解):

| 格 | decode | pipe+exit | 归因 |
|---|---|---|---|
| 100MP@512 冷 | 0.262 | 1.986 | 全局 PSO 编译落在 pipe 腿 |
| A7R V@512 冷 | 2.623 | 2.818 | decode 腿 = RAW 9 CoreML 一次性编译;pipe 腿 = 该样张首配管 |

## 读数

- **热稳态**:缩略(512)0.17–0.19s;中档(1440)≈0.7s;QL fit(2560)1.9–2.1s。
  100MP 与中等 RAW 同尺寸热时延几乎相同(瓶颈 = 管线吞吐,非解码——解码
  热 0.08–0.12s)。
- **冷**:一次性编译(PSO / CoreML)落在 2–5.4s;系统缓存落盘后通常一次付费。
- 尺寸-时延近线性:512→2560 约 ×12 像素、×12 时延,无超线性拐点。

## 超时阈值结论(D-13-CONTEXT-2 定名参数)

- **`QuickLookRenderer.renderTimeout = 30s`**(thumbnail / preview 共用单一常量)。
- 依据:最坏单点冷观测 5.44s(A7R V@512,含一次性编译)→ ×5.5 安全系数;
  热稳态最坏 2.08s,正常路径永不触发;真卡死(GPU hang / 损 sidecar 死循环)
  在 30s 内转档 A 嵌入预览(Finder 体验仍可用,档 A 为 ms 级)。
- 超时语义 = 等待上界(渲染任务后台跑完进 void,不取消 GPU mid-flight,
  SessionThumbnailProvider.cancelAll generation-gate 同款先例)。
