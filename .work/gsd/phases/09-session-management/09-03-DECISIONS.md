# Plan 09-03 — 执行决策(DECISIONS)

> 执行期决策边界(09-CONTEXT specifics):RESEARCH 未覆盖的实现细节在此登记。
> 编号 D1..D11 按产生顺序;全部为 09-03 范围内可逆决策(标注可逆性)。

## D1:缩略图磁盘文件命名 = FNV-1a 64 hex 16 字符
`ThumbnailPath.hash(relPath)` = StableHash FNV-1a 64(relPath UTF-8)→ 16 位
小写 hex。与 L013 同源原语,但**文件名不走 decimal TEXT 纪律**——decimal 纪律
防的是 JSON number 精度丢失(索引列),文件名无此消费面;hex 16 字符紧凑且
cell identifier(`browser.cell.<pathhash>`)与文件名同源单一真源。
Reversibility: 高(换拼法 = 一次性全量重生成,索引可重建)。

## D2:LRU 内存预算终值 = 384 MB
RESEARCH §5.3 窗口(256–512MB)取中点;~0.35MB/张 → ~1100 张驻留,覆盖重度
滚动工作集且与 PipeCache 3GB 会话预算互不挤压。可注入(测试用 KB 级预算)。
Reversibility: 高(常量)。

## D3:磁盘格式 = JPEG q85(HEIC 继续挂账)
RESEARCH 计划期默认;实测 360px 合成图 ~2KB、真图 30-60KB 量级 → 10k 上限
~0.5GB 预算内。HEIC 增益 <2×,非沙盒环境 JPEG 兼容性/可调试性更好。
Reversibility: 高(重生成)。

## D4:round-trip 口径 = 有损域(D6)
JPEG 带 ICC,decode→re-encode 与源编码**不可能字节恒等**(profile 重盖)。
内容级断言改为:①同一 CGImage 两次编码字节恒等(确定性);②解码图写第二
relPath == 直接重编码字节(解码图即文件内容);③双图 rasterizedBytes 均差
<3 LSB(有损域窗口)。L020 内容级满足,不做记账级。@testable 先例已在
SessionThumbnailProviderTests 头注钉死。

## D5:渐进 ingest 占位行不触发缩略图产线
占位行 hasEdits=false + thumbState=nil——双档判定禁止在猜测上运行;占位 cell
只显示渐变占位,权威 reload(finishProgressiveIngest)后才有缩略图。
Reversibility: 无需(语义正确性优先)。

## D6:档 A 超采样 = 720px
`kCGImageSourceThumbnailMaxPixelSize` = 720(360 显示尺寸 2×,与 D-C3 阶梯
超采样余量同构)。实测 10.9ms(预算 10-50ms)。

## D7:队列并发 2 + 空闲延迟 1500ms
并发 2 = RESEARCH §5.2(Phase 7 Neural/GPU 竞争教训);空闲延迟 1500ms =
dt backthumbs_inactivity 同构(后台任务入队后 sleep 让位交互,可见任务跳队
且跳延迟)。两项均构造注入(测试 0ms)。

## D8:provider 渲染/解码腿注入制(隔离红线的机械化形态)
`ThumbnailRenderLeg`/`ThumbnailDecodeLeg`/`ThumbnailRunContextInjector` 三个
注入缝:Core provider 组装语义(判定/材料化/绑定/队列),GPU 腿由 App 装配
(`SessionThumbnailRenderer`,位于 App/State/)实现。红线 grep
`PipeCache` 在 LightamerCore/Sources/Session + App/Sources/Lightamer/Session
**严格零命中**(provider 连缓存类型名都不出现),App/State 的 renderer 只构造
throwaway per-run 实例。测试可注入合成 decode(队列语义测试毫秒级)。
Reversibility: 高(接口缝,非语义)。

## D9:thumb_path 存绝对路径
9-1 的 cleanupThumbFiles 语义(直接 removeItem)零改动挂接;会话移动后绝对
路径失联 = 缓存 miss 重生成(索引可重建派生物,正确性无损)。备选(存文件
名拼目录)被否:需改 9-1 已验收代码,收益仅迁移后首扫省一次重生成。

## D10:双档观感抽检判定 =「可辨」,全走档 B 退路**否决**
实测(真 ARW/NEF/RAF,档 A vs 档 B @360,8-bit 通道均差):74.4 / 51.6 /
60.6,p95 97–112——远超「不可辨」带。**根因证据**:档 B 与编辑器显示同链
同形(Phase 8 GUI 真机截图 2026-09-25-083-base-pristine.png 同色调),差异
主体 = v1 基础 trio 管线的色彩形态 vs 相机嵌入预览域,属 Phase 3+ 色彩 iop
校准范围;**不是双档机制缺陷**。退路(全走档 B)否决理由:10k × 0.5-2s
首扫直接冲突 PERF-06 吞吐目标,且档 B 在校准后自然收敛。处置:
①机制保留(has_edits 判定红线测试不动);②抽检测试常驻为复核 harness
(P3+ 校准后数字应收紧,届时该断言从记录型改回阈值型);③混排观感入
Manual-Only 待人工(P3+ 复核)。**重大返工回注 planner**:无——机制照 plan,
仅退路预案经证据否决。执行中附带修复:转换腿的 bgra8Unorm/float32 双域分支
(初版把 display-ready 平面按 linear Rec2020 读并 R/B 互换,抽检归档
09-3-tiers-*-A-vs-B.jpg 即证据)。

## D11:culling 常驻账本口径 = bgra8 display plane(~5.8MB/平面)
RESEARCH §5.4 的「~23MB/平面」= float32 PREVIEW 工作平面,实测管线终态是
gamma 尾 bgra8Unorm(4B/px)——**常驻** 5.8MB/平面(双格 ~12MB),23MB 为
run 内瞬态(throwaway cache 生命周期)。MemoryBudgetTests/CullingPipelineTests
两处断言统一到常驻口径(4-8MB/平面、dual <16MB),瞬态语义在账本头注钉死。
4 图扩展位复核口径:常驻 ~24MB + 瞬态 ~92MB。
Reversibility: 无需(计量口径修正)。
