# omp summary — gpui 最小复现 lane（refs #27）

日期 2026-11-25 · 开工 HEAD `4285f69e` · 仓外 `/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike/{minimal,upstream}` · 产品树零改动 · 探针 `measure/FrameProbe.swift`（判据 `cells>=1 && maxd>=10` 不变）

## 结论

**最普通的写法下现象不在。** 600×600 窗口、`overflow_y_scroll` 容器、80 行 40 px 普通 div、第 20 行被测控件、`ScrollHandle::set_offset(-600)`、定时器 16 ms × 40 次：纯 div（M1）、canvas（M2）、gpui-kit `Progress`（M3）、`Slider`（M4）全部持续上屏（36–40/40 变化帧），每 tick 应用内都重绘（39–40 次）。偏移 0（C1）与容器外（C2）同样上屏。上游 `gpui 0.2.2` 的 M1/C1 对照同为 37/40。

- 不是 gpui-kit 这套 gpui 的通病。
- 不是上游 Zed 发布的 gpui 的问题。
- 前五轮「框架在滚动子树里抑制非文本绘制」的结论**必须改写**为：现象由原型里多出来的某种结构/写法触发，最小程序不含它。
- 原型的具体触发点**未定位**；最大方法差异 = 原型用合成滚轮滚出偏移，本轮按任务要求用 `set_offset`。

## 数字（40 次更新，偏移 600，除非注明）

| # | 控件 | 变化帧/40 | 每 tick 中位 | p95/max | 应用内重绘 |
|---|---|---|---|---|---|
| M1 | 纯 div 宽度 10→90% | 37 (55.6 fps) | 1.2 ms | 22.2/56.9 | 39 |
| M2 | canvas 矩形 | 36 (54.7) | 12.4 | 31.0/62.2 | 39 |
| M3 | gpui-kit Progress | 40 (60.0) | 9.9 | 98.9/131.2 | 40 |
| M4 | gpui-kit Slider (set_value) | 39 (58.5) | 5.9 | 36.7/69.0 | 39 |
| C1 | M1 @ 偏移 0 | 37 (56.9) | −0.5¹ | 17.0/49.4 | 39 |
| C2 | M1 @ 容器外 | 19 (28.7)² | 15.6 | 37.2/54.1 | 39 |
| U-M1 | 上游 gpui 0.2.2, M1 | 37 (54.9) | −0.4¹ | 16.6/39.2 | 39 |
| U-C1 | 上游 gpui 0.2.2, C1 | 37 (56.9) | −0.4¹ | 16.9/31.9 | 39 |

¹ 判据窗口 −2 ms 容差的近零值；该情形 40/40 tick 均匹配到变化帧，不是丢帧。
² 200 px 宽条每 tick 位移 ~4.6 px，低于探针 80×45 网格 7.5 px 间距；40/40 tick 均匹配到变化帧，19 是不同帧数，不是没上屏。M1/M2 的 36–37 同理（≈55–60 fps，网格阈值抖动）。

证据：`traces/minimal/*.{run,err}`（8 情形）、`shots/minimal/*-mid.png`（8 张，timer 跑到 tick 20 时截图）。时钟对齐：应用用 `mach_absolute_time` 记录，与探针 `CMClockGetHostTimeClock` 实测差 4 µs；全程无合成输入。

## 写法（要点）

- crate `minimal/` 只依赖 `gpui-kit 0.11.0`；照 README 的 `application()/init()/open_window`；源码 320 行，未从原型复制任何控件代码。
- 单实体；`div().id("scroll-root").w(px(400.)).h_full().overflow_y_scroll().track_scroll(&h)`；80 行 40 px；控件在第 20 行。
- 偏移在 200 ms 后 `set_offset(point(0, -600))` + `cx.notify()`；2 s 后 `spawn_in` 定时器 40 次，每次 `update_in` 改值 + `notify`；M4 走 `SliderState::set_value(v, window, cx)`。
- 屏幕无任何随值变化的文字/计数器（只有 stderr 日志），避免污染帧差。
- 不常见写法：① `set_offset` 而非滚轮（任务要求，也是与原型最大差异）；② `mach_absolute_time` 对齐日志与帧；③ C1 控件放第 1 行（偏移 0 时第 20 行在视口外，否则测的是不可见元素）；④ 整窗单实体、无子视图。
- 第三组 `upstream/` 直接依赖 `gpui = "0.2.2"`，代码与 M1/C1 同构，独立 `Cargo.lock`。

## 和原型的差别（嫌疑清单，§3 详版）

1. 偏移由合成滚轮产生 vs `set_offset`（最大方法差异；下一步第一优先测）。
2. 行内交互/hitbox（module header id + mouse handlers；根上还有 on_mouse_move/up/down）。
3. 常驻 TextInput（IME 实体）+ `track_focus`/`on_key_down`。
4. 滚动容器用 `flex_1().min_h(0)` 在 280 px flex 列里（高度由 flex 计算）vs 固定 400×632。
5. 绘制复杂度（canvas 画 track+fill+PathBuilder 三角；div 臂绝对定位叠层；`on_children_prepainted`）。
6. 几何尺度（7 px 条、每 tick 2–3 px、263 px 轨道 vs 22 px/8 px/400 px）。
7. 场景规模（1440×816、30 模块、max 1576 vs 600×632、80 行、max 2600）。
8. overlay 尾巴、render 里读 scroll offset 写 Cell、原生标题栏 vs 自绘顶栏。

## 对 #27 的含义

- 不要把「gpui 滚动子树丢帧」写进选型风险；滑杆/进度条可用普通 div/canvas，不必为躲「框架 bug」改写法。
- 原型回查方向：先试 (a) 合成滚轮滚到 600，(b) 给行加 id+on_mouse_down、根加 on_mouse_move；任一复现即缩范围。
- 审慎：本轮只证明这些普通写法不触发；不证明 gpui 无其它滚动缺陷，也不解释原型「24 次 render / 0 变化帧」的机制。

## 未验

1. 原型具体触发点未定位（嫌疑清单未逐项加回验证）。
2. 滚轮路径未测（本轮按约束禁合成输入）。
3. 每情形单次运行，无重复统计。
4. 探针分辨率对 C2/小位移的限制（已用 tick 匹配补判）。
5. M3/M4 内部 transition/spring 会自行请求动画帧（组件能上屏 ≠ 静态几何，静态几何由 M1/M2 证明）。
6. 只测前台激活窗口；未测失焦/遮挡/多显示器。
7. 上游组只做 M1/C1（任务要求）。

## 产物

- 报告：`.work/gsd/phases/gpui-spike/REPORT-MINIMAL.md`
- 本摘要：`.work/gsd/phases/gpui-spike/omp-gpui-minimal-summary.md`
- 源码副本：`.work/gsd/phases/gpui-spike/minimal-src/{gpui-kit,upstream-gpui}/`
- 轨迹/日志：`.work/gsd/phases/gpui-spike/traces/minimal/`（24 文件）
- 截图：`.work/gsd/phases/gpui-spike/shots/minimal/`（8 张）
- 仓外工作树：`/Volumes/UNITEK/Documents/Development/Lightamer-gpui-spike/{minimal,upstream}`

单 commit，`refs #27`，零 push，产品树零改动。
