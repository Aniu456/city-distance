import 'dart:convert';
import 'dart:typed_data';
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

/// 一块区域解码后的纯数据：投影后的环坐标按 x, y 交替存放。
///
/// 不含 [Path] 等引擎对象，可以在后台 isolate 中生成后传回 UI 线程。
typedef RegionShape = ({
  String code,
  String name,
  String level,
  bool hasChildren,
  List<Float64List> rings,
  Offset? label,
});

/// 在资源输入边界解析 GeoJSON，支持岛屿、多面及内环。
List<MapRegion> parseRegions(String source) =>
    buildRegions(decodeRegions(source));

/// 解码并投影 GeoJSON，不创建路径；耗时的 JSON 解析和投影都在这里，
/// 可通过 `compute` 放到后台 isolate 执行。
List<RegionShape> decodeRegions(String source) {
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
        final rings = <Float64List>[];
        for (final polygon in polygons) {
          for (final ring in _list(polygon)) {
            final points = _list(ring);
            if (points.length < 4) {
              throw const FormatException('地图边界点数量不足');
            }
            final values = Float64List(points.length * 2);
            for (final (index, raw) in points.indexed) {
              final point = _point(raw);
              values[index * 2] = point.dx;
              values[index * 2 + 1] = point.dy;
            }
            rings.add(values);
          }
        }
        final code = properties['adcode'];
        final name = properties['name'];
        if ((code is! int && code is! String) || name is! String) {
          throw const FormatException('地图缺少区域编码或名称');
        }
        final center = properties['centroid'] ?? properties['center'];
        return (
          code: code.toString(),
          name: name,
          level: properties['level'] as String? ?? 'decoration',
          hasChildren: (properties['childrenNum'] as num? ?? 0) > 0,
          rings: rings,
          label: center == null ? null : _point(center),
        );
      })
      .toList(growable: false);
}

/// 由解码结果创建路径，须在 UI 线程执行；无标注点时取边界中心。
List<MapRegion> buildRegions(List<RegionShape> shapes) => [
  for (final shape in shapes)
    () {
      final path = Path()..fillType = PathFillType.evenOdd;
      for (final ring in shape.rings) {
        path.addPolygon([
          for (var i = 0; i < ring.length; i += 2) Offset(ring[i], ring[i + 1]),
        ], true);
      }
      return MapRegion(
        code: shape.code,
        name: shape.name,
        level: shape.level,
        hasChildren: shape.hasChildren,
        path: path,
        label: shape.label ?? path.getBounds().center,
      );
    }(),
];
