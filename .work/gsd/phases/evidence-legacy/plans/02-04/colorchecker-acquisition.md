# ColorChecker ARW 采集记录（02-04 遗留 → 2026-10-26 网上寻获，标定完毕）

## 结果

`ColorChecker.ARW`（117MB，Sony ILCE-7RM4，9504×6336 传感器帧，EXIF orientation 6
不应用——纹理 = 传感器帧）已落 `~/Library/Application Support/Lightamer/TestRAW/`
（Fixtures 首选腿）。灰补丁坐标已标定（见下），待修正批 executor 收工后激活
Fixtures.swift 坐标表（激活开关 = `colorCheckerGrayPatches` 非空；文件先在位安全，
空表持续 skip）。

## 来源与许可

- 来源链 = photo.stackexchange.com/questions/117345（「How to use X-Rite
  ColorChecker with Sony a7R IV?」公开求助贴）附件 Google Drive
  `1H3Fke4QMcin1BqLSSWniGdGl3CV5G1oQ`（zip：image.ARW 117M + image.DNG 60M +
  自制 DCP）。
- 拍摄：2020-06，室外日光，ColorChecker Passport（2019 Edition）置于米色坐垫上；
  24 补丁面板在画面左侧（传感器帧内旋转 90° CW：中性行呈左列、白上黑下）。
- **许可状态：源帖未附显式许可（非 CC0）**——公开求助贴共享样本，用途 = 本仓
  untracked 本地测试供件（与既有样张政策同源：永不入 git、永不分发）。与 02-04
  Task 06 原定「release CC0」的偏差如实登记；若日后觅得 CC0 色卡 RAW 可无成本
  换装（坐标重标即可）。raw.pixls.us 明确不收色卡照（Fixtures.swift:147 注记），
  2026-09-19 sweep 无 CC0 源，2026-10-26 二轮 sweep（StackExchange API + Drive
  直链）寻获本件。

## 标定值（归一化坐标，传感器帧 9504×6336，x=475.5px 恒列心）

| 补丁 | y 中心 (px) | 归一化 (x, y) | 采样实测 RGB（sips 导出 JPEG，参考非门值） |
|---|---|---|---|
| N9.5 white | 1781.5 | (0.05003, 0.28117) | 249/249/251 |
| N8.0 | 1946.5 | (0.05003, 0.30721) | 235/236/240 |
| N6.5 | 2109 | (0.05003, 0.33286) | 212/213/217 |
| N5.0 | 2275 | (0.05003, 0.35906) | 167/168/173 |
| N3.5 | 2444 | (0.05003, 0.38573) | ~111 平坦带中心 |
| N2.0 black | 2622 | (0.05003, 0.41383) | ~53 平坦带中心 |

标定方法 = 分隔暗线中点（上四补丁）+ 平坦带剖面（N3.5/N2）+ 六点十字标记视觉
复验（正中）；列心 x 恒定（列左沿 384 恒定，右沿侵蚀为阈值伪象）。中间件 =
`/tmp/cc-full.jpg`（即弃）。

## 风险与验金预期

- 日光外景 + sips 预览渲染显示补丁轻微偏蓝（N5 档 B+9）——中性门 |R−G|,|G−B|
  < 2/255 走的是我方管线（相机 WB 元数据 + temperature 源），sips 渲染偏色不
  预测门值；若门红则为真实发现（该样张色偏/管线中性处理），按红即停分类纪律走。
- 交叉一致性门（pipe vs ColorSync 逐像素）与本张丰富场景（蓝天/木栅/植物/织物）
  = 高判别力组合。
