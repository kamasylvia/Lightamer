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
| Tone | `temperature` | main | Tone: CAT02 White Balance（M2-5 前温度面板 = 现 M1 语义） | — |
| Tone | `tonecurve` | main | Tone: Curve | — |
| Tone | `levels` | main | Tone: White/Black（levels 自动模式） | — |
| Tone | `colisa` | main | Tone: Contrast（+brightness/saturation 合一面） | Alcedo 拆分三滑杆，M1 为单面板 |
| Tone | `shadhi` | main | Tone: Shadows / Highlights | — |
| Tone | `colorcontrast` | main | Tone: Contrast（辅助） | Alcedo 无独立对应物 |
| Tone | `toneequal` | main | —（OQ-4 草案漏列，动态集完备性补入本页） | **Alcedo 无对应**（dt tone equalizer） |
| Look | `vibrance` | main | Look: Saturation/Vibrance | — |
| Look | `velvia` | main | Look: Vibrance 增强 | **Alcedo 无对应**（D6 独有增强） |
| Look | `monochrome` | main | Look: Selective Color/Mono | **Alcedo 无对应**（D6 独有增强） |
| Look | `colorbalancergb` | main | Look: LGG 色轮（M2-5 前 ColorBalanceRGB 暂驻） | — |
| Look | `colorzones` | main | Look: Selective Color（L/C/h 三轴） | — |
| Look | `skinSmooth` | main | Look: Detail/Texture 辅助 | **Alcedo 无对应**（D6 独有增强） |
| Look | `sharpen` | main | Look: Detail | — |
| Look | `highpass` | main | Look: Texture（高频腿） | **Alcedo 无独立对应**（与 soften 同视图双 provider） |
| Look | `soften` | main | Look: Texture（柔化腿） | 同上（共用 HighpassSoften 面板视图） |
| Look | `bilat` | main | Look: Detail（局部对比） | **Alcedo 无对应**（LocalContrast 面板；opName 沿 dt `bilat` 字面） |
| Look | `equalizer` | main | Look: Detail（多频带） | **Alcedo 无对应** |
| Look | `grain` | main | DRT 后 Post: FilmGrain（M2-6 前暂驻 Look，OQ-4 DT 行注记） | 暂驻语义（M2-6 迁 DRT 后段） |
| Look | `bloom` | main | DRT 后 Post: Halation（M2-6 前暂驻 Look，同上） | 暂驻语义（同上） |
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
