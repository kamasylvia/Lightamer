# 胶片相框（Film Edge）research lane（omp 执行；纯文本零 commit 零构建）

你是「胶片相框」功能 research lane。工作目录 /Volumes/UNITEK/Documents/Development/Lightamer。全程中文。**纯文本：零 git commit、零构建零测试零 GUI**，产物 = 一个 RESEARCH.md，由 orchestrator 收割。

## 功能定义（用户指令）

当前印框/水印功能（yiyin 移植）增**胶片相框**风格——照片以 SpektraLab 式胶片边框呈现：片边排版（胶片品牌/型号文字沿边）、帧号、日期后背（日期+拍摄数据）、可选 DX 条/片孔形态。落位 = yiyin 面板新相框风格（与既有画布边框并列），非整卷画布重构。

## 调研任务

1. **上游测绘**（SpektraLab `git show origin/main:` 读法——本地树 stale；RFC-032/031 = Film Edge + Date Back）：film edge 渲染实现（每 stock 边缘排版/字体/DX 条/片孔/overscan 尺寸表）、date back（日期+拍摄数据版式、120 中幅日期、帧号行）、数据来源（stock 边缘文案从哪来——内置表？）。file 级出处。
2. **我方落点测绘**：yiyin 构成管线（`App/Sources/Lightamer/Yiyin/` 或 LightamerIOP 相应域——印框/水印渲染器结构、画布边框现状、字体排印能力 CoreText）、FilmRecord（stock id 可作边缘文案来源）、EXIF 日期/拍摄数据可得性、导出链挂点。
3. **设计提案**：胶片相框作为 yiyin 新 frame style 的形态（边框区排版/元素开关：品牌行/帧号/日期/DX 条/片孔拟态）、参数面（开关逐元素 + 密度/比例）、数据流（FilmRecord.stock → 边缘文案映射表——28+4 卷内置文案表自建零复制）、渲染路径（CoreText 排版 + Metal/图形合成）。
4. **OQ 清单**：形态/范围/数据/性能逐条带推荐值。

## 产出契约

`.work/gsd/phases/yiyin-filmframe/RESEARCH.md`：上游测绘（file 级）+ 我方落点（file 级）+ 设计提案 + 工作量分级（S/M/L）+ OQ 清单。零 commit。
