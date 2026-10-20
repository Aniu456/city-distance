# 中国地图 · Flutter

只实现地图展示：全国省级边界 → 放大显示市级边界 → 继续放大显示区县边界。

## 使用

```sh
flutter pub get
flutter run -d chrome  # Web，也可以选择其他已配置的设备
```

已生成 Android、iOS、Web、macOS、Windows、Linux 工程。使用纯 Flutter
CustomPainter 和 InteractiveViewer，不依赖某一个平台的原生地图 SDK，也不需要地图 Key。
原生平台运行仍需对应系统的 Flutter 开发环境；本次未做六个平台的构建或真机验收。

- 拖动移动地图；鼠标滚轮、触控板、双指手势或右下角按钮缩放。
- 相对全国视图达到 3 倍显示市级，10 倍显示区县级；缩小自动恢复上级。
- 点击行政区放大定位；“全国”回到初始视图。
- 直辖市、港澳等按数据的真实层级直接展示区县。东莞、中山等无县级子区划的城市保留市界，不虚构下级。
- 标签做碰撞避让，继续放大可查看密集区域地名。
- 边界资源随项目打包，运行时不请求地图服务器。Web 首次访问仍需加载应用及资源。

## 数据

资源位于 `assets/maps/`，约 29 MB，按当前视口和层级懒加载并缓存。
包含 34 个省级区域、385 个市级展示单元、3208 个区县/乡镇展示单元及南海边界附加几何；
这些是数据文件的展示单元数量，不应作为最新法定行政区数量。

1. 主数据：[阿里云 DataV GeoAtlas](https://datav.aliyun.com/portal/school/atlas/area_selector)，
   `https://geo.datav.aliyun.com/areas_v3/bound/{adcode}_full.json`，下载日期 2026-10-19。
   保留原始坐标、名称、层级和边界；下载时间不代表行政区划更新时间。
2. DataV 没有提供台湾下级边界，因此以
   [taiwan-atlas](https://github.com/dkaoster/taiwan-atlas) 的 `towns-10t.json`
   补充 22 个县市、368 个乡镇市区。补充文件使用 `tw_` 编码命名空间及源数据名称，
   按“县市 → 乡镇市区”显示；相关许可证见 `assets/maps/taiwan-atlas-LICENSE.txt`。
   两个来源独立，边界精度、坐标基准与更新时间不保证完全一致，沿海及离岛接缝尚未逐一校准。

这是一份固定数据快照。后续正式发布前应确认数据使用授权、地图版本及适用的地图展示要求；
仓库不把第三方边界数据重新授权为本项目代码。

刷新主数据（默认复用已有文件；更新时先备份并移除拟更新资源）：

```sh
python3 tool/fetch_maps.py
curl -fL https://cdn.jsdelivr.net/npm/taiwan-atlas/towns-10t.json -o /tmp/towns-10t.json
python3 tool/import_taiwan.py /tmp/towns-10t.json
```

## 源码与检查

- `lib/map_data.dart`：GeoJSON 输入校验、墨卡托投影、资源缓存。
- `lib/map_page.dart`：视口、缩放分层、点击定位、地图绘制与标签避让。
- `test/map_data_test.dart`：全量边界解析、下级资源完整性、代表性省市县链路。
- `test/widget_test.dart`：缩放层级切换、复位、窄屏与横屏布局。

```sh
flutter analyze
flutter test
```
