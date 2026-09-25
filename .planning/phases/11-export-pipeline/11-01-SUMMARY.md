# Plan 11-01 — SUMMARY（导出模型 + 唯一 SPM 依赖，W1）

> 执行：2026-09-26，ZCode subagent worker（omp 分工制下的验收前执行件）。
> 基线全 suite **1133/6skip/0fail** → 终轮 **1187/6skip/0fail**（净增 54）。
> 未 push（Phase 11 纪律）；每任务边界检查 `.work/config.toml [gsd]`（全程 auto=true/paused=false）。

## 任务表

| 任务 | 交付 | commit | 证据 |
|---|---|---|---|
| T1 ExportVariant/ExportRecipe 模型 | `LightamerCore/Sources/Export/ExportRecipe.swift` + `ExportRecipeTests.swift` | `c4bd371` | 22 tests：Codable round-trip（px 1..100_000/dpi 1..2400/quality 0..1 边界）+ 校验向量（quality 越界 ×8 逐例 throw invalidParameter）+ scalePercent 域 (0,10_000] + **percent 换算向量**（50%/25%/33%/33.4%/100/3 %、纵横长边、>100 钳源、≥1px 地板、DPI 保留）+ tag 派生向量（单 nil/多尺寸格式/显式优先/空白视缺/冲突消歧）+ 正交性 + 零哈希字段审计 |
| T2 输出命名与冲突递增 | `ExportNamer.swift` + `ExportNamerTests.swift` | `559065c` | 16 tests：`<stem>[_<tag>].<ext>` 形状 + `-1/-2` 递增（含 gapped run 取首个空位）+ 大小写不敏感占用 + 特殊字符策略（`/` `:` → `-`、空/全 dash → Untitled、Unicode 原样）+ 纯度断言（不创建目录不摸 FS） |
| T3 ExportQueue 契约骨架 | `ExportQueueContract.swift` + `ExportQueueContractTests.swift` | `84a91f4` | 12 tests：合法/非法迁移向量全表 + 终态零出边 + Sendable 编译期证明（8 类型泛型约束）+ concurrency==1 + yieldsToEditor==false + leg round-trip |
| T4 Swift-WebP SPM 接线 | `Project.swift` + `WebPIntegrationSmokeTests.swift` | `d12311b` | 4 tests：1×1 lossy/lossless encode（RIFF/WEBP header + bitstream features 断言）+ lossless decode round-trip 逐字节 + libwebp ≥1.5 版本钉。fetch 走代理一次（见下），build 0 告警（dangling pointer 清零后 amend） |
| T5 回归 + 收尾 | 本文件 + DECISIONS + TODO + PROGRESS log | T5 本提交 | 全套 **1187/6skip/0fail**（295.9s） |

## Verification 对照

| 验收面 | 判据 | 结果 |
|---|---|---|
| 模型层 | `Scripts/test-direct.sh 'ExportRecipeTests'` | ✅ 22/22 |
| 命名 | `Scripts/test-direct.sh 'ExportNamerTests'` | ✅ 16/16 |
| 契约 | `Scripts/test-direct.sh 'ExportQueue'` | ✅ 12/12 |
| SPM | build 过 + `WebPIntegrationSmokeTests` | ✅ 4/4，build-for-testing exit 0 |
| 回归 | 全 suite 0 fail（1133→N） | ✅ 1187/6skip/0fail |

## SPM 版本钉记

- **Swift-WebP**：manifest `from: "0.6.0"` → 实际 resolve **0.6.1**（`git describe` 于 DerivedData checkout）。
- 传递依赖 **libwebp-Xcode**（libwebp 1.5.0+ C 源码包，SPM 原生构建，无 xcframework 下载步）。
- product `WebP`（static）挂 LightamerCore + LightamerTests 双 target——static product 双链接告警判 benign（各自静态拷贝，无符号冲突面；D12）。
- strict concurrency（D-33 complete）：包本体编译零告警，R2 预案（圈 actor 单编码路径）**未触发**。

## fetch 网络实录（R3 预案留痕）

1. 直连首次 `tuist generate`（SPM resolve）失败——根因非 GitHub 不可达，而是**会话环境变量常开代理**（`http_proxy=127.0.0.1:10809` 等）指向**未运行的 xray daemon**（git clone → Connection refused 10809）。
2. `px --up` 起 daemon：第一次被自身代理 env 反坑（xray.py 经 uv 拉 requests 也走死端口）→ `env -u http_proxy … px --up` 清 env 重跑成功，curl 经 10809 到 GitHub 返回 200。
3. `tuist generate` 重跑 → WebP 0.6.1 解析成功；**`px --stop` 收尾**，无残留。
4. plan 字面命令 `tuist fetch` 在 Tuist 4.208 不存在（`tuist install` 只管 plugins/外部内容；**SPM 解析发生在 `tuist generate`**）——执行期修正入 DECISIONS D9。

## 与 SessionThumbnailProvider 契约面逐件对照（T3 证据）

| 9-3 件（SessionThumbnailProvider.swift） | 导出契约（11-01） | 对照结论 |
|---|---|---|
| `ThumbnailDecodeLeg`/`ThumbnailRenderLeg` typealias（:107-110） | `ExportRenderLeg`/`ExportEncodeLeg`（@Sendable 闭包 + 测试缝语义同款） | ✅ 同构 |
| `QueuedJob{relPath,row,visible,seq,generation}`（:145-151） | `ExportJobSnapshot{id,imageURL,relPath,variants,seq,generation,state}` | ✅ 同构；document 快照（instances+layerStack）留 11-04 actor 私有，不入 UI 快照 |
| `defaultConcurrency = 2`（:154-157） | `ExportQueueContract.concurrency = 1` + 头注钉内存推导（单 job 峰值 ≈5GB@100MP，RESEARCH §4.5） | ✅ 值不同、形状同 |
| `defaultIdleDelayMs = 1500` + visible jump（:140-143/:247-254） | **无**（导出吞吐非交互，RESEARCH §4.1 明示不要） | ✅ 刻意不复用 |
| generation epoch + `cancelAll()`（:256-269） | 状态机终态 `cancelled` + `generation` 字段承载；epoch bump/pump/gate **实现 = 11-04** | 契约面已预留（本 plan 只钉类型） |
| `pump()`/`execute()` generation gate（:272-310） | 同上，11-04 | 同上 |
| `waiters: CheckedContinuation` | 同上，11-04 | 同上 |
| idle/visible 调度 | — | 同上「不要」行 |
| `ExportJobState`（pending→rendering→encoding→done/failed/cancelled） | 9-3 无对应（缩略图无中间相） | 导出新增；canTransition 无 default 的穷尽 switch = 编译期不可达 |

## AC 自检（plan 验收标准逐条）

- [x] ExportRecipe/ExportVariant 值类型齐备：sizing=YiyinExportSettings 复用（OQ-11-6）+ 六格式参数面（jpeg/png 8|16/tiff 8|16|f32×none|lzw|zip/heic 8|10/avif 8|10|12/webp 8bit+lossless 独立面）+ 五色域 + yiyin 开关 + tag 派生 + scalePercent 换算向量（checker R1-E2/R2 补点均落）；Codable round-trip；零哈希字段（L013）
- [x] 输出命名纯函数：`<stem>[_<tag>].<ext>` + `-1/-2` 递增 + 不摸 FS（测试含「不创建目录」反证）；Output/ 默认落点引用钉注在 ExportNamer 头注（EXP-08 义务 + SessionLayout.outputDirectory(for:) 9-1 移交常量，11-04 App 侧接线）
- [x] 契约骨架：状态机/快照/进度两层/leg 缝/concurrency=1 内存推导头注/yieldsToEditor 接口位（v1 不实现，注释钉 Phase 15）
- [x] Swift-WebP 唯一 SPM 依赖：fetch 成功（px 代理一次性留痕）+ build 过 + 冒烟绿；无额外加包（Project.swift packages 数组恰 1 项）
- [x] Core/Export/ 目录落位（LightamerTests 只 import Core 红线）；落位修正 + 全部执行期决策入 11-01-DECISIONS
- [x] 全 suite 0 fail（1187/6skip）；每任务独立提交 ×4 + T5 收尾提交；边界查开关 ×4；不 push；无 /tmp 过程产物入仓（构建日志全在 /tmp）；SUMMARY + DECISIONS 落盘

## 新增测试计数

ExportRecipeTests 22 + ExportNamerTests 16 + ExportQueueContractTests 12 + WebPIntegrationSmokeTests 4 = **54**（1133 → 1187）。

## 遗留 / 移交下波（非阻塞）

- 契约 actor 实现件（generation/pump/gate/waiters）= 11-04；`ExportRenderArtifact` 的真载荷扩点 = 11-04（D3）。
- 每格式 golden（像素/ICC/元数据/10-12bit 探针）= 11-02（本 plan 冒烟仅为链接+能力面）。
- Swift-WebP mux 面（OQ-11-5 WebP 元数据 v1 口径）= 11-02 编码轮顺探。
- 静态产品双链接告警若 11-02 起出现符号重复实测问题 → 回改 Tests 侧去依赖改经 Core 转发（D12 有退路）。
