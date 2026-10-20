import 'dart:ui';

/// 一块行政区的几何边界；children 表示数据源确实提供下一级。
class MapRegion {
  MapRegion({
    required this.code,
    required this.name,
    required this.level,
    required this.hasChildren,
    required this.path,
    required this.label,
  }) : bounds = path.getBounds();

  final String code;
  final String name;
  final String level;
  final bool hasChildren;
  final Path path;
  final Rect bounds;
  final Offset label;
}
