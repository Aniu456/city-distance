import 'dart:convert';
import 'dart:ui';

import '../models/map_region.dart';
import '../utils/map_projection.dart';

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('地图数据对象格式不正确');
  }
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List<Object?>) {
    throw const FormatException('地图坐标数组格式不正确');
  }
  return value;
}

Offset _point(Object? value) {
  final pair = _list(value);
  if (pair.length < 2 || pair[0] is! num || pair[1] is! num) {
    throw const FormatException('地图坐标格式不正确');
  }
  final longitude = (pair[0] as num).toDouble();
  final latitude = (pair[1] as num).toDouble();
  if (!longitude.isFinite || !latitude.isFinite || latitude.abs() >= 90) {
    throw const FormatException('地图坐标超出范围');
  }
  return project(longitude, latitude);
}

/// 在资源输入边界解析 GeoJSON，支持岛屿、多面及内环。
List<MapRegion> parseRegions(String source) {
  final collection = _object(jsonDecode(source));
  if (collection['type'] != 'FeatureCollection') {
    throw const FormatException('地图不是 FeatureCollection');
  }
  return _list(collection['features'])
      .map((raw) {
        final feature = _object(raw);
        final properties = _object(feature['properties']);
        final geometry = _object(feature['geometry']);
        final coordinates = _list(geometry['coordinates']);
        final polygons = switch (geometry['type']) {
          'Polygon' => <Object?>[coordinates],
          'MultiPolygon' => coordinates,
          _ => throw const FormatException('不支持的地图几何类型'),
        };
        final path = Path()..fillType = PathFillType.evenOdd;
        for (final polygon in polygons) {
          for (final ring in _list(polygon)) {
            final points = _list(ring).map(_point).toList();
            if (points.length < 4) {
              throw const FormatException('地图边界点数量不足');
            }
            path.addPolygon(points, true);
          }
        }
        final code = properties['adcode'];
        final name = properties['name'];
        if ((code is! int && code is! String) || name is! String) {
          throw const FormatException('地图缺少区域编码或名称');
        }
        final center = properties['centroid'] ?? properties['center'];
        return MapRegion(
          code: code.toString(),
          name: name,
          level: properties['level'] as String? ?? 'decoration',
          hasChildren: (properties['childrenNum'] as num? ?? 0) > 0,
          path: path,
          label: center == null ? path.getBounds().center : _point(center),
        );
      })
      .toList(growable: false);
}
