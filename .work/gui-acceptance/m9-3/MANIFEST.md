# M9-3 gui-acceptance MANIFEST — 走查配方（execute/validate 道消费）

> 本批交付面（T1-T4）的实机走查六项 + 两项实测转办。AXPress 纪律
> （AX id 顺路浮出已随控件在位：`crop.handle.rotation` /
> `crop.straighten.slider` / `crop.rotate.cw|ccw` / `crop.auto.straighten` /
> `crop.constrain` / `upright.mode.picker` / `upright.guides.readout` /
> `upright.guides.clear` / `upright.tool.toggle` / `upright.tool.done` /
> `upright.guides.overlay`）。parentage 纪律：清进程先核 `ps -o ppid`
> （测试宿主 parent = 脚本树；GUI 实例 parent = launchd）。

## 样张

用户实拍 RAW 库（隐私红线：只读本机走查，永不入 git/外发）：
- 建筑/多主体 → `/Volumes/UNITEK/Cloud Drive/QSync/Medias/Photos/Workspace`
  的「摄影会/展会」目录（keystone 竖线场景）。
- 地平线 → 「扫街」目录（海/地平线拉直）。

## 走查项

① **crop 角度手柄联动**（T3）：crop 工具 → 拖 `crop.handle.rotation`
   （框顶圆点绕框心）→ 直显旋转（无 scrim，live）→ 松手单 commit →
   框随角重算（最大框随角缩放）→ undo×2 复原（先框后角 LIFO）。
   **边界样张**：手调小框 + 拖大角度（>30°）→ 松手后框绕自身中心收缩保
   aspect（#1794 中段），无黑边悬空。
② **拉直滑杆 + auto straighten**（T3）：`crop.straighten.slider` 拖动
   （±45，D-H1 三段）→ 松手联动批；`crop.auto.straighten` 于带纹地平线
   样张 → −4° 档自动入角；单线样张 → toast 明说（`crop_auto_none_toast`）。
③ **90° 步进**（T3）：`crop.rotate.cw|ccw` 各点一次 → 图像视觉顺/逆时针
   转 90°；重开 sidecar 位保持；换 EXIF 不翻转（显式位持久）。
④ **Guided 导线**（T4）：upright 面板（Geometry 页 upright 行）→
   `upright.mode.picker` 切 Guided → `upright.tool.toggle` 进入画线 →
   画两条竖导线（沿会聚建筑线）→ keystone 恢复（直显 live）→ 松手单
   item → 拖已有线端点（近端跟随远端不动）→ 点线选中（白/加粗）→
   Delete 删选中 → 空白点清选中 → 第 5 条拒（画不出去）→ `upright.tool.done`
   退出。
⑤ **Constrain Crop**（T3）：upright/拉直后黑边样张 → `crop.constrain` →
   黑边收缩（before/after 截图）→ aspect 不变；已贴合时 toast
   （`crop_constrain_none_toast`）。
⑥ **双 warp 提示 note**（R-3）：upright guides 非空 + ashift.rotation ≠ 0
   → 面板橙色 note 出现；rotation 回 0 → note 消失。
⑦ **检测源对比实测**（R-5 转办）：同一建筑 RAW 分别以 decoded 裸探针
   （现役）与 lens 校正后帧（followEdgesSurface 截断栈形）跑 auto
   straighten → 对比角度差 → DECISIONS 回填选型。
⑧ **live hitch 实测**（D-M9G-5 转办）：导线端点拖动期观察 preview 帧率
   （>50ms hitch 计数）→ DECISIONS 回填（越门则启用回落② disabled+scrim）。

## 验收口径

走查面以我方语义断言（mapper 唯一通道 / off byte-exact / 谓词不动框），
不照抄 upstream UX 细节。每项留 before/after 截图于本目录（`m9-3/`）。
