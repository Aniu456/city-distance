/// 按视口较长边覆盖的投影范围选择展示层级，单位与地图画布一致。
/// 缩小时保留一段当前层级，避免手势在临界值附近反复切换。
int mapDetailDepth({required int previous, required double visibleSpan}) {
  if (visibleSpan <= 100 || (previous == 2 && visibleSpan < 140)) {
    return 2;
  }
  if (visibleSpan <= 360 || (previous >= 1 && visibleSpan < 460)) {
    return 1;
  }
  return 0;
}

/// 新层级随可见范围缩小逐渐显现；数据加载阈值不等于全部可见。
double mapDetailOpacity({required int depth, required double visibleSpan}) {
  final start = depth == 1 ? 360.0 : 100.0;
  final end = depth == 1 ? 180.0 : 50.0;
  final progress = ((start - visibleSpan) / (start - end)).clamp(0.0, 1.0);
  return progress * progress * (3 - 2 * progress);
}
