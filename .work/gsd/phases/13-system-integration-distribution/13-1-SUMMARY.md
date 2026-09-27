# 13-1 SUMMARY — 系统扩展底座(W1)

> 执行:2026-09-27,executor subagent worker,全程 auto=true/paused=false(每任务边界实测核对)。
> 分工:执行 = 本 worker(AGENTS.md Phase 执行模型)。

## 任务表

| 任务 | 内容 | commit | 验证 |
|---|---|---|---|
| T1 | Tuist 5→7 targets:双 appex(`LightamerQuickLook` / `LightamerSpotlight`,非沙盒 entitlements + per-config hardened 继承 + 宿主嵌入 + 共享 framework @rpath);占位薄壳使 target 编译;形状验证全项 | `16359fd` | generate + Debug/Release 构建绿;PlugIns 内双 appex;签名 Authority 三者同「Lightamer Dev」;Release flags=0x10000(hardened)三者齐;otool @rpath 链 + entitlements 无 sandbox key |
| T2 | QL 渲染时延探针:2 样张(100MP GFX100S RAF / A7R V ARW)× 3 尺寸(512/1440/2560)× 冷/热×3 中位 | (并入 perf.md 提交) | `LA_QL_PERF=1` 门控跑通,Executed 1/0 fail(37.9s);全表 + 阈值结论落 `perf.md` |
| T3 | `QuickLookRenderer` Core 缝:ExportRenderer 减法孪生(无 yiyin/sizing/encode,sRGB display 终态 CGImage)+ 三查回退链 + 30s 有界等待 + 只读 lindex 探针(immutable-URI 回退) | `7dde232` | `QuickLookRendererTests` 10/10 绿(parity 逐字节/三查逐级/零渲染计数/超时回退/常量钉住);相邻 SessionThumbnailProvider/SessionIndexStore 套件绿 |
| T4 | QL appex 接线:provideThumbnail(三查)→ QLThumbnailReply 位图;providePreview(data-based)→ 2560 fit JPEG QLPreviewReply | `2d5b591` | 构建绿;薄壳 90 行(≤100)grep 自证零业务逻辑;Core 测试承接 |
| T5 | `SpotlightAttributeMapper` + Spotlight appex 接线:lindex 只读投影 → 标准属性;34 列冻结契约同批 | `a05ccda` | `SpotlightAttributeMapperTests` 10/10 绿(契约 verbatim/mtime+size 零变/映射逐项/降级三态/schema v99 拒) |
| T6 | 全套回归 + SUMMARY + DECISIONS + TODO 开账 | 本提交 | 基线 1553 → 1573/10skip/0fail(见下) |

## 回归计数(T6 终轮)

- 基线 **1553/9skip/0fail**(16-4 收口后终值)
- 本 plan 新增测试:**20**(QuickLookRendererTests 10 + SpotlightAttributeMapperTests 10)
- 门控探针:**+1**(QuickLookPerfProbeTests,无 `LA_QL_PERF` 时 XCTSkip → skip +1)
- 终轮:**1574 / 10skip / 0fail(510.6s)EXIT=0**(1553 + 21 = QL Renderer 10 + Spotlight Mapper 10 + 门控探针 1;在案负载型 flake LayerE2ERoundTripTests / ToneEqualPerf 本轮 4 条 passed 未现身)

## 证据指针

- target 形状:本 commit message(T1)+ 13-1-DECISIONS D-13-1-8/9
- 时延全表 + 阈值:`perf.md`
- 执行期决策(API 形状变更/属性映射全表/KVC 实测/immutable-URI 等 10 条):`13-1-DECISIONS.md`
- QL parity 证据:`QuickLookRendererTests.testPreviewPlaneByteIdenticalSharedDecode` —— 同 sidecar 同参数**共享单次 decode**(CIRAW speckle 教训)下 QL plane vs `ExportRenderer.renderStage` plane **逐字节一致**(XCTAssertEqual(Data, Data) 原样通过;无需 ≤1/255 放宽域)

## GUI 实测域(13-4 走查批承接,Manual-Only 候补)

- Finder 空格实测:QL 预览显示编辑态(2560 fit)、缩略图三查、RAW/raster 全类型集
- `mdimport -t -d3 <file>`:importer 注册属性实测(需 app 安装后 importer 可被 mds 定位)
- Spotlight 检索验收:rating/tag/keyword/EXIF 关键词命中(SYS-02 黑体)

## 人工阻塞项提醒(D-13-CONTEXT-8 承接,非本 plan 消费)

Developer ID 证书与私钥 / App Store Connect API key / GitHub 公开仓时机 / Secrets 配置——
13-4 排期前必须由用户供件(登记义务履行;GOAL-STATE 阻塞节由 orchestrator 汇总时同步)。
另:Release 全 target 当前 `get-task-allow=true`(项目级 base-injection 既有行为),
公证前必须翻 false——已入 DECISIONS D-13-1-9,归 13-4 签名切换批。
