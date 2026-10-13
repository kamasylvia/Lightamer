# M2-0「charter/feature map 测绘与规格」回溯二次验收（PI 独立路）

- 验收员身份：PI（零共享上下文，独立双路之 PI 路）
- 日期：2026-10-10
- HEAD（Lightamer）：`1ee26c4`；Alcedo 本地仓工作树 HEAD `9ce6a24`（v0.3.2），**引用抽核一律 pinned `34241d0bd3f3183da78d39d5c1bd6c9e7a53cbeb`（feature map 头注记基线）只读 `git show`**
- 方法：亲读四正本 + ROADMAP M2 节 + STATE 台账（M2-0 为 charter phase，无独立 phase 目录，闭环证据 = ROADMAP M2-0 行 + STATE:57 + 签核 commit；AGENTS.md 无 M2-0 架构增量节，符合零代码交付定位）；从上一轮 OMP 报告提炼抽查点后逐项独立取证（不照抄），feature map 引用抽核 14 处覆盖 UI/operators/解码三面。

结论头：**PASS / 0 error + 4 minor**

---

## 一、抽查点：Alcedo 引用真实性（独立亲核 14 处，全部 pinned `34241d0`）

### UI 面（5 处）
1. **七页签 `EditorAdjustmentStack.qml`**：`navItems` 七项实测 Tone(:49)/Look(:51)/LUT(:53)/Display Transform(:55)/Geometry(:58)/RAW Decode(:60)/Mask(:62)——页签名 7/7 与 feature map 逐字一致；cited `:10-16` 实为文件头注释（:6-19），定义在 :47 起 → 行号漂移（记 minor m-a）。
2. **`EditorTonePanel.qml:126-139`**：exposure model minimum −10/maximum 10/step 0.01/defaultValue 0 + 注释 "user-created grades and reset both use 0" 逐字命中，cited 范围精确。
3. **`EditorWorkspace.qml:89`**：`// Desktop order (non-negotiable): tool rail left, viewport / center, scopes + adjustment stack right.` 于 :88-89 命中；FIT 读出实际 :327-332（cited :331-347 部分重叠、语义命中，行号漂移入 m-a）。
4. **`EditorDisplayTransformPanel.qml`**：method `defaultIndex: 1 // open_drt`（:248）✅；EOTF 联动 `eotfOptionsForSpace`（:48）逐支一致（Rec709→bt1886/gamma22 :30-31；P3-D65→gamma22/st2084 :34-35；gamma26 档 :38；Rec2020→st2084/hlg :41-42）✅；Tonescale entries `grep -c value:` = **15** ✅（与 feature map「共 15 项」一致，M2-6 后续勘误的 14 系模型枚举口径，非本件矛盾）；Creative White entries = **7**（use_look_preset+D93/D75/D65/D60/D55/D50，:369-375）——feature map §5 原文列 7 项正确，**「6」错在 ROADMAP M2-6 行与 REQUIREMENTS M2DRT-02 冻结文本**（记 minor m-b）。
5. **`SettingDialog.qml`**：9 页名逐字（:352-360，Language/Theme→About 全在）；蒙版三选 `Ask every time`/`Create a new layer, then draw`/`Draw on the current node` 于 **:226-228** 逐字命中（cited 精确）。

### operators/模型面（5 处）
6. **`adjustment_catalog.cpp:33-52`**：构造体内 Register 恰 **18** 条（:34-51），display_name 18/18 与 §2.1 表逐项一致；cited 范围逐字精确。
7. **`cat02_white_balance_model.hpp:18-23`**：kCat02DefaultTemperature 5999.9934 / Tint 9.7112783 / 2000–15000 K / ±150 六常量恰落 :18-23，逐值命中。
8. **`mask_model.hpp`**：:28-34 = MaskSourceKind 枚举（Brush 在 `ALCEDO_ENABLE_BRUSH_MASK` 开关内、Radial=1/LinearGradient=2）✅；:100-120 = ColorRangeModel/LuminanceRangeModel 双 `enabled=false` 占位（"Only the disabled placeholder"）✅；:185-190 doc 仅实证 **invert→opacity→clamp**，"feather→" 序无 hpp 文本证据（feather 为源内参数）→ 表述部分成立（记 minor m-c）。
9. **`color_grade_node_model.hpp`**：所有权 doc 注释（ordered list/GraphCompiler 不得重排/DRT-owned rejected/scene-image input only）逐句命中（实际 :30-36，cited :29-34 同块近位）；:56-65 MakeDefault 注释载 +1.5EV/+15/1.3 归 CreateDefaultPipelineDocument ✅。
10. **`drt_node_model.hpp`**：默认 `DrtMethod::OpenDrt` 恰 :102；载荷 creative_white_limit 0.25/display_grey_luminance 10/hdr_grey_boost 0.13/hdr_purity 0.5（:110-113）✅；:45-99 typed 字段机检计数 = **53**——45→53 勘误注记（分组求和 53）反向钉死成立。

### 解码面（4 处）
11. **`develop_node_model.hpp`**：demosaic_method="default"(:68)/highlights_reconstruct=true(:69)/custom_cct 6500(:73)/lens_enabled=false(:78)/user_scale(:85)/projection_enabled=false(:86)/camera_profile(:77)——逐字段命中。
12. **`docs/supported_raw_formats.md`**：`.3fr/.arw/.cr2/.cr3/.dng/.fff/.nef/.raf/.raw/.rw2` 恰 **10** 项逐字。
13. **导入缺陷链三环**：`import_export.cpp:131` = CollectFolderFiles 定义行（recursive_directory_iterator 全量 push、零扩展名过滤——正文亲读 :131-163）✅ 精确；`image_loader.cpp:66` = `// if (!is_supported_file(img)) {` 被注释 ✅ 精确；`supported_file_type.hpp` is_supported_file 定义实际 **:63**（cited :57，行号漂移入 m-a）。0.3.0 changelog「Import accepts camera RAW files only」与该链矛盾成立。
14. **README**：:44 = RCD 默认 Bayer / Neural Engine（DemosaicNet 蒸馏）默认 X-Trans + inpaint-opposed（darktable/RawTherapee）逐句命中；**:19 与 :114-115 平台引文精确**（114=Windows bullet、115=macOS bullet）——上一轮 m6 该子项判定不成立，见分歧项。

## 二、抽查点：文档落账一致（Lightamer 侧）

- **ROADMAP M2 表 12 行**（M2-0..M2-11 机检 `grep -oE "^\| M2-[0-9]+"` 12 唯一）✅；M2-0 行闭环四要素（feature map 301→330 行亲测属实：首 commit `adaca821` 301 行 → 现 330 行 + 本表 + REQUIREMENTS M2 族 + 签核）齐备。
- **D1-D6 签核**：签核 commit 实测 = `4ec4b5ac`（2026-09-28 20:27 +0800，body 逐条记 D1..D6 与用户 2026-09-27「全按推荐」裁决）；ROADMAP :85-96 D1-D6 正文与之逐条自洽；STATE:57 `complete (2026-09-27; D1-D6 signed "all per recommendation")` 落账 ✅。
- **REQUIREMENTS M2 族**：机检 `M2[A-Z]+-[0-9]+` 唯一 FR ID = **67**（+12 phase 行号 = 宽口径 79，与上一轮「79」计数在宽口径下复现一致）；抽 6 条锚点核验零孤链（M2LIB-03→§附缺陷链 / M2GRADE-01→§2.1 / M2DRT-02→§5 / M2VER-01→§6.2 DDL / M2EXP-03→§7 / M2AI-01→§8.1）。
- **PROJECT.md（Constraints/Project 节）与 AGENTS.md「Project」节**：重定义五要素（Alcedo 克隆/RAW9/节点模型/导出矩阵保留/yiyin 一等公民）与 feature map §9/§10 映射方向一致；AGENTS.md 无 M2-0 架构增量节 = 零代码交付定位自洽。
- **GPL 纪律**：本报告仅符号名/行号/参数值级事实引用，零代码复制。

## 三、分歧项（与上一轮 OMP 报告 M2-0-ACCEPTANCE-OMP.md 的判定差异）

1. **上一轮 m6 子项误判（README 平台引文）**：上一轮判「README 平台 `:19,114-115` → 实际 :19/:114」（暗示 115 引错）。独立取证：pinned `34241d0` 的 README **:19（平台总述）/:114（Windows）/:115（macOS）三行全在且内容逐字命中**，feature map 引文精确无漂移。该子项应从 m6 中剔除（不影响上一轮 PASS 总判定）。
2. **上一轮证据瑕疵：两枚幽灵 hash**：上一轮抽查点 3 的 M2-0 行引用初版 feature map commit `d0ffd80` 与签核 commit `f0295fd`——两 hash 在本仓与 Alcedo 仓均**不存在**（`git cat-file -t` fatal、`git rev-list --all` grep 零命中）。实测真身 = `adaca821`（初版 301 行）与 `4ec4b5ac`（签核）。其实质结论（301→330、D1-D6 verbatim）经独立取证仍成立，但引证不可复核，特此单列。
3. **其余复核一致**：上一轮 m1（七页签行号）/m2（蒙版序 feather 无证）/m3（brush 文件实测 src+include 14 个 vs「9 个」）/m4（Creative White 6 vs 7，归 ROADMAP+REQ 冻结文本）/m5（providers 实测 8 文件列 7，漏 `volcengine_ark_coding.json`）/m6 余下两子项（is_supported_file :57→:63；FIT :331-347→:327-332）——PI 独立取证全部复现，判定成立。

## 四、minor 清单（PI 口径 4 项，均为文档级，无一触及测绘正确性）

- **m-a 行号漂移集**（合并记 1 项）：七页签 :10-16（实 :47-62）、is_supported_file :57（实 :63）、FIT :331-347（实 :327-332）、color_grade 所有权注释 :29-34（实 :30-36）——内容语义全对，仅行号欠准。
- **m-b「Creative White 6」**：QML 实测 7 值；feature map 原文正确，错在 ROADMAP M2-6 行 + REQUIREMENTS M2DRT-02 冻结文本（后者已有 Tonescale/53 参数勘误链，本项未入链）。
- **m-c 蒙版应用序**：「源 feather → invert → opacity → clamp」中 feather 前置序在 Alcedo hpp 无文本证据（仅 invert→opacity→clamp 有证）。
- **m-d providers 列举缺 volcengine_ark_coding.json**（所列 7 名全对，8 文件列 7）。

可修性判定：全部**小修**（文档勘误级；feature map 有「REQUIREMENTS 原文不改」勘误先例，m-b 可照 45→53 先例加注记不改原文）。

## 五、后演进注记（不记账）

- Lightamer HEAD `1ee26c4` 远超 M2-0 收官（2026-09-27/28）；工作树在飞改动（M2-4-0-BUNDLE-MAP / ColorMatch 族 / Project.swift）与本验收无关，未触碰。
- feature map 301→330 行 = 自记「上游增量测绘（2026-10-07/08）」追加节，文件内自洽，不计漂移。
- Alcedo 本地仓已演进至 v0.3.2（`9ce6a24`）；本报告全部抽核 pinned `34241d0`，现状差异不记账。
- 生成日期注记（头 2026-09-27 vs 首 commit 2026-09-28 18:45+0800）：以用户裁决日 09-27 落账、次日入库，observation 级不记缺陷。

PI-VERDICT: PASS
