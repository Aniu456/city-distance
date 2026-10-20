import 'dart:math' as math;
import 'dart:ui';

/// 地图相机：视口中心对应的画布坐标与缩放倍数。
typedef MapCamera = ({Offset center, double scale});

/// 中心线性插值，缩放按对数插值，使放大和缩小的速度感一致。
MapCamera lerpMapCamera(MapCamera from, MapCamera to, double t) => (
  center: Offset.lerp(from.center, to.center, t)!,
  scale: math.exp(lerpDouble(math.log(from.scale), math.log(to.scale), t)!),
);
