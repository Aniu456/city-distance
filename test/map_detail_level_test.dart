import 'package:china_map/utils/map_detail_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('跨省范围保持省会，省域和市域范围才逐级进入', () {
    expect(mapDetailDepth(previous: 0, visibleSpan: 650), 0);
    expect(mapDetailDepth(previous: 0, visibleSpan: 361), 0);
    expect(mapDetailDepth(previous: 0, visibleSpan: 360), 1);
    expect(mapDetailDepth(previous: 1, visibleSpan: 101), 1);
    expect(mapDetailDepth(previous: 1, visibleSpan: 100), 2);
  });

  test('进出阈值分离，临界范围的小幅缩放不会反复跳层', () {
    var depth = 0;
    for (final span in [370.0, 359.0, 363.0, 355.0, 400.0, 459.0]) {
      depth = mapDetailDepth(previous: depth, visibleSpan: span);
    }
    expect(depth, 1);
    expect(mapDetailDepth(previous: depth, visibleSpan: 460), 0);
    depth = mapDetailDepth(previous: 1, visibleSpan: 99);
    for (final span in [101.0, 98.0, 120.0, 139.0]) {
      depth = mapDetailDepth(previous: depth, visibleSpan: span);
      expect(depth, 2);
    }
    expect(mapDetailDepth(previous: depth, visibleSpan: 140), 1);
    expect(mapDetailDepth(previous: 2, visibleSpan: 1000), 0);
  });
  test('市县边界从透明开始渐显，临界值没有整层突变', () {
    for (final settings in [(1, 360.0, 180.0), (2, 100.0, 50.0)]) {
      final (depth, start, end) = settings;
      expect(mapDetailOpacity(depth: depth, visibleSpan: start), 0);
      expect(
        mapDetailOpacity(depth: depth, visibleSpan: start - 1),
        lessThan(0.002),
      );
      expect(
        mapDetailOpacity(depth: depth, visibleSpan: (start + end) / 2),
        closeTo(0.5, 0.001),
      );
      expect(mapDetailOpacity(depth: depth, visibleSpan: end), 1);
    }
  });
}
