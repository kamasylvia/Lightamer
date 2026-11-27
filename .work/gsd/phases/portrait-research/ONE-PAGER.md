# Portrait Research One-Pager（2026-11-27）

结论：两仓均已最新（Alcedo f4d36474 v0.3.7 / Lumen f520192 v2.3.2，
各 0 新提交）。近两月人像交付：Alcedo 仅 0.3.4 AI 蒙版四任务
（整人级，无脸部部件）；Lumen 仅 2.3.0「人像」面板 7 项修饰
（磨皮/美白/祛痘/去黑眼圈/白牙/大眼/瘦脸，MIT 纯算法）。
虚化/背景替换/眼神光/人脸感知曝光两家皆无；身体部位细分维持不做。

现在就收（6 lane / 18 h，新波 PORTRAIT，B14A 之后，零新权重）：
1. P1 七修饰算法转写（4 lane）：Lumen portrait.py:511-786，MIT。
2. P2 皮肤掩膜算法（1 lane）：椭圆+脖子−五官×自学肤色−镜框。
3. P3 配方存关键点+分块精确语义（0 lane）：设计约束，含 P1 接线内。
4. 面板/命令面（1 lane）：mask.generate 扩展或新命令 + A3 面板描述。
顺带零 lane：P5 柔和人像预设、P6 vibrance 肤色保护、
P7 per-person toggles UX 注记、P8 权重分发许可纪律。

待用户定（4 件，各带推荐）：
1. 开 PORTRAIT 波吗（6/18h）？推荐开；不开则退 C 期。
2. P4 YuNet+FaceMesh 权重暂不收？推荐暂不收（Vision 零权重覆盖；
   YuNet 权重仓内无单独文本/上游未核+数据无声明；P2 对照不够再收，+2 lane）。
3. P5+P6 顺带收？推荐收（零 lane，oracle 各一例）。
4. P7+P8 进 B14A 注记？推荐收（B14A 15/45 不动）。

估算合计：现在就收 6 lane / 18 h；暂不收 P4（2/6h 备选）。
风险：全本机零外发；零新增权重；Vision 76 点 vs 478 点差距由 P2
对照实测回答；P9（Alcedo S3OD/自训/SAM2.1）与 P10（虚化/眼神光/
感知曝光/身体部位）不收，理由见 PORTRAIT.md §5。
