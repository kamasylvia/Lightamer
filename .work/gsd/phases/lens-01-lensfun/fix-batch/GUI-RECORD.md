# 修复批 GUI 记录(2026-10-20)

- 构建产物实机启动一次:DerivedData Debug 容器 `Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi`
  (build-for-testing 产品,含本批全部修复),直启 PID 49304。
- 启动面 = ProjectWorkspaceFace(「尚未打开项目。」)正常;RSS 416MB / CPU 0.1%
  空闲态(远低于 3G 介入线);截图 = `gui-launch.png`(视口,已缩)。
- guard 偏差申报(D-L4-4 同形):G3 swap 5.1G = 前序定向轮冷页残留(G2 83% 过、
  零并发重活;本活动 = 单 app 启动+截图,轻于 guard 门标的构建/测试重活)。
- 交互面(开文档/browser 选型)本环境点击全惰(M3-3-03 三路对照 + M7-1 AX 限制
  先例)——W13/W13b/W14 渲染观感行留人工真机走查(MANIFEST 修复批补录节);
  行为级等价面已机检绿:LensParityTests process-gate golden(选型即校正)+
  miss 恒等面 + LensProjectionGoldenTests 往返恒等/equidistant 真值两法。
- 进程清理:kill 自出 PID 49304,零残留。
