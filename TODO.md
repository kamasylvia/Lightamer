# TODO — Lightamer

> 镜像 `.planning/ROADMAP.md`（13 phases, 123 v1 reqs）+ 当前执行状态。
> 阶段进度以 `.planning/STATE.md` 为准。

---

## 🚧 当前阻塞：环境就绪（换机后第一件事）

Phase 1 已规划完成（6 plans, 2 waves, 全部 verified），但执行被环境阻塞。换到另一台机器后，**先确认以下两项就绪**：

- [ ] **Xcode 27 beta**（含 macOS 27 SDK）已安装并 `xcode-select` 切换到位
  - 下载：[developer.apple.com/download](https://developer.apple.com/download)（需 Apple Developer 账号）
  - 切换：`sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer`
  - 验证：`xcodebuild -showsdks | grep "macOS 27"` 应输出 macOS 27.x
- [ ] **Tuist** 已安装
  - `brew install tuist`
  - 验证：`tuist version`

两项就绪后，运行 `$gsd-execute-phase 1` 开始执行（Plan 01→02→03→04→05→06 顺序，因依赖链 Wave 1 必须顺序）。

---

## 项目初始化（已完成 ✓）

- [x] GSD 项目初始化（PROJECT.md / config.json / 5 份研究 / REQUIREMENTS / ROADMAP 13 phases / STATE）
- [x] GitHub 仓库 + Azure DevOps 镜像；分支 master→main；远程 origin = Azure
- [x] AGENTS.md / TODO.md / LESSONS.md 三件套建立
- [x] 关键决策锁定：macOS 27 floor、linear Rec2020 float32 RGBA、v50_order、Metal-first/CIRAW-as-decoder、sidecar 自有格式、多 target + Tuist 解耦

## Phase 1: Foundation, App Skeleton & Capability Spikes — 规划完成，待执行

**状态**：6 plans 已 verified（0 BLOCKER）、RESEARCH/CONTEXT/UI-SPEC/VALIDATION 齐全、38/38 决策覆盖、11/11 需求覆盖。

**架构（多 target + Tuist，D-02/D-03 修订）**：
- `LightamerCore`（framework）— Decode/Metal/Pipe/Layers/Foundation
- `LightamerIOP`（framework，依赖 Core）— iop 模块集（Phase 1 仅 Passthrough）
- `Lightamer`（app，依赖 Core+IOP）— UI/Session/Export/Yiyin/AI
- `LightamerTests` + `LightamerUITests`

### Wave 1（顺序，构建端到端 vertebra "打开 RAW → 显示"）
- [ ] **Plan 01** — Tuist Project.swift + app shell（三栏 NavigationSplitView、强制深色、空状态、toolbar、菜单栏）+ WorkingSpace/AppError（Core/Foundation, public）+ SessionState/EditorState/ExportState/InspectorState 隔离（D-03b）
- [ ] **Plan 02** — RAWDecoder（Core/Decode, public）CIRAWFilter 封装 + RAW 9 opt-in+降级 + 元数据三类 + 统一 RAW/非RAW 入口 + async 可取消解码
- [ ] **Plan 03** — MetalContext（Core/Metal, public）+ CIContextPool + 两层 dispatch + 懒加载 PSO cache + function-constants + EditorMTKView（app/UI）render-pipeline blit — **完成 tracer**
- [ ] **Plan 04** — IOPModule 协议（Core/Pipe, public）+ V50Order（Core/Foundation, port iop_order.c:298-415）+ **Layer 骨架（Core/Layers, D-03a）** + PassthroughModule（IOP）+ PixelPipe 骨架（layer-aware）

### Wave 2（验证 + 包装）
- [ ] **Plan 05** — Spike A（CIRAW 9 能力边界）+ Spike B（100MP GFX100S 性能），独立 spike 分支 + 报告 + golden samples
- [ ] **Plan 06** — 测试骨架（Tests+UITests）+ 模块 API.md（D-03c）+ os.signpost 性能基线

**执行命令**：`$gsd-execute-phase 1`

## Phase 2-13（已规划，未开始）

| # | Phase | Reqs | 关键内容 |
|---|-------|------|---------|
| 2 | Pixelpipe Core, Color Mgmt & History | 8 | per-module cache、terminal trio、history stack+hash、sidecar、layer-aware pixelpipe |
| 3 | Tone & Filmic iops | 10 | exposure/WB/curve/shadhi/levels/toneq + filmicrgb（最难移植） |
| 4 | Geometry, Lens & Detail iops | 8 | crop/rotate/lens/sharpen/localcontrast |
| 5 | Color & Denoise iops | 12 | colorbalancergb/colorzones/monochrome + profiled denoise（第二难） |
| 6 | Layers & Masking System | 14 | C1 调整图层 + drawn/parametric/raster mask + blend modes + liquify/retouch（最大架构阶段，Layer 骨架已就位） |
| 7 | AI Modules（Native Vision） | 4 | 主体检测 + 频率分离磨皮（仅 Apple 原生 API） |
| 8 | HDR/Stacking & Effects iops | 10 | HDR merge/focus stack + EDR + vignette/grain/bloom/dehaze |
| 9 | Capture One Session Management | 8 | 文件夹即会话 + Capture/Crop/Output + FSEvents + 多会话 + 复制粘贴/前后对比 |
| 10 | yiyin Border/Watermark Panel | 8 | 印框/EXIF/日期/Logo/字体/品牌归一化，移植为原生 |
| 11 | Export Pipeline & Batch Queue | 8 | 6 格式 + 配方 + 后台队列 + yiyin 应用 |
| 12 | Metadata, Rating, Presets & LUT | 11 | 评级/标签/关键字/智能相册 + 原生预设 + .cube LUT |
| 13 | System Integration & Distribution | 11 | Quick Look/Spotlight/软打样/多 ICC/手势/i18n + GitHub 开源/签名公证/CI |

详细需求/成功标准见 `.planning/ROADMAP.md`，需求清单见 `.planning/REQUIREMENTS.md`。

## v2（已记录，不在当前 roadmap）

AI 追色 / AI 评分 / AI 天空分离 / AI 人像部位 / AI 通用语义分割（需自定义 Core ML 模型）/ 联机拍摄 / 地图视图 / 打印 / 跨 Session 搜索

---

*镜像自 `.planning/ROADMAP.md`。阶段进度以 `.planning/STATE.md` 为准。*
