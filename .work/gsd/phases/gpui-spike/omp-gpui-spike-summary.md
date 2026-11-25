# gpui-kit + gpui 复刻 darktable — 交付摘要（omp lane）

## 结论

**能复刻。** 页面 **达成**（高置信）；交互 **部分达成**（中）；手感 **达成**（中，dt 三项未测得）。
页面差距 = 无直方图、图标字符化、白平衡图标行占位；交互差距 = 模块头键盘可达、dt 5.6.2 的搜索行为与下拉不可搜索；手感差距 = 无可测差距（原型 60 fps vs dt 19.3 fps 拖动）。

## 手感数字（同一工具、同一动作、1440×816、60 Hz）

| 指标 | darktable 5.6.2 | 原型 |
|---|---|---|
| 滑杆拖动更新率 | 19.3 fps（中位 51.7 ms，p95 65.4，>33.3 ms 3 帧） | 59.7 / 60.0 fps（中位 16.76/16.67，p95 34.1/34.8，>33.3 ms 3/4 帧） |
| 拖动按下 → 首帧变化 | 95.5 ms（扣 54.3 ms 工具地板 ≈ 41 ms） | 50.4 / 54.1 ms（≈ 0 ms） |
| 模块列表滚动（480 ms 连续） | 未测得（合成滚轮不滚动 GTK 列表） | 62.3 fps，中位 16.5 ms，p95 18.9，>25 ms 0 帧 |
| 展开/折叠 | 87.4 ms（≈ 33 ms） | 50.4 / 50.6 ms（≈ 0） |
| 右键菜单可见 | 82.7 ms（整屏抓帧） | 56.6 ms（单窗抓帧，≈ 2 ms） |
| 方向键切图 | 未测得（隔离库 1 张，无 CLI 导入） | 首帧 65.6 / 44.2 ms；稳定 215 / 394 ms |

工具自检：应用内 16.67 ms/帧；探针 16.60–16.66 ms；点击→闪烁 2.9 ms（动画窗）/ 54.3 ms（静止窗地板），应用内 0.4 ms。

## 成本

- 原型 `main.rs` 1601 行（自绘控件 ~900 行：滑杆、组合框、模块 chrome、右键菜单、历史、视口）。
- 测量工具 `FrameProbe.swift` 494 行 + 自检 101 + axdump/imesel/compose 133。
- 首次编译 300.6 s，`target/` 3.2 GB，峰值 RSS 3.43 GB；增量 40–210 s。
- gpui-kit 现成：窗口/Root/主题、`Input`（IME 正常）、滚动容器、AccessKit 接线、Metal。

## 卡点

1. **Enter 不作为按键事件到达 `on_key_down`**；只有 `KeyBinding` + action 能收到（`main()` 的 `cx.bind_keys`），导致输入框 Enter 也要走 action 分派。
2. **弹层必须 `.occlude()`**；`deferred()` 只影响绘制，点击会穿透到下面的滑杆（实测一次点击改了三处状态）。
3. **合成双击必须带 `mouseEventClickState`**（1/2），否则 gpui 不算双击。
4. gpui-kit 的 styled `Slider` 与 dt 控件形状不同（thumb/spring vs 填充条+三角），数学可复用但外观/命中/右键需重写。
5. AX 逐元素显式声明：不加 `.role()` 就零节点（首版只有 2 个输入框；加 role 后 46 节点）。
6. 合成滚轮能改 dt 滑杆但滚不动 dt 的模块列表（相位/行单位/滚动条拖动都失败）。

## Commit

Commit: `HEAD`（`git log -1` 即本提交）— `feat(spike): gpui-kit + gpui darktable interaction replication`（refs #27，body Refs #24），只含 `.work/gsd/phases/gpui-spike/`。

## 未验项

- dt 的滚动/切图/搜索计时；dt 的多图库（无 CLI 导入）。
- 可拖拽分栏/停靠（`h_resizable`）未接；模块头 Tab 焦点未做。
- 像素管线未验证（视口是 JPEG + 亮度覆盖）。
- 单机、单 60 Hz 面板、单样张；Linux/Windows 后端未验。
- gpui-kit crates.io license 字段为空（README 写 Apache-2.0），正式采用前需核实。
