import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/city.dart';
import '../models/map_region.dart';
import '../theme/app_colors.dart';
import '../utils/map_detail_level.dart';

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
  });

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

  double get _visibleSpan => math.max(view.width, view.height);

  double get cityOpacity =>
      showCities ? mapDetailOpacity(depth: 1, visibleSpan: _visibleSpan) : 0;
  double get districtOpacity =>
      showDistricts ? mapDetailOpacity(depth: 2, visibleSpan: _visibleSpan) : 0;

  bool _isSelected(City city) =>
      city.code == origin?.code || city.code == destination?.code;

  bool _isDetailed(City city) =>
      detailProvinces?.contains(city.provinceCode) ?? true;

  /// 市级区域是否属于完整显示的省份；省级编码为市级编码前两位加四个 0。
  bool isDetailedRegion(String code) =>
      detailProvinces?.contains('${code.substring(0, 2)}0000') ?? true;

  List<City> get _visibleCities => cities
      .where(
        (city) =>
            view.contains(city.point) &&
            (city.isCapital || _isSelected(city) || showCities),
      )
      .toList();

  Color _cityColor(City city) =>
      city.code == origin?.code ? const Color(0xff9b5433) : AppColors.primary;

  TextPainter _text(
    String value,
    double fontSize,
    int priority,
    Color color, {
    bool outline = false,
  }) => TextPainter(
    text: TextSpan(
      text: value,
      style: TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize / scale,
        fontWeight: priority <= 1 ? FontWeight.w600 : FontWeight.w400,
        color: outline ? null : color,
        foreground: outline
            ? (Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3 / scale
                ..strokeJoin = StrokeJoin.round
                ..color = AppColors.background.withValues(alpha: 0.85))
            : null,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  /// 先放置起终点，低优先级文字无法占用它们的位置。
  List<MapLabel> layoutLabels() {
    final candidates =
        <
          ({
            String code,
            String text,
            Offset anchor,
            int priority,
            Color color,
            double fontSize,
            bool muted,
          })
        >[];
    final visible = _visibleCities;
    for (final city in visible) {
      final selected = _isSelected(city);
      final muted = !selected && !city.isCapital && !_isDetailed(city);
      final prefix = city.code == origin?.code
          ? (city.code == destination?.code ? '起终 ' : '起 ')
          : city.code == destination?.code
          ? '终 '
          : '';
      candidates.add((
        code: city.code,
        text: '$prefix${city.name}',
        anchor: city.point,
        priority: selected
            ? 0
            : city.isCapital
            ? 1
            : 2,
        color: selected
            ? _cityColor(city)
            : muted
            ? AppColors.hintText
            : AppColors.label,
        fontSize: selected
            ? 12
            : city.isCapital
            ? 11
            : muted
            ? 9
            : 10,
        muted: muted,
      ));
    }
    final cityCodes = cities.map((city) => city.code).toSet();
    if (showDistricts) {
      for (final region in regions) {
        if (region.level == 'district' &&
            region.name.isNotEmpty &&
            view.contains(region.label) &&
            !cityCodes.contains(region.code)) {
          candidates.add((
            code: region.code,
            text: region.name,
            anchor: region.label,
            priority: 3,
            color: AppColors.label,
            fontSize: 10,
            muted: false,
          ));
        }
      }
    }
    candidates.sort((a, b) {
      // 同一层级先放聚焦省份的城市，淡化的邻省城市只填空位。
      var order = a.priority.compareTo(b.priority);
      if (order == 0) {
        order = (a.muted ? 1 : 0).compareTo(b.muted ? 1 : 0);
      }
      return order == 0 ? a.code.compareTo(b.code) : order;
    });
    final safeView = view.deflate(6 / scale);
    final labels = <MapLabel>[];
    // 只有淡化的邻省城市和区县受屏幕面积预算约束；聚焦省份的城市全部参与，
    // 仅在屏幕上真正重叠时才被舍弃。
    final labelBudget =
        ((view.width * scale * view.height * scale) /
                (showDistricts ? 10000 : 9000))
            .floor()
            .clamp(6, 80);
    final selectedMarkers = visible
        .where(_isSelected)
        .map(
          (city) => (
            code: city.code,
            bounds: Rect.fromCircle(center: city.point, radius: 7 / scale),
          ),
        )
        .toList();
    for (final candidate in candidates) {
      var opacity = 1.0;
      if (candidate.priority >= 2) {
        // 透明度只随缩放层级渐显，不再按与邻近标签的距离淡出（之前上饶因此成了残影）。
        opacity = candidate.priority == 2 ? cityOpacity : districtOpacity;
        final budgeted = candidate.muted || candidate.priority == 3;
        if (opacity < 0.05 ||
            (budgeted &&
                labels.where((label) => label.priority != 0).length >=
                    labelBudget)) {
          continue;
        }
      }
      final text = _text(
        candidate.text,
        candidate.fontSize,
        candidate.priority,
        candidate.color,
      );
      final gap = 8 / scale;
      final anchor = candidate.anchor;
      final positions = <Offset>[
        Offset(anchor.dx + gap, anchor.dy - text.height / 2),
        Offset(anchor.dx - gap - text.width, anchor.dy - text.height / 2),
        Offset(anchor.dx - text.width / 2, anchor.dy + gap),
        Offset(anchor.dx - text.width / 2, anchor.dy - gap - text.height),
        if (candidate.priority == 0)
          for (var step = 1; step <= 5; step++)
            for (final direction in [-1, 1])
              Offset(
                anchor.dx - text.width / 2,
                anchor.dy +
                    direction * step * (text.height + gap) -
                    text.height / 2,
              ),
      ];
      final selectedArea = safeView.deflate(3 / scale);
      for (var position in positions) {
        if (candidate.priority == 0 &&
            text.width <= selectedArea.width &&
            text.height <= selectedArea.height) {
          position = Offset(
            position.dx.clamp(
              selectedArea.left,
              selectedArea.right - text.width,
            ),
            position.dy.clamp(
              selectedArea.top,
              selectedArea.bottom - text.height,
            ),
          );
        }
        final bounds = position & text.size;
        // 屏幕空间内的固定留白，与缩放层级无关。
        final padding = candidate.priority >= 2 ? 3.0 : 2.0;
        final padded = bounds.inflate(padding / scale);
        if (!safeView.contains(padded.topLeft) ||
            !safeView.contains(padded.bottomRight) ||
            labels.any(
              (label) => label.bounds.inflate(3 / scale).overlaps(padded),
            ) ||
            selectedMarkers.any(
              (marker) =>
                  marker.code != candidate.code &&
                  marker.bounds.overlaps(padded),
            )) {
          continue;
        }
        labels.add(
          MapLabel(
            code: candidate.code,
            text: candidate.text,
            anchor: anchor,
            bounds: bounds,
            priority: candidate.priority,
            color: candidate.color,
            fontSize: candidate.fontSize,
            opacity: opacity,
            muted: candidate.muted,
          ),
        );
        break;
      }
      text.dispose();
    }
    return labels;
  }

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
    final labeledCodes = labels.map((label) => label.code).toSet();
    final visible =
        _visibleCities
            .where(
              (city) =>
                  city.isCapital ||
                  _isSelected(city) ||
                  labeledCodes.contains(city.code),
            )
            .toList()
          ..sort(
            (a, b) =>
                (_isSelected(a) ? 1 : 0).compareTo(_isSelected(b) ? 1 : 0),
          );
    for (final city in visible) {
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
    for (final label in labels) {
      final alpha = label.opacity * (label.muted ? 0.8 : 1);
      if (alpha < 1) {
        canvas.saveLayer(
          label.bounds.inflate(4 / scale),
          Paint()..color = Colors.white.withValues(alpha: alpha),
        );
      }
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
      final text = _text(
        label.text,
        label.fontSize,
        label.priority,
        label.color,
      );
      outline.paint(canvas, label.bounds.topLeft);
      text.paint(canvas, label.bounds.topLeft);
      outline.dispose();
      text.dispose();
      if (alpha < 1) {
        canvas.restore();
      }
    }
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
