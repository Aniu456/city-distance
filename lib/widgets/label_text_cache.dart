import 'package:flutter/painting.dart';

import '../theme/app_colors.dart';

typedef _LabelKey = ({
  String text,
  double fontSize,
  double scale,
  bool bold,
  int color,
  String? fontFamily,
  bool outline,
});

/// 地图标签的文字排版缓存。
///
/// 画笔每帧新建，但平移时缩放不变、文字相同，排版结果可以直接复用。
/// 排版仍在地图坐标下进行（字号与描边宽度除以 [scale]），与不缓存时
/// 逐像素一致；缩放变化的帧会生成新条目，旧条目按最近最少使用淘汰。
class LabelTextCache {
  /// 默认容量覆盖城市层级下视野内全部城市的两种样式（各含描边版本）。
  LabelTextCache({this.capacity = 1024});

  /// 进程内共享的缓存，供每帧新建的地图画笔复用。
  static final shared = LabelTextCache();

  /// 最多保留的排版数量；淘汰时释放对应的 [TextPainter]。
  final int capacity;

  // LinkedHashMap 按插入顺序迭代；命中时重新插入，即按最近使用排序。
  final _entries = <_LabelKey, TextPainter>{};

  int get length => _entries.length;

  /// 累计未命中（新建排版）的次数，供基准和测试观察。
  int misses = 0;

  /// 返回已排版的文字。[fontSize] 为屏幕逻辑像素，[scale] 为地图当前缩放；
  /// [outline] 为 true 时返回用于描边的版本。
  TextPainter get({
    required String text,
    required double fontSize,
    required double scale,
    required bool bold,
    required Color color,
    String? fontFamily,
    bool outline = false,
  }) {
    final key = (
      text: text,
      fontSize: fontSize,
      scale: scale,
      bold: bold,
      color: color.toARGB32(),
      fontFamily: fontFamily,
      outline: outline,
    );
    final hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit;
      return hit;
    }
    misses++;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize / scale,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
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
    _entries[key] = painter;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first)!.dispose();
    }
    return painter;
  }

  /// 释放全部排版。
  void clear() {
    for (final painter in _entries.values) {
      painter.dispose();
    }
    _entries.clear();
  }
}
