# 13-1 DECISIONS — 执行期决策清单

> Plan 13-1(系统扩展底座)执行期决策全录。纪律:RESEARCH/CONTEXT 未覆盖细节不臆造,常量名/键拼写以系统实测核对。

## D-13-1-1 macOS 27 SDK 双 API 形状变更(T1 探测,构建期即证)

1. **QL thumbnail API 离开了 `QLPreviewingController` protocol**——新 SDK 中它移到
   `QuickLookThumbnailing.QLThumbnailProvider` 基类(`provideThumbnail(for:_:)` 为须
   override 方法)。单 appex 双能力(D-13-CONTEXT-1)在新形状下的落法 = **一个
   principal class 同时 `QLThumbnailProvider` 子类 + `QLPreviewingController`
   conformance**(protocol 的 NSObject 要求经同一基类满足)。验证:probe 编译 +
   T1 构建绿。
2. **Spotlight 的 Swift-only `ImportPlugin` protocol 在 macOS 27 SDK 已删除**
   (`cannot find type`)。正主 = ObjC `CSImportExtension` class(CSImportExtension.h,
   macOS 12+):principal class 改为继承它并实现
   `update(attributes:forFileAt:) throws`(ObjC `updateAttributes:forFileAtURL:error:`
   的 out-param 导入为 throws)。

## D-13-1-2 QL 预览腿选 data-based `providePreview`(T4)

plan 原文锚点是 `preparePreviewOfFile(at:)`(view-based)。新 SDK 下 view-based 需要
principal class 是 NSViewController 并装配 `self.view`——与 `QLThumbnailProvider`
基类互斥(单类双能力不可行),且引 View 层状态违背薄壳红线。改走 **data-based**
`providePreview(for:completionHandler:)` → `QLPreviewReply(__dataOfContentType:
contentSize:dataCreationBlock:)`(JPEG data;`__` 前缀是该 ObjC init 的 Swift 导入
标签,实测)。`preparePreviewOfFile` 不实现(QLPreviewingController 的三个 optional
方法实现其一定可)。

## D-13-1-3 QL 全预览 fit 尺寸 = 2560(T4)

`QLFilePreviewRequest` 只携带 fileURL 无尺寸。fit 尺寸自定 = **2560 long edge**
(= T2 探针的 fit 档;T2 实测 2560 热稳态 1.9–2.1s,QL 窗口无 100MP 原生全幅需求)。

## D-13-1-4 渲染超时阈值 = 30s(T2 结论,D-13-CONTEXT-2 ④定名)

依据见 `perf.md`:最坏单点冷观测 5.44s(A7R V@512,含 RAW 9 CoreML 一次性编译
2.62s + PSO 2.82s)× 5.5 安全系数;热稳态最坏 2.08s(100MP@2560)永不触发;
真卡死 30s 内降档 A。语义 = 等待上界(渲染任务后台跑完进 void,不取消 GPU
mid-flight——SessionThumbnailProvider.cancelAll generation-gate 同款)。
测试用注入 timeout 参数(生产常量 30s 由常量钉住测试断言,不在测试中等 30s)。

## D-13-1-5 Spotlight 属性映射全表(T5,系统 schema + CoreSpotlight 实测)

实测方法:`mdimport -A` dump 系统 schema(291 属性)+ 每个候选 CoreSpotlight Swift
属性逐一 typecheck/runtime 回读。**多属性无 Swift 名(exposureTimeSeconds/
starRating/userTags 无强类型属性),KVC key 用小写驼峰非 kMD 前缀**(kMD 前缀
KVC 会 NSUnknownKeyException 崩)——实测定稿:

| lindex 列 | CoreSpotlight 面 | kMDItem 恒定名 | 备注 |
|---|---|---|---|
| rating | `attributes.rating`(Swift 属性) | kMDItemStarRating | 仅 0...5 映射;-1/越界不映射 |
| color_label | `setValue([name], forKey: "userTags")` | kMDItemUserTags | 色名 = XMPWriter.labelNames(Red/Orange/Yellow/Green/Blue/Purple/Gray);越界不映射 |
| keywords | `attributes.keywords`([String]) | kMDItemKeywords | `|` 材料化展平 = tokens + 层级路径前缀(CatalogProjector.tagRows 同款超集),序稳去重 |
| camera_make | `attributes.acquisitionMake` | kMDItemAcquisitionMake | |
| camera_model | `attributes.acquisitionModel` | kMDItemAcquisitionModel | |
| lens_model | `attributes.lensModel` | kMDItemLensModel | schema 实测在册 |
| capture_date | `attributes.contentCreationDate` | kMDItemContentCreationDate | timeIntervalSince1970 → Date |
| iso | `attributes.isoSpeed` | kMDItemISOSpeed | NSNumber(value:) |
| focal_length | `attributes.focalLength` | kMDItemFocalLength | mm 原值 |
| aperture | `attributes.fNumber` | kMDItemFNumber | **F 值直映;kMDItemAperture 是 APEX 对数标度,故意不写**(错值风险) |
| exposure | `attributes.exposureTime` | kMDItemExposureTimeSeconds | 秒原值 |
| flag / note / layer_summary | **不映射** | — | 无标准席位;Projection 类型无字段(结构即证明),apply 体被测试源级断言零写 |

数字属性 Swift 名为 `NSNumber?` 型,赋值须显式 `NSNumber(value:)`(Int/Double
变量不隐式桥——probe 实测)。

## D-13-1-6 lindex 只读连接的双开形态(T3/T5 共有)

主 app **运行中**:WAL 库带 `-shm/-wal`,普通 `SQLITE_OPEN_READONLY` 连接可读。
主 app **已关闭**:checkpoint 后无 sidecar 文件,只读连接直接失败
("unable to open database file",sqlite3 CLI 复现实测)。回退 = `file:...?immutable=1`
URI 重试——精确读 checkpoint 后的已提交主库;checkpoint 进行中可能读到略旧的
已提交态(安全方向:probe 只会多降一级渲染腿,答案仍是磁盘已提交态)。

## D-13-1-7 QL/Spotlight 内容类型声明(T1)

`QLSupportedContentTypes` / `LSItemContentTypes` = `public.camera-raw-image`
(抽象聚合;实测 CGImageSourceCopyTypeIdentifiers 不含抽象父型但 conformance
展开,DNG= com.adobe.raw-image 由 conformance 覆盖)+ `public.avif` `public.heic`
`public.jpeg` `public.png` `public.tiff` `org.webmproject.webp`(与主 app
CFBundleDocumentTypes 对齐 + AVIF;AVIF/WEBP 可解码性经 CGImageSourceCopyTypeIdentifiers 实测)。

## D-13-1-8 TUist appex target settings 形状(T1)

appex 不重复嵌入 framework(宿主 App 持 Frameworks copy phase),runpath =
`@executable_path/../Frameworks @executable_path/../../../../Frameworks`
(PlugIns/<appex>.appex/Contents/MacOS 距 Contents/ 四级)。Xcode Debug 构建会
自动附加 `@loader_path` 与 PackageFrameworks 绝对路径 rpath(dev 构建遗留,
Release 无)。entitlements = 空 dict 注释文件(非沙盒 = 无 sandbox key;Debug
get-task-allow 由 base-injection 供给,L011 三件套不动)。

## D-13-1-9 13-4 面的预检发现(非本 plan 消费,登记提醒)

- **Release 构建三 target(宿主+双 appex)当前都带 `get-task-allow=true`**——
  项目级 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES` 的既有行为(非本 plan 引入)。
  公证(notarytool warnings=errors)前必须翻 false:归 13-4 Developer ID 切换批。
- Release hardened 位实测三 target 均 `flags=0x10000` ✓(per-config hardened
  形状对 appex 自动生效)。

## D-13-1-10 教训候选(T6 同批评估)

- tuist glob 生成期定文件清单:generate 后新增源文件必须重跑 `tuist generate`
  (11-03 教训复现——QuickLookPerfProbeTests 加文件后 Executed 0,重 generate
  解决)。已有 LESSONS 记录则不重复立项。
- SessionIndexStore 无 handle 的实例是静默 no-op(fetchRow 返 nil、update
  返 void):测试里 reopen 空扫会把全部行 diff-DELETE——「reopen 复用同一
  open 实例」是唯一正确姿势。
