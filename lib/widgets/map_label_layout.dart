part of 'map_painter.dart';

/// 标签候选的收集、排序与碰撞放置；结果由 [MapPainter.layoutLabels] 缓存，
/// 绘制和点击判定共用。
extension _LabelLayout on MapPainter {
  /// 标签与锚点的屏幕间距，逻辑像素。
  static const _labelGap = 8.0;

  /// 地级市及以下标签之间的屏幕留白，逻辑像素。
  static const _detailLabelPadding = 3.0;

  /// 省会和起终点标签之间的屏幕留白，逻辑像素。
  static const _primaryLabelPadding = 2.0;

  /// 标签距视口边缘的最小屏幕距离，逻辑像素。
  static const _viewInset = 6.0;

  /// 每个淡化标签或区县标签平均占用的屏幕面积，平方逻辑像素。
  static const _cityLabelArea = 9000.0;
  static const _districtLabelArea = 10000.0;

  List<MapLabel> _layoutLabels() {
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
      if (!selected && !city.isCapital) {
        _prewarm(city.name, muted: !muted);
      }
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
    final safeView = view.deflate(_viewInset / scale);
    final labels = <MapLabel>[];
    // 只有淡化的邻省城市和区县受屏幕面积预算约束；聚焦省份的城市全部参与，
    // 仅在屏幕上真正重叠时才被舍弃。
    final labelBudget =
        ((view.width * scale * view.height * scale) /
                (showDistricts ? _districtLabelArea : _cityLabelArea))
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
      final gap = _labelGap / scale;
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
        final padding = candidate.priority >= 2
            ? _detailLabelPadding
            : _primaryLabelPadding;
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
    }
    return labels;
  }

  /// 预先排版普通城市另一种样式（淡化或完整）的文字。
  ///
  /// 平移跨省时聚焦切换，两省城市同时改变样式；若此时才排版，几十个标签
  /// 挤在同一帧里造成卡顿。城市进入视野时顺带排好另一种样式，切换帧只命中缓存。
  void _prewarm(String name, {required bool muted}) {
    final color = muted ? AppColors.hintText : AppColors.label;
    final fontSize = muted ? 9.0 : 10.0;
    _text(name, fontSize, 2, color, outline: true);
    _text(name, fontSize, 2, color);
  }
}
