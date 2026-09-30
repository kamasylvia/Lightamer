# M2-3 TAB-MATRIX — 七页签归页映射表（OQ-4 代码化正本誊写）

> 正本 = `App/Sources/Lightamer/UI/Shell/EditorTabRoute.swift`（`EditorTabRoutingTable`，
> D4/OQ-4 表代码化单一正本）。**本 md 由表誊写，T2 验收含逐行对账断言**
> （`EditorStackRoutingTests.testTabMatrixMatchesTheRoutingTableLineByLine`——
> 每行 opName 字面 + 行数与表一致，漂移即红）。
>
> 归页总断言（checker m3）：**动态 populated provider 全集 − {TextOverlay} 恰一次归页**。
> 执行期实测（T2，Debug 构建）：`InspectorState.registerDefaultProviders(defaultFace: true)`
> 后 provider 键集 = **34**（38 provider 注册 − M2-1 禁用 6 gate；含 yiyin 双 provider 与
> textOverlay），减去 textOverlay = **33 恰一次**（31 页签行 + 2 顶栏 sheet 行）。
> plan 文本预估基数「Registry 注册 37/默认面 31」= ModuleRegistry **模块**口径
> （37 = 33 模块 + terminal trio 3 + testgain(DEBUG) 1；31 = 37 − 禁用 6）；断言域取
> **panel provider 面**（= 归页对象本身；terminal trio/testgain 无面板不入域）。两口径
> 差异 = `bilat`/`passthrough_spike` 无 provider、`highpass`/`soften` 各有 provider、
> yiyin 双 provider——以动态集为准登记（本节即 DECISIONS D3 的数据源）。
>
> **checker E1 勘误（2026-09-29）**：Display Transform 行 = **Vignette + DRT 占位节**；
> **AgX 失挂不入表**（`LightamerIOP/Sources/Registry.swift:43` `defaultFaceDisabledOpNames`
> 禁用面；env=1 全量回切走 legacy 平铺路径不受影响）。
>
> 禁用 6 名（M2-1 禁用面 op 名小写比对——正本 =
> `LightamerIOP/Sources/Registry.swift` `defaultFaceDisabledOpNames`）在表与全部新壳文件
> grep **零命中**（AC#3 机检；本 md 有意不拼写出六名——元提及也会命中 grep）。

## 页签 × 面板 × 组语义 × Alcedo 对应物

| 页签 | 面板（opName 字面） | 组语义 | Alcedo 对应物 | Alcedo 无对应标注 |
|---|---|---|---|---|
| Tone | `exposure` | main | Tone: Exposure | — |
| Tone | `contrast` | main | Tone: Contrast（新 contrast 件——OkLab S 曲线，M2-5-2 T3 批挂行） | — |
| Tone | `white` | main | Tone: White（新 white 件，T3） | — |
| Tone | `black` | main | Tone: Black（新 black 件，T3） | — |
| Tone | `shadhi` | main | Tone: Shadows / Highlights（**单行双滑杆**——M2-5-2 checker m2 钉死：同 opName 双 descriptor 在 `ForEach(id: \.opName)` 静态 id 冲突，两行分支删除；面板内两滑杆 = 两目录项最小忠实映射） | — |
| Tone | `tonecurve` | main | Tone: Curve | — |
| Tone | `levels` | **compat** | —（D6 独有件） | **Alcedo 无对应**（M2-5-2 D10：compat 折叠组，可编辑不删除） |
| Tone | `colisa` | **compat** | —（D6 独有件；Alcedo Contrast 语义由新 `contrast` 件承载） | **Alcedo 无对应**（同上） |
| Tone | `colorcontrast` | **compat** | —（D6 独有件） | **Alcedo 无对应**（同上） |
| Tone | `toneequal` | **compat** | —（dt tone equalizer） | **Alcedo 无对应**（同上） |
| Tone | `temperature` | **compat** | —（相机 WB = RAW Decode / CIRAW 域，M2GRADE-04；CAT02 创意 WB = Look/Color 组新件） | **Alcedo 无对应**（M2-5-2 D5：主面摘除 =「Tone −1 行」） |
| Look | `saturation` | **Master** | Look: Saturation（新 saturation 件，M2-5-2 T3 批挂行） | — |
| Look | `vibrance` | **Master** | Look: Saturation/Vibrance | — |
| Look | `equalizer` | **Look（D9 占位组）** | Look: Clarity（Equalizer 单滑杆呈现简化 = D9 面板决策） | 「applies pre-DRT for now — moves post-DRT with M2-6」注记行 |
| Look | `sharpen` | **Look（D9 占位组）** | Look: Sharpen | 同上注记行 |
| Look | `grain` | **Look（D9 占位组）** | Look: Film Grain | 同上注记行（M2-6 迁 DRT 后段） |
| Look | `bloom` | **Look（D9 占位组）** | Look: Halation | 同上注记行（同上） |
| Look | `cat02WhiteBalance` | **Color** | Look: White Balance（CAT02 创意 WB，M2GRADE-04；相机 WB = RAW Decode 域，D5） | — |
| Look | `tint` | **Color** | Look: Tint（独立 ±100 标量，T3） | — |
| Look | `velvia` | **Detail/Texture** | —（D6 独有增强） | **Alcedo 无对应**（D6 收纳 Detail/Texture 组） |
| Look | `monochrome` | **Detail/Texture** | —（D6 独有增强） | **Alcedo 无对应**（同上） |
| Look | `colorbalancergb` | **Detail/Texture** | —（D6 独有件；LGG 色轮 = 新 colorWheels 件，随 T4 批挂 Color 组） | **Alcedo 无对应**（同上） |
| Look | `colorzones` | **Detail/Texture** | —（checker m1 裁定归 Detail/Texture；HLS Selective Color = 新 hls 件，随 T5 批挂 Color 组） | **Alcedo 无对应**（同上） |
| Look | `skinSmooth` | **Detail/Texture** | —（D6 独有增强） | **Alcedo 无对应**（同上） |
| Look | `highpass` | **Detail/Texture** | Look: Texture（高频腿） | **Alcedo 无独立对应**（与 soften 同视图双 provider） |
| Look | `soften` | **Detail/Texture** | Look: Texture（柔化腿） | 同上（共用 HighpassSoften 面板视图） |
| Look | `bilat` | **Detail/Texture** | —（局部对比；LocalContrast 面板，opName 沿 dt `bilat` 字面） | **Alcedo 无对应**（D6 收纳 Detail/Texture 组） |
| LUT | `lut3d` | main | LUT 页（递归扫描/根目录选择器 = M2GRADE-05/06 留 M2-5） | — |
| Display Transform | `vignette` | main | DRT/Post（暗角） | — |
| Display Transform | —（占位节） | special | DRT 本体：OpenDRT / ACES 2.0（目标空间/传递函数/峰值亮度，HDR 直出） | 「arrives with M2-6」占位节；**AgX 失挂（E1 勘误）** |
| Geometry | `crop` | main | crop/aspect | — |
| Geometry | `flip` | main | rotate/flip | — |
| Geometry | `lens` | main | 镜头校正 | **Alcedo 无独立面板**（自动 metadata 校正） |
| Geometry | `ashift` | **Advanced** | 透视/旋转 | **Alcedo 无对应**（D6 独有项） |
| Geometry | `liquify` | **Advanced** | 液化 | **Alcedo 无对应**（D6 独有项） |
| Geometry | `channelmixerrgb` | **Advanced** | — | **Alcedo 无对应**（D6 独有项） |
| Geometry | `channelmixer` | **Advanced** | — | **Alcedo 无对应**（D6 独有项，legacy 双胞胎） |
| Geometry | `hazeremoval` | **Advanced** | — | **Alcedo 无对应**（D6 独有项，去雾） |
| RAW Decode | —（T4 CIRAW 面板槽位：NR amount/luminance/chroma/sharpness + decoder version + boost） | special | RAW Decode 页（M2DIS-04 载体） | 面板本体 T4 落（本表行 = 槽位声明） |
| Mask | —（LayersPanelView + MaskToolbar 联动入口） | special | Mask Groups（每 Color Grade 一组） | M2-7 替换前的 M1 adjustment layers 归位 |

## 非页签归页面（恰一次断言域内）

| 归页面 | 面板（opName 字面） | Alcedo 对应物 | Alcedo 无对应标注 |
|---|---|---|---|
| 顶栏 sheet（`shell.topbar.yiyin`） | `watermark` | —（水印是导出域一等公民） | **Alcedo 无对应**（壹印） |
| 顶栏 sheet（同上） | `borders` | —（印框同上） | **Alcedo 无对应**（壹印） |

## 表外特例（断言域外，D4 独有入口登记）

- **`textOverlay`**：yiyin 顶栏 sheet 的文本 overlay 载体（`TextOverlayPanelView` 挂同一
  sheet）；checker m3 口径不入表、不入恰一次断言域。
- **PresetPanelView**：非 registry IOP（App 层预设面板）——七页签**头部全局入口**
  （`editor.stack.preset.entry`，沿 M1 Inspector 底部形态）。
- **McpLauncherPanelView**：现状保持（菜单/窗口入口），不动。
- **ExportPanelView**：现状保持（导出域，M2-9 Alcedo 化另接）。

## 页序（Alcedo `EditorAdjustmentStack.qml:10-16`，== `EditorTabRoute.allCases`）

Tone → Look → LUT → Display Transform → Geometry → RAW Decode → Mask

## M2-5-2 增批注记（2026-09-30，随实态同批）

- **Tone 主面终态 = 六行**（Alcedo Tone 目录）：Exposure / Contrast（新 `contrast` 件）/
  White（新 `white` 件）/ Black（新 `black` 件）/ **Shadows / Highlights（`shadhi` 单行
  双滑杆）** / Curve。T1 批先落 provider 已填充的三行（exposure/tonecurve/shadhi）；
  **contrast/white/black 三行随 T3 provider 批同 commit 挂入**（m3 恰一次断言域 =
  populated provider 面，行与 provider 必须同批到位）。
- **Look 页四组 IA**（M2-5-2 KD-1）：Master / Look（D9 占位组，四 DRT 件带 pre-DRT
  注记）/ Color / Detail/Texture——分组 = 纯呈现投影（`PanelGroup`），行账随 T2 批
  同批更新；新件行（cat02WhiteBalance/hls/colorWheels/tint/saturation）随 T3-T5
  provider 批逐批挂入。
- 组头键族：`panel_group_master` / `panel_group_look` / `panel_group_color` /
  `panel_group_detail_texture` / `editor_stack_compat`（Tone compat 组头，复用
  `isAdvancedGroup` 折叠槽）。
