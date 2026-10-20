import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/city.dart';
import '../models/map_region.dart';
import '../theme/app_colors.dart';
import '../utils/map_detail_level.dart';
import 'label_text_cache.dart';

part 'map_label_layout.dart';

/// 已避让的标签，坐标与地图画布一致。
class MapLabel {
  const MapLabel({
    required this.code,
    required this.text,
    required this.anchor,
    required this.bounds,
    required this.priority,
    required this.color,
    required this.fontSize,
    required this.opacity,
    this.muted = false,
  });

  final String code;
  final String text;
  final Offset anchor;
  final Rect bounds;

  /// 起终点、省会、地级市、区县依次为 0、1、2、3。
  final int priority;
  final Color color;
  final double fontSize;
  final double opacity;

  /// 非聚焦省份的地级市：浅色小字，让聚焦省份更突出。
  final bool muted;
}

/// 省界和城市标签分别绘制，所有层级的文字共享碰撞检测。
class MapPainter extends CustomPainter {
  MapPainter({
    required this.regions,
    required this.provinces,
    required this.scale,
    required this.view,
    this.highlighted = const {},
    this.detailProvinces,
    this.cities = const [],
    this.cityBoundaries = const [],
    this.showCities = false,
    this.showDistricts = false,
    this.origin,
    this.destination,
    this.fontFamily,
    this.parentOf,
    LabelTextCache? textCache,
  }) : textCache = textCache ?? LabelTextCache.shared;

  final List<MapRegion> regions;
  final List<MapRegion> provinces;
  final double scale;
  final Rect view;

  /// 以选中色填充的区域编码；省级编码在市界显现前整省高亮。
  final Set<String> highlighted;

  /// 以完整对比度显示地级市标签和市界的省级编码；其余省份的市级细节淡化显示。
  /// null 表示全部完整显示。
  final Set<String>? detailProvinces;
  final List<City> cities;
  final List<MapRegion> cityBoundaries;
  final bool showCities;
  final bool showDistricts;
  final City? origin;
  final City? destination;
  final String? fontFamily;

  /// 已加载区域的上级编码，用于判断市级边界所属省份。
  final String? Function(String code)? parentOf;

  /// 标签文字排版缓存；默认使用进程内共享缓存。
  final LabelTextCache textCache;

  /// 按本画笔的缩放预先排版区县标签文字（与区县候选标签的样式一致），
  /// 供平移到新地级市前在空闲时调用。
  void prewarmDistrictLabels(Iterable<String> names) {
    for (final name in names) {
      _text(name, 10, 3, AppColors.label, outline: true);
      _text(name, 10, 3, AppColors.label);
    }
  }

  /// 本画笔的标签布局；画笔每帧新建且输入不变，因此只计算一次。
  List<MapLabel>? _labels;

  double get _visibleSpan => math.max(view.width, view.height);

  double get cityOpacity =>
      showCities ? mapDetailOpacity(depth: 1, visibleSpan: _visibleSpan) : 0;
  double get districtOpacity =>
      showDistricts ? mapDetailOpacity(depth: 2, visibleSpan: _visibleSpan) : 0;

  bool _isSelected(City city) =>
      city.code == origin?.code || city.code == destination?.code;

  bool _isDetailed(City city) =>
      detailProvinces?.contains(city.provinceCode) ?? true;

  /// 市级区域是否属于完整显示的省份；所属省份由 [parentOf] 查得，
  /// 台湾等编码不遵循“前两位加 0000”规则的区域也能正确判断。
  bool isDetailedRegion(String code) {
    final provinces = detailProvinces;
    if (provinces == null) {
      return true;
    }
    return provinces.contains(parentOf?.call(code) ?? code);
  }

  late final List<City> _visibleCities = cities
      .where(
        (city) =>
            view.contains(city.point) &&
            (city.isCapital || _isSelected(city) || showCities),
      )
      .toList();

  Color _cityColor(City city) =>
      city.code == origin?.code ? const Color(0xff9b5433) : AppColors.primary;

  /// 地图坐标下排版的标签文字，取自 [textCache]，不得由调用方释放。
  TextPainter _text(
    String value,
    double fontSize,
    int priority,
    Color color, {
    bool outline = false,
  }) => textCache.get(
    text: value,
    fontSize: fontSize,
    scale: scale,
    bold: priority <= 1,
    color: color,
    fontFamily: fontFamily,
    outline: outline,
  );

  /// 实际绘制标记点的城市：省会、起终点和放下了标签的城市，起终点排在最后
  /// 以绘制在最上层。绘制与点击判定共用此结果，未显示的城市不能被点中。
  late final List<City> markers = () {
    final labeled = layoutLabels().map((label) => label.code).toSet();
    return _visibleCities
        .where(
          (city) =>
              city.isCapital ||
              _isSelected(city) ||
              labeled.contains(city.code),
        )
        .toList()
      ..sort(
        (a, b) => (_isSelected(a) ? 1 : 0).compareTo(_isSelected(b) ? 1 : 0),
      );
  }();

  /// 地图坐标 [point] 处可点中的城市：先看已显示的标签文字，再找 [radius]
  /// （地图坐标）内最近的已显示标记点；都没有时返回 null。
  City? cityAt(Offset point, {required double radius}) {
    final byCode = {for (final city in markers) city.code: city};
    for (final label in layoutLabels().reversed) {
      final city = byCode[label.code];
      if (city != null && label.bounds.contains(point)) {
        return city;
      }
    }
    City? nearest;
    var distance = radius;
    for (final city in markers) {
      final candidate = (city.point - point).distance;
      if (candidate < distance) {
        nearest = city;
        distance = candidate;
      }
    }
    return nearest;
  }

  /// 先放置起终点，低优先级文字无法占用它们的位置。
  ///
  /// 结果按画笔缓存：同一画笔多次调用返回同一列表。
  List<MapLabel> layoutLabels() => _labels ??= _layoutLabels();

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint();
    final border = Paint()..style = PaintingStyle.stroke;
    // 底色始终跟随省级区域，切入市县时不整屏换色。
    for (final province in provinces) {
      if (province.bounds.overlaps(view)) {
        final hash = province.code.codeUnits.fold(
          0,
          (value, char) => value * 31 + char,
        );
        fill.color = AppColors
            .regionPalette[hash.abs() % AppColors.regionPalette.length];
        canvas.drawPath(province.path, fill);
        // 聚焦省份在市界显现前整体高亮，随市级细节渐显而淡出，交给所选城市。
        final fade = 1 - cityOpacity;
        if (highlighted.contains(province.code) && fade > 0) {
          fill.color = AppColors.regionSelected.withValues(alpha: fade);
          canvas.drawPath(province.path, fill);
        }
      }
    }
    for (final region in regions) {
      if (highlighted.contains(region.code)) {
        canvas.drawPath(region.path, fill..color = AppColors.regionSelected);
      }
      if (region.level == 'district' && districtOpacity > 0) {
        border
          ..color = AppColors.regionBorder.withValues(
            alpha: districtOpacity * 0.5,
          )
          ..strokeWidth = 0.6 / scale;
        canvas.drawPath(region.path, border);
      }
    }
    if (cityOpacity > 0) {
      border
        ..color = AppColors.regionBorder.withValues(alpha: cityOpacity * 0.65)
        ..strokeWidth = 0.7 / scale;
      final boundaries = cityBoundaries.isEmpty ? regions : cityBoundaries;
      final muted = Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.regionBorder.withValues(alpha: cityOpacity * 0.3)
        ..strokeWidth = 0.5 / scale;
      for (final city in boundaries) {
        if (city.level == 'city' && city.bounds.overlaps(view)) {
          canvas.drawPath(
            city.path,
            isDetailedRegion(city.code) ? border : muted,
          );
        }
      }
    }
    border
      ..color = AppColors.provinceBorder
      ..strokeWidth = 1.1 / scale;
    for (final province in provinces) {
      if (province.bounds.overlaps(view)) {
        canvas.drawPath(province.path, border);
      }
    }
    _drawConnection(canvas);
    final labels = layoutLabels();
    for (final city in markers) {
      final radius =
          (_isSelected(city)
              ? 5
              : city.isCapital
              ? 3
              : 2) /
          scale;
      final label = city.isCapital || _isSelected(city)
          ? null
          : labels.firstWhere((label) => label.code == city.code);
      final opacity = label == null
          ? 1.0
          : label.opacity * (label.muted ? 0.55 : 1);
      canvas.drawCircle(
        city.point,
        radius + 1 / scale,
        Paint()..color = AppColors.background.withValues(alpha: opacity),
      );
      canvas.drawCircle(
        city.point,
        radius,
        Paint()..color = _cityColor(city).withValues(alpha: opacity),
      );
    }
    // 半透明标签按透明度分组，每组只开一个图层：放置后的标签互不重叠，
    // 与逐个标签开图层的效果相同，而真机上逐个 saveLayer 是光栅化的主要开销。
    final groups = <double, List<MapLabel>>{};
    for (final label in labels) {
      final alpha = label.opacity * (label.muted ? 0.8 : 1);
      groups.putIfAbsent(math.min(alpha, 1), () => []).add(label);
    }
    for (final MapEntry(key: alpha, value: group) in groups.entries) {
      if (alpha < 1) {
        canvas.saveLayer(
          group
              .map((label) => _labelLayerBounds(label))
              .reduce((a, b) => a.expandToInclude(b)),
          Paint()..color = Colors.white.withValues(alpha: alpha),
        );
      }
      for (final label in group) {
        if (alpha < 1) {
          // 与原来每个标签的图层范围一致：引线超出部分同样被裁掉。
          canvas
            ..save()
            ..clipRect(_labelLayerBounds(label));
        }
        _paintLabel(canvas, label);
        if (alpha < 1) {
          canvas.restore();
        }
      }
      if (alpha < 1) {
        canvas.restore();
      }
    }
  }

  Rect _labelLayerBounds(MapLabel label) => label.bounds.inflate(4 / scale);

  void _paintLabel(Canvas canvas, MapLabel label) {
    if (!label.bounds.inflate(14 / scale).contains(label.anchor)) {
      canvas.drawLine(
        label.anchor,
        label.bounds.center,
        Paint()
          ..color = AppColors.regionBorder
          ..strokeWidth = 0.7 / scale,
      );
    }
    final outline = _text(
      label.text,
      label.fontSize,
      label.priority,
      label.color,
      outline: true,
    );
    final text = _text(label.text, label.fontSize, label.priority, label.color);
    outline.paint(canvas, label.bounds.topLeft);
    text.paint(canvas, label.bounds.topLeft);
  }

  void _drawConnection(Canvas canvas) {
    final start = origin;
    final end = destination;
    if (start == null || end == null || start.code == end.code) {
      return;
    }
    final path = Path()
      ..moveTo(start.point.dx, start.point.dy)
      ..lineTo(end.point.dx, end.point.dy);
    final paint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / scale;
    for (final metric in path.computeMetrics()) {
      for (var offset = 0.0; offset < metric.length; offset += 12 / scale) {
        canvas.drawPath(metric.extractPath(offset, offset + 7 / scale), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant MapPainter oldDelegate) => true;
}
