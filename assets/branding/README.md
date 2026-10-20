# 城向 · 品牌资源

- 名称：城向。仅改显示名称，保留 Dart 包名、各平台包名和 Bundle ID。
- 主题色：松石绿 `#287565`；折面色 `#A6CBBE`；界面底色 `#F7F9F8`。
- `app_icon.png`：1024 × 1024、不透明方形母版。系统负责应用图标遮罩。
- 图案：用户确认的折叠地图与东北向箭头。
- 生成：内置 image_gen，根据本会话中已确认的蓝色原始图标仅调整配色。

## 生成提示词

Edit this exact app icon, ONLY recoloring it. Preserve the white folded map + northeast arrow geometry, orientation, proportions and shape exactly. Replace the entire royal blue background with flat solid pine jade green #287565, and replace the light-blue center fold plane with flat light sage #A6CBBE. White main planes remain pure white. The output is the FINAL production icon master, a single square 1024x1024 image. Full bleed green background all the way to all four square corners, NO baked-in rounded corners, no border, no labels, no lettering, no mockup, no surrounding white canvas, no shadow, no gradient, no texture, no other changes. Keep the symbol within the central 62% safe zone, same centered original composition.

## 导出

在 macOS 项目根目录执行：`python3 tool/generate_app_icons.py`。
使用系统 sips 只转换尺寸，再以原 PNG 数据封装多尺寸 Windows ICO。
覆盖 Android、iOS、macOS、Web、Windows 与 Linux 的图标资源。
Linux bundle 的图标安装到 `data/app_icon.png`，运行时从可执行文件所在目录读取。
Linux 桌面菜单集成及 Wayland Dock 图标仍取决于发行包的 desktop entry 安装方式。

平台资源尺寸和引用检查不代表已经在各平台完成安装及桌面图标验收。
