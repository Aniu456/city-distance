import 'dart:math' as math;
import 'dart:ui';

/// 当前聚焦的行政区编码路径，从省级到被选区域，例如 `['610000', '610100']`。
///
/// 只有路径上的上级和被选区域内部允许展开到下一级，其余区域保持粗粒度，
/// 放大后不会把视野内所有省份的市县一起铺开。
class MapFocus {
  const MapFocus(this.path);

  /// 不能为空。
  final List<String> path;

  String get code => path.last;
  String get provinceCode => path.first;

  /// [code] 是否为被选区域或其内部区域；[parentOf] 返回已加载区域的上级编码。
  bool contains(String code, String? Function(String code) parentOf) {
    String? current = code;
    // 行政层级最多四级，限制步数防止数据异常造成死循环。
    for (var step = 0; current != null && step < 8; step++) {
      if (current == this.code) {
        return true;
      }
      current = parentOf(current);
    }
    return false;
  }

  /// 区域可以展开到下一级并参与高亮：位于聚焦路径上，或在被选区域内部。
  bool includes(String code, String? Function(String code) parentOf) =>
      path.contains(code) || contains(code, parentOf);
}

/// 聚焦时按钮缩放的新中心，坐标与地图画布一致。
///
/// 进度按对数缩放从全国视图 [fitScale] 到恰好容纳被选区域的 [focusScale]
/// 计算。放大时中心逐步移向 [focus]，缩小时逐步回到全国中心 [national]。
Offset focusZoomCenter({
  required Offset current,
  required Offset focus,
  required Offset national,
  required double scale,
  required double fitScale,
  required double focusScale,
  required bool zoomingIn,
}) {
  var progress = 1.0;
  if (focusScale > fitScale * 1.0001) {
    progress = (math.log(scale / fitScale) / math.log(focusScale / fitScale))
        .clamp(0.0, 1.0);
  }
  return zoomingIn
      ? Offset.lerp(current, focus, progress)!
      : Offset.lerp(current, national, 1 - progress)!;
}
