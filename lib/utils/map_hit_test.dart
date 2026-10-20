import 'dart:ui';

import '../models/map_region.dart';

/// 返回包含 [point] 的最上层具名区域；[regions] 按绘制顺序排列，后绘制者在上。
MapRegion? regionAt(List<MapRegion> regions, Offset point) {
  for (final region in regions.reversed) {
    if (region.name.isNotEmpty &&
        region.bounds.contains(point) &&
        region.path.contains(point)) {
      return region;
    }
  }
  return null;
}
