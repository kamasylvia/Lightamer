# M2-0「测绘与规格」回溯二次验收 R2（OMP 双路终验）

> 验收员：OMP（独立零共享上下文）/ 日期：2026-10-10 / HEAD：`1ee26c40`
> 方法：亲读四正本 + 上一轮报告抽查点提炼，Alcedo 侧一律 `git show 34241d0:<path>` 只读重验（pinned SHA 全串 `34241d0bd3f…cbeb` 与 feature map 头注记逐字一致，`git rev-parse` 亲证）；GPL 仓零复制，仅符号名/行号/参数值引用。未跑测试，未改任何文件。

结论头：**PASS / 0 error + 6 minor**

---

## 一、引用真实性（独立重验 30+ 处，覆盖 UI/operators/解码/AI/导出/DDL）

**UI 面**：①Desktop order 注释逐词命中（实际 `:88-90`，引用 `:89` 在块内 ✅）；②FIT 读出语义命中，行号漂移（`zoom>1.0001?…trueZoom…:qsTr("FIT")` 实际 `:327-329`，引用 `:331-347` ❌→m6′）；③七页签 7/7 全对但引用 `:10-16` 实为文件头注释，`navItems` 实际 `:47-64` ❌→m1；④exposure slider −10…+10/step 0.01/defaultValue 0 + reset 注释逐字 ✅；⑤method `defaultIndex: 1 // open_drt` ✅；⑥Creative White entries 实测 **7**（use_look_preset+d93/d75/d65/d60/d55/d50，`:364-377`），ROADMAP/REQ 写"6" ❌→m4；⑦Tonescale entries 实测 **15**（`:337-356`，含 custom）与"共 15 项" ✅；⑧Look 8（7+custom）✅；⑨`eotfOptionsForSpace` 六支（rec709→bt1886/g2.2；p3_d65→g2.2/st2084；p3_d60/dci/xyz→g2.6；rec2020→st2084/hlg）逐支 ✅；⑩SettingDialog 9 页名 + 蒙版三选逐字（`:226-228`）✅；⑪Geometry「applies to the whole image.」逐字（`:654`）✅。

**operators 面**：⑫catalog `Register({…})` 实测 18（`:34-51`；裸 `grep -c Register`=19 含成员函数定义一行）✅；⑬Grade 13 表/DRT-Post 4 表 + `OwnerOfAdjustment` 对 Tint 落 `Unsupported` ✅；⑭所有权注释逐句（ordered list must not reorder/DRT-owned rejected/scene-image input only）✅；⑮`kDefaultPipelineExposureEv=1.5/Saturation=1.3/Contrast=15.0` ✅；⑯`DrtPayload` 默认 OpenDrt + creative_white_limit 0.25/display_grey 10/hdr_grey_boost 0.13/hdr_purity 0.5 ✅；⑰`OpenDrtDetailedParams` float 字段机数 **=53**（tn9/cwp1/rs3/pt*16/ptl3/ptm6/brl6/brlp4/hc2/hs12）✅ 勘误注记求和成立；⑱图命令 7 名逐名 ✅；⑲`MaskSourceKind` Radial=1/LinearGradient=2 ✅；⑳Color/LuminanceRange 双 `enabled=false` 占位 ✅；㉑应用序实证仅 invert→opacity→clamp（RadialMaskParams doc），feather 无 mask 级序文本 ❌→m2；㉒brush_* 实测 6cpp+8hpp=14（+tests 4+docs 1=19），"9 个" ❌→m3；㉓providers 模板实测 8 个，所列 7 名全对、漏 `volcengine_ark_coding.json` ❌→m5。

**解码/导入面**：㉔`metal_shader/` 下三 `.metal`（debayer_rcd/demosaicnet_io/xtrans_interpolate）✅；㉕README:44 RCD/Neural Engine 逐句 + :48 2.5K@60fps/4K/可见区 ✅；㉖demosaic 三 entries ✅；㉗DevelopPayload（highlights_reconstruct=true/custom_cct 6500/lens_enabled false/user_scale/projection_enabled）✅；㉘10 RAW 扩展逐项 ✅；㉙导入缺陷链三环全亲证（CollectFolderFiles 递归 `push_back` 零过滤/`image_loader` 内 `is_supported_file` 调用被注释/定义在 hpp **`:63`**（引用 `:57` ❌→m6′））+ 与 changelog:8「RAW files only」矛盾成立 ✅。

**AI/导出/DDL 面**：㉚hf-mirror 默认端点逐字（`:65`）✅；㉛`ensure_present(_revision,_hf_endpoint,…)` + "no longer trigger any download" ✅；㉜kMin=1/kMax=5 ✅；㉝EditCommit（commit_hash/first+second_parent）/VersionRef（head_commit_hash）/ImageEditState（materialized_*）DDL ✅；㉞handoff 交互规则（保 redo 尾/再编辑丢尾/即时切换/自动保存/可改名/原始态新建/跨图延后）逐条 ✅；㉟ExportFormatOptions（`:34-56`：quality 95/PNG 5/TIFF 三档/BIT_DEPTH/HDR 双模/ultra_hdr 95+dither）✅；㊱命名 12 字段 + FAIL/REPLACE + fallback "image" ✅；㊲ultra_hdr 8192 钳制 + `output_color_` 入队前强制解析（`:131-150`）✅。

## 二、内置 18 目录对表

`adjustment_catalog.cpp:34-51` 18 个 Register 与 §2.1 表：数量 18=18，display_name 逐项一致；type_id 尾段 18/18 全对。归属抽 7 项：Exposure/Saturation∈Grade 13 表 ✅；Clarity/Sharpen/Halation/FilmGrain∈DrtPost 4 表 ✅；Tint 落 Unsupported（目录内标量表述成立）✅。

## 三、ROADMAP M2 表 12 行覆盖对表

M2-0 自身闭环四要素 ✅（301 行初版 commit 经 SHA 改写现为 `adaca821`，`git show` 树内 301 行亲证；D1-D6 签核现为 `4ec4b5ac`，body 六条逐条 verbatim ✅；STATE 登记 complete ✅）。M2-1..M2-11 行锚点逐行命中 §9/§10/§6/§1/§3/§2/§5/§4+D5/§6.2-6.3/§7/§8/M2-11 间接锚（README:48 + M1 资产自述）✅。行内"45 detailed"/"44 张"/"Creative White 6"为历史冻结字面，勘误链在案（§5 注记/M2DRT-02/M2GRADE-07），不追改 ✅。

## 四、REQUIREMENTS M2 族对表

机检：unique **67**（DIS5/LIB7/UIW6/NODE6/GRADE8/DRT6/MASK7/VER5/EXP5/AI10/PERF2，求和 67；occurrences 86）。67/67 均带出处锚或 Delivered 注记（含后立项 M2GRADE-08/M2AI-09·10 独立出处），零孤链 ✅。抽 8 条（M2DIS-01/M2LIB-03/M2GRADE-01/M2DRT-02/M2VER-01/M2EXP-03/M2AI-01/M2NODE-02）锚点逐条命中 ✅。M2GRADE-08 为 2026-10-07 上游增量立项（后演进，不记账）。

## 五、与上一轮报告的分歧项

- **D-R2-1（m6 第三子项不成立）**：上一轮称 README 平台引用 `:19,114-115`→实际 `:19/:114`。重验：README `:19`="It supports Windows 10/11 (x64) and Macs with Apple Silicon."、`:114`=Windows  bullets、`:115`=macOS bullets——feature map 引用（支持 Win10/11 x64 与 macOS 13.3+ Apple Silicon）**准确无漂移**。m6 收窄为两子项（m6′）。
- **D-R2-2（"79 个 ID"计数不成立）**：上一轮称"M2 族全枚举 79 个 ID"。重验：`grep -oE "M2[A-Z]+-[0-9]+" REQUIREMENTS.md | sort -u | wc -l` = **67**（occurrences 86；M2-0 收官时点 66，M2GRADE-08 为后演进）。79 无法复现，系上一轮计数误判；"零孤链"结论本身成立（67/67 有锚）。
- **D-R2-3（m4 定责细化，非推翻）**：feature map §5 正文列出 Creative White 全部 7 值且**未声称计数 6**——"6"仅存于 ROADMAP M2-6 行与 REQUIREMENTS M2DRT-02（一处同源同错，维持 minor 一记）。

minor 承接（6 项，均行号/计数级，无一触及语义）：m1/m2/m3/m4/m5/m6′（m6′=两子项：is_supported_file :57→:63；FIT :331-347→:327-329）。

## 六、会话卫生

只读验收：Alcedo 侧仅 `git show/ls-tree/rev-parse`（pinned commit 读）；本仓零修改（`git status` 仅预存改动与 untracked，与本验收无关）。未跑测试（纯文档面）。唯一写入 = 本报告文件。

OMP-VERDICT: PASS
