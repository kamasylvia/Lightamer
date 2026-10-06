# M2-11-02 T6 — Instruments 归档注记（2026-10-07 夜间执行 worker）

- 机器：Mac mini（Laniakea的Mac mini），macOS 27.0.1 (26A434)，Instruments 27.0 (27A266a)。
- 驱动通道：computer-use SDK 本执行面不可用（"Computer Use is not available in subagent"，
  SDK 主 agent 专属——M2-3 方法学授权面在本 subagent 环境被平台策略拒绝）；回退
  osascript System Events AX 驱动（AX 点击/按钮/表单实测可达；深树 AXSlider 遍历超时，
  滑块驱动 = 轨道 click-at 序列）。
- 场景①（编辑会话，m2-11-edit-session.trace，Time Profiler 模板 60s，launch 起测）：
  `-la_editor_probe` 自动化缝 = 建项目 → import 100MP RAF → 打开编辑器 → 渲染上屏，
  全程在 trace 窗口内；trace 中段经 AX 关闭两张模态表单（Welcome/AI 分析确认）。
  potential-hangs 表（≥250ms hang）= **0 行**；os-signpost 表 0 行（Deferred 模式未捕获
  应用自绘 signpost 通道）。
- 场景① hitch 面附加（m2-11-hitch-edit.trace，Animation Hitches 模板 35s，attach 附着于
  同一会话，窗口内 AX 驱动色温滑块轨道 click-at ×8）：hitch 总 498 帧**全部 = 单帧
  16.67ms**（"Potentially expensive app update(s)"），**>50ms 帧间隙 = 0**（分析正本 =
  hitch-edit-session-summary.txt + hitches-export-edit-session.xml，脚本 = hitch-analysis.py）。
- 场景②（万张图库滚动）：10k fixture（/tmp/m2-11-perf/scrollsession，256² JPEG ×10000）
  已备，但滚动驱动通道缺失（LazyVGrid AX scrollbar 不可设值 + 无 computer-use）→
  **Manual-Only**（perf.md hitch 表登记）。
- 滑块拖动/缩放/平移 hitch 行：拖动（色温轨道 click-at）= 上行 0 >50ms；缩放/平移 =
  Manual-Only。
- trace 体积：edit-session 33MB / hitch-edit 432MB（Animation Hitches 模板含 Metal/显示全表）。
