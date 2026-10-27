# M9-2 GUI 走查配方（BW 族 + 滤色镜 + granularity）

> 实机走查归验收批（SC 措辞与 M7-6 先例同款登记）。本配方 = 验收面清单;
> 全部走查以一张彩色 RAW/JPEG 打开为底,Inspector → Film 页为入口。

## 前置

- 构建产物 = 本批 HEAD;项目内含 Resources/FilmProfilesBW(双目录 store)。
- 打开任意一张图,Inspector 切 Film Simulation 页,点 enable entry 进入
  session 控制区。

## 1. BW stock 分节选择（D-M92-7）

- Film picker 下拉:顶部平铺彩色卷(Portra 等),底部「黑白」分节头下
  四卷:TRI-X 400 / T-MAX 100 / NEOPAN ACROS II / HP5 PLUS。
- Paper picker:「黑白」分节头下 MULTIGRADE IV RC。
- 选 Tri-X × Multigrade → 预览变黑白负转正观感;分节头不可被选中
  （tag 为 section 占位）。

## 2. Grade 切换（T2 主面）

- 绑定 Multigrade 后 Grade 行出现:None (auto) + 00/0/1/2/3/4/5 八项。
- 切 5 → 观感反差明显变硬(密度跨度变宽);切 00 → 变软;None → 回
  自动 solve。切换首挂构建(秒级),二次切换即时(缓存命中)。
- undo(⌘Z)逐档回退,history 面板每档一条「相纸反差号」。
- 18% 灰区在 grade 2 档观感密度中性带(0.55-0.95 机检面的人眼旁证)。

## 3. SHOOT 滤色镜（T3,D-M92-6）

- session 控制区出现「拍摄」节:说明 caption + Filter picker(None +
  w8/w11/w12/w15/w21/w25/w47/w58)。
- 切 w25(红)→ 预览中蓝天区明显压暗(方向断言的观感面);w47(蓝)→
  红色区压暗;None → 回无滤镜。
- 与下方 Yellow/Magenta 二色性滑杆区分:SHOOT 节在材料/grade 之后、
  Y/M 滑杆之前,节头 caption 明示「作用于胶片感光」。
- w58 档出现数据注记行(B-3 vs W2 分歧 note)。

## 4. granularity readout（T4）

- 选 Tri-X(或 T-MAX/ACROS)为 film → 材料区出现「发表 RMS 17 µm ·
  推荐 strength N」行 + 「应用」按钮。
- 点应用 → Effects 的 grain strength 变为推荐值(history 一条
  「Grain」);grain 面板滑杆同步。
- 选 HP5 → readout 行消失(Harman 无发表值,诚实 null)。

## 5. 色卷回归（零漂移旁证）

- 切回 Portra × Endura(grade 行隐藏、SHOOT 节仍在——滤镜对色卷
  合法),Grade 区不出现(非 BW 相纸)。
- 全程无 grade/无 filter 档观感与本批前逐字节一致(机检哨兵
  filmRampPlaneHash/spectralRampPlaneHash 的观感旁证)。
