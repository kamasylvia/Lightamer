# Plan 12-3 — Decisions

**Date:** 2026-09-26
**Status:** Complete
**Scope:** XMP 同步面（XMPWriter 薄封装 + JPEG/PNG/TIFF 容器注入缝 + ExportEncoder 后置挂载六格式矩阵 + 第三方 .xmp 只读导入）

执行期决策（RESEARCH 未覆盖细节 / plan 留白处的落地裁决），验收对照用。注：T1-T4 三提交（`76dde86`/`e5e3a21`/`12c6afa`）完成于配额中断前，本文件由续班 executor 依源码 + commit 考古 reconstruct；T5/T6 决策为执行班原录。

## D1 序列化端宿主事实（F1 形态裁定的正本）

`CGImageMetadataCreateXMPData` 在 macOS 27 本机**可用**（12-RESEARCH §1 探针：831 字节合法 packet + round-trip 全对）——11-02 D3「ImageIO 写端死」的表述就此修正：死的是 **properties dict → 文件字节** 的写端面，**序列化端（fields → packet）活着**。XMPWriter 因此是约百行级薄封装，12-CONTEXT D-2 案 A「手写 XML 模板（+1 天）」预案作废。

## D2 lr namespace 注册前置 + Bag 构造纪律（F2 两条，探针钉死）

- 自定义 `lr` 前缀必须先 `CGImageMetadataRegisterNamespaceForPrefix` 再 SetTagWithPath——不注册 set 返回 false（静默丢字段）。
- `dc:subject` 数组必须 `CGImageMetadataTagCreate` + `.arrayUnordered` 才得 `rdf:Bag`；**直塞 CFArray 产 `rdf:Seq`**（`testRawCFArraySerializesSeqNotBag` 反例测试钉死错误形态）。

## D3 label 七色名表（执行期拼写，golden 锁）

`xmp:Label` 用 Capture One 七色集：`0:Red / 1:Orange / 2:Yellow / 3:Green / 4:Blue / 5:Purple / 6:Gray`（与 12-1 的 ⌘0-6 色标映射一致）。反查 `colorLabel(forName:)` 大小写不敏感；**未知色名永不发明 colorLabel**（返回 nil）。

## D4 reject/pick 的 XMP 面（D-12-CONTEXT-2 落地）

- `flag == 2`（reject）→ `xmp:Rating = -1`（XMP 的 reject 惯例；**reject 胜过任何星级**——XMP 面无独立 flag 位）。
- `flag == 1`（pick）**无 XMP 正位**——不映射（文档化；pick 保持 sidecar/DB 本地维度）。
- rating 0-5 verbatim；导入反向：-1 → flag=2 + rating nil，0 = unrated → 无字段。

## D5 JPEG APP1 口径

SOI 后、**APP0/既有 Exif APP1 之后**拼接（Adobe XMP Part 3 推荐位）：`FFE1` + u16-BE 长度 + `"http://ns.adobe.com/xap/1.0\0"` 段头 + packet 逐字节。packet + 段头 > 65535 字节 → typed `jpegSegmentTooLarge`（**不做多段扩展**，文档化边界——超长 keywords 保护）。

## D6 PNG iTXt 位置 = pre-IDAT（宿主事实压过 plan 字样）

macOS 27 宿主 PNG reader **只读 pre-IDAT 的 XMP iTXt**，IEND 邻位被忽略（写端探针钉死）——plan 的「IEND 前插入」字样让位于宿主可读性面 + Adobe XMP Part 3 §1.1.3 位置，实落 = **首个 IDAT 之前**。

## D7 PNG replace 语义 vs JPEG/TIFF refuse（T5 批契约修正）

写端宿主事实：PNG 是宿主**自己生成 XMP iTXt** 的唯一格式（EXIF properties bridge 写 exif:*-only iTXt，键 `XML:com.adobe.xmp`）——fresh encode 也会带宿主 XMP，refuse 语义在 PNG 上自败。故 PNG 缝 = **替换语义**（遍历删全部既有 XMP iTXt + 新包插 pre-IDAT），重注入收敛为恰一 iTXt 携带最新 packet（`testPNGMisuseAndReplaceSemantics` 钉死：恰一 iTXt + 宿主读最新值 + 像素逐字节不变）；JPEG/TIFF 的既有 XMP 仍 `existingXMPNotReplaced` refuse（v1 不拼接覆盖外来 XMP）。T5 批随导入面同 commit 修正（`7c06fa2`）。

## D8 TIFF tag 700 裁定 = 注入成功（风险预案未触发）

IFD 重组：新 tag 700（BYTE 数组）按排序插入 + 后续数据区 offset 平移 + 下一 IFD 链保持。完成判据全绿：正锚字节 + 值匹配 + **既有 tag 值逐字节不变** + 宿主 `CGImageSource` round-trip；双注入 typed refuse（`testTIFFDoubleInjectionRefusesAndMisuse`）。**文档化降级预案未触发**（无例外集 +1）。

## D9 导出链挂载形态（T4）

`ExportChainBuilder.mountXMP` 后置挂载（编码原子晋升之后）：盘上 sidecar → `XMPWriter.project`（D4 映射）→ 序列化 → inject → 同目录原子晋升（L009）。`XMPMountOutcome` 四态 tally：`attached / skippedNoFields / skippedUnsupportedFormat / failed(String)`——**导出永不因 XMP 硬失败**（非 attached 皆文档化降级）。HEIC/AVIF/WebP = D-12-CONTEXT-10 文档化例外，六格式矩阵以 byte-scan **反锚**钉死缺席（防宿主漂移：宿主行为变化即红）。

## D10 解析端宿主事实：空包 → unparsableXMP（T5 批）

`CGImageMetadataCreateFromXMPData` 对**属性为零的合法 XMP 包**返回 nil（2026-09-26 探针）——诚实错误是 `.unparsableXMP` 而非 `.noFields`（「宿主都无法建 metadata」≠「解析了但没字段」）。测试对齐宿主行为（`testTypedErrors` 内注释在案）。

## D11 契约对齐四处（T5 批，orchestrator 修复后由续班提交）

导入面的「无内容」语义统一为 **typed throw，绝不返回空 Fields**：

1. `xmp:Rating = 0`（XMP unrated）→ 无字段 → `.noFields`（不发明 unrated 位——sidecar 面无此位）。
2. `xmp:Rating` 超出 -1/0-5 惯例（如 9）→ 无字段 → `.noFields`（惯例外值不发明评分）。
3. `xmp:Label` 未知色名 → 永不发明 colorLabel；包内再无其它 importable 字段 → `.noFields`。
4. 空包（无属性）→ 宿主 nil → `.unparsableXMP`（D10）。

用户面语义：三者皆「什么都没找到/读不了」可见 alert，**零静默空写**。

## D12 allowHierarchical 门（T5 的 MetadataService 语义面）

`|` 严格校验的存在理由 = **拦手动输入**键入分隔符（12-RESEARCH §3.1——防 GUI 编辑行把 `|` 当普通字符存进层级 path 空间），非拒绝第三方良构 `lr:hierarchicalSubject` path。故 `setKeywords(_:relPaths:allowHierarchical:)` 默认 false（既有调用面零变化），仅 `MetadataController.setImportedKeywords`（导入唯一 GUI 路由）开门。

## D13 dc:subject-only 诚实降级 + lr 胜出

- 仅 `dc:subject` 的第三方文件：**叶子升单级 path** 直存（无祖先信息可发明——不虚构 `A|B` 结构）。
- `lr:hierarchicalSubject` 与 `dc:subject` 并存 → **lr 胜**（dc 的叶子集可从 lr path 派生，存 dc 会丢层级）。
- lr Bag 全 path verbatim（无 flattening、无去重改写——生态字节直读）。

## D14 GUI 走查的 app 来源（偏离注记）

任务书给的 `build/Build/Products/Debug/Lightamer.app` 是 **01:31 旧构建**（不含 T5 代码，AX 树无 `toolbar.import` 实证）；走查改用 DerivedData `Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi` 的 **22:00 build-for-testing 产物**——与全套验证（1364/6/0）同一二进制，走查结论对「已验证代码」成立。
