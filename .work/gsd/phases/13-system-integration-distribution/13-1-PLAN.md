---
phase: 13
plan: "13-1"
title: "系统扩展底座（全 Phase 依赖根）：Tuist 双 appex target（LightamerQuickLook + LightamerSpotlight，5→7 targets、非沙盒 + per-config hardened、共享 framework @rpath 嵌入）+ QL 渲染时延探针（定超时阈值落 perf.md）+ QuickLookRenderer Core 缝（ExportRenderer 减法孪生 + 三查回退链 + 有界超时）+ QL appex 接线（thumbnail/preview 双能力薄壳 + parity 专项）+ Spotlight importer（lindex 只读行读 + 标准属性映射 + 34 列冻结契约同批）"
wave: 1
depends_on: []
autonomous: true
requirements: [SYS-01, SYS-02]
files_modified:
  - Project.swift                                                     # 5→7 targets：新增 .appExtension 双 target（bundleId com.kamasylvia.lightamer.quicklook / .spotlight）；非沙盒 entitlements；per-config hardened（Release）；appex 由宿主 App 依赖嵌入；共享 LightamerCore/LightamerIOP @rpath 链接
  - App/Extensions/QuickLook/LightamerQuickLook.swift                 # 新建：QLPreviewingController 薄壳（provideThumbnail + preparePreviewOfFile 双能力，零业务逻辑，全部转调 Core 缝）
  - App/Extensions/QuickLook/Info.plist                               # 新建：NSExtensionPointIdentifier com.apple.quicklook.preview + QLSupportedContentTypes（RAW + raster 全集）
  - App/Extensions/QuickLook/LightamerQuickLook.entitlements          # 新建：非沙盒（无 sandbox key）+ hardened 配套
  - App/Extensions/Spotlight/LightamerSpotlight.swift                 # 新建：mdimporter 薄壳（会话根定位 → lindex 只读 → 属性注册，零业务逻辑）
  - App/Extensions/Spotlight/Info.plist                               # 新建：NSExtensionPointIdentifier com.apple.spotlight.import 形状
  - App/Extensions/Spotlight/LightamerSpotlight.entitlements          # 新建：非沙盒
  - LightamerCore/Sources/Export/QuickLookRenderer.swift              # 新建：ExportRenderer 减法孪生——sidecar 真身读 → ExportChainBuilder（display 终态 sRGB，无 yiyin/无 export sizing/无 quantize/encode）→ CGImage；thumbnail(for:) 三查回退链 + 有界超时
  - LightamerCore/Sources/Session/SpotlightAttributeMapper.swift      # 新建：lindex 行 → 标准属性字典（rating/keywords/color_label/EXIF 七列映射；flag/note/layer_summary 不映射）
  - Tests/LightamerTests/QuickLookRendererTests.swift                 # 新建：parity 专项 / 三查回退链逐级 / 档 A golden / 超时回退注入 / fresh 直读零渲染计数
  - Tests/LightamerTests/SpotlightAttributeMapperTests.swift          # 新建：映射逐项 / 只读 mtime+哈希零变 / 34 列契约同批 / schema>2 与无 lindex 降级
  - .work/gsd/phases/13-system-integration-distribution/perf.md       # 新建：QL 渲染时延探针数字（缩略/PREVIEW/fit 尺寸 × 100MP/中等 RAW，冷热分离）+ 超时阈值结论
  - .work/gsd/phases/13-system-integration-distribution/13-1-SUMMARY.md
  - .work/gsd/phases/13-system-integration-distribution/13-1-DECISIONS.md
  - TODO.md                                                           # Phase 13 节开账 + 13-1 勾选
  - LESSONS.md                                                        # 如踩坑
---

# Plan 13-1 — 系统扩展底座（W1，全 Phase 依赖根）

> 背景：把 Phase 9 双档缩略图 + Phase 11 headless 导出渲染 + Phase 12 DB v2 34 列三块已验证底座接到两个新系统扩展进程上（D-13-CONTEXT-1/2/3）。
> 三条主线：① **Tuist 双 appex target**——项目首例新 target 形态，`Project.swift` 5→7 targets，QL/Spotlight 独立进程独立签名单元、宿主嵌入共享 framework（@rpath），非沙盒 + Release hardened（Boundary 事实 2：要读 `.lightamer/` 兄弟隐藏资产）；② **QL 渲染缝**——`QuickLookRenderer` = `ExportRenderer` 减法孪生（终点 CGImage sRGB 显示终态），三查回退链（thumbs fresh 直读 → headless 渲染 → 档 A 嵌入预览）+ 渲染有界超时；③ **Spotlight 抽取缝**——34 列冻结表为唯一抽取源（移交①），标准属性集映射，自定义 schema 不做。内部任务序刚性：T1 target 形状先行（结构风险根、探针最早该跑）→ T2 时延探针（定阈值）→ T3 Core 缝 → T4/T5 两个 appex 薄壳接线 → T6 收口。

## read_first

1. `.work/gsd/phases/13-system-integration-distribution/13-CONTEXT.md` 全文——D-13-CONTEXT-1（单 appex 双能力/非沙盒/薄壳下沉）、D-13-CONTEXT-2（三查回退链/编辑态语义/有界超时）、D-13-CONTEXT-3（lindex 只读/标准属性集/schema 冻结）、继承定案节（真身恒 sidecar/L013/one-way 格式锁）、验证红线节（QL parity/Spotlight 只读专项）
2. `.work/gsd/phases/12-metadata-presets-lut/12-DISCUSSION-LOG.md:61-79`——Phase 13 移交清单五条（①34 列=抽取源 + frozen-spelling 契约；②XMP 例外集本 Phase 不依赖）
3. `Project.swift` 全文——:27-35 Manual signing + `CODE_SIGN_IDENTITY "Lightamer Dev"`（L011 三件套，Debug 不动）/ :45-48 per-config hardened / :148 `ENABLE_USER_SELECTED_FILES` 非沙盒先例 / :80-199 五 target 现状（7 targets 扩展点）
4. `LightamerCore/Sources/Export/ExportRenderer.swift`（:1-56 headless 流程注释——本 plan Core 缝的减法孪生模板；:263/:329 exportTargetOverride 装配先例）+ `LightamerCore/Sources/Export/ExportChainBuilder.swift`（gamma/colorout 装配复用面）
5. `LightamerCore/Sources/Session/SessionThumbnailProvider.swift`（:63 ThumbnailRenderRequest 分辨率语义 / :112 actor）+ `LightamerCore/Sources/Session/ThumbnailDiskStore.swift`（:11 `<root>/.lightamer/thumbs/<pathhash>.jpg` 落位 / :46 定位函数 / :75 read）——三查第 a 腿数据源
6. `LightamerCore/Sources/Session/SessionIndexSchema.swift`（:49 schemaVersion=2 / :66-102 34 列冻结表）+ `SessionIndexStore.swift` 只读打开形态（importer 侧一次性只读连接，无并发面）
7. `.work/gsd/phases/09-session-management/09-CONTEXT.md`（:77 双档缩略图管线硬约束——QL 缩略图语义对齐正本 / :82 会话切换 teardown——QL 进程与主 app 并存的资产一致性语境：QL 恒读磁盘已提交态，不等待主 app 内存态）
8. `LESSONS.md` L009（fixture 禁 UNITEK / tmp 原子晋升）/ L011（测试授权三件套不动）/ L014（GPU 读回 fence）/ L019b（`Scripts/test-direct.sh` 直启宿主）/ L031（唯一路由获取点——Core 缝内任何 identity blit/GPU 提交走 `makeRoutedCommandBuffer()`）+ `AGENTS.md`（Phase 执行模型 + 暂停机制）+ `.work/GOAL-STATE.md`（Phase 13 阻塞登记节——凭据供件不属本 plan，但登记提醒义务见纪律节）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 本任务申报文件）；`caffeinate -dis` 包裹一切构建（`xcodebuild build` / `build-for-testing`）。
- **单测命令** = `Scripts/test-direct.sh '<Class>'`；**判据 = Executed 计数行 + failures 行**，Executed 0 = 判据失败（防空转假绿）。
- **每任务边界检查 `.work/config.toml [gsd]` 开关（`auto`/`paused`）**——commit 后、下一任务前：`paused=true` 全链路停；`auto=false` 完成当前任务后停等「继续」。
- **不 push**（日常任务一律不 push 既有 remote；GitHub 公开仓操作属 13-4 面，本 plan 零触碰）。
- **构建勿加 `-derivedDataPath`**（SPM submodule 坑）；**T1 与此后每新建文件/目录后跑 `tuist generate`**（11-03 教训；本 plan 新增 2 个 target + 2 个源目录，T1 提交前 generate + 构建绿一次）。
- **回归基线 = 1553/9skip/0fail**（16-4 收口后终值）；每任务全套 suite 绿；收尾轮 = 1553 + 本 plan 新增，0 fail。**在案 flake 归因条款**：`LayerE2ERoundTripTests` / `ToneEqualPerf` 两个负载型 flake 若现，隔离 ×3 归因单列入 SUMMARY，不计违约。
- **凭据阻塞项提醒义务**（不在本 plan 消费）：Developer ID 证书/AC API key/GitHub 仓公开时机若仍未就位，执行中一经发现即在 SUMMARY 与 `.work/GOAL-STATE.md` 阻塞节登记提醒——13-4 排期前必须由用户供件，本 plan 不自造凭据、不改签名身份。
- **appex 不进单测宿主**：一切可测逻辑下沉 Core（`QuickLookRenderer`/`SpotlightAttributeMapper` 全走既有直启宿主 suite）；appex 本体只做协议粘合，验证 = 构建走查 + `codesign -dv` 签名检查 + （GUI 实测归 13-4 走查批，**需解锁控制台（Manual-Only 候补）**）。
- **只读纪律（跨进程延续）**：QL/Spotlight 对 sidecar/lindex/thumbs 零写；Spotlight 测试断言 lindex 文件 mtime/哈希零变；lindex 打开带 schemaVersion 探测（>2 拒开降级零注册）；「mutable and untrusted」。
- **L031 声明**：`QuickLookRenderer` 若执行中出现 identity blit / 自建 command buffer，必须走 `makeRoutedCommandBuffer()` 路由点（L031 红线适用于任何 headless 管线 GPU 提交）；GPU 读回（探针/测试）前必须 fence（L014）。
- **fixture 纪律**：探针/测试样张走仓内 `input/RAW/` 既有 fixture；临时渲染产物落真机本地盘 /tmp 即弃（L009 禁 UNITEK、禁入工作区/入仓）。
- **QL 预览语义边界（显式教学）**：QL 显示的是**编辑态**（编辑器视口孪生，无 yiyin 印框、无导出 sizing/量化/编码）——不是导出预览；UX 文案不得暗示印框后成品。
- RESEARCH/CONTEXT 未覆盖细节（QL InfoPlist 键精确拼写、Spotlight 属性常量名、超时阈值具体值、parity 容差最终形式）标注**执行期决策**入 `13-1-DECISIONS.md`，不臆造（常量名以系统文档/`mdimport -t` 实测核对，CONTEXT 锚点为方向）。

## Tasks

### T1 Tuist 双 appex target：5→7 targets + 形状验证

- **action**
  1. `Project.swift` 新增两个 `.appExtension` target：`LightamerQuickLook`（bundleId `com.kamasylvia.lightamer.quicklook`）与 `LightamerSpotlight`（bundleId `com.kamasylvia.lightamer.spotlight`，D-05 命名惯例延伸）。两者 dependencies = `LightamerCore` + `LightamerIOP`（framework 由宿主 App 嵌入、appex 经 @rpath 共享，不复制）；App target 增加对两 appex 的嵌入依赖（`CopyFiles` extension mechanism）。
  2. **InfoPlist 形状**：QL = `NSExtensionPointIdentifier: com.apple.quicklook.preview` + `QLSupportedContentTypes` 覆盖项目可打开全集（CIRAW RAW 面 + JPEG/PNG/TIFF/HEIF/WebP/AVIF raster；UTI 列表以 `CGImageSourceCopyTypeIdentifiers` 与项目既有 UTI 声明为准核对）；Spotlight = `com.apple.spotlight.import`（mdimporter appex 标准形状）。entitlements：非沙盒（无 sandbox key，与主 app `ENABLE_USER_SELECTED_FILES: read-write` 决策一致）。
  3. **签名**：沿用 `CODE_SIGN_STYLE: Manual` + `CODE_SIGN_IDENTITY "Lightamer Dev"`（L011 Debug 测试授权三件套不动；Developer ID 切换 = 13-4，本 plan 不动签名身份）；per-config hardened 沿用 `:45-48` 既有形状（Release hardened / Debug unhardened）。
  4. **形状验证（research 头项探针③）**：`tuist generate` + `caffeinate -dis xcodebuild build` 绿；产物检查——app bundle 内两 appex 就位、每 appex `codesign -dv` 有签名且证书与宿主同、otool 轻查 Core framework 引用走 `@rpath`（共享嵌入非复制）。任一形状问题（appex 进程拿不到 framework、entitlements 拒载）当场停下归因，不得绕行。
- **证据**：构建绿 + 产物结构检查输出（appex 路径/签名 identity/@rpath 链）贴 SUMMARY；`Project.swift` diff 评审面干净（只加不改既有五 target）。

### T2 QL 渲染时延探针（定超时阈值）

- **action**
  1. 探针脚本/测试（可不入常驻 suite，环境变量门控）：headless 渲染实测——100MP 级 RAW 与中等尺寸 RAW 各一（`input/RAW/` fixture），在缩略尺寸（≈512）/ PREVIEW bucket / fit 预览尺寸三档各渲染 N≥3 次取中位，冷/热分离（首渲含 PSO 编译单独记）。
  2. 复用 `ExportChainBuilder` 装配到 CGImage 终态（即 T3 缝的前身原型，探针代码可直接演化为 T3 实现）。
  3. **结论落档**：`perf.md` 数字表 + **超时阈值建议值**（秒级，覆盖 100MP 冷渲染最坏观测 × 安全系数）入 `13-1-DECISIONS.md`——阈值是 D-13-CONTEXT-2 回退链的定名参数，T3 依此落常量。
- **证据**：perf.md 全表（尺寸 × 样张 × 冷热 × 中位）+ DECISIONS 阈值条目。

### T3 QuickLookRenderer Core 缝（三查回退链 + parity + 有界超时）

- **action**
  1. 新建 `LightamerCore/Sources/Export/QuickLookRenderer.swift`：
     - **preview(for:targetSize:)**：文件 → 同目录 `<name>.lra` 读 history stack（`ExportRenderer.swift:7-13` 读取法，磁盘文档即真相）→ `ExportChainBuilder` 装配（gamma/colorout，display 终态 = sRGB；**无 yiyin injection、无 export sizing、无 quantize/encode**——与 `ExportRenderer` 的减法差异即此三项）→ materialize → render → CGImage。GPU 提交走 L031 路由点（如触）。
     - **thumbnail(for:requestedSize:)** 三查：a. `thumb_state` fresh 且 `thumbs/<pathhash>.jpg` 在（`ThumbnailDiskStore.swift:46/:75`）→ 直读 JPEG（零渲染，计数探针位）；b. stale/缺失 → headless 渲染 @ 请求尺寸（`ThumbnailRenderRequest` 分辨率语义 `SessionThumbnailProvider.swift:63`）；c. 无 sidecar（pristine）→ **档 A 嵌入预览**（ImageIO，09-CONTEXT:77 双档定义）。
     - **有界超时**：单次渲染包超时（阈值 = T2 结论常量）→ 超时回退档 A；QL 永不无限等待。
  2. 渲染失败（sidecar 损读/解码错）→ 逐级降级至档 A，typed error 仅日志，QL 永不崩。
- **证据**：`QuickLookRendererTests`——**QL parity 专项**：同 sidecar 同参数下 preview 输出 vs `ExportRenderer` 同链参考渲染程序化差分，**首选逐字节一致；float→8bit 量化单点不可达域放宽 max ≤1/255**（归因入 DECISIONS）；无 sidecar → 档 A golden（与 ImageIO 解码对照）；stale → b 腿、损 sidecar → c 腿回退链逐级断言；**超时回退有界性**（假慢渲染注入，断言超时后返回档 A 且耗时有界）；**fresh 直读零渲染**（渲染计数探针 = 0 断言）。

### T4 QL appex 接线（薄壳 + 双能力）

- **action**
  1. `App/Extensions/QuickLook/LightamerQuickLook.swift`：实现 `QLPreviewingController`——`provideThumbnail(for:completionHandler:)` → `QuickLookRenderer.thumbnail`；`preparePreviewOfFile(at:)` → `QuickLookRenderer.preview`（@ QL 请求的 fit 尺寸，不渲 100MP 原生全幅）。appex 内零业务逻辑、零新状态。
  2. 主 app 并存语境注记（09-CONTEXT:82）：QL 恒读磁盘已提交态（sidecar 2s debounce 已晋升的最后 committed 版本），与主 app 内存态天然解耦——注记写入 appex 文件头 doc comment。
  3. 构建走查：appex 嵌入后 `quicklookd` 可加载（构建产物级检查；Finder 空格实测 = 13-4 走查批，**需解锁控制台（Manual-Only 候补）**）。
- **证据**：构建绿 + appex 源 ≤100 行薄壳自证（grep 无业务逻辑）+ Core 层测试全绿承接。

### T5 Spotlight importer + SpotlightAttributeMapper（34 列契约同批）

- **action**
  1. 新建 `LightamerCore/Sources/Session/SpotlightAttributeMapper.swift`：lindex 行值 → 标准属性字典。方向锚点（D-13-CONTEXT-3）：`rating`→`kMDItemStarRating`、`keywords`→`kMDItemKeywords`（`|` path 展平）、`color_label`→`kMDItemUserTags` 系、`camera_make/model`/`capture_date`/`iso`/`focal_length`/`aperture`/`exposure` → 各标准 EXIF 属性；`flag`/`note`/`layer_summary` → **不映射**。属性常量名以系统 schema 实测核对（`mdimport -t -d2` 或文档），全表落 DECISIONS。
  2. importer 链（appex 薄壳转调 Core）：收文件 URL → 向上探测会话根（`.lightamer/session.lindex` 存在性）→ **只读**打开 lindex（schemaVersion 探测，>2 = 拒开降级零注册——`SessionIndexSchema.swift:49` 冻结契约）→ 按 rel-path 读行 → 映射 → 返回属性；不在 lindex → 空注册零崩溃。
  3. 零写面：只读连接，无任何写语句。
- **证据**：`SpotlightAttributeMapperTests`——**只读专项**：全流程 lindex 文件 mtime/哈希零变断言；**34 列冻结契约同批**：引用 `SessionIndexStoreTests` verbatim 断言同源列集（importer 读面改动与 frozen-spelling 同绿）；**映射逐项单测**（行值 → 预期属性值，含 keywords 展平）；无 lindex / schema 超 v2 → 零崩溃零注册；`flag/note/layer_summary` 零注册断言。

### T6 全量回归 + SUMMARY + DECISIONS

- **action**：全 suite 终轮（基线 **1553/9skip/0fail** + 新增，0 fail；flake 归因条款见纪律节）；TODO.md 开 Phase 13 节 + 13-1 勾选；`13-1-SUMMARY.md`（任务表/commit 表/证据/探针指针）；`13-1-DECISIONS.md`（QL InfoPlist 键拼写、Spotlight 属性常量全表、超时阈值、parity 容差归因、其余执行期决策）；新教训候选评估入 LESSONS。
- **证据**：测试计数（1553 → N，0 fail）；SUMMARY + DECISIONS + perf.md 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| target 形状 | 7 targets 生成 + 构建 + 双 appex 签名/@rpath 检查 | `caffeinate -dis xcodebuild build` + 产物检查（SUMMARY 贴证） |
| 时延探针 | 三尺寸×双样张×冷热全表 + 阈值落 DECISIONS | 门控探针跑（perf.md） |
| QL Core 缝 | parity 专项 + 三查逐级 + 档 A golden + 超时有界 + 零渲染计数 | `Scripts/test-direct.sh 'QuickLookRendererTests'` |
| QL appex | 薄壳 ≤100 行 + 构建嵌入检查 | 构建走查（SUMMARY 贴证） |
| Spotlight | 只读零变 + 34 列契约同批 + 映射逐项 + 降级 | `Scripts/test-direct.sh 'SpotlightAttributeMapperTests'` |
| 回归 | 全 suite 0 fail（基线 1553+新增） | `caffeinate -dis Scripts/test-direct.sh`（全套） |

## 验收标准（Acceptance）

- [ ] `Project.swift` 5→7 targets：双 appex（bundleId 命名/非沙盒 entitlements/per-config hardened/宿主嵌入共享 framework @rpath）+ 既有五 target 零改动 + L011 签名三件套不动
- [ ] 时延探针落 perf.md + 超时阈值定名入 DECISIONS（秒级、覆盖 100MP 冷渲染 × 安全系数）
- [ ] `QuickLookRenderer`：preview = 编辑态 sRGB CGImage（无 yiyin/sizing/encode 减法孪生）+ thumbnail 三查回退链 + 有界超时回退 + 失败逐级降级不崩
- [ ] QL parity 专项：同 sidecar 同参数 vs 同链参考程序化差分过容差（逐字节优先，放宽域归因）；fresh 直读零渲染计数断言
- [ ] Spotlight：lindex 只读（mtime/哈希零变）+ 34 列 frozen-spelling 契约同批 + 标准属性映射逐项单测 + 无 lindex/schema>2 零崩溃零注册 + 自定义属性零映射
- [ ] appex 薄壳自证零业务逻辑；GUI 实测项已登记 13-4 走查批（Manual-Only 候补）
- [ ] 全 suite 0 fail（1553+新增）；每任务独立提交 + 边界查 config 开关 ×6；不 push；无 /tmp 产物入工作区；SUMMARY + DECISIONS + perf.md 落盘
