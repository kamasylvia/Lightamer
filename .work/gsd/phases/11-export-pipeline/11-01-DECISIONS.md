# Plan 11-01 — 执行决策(DECISIONS)

> 执行期决策边界(11-CONTEXT D-11-CONTEXT-1..8 + plan 纪律):RESEARCH 未覆盖/
> API 事实与 plan 字面冲突的实现细节在此登记。编号 D1..D13 按产生顺序;体例照
> 09-04-DECISIONS。全部为 11-01 范围内决策(标注可逆性)。

## D1:契约骨架落位 `LightamerCore/Sources/Export/`(非 RESEARCH §4.1 字面「App/State 层」)

plan 已预告的落位修正,入账固化:LightamerTests 只 import Core(App 层不可单测是
02-05 起红线),且 9-3 队列骨架本体 `SessionThumbnailProvider` 本就在 Core——契约
类型(状态机/快照/leg 缝)放 Core 与先例一致。11-04 的 actor 实现件仍可 App 侧
接线,不必移动这些类型。
Reversibility: 高(public 类型,移动 = import 面调整)。

## D2:`ExportJobSnapshot.variants` 保持复数(plan 字面),单 variant/job 的收敛留给 11-04

RESEARCH §4.1 表与 plan T3 均写 `variants`;但「一次队列动作 = N variants → N jobs」
(EXP-07)意味着每 job 通常恰一个 variant。契约照字面保留数组形状,头注注明 11-04
可携带单元素——避免契约层提前替实现层做减法。
Reversibility: 高(11-04 收敛为单 variant 是字段级改动)。

## D3:`ExportRenderArtifact` = 不透明 token 型 Sendable 盒(render→encode 缝的交接载荷)

9-3 的腿签名携带具体类型(`CGImage`),但导出链的 render→encode 交接物在 11-02/11-04
才定型(CI bitmap 出口 + 量化 buffer vs MTLTexture 身份)。契约层以 `token: Int +
width/height` 的 Hashable Sendable 盒钉住**缝的形状**,测试传合成 token;真载荷
= 11-04 additive 扩字段(或改泛型),队列单测不破。
Reversibility: 高(additive)。

## D4:`scalePercent` 合法域 `(0, 10_000]`;fold = `round(long × p/100)` 钳 `[1, long]`

plan 未钉数值域。0/负无意义必拒;上限 10_000(=100 倍)纯防 typo——>100 的部分
本就被 never-upscale 钳回源尺寸。fold 用 `.rounded()`(nearest)而非 floor:与
`YiyinExportSettings.targetSize` 的 `.rounded(.down)` 不同层(那是缩放后的宽高,
这是 longEdge px 的入口值),测试向量逐值钉死(100/3 % of 3000 → 1000)。
`effectiveSizing` 对 `nil` 与 `100` 恒等返回原 sizing(不包无谓 longEdge 壳)。
Reversibility: 高(纯函数 + 向量表)。

## D5:文件扩展名 = `jpg`/`tif` 短惯例(其余全名)

`ExportFormatSpec.fileExtension`:jpeg→`jpg`、tiff→`tif`(Lightroom/C1/darktable
互操作惯例),png/heic/avif/webp 全名。`formatName`(tag 派生用)恒全名。
Reversibility: 高(单 switch)。

## D6:stem 特殊字符保守策略 = 仅 `/` 与 `:` 替换 `-` + trim + 空/全 dash 回退 `Untitled`;Unicode 原样

plan 留给执行期(替换 vs 原样)。APFS 唯一文件名非法字符是 `/`(路径分隔),`:`
为 HFS legacy 互操作保留——替换而非拒绝(怪 stem 也能导出);中文/emoji/空格/
点号全为合法 APFS 名,**不做音译不清洗**(保守 = 最小干预,与 dt/PS 命名行为对齐)。
纯空白或只含非法字符的 stem 回退 `Untitled`(空名不可写盘)。
Reversibility: 高(单函数 + 向量表)。

## D7:冲突占用比较大小写不敏感

默认 APFS 卷大小写不敏感:盘上已有 `Photo.JPG` 必须挡住 `photo.jpg` 候选,否则
编码器静默覆盖。`occupiedNames` 内部 lowercased 后比较;gapped 占用集取**首个**
空位递增(非 max+1)。
Reversibility: 高(若未来支持大小写敏感卷,加 flag 即可)。

## D8:tag 消歧链 = `-<formatName>` → `-<index>`;whitespace-only 显式 tag 视为缺省

多 variant 派生 tag 冲突时:首个保裸名,第二撞名者追加**自己**的格式名
(`1200`/`1200-heic`),再撞追加序号(`1200-avif-2`)。用户显式 `outputTag` 去首尾
空白后非空才生效;全空白或全非法字符的 tag 视为未提供(退派生)。
Reversibility: 高(纯函数)。

## D9:Tuist 4.208 API 事实修正(plan 字面不可执行处)

- **`tuist fetch` 子命令不存在**(4.x 移除);`tuist install` 只装 plugins/templates;
  **SPM 包解析发生在 `tuist generate`**(内部跑 `xcodebuild -resolvePackageDependencies`)。
- **`TargetDependency.package` 签名 = `.package(product:type:condition:)`**——无
  `package:` 名字参数(product 名全局解析,单包项目无歧义);plan T4 字面
  `.package(product:package:)` 编译报 `extra argument`。
- Project 级 `packages:` 参数类型 = `[Package.Dependency]`(工厂
  `.package(url:from:)`),位于 options 与 settings 之间。
Reversibility: 高(纯 manifest 写法)。

## D10:fetch 网络实录 = 代理环境变量常开而 daemon 未运行;px 一次性拉起后 `px --stop`

R3 预案触发,根因与预案假设(直连失败)不同:会话 shell profile 常开
`http_proxy=127.0.0.1:10809` 等,但 xray daemon 没跑 → git clone 走死端口
Connection refused。处置:`px --up`(首次被同一批代理 env 反坑——xray.py 经 uv 拉
requests 也走死端口,`env -u http_proxy -u HTTPS_PROXY … px --up` 清 env 重跑成功)
→ `tuist generate` SPM 解析成功 → **`px --stop` 收尾零残留**。留痕:日志见本文件
+ SUMMARY「fetch 网络实录」节。
Reversibility: 高(缓存已落定,后续离线增量构建)。

## D11:Swift-WebP 0.6.1 API 面实况(冒烟钉死,11-02 编码轮直接消费)

- encode:`WebPEncoder().encode(UnsafeBufferPointer<UInt8>, format: WebPEncodePixelFormat,
  config:, originWidth:, originHeight:, stride:, resizeWidth: = 0, resizeHeight: = 0) throws -> Data`;
  像素格式 `.rgb/.rgba/.rgbx/.bgr/.bgra/.bgrx`。
- config:**lossy = `WebPEncoderConfig.preset(_:quality:)`**(preset 6 case + Float
  quality 0-100);**lossless = `WebPEncoderConfig.losslessPreset(level:)`**(0-9,
  throws)——`lossless: Int` 字段在 config 上但走 preset 工厂更稳(11-02 桥接
  `ExportFormatSpec.webp(quality:lossless:)` 时 lossless 分支映射 level)。
- 检查:`WebPImageInspector.inspect(Data) -> WebPBitstreamFeatures`
  (.width/.height/.hasAlpha/.format lossy|lossless)。
- 版本:`WebPEncoder.libwebpVersion` / `WebPDecoder.libwebpVersion`(实测 ≥1.5)。
- decoder:`WebPDecoder().decode(Data, into: inout [UInt8], options:, format:)`
  (options 无参 init)。
- strict concurrency:包编译零告警,R2 圈 actor 预案未触发。

## D12:static product 双 target 链接告警判 benign

WebP(static product)同挂 LightamerCore 与 LightamerTests(generate 告警
「may introduce unwanted side effects」):各 target 独立静态拷贝,单包单 product
无版本分裂面;Tests 需直接 `import WebP` 做链接冒烟。若 11-02 起实测符号重复/
体积问题,退路 = Tests 去依赖、经 Core 转发断言。
Reversibility: 高。

## D13:T3 补建 `ExportQueueContractTests.swift`(plan files_modified 缺项)

plan 的 files_modified 只列三个测试文件(Recipe/Namer/WebP),但 T3 证据要求
「状态机迁移合法性测试 + Sendable 编译期证明」,且 Verification 表过滤串
`'ExportQueue'` 隐含测试类名。补建 `ExportQueueContractTests.swift`(12 tests),
本条即为偏差登记。
Reversibility: 高(纯新增)。
