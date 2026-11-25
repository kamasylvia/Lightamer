# 塔台核验记录：gpui-fast 三路侦察

日期 2026-11-25。核验对象 = 同目录 `R1-FRAMEWORK.md`、`R2-CAPABILITIES.md`、`T1-BENCH.md`（三路 omp 侦察兵产出，零 commit，由塔台统一提交）。
原则：先核证据，再读结论；以源码和原始轨迹为准，作者文档只作线索。

## §0 结论头

三份报告的关键数字和出处经独立复核**全部成立**，一处结论被推翻并更正：

- **更正 R1 §7 A.2**：R1 写「列表层默认关闭」，出自作者文档 `docs/architecture.md` 的 Lists 一节。该文档已滞后：0.1.19 源码 `src/fast/layers/lists.rs:79` 是 `LIST_LAYERS: bool = true`。R2 读的是源码，是对的。
- **T1 的帧数逐项重数一致**（见 §3）。
- **附带发现一个环境问题**：本机当前每个新 GUI 进程首次建窗要等约 2.07 秒，卡在系统字体服务的应答上（见 §4）。它只影响「启动」类数字的绝对值，不影响 pre 与 fast 的差值。

## §1 R1（框架调研）核验

| 出处类型 | 抽查内容 | 结果 |
|---|---|---|
| 本机 crate 源码 | `layers/mod.rs:33` 的 `COMPILED`、`:49/:75` 的 `GPUI_SCROLL_LAYERS`、`retained.rs:293` 的 `GPUI_VIEW_RETENTION`、`metal_renderer.rs:213` 的 `setMaximumDrawableCount(3)`、gpui-pre 的 `zed-rev`、gpui-kit 的特性定义行、`extern crate gpui_fast as gpui` 两处 | 全部对上 |
| GitHub | 仓库 `has_issues=false`、创建时间 2026-09-24、683 star / 94 fork、`UPSTREAM` @v0.1.19 的 `zed_commit`、`upstream-sync.md` 规则 5、`architecture.md` 的 +609/−776 | 全部对上 |
| issue | gpui-kit #4057 / #3946 / #3865 均为 open，标题相符 | 对上 |
| crates.io | gpui-fast 19 个版本（0.1.0@2026-10-06 → 0.1.19@2026-11-23，无 0.1.18）、gpui-pre 15 个版本、下载量 259043 | 对上 |

小出入：R1 写 Zed 官方 `gpui`「全站仅 7 个版本」，其中含已撤回的；非撤回版本是 4 个（0.1.0@2022-06-23、0.2.0–0.2.2@2025-10）。结论不变：官方包停在一年前，T1 的 zed 列量的是旧包。

## §2 R2（能力调研）核验

| 抽查内容 | 结果 |
|---|---|
| `wantsExtendedDynamicRangeContent` 在全部 gpui-fast-* 与 gpui-pre-* crate 中零命中 | 对上 |
| 窗口层 `MTLPixelFormat::BGRA8Unorm`（fast `metal_renderer.rs:200`、pre `:190`）；`use_display_p3` 默认 false（`platform.rs:2926`） | 对上 |
| `paint_layer` 签名：pre `(f)` @`window.rs:4965`、fast `(bounds, f)` @`:5026` | 对上 |
| `paint_surface` 的 NV12 硬断言（fast `metal_renderer.rs:1298`） | 对上 |
| 动态纹理公开面（`create/update/refresh/paint/remove_dynamic_texture`） | 对上 |
| gpui-kit #3658 / #3605 / #3456 / #2488 均 open；示例 `native_webview.rs` 存在；PR #157 / #103 / #169 已合并 | 对上 |

补充（R2 未提，不改变结论）：`fast/dynamic_textures.rs:127` 的 `DynamicTexturePlatform` 是公开 trait，`:161` 的 `set_dynamic_texture_platform` 是公开接缝。它的两个方法都是「按字节上传」语义，仍然没有「交出现成 GPU 纹理」的入口。

R2 其余行号级引用没有逐条核。

## §3 T1（本机实测）核验

### 3.1 帧数独立重数

工具：塔台自写 awk（与 T1 的 `analyze.py` 无关），读 `traces/*.run` 原始轨迹。判据同探针：`cells ≥ 1 && maxd ≥ 10`。

| 项 | 报告 | 塔台重数 |
|---|---|---|
| T1a 拖动窗口内变化帧，pre / fast | 24/27、23/26 | 24/27、23/26 |
| T1b 拖动窗口内变化帧，pre / fast | 22/26、23/26 | 22/26、23/26 |
| T2 变化帧间隔 >33.3 ms 的个数，pre / fast | 5、7 | 5、7 |
| T3 变化帧数，pre / fast | 57、60 | 57、60 |
| T3 间隔 >33.3 ms 的个数，pre / fast | 4、6 | 4、6 |
| T2 变化帧率 | 51.1、50.2 fps | 变化帧数 59–60 / 58–60（窗口边界取法略有差别） |

步延迟中位数：塔台 7.2–7.9 ms，报告 8.2–9.0 ms（百分位取整方法不同）；方向一致，都在半个刷新帧以内。

### 3.2 截图与二进制

- `shots/t1a-pre-panel.png`、`shots/t1a-fast-panel.png` 目视：两张都是曝光 −1.580 EV、填充条缩短、三角标左移，列表停在滚动后的位置。与报告描述一致。
- 文字对比：`bench/out/t6-pre.png` 与 `t6-fast.png` 的 md5 相同（`84e6dc41…`），整窗逐字节相同。
- 被测二进制 sha256 前缀：pre `98bb3430ba7b4745`、fast `6749a3ddc7e00d26`，与报告一致。

未重数：T5（空闲与滚动占用）、T7（外部画面）、T9（10 分钟稳定性）的轨迹只读了报告，没有自己再算一遍。

### 3.3 没测成的项（报告如实列出）

- T8 窗口角拖拽缩放：合成事件在本机不触发系统缩放手势，连 AppKit 对照窗也不动。
- T7 的 `surface()`：BGRA 被源码断言拒绝；改成 NV12 后仍不出画，缓冲区是否真拿到 IOSurface 没有验证。
- 全部交互均为合成事件，真实鼠标手感没有人验过。

## §4 环境发现：首次建窗 2.07 秒的地板

**现象**：一个只建空窗口的 40 行 AppKit 对照程序（`bench-src/appkitfloor2.swift`），10 次运行中「`NSWindow` 创建」一步稳定耗时 2.06–2.10 秒；`NSApplication.shared` 只要 40–140 ms，`orderFront` 只要 1–8 ms。

**定位**：`sample` 采样主线程，约 78% 的样本落在同一条栈上：首次取系统字体 `+[NSFont systemFontOfSize:]` → `XTCopyFontWithName` → `TGlobalFontRegistry::CreateRegistry` → `RendezvousWithServer` → 等待字体服务的同步 XPC 应答。字体数量正常（系统 369、用户 1）。`fontd` 开机起已运行 20 天。

**与启动方式无关**：同一分钟内，经 `open`（LaunchServices）启动 2 次、直接执行 2 次，都是 2.07–2.08 秒。

**不是一直这样**：今天的 GUI 计时报告里，Lightamer（01:34）启动到窗口 0.36–0.37 秒，Alcedo（03:48）启动 0.8 秒。地板是今天白天才出现的。

**影响范围**：

- T1 的启动项（原型 3.77 秒、最小程序 3.5–3.75 秒）含这 2 秒；pre 与 fast 的差值（6 ms）不受影响。
- Lumen（04:37）、RawLab（05:42）、LightCraft（06:31）的冷启动数可能含这 2 秒：RawLab 与 LightCraft 都是 2.3 秒出窗口，可疑但未证实。
- Lightamer、darktable、Alcedo 的冷启动数早于地板出现，不受影响。

**处置**：`fontd` 未动。重启它需要用户同意；重启后应把受影响的三家「启动到窗口」重量一遍。

## §5 仍未验证

1. macOS 上把 `create_native_surface()` 给的 NSView 换成 `CAMetalLayer` 并开出 EDR：只有 Linux 的 wgpu 示例，没有第一手验证。这是跨平台路线里视口与 HDR 的唯一通路。
2. Linux 与 Windows 上的实际表现：R1、R2 只有源码与 CI 证据，本机没有跑过。
3. 十万行可变行高列表：只有等高列表的实测。
4. gpui-fast 作者的性能数字全是 Linux 的；本机 macOS 上 fast 与 pre 在这套原型上同速，fast 的收益要在更重的界面上才看得出还是根本没有，本轮没有结论。
