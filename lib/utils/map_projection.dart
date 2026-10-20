import 'dart:math' as math;
import 'dart:ui';

/// 固定墨卡托投影画布，保留南海岛屿的实际地理位置。
const mapSize = Size(1280, 1300);

Offset project(double longitude, double latitude) {
  final radians = latitude * math.pi / 180;
  final mercator = math.log(math.tan(math.pi / 4 + radians / 2));
  return Offset((longitude - 72) * 20, (66 - mercator * 180 / math.pi) * 20);
}
